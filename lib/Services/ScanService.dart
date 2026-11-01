// lib/Services/ScanService.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:location/location.dart' as gps;
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import '../Auth/AuthService.dart';
import 'BiometrricService.dart';

enum CheckinAction { checkIn, checkOut, done }

class DeviceFacts {
  const DeviceFacts({
    required this.lat,
    required this.lng,
    required this.accuracyM,
    required this.isMocked,
    required this.wifiBssid,
    this.wifiSsid,
  });

  final double lat;
  final double lng;
  final double accuracyM;
  final bool isMocked;

  /// BSSID of the access point the phone is connected to right now.
  /// A phone is on exactly ONE access point, so this is a single value.
  /// The server matches it against ALL rows of the branch in `branch_wifi`.
  final String? wifiBssid;

  /// Network name, for logging / optional server fallback only.
  final String? wifiSsid;

  Map<String, dynamic> toJson() => {
    'lat': lat,
    'lng': lng,
    'accuracy_m': accuracyM,
    'is_mocked': isMocked,
    'wifi_bssid': wifiBssid,
    'wifi_ssid': wifiSsid,
  };
}

class ScanContextInfo {
  const ScanContextInfo({
    required this.next,
    required this.branchName,
    required this.distanceM,
    required this.radiusM,
    this.shiftNumber,
    this.shiftTotal = 1,
    this.shiftStartMin,
    this.shiftEndMin,
    this.shiftsDone = 0,
  });

  final CheckinAction next;
  final String branchName;
  final int distanceM;
  final int radiusM;

  /// Which shift the next scan belongs to (1-based). Null when everything is done.
  final int? shiftNumber;
  final int shiftTotal;
  final int? shiftStartMin;
  final int? shiftEndMin;
  final int shiftsDone;

  bool get isMultiShift => shiftTotal > 1;
}

class QrPayload {
  const QrPayload({required this.type, required this.secret, this.branchId});

  final String type; // 'static' | 'live'
  final String secret;
  final String? branchId;
}

class CheckinResult {
  const CheckinResult({
    required this.action,
    required this.message,
    required this.timeMin,
    required this.checkInMin,
    required this.status,
    required this.lateMinutes,
    required this.branchName,
    this.shiftNumber = 1,
    this.shiftTotal = 1,
    this.shiftStartMin,
    this.shiftEndMin,
    this.shiftsDone = 0,
  });

  final CheckinAction action;
  final String message;
  final int timeMin;
  final int? checkInMin;
  final String status; // present | late
  final int lateMinutes;
  final String branchName;
  final int shiftNumber;
  final int shiftTotal;
  final int? shiftStartMin;
  final int? shiftEndMin;

  /// Shifts fully completed today, counting the one this scan just closed.
  final int shiftsDone;

  bool get isMultiShift => shiftTotal > 1;
}

class _WifiInfo {
  const _WifiInfo({this.bssid, this.ssid});
  final String? bssid;
  final String? ssid;
}

int? _int(dynamic v) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

class ScanService {
  ScanService._();
  static final ScanService instance = ScanService._();

  static final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  static final RegExp _liveToken = RegExp(r'^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$');
  static final RegExp _bssid = RegExp(r'^([0-9A-F]{2}:){5}[0-9A-F]{2}$');

  /// The server challenge lives 60 s. If the fingerprint proof is older than this
  /// when the QR is scanned, the finger is asked for again.
  static const Duration _proofMaxAge = Duration(seconds: 40);

  /// Wi-Fi BSSID read: Android sometimes returns null on the first call.
  static const int _wifiReadAttempts = 3;
  static const Duration _wifiRetryDelay = Duration(milliseconds: 400);

  BioProof? _proof;

  // ───────────── Wi-Fi helpers ─────────────

  /// Normalizes any BSSID format to `AA:BB:CC:DD:EE:FF`.
  /// Handles lowercase, dashes and missing zero-padding (`a:b:c:d:e:f`).
  /// Returns null for invalid or placeholder values.
  static String? normalizeBssid(String? raw) {
    if (raw == null) return null;
    final cleaned = raw.trim().toUpperCase().replaceAll('-', ':');
    if (cleaned.isEmpty) return null;

    final parts = cleaned.split(':');
    if (parts.length != 6) return null;
    final padded = parts.map((p) => p.length == 1 ? '0$p' : p).join(':');

    if (!_bssid.hasMatch(padded)) return null;
    if (padded == '02:00:00:00:00:00' || padded == '00:00:00:00:00:00') return null;
    return padded;
  }

  static String? _cleanSsid(String? raw) {
    if (raw == null) return null;
    var s = raw.trim();
    if (s.length >= 2 && s.startsWith('"') && s.endsWith('"')) {
      s = s.substring(1, s.length - 1);
    }
    if (s.isEmpty || s == '<unknown ssid>' || s == '0x') return null;
    return s;
  }

  /// Reads the connected access point (BSSID + SSID), retrying a few times
  /// because the first read right after permission grant can be empty.
  Future<_WifiInfo> _readWifi() async {
    final info = NetworkInfo();
    String? bssid;
    String? ssid;

    for (int attempt = 1; attempt <= _wifiReadAttempts; attempt++) {
      try {
        bssid = normalizeBssid(await info.getWifiBSSID());
        ssid = _cleanSsid(await info.getWifiName());
      } catch (e) {
        debugPrint('📶❌ Wi-Fi read attempt $attempt failed: $e');
      }
      if (bssid != null) break;
      if (attempt < _wifiReadAttempts) {
        debugPrint('📶⏳ BSSID empty on attempt $attempt, retrying…');
        await Future.delayed(_wifiRetryDelay);
      }
    }

    debugPrint('📶 Connected Wi-Fi → ssid=$ssid bssid=$bssid');
    return _WifiInfo(bssid: bssid, ssid: ssid);
  }

  // ───────────── device facts (location + Wi-Fi) ─────────────
  static const double _goodEnough = 25; // m: stop waiting for a better fix
  final gps.Location _gps = gps.Location();

  Future<DeviceFacts> collectFacts() async {
    bool serviceOn = await _gps.serviceEnabled();
    if (!serviceOn) serviceOn = await _gps.requestService();
    if (!serviceOn) {
      debugPrint('📍❌ Location service is off');
      throw AuthFailure('LOCATION_OFF', 'Turn on your phone location (GPS) to check in.');
    }

    var perm = await _gps.hasPermission();
    if (perm == gps.PermissionStatus.denied) perm = await _gps.requestPermission();
    if (perm == gps.PermissionStatus.deniedForever) {
      debugPrint('📍❌ Location permission denied forever');
      throw AuthFailure(
        'LOCATION_DENIED_FOREVER',
        'Location permission is blocked. Allow it in app settings to check in.',
      );
    }
    if (perm == gps.PermissionStatus.denied) {
      debugPrint('📍❌ Location permission denied');
      throw AuthFailure('LOCATION_DENIED', 'Allow location access to check in.');
    }

    // Wi-Fi needs location permission on Android, so start it now and let it
    // run while the GPS is locking: no extra waiting.
    final wifiFuture = _readWifi();

    gps.LocationData? best;
    bool sawMock = false;
    StreamSubscription<gps.LocationData>? sub;
    final done = Completer<void>();
    try {
      await _gps.changeSettings(
        accuracy: gps.LocationAccuracy.high,
        interval: 1000,
        distanceFilter: 0,
      );
      sub = _gps.onLocationChanged.listen(
            (d) {
          final lat = d.latitude;
          final lng = d.longitude;
          if (lat == null || lng == null || (lat == 0 && lng == 0)) return;
          if (d.isMock ?? false) {
            sawMock = true;
            return;
          }
          final t = d.time;
          if (t != null && t > 0) {
            final ageSec = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(t.round())).inSeconds;
            if (ageSec > 20 && ageSec < 600) return;
          }
          final acc = d.accuracy ?? 999;
          if (best == null || acc < (best!.accuracy ?? 999)) best = d;
          if (acc <= _goodEnough && !done.isCompleted) done.complete();
        },
        onError: (Object _) {
          if (!done.isCompleted) done.complete();
        },
      );
      await done.future.timeout(const Duration(seconds: 10), onTimeout: () {});
    } catch (e) {
      debugPrint('📍⚠️ GPS stream failed, falling back to single read: $e');
    } finally {
      await sub?.cancel();
    }

    if (best == null && !sawMock) {
      try {
        final d = await _gps.getLocation().timeout(const Duration(seconds: 6));
        if (d.latitude != null && d.longitude != null && !(d.isMock ?? false)) best = d;
        if (d.isMock ?? false) sawMock = true;
      } catch (e) {
        debugPrint('📍⚠️ Single GPS read failed: $e');
      }
    }

    if (sawMock && best == null) {
      debugPrint('📍🚫 Mock location detected');
      throw AuthFailure('MOCK_LOCATION', 'Fake location detected. Turn off mock location apps.');
    }
    final fix = best;
    if (fix == null || fix.latitude == null || fix.longitude == null) {
      debugPrint('📍❌ No GPS fix');
      throw AuthFailure('NO_FIX', 'Could not get your location. Move to an open area and try again.');
    }

    final wifi = await wifiFuture;

    final facts = DeviceFacts(
      lat: fix.latitude!,
      lng: fix.longitude!,
      accuracyM: (fix.accuracy != null && fix.accuracy! > 0) ? fix.accuracy! : 999,
      isMocked: fix.isMock ?? false,
      wifiBssid: wifi.bssid,
      wifiSsid: wifi.ssid,
    );
    debugPrint(
      '📍✅ Facts ready → lat=${facts.lat} lng=${facts.lng} acc=${facts.accuracyM}m '
          'bssid=${facts.wifiBssid} ssid=${facts.wifiSsid}',
    );
    return facts;
  }

  Future<void> openLocationSettings() async {
    await _gps.requestService();
  }

  Future<void> openAppSettings() => ph.openAppSettings();

  // ───────────── before the camera: right place, then the right finger ─────────────
  Future<ScanContextInfo> preflight() async {
    _proof = null;
    debugPrint('🚦 Preflight started');

    final facts = await collectFacts();
    final json = await AuthService.instance.callFunction('checkin', {
      'action': 'preflight',
      ...facts.toJson(),
      'device_id': await AuthService.instance.deviceId(),
    });
    final CheckinAction next;
    switch (json['next_action']) {
      case 'check_out':
        next = CheckinAction.checkOut;
        break;
      case 'done':
        next = CheckinAction.done;
        break;
      default:
        next = CheckinAction.checkIn;
    }
    final ctx = ScanContextInfo(
      next: next,
      branchName: json['branch_name']?.toString() ?? '',
      distanceM: _int(json['distance_m']) ?? 0,
      radiusM: _int(json['radius_m']) ?? 0,
      shiftNumber: _int(json['shift_number']),
      shiftTotal: _int(json['shift_total']) ?? 1,
      shiftStartMin: _int(json['shift_start_min']),
      shiftEndMin: _int(json['shift_end_min']),
      shiftsDone: _int(json['shifts_done']) ?? 0,
    );
    debugPrint('🚦✅ Preflight OK → next=$next shift=${ctx.shiftNumber}/${ctx.shiftTotal} '
        'branch=${ctx.branchName} dist=${ctx.distanceM}m/${ctx.radiusM}m');

    // Place is fine: now the fingerprint, BEFORE the camera opens.
    if (next != CheckinAction.done) {
      _proof = await BiometricService.instance.proveIdentity(
        subtitle: next == CheckinAction.checkOut ? 'Confirm to check out' : 'Confirm to check in',
      );
      debugPrint('🔐✅ Fingerprint proof ready');
    }
    return ctx;
  }

  // ───────────── QR parsing ─────────────
  /// Static: xaadir://checkin?b=<branch-id>&t=<static-secret>
  /// Live:   a signed token "payload.signature" (raw, or xaadir://checkin?live=<token>)
  QrPayload parseQr(String raw) {
    final text = raw.trim();
    final bad = AuthFailure('INVALID_QR', 'This is not a Xaadir QR code.');

    final uri = Uri.tryParse(text);
    if (uri != null && uri.scheme == 'xaadir' && uri.host == 'checkin') {
      final b = uri.queryParameters['b'];
      final t = uri.queryParameters['t'];
      final live = uri.queryParameters['live'];
      if (b != null && t != null && _uuid.hasMatch(b) && t.length >= 8 && t.length <= 1024) {
        return QrPayload(type: 'static', secret: t, branchId: b);
      }
      if (live != null && _liveToken.hasMatch(live) && live.length <= 1024) {
        return QrPayload(type: 'live', secret: live);
      }
      debugPrint('🔳❌ Invalid xaadir QR');
      throw bad;
    }
    if (_liveToken.hasMatch(text) && text.length <= 1024) {
      return QrPayload(type: 'live', secret: text);
    }
    debugPrint('🔳❌ QR not recognised');
    throw bad;
  }

  // ───────────── scan → check-in / check-out ─────────────
  /// The server decides which shift this scan belongs to; nothing shift-related
  /// is sent from the phone, so it cannot be tampered with.
  Future<CheckinResult> submit(QrPayload qr, DeviceFacts facts) async {
    // Fresh fingerprint proof (the server burns each challenge, so one proof = one attempt).
    var proof = _proof;
    _proof = null;
    if (proof == null || proof.age > _proofMaxAge) {
      debugPrint('🔐 Proof missing or older than ${_proofMaxAge.inSeconds}s, asking finger again');
      proof = await BiometricService.instance.proveIdentity(subtitle: 'Confirm to continue');
    }

    debugPrint('📤 Submitting scan → qr=${qr.type} bssid=${facts.wifiBssid} ssid=${facts.wifiSsid}');
    final json = await AuthService.instance.callFunction('checkin', {
      'action': 'scan',
      'qr_type': qr.type,
      if (qr.branchId != null) 'branch_id': qr.branchId,
      'qr_secret': qr.secret,
      ...facts.toJson(),
      'device_id': await AuthService.instance.deviceId(),
      'device_name': await AuthService.instance.deviceName(),
      'challenge_id': proof.challengeId,
      'signature': proof.signature,
    });
    final result = CheckinResult(
      action: json['action'] == 'check_out' ? CheckinAction.checkOut : CheckinAction.checkIn,
      message: json['message']?.toString() ?? '',
      timeMin: _int(json['time_min']) ?? 0,
      checkInMin: _int(json['check_in_min']),
      status: json['status']?.toString() ?? 'present',
      lateMinutes: _int(json['late_minutes']) ?? 0,
      branchName: json['branch_name']?.toString() ?? '',
      shiftNumber: _int(json['shift_number']) ?? 1,
      shiftTotal: _int(json['shift_total']) ?? 1,
      shiftStartMin: _int(json['shift_start_min']),
      shiftEndMin: _int(json['shift_end_min']),
      shiftsDone: _int(json['shifts_done']) ?? 0,
    );
    debugPrint('✅ Scan recorded → ${result.action} shift ${result.shiftNumber}/${result.shiftTotal} '
        'at ${result.timeMin} min, status=${result.status}');
    return result;
  }
}