import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorage {
  static const _storage = FlutterSecureStorage();

  static const String _keyToken = 'auth_token';
  static const String _keyUser = 'auth_user';
  static const String _keySerial = 'device_serial';
  static const String _keyInstallId = 'shiei_device_install_id';
  static const String _keyRole = 'auth_role';
  static const String _keySessionTimestamp = 'session_timestamp';

  static Future<void> saveSession({
    required String token,
    required String role,
    required Map<String, dynamic> user,
    String? serialNumber,
  }) async {
    await _storage.write(key: _keyToken, value: token);
    await _storage.write(key: _keyRole, value: role);
    await _storage.write(key: _keyUser, value: jsonEncode(user));
    await _storage.write(
      key: _keySessionTimestamp,
      value: DateTime.now().millisecondsSinceEpoch.toString(),
    );
    if (serialNumber != null) {
      await _storage.write(key: _keySerial, value: serialNumber);
    }
  }

  static Future<String?> getToken() async {
    return await _storage.read(key: _keyToken);
  }

  static Future<String?> getRole() async {
    return await _storage.read(key: _keyRole);
  }

  static Future<Map<String, dynamic>?> getUser() async {
    final raw = await _storage.read(key: _keyUser);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveUser(Map<String, dynamic> user) async {
    await _storage.write(key: _keyUser, value: jsonEncode(user));
  }

  static Future<String?> getSerialNumber() async {
    return await _storage.read(key: _keySerial);
  }

  /// Returns a persistent cryptographic per-installation identifier stored in Keystore/Keychain.
  static Future<String> getOrCreateInstallationId() async {
    final existing = await _storage.read(key: _keyInstallId);
    if (existing != null && existing.trim().length >= 16) {
      return existing.trim();
    }
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    final generated = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
    await _storage.write(key: _keyInstallId, value: generated);
    return generated;
  }

  static const String _keyScreenshotProtection = 'screenshot_protection_enabled';
  static const String _keyAppExitBypass = 'app_exit_bypass_enabled';
  static const String _keyAntiAlarmBypass = 'anti_alarm_bypass_enabled';

  static Future<void> setScreenshotProtection(bool enabled) async {
    await _storage.write(key: _keyScreenshotProtection, value: enabled ? '1' : '0');
  }

  static Future<bool> isScreenshotProtectionEnabled() async {
    // In release/production builds, anti-screenshot protection is permanently enforced.
    // Only allow disabling/toggling in debug builds.
    if (!kDebugMode) return true;
    final val = await _storage.read(key: _keyScreenshotProtection);
    if (val == null) return true; // Default active (protected)
    return val == '1';
  }

  static Future<void> setAppExitBypass(bool enabled) async {
    await _storage.write(key: _keyAppExitBypass, value: enabled ? '1' : '0');
  }

  static Future<bool> isAppExitBypassEnabled() async {
    if (!kDebugMode) return false;
    final val = await _storage.read(key: _keyAppExitBypass);
    return val == '1';
  }

  static Future<void> setAntiAlarmBypass(bool enabled) async {
    await _storage.write(key: _keyAntiAlarmBypass, value: enabled ? '1' : '0');
  }

  static Future<bool> isAntiAlarmBypassEnabled() async {
    if (!kDebugMode) return false;
    final val = await _storage.read(key: _keyAntiAlarmBypass);
    return val == '1';
  }

  static const String _keyOnboardingDone = 'shiei_onboarding_completed';
  static const String _keyMobileTourDone = 'shiei_mobile_tour_completed';
  static const String _keyBaseUrl = 'configured_base_url';

  static Future<void> saveBaseUrl(String url) async {
    await _storage.write(key: _keyBaseUrl, value: url);
  }

  static Future<String?> getBaseUrl() async {
    return await _storage.read(key: _keyBaseUrl);
  }

  static Future<void> setOnboardingCompleted(bool completed) async {
    await _storage.write(key: _keyOnboardingDone, value: completed ? '1' : '0');
  }

  static Future<bool> isOnboardingCompleted() async {
    final val = await _storage.read(key: _keyOnboardingDone);
    return val == '1';
  }

  static const String _keyAppVersion = 'shiei_last_app_version';
  static const String _keyFirstOpenDone = 'shiei_first_open_done';

  static Future<String?> getCurrentUserIdentifier() async {
    final user = await getUser();
    if (user == null) return null;
    final id = user['id']?.toString() ??
        user['username']?.toString() ??
        user['nisn']?.toString() ??
        user['nip']?.toString() ??
        user['email']?.toString();
    return (id != null && id.trim().isNotEmpty) ? id.trim() : null;
  }

  static Future<void> setMobileTourCompleted(bool completed, {String? accountId}) async {
    final id = accountId ?? await getCurrentUserIdentifier();
    final val = completed ? '1' : '0';
    if (id != null && id.isNotEmpty) {
      await _storage.write(key: 'shiei_tour_user_$id', value: val);
    }
    await _storage.write(key: _keyMobileTourDone, value: val);
  }

  static Future<bool> isMobileTourCompleted({String? accountId}) async {
    final id = accountId ?? await getCurrentUserIdentifier();
    if (id != null && id.isNotEmpty) {
      final val = await _storage.read(key: 'shiei_tour_user_$id');
      if (val != null) return val == '1';
      return false; // Not completed yet for this specific account
    }
    final val = await _storage.read(key: _keyMobileTourDone);
    return val == '1';
  }

  static const String _keyProctorTourDone = 'shiei_proctor_tour_completed';
  static const String _keyAdminTourDone = 'shiei_admin_tour_completed';
  static const String _keyTeacherTourDone = 'shiei_teacher_tour_completed';

  static Future<void> setProctorTourCompleted(bool completed, {bool isAdmin = false, String? accountId}) async {
    final id = accountId ?? await getCurrentUserIdentifier();
    final val = completed ? '1' : '0';
    if (id != null && id.isNotEmpty) {
      await _storage.write(key: 'shiei_proctor_tour_user_$id', value: val);
    }
    await _storage.write(key: _keyProctorTourDone, value: val);
    await _storage.write(key: isAdmin ? _keyAdminTourDone : _keyTeacherTourDone, value: val);
  }

  static Future<bool> isProctorTourCompleted({bool isAdmin = false, String? accountId}) async {
    final id = accountId ?? await getCurrentUserIdentifier();
    if (id != null && id.isNotEmpty) {
      final val = await _storage.read(key: 'shiei_proctor_tour_user_$id');
      if (val != null) return val == '1';
      return false; // Not completed yet for this specific account
    }
    final roleKey = isAdmin ? _keyAdminTourDone : _keyTeacherTourDone;
    final val = await _storage.read(key: roleKey);
    if (val != null) return val == '1';
    final legacyVal = await _storage.read(key: _keyProctorTourDone);
    return legacyVal == '1';
  }

  static Future<String?> getLastAppVersion() async {
    return await _storage.read(key: _keyAppVersion);
  }

  static Future<void> setLastAppVersion(String version) async {
    await _storage.write(key: _keyAppVersion, value: version);
  }

  static Future<bool> isFirstOpenDone() async {
    final val = await _storage.read(key: _keyFirstOpenDone);
    return val == '1';
  }

  static Future<void> setFirstOpenDone() async {
    await _storage.write(key: _keyFirstOpenDone, value: '1');
  }

  static const String _keyThemeMode = 'app_theme_mode';
  static const String _keyAudioFeedback = 'shiei_audio_feedback_enabled';
  static const String _keyFraudAlarm = 'shiei_fraud_alarm_enabled';
  static const String _keyKeepBrowserLogin = 'shiei_keep_browser_login';
  static const String _keyBrowserLoginConnected = 'shiei_browser_login_connected';
  static const String _keyBrowserLoginLabel = 'shiei_browser_login_label';
  static const String _keyBrowserLoginEmail = 'shiei_browser_login_email';
  static const String _keyBrowserLoginUrl = 'shiei_browser_login_url';
  static const String _keyBrowserLoginUpdatedAt = 'shiei_browser_login_updated_at';
  static const String _keySavedBrowserEmails = 'shiei_saved_browser_emails';
  static const String _keyHiddenDeviceEmails = 'shiei_hidden_device_emails';

  static Future<void> saveThemeMode(String mode) async {
    await _storage.write(key: _keyThemeMode, value: mode);
  }

  static Future<String?> getThemeMode() async {
    return await _storage.read(key: _keyThemeMode);
  }

  static Future<void> setAudioFeedbackEnabled(bool enabled) async {
    await _storage.write(key: _keyAudioFeedback, value: enabled ? '1' : '0');
  }

  static Future<bool> isAudioFeedbackEnabled() async {
    final val = await _storage.read(key: _keyAudioFeedback);
    return val != '0'; // default true
  }

  static Future<void> setFraudAlarmEnabled(bool enabled) async {
    await _storage.write(key: _keyFraudAlarm, value: enabled ? '1' : '0');
  }

  static Future<bool> isFraudAlarmEnabled() async {
    final val = await _storage.read(key: _keyFraudAlarm);
    return val != '0'; // default true
  }

  static Future<void> setKeepBrowserLoginEnabled(bool enabled) async {
    await _storage.write(key: _keyKeepBrowserLogin, value: enabled ? '1' : '0');
  }

  static Future<bool> isKeepBrowserLoginEnabled() async {
    final val = await _storage.read(key: _keyKeepBrowserLogin);
    return val == '1'; // default false (Incognito / Guest mode)
  }

  static Future<void> saveBrowserLoginMeta({
    required bool connected,
    String? label,
    String? email,
    String? url,
    bool clearEmailIfMissing = false,
  }) async {
    await _storage.write(key: _keyBrowserLoginConnected, value: connected ? '1' : '0');
    if (label != null && label.trim().isNotEmpty) {
      await _storage.write(key: _keyBrowserLoginLabel, value: label.trim());
    }
    if (email != null && email.trim().isNotEmpty) {
      await _storage.write(key: _keyBrowserLoginEmail, value: email.trim());
      if (connected) {
        await addSavedBrowserEmail(email.trim());
      }
    } else if (clearEmailIfMissing) {
      await _storage.delete(key: _keyBrowserLoginEmail);
    }
    if (url != null && url.trim().isNotEmpty) {
      await _storage.write(key: _keyBrowserLoginUrl, value: url.trim());
    }
    if (connected) {
      await _storage.write(
        key: _keyBrowserLoginUpdatedAt,
        value: DateTime.now().toIso8601String(),
      );
    }
  }

  static Future<Map<String, dynamic>> getBrowserLoginMeta() async {
    final connected = (await _storage.read(key: _keyBrowserLoginConnected)) == '1';
    final label = await _storage.read(key: _keyBrowserLoginLabel);
    final email = await _storage.read(key: _keyBrowserLoginEmail);
    final url = await _storage.read(key: _keyBrowserLoginUrl);
    final updatedAt = await _storage.read(key: _keyBrowserLoginUpdatedAt);
    return {
      'connected': connected,
      'label': label,
      'email': email,
      'url': url,
      'updatedAt': updatedAt,
    };
  }

  static Future<void> clearBrowserLoginMeta() async {
    await _storage.delete(key: _keyBrowserLoginConnected);
    await _storage.delete(key: _keyBrowserLoginLabel);
    await _storage.delete(key: _keyBrowserLoginEmail);
    await _storage.delete(key: _keyBrowserLoginUrl);
    await _storage.delete(key: _keyBrowserLoginUpdatedAt);
  }

  static Future<List<String>> _readEmailList(String key) async {
    final raw = await _storage.read(key: key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .map((e) => e?.toString().trim().toLowerCase() ?? '')
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList();
      }
    } catch (_) {}
    return [];
  }

  static Future<void> _writeEmailList(String key, List<String> emails) async {
    final cleaned = emails
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    await _storage.write(key: key, value: jsonEncode(cleaned));
  }

  static Future<List<String>> getSavedBrowserEmails() async {
    return _readEmailList(_keySavedBrowserEmails);
  }

  static Future<void> addSavedBrowserEmail(String email) async {
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty) return;
    final current = await getSavedBrowserEmails();
    current.removeWhere((e) => e == normalized);
    current.insert(0, normalized);
    await _writeEmailList(_keySavedBrowserEmails, current);

    // Unhide if previously hidden by the user
    final hidden = await getHiddenDeviceGoogleEmails();
    if (hidden.contains(normalized)) {
      hidden.removeWhere((e) => e == normalized);
      await _writeEmailList(_keyHiddenDeviceEmails, hidden);
    }
  }

  static Future<void> removeSavedBrowserEmail(String email) async {
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty) return;
    final current = await getSavedBrowserEmails();
    current.removeWhere((e) => e == normalized);
    await _writeEmailList(_keySavedBrowserEmails, current);
  }

  static Future<List<String>> getHiddenDeviceGoogleEmails() async {
    return _readEmailList(_keyHiddenDeviceEmails);
  }

  static Future<void> hideDeviceGoogleEmail(String email) async {
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty) return;
    final hidden = await getHiddenDeviceGoogleEmails();
    if (!hidden.contains(normalized)) {
      hidden.add(normalized);
      await _writeEmailList(_keyHiddenDeviceEmails, hidden);
    }
  }

  static Future<bool> isSessionExpired({int maxDays = 3}) async {
    final token = await getToken();
    if (token == null || token.isEmpty) return false;

    final raw = await _storage.read(key: _keySessionTimestamp);
    if (raw == null) {
      // Legacy session without timestamp: treat as expired to enforce freshness
      return true;
    }
    final ts = int.tryParse(raw);
    if (ts == null) return true;
    final sessionDate = DateTime.fromMillisecondsSinceEpoch(ts);
    final age = DateTime.now().difference(sessionDate);
    return age.inSeconds >= (maxDays * 24 * 60 * 60);
  }

  static Future<void> clear() async {
    await _storage.delete(key: _keyToken);
    await _storage.delete(key: _keyRole);
    await _storage.delete(key: _keyUser);
    await _storage.delete(key: _keySessionTimestamp);
  }

  static Future<void> clearToken() async {
    await clear();
  }
}
