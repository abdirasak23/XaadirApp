// lib/scan_page.dart
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../Auth/AuthService.dart';
import '../Services/DataService.dart';
import '../Services/ScanService.dart';
import 'FingrPrintPage.dart';

// ════════════════════════════════════════════════════════════════════
//  DESIGN TOKENS (same as Home)
// ════════════════════════════════════════════════════════════════════
class _C {
  static const Color bg = Colors.white;
  static const Color card = Color(0xFFF1F3F7);
  static const Color border = Color(0xFFE2E5EB);
  static const Color ink = Color(0xFF0F172A);
  static const Color dim = Color(0xFF6B7280);
  static const Color green = Color(0xFF1DB580);
  static const Color orange = Color(0xFFE09112);
  static const Color red = Color(0xFFF04438);
  static const Color blue = Color(0xFF3B82F6);
}

class _T {
  static const String f = 'Poppins';
  static const TextStyle title = TextStyle(
      fontFamily: f, fontSize: 24, fontWeight: FontWeight.w700, color: _C.ink, height: 1.25);
  static const TextStyle body = TextStyle(
      fontFamily: f, fontSize: 14, fontWeight: FontWeight.w400, color: _C.dim, height: 1.5);
  static const TextStyle bodyStrong = TextStyle(
      fontFamily: f, fontSize: 14, fontWeight: FontWeight.w600, color: _C.ink, height: 1.4);
  static const TextStyle caption = TextStyle(
      fontFamily: f, fontSize: 12, fontWeight: FontWeight.w400, color: _C.dim, height: 1.4);
  static const TextStyle button = TextStyle(
      fontFamily: f, fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white);
}

/// All icons live here. If a Hugeicons name does not exist in your
/// package version, change it in this one place.
class _I {
  static const qr = HugeIcons.strokeRoundedQrCode;
  static const wifiOff = HugeIcons.strokeRoundedWifiDisconnected01;
  static const alert = HugeIcons.strokeRoundedAlertCircle;
  static const refresh = HugeIcons.strokeRoundedRefresh;
  static const close = HugeIcons.strokeRoundedCancel01;
  static const branch = HugeIcons.strokeRoundedLocation01;
  static const clock = HugeIcons.strokeRoundedClock01;
  static const info = HugeIcons.strokeRoundedInformationCircle;
}

Color _tint(Color c, double opacity) => c.withAlpha((opacity * 255).round());

class _Hi extends StatelessWidget {
  const _Hi(this.icon, {this.size = 22, this.color = _C.ink});
  final dynamic icon;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => HugeIcon(icon: icon, color: color, size: size);
}

// ════════════════════════════════════════════════════════════════════
//  SCAN PAGE
// ════════════════════════════════════════════════════════════════════
enum _Phase { checking, blocked, camera, submitting, result }

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  // The fingerprint prompt now runs inside preflight(), so allow more time.
  static const Duration _submitTimeout = Duration(seconds: 90);
  static const Duration _requestTimeout = Duration(seconds: 20);

  final ScanService _service = ScanService.instance;

  MobileScannerController? _scanner;

  late final AnimationController _lineCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2000),
  )..repeat(reverse: true);

  _Phase _phase = _Phase.checking;
  ScanContextInfo? _ctx;
  AuthFailure? _failure;
  CheckinResult? _result;
  String? _scanHint;
  bool _torchOn = false;
  bool _handling = false;
  bool _openedSettings = false;
  int _seq = 0;

  // "Phone not approved" → ask HR
  bool _approvalBusy = false;
  bool _approvalSent = false;
  String? _approvalError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _runPreflight();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _lineCtrl.dispose();
    _scanner?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Came back from system settings → re-check automatically.
    if (state == AppLifecycleState.resumed && _openedSettings && _phase == _Phase.blocked) {
      _openedSettings = false;
      _runPreflight();
      return;
    }

    final s = _scanner;
    if (s == null || _phase != _Phase.camera) return;
    if (state == AppLifecycleState.resumed) {
      s.start().catchError((_) {});
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      s.stop().catchError((_) {});
    }
  }

  // ───────────── scanner helpers ─────────────
  MobileScannerController _newScanner() => MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
    formats: const [BarcodeFormat.qrCode],
  );

  void _disposeScannerLater() {
    final old = _scanner;
    _scanner = null;
    if (old == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      old.dispose();
    });
  }

  // ───────────── flow ─────────────
  void _leave() {
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  void _close([bool changed = false]) {
    if (!mounted) return;
    Navigator.of(context).maybePop(changed);
  }

  void _showBlocked(AuthFailure e) {
    HapticFeedback.heavyImpact();
    _disposeScannerLater();
    setState(() {
      _failure = e;
      _phase = _Phase.blocked;
      _torchOn = false;
    });
  }

  Future<void> _runPreflight() async {
    final id = ++_seq;
    _disposeScannerLater();
    setState(() {
      _phase = _Phase.checking;
      _failure = null;
      _scanHint = null;
      _torchOn = false;
      _approvalBusy = false;
      _approvalSent = false;
      _approvalError = null;
    });
    try {
      final ctx = await _service.preflight().timeout(_submitTimeout);
      if (!mounted || id != _seq) return;
      if (ctx.next == CheckinAction.done) {
        setState(() {
          _ctx = ctx;
          _phase = _Phase.result;
          _result = null;
        });
        return;
      }
      setState(() {
        _ctx = ctx;
        _scanner = _newScanner();
        _phase = _Phase.camera;
      });
    } on TimeoutException {
      if (!mounted || id != _seq) return;
      _showBlocked(AuthFailure('NETWORK', 'The connection is too slow. Please try again.'));
    } on AuthFailure catch (e) {
      if (!mounted || id != _seq) return;
      if (await HomeDataService.handleSessionFailure(e)) {
        _leave();
        return;
      }
      if (!mounted) return;
      _showBlocked(e);
    } catch (e) {
      debugPrint('❌ Preflight error: $e');
      if (!mounted || id != _seq) return;
      _showBlocked(AuthFailure('UNKNOWN', 'Something went wrong. Please try again.'));
    }
  }

  /// "Phone not approved" → send a request to HR.
  /// 'approved' from the server means HR already did it, so just re-check.
  Future<void> _requestApproval() async {
    if (_approvalBusy) return;
    setState(() {
      _approvalBusy = true;
      _approvalError = null;
    });
    try {
      final status = await _service.requestDeviceApproval().timeout(_requestTimeout);
      if (!mounted) return;
      if (status == 'approved') {
        _runPreflight();
        return;
      }
      HapticFeedback.mediumImpact();
      setState(() {
        _approvalBusy = false;
        _approvalSent = true;
      });
    } on TimeoutException {
      _approvalFailed('The connection is too slow. Please try again.');
    } on AuthFailure catch (e) {
      if (await HomeDataService.handleSessionFailure(e)) {
        _leave();
        return;
      }
      _approvalFailed(e.message);
    } catch (e) {
      debugPrint('❌ Device request error: $e');
      _approvalFailed('Could not send your request. Please try again.');
    }
  }

  void _approvalFailed(String message) {
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    setState(() {
      _approvalBusy = false;
      _approvalError = message;
    });
  }

  /// Back to the camera without redoing the location check
  /// (used after a bad / expired / wrong-branch QR).
  void _rescan() {
    _disposeScannerLater();
    setState(() {
      _failure = null;
      _scanHint = null;
      _torchOn = false;
      _handling = false;
      _scanner = _newScanner();
      _phase = _Phase.camera;
    });
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_phase != _Phase.camera || _handling) return;
    final raw = capture.barcodes.isNotEmpty ? capture.barcodes.first.rawValue : null;
    if (raw == null || raw.isEmpty) return;
    _handling = true;

    final QrPayload payload;
    try {
      payload = _service.parseQr(raw);
    } on AuthFailure catch (e) {
      HapticFeedback.heavyImpact();
      if (mounted) setState(() => _scanHint = e.message);
      await Future.delayed(const Duration(milliseconds: 1800));
      if (mounted) setState(() => _scanHint = null);
      _handling = false;
      return;
    }

    HapticFeedback.selectionClick();
    setState(() => _phase = _Phase.submitting);
    try {
      // fresh location + Wi-Fi at the moment of scanning
      final res = await (() async {
        final facts = await _service.collectFacts();
        return _service.submit(payload, facts);
      })()
          .timeout(_submitTimeout);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      _scanner?.stop().catchError((_) {});
      setState(() {
        _result = res;
        _phase = _Phase.result;
      });
    } on TimeoutException {
      if (!mounted) return;
      _showBlocked(AuthFailure('NETWORK', 'The connection is too slow. Please try again.'));
    } on AuthFailure catch (e) {
      if (await HomeDataService.handleSessionFailure(e)) {
        _leave();
        return;
      }
      if (!mounted) return;
      _showBlocked(e);
    } catch (e) {
      debugPrint('❌ Scan error: $e');
      if (!mounted) return;
      _showBlocked(AuthFailure('UNKNOWN', 'Something went wrong. Please try again.'));
    } finally {
      _handling = false;
    }
  }

  Future<void> _toggleTorch() async {
    try {
      await _scanner?.toggleTorch();
      if (!mounted) return;
      HapticFeedback.selectionClick();
      setState(() => _torchOn = !_torchOn);
    } catch (e) {
      debugPrint('❌ Torch error: $e');
    }
  }

  // ───────────── error presentation ─────────────
  static String _fmt(int m) {
    final h24 = (m ~/ 60) % 24;
    final mm = m % 60;
    final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
    return '$h12:${mm.toString().padLeft(2, '0')} ${h24 >= 12 ? 'PM' : 'AM'}';
  }

  /// "Shift 2 of 3" for staff with several shifts, empty for single-shift staff.
  static String _shiftTitle(int? number, int total) =>
      (total > 1 && number != null) ? 'Shift $number of $total' : '';

  String _blockedTitle(String code) {
    switch (code) {
      case 'LOCATION_OFF':
        return 'Turn on location';
      case 'LOCATION_DENIED':
      case 'LOCATION_DENIED_FOREVER':
        return 'Location permission needed';
      case 'NO_FIX':
      case 'LOW_ACCURACY':
        return 'Weak GPS signal';
      case 'MOCK_LOCATION':
        return 'Fake location detected';
      case 'OUT_OF_RANGE':
        return 'You are not at the branch';
      case 'WIFI_NOT_ALLOWED':
        return 'Connect to office Wi-Fi';
      case 'IP_NOT_ALLOWED':
        return 'Use the office network';
      case 'DEVICE_NOT_APPROVED':
        return 'Phone not approved';
      case 'WRONG_BRANCH':
        return 'Wrong branch QR';
      case 'INVALID_QR':
        return 'Invalid QR code';
      case 'QR_EXPIRED':
        return 'QR code expired';
      case 'TOO_SOON':
        return 'Just checked in';
      case 'TOO_EARLY':
        return 'Shift not started yet';
      case 'ALREADY_CHECKED_OUT':
        return 'Already done for today';
      case 'MARKED_ABSENT':
        return 'Marked absent';
      case 'NETWORK':
        return 'No connection';
      case 'NO_BIOMETRIC_ENROLLED':
      case 'BIOMETRIC_REQUIRED':
        return 'Register your fingerprint';
      case 'BIOMETRIC_CHANGED':
        return 'Fingerprint changed';
      case 'BIOMETRIC_FAILED':
        return 'Fingerprint not confirmed';
      case 'CHALLENGE_EXPIRED':
        return 'Confirm your fingerprint again';
      case 'ENROLL_NOT_ALLOWED':
        return 'Already registered';
      default:
        return 'Can\'t check in';
    }
  }

  dynamic _blockedIcon(String code) {
    switch (code) {
      case 'LOCATION_OFF':
      case 'LOCATION_DENIED':
      case 'LOCATION_DENIED_FOREVER':
      case 'NO_FIX':
      case 'LOW_ACCURACY':
      case 'MOCK_LOCATION':
      case 'OUT_OF_RANGE':
        return _I.branch;
      case 'WIFI_NOT_ALLOWED':
      case 'IP_NOT_ALLOWED':
      case 'NETWORK':
        return _I.wifiOff;
      case 'INVALID_QR':
      case 'QR_EXPIRED':
      case 'WRONG_BRANCH':
        return _I.qr;
      case 'TOO_SOON':
      case 'TOO_EARLY':
        return _I.clock;
      default:
        return _I.alert;
    }
  }

  Color _blockedTone(String code) {
    switch (code) {
      case 'MOCK_LOCATION':
      case 'MARKED_ABSENT':
      case 'BIOMETRIC_CHANGED':
      case 'BIOMETRIC_FAILED':
      case 'ENROLL_NOT_ALLOWED':
      case 'UNKNOWN':
        return _C.red;
      case 'TOO_SOON':
      case 'TOO_EARLY':
      case 'ALREADY_CHECKED_OUT':
        return _C.blue;
      default:
      // DEVICE_NOT_APPROVED lands here: orange because the user can act on it.
        return _C.orange;
    }
  }

  List<String> _tips(String code) {
    switch (code) {
      case 'LOCATION_OFF':
        return const ['Turn on Location (GPS) on your phone', 'Come back here, we will check again automatically'];
      case 'LOCATION_DENIED':
        return const ['Allow location access when asked', 'We only use it to confirm you are at the branch'];
      case 'LOCATION_DENIED_FOREVER':
        return const ['Open app settings', 'Set Location to "Allow" for this app'];
      case 'NO_FIX':
      case 'LOW_ACCURACY':
        return const ['Move closer to a window or step outside', 'Wait a few seconds for the GPS to lock'];
      case 'MOCK_LOCATION':
        return const ['Turn off any fake-GPS or mock-location app', 'Restart the app and try again'];
      case 'OUT_OF_RANGE':
        return const ['Go to your branch and try again'];
      case 'WIFI_NOT_ALLOWED':
        return const ['Connect your phone to the office Wi-Fi', 'Turn off mobile data if it still fails'];
      case 'IP_NOT_ALLOWED':
        return const ['Turn off VPN or mobile data', 'Use the office Wi-Fi network'];
      case 'DEVICE_NOT_APPROVED':
        return const [
          'Check-in only works from a phone HR has approved',
          'Tap "Request approval" and HR will be notified',
        ];
      case 'WRONG_BRANCH':
        return const ['Scan the QR code that belongs to your branch'];
      case 'INVALID_QR':
      case 'QR_EXPIRED':
        return const ['Scan the live QR code shown at your branch'];
      case 'TOO_EARLY':
        return const ['You can check in up to 60 minutes before a shift', 'Come back closer to the start time'];
      case 'NETWORK':
        return const ['Check your Wi-Fi or mobile data', 'Then try again'];
      case 'NO_BIOMETRIC_ENROLLED':
      case 'BIOMETRIC_REQUIRED':
        return const ['Register your fingerprint once on this phone', 'Check-in is locked to your finger'];
      case 'BIOMETRIC_CHANGED':
        return const [
          'A fingerprint was added or removed on this phone',
          'Ask HR to approve re-enrollment, then register again at the office'
        ];
      case 'BIOMETRIC_FAILED':
      case 'CHALLENGE_EXPIRED':
        return const ['Touch the sensor with your registered finger', 'Only a fingerprint works: no PIN or pattern'];
      default:
        return const [];
    }
  }

  // ───────────── build ─────────────
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _phase != _Phase.submitting,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: (_phase == _Phase.camera || _phase == _Phase.submitting)
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: KeyedSubtree(
            key: ValueKey<bool>(_phase == _Phase.camera || _phase == _Phase.submitting),
            child: _body(),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    switch (_phase) {
      case _Phase.checking:
        return _StatusView(
          tone: _C.ink,
          leading: const SizedBox(
            width: 34,
            height: 34,
            child: CircularProgressIndicator(strokeWidth: 3.2, color: _C.ink),
          ),
          title: 'Checking your location',
          subtitle: 'Confirming you are at the branch and on the office Wi-Fi.',
          onClose: _close,
        );

      case _Phase.blocked:
        return _buildBlocked();

      case _Phase.result:
        return _buildResult();

      case _Phase.camera:
      case _Phase.submitting:
        return _buildCamera();
    }
  }

  // ───────────── blocked ─────────────
  Widget _buildBlocked() {
    final f = _failure ?? AuthFailure('UNKNOWN', 'Something went wrong. Please try again.');
    final code = f.code;
    final notApproved = code == 'DEVICE_NOT_APPROVED';
    final sent = notApproved && _approvalSent;

    Color tone = _blockedTone(code);
    Widget leading = _Hi(_blockedIcon(code), size: 40, color: tone);
    String title = _blockedTitle(code);
    String subtitle = f.message;
    List<String> tips = _tips(code);

    String primaryLabel;
    VoidCallback? primary;
    String? secondaryLabel;
    VoidCallback? secondary;

    switch (code) {
      case 'LOCATION_OFF':
        primaryLabel = 'Open location settings';
        primary = () {
          _openedSettings = true;
          _service.openLocationSettings();
        };
        secondaryLabel = 'Try again';
        secondary = _runPreflight;
        break;
      case 'LOCATION_DENIED_FOREVER':
        primaryLabel = 'Open app settings';
        primary = () {
          _openedSettings = true;
          _service.openAppSettings();
        };
        secondaryLabel = 'Try again';
        secondary = _runPreflight;
        break;
      case 'DEVICE_NOT_APPROVED':
        if (sent) {
          // request is with HR now
          tone = _C.green;
          leading = const _PopIn(child: Icon(Icons.check_rounded, color: _C.green, size: 46));
          title = 'Request sent';
          subtitle = 'HR has been notified. Once they approve this phone, tap "Check again".';
          tips = const [
            'You do not need to send the request again',
            'Ask HR to approve your phone if it takes long',
          ];
          primaryLabel = 'Check again';
          primary = _runPreflight;
          secondaryLabel = 'Done';
          secondary = () => _close();
        } else {
          subtitle = _approvalError ?? f.message;
          primaryLabel = _approvalBusy ? 'Sending request…' : 'Request approval';
          primary = _approvalBusy ? null : _requestApproval;
          secondaryLabel = 'Try again';
          secondary = _approvalBusy ? null : _runPreflight;
        }
        break;
      case 'INVALID_QR':
      case 'QR_EXPIRED':
      case 'WRONG_BRANCH':
        primaryLabel = 'Scan again';
        primary = _rescan;
        break;
      case 'TOO_SOON':
      case 'TOO_EARLY':
      case 'ALREADY_CHECKED_OUT':
      case 'MARKED_ABSENT':
        primaryLabel = 'Done';
        primary = () => _close();
        break;
      case 'NO_BIOMETRIC_ENROLLED':
      case 'BIOMETRIC_REQUIRED':
        primaryLabel = 'Register fingerprint';
        primary = () async {
          final ok = await Navigator.of(context).push<bool>(
            MaterialPageRoute<bool>(builder: (_) => const EnrollFingerprintPage()),
          );
          if (ok == true) _runPreflight();
        };
        break;
      case 'BIOMETRIC_CHANGED':
      case 'ENROLL_NOT_ALLOWED':
        primaryLabel = 'Done';
        primary = () => _close();
        break;
      default:
        primaryLabel = 'Try again';
        primary = _runPreflight;
    }

    return _StatusView(
      tone: tone,
      leading: leading,
      title: title,
      subtitle: subtitle,
      tips: tips,
      primaryLabel: primaryLabel,
      onPrimary: primary,
      secondaryLabel: secondaryLabel,
      onSecondary: secondary,
      onClose: _close,
    );
  }

  // ───────────── result ─────────────
  Widget _buildResult() {
    final r = _result;
    if (r == null) {
      // preflight said every scan of the day was already recorded
      final multi = (_ctx?.shiftTotal ?? 1) > 1;
      return _StatusView(
        tone: _C.green,
        leading: const _PopIn(child: Icon(Icons.done_all_rounded, color: _C.green, size: 42)),
        title: 'All done for today',
        subtitle: multi
            ? 'All ${_ctx!.shiftTotal} of your shifts are already recorded.'
            : 'Your check-in and check-out are already recorded.',
        primaryLabel: 'Done',
        onPrimary: () => _close(),
        onClose: _close,
      );
    }

    final isIn = r.action == CheckinAction.checkIn;
    final late = r.status == 'late';
    final multi = r.isMultiShift;
    final chipColor = isIn ? (late ? _C.orange : _C.green) : _C.ink;
    final chipText = isIn
        ? (late ? 'Late ${r.lateMinutes} min' : 'On time')
        : (r.checkInMin != null ? 'In ${_fmt(r.checkInMin!)}' : 'Checked out');

    final shiftTitle = _shiftTitle(r.shiftNumber, r.shiftTotal);
    final shiftWindow = (r.shiftStartMin != null && r.shiftEndMin != null)
        ? '${_fmt(r.shiftStartMin!)} – ${_fmt(r.shiftEndMin!)}'
        : '';
    final subtitle = multi
        ? [shiftTitle, if (r.branchName.isNotEmpty) r.branchName].join(' · ')
        : (r.branchName.isEmpty ? r.message : r.branchName);

    return _StatusView(
      tone: late && isIn ? _C.orange : _C.green,
      leading: _PopIn(
        child: Icon(Icons.check_rounded, color: late && isIn ? _C.orange : _C.green, size: 46),
      ),
      title: isIn ? 'Checked in' : 'Checked out',
      subtitle: subtitle,
      body: Column(
        children: [
          Text(
            _fmt(r.timeMin),
            style: const TextStyle(
                fontFamily: _T.f, fontSize: 40, fontWeight: FontWeight.w700, color: _C.ink, height: 1.2),
          ),
          const SizedBox(height: 14),
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _tint(chipColor, 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: chipColor, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text(
                  chipText,
                  style: TextStyle(
                      fontFamily: _T.f, fontSize: 13, fontWeight: FontWeight.w600, color: chipColor),
                ),
              ],
            ),
          ),
          if (multi) ...[
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(color: _C.card, borderRadius: BorderRadius.circular(20)),
              child: Column(
                children: [
                  if (shiftWindow.isNotEmpty)
                    Text('${_shiftTitle(r.shiftNumber, r.shiftTotal)} · $shiftWindow',
                        textAlign: TextAlign.center, style: _T.bodyStrong),
                  if (!isIn) ...[
                    if (shiftWindow.isNotEmpty) const SizedBox(height: 4),
                    Text(
                      '${r.shiftsDone} of ${r.shiftTotal} shifts complete',
                      textAlign: TextAlign.center,
                      style: _T.caption.copyWith(fontSize: 13),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
      primaryLabel: 'Done',
      onPrimary: () => _close(true),
      onClose: () => _close(true),
    );
  }

  // ───────────── camera ─────────────
  Widget _buildCamera() {
    final submitting = _phase == _Phase.submitting;
    final isOut = _ctx?.next == CheckinAction.checkOut;
    final shiftLabel = _shiftTitle(_ctx?.shiftNumber, _ctx?.shiftTotal ?? 1);
    final barTitle = '${isOut ? 'Check out' : 'Check in'}${shiftLabel.isEmpty ? '' : ' · $shiftLabel'}';

    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          final h = c.maxHeight;
          final side = math.min(w * 0.72, 300.0);
          final frame = Rect.fromCenter(
            center: Offset(w / 2, h * 0.45),
            width: side,
            height: side,
          );

          return Stack(
            fit: StackFit.expand,
            children: [
              if (_scanner != null)
                MobileScanner(
                  controller: _scanner!,
                  onDetect: _onDetect,
                  errorBuilder: (context, error, child) => _StatusView(
                    tone: _C.red,
                    leading: const Icon(Icons.no_photography_outlined, color: _C.red, size: 38),
                    title: 'Camera not available',
                    subtitle: 'Allow camera access in your phone settings to scan the QR code.',
                    primaryLabel: 'Open app settings',
                    onPrimary: () {
                      _openedSettings = false;
                      _service.openAppSettings();
                    },
                    secondaryLabel: 'Go back',
                    onSecondary: () => _close(),
                    onClose: _close,
                  ),
                ),

              // dark overlay with rounded hole
              IgnorePointer(
                child: CustomPaint(
                  size: Size(w, h),
                  painter: _OverlayPainter(cutout: frame, radius: 28),
                ),
              ),

              // frame border
              Positioned.fromRect(
                rect: frame,
                child: IgnorePointer(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: submitting ? _C.green : Colors.white.withAlpha(90),
                        width: submitting ? 3 : 1.5,
                      ),
                    ),
                  ),
                ),
              ),
              ..._corners(frame, submitting),

              // scan line
              if (!submitting)
                Positioned.fromRect(
                  rect: frame,
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _lineCtrl,
                      builder: (context, _) {
                        final t = Curves.easeInOut.transform(_lineCtrl.value);
                        return Stack(
                          children: [
                            Positioned(
                              left: 20,
                              right: 20,
                              top: 20 + t * (frame.height - 44),
                              child: Container(
                                height: 3,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(2),
                                  boxShadow: [
                                    BoxShadow(color: Colors.white.withAlpha(130), blurRadius: 10),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),

              // submitting spinner
              if (submitting)
                Positioned.fromRect(
                  rect: frame,
                  child: IgnorePointer(
                    child: Center(
                      child: Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(120),
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: SizedBox(
                            width: 36,
                            height: 36,
                            child: CircularProgressIndicator(strokeWidth: 3.5, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              // bottom status pill (only when there is something to say)
              Positioned(
                left: 24,
                right: 24,
                bottom: 0,
                child: IgnorePointer(
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 32),
                      child: Center(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          transitionBuilder: (child, anim) => FadeTransition(
                            opacity: anim,
                            child: SlideTransition(
                              position: Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero)
                                  .animate(anim),
                              child: child,
                            ),
                          ),
                          child: _bottomPill(submitting),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // TOP BAR — last in the stack so it always receives touches
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
                        _RoundButton(
                          icon: _Hi(_I.close, size: 22, color: Colors.white),
                          semantic: 'Close',
                          enabled: !submitting,
                          onTap: () => _close(),
                        ),
                        Expanded(
                          child: Text(
                            barTitle,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: _T.f,
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        _RoundButton(
                          icon: Icon(
                            _torchOn ? Icons.flashlight_on_rounded : Icons.flashlight_off_rounded,
                            size: 22,
                            color: _torchOn ? _C.ink : Colors.white,
                          ),
                          semantic: 'Torch',
                          active: _torchOn,
                          enabled: !submitting,
                          onTap: _toggleTorch,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _bottomPill(bool submitting) {
    if (_scanHint != null) {
      return _Pill(
        key: ValueKey('hint_$_scanHint'),
        color: _C.red,
        textColor: Colors.white,
        icon: const _Hi(_I.alert, size: 18, color: Colors.white),
        text: _scanHint!,
      );
    }
    if (submitting) {
      return const _Pill(
        key: ValueKey('submitting'),
        color: _C.green,
        textColor: Colors.white,
        icon: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
        ),
        text: 'Recording…',
      );
    }
    final ctx = _ctx;
    if (ctx != null && ctx.branchName.isNotEmpty) {
      final window = (ctx.isMultiShift && ctx.shiftStartMin != null && ctx.shiftEndMin != null)
          ? '${_fmt(ctx.shiftStartMin!)} – ${_fmt(ctx.shiftEndMin!)}'
          : null;
      return _Pill(
        key: ValueKey('branch_${ctx.shiftNumber}'),
        color: Colors.black.withAlpha(140),
        textColor: Colors.white,
        icon: Icon(window != null ? Icons.schedule_rounded : Icons.place_outlined, size: 16, color: Colors.white),
        text: window ?? '${ctx.branchName} · ${ctx.distanceM} m',
      );
    }
    return const SizedBox.shrink(key: ValueKey('empty'));
  }

  List<Widget> _corners(Rect f, bool ok) {
    const double len = 38;
    const double thick = 5;
    const double r = 28;
    final color = ok ? _C.green : Colors.white;

    Widget corner({
      required double left,
      required double top,
      required bool isTop,
      required bool isLeft,
    }) {
      return Positioned(
        left: left,
        top: top,
        child: IgnorePointer(
          child: Container(
            width: len,
            height: len,
            decoration: BoxDecoration(
              border: Border(
                top: isTop ? BorderSide(color: color, width: thick) : BorderSide.none,
                bottom: !isTop ? BorderSide(color: color, width: thick) : BorderSide.none,
                left: isLeft ? BorderSide(color: color, width: thick) : BorderSide.none,
                right: !isLeft ? BorderSide(color: color, width: thick) : BorderSide.none,
              ),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(isTop && isLeft ? r : 0),
                topRight: Radius.circular(isTop && !isLeft ? r : 0),
                bottomLeft: Radius.circular(!isTop && isLeft ? r : 0),
                bottomRight: Radius.circular(!isTop && !isLeft ? r : 0),
              ),
            ),
          ),
        ),
      );
    }

    return [
      corner(left: f.left, top: f.top, isTop: true, isLeft: true),
      corner(left: f.right - len, top: f.top, isTop: true, isLeft: false),
      corner(left: f.left, top: f.bottom - len, isTop: false, isLeft: true),
      corner(left: f.right - len, top: f.bottom - len, isTop: false, isLeft: false),
    ];
  }
}

// ════════════════════════════════════════════════════════════════════
//  STATUS VIEW (checking / blocked / result / camera error)
//  Close button on top, content centered, actions anchored at bottom.
// ════════════════════════════════════════════════════════════════════
class _StatusView extends StatelessWidget {
  const _StatusView({
    required this.tone,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.onClose,
    this.body,
    this.tips = const [],
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  final Color tone;
  final Widget leading;
  final String title;
  final String subtitle;
  final VoidCallback onClose;
  final Widget? body;
  final List<String> tips;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Material(
                  color: _C.card,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onClose,
                    child: const SizedBox(
                      width: 48,
                      height: 48,
                      child: Center(child: _Hi(_I.close, size: 22)),
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
                            width: 88,
                            height: 88,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _tint(tone, 0.14),
                              shape: BoxShape.circle,
                            ),
                            child: leading,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(title, textAlign: TextAlign.center, style: _T.title),
                        const SizedBox(height: 8),
                        Text(subtitle, textAlign: TextAlign.center, style: _T.body),
                        if (body != null) ...[
                          const SizedBox(height: 28),
                          body!,
                        ],
                        if (tips.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          Container(
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                            decoration: BoxDecoration(
                              color: _C.card,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (int i = 0; i < tips.length; i++) ...[
                                  if (i > 0) const SizedBox(height: 10),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: _Hi(_I.info, size: 16, color: tone),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          tips[i],
                                          style: _T.bodyStrong.copyWith(fontSize: 13, fontWeight: FontWeight.w500),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
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
            if (primaryLabel != null || secondaryLabel != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (primaryLabel != null)
                        SizedBox(
                          height: 54,
                          child: ElevatedButton(
                            onPressed: onPrimary,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _C.ink,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: _C.ink.withAlpha(150),
                              disabledForegroundColor: Colors.white70,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                            ),
                            child: Text(primaryLabel!, style: _T.button),
                          ),
                        ),
                      if (secondaryLabel != null) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 48,
                          child: TextButton(
                            onPressed: onSecondary,
                            style: TextButton.styleFrom(foregroundColor: _C.ink),
                            child: Text(
                              secondaryLabel!,
                              style: const TextStyle(
                                  fontFamily: _T.f, fontSize: 14, fontWeight: FontWeight.w700, color: _C.ink),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  Success pop-in animation
// ════════════════════════════════════════════════════════════════════
class _PopIn extends StatelessWidget {
  const _PopIn({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.4, end: 1),
      duration: const Duration(milliseconds: 520),
      curve: Curves.elasticOut,
      builder: (context, v, child) => Transform.scale(scale: v, child: child),
      child: child,
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  Bottom pill (hint / recording / branch / shift window)
// ════════════════════════════════════════════════════════════════════
class _Pill extends StatelessWidget {
  const _Pill({
    super.key,
    required this.color,
    required this.textColor,
    required this.icon,
    required this.text,
  });

  final Color color;
  final Color textColor;
  final Widget icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontFamily: _T.f, fontSize: 14, fontWeight: FontWeight.w600, color: textColor),
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════
//  Dark overlay with a rounded hole
// ════════════════════════════════════════════════════════════════════
class _OverlayPainter extends CustomPainter {
  _OverlayPainter({required this.cutout, required this.radius});

  final Rect cutout;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final background = Path()..addRect(Offset.zero & size);
    final hole = Path()..addRRect(RRect.fromRectAndRadius(cutout, Radius.circular(radius)));
    final overlay = Path.combine(PathOperation.difference, background, hole);
    canvas.drawPath(overlay, Paint()..color = Colors.black.withAlpha(158));
  }

  @override
  bool shouldRepaint(covariant _OverlayPainter old) =>
      old.cutout != cutout || old.radius != radius;
}

// ════════════════════════════════════════════════════════════════════
//  Round icon button (close / torch) — 52px touch target
// ════════════════════════════════════════════════════════════════════
class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.onTap,
    required this.semantic,
    this.active = false,
    this.enabled = true,
  });

  final Widget icon;
  final VoidCallback onTap;
  final String semantic;
  final bool active;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: enabled,
      label: semantic,
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: Material(
          color: active ? Colors.white : Colors.black.withAlpha(140),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled ? onTap : null,
            child: SizedBox(width: 52, height: 52, child: Center(child: icon)),
          ),
        ),
      ),
    );
  }
}