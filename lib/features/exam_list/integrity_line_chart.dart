import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../shared/theme/app_theme.dart';

class IntegrityChartPoint {
  final String label;
  final String title;
  final String subject;
  final String statusText;
  final String durationSummary;
  final double value; // 0..100
  final Color color;
  final Map<String, dynamic> rawItem;

  const IntegrityChartPoint({
    required this.label,
    required this.title,
    required this.subject,
    required this.statusText,
    this.durationSummary = '',
    required this.value,
    required this.color,
    required this.rawItem,
  });
}

/// Interactive trading/analytics-style area line chart showing exam integrity over time.
class IntegrityLineChart extends StatelessWidget {
  final List<IntegrityChartPoint> points;
  final int selectedIndex;
  final bool isDark;
  final ValueChanged<int> onSelectIndex;

  const IntegrityLineChart({
    super.key,
    required this.points,
    required this.selectedIndex,
    required this.isDark,
    required this.onSelectIndex,
  });

  void _handlePointer(Offset localPosition, double totalWidth) {
    if (points.length <= 1) {
      if (points.isNotEmpty) onSelectIndex(0);
      return;
    }
    const leftPad = 12.0;
    const rightAxisWidth = 44.0;
    final plotWidth = math.max(1.0, totalWidth - leftPad - rightAxisWidth);
    final relX = (localPosition.dx - leftPad).clamp(0.0, plotWidth);
    final idx = ((relX / plotWidth) * (points.length - 1)).round().clamp(
      0,
      points.length - 1,
    );
    if (idx != selectedIndex) {
      onSelectIndex(idx);
    }
  }

  @override
  Widget build(BuildContext context) {
    final safeIdx = points.isEmpty
        ? 0
        : selectedIndex.clamp(0, points.length - 1);
    final bgColor = isDark ? const Color(0xFF0B1324) : const Color(0xFFF8FAFC);
    final borderColor = isDark
        ? const Color(0xFF1E293B)
        : const Color(0xFFE2E8F0);

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) =>
                  _handlePointer(d.localPosition, constraints.maxWidth),
              onHorizontalDragStart: (d) =>
                  _handlePointer(d.localPosition, constraints.maxWidth),
              onHorizontalDragUpdate: (d) =>
                  _handlePointer(d.localPosition, constraints.maxWidth),
              child: SizedBox(
                width: double.infinity,
                height: 188,
                child: CustomPaint(
                  painter: _IntegrityLineChartPainter(
                    points: points,
                    selectedIndex: safeIdx,
                    isDark: isDark,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _IntegrityLineChartPainter extends CustomPainter {
  final List<IntegrityChartPoint> points;
  final int selectedIndex;
  final bool isDark;

  _IntegrityLineChartPainter({
    required this.points,
    required this.selectedIndex,
    required this.isDark,
  });

  static const double _leftPad = 12.0;
  static const double _rightAxisWidth = 44.0;
  static const double _topPad = 30.0;
  static const double _bottomPad = 24.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    const plotLeft = _leftPad;
    final plotRight = math.max(plotLeft + 20.0, size.width - _rightAxisWidth);
    const plotTop = _topPad;
    final plotBottom = math.max(plotTop + 20.0, size.height - _bottomPad);
    final plotWidth = plotRight - plotLeft;
    final plotHeight = plotBottom - plotTop;

    final gridColor = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : const Color(0xFF0F172A).withValues(alpha: 0.06);
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    final axisTextColor = isDark
        ? const Color(0xFF64748B)
        : const Color(0xFF94A3B8);

    // 1. Horizontal grid lines + right Y-axis labels (0%, 25%, 50%, 75%, 100%)
    const yTicks = [100, 75, 50, 25, 0];
    for (final tick in yTicks) {
      final y = plotTop + (1.0 - (tick / 100.0)) * plotHeight;
      canvas.drawLine(Offset(plotLeft, y), Offset(plotRight, y), gridPaint);

      final tp = TextPainter(
        text: TextSpan(
          text: '$tick%',
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w600,
            color: axisTextColor,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(plotRight + 6, y - tp.height / 2));
    }

    // 2. Compute node coordinates
    final coords = <Offset>[];
    for (int i = 0; i < points.length; i++) {
      final x = points.length == 1
          ? plotLeft + plotWidth * 0.5
          : plotLeft + (i / (points.length - 1)) * plotWidth;
      final normalized = (points[i].value.clamp(0.0, 100.0)) / 100.0;
      final y = plotTop + (1.0 - normalized) * plotHeight;
      coords.add(Offset(x, y));
    }

    // Vertical grid lines & bottom X-axis exam labels
    final labelStep = points.length > 6 ? 2 : 1;
    for (int i = 0; i < coords.length; i++) {
      final x = coords[i].dx;
      canvas.drawLine(
        Offset(x, plotTop),
        Offset(x, plotBottom),
        gridPaint,
      );
      if (i % labelStep == 0 || i == coords.length - 1 || i == selectedIndex) {
        final isSel = i == selectedIndex;
        final labelPainter = TextPainter(
          text: TextSpan(
            text: points[i].label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: isSel ? FontWeight.w800 : FontWeight.w500,
              color: isSel
                  ? (isDark ? Colors.white : const Color(0xFF0F172A))
                  : axisTextColor,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final labelX = (x - labelPainter.width / 2).clamp(
          4.0,
          plotRight - labelPainter.width,
        );
        labelPainter.paint(canvas, Offset(labelX, plotBottom + 6));
      }
    }

    const lineColor = AppTheme.primaryBlue;

    // 3. Build crisp line & translucent area gradient underneath
    final linePath = Path();
    final areaPath = Path();

    if (coords.length == 1) {
      final p = coords.first;
      linePath.moveTo(plotLeft, p.dy);
      linePath.lineTo(plotRight, p.dy);
      areaPath.moveTo(plotLeft, p.dy);
      areaPath.lineTo(plotRight, p.dy);
      areaPath.lineTo(plotRight, plotBottom);
      areaPath.lineTo(plotLeft, plotBottom);
      areaPath.close();
    } else {
      linePath.moveTo(coords.first.dx, coords.first.dy);
      areaPath.moveTo(coords.first.dx, coords.first.dy);
      for (int i = 1; i < coords.length; i++) {
        linePath.lineTo(coords[i].dx, coords[i].dy);
        areaPath.lineTo(coords[i].dx, coords[i].dy);
      }
      areaPath.lineTo(coords.last.dx, plotBottom);
      areaPath.lineTo(coords.first.dx, plotBottom);
      areaPath.close();
    }

    final areaGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        lineColor.withValues(alpha: isDark ? 0.34 : 0.24),
        lineColor.withValues(alpha: 0.02),
      ],
    ).createShader(Rect.fromLTWH(plotLeft, plotTop, plotWidth, plotHeight));

    canvas.drawPath(areaPath, Paint()..shader = areaGradient);
    canvas.drawPath(
      linePath,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    // 4. Node points (subtle markers so each exam position stays clear)
    for (int i = 0; i < coords.length; i++) {
      if (i == selectedIndex) continue;
      canvas.drawCircle(
        coords[i],
        2.8,
        Paint()..color = points[i].color.withValues(alpha: 0.85),
      );
    }

    // 5. Crosshair dashed guides + active dot + right-axis pill + callout chip
    final selCoord = coords[selectedIndex];
    final selPoint = points[selectedIndex];
    final dashPaint = Paint()
      ..color = isDark
          ? Colors.white.withValues(alpha: 0.55)
          : const Color(0xFF334155).withValues(alpha: 0.55)
      ..strokeWidth = 1.0;

    _drawDashedLine(
      canvas,
      Offset(selCoord.dx, plotTop),
      Offset(selCoord.dx, plotBottom),
      dashPaint,
    );
    _drawDashedLine(
      canvas,
      Offset(plotLeft, selCoord.dy),
      Offset(plotRight, selCoord.dy),
      dashPaint,
    );

    // Outer halo + inner white dot (trading style)
    canvas.drawCircle(
      selCoord,
      7.0,
      Paint()..color = selPoint.color.withValues(alpha: 0.28),
    );
    canvas.drawCircle(
      selCoord,
      4.5,
      Paint()..color = isDark ? Colors.white : selPoint.color,
    );
    canvas.drawCircle(
      selCoord,
      2.2,
      Paint()..color = isDark ? selPoint.color : Colors.white,
    );

    // Right Y-axis active percentage pill
    final pillText = TextPainter(
      text: TextSpan(
        text: '${selPoint.value.round()}%',
        style: const TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final pillRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        plotRight + 2,
        (selCoord.dy - 9).clamp(plotTop - 6, plotBottom - 12),
        _rightAxisWidth - 5,
        18,
      ),
      const Radius.circular(5),
    );
    canvas.drawRRect(pillRect, Paint()..color = lineColor);
    pillText.paint(
      canvas,
      Offset(
        pillRect.left + (pillRect.width - pillText.width) / 2,
        pillRect.top + (pillRect.height - pillText.height) / 2,
      ),
    );

    // Floating two-line tooltip card (Opsi C: exam title + duration | status, no icons or %)
    final tooltipHeader = selPoint.title.trim().isNotEmpty
        ? selPoint.title.trim()
        : selPoint.label;
    final headerTp = TextPainter(
      text: TextSpan(
        text: tooltipHeader,
        style: TextStyle(
          fontSize: 10.4,
          fontWeight: FontWeight.w800,
          color: isDark ? Colors.white : const Color(0xFF0F172A),
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: math.max(120.0, plotWidth - 20));

    final tooltipSubParts = <String>[
      if (selPoint.durationSummary.isNotEmpty) selPoint.durationSummary,
      selPoint.statusText,
    ];
    final tooltipSub = tooltipSubParts.join(' | ');
    final statusTp = TextPainter(
      text: TextSpan(
        text: tooltipSub,
        style: TextStyle(
          fontSize: 9.3,
          fontWeight: FontWeight.w600,
          color: selPoint.color,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: math.max(120.0, plotWidth - 20));

    const hPad = 9.0;
    const vPad = 6.0;
    const lineGap = 2.0;
    final contentW = math.max(headerTp.width, statusTp.width);
    final double boxW = (contentW + hPad * 2)
        .clamp(64.0, math.max(64.0, plotWidth - 4))
        .toDouble();
    final boxH = vPad * 2 + headerTp.height + lineGap + statusTp.height;

    final double boxX = (selCoord.dx - boxW / 2)
        .clamp(plotLeft + 2, math.max(plotLeft + 2, plotRight - boxW - 2))
        .toDouble();
    final double aboveY = selCoord.dy - boxH - 11;
    final double belowY = selCoord.dy + 11;
    final double boxY = aboveY >= 6.0
        ? aboveY
        : belowY.clamp(6.0, math.max(6.0, plotBottom - boxH - 4)).toDouble();

    final calloutRRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(boxX, boxY, boxW, boxH),
      const Radius.circular(8),
    );
    canvas.drawRRect(
      calloutRRect.shift(const Offset(0, 2)),
      Paint()..color = Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
    );
    canvas.drawRRect(
      calloutRRect,
      Paint()
        ..color = isDark ? const Color(0xFF162033) : Colors.white,
    );
    canvas.drawRRect(
      calloutRRect,
      Paint()
        ..color = selPoint.color.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1,
    );
    headerTp.paint(canvas, Offset(boxX + hPad, boxY + vPad));
    statusTp.paint(
      canvas,
      Offset(boxX + hPad, boxY + vPad + headerTp.height + lineGap),
    );
  }

  void _drawDashedLine(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint, {
    double dashLen = 4.0,
    double gapLen = 3.5,
  }) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist <= 0) return;
    final ux = dx / dist;
    final uy = dy / dist;
    double covered = 0.0;
    while (covered < dist) {
      final segEnd = math.min(covered + dashLen, dist);
      canvas.drawLine(
        Offset(start.dx + ux * covered, start.dy + uy * covered),
        Offset(start.dx + ux * segEnd, start.dy + uy * segEnd),
        paint,
      );
      covered += dashLen + gapLen;
    }
  }

  @override
  bool shouldRepaint(covariant _IntegrityLineChartPainter oldDelegate) {
    return oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.isDark != isDark ||
        oldDelegate.points != points;
  }
}
