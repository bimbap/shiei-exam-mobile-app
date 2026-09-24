import '../core/auth/token_storage.dart';

class AppConfig {
  // Default points to localhost:8000 (works directly on physical devices via adb reverse and on desktop)
  static const String defaultBaseUrl = 'http://localhost:8000/api/v1';
  static const String fallbackLocalUrl = 'http://10.0.2.2:8000/api/v1';

  static String baseUrl = defaultBaseUrl;

  static const int connectTimeoutMs = 15000;
  static const int receiveTimeoutMs = 15000;

  /// Load persisted base URL from disk on startup
  static Future<void> init() async {
    try {
      final savedUrl = await TokenStorage.getBaseUrl();
      if (savedUrl != null && savedUrl.trim().isNotEmpty) {
        setCustomBaseUrl(savedUrl, persist: false);
      }
    } catch (_) {}
  }

  static void setCustomBaseUrl(String newUrl, {bool persist = true}) {
    String trimmed = newUrl.trim();
    if (trimmed.endsWith('/')) {
      baseUrl = trimmed.substring(0, trimmed.length - 1);
    } else {
      baseUrl = trimmed;
    }
    if (persist) {
      TokenStorage.saveBaseUrl(baseUrl);
    }
  }
}
