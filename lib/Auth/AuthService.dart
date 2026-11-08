// lib/auth_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum StaffState { needsPasswordChange, ready }

class AuthFailure implements Exception {
  AuthFailure(this.code, this.message, {this.attemptsLeft});

  final String code;
  final String message;
  final int? attemptsLeft;

  bool get isNetwork => code == 'NETWORK';

  /// Errors after which the session must be dropped.
  bool get endsSession => code == 'STAFF_INACTIVE' || code == 'NO_STAFF';

  @override
  String toString() => message;
}

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _deviceKey = 'xaadir_device_id';
  static const String _functionName = 'auth-service';
  static const String _recoveryFunction = 'password-recovery';

  final StreamController<void> _recheck = StreamController<void>.broadcast();

  /// One-shot message the gate shows on the Login screen after a forced sign-out.
  String? flashNotice;

  SupabaseClient get _client => Supabase.instance.client;

  Stream<AuthState> get authChanges => _client.auth.onAuthStateChange;
  Stream<void> get recheckRequests => _recheck.stream;
  bool get hasSession => _client.auth.currentSession != null;
  String? get currentEmail => _client.auth.currentUser?.email;

  void requestRecheck() => _recheck.add(null);

  // ───────────────────────── Sign in / out ─────────────────────────

  Future<void> signIn(String email, String password) async {
    final cleanEmail = email.trim().toLowerCase();
    if (cleanEmail.isEmpty || password.isEmpty) {
      throw AuthFailure('INVALID_INPUT', 'Enter your email and password.');
    }
    try {
      await _client.auth.signInWithPassword(email: cleanEmail, password: password);
    } on AuthException catch (e) {
      throw _mapAuthException(e);
    } catch (e) {
      if (_looksOffline(e)) throw _offline();
      throw AuthFailure('UNKNOWN', 'Could not sign in. Please try again.');
    }
  }

  Future<void> signOut() async {
    try {
      await _client.auth.signOut(scope: SignOutScope.local);
    } catch (_) {
      // Local session is cleared even if the server call fails.
    }
  }

  // ───────────────────────── Server calls ─────────────────────────

  Future<StaffState> check() async {
    final data = await _call({'action': 'check'});
    return data['state'] == 'NEEDS_PASSWORD_CHANGE'
        ? StaffState.needsPasswordChange
        : StaffState.ready;
  }

  Future<void> changePassword({
    required String newPassword,
    required String inviteCode,
  }) async {
    final email = currentEmail;
    if (email == null) {
      throw AuthFailure('UNAUTHORIZED', 'Your session expired. Please sign in again.');
    }

    await _call({
      'action': 'change-password',
      'new_password': newPassword,
      'invite_code': inviteCode.trim().toUpperCase(),
      'device_id': await deviceId(),
      'device_name': await deviceName(),
    });

    // The new password is now the real one: sign in again with it.
    try {
      await _client.auth.signInWithPassword(email: email, password: newPassword);
    } catch (_) {
      flashNotice = 'Password changed. Please sign in with your new password.';
      await signOut();
      throw AuthFailure(
        'RELOGIN_FAILED',
        'Password changed. Please sign in with your new password.',
      );
    }
  }

  // ───────────────────────── Staff password recovery ─────────────────────────

  /// Resets a staff password with the one-time code HR issued from the admin
  /// panel (30 min expiry, single use, NOT the invite code).
  /// Never signs the user in: the caller sends them back to Login.
  Future<void> resetStaffPassword({
    required String email,
    required String code,
    required String newPassword,
    required String confirmPassword,
  }) async {
    final cleanEmail = email.trim().toLowerCase();
    final cleanCode = code.trim().toUpperCase();

    if (cleanEmail.isEmpty || !cleanEmail.contains('@')) {
      throw AuthFailure('INVALID_INPUT', 'Enter your email address.');
    }
    if (cleanCode.length < 6) {
      throw AuthFailure('INVALID_INPUT', 'Enter the reset code HR gave you.');
    }
    if (newPassword != confirmPassword) {
      throw AuthFailure('PASSWORD_MISMATCH', 'Passwords do not match.');
    }
    final weak = validateNewPassword(newPassword);
    if (weak != null) throw AuthFailure('WEAK_PASSWORD', weak);

    debugPrint('🔐 [AuthService] Staff password reset requested');
    try {
      final res = await _client.functions
          .invoke(
        _recoveryFunction,
        body: {
          'action': 'reset',
          'account_type': 'staff',
          'email': cleanEmail,
          'code': cleanCode,
          'password': newPassword,
          'password_confirm': confirmPassword,
        },
      )
          .timeout(const Duration(seconds: 25));

      final data = _asMap(res.data);
      if (data['ok'] == true) {
        debugPrint('✅ [AuthService] Staff password reset succeeded');
        return;
      }
      debugPrint('❌ [AuthService] Reset returned no ok flag');
      throw AuthFailure('SERVER_ERROR', 'Could not reset your password. Please try again.');
    } on AuthFailure {
      rethrow;
    } on FunctionException catch (e) {
      debugPrint('❌ [AuthService] Reset failed with status ${e.status}');
      throw _mapRecoveryFailure(e.status, _asMap(e.details));
    } catch (e) {
      debugPrint('❌ [AuthService] Reset error: ${e.runtimeType}');
      if (_looksOffline(e)) throw _offline();
      throw AuthFailure('UNKNOWN', 'Could not reset your password. Please try again.');
    }
  }

  /// Same rules the Edge Function enforces: 12-128 chars, upper, lower, number.
  /// Returns an error message, or null when the password is valid.
  static String? validateNewPassword(String p) {
    if (p.length < 12) return 'Password must be at least 12 characters.';
    if (p.length > 128) return 'Password must be 128 characters or fewer.';
    if (!RegExp(r'[a-z]').hasMatch(p)) return 'Password needs a lowercase letter.';
    if (!RegExp(r'[A-Z]').hasMatch(p)) return 'Password needs an uppercase letter.';
    if (!RegExp(r'\d').hasMatch(p)) return 'Password needs a number.';
    return null;
  }

  AuthFailure _mapRecoveryFailure(int status, Map<String, dynamic> body) {
    final serverMsg = body['error'] is String ? body['error'] as String : '';
    final lower = serverMsg.toLowerCase();

    if (status == 429) {
      return AuthFailure(
        'RATE_LIMIT',
        'Too many attempts. Please wait a while and try again, or ask HR for a new code.',
      );
    }
    if (status == 400) {
      if (lower.contains('password')) {
        return AuthFailure(
          'WEAK_PASSWORD',
          'Password must be 12+ characters with uppercase, lowercase and a number, and both fields must match.',
        );
      }
      // The server returns the same 400 for a wrong, expired, used or unknown
      // code/email on purpose, so the app cannot tell them apart.
      return AuthFailure(
        'INVALID_CODE',
        'Invalid or expired reset code, or wrong email. Codes work once and expire after 30 minutes. Ask HR for a new one.',
      );
    }
    if (status == 401 || status == 403) {
      return AuthFailure(
        'SERVER_ERROR',
        'Password recovery is unavailable right now. Contact HR.',
      );
    }
    if (status == 503) {
      return AuthFailure(
        'SERVER_ERROR',
        'Password recovery is temporarily unavailable. Try again later.',
      );
    }
    return AuthFailure(
      'SERVER_ERROR',
      'Something went wrong. Please try again.',
    );
  }

  Future<Map<String, dynamic>> _call(Map<String, dynamic> body) =>
      callFunction(_functionName, body);

  /// Calls any Edge Function with the current session (shared error handling).
  Future<Map<String, dynamic>> callFunction(String name, Map<String, dynamic> body) async {
    try {
      final res = await _client.functions
          .invoke(name, body: body)
          .timeout(const Duration(seconds: 25));
      return _asMap(res.data);
    } on FunctionException catch (e) {
      if (e.status == 401) {
        flashNotice = 'Your session expired. Please sign in again.';
        await signOut();
        throw AuthFailure('UNAUTHORIZED', 'Your session expired. Please sign in again.');
      }
      final details = _asMap(e.details);
      final code = details['code'] is String ? details['code'] as String : 'SERVER_ERROR';
      final message = details['error'] is String
          ? details['error'] as String
          : 'Something went wrong. Please try again.';
      final left = details['attempts_left'];
      throw AuthFailure(code, message, attemptsLeft: left is int ? left : null);
    } on AuthException catch (e) {
      throw _mapAuthException(e);
    } catch (e) {
      if (e is AuthFailure) rethrow;
      if (_looksOffline(e)) throw _offline();
      throw AuthFailure('UNKNOWN', 'Something went wrong. Please try again.');
    }
  }

  // ───────────────────────── Device ─────────────────────────

  Future<String> deviceId() async {
    final existing = await _storage.read(key: _deviceKey);
    if (existing != null && existing.length == 32) return existing;
    final rnd = Random.secure();
    final id = List<int>.generate(16, (_) => rnd.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    await _storage.write(key: _deviceKey, value: id);
    return id;
  }

  Future<String> deviceName() async {
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final a = await info.androidInfo;
        return _clip('${a.brand} ${a.model}');
      }
      if (Platform.isIOS) {
        final i = await info.iosInfo;
        return _clip(i.name);
      }
    } catch (_) {}
    return 'Unknown device';
  }

  // ───────────────────────── Helpers ─────────────────────────

  String _clip(String s) {
    final t = s.trim();
    if (t.isEmpty) return 'Unknown device';
    return t.length > 100 ? t.substring(0, 100) : t;
  }

  Map<String, dynamic> _asMap(dynamic v) {
    if (v is Map) return Map<String, dynamic>.from(v);
    if (v is String) {
      try {
        final d = jsonDecode(v);
        if (d is Map) return Map<String, dynamic>.from(d);
      } catch (_) {}
    }
    return <String, dynamic>{};
  }

  AuthFailure _offline() => AuthFailure(
    'NETWORK',
    'No internet connection. Check your network and try again.',
  );

  bool _looksOffline(Object e) {
    if (e is SocketException || e is TimeoutException) return true;
    final s = e.toString();
    return s.contains('SocketException') ||
        s.contains('Failed host lookup') ||
        s.contains('ClientException') ||
        s.contains('Connection refused') ||
        s.contains('Connection reset') ||
        s.contains('Network is unreachable') ||
        s.contains('AuthRetryableFetchException') ||
        s.contains('TimeoutException');
  }

  AuthFailure _mapAuthException(AuthException e) {
    final status = e.statusCode;
    final msg = e.message.toLowerCase();
    if (_looksOffline(e)) return _offline();
    if (status == '429' || msg.contains('rate limit') || msg.contains('too many')) {
      return AuthFailure(
        'RATE_LIMIT',
        'Too many attempts. Please wait a minute and try again.',
      );
    }
    if (msg.contains('invalid login credentials') || msg.contains('invalid credentials')) {
      return AuthFailure('INVALID_CREDENTIALS', 'Wrong email or password.');
    }
    if (msg.contains('banned')) {
      return AuthFailure('STAFF_INACTIVE', 'Your account is inactive. Contact HR.');
    }
    return AuthFailure('AUTH_ERROR', 'Could not sign in. Please try again.');
  }
}