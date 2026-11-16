import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../config/app_config.dart';
import '../../core/auth/token_storage.dart';
import '../../shared/theme/app_theme.dart';
import '../exam_player/url_exam_player.dart';

/// Distraction-free native-style OAuth / Web Session login screen.
/// Pre-fills device Google email when available on Android and automatically closes
/// once authenticated browser session cookies are detected.
class BrowserLoginConnectScreen extends StatefulWidget {
  final String? initialUrl;
  final String? prefillEmail;
  final String? providerLabel;

  const BrowserLoginConnectScreen({
    super.key,
    this.initialUrl,
    this.prefillEmail,
    this.providerLabel,
  });

  @override
  State<BrowserLoginConnectScreen> createState() =>
      _BrowserLoginConnectScreenState();
}

class _BrowserLoginConnectScreenState extends State<BrowserLoginConnectScreen> {
  InAppWebViewController? _webController;
  double _progress = 0;
  late String _currentUrl;
  bool _hasCompleted = false;
  bool _didInjectEmail = false;
  bool _hasAuthCookie = false;
  bool _isGoogleFlow = true;

  @override
  void initState() {
    super.initState();
    final raw = (widget.initialUrl ?? '').trim();
    _currentUrl = _normalizeConnectUrl(raw) ??
        _buildGoogleLoginUrl(prefillEmail: widget.prefillEmail);
    _isGoogleFlow = _isGoogleHost(_currentUrl);
  }

  static String _buildGoogleLoginUrl({String? prefillEmail}) {
    final email = (prefillEmail ?? '').trim();
    return Uri.https('accounts.google.com', '/ServiceLogin', {
      'continue': 'https://docs.google.com/forms',
      if (email.isNotEmpty) 'Email': email,
      if (email.isNotEmpty) 'login_hint': email,
    }).toString();
  }

  static bool _isGoogleHost(String url) {
    final host = (Uri.tryParse(url)?.host ?? '').toLowerCase();
    return host.contains('google.com') || host.contains('forms.gle');
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
    if (scheme != 'https' &&
        !(scheme == 'http' && AppConfig.isLocalOrPrivateHost(uri.host))) {
      return null;
    }
    return uri.toString();
  }

  String _resolveLabel(String loadedUrl) {
    if (widget.providerLabel != null && widget.providerLabel!.trim().isNotEmpty) {
      return widget.providerLabel!.trim();
    }
    if (_isGoogleFlow || _isGoogleHost(loadedUrl)) {
      return 'Akun Google';
    }
    final host = Uri.tryParse(loadedUrl)?.host ?? '';
    return host.isNotEmpty ? host : 'Portal Browser';
  }

  Future<void> _maybeAutofillGoogleEmail(
    InAppWebViewController controller,
    String url,
  ) async {
    final email = widget.prefillEmail?.trim() ?? '';
    if (email.isEmpty || _didInjectEmail) return;
    final host = (Uri.tryParse(url)?.host ?? '').toLowerCase();
    if (!host.contains('accounts.google.com')) return;

    _didInjectEmail = true;
    final encodedEmail = jsonEncode(email);
    for (int attempt = 0; attempt < 4; attempt++) {
      if (!mounted) return;
      final filled = await controller.evaluateJavascript(source: '''
        (function() {
          try {
            var targetEmail = $encodedEmail;
            var input = document.querySelector('input[type="email"], input#identifierId, input[name="identifier"]');
            if (!input) return false;
            var nativeSetter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value')?.set;
            if (input.value !== targetEmail) {
              input.focus();
              if (nativeSetter) {
                nativeSetter.call(input, targetEmail);
              } else {
                input.value = targetEmail;
              }
              input.dispatchEvent(new Event('input', { bubbles: true }));
              input.dispatchEvent(new Event('change', { bubbles: true }));
            }
            return input.value === targetEmail;
          } catch(e) { return false; }
        })();
      ''');
      if (filled == true) break;
      await Future.delayed(const Duration(milliseconds: 250));
    }
  }

  Future<void> _checkAuthCompletion(String loadedUrl) async {
    if (_hasCompleted || !mounted) return;
    try {
      final manager = CookieManager.instance();
      final uri = Uri.tryParse(loadedUrl);
      final hostCookies = uri != null
          ? await manager.getCookies(url: WebUri(uri.toString()))
          : <Cookie>[];
      final googleCookies = await manager.getCookies(
        url: WebUri('https://accounts.google.com'),
      );
      const googleAuthCookieNames = {
        'SID',
        'HSID',
        'SSID',
        'SAPISID',
        'APISID',
        '__Secure-1PSID',
        '__Secure-3PSID',
      };
      final hasGoogleAuth =
          googleCookies.any((c) => googleAuthCookieNames.contains(c.name));
      final lowerUrl = loadedUrl.toLowerCase();
      final stillOnGoogleSignIn =
          lowerUrl.contains('accounts.google.com') &&
          (lowerUrl.contains('servicelogin') ||
              lowerUrl.contains('signin') ||
              lowerUrl.contains('challenge'));
      final landedOnGoogleService =
          lowerUrl.contains('docs.google.com') ||
          lowerUrl.contains('myaccount.google.com');

      final hasSiteAuth = hostCookies.any((c) {
        final lower = c.name.toLowerCase();
        return lower.contains('session') ||
            lower.contains('token') ||
            lower.contains('auth') ||
            lower.contains('moodle');
      });

      final detected = _isGoogleFlow &&
          hasGoogleAuth &&
          (landedOnGoogleService || !stillOnGoogleSignIn);

      if (mounted) {
        setState(() => _hasAuthCookie = _isGoogleFlow ? hasGoogleAuth : hasSiteAuth);
      }

      if (detected) {
        await _completeAndClose(loadedUrl);
      }
    } catch (_) {
      // Ignore transient WebView cookie bridge errors during redirects
    }
  }

  Future<void> _completeAndClose([String? sourceUrl]) async {
    if (_hasCompleted) return;
    _hasCompleted = true;
    final urlToSave = sourceUrl ?? _currentUrl;
    await TokenStorage.setKeepBrowserLoginEnabled(true);
    await TokenStorage.saveBrowserLoginMeta(
      connected: true,
      label: _resolveLabel(urlToSave),
      email: widget.prefillEmail,
      url: urlToSave,
    );
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final bg = isDark ? AppTheme.backgroundDark : const Color(0xFFF8FAFC);
    final surface = isDark ? AppTheme.surfaceDark : Colors.white;
    final border = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subColor = isDark ? AppTheme.textSecondary : const Color(0xFF64748B);
    final currentUri = Uri.tryParse(_currentUrl);
    final allowLocalMixed =
        currentUri != null && AppConfig.isLocalOrPrivateHost(currentUri.host);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Tutup',
          icon: Icon(Icons.close_rounded, color: titleColor),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            Icon(
              Icons.lock_rounded,
              size: 15,
              color: _currentUrl.startsWith('https://')
                  ? AppTheme.accentGreen
                  : const Color(0xFFF59E0B),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isGoogleFlow ? 'Hubungkan Akun Google' : 'Login Portal Ujian',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: titleColor,
                    ),
                  ),
                  Text(
                    widget.prefillEmail?.isNotEmpty == true
                        ? widget.prefillEmail!
                        : (Uri.tryParse(_currentUrl)?.host ?? 'Autentikasi aman'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: subColor),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Muat Ulang',
            icon: Icon(Icons.refresh_rounded, color: titleColor, size: 20),
            onPressed: () => _webController?.reload(),
          ),
          if (!_isGoogleFlow || _hasAuthCookie)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: TextButton(
                onPressed: () => _completeAndClose(),
                style: TextButton.styleFrom(
                  backgroundColor: AppTheme.accentGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'Selesai',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Container(height: 1, color: border),
          if (_progress > 0 && _progress < 1.0)
            LinearProgressIndicator(
              value: _progress,
              minHeight: 2.5,
              color: AppTheme.primaryShiei,
              backgroundColor: Colors.transparent,
            ),
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
              onWebViewCreated: (controller) => _webController = controller,
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
              onUpdateVisitedHistory: (controller, url, _) async {
                if (url == null || !mounted) return;
                final updated = url.toString();
                setState(() => _currentUrl = updated);
                await _checkAuthCompletion(updated);
              },
              onLoadStop: (controller, url) async {
                if (url == null || !mounted) return;
                final loaded = url.toString();
                setState(() => _currentUrl = loaded);
                await _maybeAutofillGoogleEmail(controller, loaded);
                await _checkAuthCompletion(loaded);
              },
            ),
          ),
        ],
      ),
    );
  }
}
