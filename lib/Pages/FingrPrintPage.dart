// lib/screens/EnrollFingerprintPage.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../Auth/AuthService.dart';
import '../Services/BiometrricService.dart';
import '../Services/DataService.dart';

/// Registers the staff member's biometric (fingerprint OR face, whichever this phone has)
/// on this phone. Pops `true` when done.
class EnrollFingerprintPage extends StatefulWidget {
  const EnrollFingerprintPage({super.key});

  @override
  State<EnrollFingerprintPage> createState() => _EnrollFingerprintPageState();
}

class _EnrollFingerprintPageState extends State<EnrollFingerprintPage> with WidgetsBindingObserver {
  static const Color _ink = Color(0xFF0F172A);
  static const Color _card = Color(0xFFF1F3F7);
  static const Color _dim = Color(0xFF6B7280);
  static const Color _green = Color(0xFF1DB580);
  static const Color _red = Color(0xFFF04438);
  static const String _f = 'Poppins';

  bool _working = false;
  bool _done = false;
  AuthFailure? _failure;

  /// 'fingerprint' | 'face', detected by the OS (never guessed).
  String _type = 'fingerprint';

  bool get _isFace => _type == 'face';
  String get _name => BioText.name(_type); // Face ID / Face unlock / Touch ID / Fingerprint
  String get _word => _isFace ? 'face' : 'fingerprint'; // lowercase, for sentences
  IconData get _icon => _isFace ? Icons.face_rounded : Icons.fingerprint;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadType();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from phone settings (user just set up a biometric) → re-detect.
    if (state == AppLifecycleState.resumed && !_working && !_done) _loadType();
  }

  Future<void> _loadType() async {
    try {
      final s = await BiometricService.instance.localStatus();
      debugPrint('🔐 Enroll page → type=${s.type} available=${s.available} reason=${s.reason}');
      if (!mounted) return;
      setState(() {
        _type = s.type == 'face' ? 'face' : 'fingerprint';
        // A previous "set up biometric" error is stale once one exists now.
        if (s.available && _failure?.code == 'NO_BIOMETRIC_ENROLLED') _failure = null;
      });
    } catch (e) {
      debugPrint('🔐⚠️ Could not read biometric type: $e');
    }
  }

  Future<void> _enroll() async {
    if (_working) return;
    setState(() {
      _working = true;
      _failure = null;
    });
    try {
      await BiometricService.instance.enroll();
      debugPrint('🔐✅ Biometric registered ($_type)');
      if (!mounted) return;
      setState(() {
        _working = false;
        _done = true;
      });
    } on AuthFailure catch (e) {
      debugPrint('🔐❌ Enroll failed → ${e.code}: ${e.message}');
      if (await HomeDataService.handleSessionFailure(e)) {
        if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
        return;
      }
      if (!mounted) return;
      setState(() {
        _working = false;
        _failure = e;
      });
    } catch (e) {
      debugPrint('🔐❌ Enroll error: $e');
      if (!mounted) return;
      setState(() {
        _working = false;
        _failure = AuthFailure('UNKNOWN', 'Something went wrong. Please try again.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color tone = _done ? _green : (_failure != null ? _red : _ink);
    final bool blocked = _failure != null &&
        (_failure!.code == 'BIOMETRIC_CHANGED' || _failure!.code == 'ENROLL_NOT_ALLOWED');

    return PopScope(
      canPop: !_working,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Material(
                    color: _card,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _working ? null : () => Navigator.of(context).pop(_done),
                      child: const SizedBox(
                        width: 48,
                        height: 48,
                        child: Icon(Icons.close_rounded, color: _ink, size: 22),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: Container(
                              width: 96,
                              height: 96,
                              decoration: BoxDecoration(
                                color: tone.withAlpha(36),
                                shape: BoxShape.circle,
                              ),
                              child: _working
                                  ? Center(
                                child: SizedBox(
                                  width: 34,
                                  height: 34,
                                  child: CircularProgressIndicator(strokeWidth: 3.2, color: tone),
                                ),
                              )
                                  : Icon(_done ? Icons.check_rounded : _icon, size: 52, color: tone),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            _done ? '$_name registered' : BioText.registerTitle(_type),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontFamily: _f, fontSize: 24, fontWeight: FontWeight.w700, color: _ink, height: 1.25),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _failure?.message ??
                                (_done
                                    ? 'You can now check in and out with your $_word on this phone.'
                                    : 'Check-in is locked to your $_word on this phone. Nobody else can check in for you.'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontFamily: _f,
                                fontSize: 14,
                                color: _failure != null ? _red : _dim,
                                height: 1.5),
                          ),
                          if (!_done && _failure == null) ...[
                            const SizedBox(height: 24),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(20)),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _Tip(_isFace
                                      ? 'Hold the phone at eye level and look straight at it'
                                      : 'Use the finger you will check in with'),
                                  const SizedBox(height: 10),
                                  _Tip('Only your $_word works: no PIN or pattern'),
                                  const SizedBox(height: 10),
                                  const _Tip(
                                      'If you add or change a fingerprint or face later, HR must approve this phone again'),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: SizedBox(
                    height: 54,
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _working
                          ? null
                          : (_done || blocked)
                          ? () => Navigator.of(context).pop(_done)
                          : _enroll,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _ink,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: _ink.withAlpha(120),
                        disabledForegroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      ),
                      child: Text(
                        _working
                            ? 'Waiting for your $_word…'
                            : _done
                            ? 'Done'
                            : blocked
                            ? 'Close'
                            : (_failure != null ? 'Try again' : BioText.registerTitle(_type)),
                        style: const TextStyle(fontFamily: _f, fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tip extends StatelessWidget {
  const _Tip(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Icon(Icons.check_circle_outline_rounded, size: 16, color: Color(0xFF6B7280)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
                fontFamily: 'Poppins', fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF0F172A)),
          ),
        ),
      ],
    );
  }
}