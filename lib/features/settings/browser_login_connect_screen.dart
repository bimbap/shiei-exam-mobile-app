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
  final String? previousEmail;

  const BrowserLoginConnectScreen({
    super.key,
    this.initialUrl,
    this.prefillEmail,
    this.providerLabel,
    this.previousEmail,
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
  bool _didTryAuthUserSwitch = false;
  bool _hasAuthCookie = false;
  bool _isGoogleFlow = true;
  late bool _isSwitchingOrAdding;

  @override
  void initState() {
    super.initState();
    final raw = (widget.initialUrl ?? '').trim();
    final prefill = (widget.prefillEmail ?? '').trim().toLowerCase();
    final prev = (widget.previousEmail ?? '').trim().toLowerCase();
    final isDifferentEmail =
        prefill.isNotEmpty && prev.isNotEmpty && prefill != prev;
    final isAddSessionUrl = raw.toLowerCase().contains('addsession');
    _isSwitchingOrAdding =
        isAddSessionUrl || isDifferentEmail || (prefill.isEmpty && prev.isNotEmpty);

    _currentUrl = _normalizeConnectUrl(raw) ??
        _buildGoogleLoginUrl(
          prefillEmail: widget.prefillEmail,
          forceAddSession: isDifferentEmail,
        );
    _isGoogleFlow = _isGoogleHost(_currentUrl);
  }

  static String _buildGoogleLoginUrl({
    String? prefillEmail,
    bool forceAddSession = false,
  }) {
    final email = (prefillEmail ?? '').trim();
    if (email.isNotEmpty && !forceAddSession) {
      return Uri.https('accounts.google.com', '/AccountChooser', {
        'continue': 'https://docs.google.com/forms',
        'Email': email,
        'login_hint': email,
      }).toString();
    }
    return Uri.https('accounts.google.com', '/AddSession', {
      'continue': 'https://docs.google.com/forms',
      if (email.isNotEmpty) 'Email': email,
      if (email.isNotEmpty) 'login_hint': email,
    }).toString();
  }

  static bool _isAccountsGoogleUrl(String url) {
    final host = (Uri.tryParse(url)?.host ?? '').toLowerCase();
    return host.contains('accounts.google.com');
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
      final onAccountsGoogle = _isAccountsGoogleUrl(loadedUrl);
      final landedOnGoogleService = !onAccountsGoogle &&
          (lowerUrl.contains('docs.google.com') ||
              lowerUrl.contains('myaccount.google.com'));

      final hasSiteAuth = hostCookies.any((c) {
        final lower = c.name.toLowerCase();
        return lower.contains('session') ||
            lower.contains('token') ||
            lower.contains('auth') ||
            lower.contains('moodle');
      });

      final readyToComplete = _isGoogleFlow
          ? (hasGoogleAuth && !onAccountsGoogle && landedOnGoogleService)
          : hasSiteAuth;

      if (mounted) {
        setState(
          () => _hasAuthCookie =
              _isGoogleFlow ? (hasGoogleAuth && !onAccountsGoogle) : hasSiteAuth,
        );
      }

      if (_isGoogleFlow && readyToComplete) {
        final extracted = await _extractSignedInGoogleEmail();
        final prevLower = (widget.previousEmail ?? '').trim().toLowerCase();
        final prefill = (widget.prefillEmail ?? '').trim();

        // If switching to a specific different email, ensure Forms actually switched authuser
        if (prefill.isNotEmpty &&
            extracted != null &&
            extracted.toLowerCase() != prefill.toLowerCase()) {
          if (!_didTryAuthUserSwitch && _webController != null) {
            _didTryAuthUserSwitch = true;
            final switchUrl = Uri.https('docs.google.com', '/forms', {
              'authuser': prefill,
            }).toString();
            await _webController!.loadUrl(
              urlRequest: URLRequest(url: WebUri(switchUrl)),
            );
            return;
          }
          // Still on the old account — let the user complete login or press Selesai manually
          return;
        }

        // During AddSession (no prefill), avoid auto-closing if landing still shows old account
        if (_isSwitchingOrAdding &&
            prefill.isEmpty &&
            prevLower.isNotEmpty &&
            extracted != null &&
            extracted.toLowerCase() == prevLower) {
          return;
        }

        await _completeAndClose(loadedUrl, extracted);
      }
    } catch (_) {
      // Ignore transient WebView cookie bridge errors during redirects
    }
  }

  Future<String?> _extractSignedInGoogleEmail() async {
    final controller = _webController;
    if (controller == null || !_isGoogleFlow) return null;
    try {
      final res = await controller.evaluateJavascript(source: '''
        (function() {
          try {
            var priorityNodes = document.querySelectorAll('a[href*="SignOutOptions"], a[aria-label*="Akun Google"], a[aria-label*="Google Account"], [data-email]');
            for (var i = 0; i < priorityNodes.length; i++) {
              var val = (priorityNodes[i].getAttribute('data-email') || priorityNodes[i].getAttribute('aria-label') || priorityNodes[i].innerText || '');
              var m = val.match(/[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}/);
              if (m) return m[0];
            }
            var body = document.body ? (document.body.innerText || '') : '';
            var bm = body.match(/[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}/);
            return bm ? bm[0] : null;
          } catch(e) { return null; }
        })();
      ''');
      final candidate = res?.toString().trim();
      if (candidate != null && candidate.contains('@') && !candidate.contains('null')) {
        return candidate;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _completeAndClose([
    String? sourceUrl,
    String? extractedEmail,
  ]) async {
    if (_hasCompleted) return;
    _hasCompleted = true;
    final urlToSave = sourceUrl ?? _currentUrl;
    String? resolvedEmail = widget.prefillEmail?.trim();
    if (resolvedEmail == null || resolvedEmail.isEmpty) {
      resolvedEmail = extractedEmail ?? await _extractSignedInGoogleEmail();
    }
    await TokenStorage.setKeepBrowserLoginEnabled(true);
    await TokenStorage.saveBrowserLoginMeta(
      connected: true,
      label: _resolveLabel(urlToSave),
      email: resolvedEmail,
      url: urlToSave,
      clearEmailIfMissing: _isSwitchingOrAdding,
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
