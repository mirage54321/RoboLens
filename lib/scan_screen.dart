import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'tap_cursor.dart';
import 'package:image_picker/image_picker.dart';
import 'constants.dart';
import 'ai_scan.dart';
import 'results_screen.dart';
import 'guided_camera_screen.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  Uint8List? _imageBytes;
  bool _isAnalyzing = false;
  String _analyzingStatus = 'Analyzing...';
  final ImagePicker _picker = ImagePicker();
  String errorMessage = "";

  Future<void> pickPhoto() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked != null) {
      final bytes = await picked.readAsBytes();
      setState(() => _imageBytes = bytes);
    }
  }

  Future<void> openGuidedCamera() async {
    final bytes = await Navigator.push<Uint8List?>(
      context,
      MaterialPageRoute(builder: (_) => const GuidedCameraScreen()),
    );
    if (bytes != null) {
      setState(() => _imageBytes = bytes);
    }
  }

  Future<void> _analyze() async {
    if (_imageBytes == null) return;
    setState(() {
      _isAnalyzing = true;
      _analyzingStatus = 'Sending to AI...';
    });
    await Future.delayed(Duration.zero);

    try {
      setState(() => _analyzingStatus = 'Scanning for issues...');
      final findings = await AiService.analyzeImage(
        _imageBytes!,
        onRetry: (attempt, maxAttempts, nextDelay) {
          if (!mounted) return;
          setState(() {
            _analyzingStatus =
                'High demand. Retrying (${attempt + 1}/$maxAttempts)...';
          });
        },
      );

      if (!mounted) return;
      setState(() => _isAnalyzing = false);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ResultsScreen(
            imageBytes: _imageBytes!,
            findings: findings,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      if (e.toString().contains('offline')) {
        errorMessage = "Can't use the AI while offline. Get a better connection and try again.";
      } else if (e.toString().contains('experiencing high demand')) {
        errorMessage = 'The AI is currently experiencing high demand. Please try again in a few seconds!';
      } else {
        errorMessage= "Scan Failed: \n${e.toString()}";
      }
      setState(() => _isAnalyzing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMessage,
          ),
          backgroundColor: const Color(0xFFD93025),
          duration: const Duration(seconds: 10),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FFFE),
      body: SafeArea(
        child: Column(
          children: [
            top(context),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    image(),
                    const SizedBox(height: 16),
                    if (_imageBytes == null) uploadArea(),
                    if (_imageBytes != null) retake(),
                    const SizedBox(height: 20),
                    button(),
                    const SizedBox(height: 20),
                    hint2(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget top(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Row(
        children: [
          TapCursor(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: TealScanLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.arrow_back, color: TealScan, size: 17),
            ),
          ),
          const SizedBox(width: 10),
          const Text('New scan',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget image() {
    return Container(
      width: double.infinity,
      height: 280,
      decoration: BoxDecoration(
        color: _imageBytes == null ? TealScanLight : null,
        border: _imageBytes == null
            ? Border.all(
                color: TealScan,
                width: 2,
                strokeAlign: BorderSide.strokeAlignInside)
            : null,
        borderRadius: BorderRadius.circular(20),
      ),
      clipBehavior: Clip.antiAlias,
      child: _imageBytes == null
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: TealScan.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.photo_library_outlined,
                      color: TealScan, size: 30),
                ),
                const SizedBox(height: 14),
                const Text('No photo selected',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: TealScanText)),
                const SizedBox(height: 4),
                Text('Take a guided photo or upload one',
                    style: TextStyle(
                        fontSize: 12,
                        color: TealScanText.withValues(alpha: 0.6))),
              ],
            )
          : Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(_imageBytes!, fit: BoxFit.cover),
                if (_isAnalyzing)
                  Container(
                    color: Colors.black.withValues(alpha: 0.5),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(color: TealScan),
                        const SizedBox(height: 14),
                        Text(
                          _analyzingStatus,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  Widget uploadArea() {
    return Row(
      children: [
        Expanded(
          child: outliner(
            icon: Icons.camera_alt_outlined,
            label: 'Take guided photo',
            onTap: openGuidedCamera,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: outliner(
            icon: Icons.photo_library_outlined,
            label: 'Upload photo',
            onTap: pickPhoto,
          ),
        ),
      ],
    );
  }

  Widget retake() {
    return Row(
      children: [
        Expanded(
          child: outliner(
            icon: Icons.camera_alt_outlined,
            label: 'Retake with camera',
            onTap: openGuidedCamera,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: outliner(
            icon: Icons.photo_library_outlined,
            label: 'Choose different photo',
            onTap: pickPhoto,
          ),
        ),
      ],
    );
  }

  Widget outliner({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return TapCursor(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: Colors.black.withValues(alpha: 0.1), width: 0.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: TealScan, size: 18),
            const SizedBox(width: 7),
            Flexible(
              child: Text(label,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: TealScanText)),
            ),
          ],
        ),
      ),
    );
  }

  Widget button() {
    final ready = _imageBytes != null && !_isAnalyzing;
    return TapCursor(
      onTap: ready ? _analyze : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          color: _isAnalyzing
              ? Colors.grey[400]
              : (ready ? TealScan : TealScan.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: _isAnalyzing
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    ),
                    const SizedBox(width: 10),
                    Text(_analyzingStatus,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: Colors.white)),
                  ],
                )
              : const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.search, color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text('Analyze photo',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: Colors.white)),
                  ],
                ),
        ),
      ),
    );
  }

  Widget hint2() {
    return Text(
      'This tool uses AI to point out things worth a closer look, like wiring, cracks, or misalignment.\n\nIt does not give a final safety verdict and can miss or misread things. Always do a manual inspection too, and never rely on it to identify what a button, light, or switch does.',
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 12, color: Colors.grey[500], height: 1.5),
    );
  }
}