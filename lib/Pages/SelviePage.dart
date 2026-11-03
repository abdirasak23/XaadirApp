// lib/Pages/SelfiePage.dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

/// Front-camera selfie capture. Pops with the JPEG bytes (Uint8List), or null if closed.
class SelfieCapturePage extends StatefulWidget {
  const SelfieCapturePage({super.key});

  @override
  State<SelfieCapturePage> createState() => _SelfieCapturePageState();
}

class _SelfieCapturePageState extends State<SelfieCapturePage> with WidgetsBindingObserver {
  static const String _f = 'Poppins';
  static const Color _ink = Color(0xFF0F172A);
  static const Color _green = Color(0xFF1DB580);
  static const int _maxBytes = 1900 * 1024; // server limit is 2 MB

  CameraController? _cam;
  bool _starting = true;
  bool _capturing = false;
  bool _permissionIssue = false;
  bool _leaving = false;
  String? _error;
  Uint8List? _shot;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cam?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _cam;
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      if (c == null) return;
      setState(() => _cam = null);
      c.dispose();
    } else if (state == AppLifecycleState.resumed) {
      if (!_leaving && _cam == null && !_starting && _error == null && _shot == null) _start();
    }
  }

  Future<void> _start() async {
    if (!mounted || _leaving) return;
    setState(() {
      _starting = true;
      _error = null;
      _permissionIssue = false;
    });
    try {
      final cams = await availableCameras();
      final front = cams.where((c) => c.lensDirection == CameraLensDirection.front).toList();
      if (front.isEmpty) {
        _fail('No front camera was found on this phone.');
        return;
      }
      final c = CameraController(front.first, ResolutionPreset.medium, enableAudio: false);
      await c.initialize();
      try {
        await c.lockCaptureOrientation(DeviceOrientation.portraitUp);
      } catch (_) {}
      if (!mounted || _leaving) {
        await c.dispose();
        return;
      }
      setState(() {
        _cam = c;
        _starting = false;
      });
    } on CameraException catch (e) {
      final denied = e.code.contains('AccessDenied') || e.code.contains('AccessRestricted');
      _fail(
        denied
            ? 'Allow camera access in your phone settings to take your selfie.'
            : 'Could not open the camera. Please try again.',
        permission: denied,
      );
    } catch (e) {
      debugPrint('❌ Selfie camera error: $e');
      _fail('Could not open the camera. Please try again.');
    }
  }

  void _fail(String msg, {bool permission = false}) {
    if (!mounted) return;
    setState(() {
      _starting = false;
      _error = msg;
      _permissionIssue = permission;
    });
  }

  Future<void> _capture() async {
    if (_leaving) return;
    final c = _cam;
    if (c == null || !c.value.isInitialized || _capturing) return;
    setState(() => _capturing = true);
    HapticFeedback.mediumImpact();
    try {
      final f = await c.takePicture();
      final bytes = await f.readAsBytes();
      try {
        await File(f.path).delete();
      } catch (_) {}
      if (!mounted) return;
      if (bytes.length > _maxBytes) {
        setState(() => _capturing = false);
        _toast('That photo is too large. Please try again.');
        return;
      }
      setState(() {
        _shot = bytes;
        _capturing = false;
      });
    } catch (e) {
      debugPrint('❌ Selfie capture error: $e');
      if (!mounted) return;
      setState(() => _capturing = false);
      _toast('Could not take the photo. Please try again.');
    }
  }

  void _retake() {
    if (_leaving) return;
    HapticFeedback.selectionClick();
    setState(() => _shot = null);
  }

  /// Releases the camera completely BEFORE leaving, so the QR scanner can take it.
  Future<void> _releaseCamera() async {
    final c = _cam;
    if (mounted) setState(() => _cam = null);
    try {
      await c?.dispose();
    } catch (_) {}
  }

  Future<void> _use() async {
    if (_leaving) return;
    _leaving = true;
    HapticFeedback.mediumImpact();
    final shot = _shot;
    await _releaseCamera();
    if (!mounted) return;
    Navigator.of(context).pop(shot);
  }

  Future<void> _closePage() async {
    if (_leaving) return;
    _leaving = true;
    await _releaseCamera();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _toast(String m) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m, style: const TextStyle(fontFamily: _f))));
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: _error != null ? _buildError() : _buildCapture(),
      ),
    );
  }

  Widget _buildCapture() {
    final reviewing = _shot != null;
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final h = c.maxHeight;
      final ovalW = w * 0.74;
      final oval = Rect.fromCenter(center: Offset(w / 2, h * 0.40), width: ovalW, height: ovalW * 1.28);
      final cam = _cam;

      return Stack(
        fit: StackFit.expand,
        children: [
          // Live preview or the captured photo
          if (reviewing)
            Image.memory(_shot!, fit: BoxFit.cover, gaplessPlayback: true)
          else if (cam != null && cam.value.isInitialized)
            ClipRect(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: cam.value.previewSize!.height,
                  height: cam.value.previewSize!.width,
                  child: CameraPreview(cam),
                ),
              ),
            )
          else
            const Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3)),

          IgnorePointer(child: CustomPaint(size: Size(w, h), painter: _OvalOverlay(oval))),
          Positioned.fromRect(
            rect: oval,
            child: IgnorePointer(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.all(Radius.elliptical(oval.width / 2, oval.height / 2)),
                  border: Border.all(color: reviewing ? _green : Colors.white.withAlpha(200), width: reviewing ? 4 : 2.5),
                ),
              ),
            ),
          ),

          // Top bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  children: [
                    _round(Icons.close_rounded, 'Close', _closePage),
                    const Expanded(
                      child: Text(
                        'Take your selfie',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontFamily: _f, fontSize: 17, fontWeight: FontWeight.w600, color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 52),
                  ],
                ),
              ),
            ),
          ),

          // Bottom controls
          Positioned(
            left: 24,
            right: 24,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: reviewing ? _reviewControls() : _captureControls(),
                ),
              ),
            ),
          ),
        ],
      );
    });
  }

  Widget _notice(String text, {IconData icon = Icons.info_outline_rounded}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: Colors.black.withAlpha(150), borderRadius: BorderRadius.circular(18)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: Colors.white),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(fontFamily: _f, fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _captureControls() {
    final ready = _cam?.value.isInitialized == true && !_capturing && !_starting && !_leaving;
    return Column(
      key: const ValueKey('capture'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _notice('Center your face in the oval, in good light. Your selfie will be reviewed.',
            icon: Icons.face_retouching_natural_rounded),
        const SizedBox(height: 20),
        Semantics(
          button: true,
          label: 'Take photo',
          child: GestureDetector(
            onTap: ready ? _capture : null,
            child: Opacity(
              opacity: ready ? 1 : 0.5,
              child: Container(
                width: 78,
                height: 78,
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3)),
                child: Container(
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: _capturing
                      ? const Padding(
                    padding: EdgeInsets.all(22),
                    child: CircularProgressIndicator(strokeWidth: 3, color: _ink),
                  )
                      : null,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _reviewControls() {
    return Column(
      key: const ValueKey('review'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _notice('Your selfie will be reviewed.', icon: Icons.verified_user_outlined),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 54,
                child: OutlinedButton(
                  onPressed: _leaving ? null : _retake,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white70, width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                  child: const Text('Retake', style: TextStyle(fontFamily: _f, fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: SizedBox(
                height: 54,
                child: ElevatedButton(
                  onPressed: _leaving ? null : _use,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: _ink,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                  child: const Text('Use photo & scan QR',
                      style: TextStyle(fontFamily: _f, fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildError() {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: _round(Icons.close_rounded, 'Close', _closePage),
            ),
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.no_photography_outlined, color: Colors.white, size: 48),
                    const SizedBox(height: 20),
                    const Text('Camera not available',
                        style: TextStyle(fontFamily: _f, fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
                    const SizedBox(height: 8),
                    Text(_error ?? '',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontFamily: _f, fontSize: 14, color: Colors.white70, height: 1.5)),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _permissionIssue ? ph.openAppSettings : _start,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: _ink,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        ),
                        child: Text(_permissionIssue ? 'Open app settings' : 'Try again',
                            style: const TextStyle(fontFamily: _f, fontSize: 16, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    if (_permissionIssue)
                      TextButton(
                        onPressed: _start,
                        child: const Text('Try again',
                            style: TextStyle(fontFamily: _f, fontWeight: FontWeight.w700, color: Colors.white)),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _round(IconData icon, String label, VoidCallback onTap) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.black.withAlpha(140),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: 52, height: 52, child: Icon(icon, color: Colors.white, size: 24)),
        ),
      ),
    );
  }
}

class _OvalOverlay extends CustomPainter {
  _OvalOverlay(this.hole);
  final Rect hole;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Path()..addRect(Offset.zero & size);
    final cut = Path()..addOval(hole);
    canvas.drawPath(Path.combine(PathOperation.difference, bg, cut), Paint()..color = Colors.black.withAlpha(150));
  }

  @override
  bool shouldRepaint(covariant _OvalOverlay old) => old.hole != hole;
}