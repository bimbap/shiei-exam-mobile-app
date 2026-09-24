import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

/// A bespoke squircle checkbox featuring an animated vector-drawn checkmark stroke,
/// tactile elastic spring bounce on check, smooth recoil & dissolve on uncheck,
/// interpolated specular gradient, and tactile haptics.
class ShieiCheckbox extends StatefulWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool indeterminate;
  final Color? activeColor;
  final Color? checkColor;
  final double size;
  final double borderRadius;
  final bool disabled;
  final bool enableHaptics;

  const ShieiCheckbox({
    super.key,
    required this.value,
    this.onChanged,
    this.indeterminate = false,
    this.activeColor,
    this.checkColor,
    this.size = 22.0,
    this.borderRadius = 7.5,
    this.disabled = false,
    this.enableHaptics = true,
  });

  @override
  State<ShieiCheckbox> createState() => _ShieiCheckboxState();
}

class _ShieiCheckboxState extends State<ShieiCheckbox> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _checkStrokeAnim;
  late Animation<double> _elasticScaleAnim;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 160),
      value: widget.value ? 1.0 : 0.0,
    );

    _checkStrokeAnim = CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.20, 1.0, curve: Curves.easeOutCubic),
    );

    _elasticScaleAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.10), weight: 45),
      TweenSequenceItem(tween: Tween(begin: 1.10, end: 1.0), weight: 55),
    ]).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    ));
  }

  @override
  void didUpdateWidget(covariant ShieiCheckbox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      if (widget.value) {
        _animController.forward(from: 0.0);
      } else {
        _animController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (widget.disabled || widget.onChanged == null) return;
    if (widget.enableHaptics) {
      HapticFeedback.selectionClick();
    }
    widget.onChanged!(!widget.value);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final activeCol = widget.activeColor ?? const Color(0xFF8B5CF6);
    final checkCol = widget.checkColor ?? Colors.white;

    final Color idleBg = isDark
        ? const Color(0xFF1E293B).withValues(alpha: 0.85)
        : Colors.white;
    final Color idleBorder = isDark
        ? const Color(0xFF475569)
        : const Color(0xFFCBD5E1);

    return GestureDetector(
      onTapDown: widget.disabled ? null : (_) => setState(() => _isPressed = true),
      onTapUp: widget.disabled ? null : (_) => setState(() => _isPressed = false),
      onTapCancel: widget.disabled ? null : () => setState(() => _isPressed = false),
      onTap: _handleTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _animController,
        builder: (context, child) {
          final double progress = _animController.value;

          // Smooth elastic scale:
          // - When pressing: compress to 0.86
          // - When checking forward: pop to 1.10 and settle at 1.0
          // - When unchecking reverse: tactile recoil dip to 0.93 and settle at 1.0
          double motionScale = 1.0;
          if (_isPressed) {
            motionScale = 0.86;
          } else if (_animController.status == AnimationStatus.forward) {
            motionScale = _elasticScaleAnim.value;
          } else if (_animController.status == AnimationStatus.reverse) {
            motionScale = 1.0 - (math.sin(progress * math.pi) * 0.07);
          }

          // Smoothly interpolate border color and background fill
          final Color currentBorder = Color.lerp(idleBorder, activeCol, progress)!;
          final Color darkerActiveCol = Color.lerp(activeCol, Colors.black, 0.14) ?? activeCol;

          return Transform.scale(
            scale: motionScale,
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(widget.borderRadius),
                gradient: progress > 0.02
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color.lerp(idleBg, activeCol, progress)!,
                          Color.lerp(idleBg, darkerActiveCol, progress)!,
                        ],
                      )
                    : null,
                color: progress <= 0.02 ? idleBg : null,
                border: Border.all(
                  color: currentBorder,
                  width: ui.lerpDouble(1.7, 1.6, progress)!,
                ),
                boxShadow: [
                  if (progress > 0.02)
                    BoxShadow(
                      color: activeCol.withValues(alpha: 0.40 * progress),
                      blurRadius: 8 * progress,
                      offset: Offset(0, 2.5 * progress),
                    ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: (isDark ? 0.15 : 0.04) * (1.0 - progress)),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Center(
                child: widget.indeterminate
                    ? Opacity(
                        opacity: progress,
                        child: Container(
                          width: widget.size * 0.45,
                          height: 2.5,
                          decoration: BoxDecoration(
                            color: checkCol,
                            borderRadius: BorderRadius.circular(1.5),
                          ),
                        ),
                      )
                    : Transform.scale(
                        // Checkmark scales down and fades out cleanly on uncheck
                        scale: _animController.status == AnimationStatus.reverse
                            ? (0.75 + 0.25 * progress)
                            : 1.0,
                        child: Opacity(
                          opacity: _animController.status == AnimationStatus.reverse
                              ? (progress * 1.3).clamp(0.0, 1.0)
                              : (_checkStrokeAnim.value > 0.0 ? 1.0 : 0.0),
                          child: CustomPaint(
                            size: Size(widget.size, widget.size),
                            painter: _AnimatedCheckmarkPainter(
                              progress: _animController.status == AnimationStatus.reverse
                                  ? 1.0
                                  : _checkStrokeAnim.value,
                              color: checkCol,
                              strokeWidth: widget.size * 0.10,
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Custom painter that draws the checkmark vector path with animated stroke progression.
class _AnimatedCheckmarkPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double strokeWidth;

  _AnimatedCheckmarkPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.0) return;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth.clamp(1.8, 3.0)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    // Start point of checkmark (left-middle)
    final start = Offset(size.width * 0.27, size.height * 0.52);
    // Knee point (bottom-middle)
    final knee = Offset(size.width * 0.43, size.height * 0.70);
    // End point (top-right)
    final end = Offset(size.width * 0.75, size.height * 0.32);

    path.moveTo(start.dx, start.dy);
    path.lineTo(knee.dx, knee.dy);
    path.lineTo(end.dx, end.dy);

    for (final ui.PathMetric metric in path.computeMetrics()) {
      final double extractLength = metric.length * progress.clamp(0.0, 1.0);
      final ui.Path extractedPath = metric.extractPath(0.0, extractLength);
      canvas.drawPath(extractedPath, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _AnimatedCheckmarkPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

/// Interactive tile containing an animated squircle ShieiCheckbox, title, subtitle,
/// optional leading icon, and smooth pressed feedback.
class ShieiCheckboxTile extends StatelessWidget {
  final bool value;
  final ValueChanged<bool?>? onChanged;
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? activeColor;
  final bool isDark;
  final bool disabled;
  final Widget? trailing;

  const ShieiCheckboxTile({
    super.key,
    required this.value,
    required this.onChanged,
    required this.title,
    this.subtitle,
    this.icon,
    this.activeColor,
    required this.isDark,
    this.disabled = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveActiveColor = activeColor ?? const Color(0xFF8B5CF6);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        color: value
            ? effectiveActiveColor.withValues(alpha: isDark ? 0.14 : 0.08)
            : (isDark ? const Color(0xFF1E293B).withValues(alpha: 0.5) : const Color(0xFFF8FAFC)),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: value
              ? effectiveActiveColor.withValues(alpha: isDark ? 0.7 : 0.5)
              : (isDark ? const Color(0xFF334155).withValues(alpha: 0.6) : const Color(0xFFE2E8F0)),
          width: value ? 1.5 : 1.0,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: disabled || onChanged == null
              ? null
              : () {
                  onChanged!(!value);
                },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                ShieiCheckbox(
                  value: value,
                  activeColor: effectiveActiveColor,
                  disabled: disabled,
                  onChanged: disabled || onChanged == null ? null : (v) => onChanged!(v),
                ),
                const SizedBox(width: 12),
                if (icon != null) ...[
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: value
                          ? effectiveActiveColor.withValues(alpha: 0.15)
                          : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      icon,
                      size: 17,
                      color: value
                          ? effectiveActiveColor
                          : (isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: value ? FontWeight.bold : FontWeight.w500,
                          color: value
                              ? effectiveActiveColor
                              : (isDark ? Colors.white : const Color(0xFF0F172A)),
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 8),
                  trailing!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
