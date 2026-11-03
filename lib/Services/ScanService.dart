// lib/Services/ScanService.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:location/location.dart' as gps;
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import '../Auth/AuthService.dart';
import 'BiometrricService.dart';

enum CheckinAction { checkIn, checkOut, done }

/// How THIS staff member proves it is them. Decided by the database (staff.check_in_method).
enum CheckInMethod { biometric, selfie }

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

  /// BSSID of the access point the phone is connected to right now (single value).
  /// The server matches it against ALL rows of the branch in `branch_wifi`.
  final String? wifiBssid;
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
    this.method = CheckInMethod.biometric,
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
  final CheckInMethod method;
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
  final int shiftsDone;

  bool get isMultiShift => shiftTotal > 1;
}

class _WifiInfo {
  const _WifiInfo({this.bssid, this.ssid, this.rawBssid});
  final String? bssid; // normalized
  final String? ssid;
  final String? rawBssid; // exactly what the phone returned (for diagnostics)
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

  /// The server challenge lives 60 s. If the proof is older than this when the QR is
  /// scanned, the biometric is asked for again.
  static const Duration _proofMaxAge = Duration(seconds: 40);

  /// A selfie taken in this scan session stays valid for a few minutes
  /// (so a mistyped / expired QR does not force a new selfie).
  static const Duration _selfieMaxAge = Duration(minutes: 5);

  static const int _wifiReadAttempts = 3;
  static const Duration _wifiRetryDelay = Duration(milliseconds: 400);

  BioProof? _proof;
  Uint8List? _selfie;
  DateTime? _selfieAt;

  /// 'fingerprint' | 'face' (set at the start of every biometric preflight, read by the UI).
  String? lastBioType;

  /// Last method the server told us.
  CheckInMethod? lastMethod;

  // ───────────── check-in method (from the database) ─────────────
  /// Asks the server how THIS staff member checks in. Always fresh: HR can change it any time.
  Future<CheckInMethod> fetchMethod() async {
    final json = await AuthService.instance.callFunction('checkin', {'action': 'method'});
    final m = json['check_in_method']?.toString() == 'selfie' ? CheckInMethod.selfie : CheckInMethod.biometric;
    lastMethod = m;
    debugPrint('🧭 Check-in method → ${m.name}');
    return m;
  }

  // ───────────── selfie ─────────────
  bool get hasFreshSelfie {
    final at = _selfieAt;
    return _selfie != null && at != null && DateTime.now().difference(at) <= _selfieMaxAge;
  }

  void setSelfie(Uint8List jpeg) {
    _selfie = jpeg;
    _selfieAt = DateTime.now();
    debugPrint('🤳 Selfie ready (${(jpeg.length / 1024).round()} KB)');
  }

  void clearSelfie() {
    _selfie = null;
    _selfieAt = null;
  }

  // ───────────── Wi-Fi helpers ─────────────
  /// Uppercase, ':' separators, every part padded to 2 digits (iOS drops leading zeros,
  /// e.g. 3c:64:cf:f1:13:4 → 3C:64:CF:F1:13:04). Returns null for empty/fake values.
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

  /// Tells the staff (and you) exactly what the phone read when the Wi-Fi check fails.
  String _wifiExplain(DeviceFacts f) {
    if (f.wifiBssid == null) {
      return Platform.isIOS
          ? 'The iPhone did not give the Wi-Fi address. Check that Location is "While Using" with Precise Location ON, and that you are connected to the office Wi-Fi.'
          : 'Could not read the Wi-Fi address. Turn Location ON and connect to the office Wi-Fi.';
    }
    return 'This Wi-Fi is not registered for this branch.\n'
        'Phone read: ${f.wifiSsid ?? 'unknown'}\n${f.wifiBssid}\n'
        'Tell HR to add this address.';
  }

  /// Calls `checkin` and, on WIFI_NOT_ALLOWED, replaces the message with what the phone read.
  Future<Map<String, dynamic>> _checkin(Map<String, dynamic> body, DeviceFacts facts) async {
    try {
      return await AuthService.instance.callFunction('checkin', body);
    } on AuthFailure catch (e) {
      if (e.code == 'WIFI_NOT_ALLOWED') {
        debugPrint('📶🚫 Server rejected Wi-Fi → ssid=${facts.wifiSsid} bssid=${facts.wifiBssid}');
        throw AuthFailure('WIFI_NOT_ALLOWED', _wifiExplain(facts));
      }
      rethrow;
    }
  }

  /// Reads the connected access point. On iOS a null/empty BSSID means: location off,
  /// permission not "While Using", Precise Location off, or the Wi-Fi entitlement is missing.
  Future<_WifiInfo> _readWifi() async {
    final info = NetworkInfo();
    String? bssid;
    String? ssid;
    String? raw;

    // iOS only gives out SSID/BSSID when location is allowed "While Using".
    if (Platform.isIOS) {
      try {
        var st = await ph.Permission.locationWhenInUse.status;
        debugPrint('📶📍 iOS location permission → $st');
        if (st.isDenied) {
          st = await ph.Permission.locationWhenInUse.request();
          debugPrint('📶📍 iOS location permission after request → $st');
        }
      } catch (e) {
        debugPrint('📶⚠️ iOS location authorization check failed: $e');
      }
    }

    for (int attempt = 1; attempt <= _wifiReadAttempts; attempt++) {
      try {
        raw = await info.getWifiBSSID();
        bssid = normalizeBssid(raw);
        ssid = _cleanSsid(await info.getWifiName());
      } catch (e) {
        debugPrint('📶❌ Wi-Fi read attempt $attempt failed: $e');
      }
      if (bssid != null) break;
      if (attempt < _wifiReadAttempts) {
        debugPrint('📶⏳ BSSID empty on attempt $attempt (raw=$raw), retrying…');
        await Future.delayed(_wifiRetryDelay);
      }
    }

    debugPrint('📶 Connected Wi-Fi → ssid=$ssid raw=$raw bssid=$bssid');
    return _WifiInfo(bssid: bssid, ssid: ssid, rawBssid: raw);
  }

  // ───────────── device facts (location + Wi-Fi) ─────────────
  static const double _goodEnough = 25;
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
    // iOS "Precise Location" OFF → permission is "limited" → the Wi-Fi address comes back null.
    if (Platform.isIOS && perm == gps.PermissionStatus.grantedLimited) {
      debugPrint('📍❌ iOS Precise Location is off');
      throw AuthFailure(
        'LOCATION_IMPRECISE',
        'Precise Location is off. Turn it on for Xaadir so the office Wi-Fi can be read.',
      );
    }

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

  // ───────────── diagnostics (long-press the title on the scan screen) ─────────────
  /// Prints BSSID, GPS and check-in method: used for the real-iPhone test at the office.
  Future<Map<String, String>> diagnostics() async {
    final out = <String, String>{};
    out['Platform'] = Platform.isIOS ? 'iOS' : 'Android';

    CheckInMethod? method;
    try {
      method = await fetchMethod();
      out['Check-in method'] = method.name;
    } catch (e) {
      out['Check-in method'] = 'error: $e';
    }

    // Biometric details only matter (and are only shown) for biometric staff.
    if (method != CheckInMethod.selfie) {
      try {
        final bio = await BiometricService.instance.localStatus();
        out['Biometric'] = '${bio.type} (${bio.reason})';
        out['Strong biometric enrolled'] = '${bio.available}';
        out['Key exists / valid'] = '${bio.keyExists} / ${bio.keyValid}';
      } catch (e) {
        out['Biometric'] = 'error: $e';
      }
    }

    // Wi-Fi first, so it shows even when GPS fails.
    final w = await _readWifi();
    out['BSSID raw (as the phone returns it)'] = w.rawBssid ?? 'null';
    out['BSSID sent to server'] = w.bssid ??
        'null  → location off / not "While Using" / Precise off / entitlement missing';
    out['SSID'] = w.ssid ?? 'null';

    try {
      final f = await collectFacts();
      out['GPS'] = '${f.lat.toStringAsFixed(6)}, ${f.lng.toStringAsFixed(6)} (±${f.accuracyM.round()} m)';
    } on AuthFailure catch (e) {
      out['GPS'] = '${e.code}: ${e.message}';
    } catch (e) {
      out['GPS'] = 'error: $e';
    }
    return out;
  }

  // ───────────── phone not approved: ask HR ─────────────
  Future<String> requestDeviceApproval() async {
    debugPrint('📲 Requesting HR approval for this phone');
    final json = await AuthService.instance.callFunction('checkin', {
      'action': 'request_device',
      'device_id': await AuthService.instance.deviceId(),
      'device_name': await AuthService.instance.deviceName(),
    });
    final status = json['status']?.toString() ?? 'pending';
    debugPrint('📲✅ Device request → $status');
    return status;
  }

  // ───────────── before the camera ─────────────
  /// 1. Ask the database which method this staff member uses.
  /// 2. Biometric staff: strong biometric must exist on the phone.
  /// 3. Everyone: right place (GPS + Wi-Fi) is checked by the server.
  /// 4. Biometric staff: prompt now. Selfie staff: the UI opens the selfie page next.
  ///
  /// [onBiometric] fires right before the biometric prompt (biometric staff only).
  Future<ScanContextInfo> preflight({void Function(String type)? onBiometric}) async {
    _proof = null;
    clearSelfie();
    debugPrint('🚦 Preflight started');

    final method = await fetchMethod();

    // Biometric staff only: no strong biometric on the phone → block immediately (no GPS, no network).
    if (method == CheckInMethod.biometric) {
      final bio = await BiometricService.instance.localStatus();
      lastBioType = bio.type == 'face' ? 'face' : 'fingerprint';
      if (!bio.available) {
        throw AuthFailure('NO_BIOMETRIC_ENROLLED', BioText.setupRequired);
      }
    }

    final facts = await collectFacts();
    final json = await _checkin({
      'action': 'preflight',
      ...facts.toJson(),
      'device_id': await AuthService.instance.deviceId(),
    }, facts);

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
      method: method,
      branchName: json['branch_name']?.toString() ?? '',
      distanceM: _int(json['distance_m']) ?? 0,
      radiusM: _int(json['radius_m']) ?? 0,
      shiftNumber: _int(json['shift_number']),
      shiftTotal: _int(json['shift_total']) ?? 1,
      shiftStartMin: _int(json['shift_start_min']),
      shiftEndMin: _int(json['shift_end_min']),
      shiftsDone: _int(json['shifts_done']) ?? 0,
    );
    debugPrint('🚦✅ Preflight OK → method=${method.name} next=$next shift=${ctx.shiftNumber}/${ctx.shiftTotal} '
        'branch=${ctx.branchName} dist=${ctx.distanceM}m/${ctx.radiusM}m');

    // Place is fine. Biometric staff prove it is them NOW, before the camera opens.
    if (next != CheckinAction.done && method == CheckInMethod.biometric) {
      onBiometric?.call(lastBioType ?? 'fingerprint');
      _proof = await BiometricService.instance.proveIdentity(
        subtitle: next == CheckinAction.checkOut ? 'Confirm to check out' : 'Confirm to check in',
      );
      debugPrint('🔐✅ Biometric proof ready');
    }
    return ctx;
  }

  // ───────────── QR parsing ─────────────
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
  Future<CheckinResult> submit(QrPayload qr, DeviceFacts facts) async {
    final method = lastMethod ?? CheckInMethod.biometric;
    final Map<String, dynamic> proofFields;

    if (method == CheckInMethod.selfie) {
      // The selfie is the proof. Missing or too old → the UI sends the person back to the selfie page.
      final shot = _selfie;
      if (shot == null || !hasFreshSelfie) {
        clearSelfie();
        throw AuthFailure('SELFIE_REQUIRED', 'Take a new selfie to continue.');
      }
      proofFields = {'selfie_base64': base64Encode(shot)};
    } else {
      // One proof = one attempt (the server burns each challenge).
      var proof = _proof;
      _proof = null;
      if (proof == null || proof.age > _proofMaxAge) {
        debugPrint('🔐 Proof missing or older than ${_proofMaxAge.inSeconds}s, asking biometric again');
        proof = await BiometricService.instance.proveIdentity(subtitle: 'Confirm to continue');
      }
      proofFields = {'challenge_id': proof.challengeId, 'signature': proof.signature};
    }

    debugPrint('📤 Submitting scan → method=${method.name} qr=${qr.type} bssid=${facts.wifiBssid}');
    final json = await _checkin({
      'action': 'scan',
      'qr_type': qr.type,
      if (qr.branchId != null) 'branch_id': qr.branchId,
      'qr_secret': qr.secret,
      ...facts.toJson(),
      'device_id': await AuthService.instance.deviceId(),
      'device_name': await AuthService.instance.deviceName(),
      ...proofFields,
    }, facts);

    // Every scan needs a NEW selfie.
    clearSelfie();

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