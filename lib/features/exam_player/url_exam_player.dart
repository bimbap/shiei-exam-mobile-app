import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../shared/theme/app_theme.dart';

class UrlExamPlayer extends StatefulWidget {
  final String url;
  final VoidCallback onPageLoaded;
  final void Function(InAppWebViewController controller)? onControllerCreated;

  const UrlExamPlayer({
    super.key,
    required this.url,
    required this.onPageLoaded,
    this.onControllerCreated,
  });

  @override
  State<UrlExamPlayer> createState() => _UrlExamPlayerState();
}

class _UrlExamPlayerState extends State<UrlExamPlayer> {
  InAppWebViewController? _webViewController;
  double _loadProgress = 0;

  InAppWebViewController? get webViewController => _webViewController;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        InAppWebView(
          initialUrlRequest: URLRequest(url: WebUri(widget.url)),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            useShouldOverrideUrlLoading: true,
            supportZoom: false,
            disableContextMenu: true, // Disables text copy/paste selection menu
            clearCache: false,
            hardwareAcceleration: true,
            transparentBackground: false,
            allowsInlineMediaPlayback: true, // Essential for teacher audio listening and video clips
            mediaPlaybackRequiresUserGesture: false, // Smooth audio/video start
            mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW, // Allow HTTP/HTTPS media resources
            domStorageEnabled: true,
            databaseEnabled: true,
          ),
          shouldOverrideUrlLoading: (controller, navigationAction) async {
            final uri = navigationAction.request.url;
            if (uri == null) return NavigationActionPolicy.ALLOW;

            // 1. Media Subresources (diagrams, audio listening clips, Google Drive streams, CDN videos, iframes)
            // MUST ALWAYS BE ALLOWED so questions render completely.
            if (!navigationAction.isForMainFrame) {
              return NavigationActionPolicy.ALLOW;
            }

            // 2. Main Frame Navigation (top-level page):
            // Check if navigation stays within exam domain or permitted media/form embed hosts
            final examUri = WebUri(widget.url);
            final host = uri.host.toLowerCase();
            final examHost = examUri.host.toLowerCase();

            final isExamHost = host == examHost || (examHost.isNotEmpty && host.endsWith('.$examHost'));
            final isAnchor = uri.fragment.isNotEmpty && uri.path == examUri.path;

            // Trusted educational media and form providers placed by teachers
            final isTrustedProvider = host.endsWith('google.com') ||
                host.endsWith('googleapis.com') ||
                host.endsWith('gstatic.com') ||
                host.endsWith('drive.google.com') ||
                host.endsWith('docs.google.com') ||
                host.endsWith('youtube.com') ||
                host.endsWith('youtu.be') ||
                host.endsWith('wikimedia.org') ||
                host.endsWith('cloudinary.com') ||
                host.endsWith('amazonaws.com');

            if (isExamHost || isAnchor || isTrustedProvider) {
              return NavigationActionPolicy.ALLOW;
            }

            // Block external browsing attempt outside authorized exam scope
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
