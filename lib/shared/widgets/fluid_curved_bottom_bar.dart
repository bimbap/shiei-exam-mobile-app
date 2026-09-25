import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../theme/app_theme.dart';

class FluidNavItem {
  final IconData icon;
  final IconData? activeIcon;
  final String label;

  const FluidNavItem({
    required this.icon,
    this.activeIcon,
    required this.label,
  });
}

class FluidCurvedBottomBar extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<FluidNavItem> items;
  final Color backgroundColor;
  final Color activeColor;
  final Color inactiveColor;
  final Color borderColor;

  const FluidCurvedBottomBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
    this.backgroundColor = const Color(0xFF0F172A),
    this.activeColor = AppTheme.primaryGlow,
    this.inactiveColor = const Color(0xFF64748B),
    this.borderColor = const Color(0xFF1E293B),
  }) : assert(items.length >= 2);

  @override
  State<FluidCurvedBottomBar> createState() => _FluidCurvedBottomBarState();
}

class _FluidCurvedBottomBarState extends State<FluidCurvedBottomBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _notchAnimation;
  int _previousIndex = 0;

  @override
  void initState() {
    super.initState();
    _previousIndex = widget.currentIndex;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );
    _notchAnimation = Tween<double>(
      begin: widget.currentIndex.toDouble(),
      end: widget.currentIndex.toDouble(),
    ).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic),
    );
  }

  @override
  void didUpdateWidget(covariant FluidCurvedBottomBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex) {
      _previousIndex = oldWidget.currentIndex;
      _notchAnimation = Tween<double>(
        begin: _previousIndex.toDouble(),
        end: widget.currentIndex.toDouble(),
      ).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic),
      );
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const double barHeight = 64.0;
    const double notchWidth = 64.0;
    const double notchDepth = 20.0;
    const double bubbleSize = 46.0;
    const double barRadius = 28.0;
    const double horizontalPadding = 14.0;

    final isDark = AppTheme.isDark(context);

    return SafeArea(
      top: false,
      left: false,
      right: false,
      bottom: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Align(
          alignment: Alignment.bottomCenter,
          heightFactor: 1.0,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final double totalWidth = constraints.maxWidth;
                final double availableWidth = totalWidth - (horizontalPadding * 2);
                final double itemWidth = availableWidth / widget.items.length;

                return AnimatedBuilder(
                  animation: _notchAnimation,
                  builder: (context, child) {
                    final double currentPos = _notchAnimation.value;
                    final double notchCenterX =
                        horizontalPadding + (currentPos + 0.5) * itemWidth;

                    return _OverflowHitTest(
                      child: SizedBox(
                        height: barHeight,
                        child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // 1. Custom Painted Bar Body with Curved Notch
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _FluidNotchPainter(
                                notchCenterX: notchCenterX,
                                notchWidth: notchWidth,
                                notchDepth: notchDepth,
                                barRadius: barRadius,
                                backgroundColor: widget.backgroundColor,
                                borderColor: widget.borderColor,
                                isDark: isDark,
                              ),
                            ),
                          ),

                          // 2. Clickable Navigation Tabs (Row)
                          Positioned.fill(
                            left: horizontalPadding,
                            right: horizontalPadding,
                            child: Row(
                              children: List.generate(widget.items.length, (index) {
                                final item = widget.items[index];
                                final isSelected = index == widget.currentIndex;

                                return Expanded(
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () => widget.onTap(index),
                                    child: Container(
                                      alignment: Alignment.bottomCenter,
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Opacity(
                                        opacity: isSelected ? 1.0 : 0.65,
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (!isSelected) ...[
                                              Icon(
                                                item.icon,
                                                size: 22,
                                                color: widget.inactiveColor,
                                              ),
                                              const SizedBox(height: 3),
                                            ] else ...[
                                              const SizedBox(height: 25),
                                            ],
                                            Text(
                                              item.label,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: isSelected
                                                    ? FontWeight.bold
                                                    : FontWeight.w500,
                                                color: isSelected
                                                    ? widget.activeColor
                                                    : widget.inactiveColor,
                                                letterSpacing: 0.2,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ),
                          ),

                          // 3. Elevated Floating Pill / Bubble
                          Positioned(
                            left: notchCenterX - (bubbleSize / 2),
                            top: -14, // Elevated above the bar body by 14px
                            child: GestureDetector(
                              onTap: () => widget.onTap(widget.currentIndex),
                              child: Container(
                                width: bubbleSize,
                                height: bubbleSize,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: isDark
                                        ? const [
                                            Color(0xFF23354E),
                                            Color(0xFF0F172A),
                                          ]
                                        : const [
                                            Colors.white,
                                            Color(0xFFFFF7ED),
                                          ],
                                  ),
                                  border: Border.all(
                                    color: widget.activeColor.withValues(
                                      alpha: isDark ? 0.55 : 0.45,
                                    ),
                                    width: 2,
                                  ),
                                  boxShadow: isDark
                                      ? [
                                          BoxShadow(
                                            color: widget.activeColor.withValues(alpha: 0.35),
                                            blurRadius: 14,
                                            spreadRadius: 1,
                                            offset: const Offset(0, 4),
                                          ),
                                          const BoxShadow(
                                            color: Colors.black54,
                                            blurRadius: 10,
                                            offset: Offset(0, 4),
                                          ),
                                        ]
                                      : [
                                          BoxShadow(
                                            color: widget.activeColor.withValues(alpha: 0.28),
                                            blurRadius: 12,
                                            spreadRadius: 1,
                                            offset: const Offset(0, 3),
                                          ),
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.08),
                                            blurRadius: 8,
                                            offset: const Offset(0, 3),
                                          ),
                                        ],
                                ),
                                child: Center(
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 220),
                                    transitionBuilder: (child, anim) => ScaleTransition(
                                      scale: anim,
                                      child: child,
                                    ),
                                    child: Icon(
                                      widget.items[widget.currentIndex].activeIcon ??
                                          widget.items[widget.currentIndex].icon,
                                      key: ValueKey<int>(widget.currentIndex),
                                      size: 22,
                                      color: widget.activeColor,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _FluidNotchPainter extends CustomPainter {
  final double notchCenterX;
  final double notchWidth;
  final double notchDepth;
  final double barRadius;
  final Color backgroundColor;
  final Color borderColor;
  final bool isDark;

  _FluidNotchPainter({
    required this.notchCenterX,
    required this.notchWidth,
    required this.notchDepth,
    required this.barRadius,
    required this.backgroundColor,
    required this.borderColor,
    this.isDark = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final double r = barRadius.clamp(12.0, h / 2);

    final double cx = notchCenterX.clamp(notchWidth / 2 + 1.0, w - notchWidth / 2 - 1.0);
    final double nw = notchWidth;
    final double nd = notchDepth;

    final double x1 = cx - nw / 2;
    final double x2 = cx + nw / 2;

    final double topLeftR = min(r, max(4.0, x1));
    final double topRightR = min(r, max(4.0, w - x2));

    final path = Path();

    // 1. Start at top-left corner
    path.moveTo(0, topLeftR);

    // 2. Top-left corner arc: convex curve from (0, topLeftR) to (topLeftR, 0)
    path.arcToPoint(
      Offset(topLeftR, 0),
      radius: Radius.circular(topLeftR),
      clockwise: true,
    );

    // 3. Flat top edge from top-left corner to start of notch (x1)
    if (x1 > topLeftR) {
      path.lineTo(x1, 0);
    }

    // 4. Smooth cubic notch curve: dipping to (cx, nd) then rising to (x2, 0)
    path.cubicTo(
      x1 + nw * 0.22, 0,
      cx - nw * 0.24, nd,
      cx, nd,
    );
    path.cubicTo(
      cx + nw * 0.24, nd,
      x2 - nw * 0.22, 0,
      x2, 0,
    );

    // 5. Flat top edge from end of notch (x2) to top-right corner
    if (w - topRightR > x2) {
      path.lineTo(w - topRightR, 0);
    }

    // 6. Top-right corner arc: convex curve from (w - topRightR, 0) to (w, topRightR)
    path.arcToPoint(
      Offset(w, topRightR),
      radius: Radius.circular(topRightR),
      clockwise: true,
    );

    // 7. Right edge straight down
    path.lineTo(w, h - r);

    // 8. Bottom-right corner arc: convex curve from (w, h - r) to (w - r, h)
    path.arcToPoint(
      Offset(w - r, h),
      radius: Radius.circular(r),
      clockwise: true,
    );

    // 9. Bottom edge straight left
    path.lineTo(r, h);

    // 10. Bottom-left corner arc: convex curve from (r, h) to (0, h - r)
    path.arcToPoint(
      Offset(0, h - r),
      radius: Radius.circular(r),
      clockwise: true,
    );

    // 11. Left edge straight up to close
    path.lineTo(0, topLeftR);

    path.close();

    // Soft pill shadow
    canvas.drawShadow(
      path,
      isDark ? Colors.black.withValues(alpha: 0.55) : Colors.black.withValues(alpha: 0.08),
      isDark ? 16.0 : 10.0,
      true,
    );

    // Background fill
    final paintFill = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, paintFill);

    // Crisp boundary stroke
    final paintStroke = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    canvas.drawPath(path, paintStroke);
  }

  @override
  bool shouldRepaint(covariant _FluidNotchPainter oldDelegate) {
    return oldDelegate.notchCenterX != notchCenterX ||
        oldDelegate.notchWidth != notchWidth ||
        oldDelegate.notchDepth != notchDepth ||
        oldDelegate.barRadius != barRadius ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.borderColor != borderColor;
  }
}

/// Allows hit-testing on children that overflow their parent bounds (such as the elevated floating bubble).
class _OverflowHitTest extends SingleChildRenderObjectWidget {
  const _OverflowHitTest({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderOverflowHitTest();
}

class _RenderOverflowHitTest extends RenderProxyBox {
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (hitTestChildren(result, position: position)) {
      result.add(BoxHitTestEntry(this, position));
      return true;
    }
    return super.hitTest(result, position: position);
  }
}

