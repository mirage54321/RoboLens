import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'retry_helper.dart';
import 'connectivity_check.dart';
import 'ai_scan.dart'
    show
        gridRegionNames,
        CropRegion,
        CroppedImage,
        cropToRegion,
        findingFromRegionJson,
        RetryCallback;

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

    final crops = {
      for (final name in gridRegionNames)
        name: cropToRegion(imageBytes, CropRegion.fromRegionName(name)),
    };

    return withBackoffRetry<List<Finding>>(
      () => _analyzeOnce(crops, base64Manual, year),
      maxAttempts: maxAttempts,
      initialDelay: const Duration(seconds: 3),
      isRetryable: isHighDemandError,
      onRetry: onRetry,
    );
  }

  static Future<List<Finding>> _analyzeOnce(
    Map<String, CroppedImage> crops,
    String base64Manual,
    String year,
  ) async {
    final parts = <Map<String, dynamic>>[
      {'text': _promptText(year)},
      {
        'inline_data': {
          'mime_type': 'application/pdf',
          'data': base64Manual,
        }
      },
    ];
    for (final name in gridRegionNames) {
      parts.add({'text': 'Region: $name'});
      parts.add({
        'inline_data': {
          'mime_type': 'image/jpeg',
          'data': crops[name]!.base64Jpeg,
        }
      });
    }

    final body = {
      'contents': [
        {'parts': parts}
      ],
      'generationConfig': {
        'temperature': 0,
        'maxOutputTokens': 3000,
        'responseMimeType': 'application/json',
      },
    };

    final response = await http
        .post(
          Uri.parse('$_base/analyzeImage'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 75));

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
      return _dedupeFindings(
        findingsJson
            .map((f) => findingFromRegionJson(f as Map<String, dynamic>))
            .toList(),
      );
    } catch (e) {
      throw Exception("Could not read the AI's response, please try again.");
    }
  }

  static String _promptText(String year) =>
      'You are helping a FRC (FIRST Robotics Competition) team do a quick '
      'pre-inspection check against the attached $year FRC game manual. '
      'Use ONLY that manual as the source of truth because rules change '
      'each season. Your job is to point out things worth double checking '
      'against the rulebook, not to give a final ruling on legality. Do '
      'not say a robot is compliant, and do not say a robot is in '
      'violation, only that something looks worth a closer look.\n\n'
      'Only check things that can actually be judged from a static photo: '
      'bumper presence, bumper color and numbering, bumper height and '
      'coverage as visible, and whether the visible outline of the robot '
      'appears to exceed the frame perimeter. Do not attempt to judge '
      'wiring correctness, breaker sizing, component legality, or any '
      'rule that depends on internal specifications, mechanism range of '
      'motion, or parts that are partially hidden. If a rule cannot be '
      'judged from what is visible in this single photo, do not comment '
      'on it.\n\n'
      'The photo is split into 9 overlapping crops. Each crop has a '
      '"Region:" label immediately before its image (top-left, top-center, '
      'top-right, middle-left, center, middle-right, bottom-left, '
      'bottom-center, bottom-right). Cite the specific rule number when '
      'the manual supports it. Do not comment on anything that cannot be '
      'seen or measured from the photo.\n\n'
      'Return an empty findings list ONLY if the image is clear enough to '
      'check the items above and nothing looks worth a closer look. If '
      'the image is too dark, blurry, obstructed, or too distant to check '
      'bumpers or frame perimeter, return one item titled "Photo quality '
      'prevents rule check" rather than an empty list. Because crops '
      'overlap, report each distinct item only once, using its clearest '
      'crop and setting "region" to that crop\'s label. For box_2d, use '
      'Gemini\'s standard format: [ymin, xmin, ymax, xmax], each 0–1000, '
      'relative to THAT CROP (not the full photo). Respond only with JSON '
      'in this exact format:\n\n'
      '{"findings":[{"region":"top-left","title":"short label for what to '
      'check","description":"one or two sentence explanation of what to '
      'double check, cite rule number if applicable",'
      '"severity":"critical|warning|ok","box_2d":[0,0,0,0]}]}\n\n'
      'Omit "box_2d" entirely if you cannot localize the item within its '
      'crop. If nothing looks worth checking, return {"findings":[]}.';

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
    final result = <Finding>[];
    for (final f in findings) {
      final key = f.title.trim().toLowerCase();
      if (seenTitles.add(key)) result.add(f);
    }
    return result;
  }
}