import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../config/app_config.dart';
import '../../shared/theme/app_theme.dart';

class UrlExamPlayer extends StatefulWidget {
  final String url;
  final bool incognito;
  final VoidCallback onPageLoaded;
  final void Function(InAppWebViewController controller)? onControllerCreated;

  const UrlExamPlayer({
    super.key,
    required this.url,
    this.incognito = false,
    required this.onPageLoaded,
    this.onControllerCreated,
  });

  static const Set<String> _trustedMainFrameHosts = {
    'docs.google.com',
    'forms.gle',
    'accounts.google.com',
  };

  static const Set<String> _trustedSubresourceHosts = {
    'drive.google.com',
    'googleusercontent.com',
    'gstatic.com',
    'googleapis.com',
    'youtube.com',
    'youtube-nocookie.com',
    'youtu.be',
    'wikimedia.org',
    'cloudinary.com',
  };

  static bool _hostMatchesDomain(String host, String domain) {
    if (domain.isEmpty || host.isEmpty) return false;
    return host == domain || host.endsWith('.$domain');
  }

  /// Validates WebView navigation URLs against allowed schemes, local-only HTTP, and trusted host rules.
  static bool isUrlAllowed(String candidateUrl, String examUrl, {bool isMainFrame = true}) {
    final uri = Uri.tryParse(candidateUrl.trim());
    if (uri == null || uri.scheme.isEmpty) return false;

    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'https' && scheme != 'http') {
      return false;
    }

    final host = uri.host.toLowerCase();
    if (host.isEmpty) return false;

    // Plain HTTP is strictly allowed only for local/private network servers.
    if (scheme == 'http' && !AppConfig.isLocalOrPrivateHost(host)) {
      return false;
    }

    // Subresources / embedded frames must stay on valid http(s), never external cleartext or custom schemes.
    if (!isMainFrame) {
      return _trustedMainFrameHosts.any((domain) => _hostMatchesDomain(host, domain)) ||
          _trustedSubresourceHosts.any((domain) => _hostMatchesDomain(host, domain)) ||
          (Uri.tryParse(examUrl.trim())?.host.toLowerCase() == host);
    }

    final examUri = Uri.tryParse(examUrl.trim());
    final examHost = examUri?.host.toLowerCase() ?? '';
    final isExamHost = examHost.isNotEmpty && _hostMatchesDomain(host, examHost);
    final isAnchor = examUri != null && uri.fragment.isNotEmpty && uri.path == examUri.path && host == examHost;
    final isTrustedProvider = _trustedMainFrameHosts.any((domain) => _hostMatchesDomain(host, domain));

    return isExamHost || isAnchor || isTrustedProvider;
  }

  /// Clean Chrome/Safari mobile User-Agent so Google & SSO providers accept WebView login.
  static String get browserCompatibleUserAgent => Platform.isIOS
      ? 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1'
      : 'Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';

  /// Clears all WebView cookies & web storage when browser login persistence is disabled or reset.
  static Future<void> clearBrowserSessionCookies() async {
    try {
      await CookieManager.instance().deleteAllCookies();
      await WebStorageManager.instance().deleteAllData();
    } catch (_) {}
  }

  /// Removes locally cached shiei_autosave_* form drafts after exam completion.
  static Future<void> clearAutosaveStorage(InAppWebViewController? controller) async {
    if (controller == null) return;
    try {
      await controller.evaluateJavascript(source: """
        (function() {
          try {
            var toDelete = [];
            for (var i = 0; i < localStorage.length; i++) {
              var k = localStorage.key(i);
              if (k && k.indexOf('shiei_autosave_') === 0) toDelete.push(k);
            }
            for (var j = 0; j < toDelete.length; j++) {
              localStorage.removeItem(toDelete[j]);
            }
          } catch(e) {}
        })();
      """);
    } catch (_) {}
  }

  @override
  State<UrlExamPlayer> createState() => _UrlExamPlayerState();
}

class _UrlExamPlayerState extends State<UrlExamPlayer> {
  InAppWebViewController? _webViewController;
  double _loadProgress = 0;

  InAppWebViewController? get webViewController => _webViewController;

  @override
  Widget build(BuildContext context) {
    final examInitialUri = Uri.tryParse(widget.url);
    final allowLocalMixedContent =
        examInitialUri != null && AppConfig.isLocalOrPrivateHost(examInitialUri.host);

    return Stack(
      children: [
        InAppWebView(
          initialUrlRequest: URLRequest(url: WebUri(widget.url)),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            useShouldOverrideUrlLoading: true,
            supportZoom: false,
            incognito: widget.incognito,
            saveFormData: false,
            disableContextMenu: true, // Disables text copy/paste selection menu
            clearCache: widget.incognito,
            cacheEnabled: !widget.incognito,
            thirdPartyCookiesEnabled: !widget.incognito,
            sharedCookiesEnabled: !widget.incognito,
            userAgent: UrlExamPlayer.browserCompatibleUserAgent,
            hardwareAcceleration: true,
            transparentBackground: false,
            allowsInlineMediaPlayback: true, // Essential for teacher audio listening and video clips
            mediaPlaybackRequiresUserGesture: false, // Smooth audio/video start
            mixedContentMode: allowLocalMixedContent
                ? MixedContentMode.MIXED_CONTENT_COMPATIBILITY_MODE
                : MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
            domStorageEnabled: true,
            databaseEnabled: true,
            // iOS specific kiosk hardening
            allowsBackForwardNavigationGestures: false, // Disables Safari edge-swipe gesture navigation
            allowsLinkPreview: false, // Disables 3D Touch / Haptic preview popups on hyperlinks
            isInspectable: kDebugMode, // Disables Safari Web Inspector in production release builds
          ),
          shouldOverrideUrlLoading: (controller, navigationAction) async {
            final uri = navigationAction.request.url;
            if (uri == null) return NavigationActionPolicy.CANCEL;

            if (UrlExamPlayer.isUrlAllowed(
              uri.toString(),
              widget.url,
              isMainFrame: navigationAction.isForMainFrame,
            )) {
              return NavigationActionPolicy.ALLOW;
            }

            // Block external browsing, non-http(s) schemes, or public HTTP attempts outside exam scope
            debugPrint('[UrlExamPlayer] Blocked unauthorized navigation attempt to: $uri');
            return NavigationActionPolicy.CANCEL;
          },
          onWebViewCreated: (controller) {
            _webViewController = controller;
            widget.onControllerCreated?.call(controller);
          },
          onProgressChanged: (controller, progress) {
            setState(() {
              _loadProgress = progress / 100;
            });
          },
          onLoadStop: (controller, url) async {
            // 1. Inject anti-copy, anti-select, and anti-print JavaScript rules
            await controller.evaluateJavascript(source: """
              (function() {
                var style = document.createElement('style');
                style.innerHTML = `
                  * {
                    -webkit-user-select: none !important;
                    -moz-user-select: none !important;
                    -ms-user-select: none !important;
                    user-select: none !important;
                    -webkit-touch-callout: none !important;
                  }
                  input, textarea {
                    -webkit-user-select: text !important;
                    user-select: text !important;
                  }
                `;
                document.head.appendChild(style);

                document.addEventListener('contextmenu', function(e) {
                  e.preventDefault();
                }, true);

                document.addEventListener('copy', function(e) {
                  if (e.target && (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA')) return;
                  e.preventDefault();
                }, true);

                document.addEventListener('cut', function(e) {
                  if (e.target && (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA')) return;
                  e.preventDefault();
                }, true);

                document.addEventListener('paste', function(e) {
                  e.preventDefault();
                }, true);

                window.print = function() { return false; };
              })();
            """);

            // 2. Inject form auto-save mirroring for 3rd-party forms (e.g. Google Form)
            await controller.evaluateJavascript(source: """
              (function() {
                try {
                  var storeKey = 'shiei_autosave_' + encodeURIComponent(window.location.href);
                  var saved = localStorage.getItem(storeKey);
                  if (saved) {
                    try {
                      var data = JSON.parse(saved);
                      for (var name in data) {
                        var input = document.querySelector('[name="' + name + '"]') || document.getElementById(name);
                        if (input && !input.value) {
                          input.value = data[name];
                          input.dispatchEvent(new Event('input', { bubbles: true }));
                          input.dispatchEvent(new Event('change', { bubbles: true }));
                        }
                      }
                    } catch(e) {}
                  }

                  document.addEventListener('input', function(e) {
                    if (!e.target || !e.target.name) return;
                    try {
                      var cur = JSON.parse(localStorage.getItem(storeKey) || '{}');
                      cur[e.target.name] = e.target.value;
                      localStorage.setItem(storeKey, JSON.stringify(cur));
                    } catch(e) {}
                  }, true);
                } catch(e) {}
              })();
            """);

            widget.onPageLoaded();
          },
        ),

        // Progress bar indicator
        if (_loadProgress < 1.0)
          LinearProgressIndicator(
            value: _loadProgress,
            color: AppTheme.primaryBlue,
            backgroundColor: AppTheme.surfaceDark,
            minHeight: 3,
          ),
      ],
    );
  }
}
