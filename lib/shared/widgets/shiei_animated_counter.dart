import 'package:flutter/material.dart';

/// A true mechanical slot-reel rolling odometer counter (Apple / Robinhood style).
///
/// Each digit sits in its own clipped vertical slot.
/// When the value changes, only the specific changing digits roll vertically
/// with spring physics, while unchanged digits remain still.
class ShieiAnimatedCounter extends StatefulWidget {
  final int count;
  final TextStyle? style;
  final String prefix;
  final String suffix;
  final Duration duration;
  final Curve curve;
  final MainAxisSize mainAxisSize;
  final int padDigits;

  const ShieiAnimatedCounter({
    super.key,
    required this.count,
    this.style,
    this.prefix = '',
    this.suffix = '',
    this.duration = const Duration(milliseconds: 450),
    this.curve = Curves.easeInOutCubic,
    this.mainAxisSize = MainAxisSize.min,
    this.padDigits = 0,
  });

  @override
  State<ShieiAnimatedCounter> createState() => _ShieiAnimatedCounterState();
}

class _ShieiAnimatedCounterState extends State<ShieiAnimatedCounter> {
  int _prevCount = 0;

  @override
  void initState() {
    super.initState();
    _prevCount = widget.count;
  }

  @override
  void didUpdateWidget(covariant ShieiAnimatedCounter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.count != widget.count) {
      _prevCount = oldWidget.count;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isIncreasing = widget.count >= _prevCount;
    final String rawStr = widget.padDigits > 0
        ? widget.count.abs().toString().padLeft(widget.padDigits, '0')
        : widget.count.abs().toString();
    final digits = rawStr.split('');

    return AnimatedSize(
      duration: widget.duration,
      curve: widget.curve,
      child: Row(
        mainAxisSize: widget.mainAxisSize,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (widget.prefix.isNotEmpty)
            Text(widget.prefix, style: widget.style),
          if (widget.count < 0)
            Text('-', style: widget.style),
          ...digits.asMap().entries.map((entry) {
            final int index = entry.key;
            final String digitChar = entry.value;
            // Place index from the right (0 = units, 1 = tens, 2 = hundreds)
            final int placeFromRight = digits.length - 1 - index;

            return _OdometerSlotDigit(
              key: ValueKey('odometer_place_$placeFromRight'),
              digitChar: digitChar,
              isIncreasing: isIncreasing,
              style: widget.style,
              duration: widget.duration,
              curve: widget.curve,
            );
          }),
          if (widget.suffix.isNotEmpty)
            Text(widget.suffix, style: widget.style),
        ],
      ),
    );
  }
}

class _OdometerSlotDigit extends StatelessWidget {
  final String digitChar;
  final bool isIncreasing;
  final TextStyle? style;
  final Duration duration;
  final Curve curve;

  const _OdometerSlotDigit({
    super.key,
    required this.digitChar,
    required this.isIncreasing,
    this.style,
    required this.duration,
    required this.curve,
  });

  @override
  Widget build(BuildContext context) {
    final fontSize = style?.fontSize ?? 14.0;
    final lineHeight = fontSize * 1.35;

    return SizedBox(
      height: lineHeight,
      child: ClipRect(
        child: AnimatedSwitcher(
          duration: duration,
          layoutBuilder: (currentChild, previousChildren) {
            return Stack(
              alignment: Alignment.center,
              children: <Widget>[
                ...previousChildren,
                if (currentChild != null) currentChild,
              ],
            );
          },
          transitionBuilder: (child, animation) {
            final isCurrent = (child.key as ValueKey<String>?)?.value == digitChar;
            final double offsetSign = isIncreasing ? 1.0 : -1.0;

            final Animation<Offset> slideAnim;
            if (isCurrent) {
              // Incoming child: animation runs forward 0.0 -> 1.0
              slideAnim = Tween<Offset>(
                begin: Offset(0.0, offsetSign),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: animation, curve: curve));
            } else {
              // Outgoing child: animation runs reverse 1.0 -> 0.0
              // At 1.0 (start of exit), evaluated value is Offset.zero
              // At 0.0 (end of exit), evaluated value is Offset(0.0, -offsetSign)
              slideAnim = Tween<Offset>(
                begin: Offset(0.0, -offsetSign),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: animation, curve: curve));
            }

            return SlideTransition(
              position: slideAnim,
              child: FadeTransition(
                opacity: CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeInOut,
                ),
                child: child,
              ),
            );
          },
          child: Text(
            digitChar,
            key: ValueKey<String>(digitChar),
            style: style,
          ),
        ),
      ),
    );
  }
}
