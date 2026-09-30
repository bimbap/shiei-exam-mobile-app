import '../core/auth/token_storage.dart';

class AppConfig {
  // Default points to localhost:8000 (works directly on physical devices via adb reverse and on desktop)
  static const String defaultBaseUrl = 'http://localhost:8000/api/v1';
  static const String fallbackLocalUrl = 'http://10.0.2.2:8000/api/v1';

  static String baseUrl = defaultBaseUrl;
  static bool hasCustomServerUrl = false;

  /// Returns baseUrl if explicitly configured by the user/admin;
  /// returns empty string so text fields are blank by default without pre-filling localhost.
  static String get inputBaseUrl => hasCustomServerUrl ? baseUrl : '';

  static const int connectTimeoutMs = 15000;
  static const int receiveTimeoutMs = 15000;

  /// Load persisted base URL from disk on startup
  static Future<void> init() async {
    try {
      final savedUrl = await TokenStorage.getBaseUrl();
      if (savedUrl != null && savedUrl.trim().isNotEmpty) {
        final trimmed = savedUrl.trim();
        // Ignore test dummy localhost saved in older test sessions
        if (trimmed != defaultBaseUrl && !trimmed.contains('localhost')) {
          setCustomBaseUrl(trimmed, persist: false);
        } else {
          hasCustomServerUrl = false;
        }
      } else {
        hasCustomServerUrl = false;
      }
    } catch (_) {}
  }

  static void setCustomBaseUrl(String newUrl, {bool persist = true}) {
    String trimmed = newUrl.trim();
    if (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    if (!trimmed.endsWith('/api/v1')) {
      if (trimmed.endsWith('/api')) {
        trimmed = '$trimmed/v1';
      } else {
        trimmed = '$trimmed/api/v1';
      }
    }
    baseUrl = trimmed;
    hasCustomServerUrl = true;
    if (persist) {
      TokenStorage.saveBaseUrl(baseUrl);
    }
  }

  static Future<void> clearCustomBaseUrl() async {
    baseUrl = defaultBaseUrl;
    hasCustomServerUrl = false;
    await TokenStorage.saveBaseUrl('');
  }
}
