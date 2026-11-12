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

  /// Returns true when [host] refers to loopback, .local mDNS, or RFC1918/link-local private IPv4.
  static bool isLocalOrPrivateHost(String host) {
    final normalized = host.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    if (normalized == 'localhost' ||
        normalized == '127.0.0.1' ||
        normalized == '10.0.2.2' ||
        normalized == '::1' ||
        normalized.endsWith('.local')) {
      return true;
    }

    final parts = normalized.split('.');
    if (parts.length == 4) {
      final octets = parts.map(int.tryParse).toList();
      if (octets.every((o) => o != null && o >= 0 && o <= 255)) {
        final a = octets[0]!;
        final b = octets[1]!;
        if (a == 10) return true;
        if (a == 127) return true;
        if (a == 169 && b == 254) return true;
        if (a == 172 && b >= 16 && b <= 31) return true;
        if (a == 192 && b == 168) return true;
      }
    }
    return false;
  }

  /// Validates a user/admin server URL: public domains require HTTPS; HTTP is limited to local/private IPs.
  static String? validateAndNormalizeServerUrl(String rawInput) {
    String trimmed = rawInput.trim();
    if (trimmed.isEmpty) return null;

    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      final candidateHost = trimmed.split('/').first.split(':').first;
      final scheme = isLocalOrPrivateHost(candidateHost) ? 'http' : 'https';
      trimmed = '$scheme://$trimmed';
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasAuthority || uri.host.trim().isEmpty) {
      return null;
    }

    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'https' && !(scheme == 'http' && isLocalOrPrivateHost(uri.host))) {
      return null;
    }

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
    return trimmed;
  }

  /// True when [rawUrl] uses HTTPS or targets a local/private IP over HTTP.
  static bool isAllowedServerBaseUrl(String rawUrl) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || !uri.hasAuthority || uri.host.trim().isEmpty) {
      return false;
    }
    final scheme = uri.scheme.toLowerCase();
    return scheme == 'https' || (scheme == 'http' && isLocalOrPrivateHost(uri.host));
  }

  /// Load persisted base URL from disk on startup
  static Future<void> init() async {
    try {
      final savedUrl = await TokenStorage.getBaseUrl();
      if (savedUrl != null && savedUrl.trim().isNotEmpty) {
        final trimmed = savedUrl.trim();
        // Ignore test dummy localhost saved in older test sessions and reject public HTTP URLs
        if (trimmed != defaultBaseUrl &&
            !trimmed.contains('localhost') &&
            isAllowedServerBaseUrl(trimmed)) {
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
    final normalized = validateAndNormalizeServerUrl(newUrl);
    if (normalized == null) {
      throw ArgumentError('Server URL must use HTTPS for public domains; HTTP is restricted to local/private IPs.');
    }
    baseUrl = normalized;
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
