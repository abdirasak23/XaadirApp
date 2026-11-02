// lib/Services/BiometrricService.dart
import 'dart:io' show Platform;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/services.dart';

import '../Auth/AuthService.dart';

enum BioGate { unknown, active, needsEnroll, noSensor, changed }

enum BioPurpose { checkin, enroll }

class BioStatus {
  const BioStatus({
    required this.available,
    required this.reason,
    required this.keyExists,
    required this.keyValid,
    this.type = 'none',
  });

  /// A strong biometric is enrolled on the phone (Android BIOMETRIC_STRONG, iOS Face ID / Touch ID).
  final bool available;

  /// OK | NO_HARDWARE | NONE_ENROLLED | HW_UNAVAILABLE | UPDATE_REQUIRED | UNSUPPORTED
  final String reason;
  final bool keyExists;
  final bool keyValid;

  /// 'fingerprint' | 'face' | 'none'  (detected by the OS, never guessed from the model)
  final String type;

  bool get isFace => type == 'face';
}

/// All user-facing biometric text (English + Somali) in one place.
class BioText {
  BioText._();

  static bool get _so => PlatformDispatcher.instance.locale.languageCode.toLowerCase() == 'so';

  static String get setupRequired => _so
      ? 'Ku dhis faraha (Android) ama Face ID / Touch ID (iPhone) dejinta taleefankaaga, kadibna mar kale isku day.'
      : 'Set up a fingerprint (Android) or Face ID / Touch ID (iPhone) in your phone settings, then try again.';

  /// Short name: "Face ID", "Touch ID", "Fingerprint", "Face unlock".
  static String name(String type) {
    if (type == 'face') return Platform.isIOS ? 'Face ID' : 'Face unlock';
    return Platform.isIOS ? 'Touch ID' : 'Fingerprint';
  }

  static String scanTitle(String type) {
    if (type == 'face') {
      final n = Platform.isIOS ? 'Face ID' : 'Face unlock';
      return _so ? 'Fiiri taleefankaaga ($n)' : 'Look at your phone ($n)';
    }
    if (Platform.isIOS) {
      return _so ? 'Faraha ku dheji sensor-ka (Touch ID)' : 'Scan your fingerprint (Touch ID)';
    }
    return _so ? 'Faraha ku dheji sensor-ka' : 'Scan your fingerprint';
  }

  static String registerTitle(String type) =>
      _so ? 'Diiwaangeli ${name(type)}' : 'Register ${name(type)}';
}

/// Proof that the enrolled biometric just signed a fresh server challenge.
class BioProof {
  BioProof({required this.challengeId, required this.signature}) : at = DateTime.now();

  final String challengeId;
  final String signature;
  final DateTime at;

  Duration get age => DateTime.now().difference(at);
}

class _Challenge {
  const _Challenge(this.id, this.value);
  final String id;
  final String value;
}

/// Biometric-bound key. Android: Keystore (Kotlin). iOS: Secure Enclave (Swift).
/// Only the phone's own enrolled biometric unlocks it: no PIN, pattern or password fallback.
class BiometricService {
  BiometricService._();
  static final BiometricService instance = BiometricService._();

  static const MethodChannel _ch = MethodChannel('xaadir/biometric');

  AuthService get _auth => AuthService.instance;

  // ───────────── local phone state ─────────────
  Future<BioStatus> localStatus() async {
    try {
      final m = await _ch.invokeMapMethod<String, dynamic>('status');
      final available = m?['available'] == true;
      var type = m?['type']?.toString() ?? 'none';
      if (type != 'face' && type != 'fingerprint') type = available ? 'fingerprint' : 'none';
      return BioStatus(
        available: available,
        reason: m?['reason']?.toString() ?? 'UNSUPPORTED',
        keyExists: m?['keyExists'] == true,
        keyValid: m?['keyValid'] == true,
        type: type,
      );
    } on MissingPluginException {
      return const BioStatus(available: false, reason: 'UNSUPPORTED', keyExists: false, keyValid: false);
    } on PlatformException {
      return const BioStatus(available: false, reason: 'UNSUPPORTED', keyExists: false, keyValid: false);
    }
  }

  // ───────────── server state ─────────────
  /// 'none' | 'active' | 'invalidated'
  Future<String> serverStatus() async {
    final j = await _auth.callFunction('enroll-biometric', {
      'action': 'status',
      'device_id': await _auth.deviceId(),
    });
    return j['biometric_status']?.toString() ?? 'none';
  }

  /// One answer for the UI: can this staff member check in right now?
  Future<BioGate> gate() async {
    final local = await localStatus();
    final server = await serverStatus();
    if (server == 'invalidated') return BioGate.changed;
    if (!local.available) return BioGate.noSensor;
    if (server == 'none') return BioGate.needsEnroll;
    if (!local.keyExists || !local.keyValid) return BioGate.changed;
    return BioGate.active;
  }

  // ───────────── enrollment ─────────────
  /// Creates the key pair, proves possession behind the biometric prompt, registers the public key.
  Future<void> enroll() async {
    final local = await localStatus();
    if (!local.available) throw _noBiometric();

    final server = await serverStatus();
    if (server == 'invalidated') throw _changed();
    if (server == 'active') {
      throw AuthFailure(
        'ENROLL_NOT_ALLOWED',
        'A biometric is already registered on this phone. Ask HR to approve re-enrollment.',
      );
    }

    final deviceId = await _auth.deviceId();
    final ch = await _challenge();

    final String publicKey;
    try {
      final k = await _ch.invokeMethod<String>('createKey');
      if (k == null || k.isEmpty) throw PlatformException(code: 'KEY_ERROR');
      publicKey = k;
    } on PlatformException {
      throw AuthFailure('BIOMETRIC_FAILED', 'Could not create the secure key on this phone.');
    }

    try {
      final signature = await _sign(
        'xaadir:enroll:${ch.id}:${ch.value}:$deviceId',
        'Confirm to register',
      );
      await _auth.callFunction('enroll-biometric', {
        'action': 'enroll',
        'device_id': deviceId,
        'device_name': await _auth.deviceName(),
        'challenge_id': ch.id,
        'public_key': publicKey,
        'signature': signature,
        'biometric_type': local.type == 'face' ? 'face' : 'fingerprint',
      });
    } catch (_) {
      await _deleteKeySilently(); // keep phone and server in step
      rethrow;
    }
  }

  // ───────────── check-in proof ─────────────
  Future<BioProof> proveIdentity({String subtitle = 'Confirm to continue'}) async {
    final local = await localStatus();
    if (!local.available) throw _noBiometric();

    // The server already accepted this phone as "active" before we got here,
    // so a missing / dead key means the enrolled biometrics changed (or the app was reinstalled).
    if (!local.keyExists || !local.keyValid) {
      await _reportInvalidated();
      throw _changed();
    }

    final deviceId = await _auth.deviceId();
    final ch = await _challenge();
    final signature = await _sign('xaadir:checkin:${ch.id}:${ch.value}:$deviceId', subtitle);
    return BioProof(challengeId: ch.id, signature: signature);
  }

  // ───────────── internals ─────────────
  Future<_Challenge> _challenge() async {
    final j = await _auth.callFunction('checkin-challenge', <String, dynamic>{});
    final id = j['challenge_id']?.toString();
    final value = j['challenge']?.toString();
    if (id == null || value == null) {
      throw AuthFailure('SERVER_ERROR', 'Something went wrong. Please try again.');
    }
    return _Challenge(id, value);
  }

  Future<String> _sign(String payload, String subtitle) async {
    try {
      final s = await _ch.invokeMethod<String>('sign', {
        'payload': payload,
        'title': 'Confirm it\'s you',
        'subtitle': subtitle,
      });
      if (s == null || s.isEmpty) {
        throw AuthFailure('BIOMETRIC_FAILED', 'Could not confirm it is you. Try again.');
      }
      return s;
    } on PlatformException catch (e) {
      switch (e.code) {
        case 'KEY_INVALIDATED':
          await _reportInvalidated();
          throw _changed();
        case 'NO_KEY':
          throw AuthFailure('BIOMETRIC_REQUIRED', 'Register your biometric to check in.');
        case 'NONE_ENROLLED':
          throw _noBiometric();
        case 'CANCELLED':
          throw AuthFailure('BIOMETRIC_FAILED', 'The check was cancelled.');
        case 'LOCKED_OUT':
          throw AuthFailure(
            'BIOMETRIC_FAILED',
            'Too many wrong attempts. Wait a moment (or unlock your phone once), then try again.',
          );
        default:
          throw AuthFailure('BIOMETRIC_FAILED', 'Could not confirm it is you. Try again.');
      }
    }
  }

  /// Tells the server the key is dead. The function always answers BIOMETRIC_CHANGED,
  /// so the error is expected and ignored here.
  Future<void> _reportInvalidated() async {
    try {
      await _auth.callFunction('enroll-biometric', {
        'action': 'report-invalidated',
        'device_id': await _auth.deviceId(),
      });
    } catch (_) {}
  }

  Future<void> _deleteKeySilently() async {
    try {
      await _ch.invokeMethod<bool>('deleteKey');
    } catch (_) {}
  }

  AuthFailure _changed() => AuthFailure(
    'BIOMETRIC_CHANGED',
    'The fingerprint or face on this phone changed. Ask HR to approve re-enrollment.',
  );

  AuthFailure _noBiometric() => AuthFailure('NO_BIOMETRIC_ENROLLED', BioText.setupRequired);
}