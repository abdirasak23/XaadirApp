// lib/Services/BiometricService.dart
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
  });

  final bool available; // a strong fingerprint is enrolled on the phone
  final String reason; // OK | NO_HARDWARE | NONE_ENROLLED | HW_UNAVAILABLE | UPDATE_REQUIRED | UNSUPPORTED
  final bool keyExists;
  final bool keyValid;
}

/// Proof that the enrolled finger just signed a fresh server challenge.
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

/// Fingerprint-bound key (Android Keystore, via the Kotlin channel).
/// Only the fingerprint can unlock it: no PIN, pattern or password fallback.
class BiometricService {
  BiometricService._();
  static final BiometricService instance = BiometricService._();

  static const MethodChannel _ch = MethodChannel('xaadir/biometric');

  AuthService get _auth => AuthService.instance;

  // ───────────── local phone state ─────────────
  Future<BioStatus> localStatus() async {
    try {
      final m = await _ch.invokeMapMethod<String, dynamic>('status');
      return BioStatus(
        available: m?['available'] == true,
        reason: m?['reason']?.toString() ?? 'UNSUPPORTED',
        keyExists: m?['keyExists'] == true,
        keyValid: m?['keyValid'] == true,
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

  /// One answer for the UI: can this staff member check in with a fingerprint right now?
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
  /// Creates the key pair behind a fingerprint prompt and registers the public key.
  Future<void> enroll() async {
    final local = await localStatus();
    if (!local.available) throw _noBiometric(local.reason);

    final server = await serverStatus();
    if (server == 'invalidated') throw _changed();
    if (server == 'active') {
      throw AuthFailure(
        'ENROLL_NOT_ALLOWED',
        'A fingerprint is already registered on this phone. Ask HR to approve re-enrollment.',
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
        'Register your fingerprint',
      );
      await _auth.callFunction('enroll-biometric', {
        'action': 'enroll',
        'device_id': deviceId,
        'device_name': await _auth.deviceName(),
        'challenge_id': ch.id,
        'public_key': publicKey,
        'signature': signature,
      });
    } catch (_) {
      await _deleteKeySilently(); // keep phone and server in step
      rethrow;
    }
  }

  // ───────────── check-in proof ─────────────
  /// Shows the fingerprint prompt and signs a fresh server challenge.
  Future<BioProof> proveIdentity({String subtitle = 'Confirm to continue'}) async {
    final local = await localStatus();
    if (!local.available) throw _noBiometric(local.reason);
    if (!local.keyExists) {
      throw AuthFailure('NO_BIOMETRIC_ENROLLED', 'Register your fingerprint to check in.');
    }
    if (!local.keyValid) {
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
        throw AuthFailure('BIOMETRIC_FAILED', 'Fingerprint was not confirmed.');
      }
      return s;
    } on PlatformException catch (e) {
      switch (e.code) {
        case 'KEY_INVALIDATED':
          await _reportInvalidated();
          throw _changed();
        case 'NO_KEY':
          throw AuthFailure('NO_BIOMETRIC_ENROLLED', 'Register your fingerprint to check in.');
        case 'CANCELLED':
          throw AuthFailure('BIOMETRIC_FAILED', 'Fingerprint check was cancelled.');
        case 'LOCKED_OUT':
          throw AuthFailure('BIOMETRIC_FAILED', 'Too many wrong attempts. Wait 30 seconds and try again.');
        default:
          throw AuthFailure('BIOMETRIC_FAILED', 'Fingerprint was not recognised. Try again.');
      }
    }
  }

  /// Tells the server the key is dead (new fingerprint added). The function always answers
  /// BIOMETRIC_CHANGED, so the error is expected and ignored here.
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
    'Your fingerprints changed on this phone. Ask HR to approve re-enrollment.',
  );

  AuthFailure _noBiometric(String reason) {
    switch (reason) {
      case 'NO_HARDWARE':
        return AuthFailure('NO_BIOMETRIC_ENROLLED', 'This phone has no fingerprint sensor, so it cannot be used to check in.');
      case 'NONE_ENROLLED':
        return AuthFailure('NO_BIOMETRIC_ENROLLED', 'Add a fingerprint in your phone settings (Security → Fingerprint), then try again.');
      default:
        return AuthFailure('NO_BIOMETRIC_ENROLLED', 'Fingerprint is not available right now. Try again in a moment.');
    }
  }
}