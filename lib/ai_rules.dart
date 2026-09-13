import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'retry_helper.dart';
import 'connectivity_check.dart';
import 'ai_scan.dart'
    show
        CropRegion,
        CroppedImage,
        cropToRegion,
        clusterFindings,
        regionForCluster,
        mapBoxFromCropToFull,
        parseSeverity,
        scaleCoord,
        mergeOverlappingFindings,
        RoughFinding,
        RetryCallback;

bool _isRetryableAiError(Object error) {
  final msg = error.toString();
  return msg.contains('experiencing high demand') ||
      msg.contains("Could not read the AI's response");
}

class AiRulesService {
  static const String _base = 'https://ridgeboticsapp.onrender.com';

  static const Map<String, String> _manualAssetPaths = {
    '2026': 'assets/rules/frc_2026_manual.pdf',
    '2025': 'assets/rules/frc_2025_manual.pdf',
    '2024': 'assets/rules/frc_2024_manual.pdf',
  };

  static Future<List<Finding>> analyzeImage(
    Uint8List imageBytes,
    String year, {
    int maxAttempts = 3,
    RetryCallback? onRetry,
  }) async {
    if (!ConnectivityCheck.isOnline) {
      throw Exception('offline');
    }

    final manualPath = _manualAssetPaths[year];
    if (manualPath == null) {
      throw Exception('No game manual available for $year');
    }

    final manualData = await rootBundle.load(manualPath);
    final base64Manual = base64Encode(manualData.buffer.asUint8List(
      manualData.offsetInBytes,
      manualData.lengthInBytes,
    ));

    final roughFindings = await withBackoffRetry<List<RoughFinding>>(
      () => _detectOnce(imageBytes, base64Manual, year),
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

  static Future<List<RoughFinding>> _detectOnce(
    Uint8List imageBytes,
    String base64Manual,
    String year,
  ) async {
    final base64Image = base64Encode(imageBytes);

    final body = {
      'contents': [
        {
          'parts': [
            {'text': _detectPromptText(year)},
            {
              'inline_data': {
                'mime_type': 'application/pdf',
                'data': base64Manual,
              }
            },
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
        .timeout(const Duration(seconds: 60));

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

  static String _detectPromptText(String year) =>
      'You are helping a FRC (FIRST Robotics Competition) team do a quick '
      'pre-inspection check against the attached $year FRC game manual. '
      'Use ONLY that manual as the source of truth because rules change '
      'each season. Your job is to point out things worth double checking '
      'against the rulebook, not to give a final ruling on legality. Do '
      'not say a robot is compliant, and do not say a robot is in '
      'violation, only that something looks worth a closer look. The '
      'photo may have a lot of plain background around the robot, so look '
      'carefully at where the robot itself actually is.\n\n'
      'Only check things that can actually be judged from a static photo: '
      'bumper presence, bumper color and numbering, bumper height and '
      'coverage as visible, and whether the visible outline of the robot '
      'appears to exceed the frame perimeter. Do not attempt to judge '
      'wiring correctness, breaker sizing, component legality, or any '
      'rule that depends on internal specifications, mechanism range of '
      'motion, or parts that are partially hidden. If a rule cannot be '
      'judged from what is visible in this single photo, do not comment '
      'on it.\n\n'
      'Cite the specific rule number when the manual supports it. For each '
      'thing you flag, give its approximate center point ON THE ROBOT '
      'ITSELF (not the background) as "point":[y,x], each 0-1000, '
      'relative to the full photo, using Gemini\'s standard point format. '
      'Give each finding a short, specific title.\n\n'
      'Return an empty findings list ONLY if the image is clear enough to '
      'check the items above and nothing looks worth a closer look. If '
      'the image is too dark, blurry, obstructed, or too distant to check '
      'bumpers or frame perimeter, return one item titled "Photo quality '
      'prevents rule check" with point [500,500] rather than an empty '
      'list. Respond only with JSON in this exact format:\n\n'
      '{"findings":[{"title":"short specific issue name","description":'
      '"one or two sentence explanation of what to double check, cite '
      'rule number if applicable","severity":"critical|warning|ok",'
      '"point":[500,500]}]}\n\n'
      'If nothing looks worth checking, return {"findings":[]}.';

  static String _localizePromptText(String titleList) =>
      'You are looking at a zoomed-in crop of a larger robot photo. A '
      'previous pass identified these possible items to double check as '
      'being somewhere in this crop:\n\n$titleList\n\n'
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
      'If none of the listed items are visible in this crop, return '
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

  static List<Finding> _dedupeFindings(List<Finding> findings) {
    final seenTitles = <String>{};
    final byTitle = <Finding>[];
    for (final f in findings) {
      final key = f.title.trim().toLowerCase();
      if (seenTitles.add(key)) byTitle.add(f);
    }
    return mergeOverlappingFindings(byTitle);
  }
}