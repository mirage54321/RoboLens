import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'tap_cursor.dart';
import 'package:image_picker/image_picker.dart';
import 'constants.dart';
import 'ai_rules.dart';
import 'results_screen.dart';
import 'guided_camera_screen.dart';

const Pinky = Color(0xFFCF2879);
const PinkyLight = Color(0xFFFFE4F0);

class RulesScreen extends StatefulWidget {
  const RulesScreen({super.key});

  @override
  State<RulesScreen> createState() => _RulesScreenState();
}

class _RulesScreenState extends State<RulesScreen> {
  Uint8List? _imageBytes;
  bool analyzedYes = false;
  String stat = 'Analyzing...';
  String year = '2026';
  String errorMessage = "";
  final ImagePicker _picker = ImagePicker();

  final List<String> roboticYear = ['2026', '2025', '2024'];

  Future<void> _pickFromGallery() async {
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

  Future<void> sendToai() async {
    if (_imageBytes == null) return;
    setState(() {
      analyzedYes = true;
      stat = 'Sending to AI...';
    });
    await Future.delayed(Duration.zero);

    try {
      setState(() => stat = 'Checking $year rules...');
      final findings = await AiRulesService.analyzeImage(
        _imageBytes!,
        year,
        onRetry: (attempt, maxAttempts, nextDelay) {
          if (!mounted) return;
          setState(() {
            stat = 'High demand. Retrying (${attempt + 1}/$maxAttempts)...';
          });
        },
      );

      if (!mounted) return;
      setState(() => analyzedYes = false);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ResultsScreen(
            imageBytes: _imageBytes!,
            findings: findings,
            scanMode: 'rules',
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
      setState(() => analyzedYes = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: const Color(0xFFD93025),
          duration: const Duration(seconds: 10),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 255, 248, 253),
      body: SafeArea(
        child: Column(
          children: [
            Top(context),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    years(),
                    const SizedBox(height: 16),
                    imageSpace(),
                    const SizedBox(height: 16),
                    if (_imageBytes == null) picking(),
                    if (_imageBytes != null) retakePHOTO(),
                    const SizedBox(height: 20),
                    analyzeButt(),
                    const SizedBox(height: 20),
                    hint(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget Top(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          TapCursor(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: PinkyLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.arrow_back, color: Pinky, size: 17),
            ),
          ),
          const SizedBox(width: 10),
          const Text('New scan',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget years() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.07), width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('FRC Season Year',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          const SizedBox(height: 12),
          Row(
            children: roboticYear.map((option) {
              final selected = option == year;
              return Padding(
                padding: const EdgeInsets.only(right: 10),
                child: TapCursor(
                  onTap: () => setState(() => year = option),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: selected ? Pinky : PinkyLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      option,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: selected ? Colors.white : Pinky,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget imageSpace() {
    return Container(
      width: double.infinity,
      height: 260,
      decoration: BoxDecoration(
        color: _imageBytes == null ? PinkyLight : null,
        border: _imageBytes == null
            ? Border.all(
                color: Pinky,
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
                    color: Pinky.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.photo_library_outlined,
                      color: Pinky, size: 30),
                ),
                const SizedBox(height: 14),
                const Text('No photo selected',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Pinky)),
                const SizedBox(height: 4),
                Text('Take a guided photo or upload one',
                    style: TextStyle(
                        fontSize: 12,
                        color: Pinky.withValues(alpha: 0.6))),
              ],
            )
          : Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(_imageBytes!, fit: BoxFit.cover),
                if (analyzedYes)
                  Container(
                    color: Colors.black.withValues(alpha: 0.5),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(color: Pinky),
                        const SizedBox(height: 14),
                        Text(
                          stat,
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

  Widget picking() {
    return Row(
      children: [
        Expanded(
          child: outline(
            icon: Icons.camera_alt_outlined,
            label: 'Take guided photo',
            onTap: openGuidedCamera,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: outline(
            icon: Icons.photo_library_outlined,
            label: 'Upload photo',
            onTap: _pickFromGallery,
          ),
        ),
      ],
    );
  }

  Widget retakePHOTO() {
    return Row(
      children: [
        Expanded(
          child: outline(
            icon: Icons.camera_alt_outlined,
            label: 'Retake with camera',
            onTap: openGuidedCamera,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: outline(
            icon: Icons.photo_library_outlined,
            label: 'Choose a different photo',
            onTap: _pickFromGallery,
          ),
        ),
      ],
    );
  }

  Widget outline({
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
            Icon(icon, color: Pinky, size: 18),
            const SizedBox(width: 7),
            Flexible(
              child: Text(label,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Pinky)),
            ),
          ],
        ),
      ),
    );
  }

  Widget analyzeButt() {
    final ready = _imageBytes != null && !analyzedYes;
    return TapCursor(
      onTap: ready ? sendToai : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          color: analyzedYes
              ? Colors.grey[400]
              : (ready ? Pinky : Pinky.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: analyzedYes
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
                    Text(stat,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: Colors.white)),
                  ],
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.rule, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Text('Check $year rules',
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: Colors.white)),
                  ],
                ),
        ),
      ),
    );
  }

  Widget hint() {
    return Text(
      'This tool uses AI to flag things worth double checking against the $year FRC game manual, limited to what a photo can actually show, like bumpers and frame perimeter. \n\nIt does not give a final ruling on legality and is not a replacement for a real inspection. Always consult the official FRC rules and your local inspectors for final decisions.',
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 12, color: Colors.grey[500], height: 1.5),
    );
  }
}