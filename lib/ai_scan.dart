import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import 'constants.dart';
import 'retry_helper.dart';
import 'connectivity_check.dart';

class CropRegion {
  final double x;
  final double y;
  final double width;
  final double height;

  const CropRegion({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });
}

class CroppedImage {
  final String base64Jpeg;
  final CropRegion region;

  const CroppedImage({required this.base64Jpeg, required this.region});
}

CroppedImage cropToRegion(Uint8List originalBytes, CropRegion region) {
  final decoded = img.decodeImage(originalBytes);
  if (decoded == null) {
    return CroppedImage(
      base64Jpeg: base64Encode(originalBytes),
      region: const CropRegion(x: 0.0, y: 0.0, width: 1.0, height: 1.0),
    );
  }

  final cropX = (region.x * decoded.width).round().clamp(0, decoded.width - 1);
  final cropY =
      (region.y * decoded.height).round().clamp(0, decoded.height - 1);
  final cropW =
      (region.width * decoded.width).round().clamp(1, decoded.width - cropX);
  final cropH = (region.height * decoded.height)
      .round()
      .clamp(1, decoded.height - cropY);

  final cropped = img.copyCrop(
    decoded,
    x: cropX,
    y: cropY,
    width: cropW,
    height: cropH,
  );

  final jpegBytes = img.encodeJpg(cropped, quality: 85);

  return CroppedImage(
    base64Jpeg: base64Encode(jpegBytes),
    region: region,
  );
}

BoundingBox? mapBoxFromCropToFull(
  List<dynamic>? box2dInCrop,
  CropRegion region,
) {
  if (box2dInCrop == null || box2dInCrop.length != 4) return null;

  final cropBox = BoundingBox.fromBox2D(box2dInCrop);

  return BoundingBox(
    x: region.x + cropBox.x * region.width,
    y: region.y + cropBox.y * region.height,
    width: cropBox.width * region.width,
    height: cropBox.height * region.height,
  );
}

typedef RetryCallback = void Function(
    int attempt, int maxAttempts, Duration nextDelay);

class RoughFinding {
  final String title;
  final String description;
  final ScanStatus severity;
  final double centerX;
  final double centerY;

  RoughFinding({
    required this.title,
    required this.description,
    required this.severity,
    required this.centerX,
    required this.centerY,
  });
}

double scaleCoord(dynamic v) {
  if (v == null) return 0.5;
  final n = (v as num).toDouble();
  return (n / 1000.0).clamp(0.0, 1.0);
}

const int maxLocalizeClusters = 4;
const double clusterDistanceThreshold = 0.35;
const double clusterPadding = 0.12;

List<List<RoughFinding>> clusterFindings(
  List<RoughFinding> findings, {
  double threshold = clusterDistanceThreshold,
  int maxClusters = maxLocalizeClusters,
}) {
  final clusters = <List<RoughFinding>>[];

  for (final f in findings) {
    List<RoughFinding>? bestCluster;
    var bestDistSq = double.infinity;

    for (final cluster in clusters) {
      final avgX =
          cluster.map((c) => c.centerX).reduce((a, b) => a + b) / cluster.length;
      final avgY =
          cluster.map((c) => c.centerY).reduce((a, b) => a + b) / cluster.length;
      final dx = f.centerX - avgX;
      final dy = f.centerY - avgY;
      final distSq = dx * dx + dy * dy;
      if (distSq < bestDistSq) {
        bestDistSq = distSq;
        bestCluster = cluster;
      }
    }

    final withinThreshold = bestDistSq < threshold * threshold;
    final atCapacity = clusters.length >= maxClusters;

    if (bestCluster != null && (withinThreshold || atCapacity)) {
      bestCluster.add(f);
    } else {
      clusters.add([f]);
    }
  }

  return clusters;
}

CropRegion regionForCluster(
  List<RoughFinding> cluster, {
  double padding = clusterPadding,
}) {
  final minX = cluster.map((f) => f.centerX).reduce(min);
  final maxX = cluster.map((f) => f.centerX).reduce(max);
  final minY = cluster.map((f) => f.centerY).reduce(min);
  final maxY = cluster.map((f) => f.centerY).reduce(max);

  var width = (maxX - minX) + padding * 2;
  var height = (maxY - minY) + padding * 2;
  width = width.clamp(0.3, 1.0);
  height = height.clamp(0.3, 1.0);

  var x = minX - padding;
  var y = minY - padding;
  x = x.clamp(0.0, 1.0 - width);
  y = y.clamp(0.0, 1.0 - height);

  return CropRegion(x: x, y: y, width: width, height: height);
}

bool _isRetryableAiError(Object error) {
  final msg = error.toString();
  return msg.contains('experiencing high demand') ||
      msg.contains("Could not read the AI's response");
}

class AiService {
  static const String _base = 'https://ridgeboticsapp.onrender.com';

  static Future<void> reportFinding({
    required String scanId,
    required String findingId,
    required Finding finding,
    required String errorType,
    required String scanMode,
    String userComment = '',
  }) async {
    final response = await http
        .post(
          Uri.parse('$_base/reportFinding'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'scanId': scanId,
            'findingId': findingId,
            'scanMode': scanMode,
            'errorType': errorType,
            'title': finding.title,
            'description': finding.description,
            'severity': finding.severity.name,
            'userComment': userComment,
          }),
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode >= 200 && response.statusCode < 300) return;

    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(data['error']?.toString() ?? 'Could not submit report');
    } catch (error) {
      if (error is Exception) rethrow;
      throw Exception('Could not submit report');
    }
  }

  static Future<List<Finding>> analyzeImage(
    Uint8List imageBytes, {
    int maxAttempts = 3,
    RetryCallback? onRetry,
  }) async {
    if (!ConnectivityCheck.isOnline) {
      throw Exception('offline');
    }

    final roughFindings = await withBackoffRetry<List<RoughFinding>>(
      () => _detectOnce(imageBytes),
      maxAttempts: maxAttempts,
      initialDelay: const Duration(seconds: 3),
      isRetryable: _isRetryableAiError,
      onRetry: onRetry,
    );

    if (roughFindings.isEmpty) return [];

    final clusters = clusterFindings(roughFindings);
    final located = <Finding>[];

    for (final cluster in clusters) {
      final region = regionForCluster(cluster);
      final crop = cropToRegion(imageBytes, region);

      final boxesByTitle = await withBackoffRetry<Map<String, List<dynamic>?>>(
        () => _localizeOnce(crop, cluster),
        maxAttempts: maxAttempts,
        initialDelay: const Duration(seconds: 3),
        isRetryable: _isRetryableAiError,
        onRetry: onRetry,
      );

      for (final f in cluster) {
        final key = f.title.trim().toLowerCase();
        final box2d = boxesByTitle[key];
        located.add(Finding(
          title: f.title,
          description: f.description,
          severity: f.severity,
          box: mapBoxFromCropToFull(box2d, region),
          isReported: false,
        ));
      }
    }

    return _dedupeFindings(located);
  }

  static Future<List<RoughFinding>> _detectOnce(Uint8List imageBytes) async {
    final base64Image = base64Encode(imageBytes);

    final body = {
      'contents': [
        {
          'parts': [
            {'text': _detectPromptText},
            {
              'inline_data': {
                'mime_type': 'image/jpeg',
                'data': base64Image,
              }
            },
          ]
        }
      ],
      'generationConfig': {
        'temperature': 0,
        'maxOutputTokens': 2000,
        'responseMimeType': 'application/json',
      },
    };

    final response = await http
        .post(
          Uri.parse('$_base/analyzeImage'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 45));

    final data = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 200) {
      final errMsg = data['error']?.toString() ?? 'Unknown error';
      if (_looksLikeQuotaError(errMsg)) {
        throw Exception('experiencing high demand');
      }
      throw Exception(errMsg);
    }

    final rawText = _extractText(data);
    if (rawText == null || rawText.isEmpty) {
      throw Exception('experiencing high demand');
    }

    try {
      final parsed = jsonDecode(rawText) as Map<String, dynamic>;
      final findingsJson = parsed['findings'] as List<dynamic>? ?? [];
      return findingsJson.map((f) {
        final map = f as Map<String, dynamic>;
        final point = map['point'] as List<dynamic>?;
        final centerY = point != null && point.length == 2 ? scaleCoord(point[0]) : 0.5;
        final centerX = point != null && point.length == 2 ? scaleCoord(point[1]) : 0.5;
        return RoughFinding(
          title: map['title'] as String? ?? 'Issue found',
          description: map['description'] as String? ?? '',
          severity: parseSeverity(map['severity']),
          centerX: centerX,
          centerY: centerY,
        );
      }).toList();
    } catch (e) {
      throw Exception("Could not read the AI's response, please try again.");
    }
  }

  static Future<Map<String, List<dynamic>?>> _localizeOnce(
    CroppedImage crop,
    List<RoughFinding> cluster,
  ) async {
    final titleList =
        cluster.map((f) => '- "${f.title}": ${f.description}').join('\n');

    final body = {
      'contents': [
        {
          'parts': [
            {'text': _localizePromptText(titleList)},
            {
              'inline_data': {
                'mime_type': 'image/jpeg',
                'data': crop.base64Jpeg,
              }
            },
          ]
        }
      ],
      'generationConfig': {
        'temperature': 0,
        'maxOutputTokens': 800,
        'responseMimeType': 'application/json',
      },
    };

    final response = await http
        .post(
          Uri.parse('$_base/analyzeImage'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 40));

    final data = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode != 200) {
      final errMsg = data['error']?.toString() ?? 'Unknown error';
      if (_looksLikeQuotaError(errMsg)) {
        throw Exception('experiencing high demand');
      }
      throw Exception(errMsg);
    }

    final rawText = _extractText(data);
    if (rawText == null || rawText.isEmpty) {
      throw Exception('experiencing high demand');
    }

    try {
      final parsed = jsonDecode(rawText) as Map<String, dynamic>;
      final boxesJson = parsed['boxes'] as List<dynamic>? ?? [];
      final result = <String, List<dynamic>?>{};
      for (final b in boxesJson) {
        final map = b as Map<String, dynamic>;
        final title = (map['title'] as String? ?? '').trim().toLowerCase();
        if (title.isEmpty) continue;
        result[title] = map['box_2d'] as List<dynamic>?;
      }
      return result;
    } catch (e) {
      throw Exception("Could not read the AI's response, please try again.");
    }
  }

  static const String _detectPromptText =
      'You are helping a FRC (FIRST Robotics Competition) team do a quick '
      'visual check of their robot before a real inspection. Your job is to '
      'point out things worth a closer look, not to give a final verdict on '
      'safety or compliance. The photo may have a lot of plain background '
      'around the robot, so look carefully at where the robot itself '
      'actually is.\n\n'
      'Look for things like exposed conductors or damaged insulation, '
      'loose or unsecured wiring, loose connectors, unprotected battery '
      'terminals, loose or missing fasteners, cracked or bent frame '
      'members, corrosion, loose or misaligned belts or chains, sharp '
      'edges, and parts that look like they could fail in a match. Do not '
      'invent defects: ordinary screws, mounting holes, zip ties, and '
      'normal wires are not problems by themselves.\n\n'
      'Never identify what a button, light, or switch does. Do not label '
      'anything as an emergency stop, e-stop, safety light, or any other '
      'safety-critical control, even if it looks like one. If you notice a '
      'button, light, or switch that looks worth checking, describe only '
      'what you see physically (for example, "unlabeled red button near the '
      'battery") and let the team confirm its actual function themselves.\n\n'
      'Only flag something if you can actually see it clearly enough to '
      'describe specifically. If you are not confident something is an '
      'issue, phrase it as something to double check rather than a '
      'confirmed problem.\n\n'
      'For each thing you flag, give its approximate center point ON THE '
      'ROBOT ITSELF (not the background) as "point":[y,x], each 0-1000, '
      'relative to the full photo, using Gemini\'s standard point format. '
      'Give each finding a short, specific title.\n\n'
      'Return an empty findings list ONLY when the photo is clear enough '
      'to inspect and you see nothing worth a closer look. If the image is '
      'too dark, blurry, obstructed, or too distant for a meaningful '
      'check, return one item titled "Photo quality prevents inspection" '
      'with point [500,500] instead of returning an empty list. Respond '
      'only with JSON in this exact format:\n\n'
      '{"findings":[{"title":"short specific issue name","description":'
      '"one or two sentence explanation of what to look at and why",'
      '"severity":"critical|warning|ok","point":[500,500]}]}\n\n'
      'If nothing stands out, return {"findings":[]}.';

  static String _localizePromptText(String titleList) =>
      'You are looking at a zoomed-in crop of a larger robot photo. A '
      'previous pass identified these possible issues as being somewhere '
      'in this crop:\n\n$titleList\n\n'
      'For each one, look carefully in THIS crop and, if you can actually '
      'see it, give its exact bounding box within this crop. If you cannot '
      'find a specific one of these in this crop, leave it out entirely, '
      'do not guess a box for it. Do not add any new issues that were not '
      'in the list above.\n\n'
      'For box_2d, use Gemini\'s standard format: [ymin, xmin, ymax, xmax], '
      'each 0–1000, relative to THIS CROP. Match each box back to its exact '
      'title from the list above. Respond only with JSON in this exact '
      'format:\n\n'
      '{"boxes":[{"title":"short specific issue name","box_2d":'
      '[0,0,0,0]}]}\n\n'
      'If none of the listed issues are visible in this crop, return '
      '{"boxes":[]}.';

  static bool _looksLikeQuotaError(String msg) {
    final lower = msg.toLowerCase();
    return lower.contains('quota') ||
        lower.contains('429') ||
        lower.contains('rate limit') ||
        lower.contains('resource_exhausted');
  }

  static String? _extractText(Map<String, dynamic> data) {
    try {
      final candidates = data['candidates'] as List<dynamic>?;
      final text = candidates?[0]['content']['parts'][0]['text'] as String?;
      return text?.replaceAll('```json', '').replaceAll('```', '').trim();
    } catch (e) {
      return null;
    }
  }
}

ScanStatus parseSeverity(dynamic value) {
  final s = (value as String? ?? '').toLowerCase();
  if (s.contains('critical') || s == 'high') return ScanStatus.critical;
  if (s.contains('warn') || s == 'medium') return ScanStatus.warning;
  return ScanStatus.ok;
}

int severityRank(ScanStatus s) {
  switch (s) {
    case ScanStatus.critical:
      return 2;
    case ScanStatus.warning:
      return 1;
    case ScanStatus.ok:
      return 0;
  }
}

double boxOverlapRatio(BoundingBox? a, BoundingBox? b) {
  if (a == null || b == null) return 0.0;

  final interLeft = a.x > b.x ? a.x : b.x;
  final interTop = a.y > b.y ? a.y : b.y;
  final interRight =
      (a.x + a.width) < (b.x + b.width) ? (a.x + a.width) : (b.x + b.width);
  final interBottom = (a.y + a.height) < (b.y + b.height)
      ? (a.y + a.height)
      : (b.y + b.height);

  final interWidth = interRight - interLeft;
  final interHeight = interBottom - interTop;
  if (interWidth <= 0 || interHeight <= 0) return 0.0;

  final interArea = interWidth * interHeight;
  final aArea = a.width * a.height;
  final bArea = b.width * b.height;
  final unionArea = aArea + bArea - interArea;
  if (unionArea <= 0) return 0.0;

  return interArea / unionArea;
}

List<Finding> mergeOverlappingFindings(
  List<Finding> findings, {
  double overlapThreshold = 0.3,
}) {
  final used = List<bool>.filled(findings.length, false);
  final merged = <Finding>[];

  for (var i = 0; i < findings.length; i++) {
    if (used[i]) continue;
    used[i] = true;
    var best = findings[i];

    for (var j = i + 1; j < findings.length; j++) {
      if (used[j]) continue;
      if (boxOverlapRatio(best.box, findings[j].box) >= overlapThreshold) {
        used[j] = true;
        if (severityRank(findings[j].severity) > severityRank(best.severity)) {
          best = findings[j];
        }
      }
    }

    merged.add(best);
  }

  return merged;
}

List<Finding> _dedupeFindings(List<Finding> findings) {
  final seenTitles = <String>{};
  final byTitle = <Finding>[];
  for (final f in findings) {
    final key = f.title.trim().toLowerCase();
    if (seenTitles.add(key)) byTitle.add(f);
  }
  return mergeOverlappingFindings(byTitle);
}