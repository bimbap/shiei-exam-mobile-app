import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../config/app_config.dart';
import '../../core/auth/token_storage.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/app_notification.dart';
import '../exam_player/url_exam_player.dart';

/// Dedicated in-app browser login setup page accessed from Settings.
/// Shares the exact WebView cookie store and User-Agent with [UrlExamPlayer] so
/// Google Forms, Microsoft SSO, Moodle, or school CBT logins stay active during kiosk exams.
class BrowserLoginConnectScreen extends StatefulWidget {
  final String? initialUrl;

  const BrowserLoginConnectScreen({super.key, this.initialUrl});

  @override
  State<BrowserLoginConnectScreen> createState() => _BrowserLoginConnectScreenState();
}

class _BrowserLoginConnectScreenState extends State<BrowserLoginConnectScreen> {
  static const String _googleLoginUrl = 'https://accounts.google.com';
  static const String _googleFormsUrl = 'https://docs.google.com/forms';

  late final TextEditingController _urlController;
  InAppWebViewController? _webController;
  double _progress = 0;
  String _currentUrl = _googleLoginUrl;
  String _detectedLabel = 'Google Account';
  int _cookieCount = 0;
  bool _hasAuthCookie = false;
  bool _isCheckingCookies = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final initial = _normalizeConnectUrl(widget.initialUrl ?? '') ?? _googleLoginUrl;
    _currentUrl = initial;
    _detectedLabel = _deriveProviderLabel(initial);
    _urlController = TextEditingController(text: initial);
    _inspectActiveCookies(initial);
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  static String? _normalizeConnectUrl(String raw) {
    var trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    if (!trimmed.contains('://')) {
      final host = trimmed.split('/').first.split(':').first;
      final scheme = AppConfig.isLocalOrPrivateHost(host) ? 'http' : 'https';
      trimmed = '$scheme://$trimmed';
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasAuthority || uri.host.trim().isEmpty) return null;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'https' && !(scheme == 'http' && AppConfig.isLocalOrPrivateHost(uri.host))) {
      return null;
    }
    return uri.toString();
  }

  static String _deriveProviderLabel(String url) {
    final host = (Uri.tryParse(url)?.host ?? '').toLowerCase();
    if (host.contains('google.com') || host.contains('forms.gle')) {
      return 'Akun Google / Forms';
    }
    if (host.contains('microsoft') || host.contains('live.com') || host.contains('office.com')) {
      return 'Akun Microsoft 365';
    }
    return host.isNotEmpty ? host : 'Portal Browser Ujian';
  }

  String? _getSchoolWebOrigin() {
    if (!AppConfig.hasCustomServerUrl) return null;
    final uri = Uri.tryParse(AppConfig.baseUrl);
    if (uri == null || uri.host.isEmpty) return null;
    return '${uri.scheme}://${uri.authority}';
  }

  Future<void> _inspectActiveCookies(String url) async {
    if (_isCheckingCookies) return;
    _isCheckingCookies = true;
    try {
      final manager = CookieManager.instance();
      final uri = Uri.tryParse(url);
      final List<Cookie> cookies = [];
      if (uri != null) {
        cookies.addAll(await manager.getCookies(url: WebUri(uri.toString())));
      }
      final googleCookies = await manager.getCookies(url: WebUri('https://accounts.google.com'));
      final combinedNames = <String>{
        for (final c in cookies) c.name,
        for (final c in googleCookies) c.name,
      };
      const googleAuthCookieNames = {'SID', 'HSID', 'SSID', 'SAPISID', 'APISID', '__Secure-1PSID', '__Secure-3PSID'};
      final hasGoogleAuth = googleCookies.any((c) => googleAuthCookieNames.contains(c.name));
      final hasSiteAuth = cookies.any((c) {
        final lower = c.name.toLowerCase();
        return lower.contains('session') ||
            lower.contains('token') ||
            lower.contains('auth') ||
            lower.contains('moodle') ||
            googleAuthCookieNames.contains(c.name);
      });

      if (mounted) {
        setState(() {
          _cookieCount = combinedNames.length;
          _hasAuthCookie = hasGoogleAuth || hasSiteAuth || cookies.length >= 2;
        });
      }
    } catch (_) {
      // Ignore cookie inspection issues on unsupported WebView runtimes
    } finally {
      _isCheckingCookies = false;
    }
  }

  void _navigateToInput([String? customRaw]) {
    FocusManager.instance.primaryFocus?.unfocus();
    final targetRaw = customRaw ?? _urlController.text;
    final normalized = _normalizeConnectUrl(targetRaw);
    if (normalized == null) {
      AppNotification.show(
        context,
        title: 'Alamat URL Tidak Valid',
        subtitle: 'Gunakan alamat HTTPS (contoh: https://accounts.google.com) atau IP LAN sekolah.',
        type: NotificationType.warning,
      );
      return;
    }

    setState(() {
      _currentUrl = normalized;
      _detectedLabel = _deriveProviderLabel(normalized);
      _urlController.text = normalized;
    });
    _webController?.loadUrl(urlRequest: URLRequest(url: WebUri(normalized)));
  }

  Future<void> _saveAndFinish() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      await _inspectActiveCookies(_currentUrl);
      await TokenStorage.setKeepBrowserLoginEnabled(true);
      await TokenStorage.saveBrowserLoginMeta(
        connected: true,
        label: _detectedLabel,
        url: _currentUrl,
      );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _clearBrowserSession() async {
    await UrlExamPlayer.clearBrowserSessionCookies();
    await TokenStorage.clearBrowserLoginMeta();
    if (!mounted) return;
    setState(() {
      _cookieCount = 0;
      _hasAuthCookie = false;
    });
    AppNotification.showSuccess(
      context,
      'Sesi Browser Dibersihkan',
      subtitle: 'Cookie & login web di dalam aplikasi telah direset.',
    );
    _webController?.loadUrl(urlRequest: URLRequest(url: WebUri(_currentUrl)));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final bg = isDark ? AppTheme.backgroundDark : const Color(0xFFF8FAFC);
    final surface = isDark ? AppTheme.surfaceDark : Colors.white;
    final border = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subColor = isDark ? AppTheme.textSecondary : const Color(0xFF64748B);
    final schoolOrigin = _getSchoolWebOrigin();

    final currentUri = Uri.tryParse(_currentUrl);
    final allowLocalMixed =
        currentUri != null && AppConfig.isLocalOrPrivateHost(currentUri.host);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Connect Login Browser',
              style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
                color: titleColor,
              ),
            ),
            Text(
              _hasAuthCookie
                  ? 'Sesi aktif terdeteksi ($_cookieCount cookie tersimpan)'
                  : 'Login akun Google / portal CBT sebelum ujian',
              style: TextStyle(
                fontSize: 11,
                color: _hasAuthCookie ? AppTheme.accentGreen : subColor,
                fontWeight: _hasAuthCookie ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Muat Ulang Halaman',
            icon: Icon(Icons.refresh_rounded, color: titleColor, size: 20),
            onPressed: () => _webController?.reload(),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: TextButton(
              onPressed: _isSaving ? null : _saveAndFinish,
              style: TextButton.styleFrom(
                backgroundColor: AppTheme.primaryShiei,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(
                _isSaving ? 'Menyimpan...' : 'Simpan',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Address bar & quick provider shortcuts
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            decoration: BoxDecoration(
              color: surface,
              border: Border(bottom: BorderSide(color: border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 40,
                        child: TextField(
                          controller: _urlController,
                          keyboardType: TextInputType.url,
                          textInputAction: TextInputAction.go,
                          onSubmitted: (_) => _navigateToInput(),
                          style: TextStyle(fontSize: 12.5, color: titleColor),
                          decoration: InputDecoration(
                            hintText: 'https://accounts.google.com',
                            hintStyle: TextStyle(fontSize: 12, color: subColor),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                            filled: true,
                            fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                            prefixIcon: Icon(
                              Icons.lock_outline_rounded,
                              size: 16,
                              color: _currentUrl.startsWith('https://')
                                  ? AppTheme.accentGreen
                                  : const Color(0xFFF59E0B),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: border),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: border),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 40,
                      child: ElevatedButton(
                        onPressed: () => _navigateToInput(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFF0F172A),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          minimumSize: const Size(52, 40),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          elevation: 0,
                        ),
                        child: const Text('Buka', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildPresetChip(
                        label: 'Google Account',
                        icon: Icons.account_circle_outlined,
                        active: _currentUrl.contains('accounts.google.com'),
                        isDark: isDark,
                        onTap: () => _navigateToInput(_googleLoginUrl),
                      ),
                      const SizedBox(width: 6),
                      _buildPresetChip(
                        label: 'Google Forms',
                        icon: Icons.description_outlined,
                        active: _currentUrl.contains('docs.google.com/forms'),
                        isDark: isDark,
                        onTap: () => _navigateToInput(_googleFormsUrl),
                      ),
                      if (schoolOrigin != null) ...[
                        const SizedBox(width: 6),
                        _buildPresetChip(
                          label: 'Web Server Sekolah',
                          icon: Icons.dns_outlined,
                          active: _currentUrl.startsWith(schoolOrigin),
                          isDark: isDark,
                          onTap: () => _navigateToInput(schoolOrigin),
                        ),
                      ],
                      const SizedBox(width: 6),
                      ActionChip(
                        avatar: const Icon(Icons.delete_sweep_outlined, size: 15, color: Color(0xFFEF4444)),
                        label: const Text(
                          'Reset Sesi Web',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFEF4444)),
                        ),
                        backgroundColor: const Color(0xFFEF4444).withValues(alpha: 0.08),
                        side: BorderSide(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
                        visualDensity: VisualDensity.compact,
                        onPressed: _clearBrowserSession,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          if (_progress > 0 && _progress < 1.0)
            LinearProgressIndicator(
              value: _progress,
              minHeight: 2.5,
              color: AppTheme.primaryShiei,
              backgroundColor: Colors.transparent,
            ),

          // Live Login WebView sharing Exam Cookie Store
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(_currentUrl)),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                domStorageEnabled: true,
                databaseEnabled: true,
                clearCache: false,
                cacheEnabled: true,
                thirdPartyCookiesEnabled: true,
                sharedCookiesEnabled: true,
                supportMultipleWindows: true,
                javaScriptCanOpenWindowsAutomatically: true,
                useShouldOverrideUrlLoading: true,
                userAgent: UrlExamPlayer.browserCompatibleUserAgent,
                mixedContentMode: allowLocalMixed
                    ? MixedContentMode.MIXED_CONTENT_COMPATIBILITY_MODE
                    : MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
                isInspectable: kDebugMode,
              ),
              onWebViewCreated: (controller) {
                _webController = controller;
              },
              onCreateWindow: (controller, createWindowAction) async {
                final popupUrl = createWindowAction.request.url?.toString();
                if (popupUrl != null && _normalizeConnectUrl(popupUrl) != null) {
                  controller.loadUrl(urlRequest: URLRequest(url: WebUri(popupUrl)));
                }
                return false;
              },
              shouldOverrideUrlLoading: (controller, action) async {
                final uri = action.request.url;
                if (uri == null) return NavigationActionPolicy.CANCEL;
                final scheme = uri.scheme.toLowerCase();
                if (scheme == 'https') return NavigationActionPolicy.ALLOW;
                if (scheme == 'http' && AppConfig.isLocalOrPrivateHost(uri.host)) {
                  return NavigationActionPolicy.ALLOW;
                }
                return NavigationActionPolicy.CANCEL;
              },
              onProgressChanged: (controller, progress) {
                if (mounted) {
                  setState(() => _progress = progress / 100);
                }
              },
              onLoadStop: (controller, url) async {
                if (url == null || !mounted) return;
                final loaded = url.toString();
                setState(() {
                  _currentUrl = loaded;
                  _urlController.text = loaded;
                  _detectedLabel = _deriveProviderLabel(loaded);
                });
                await _inspectActiveCookies(loaded);
              },
            ),
          ),

          // Bottom Confirmation Strip
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            decoration: BoxDecoration(
              color: surface,
              border: Border(top: BorderSide(color: border)),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Icon(
                    _hasAuthCookie ? Icons.verified_user_rounded : Icons.info_outline_rounded,
                    size: 18,
                    color: _hasAuthCookie ? AppTheme.accentGreen : AppTheme.primaryGlow,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _hasAuthCookie
                          ? 'Cookie login aktif. Tekan Simpan agar langsung terhubung saat ujian.'
                          : 'Masuk ke akun Anda di halaman ini lalu tekan Simpan & Selesai.',
                      style: TextStyle(fontSize: 11.5, color: subColor),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: _isSaving ? null : _saveAndFinish,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _hasAuthCookie ? AppTheme.accentGreen : AppTheme.primaryShiei,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(110, 38),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: const Text('Selesai', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetChip({
    required String label,
    required IconData icon,
    required bool active,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return ChoiceChip(
      avatar: Icon(
        icon,
        size: 15,
        color: active ? Colors.white : (isDark ? Colors.white70 : const Color(0xFF475569)),
      ),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: active ? Colors.white : (isDark ? Colors.white70 : const Color(0xFF334155)),
        ),
      ),
      selected: active,
      selectedColor: AppTheme.primaryShiei,
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
      side: BorderSide(
        color: active
            ? AppTheme.primaryShiei
            : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
      ),
      visualDensity: VisualDensity.compact,
      onSelected: (_) => onTap(),
    );
  }
}
