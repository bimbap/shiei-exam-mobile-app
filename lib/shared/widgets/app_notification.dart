import 'dart:async';
import 'package:flutter/material.dart';
import '../../main.dart' show appNavigatorKey;
import '../theme/app_theme.dart';

enum NotificationType { success, warning, error, info }

class AppNotification {
  static OverlayEntry? _activeEntry;
  static Timer? _activeTimer;

  static void hide() {
    _activeTimer?.cancel();
    _activeTimer = null;
    final entry = _activeEntry;
    _activeEntry = null;
    if (entry != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          if (entry.mounted) {
            entry.remove();
          }
        } catch (_) {}
      });
    }
  }

  static void show(
    BuildContext context, {
    required String title,
    String? subtitle,
    NotificationType type = NotificationType.info,
    Duration duration = const Duration(milliseconds: 3200),
    IconData? customIcon,
  }) {
    // Dismiss existing active notification immediately
    hide();

    final overlay = appNavigatorKey.currentState?.overlay ??
        Overlay.maybeOf(context, rootOverlay: true) ??
        Overlay.maybeOf(context);
    if (overlay == null) return;

    Color accentColor;
    IconData iconData;

    switch (type) {
      case NotificationType.success:
        accentColor = const Color(0xFF10B981);
        iconData = Icons.check_circle_rounded;
        break;
      case NotificationType.warning:
        accentColor = const Color(0xFFF59E0B);
        iconData = Icons.shield_outlined;
        break;
      case NotificationType.error:
        accentColor = AppTheme.dangerRed;
        iconData = Icons.error_outline_rounded;
        break;
      case NotificationType.info:
        accentColor = AppTheme.primaryGlow;
        iconData = Icons.info_outline_rounded;
        break;
    }

    if (customIcon != null) {
      iconData = customIcon;
    }

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _TopNotificationWidget(
        title: title,
        subtitle: subtitle,
        accentColor: accentColor,
        iconData: iconData,
        duration: duration,
        onDismiss: () {
          if (_activeEntry == entry) {
            hide();
          }
        },
      ),
    );

    _activeEntry = entry;
    overlay.insert(entry);
  }

  static void showSuccess(BuildContext context, String title, {String? subtitle, IconData? customIcon}) {
    show(context, title: title, subtitle: subtitle, type: NotificationType.success, customIcon: customIcon);
  }

  static void showWarning(BuildContext context, String title, {String? subtitle, IconData? customIcon}) {
    show(context, title: title, subtitle: subtitle, type: NotificationType.warning, customIcon: customIcon);
  }

  static void showError(BuildContext context, String title, {String? subtitle, IconData? customIcon}) {
    show(context, title: title, subtitle: subtitle, type: NotificationType.error, customIcon: customIcon);
  }

  static void showInfo(BuildContext context, String title, {String? subtitle, IconData? customIcon}) {
    show(context, title: title, subtitle: subtitle, type: NotificationType.info, customIcon: customIcon);
  }
}

class _TopNotificationWidget extends StatefulWidget {
  final String title;
  final String? subtitle;
  final Color accentColor;
  final IconData iconData;
  final Duration duration;
  final VoidCallback onDismiss;

  const _TopNotificationWidget({
    required this.title,
    this.subtitle,
    required this.accentColor,
    required this.iconData,
    required this.duration,
    required this.onDismiss,
  });

  @override
  State<_TopNotificationWidget> createState() => _TopNotificationWidgetState();
}

class _TopNotificationWidgetState extends State<_TopNotificationWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      reverseDuration: const Duration(milliseconds: 240),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1.2),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animController,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _animController,
        curve: Curves.easeOut,
      ),
    );

    _animController.forward();

    _dismissTimer = Timer(widget.duration, () {
      _dismissWithAnimation();
    });
  }

  void _dismissWithAnimation() {
    if (!mounted) return;
    _dismissTimer?.cancel();
    _animController.reverse().then((_) {
      if (mounted) {
        widget.onDismiss();
      }
    });
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: SlideTransition(
          position: _slideAnimation,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: GestureDetector(
                onVerticalDragUpdate: (details) {
                  if (details.primaryDelta != null && details.primaryDelta! < -4) {
                    _dismissWithAnimation();
                  }
                },
                child: Material(
                  color: Colors.transparent,
                  child: Builder(
                    builder: (ctx) {
                      final isDark = AppTheme.isDark(ctx);
                      final cardBg = isDark
                          ? const Color(0xFF0B1120).withValues(alpha: 0.96)
                          : Colors.white.withValues(alpha: 0.98);
                      final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
                      final subColor = isDark ? AppTheme.textSecondary : const Color(0xFF475569);
                      final closeColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: widget.accentColor.withValues(alpha: isDark ? 0.55 : 0.45),
                            width: 1.2,
                          ),
                          boxShadow: isDark
                              ? [
                                  BoxShadow(
                                    color: widget.accentColor.withValues(alpha: 0.22),
                                    blurRadius: 18,
                                    spreadRadius: 1,
                                    offset: const Offset(0, 4),
                                  ),
                                  const BoxShadow(
                                    color: Colors.black87,
                                    blurRadius: 16,
                                    offset: Offset(0, 6),
                                  ),
                                ]
                              : [
                                  BoxShadow(
                                    color: widget.accentColor.withValues(alpha: 0.16),
                                    blurRadius: 14,
                                    offset: const Offset(0, 4),
                                  ),
                                  BoxShadow(
                                    color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                                    blurRadius: 20,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: widget.accentColor.withValues(alpha: isDark ? 0.16 : 0.12),
                                border: Border.all(
                                  color: widget.accentColor.withValues(alpha: isDark ? 0.4 : 0.3),
                                  width: 1.2,
                                ),
                              ),
                              child: Icon(widget.iconData, color: widget.accentColor, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.title,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: titleColor,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                  if (widget.subtitle != null && widget.subtitle!.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      widget.subtitle!,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: subColor,
                                        height: 1.3,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.close_rounded, size: 16, color: closeColor),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                              onPressed: _dismissWithAnimation,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
