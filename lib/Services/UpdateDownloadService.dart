// lib/Services/UpdateDownloadService.dart
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../Auth/AuthService.dart';

/// What the popup needs to draw itself.
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.build,
    required this.url,
    required this.message,
    required this.closesUsed,
    required this.maxCloses,
    required this.isIos,
  });

  final String version;
  final int build;
  final String url;
  final String message;
  final int closesUsed;
  final int maxCloses;
  final bool isIos;

  /// After [maxCloses] closes the popup can no longer be closed.
  bool get locked => closesUsed >= maxCloses;
  int get closesLeft => (maxCloses - closesUsed).clamp(0, maxCloses);
}

class UpdateDownloadService {
  UpdateDownloadService._();
  static final UpdateDownloadService instance = UpdateDownloadService._();

  static const String _function = 'app-update';
  static const int maxCloses = 3;

  // Fallbacks if the database row has no link.
  static const String androidUrl = 'https://play.google.com/apps/internaltest/4701720515916658803';
  static const String iosUrl = 'https://testflight.apple.com/join/wjP1tMAv';

  static const String _defaultMessage =
      'A new version of Xaadir is ready. Update to keep checking in without problems.';

  /// The closable popup shows once per app launch. The locked one always shows.
  bool _shownThisSession = false;
  bool _checking = false;

  bool get _isIos => Platform.isIOS;

  String _closeKey(int build, String version) => 'update_closes_${build}_$version';

  /// Returns the update to show now, or null (no update, already shown this
  /// session, or any error: an update check must never block the app).
  Future<UpdateInfo?> check() async {
    if (_checking) return null;
    _checking = true;
    try {
      final platform = _isIos ? 'ios' : 'android';
      final json = await AuthService.instance.callFunction(_function, {'platform': platform});

      if (json['is_available'] != true) {
        debugPrint('⬆️ Update switch is OFF ($platform)');
        return null;
      }

      final latestBuild = _toInt(json['latest_build']);
      final version = json['latest_version']?.toString().trim() ?? '';
      final pkg = await PackageInfo.fromPlatform();
      final installed = int.tryParse(pkg.buildNumber) ?? 0;
      if (latestBuild > 0 && installed >= latestBuild) {
        debugPrint('⬆️ Already up to date (installed=$installed latest=$latestBuild)');
        return null;
      }

      final prefs = await SharedPreferences.getInstance();
      final used = prefs.getInt(_closeKey(latestBuild, version)) ?? 0;
      final locked = used >= maxCloses;

      if (!locked && _shownThisSession) {
        debugPrint('⬆️ Update popup already shown this session');
        return null;
      }
      if (!locked) _shownThisSession = true;

      final dbUrl = json['store_url']?.toString().trim() ?? '';
      final msg = json['message']?.toString().trim() ?? '';
      debugPrint('⬆️✅ Update available → v$version build $latestBuild · closes=$used/$maxCloses · locked=$locked');
      return UpdateInfo(
        version: version,
        build: latestBuild,
        url: dbUrl.isNotEmpty ? dbUrl : (_isIos ? iosUrl : androidUrl),
        message: msg.isNotEmpty ? msg : _defaultMessage,
        closesUsed: used,
        maxCloses: maxCloses,
        isIos: _isIos,
      );
    } catch (e) {
      debugPrint('⬆️⚠️ Update check failed (ignored): $e');
      return null;
    } finally {
      _checking = false;
    }
  }

  /// Counts one close. Persisted, so it survives app restarts.
  Future<void> registerClose(UpdateInfo info) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _closeKey(info.build, info.version);
      final next = (prefs.getInt(key) ?? 0) + 1;
      await prefs.setInt(key, next);
      debugPrint('⬆️❎ Update popup closed → $next/$maxCloses');
    } catch (e) {
      debugPrint('⬆️⚠️ Could not save close count: $e');
    }
  }

  /// Opens Google Play (Android) or TestFlight (iOS).
  Future<bool> openStore(UpdateInfo info) async {
    try {
      final ok = await launchUrl(Uri.parse(info.url), mode: LaunchMode.externalApplication);
      debugPrint('⬆️🚀 Opened store → ${info.url} ok=$ok');
      return ok;
    } catch (e) {
      debugPrint('⬆️❌ Could not open store: $e');
      return false;
    }
  }

  static int _toInt(dynamic v) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }
}