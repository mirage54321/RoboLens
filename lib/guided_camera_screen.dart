import 'dart:async';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'constants.dart';
import 'web_probe.dart';


class GuidedCameraScreen extends StatefulWidget {
  const GuidedCameraScreen({super.key});

  @override
  State<GuidedCameraScreen> createState() => _GuidedCameraScreenState();
}

class _GuidedCameraScreenState extends State<GuidedCameraScreen> {
  CameraController? camera;
  List<CameraDescription> camSquad = [];
  StreamSubscription<AccelerometerEvent>? wobbleWatcher;

  double tiltAngle = 0;
  static const double tiltWiggle = 5;
  bool get levelOk => tiltAngle.abs() <= tiltWiggle;

  double glow = 0;
  bool get litJustRight => glow >= 80 && glow <= 130;

  double crispiness = 0;
  static const double crispyMin = 0.001;
  bool get crispyEnough => crispiness >= crispyMin;

  bool get greenLight => levelOk && litJustRight && crispyEnough;

  bool busyBee = false;
  bool snapping = false;
  bool oops = false;
  bool noPermission = false;
  bool permissionLockedOut = false;
  String? errorMassage;
  bool waitingForTap = false;

  DateTime? goodStartTime;
  double progressBar = 0;
  static const Duration holdTime = Duration(milliseconds: 1400);

  String get statusText {
    if (snapping) return 'Capturing...';
    if (!levelOk) {
      return tiltAngle > 0 ? 'Tilt the phone down a bit' : 'Tilt the phone up a bit';
    }
    if (!litJustRight) {
      return glow < 60 ? 'Find better lighting' : 'Too much glare — reduce light';
    }
    if (!crispyEnough) return 'Hold steady / adjust distance';
    return 'Hold still...';
  }

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      waitingForTap = true;
    } else {
      fireUp();
    }
  }

  Future<void> fireUp() async {
    waitingForTap = false;
    try {
      if (kIsWeb) {
        await stage('requestMotionAccess', () => WebProbe.requestMotionAccess());
      } else {
        final status = await Permission.camera.request();
        if (!status.isGranted) {
          if (!mounted) return;
          setState(() {
            oops = true;
            noPermission = true;
            permissionLockedOut = status.isPermanentlyDenied;
          });
          return;
        }
      }

      camSquad = await stage('availableCameras', () => availableCameras());
      if (camSquad.isEmpty) {
        if (mounted) setState(() => oops = true);
        return;
      }
      final back = camSquad.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => camSquad.first,
      );
      final newCamera = await stage('createController', () async {
        return CameraController(
          back,
          kIsWeb ? ResolutionPreset.medium : ResolutionPreset.high,
          enableAudio: false,
          imageFormatGroup: ImageFormatGroup.yuv420,
        );
      });
      await stage('controller.initialize', () => newCamera.initialize());
      if (!mounted) return;
      setState(() => camera = newCamera);

      if (!kIsWeb) {
        await stage('startImageStream', () => newCamera.startImageStream(onSnapshot));
        wobbleWatcher = accelerometerEventStream().listen(onWobble);
      } else {
        try {
          WebProbe.watchTilt((pitchDeg) {
            if (!mounted) return;
            setState(() => tiltAngle = pitchDeg);
            checkVibes();
          });
          WebProbe.watchFrame((brightness, sharpness) {
            if (!mounted) return;
            setState(() {
              glow = brightness;
              crispiness = sharpness;
            });
            checkVibes();
          });
        } catch (e) {
          debugPrint('Web guidance setup failed (camera still works): $e');
        }
      }
    } catch (e) {
      debugPrint('Camera init failed: $e');
      if (mounted) {
        setState(() {
          oops = true;
          errorMassage = e.toString();
        });
      }
    }
  }

  Future<T> stage<T>(String name, Future<T> Function() action) async {
    try {
      return await action();
    } catch (e) {
      throw '[$name] $e';
    }
  }

  void onWobble(AccelerometerEvent event) {
    final pitchRad =
        math.atan2(-event.x, math.sqrt(event.y * event.y + event.z * event.z));
    final pitchDeg = pitchRad * 180 / math.pi;
    if (!mounted) return;
    setState(() => tiltAngle = pitchDeg);
    checkVibes();
  }

  void onSnapshot(CameraImage image) {
    if (busyBee || snapping) return;
    busyBee = true;
    try {
      final yPlane = image.planes[0];
      final bytes = yPlane.bytes;
      final width = image.width;
      final height = image.height;
      final bytesPerRow = yPlane.bytesPerRow;

      const step = 12;
      int sum = 0;
      int count = 0;
      int sharpnessSum = 0;
      int sharpnessCount = 0;

      for (int y = step; y < height - step; y += step) {
        final rowStart = y * bytesPerRow;
        for (int x = step; x < width - step; x += step) {
          final idx = rowStart + x;
          if (idx >= bytes.length) continue;
          final val = bytes[idx];
          sum += val;
          count++;

          final rightIdx = idx + step;
          if (rightIdx < bytes.length) {
            sharpnessSum += (val - bytes[rightIdx]).abs();
            sharpnessCount++;
          }
        }
      }

      final avgBrightness = count == 0 ? 0.0 : sum / count;
      final avgSharpness = sharpnessCount == 0 ? 0.0 : sharpnessSum / sharpnessCount;

      if (mounted) {
        setState(() {
          glow = avgBrightness;
          crispiness = avgSharpness;
        });
        checkVibes();
      }
    } catch (_) {
    } finally {
      busyBee = false;
    }
  }

  void checkVibes() {
    if (snapping) return;
    if (greenLight) {
      goodStartTime ??= DateTime.now();
      final elapsed = DateTime.now().difference(goodStartTime!);
      final progress =
          (elapsed.inMilliseconds / holdTime.inMilliseconds).clamp(0.0, 1.0);
      if (progress != progressBar) {
        setState(() => progressBar = progress);
      }
      if (progress >= 1.0) {
        snapPic();
      }
    } else {
      goodStartTime = null;
      if (progressBar != 0) {
        setState(() => progressBar = 0);
      }
    }
  }

  Future<void> snapPic() async {
    if (snapping || camera == null) return;
    setState(() => snapping = true);
    try {
      if (!kIsWeb) {
        await camera!.stopImageStream();
      } else {
        WebProbe.stopFrame();
        WebProbe.stopTilt();
      }
      final file = await camera!.takePicture();
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      Navigator.pop(context, bytes);
    } catch (e) {
      if (!mounted) return;
      setState(() => snapping = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Capture failed: $e')),
      );
      if (!kIsWeb) {
        try {
          await camera?.startImageStream(onSnapshot);
        } catch (_) {}
      } else {
        WebProbe.watchTilt((pitchDeg) {
          if (!mounted) return;
          setState(() => tiltAngle = pitchDeg);
          checkVibes();
        });
        WebProbe.watchFrame((brightness, sharpness) {
          if (!mounted) return;
          setState(() {
            glow = brightness;
            crispiness = sharpness;
          });
          checkVibes();
        });
      }
    }
  }

  Future<void> snapByHand() async {
    goodStartTime = null;
    await snapPic();
  }

  @override
  void dispose() {
    wobbleWatcher?.cancel();
    if (kIsWeb) {
      WebProbe.stopTilt();
      WebProbe.stopFrame();
    }
    camera?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cam = camera;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            if (waitingForTap)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.camera_alt_outlined, color: Colors.white54, size: 40),
                      const SizedBox(height: 16),
                      const Text(
                        'Tap below to enable your camera',
                        style: TextStyle(color: Colors.white, fontSize: 15),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 18),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {});
                          fireUp();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: TealScan,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Enable Camera'),
                      ),
                    ],
                  ),
                ),
              )
            else if (oops)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.camera_alt_outlined, color: Colors.white54, size: 40),
                      const SizedBox(height: 16),
                      Text(
                        noPermission
                            ? 'Camera access is needed to take a guided photo.'
                            : 'Could not access the camera.',
                        style: const TextStyle(color: Colors.white, fontSize: 15),
                        textAlign: TextAlign.center,
                      ),
                      if (errorMassage != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          errorMassage!,
                          style: const TextStyle(color: Colors.orangeAccent, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      if (permissionLockedOut) ...[
                        const SizedBox(height: 18),
                        ElevatedButton(
                          onPressed: () => openAppSettings(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: TealScan,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Open Settings'),
                        ),
                      ] else if (noPermission) ...[
                        const SizedBox(height: 18),
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              oops = false;
                              noPermission = false;
                              errorMassage = null;
                            });
                            fireUp();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: TealScan,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Try again'),
                        ),
                      ],
                    ],
                  ),
                ),
              )
            else if (cam != null && cam.value.isInitialized)
              Positioned.fill(child: CameraPreview(cam))
            else
              const Center(child: CircularProgressIndicator(color: TealScan)),
            Positioned(
              top: 10,
              left: 10,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 18),
                ),
              ),
            ),
            if (!oops && !waitingForTap) ...[
              drawFrame(),
              drawStatus(),
              drawShutterButton(),
            ],
          ],
        ),
      ),
    );
  }

  Widget drawFrame() {
    return Center(
      child: AspectRatio(
        aspectRatio: 3 / 4,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: greenLight ? const Color(0xFF00B3AC) : Colors.white.withValues(alpha: 0.6),
                width: greenLight ? 3 : 1.5,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),
    );
  }

  Widget drawStatus() {
    return Positioned(
      top: 60,
      left: 20,
      right: 20,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              statusText,
              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
          ),
          if (greenLight && !snapping) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: 120,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progressBar,
                  minHeight: 5,
                  backgroundColor: Colors.white24,
                  color: const Color(0xFF00B3AC),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget drawShutterButton() {
    return Positioned(
      bottom: 24,
      left: 0,
      right: 0,
      child: Center(
        child: GestureDetector(
          onTap: snapping ? null : snapByHand,
          child: Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(color: Colors.white54, width: 4),
            ),
            child: snapping
                ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(color: TealScan, strokeWidth: 3),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}