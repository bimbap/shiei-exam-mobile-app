import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

/// High-performance, spring-physics bottom sheet.
///
/// Architecture:
/// - [ValueNotifier<double>] drives the fraction position.
/// - [AnimationController.unbounded] runs spring simulations; its value
///   is pushed into the notifier each frame via addListener â€” no setState.
/// - [ValueListenableBuilder] wraps ONLY the Transform.translate + SizedBox,
///   so the heavy content subtree (form, body, footer) is NEVER rebuilt during
///   animation â€” only the position wrapper is.
/// - Content rebuilds only when MediaQuery (keyboard, padding) or theme changes.
/// - Keyboard auto-snap is detected in [didChangeDependencies], not every build.
class ShieiBottomSheet extends StatefulWidget {
  final double initialFraction;
  final double dismissThreshold;
  final double maxFraction;
  final List<double> snapFractions;
  final Widget Function(bool isFullscreen) headerBuilder;
  final Widget Function(bool isFullscreen)? footerBuilder;
  final Widget Function(ScrollController scrollController) bodyBuilder;
  final Color? barrierColor;

  const ShieiBottomSheet({
    super.key,
    required this.initialFraction,
    this.dismissThreshold = 0.35,
    this.maxFraction = 0.925,
    required this.snapFractions,
    required this.headerBuilder,
    this.footerBuilder,
    required this.bodyBuilder,
    this.barrierColor,
  });

  static Future<T?> show<T>({
    required BuildContext context,
    required double initialFraction,
    double dismissThreshold = 0.35,
    double maxFraction = 0.925,
    required List<double> snapFractions,
    required Widget Function(bool isFullscreen) headerBuilder,
    Widget Function(bool isFullscreen)? footerBuilder,
    required Widget Function(ScrollController scrollController) bodyBuilder,
    Color? barrierColor,
  }) {
    FocusScope.of(context).unfocus();
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: barrierColor ?? Colors.black.withValues(alpha: 0.55),
      builder: (_) => ShieiBottomSheet(
        initialFraction: initialFraction,
        dismissThreshold: dismissThreshold,
        maxFraction: maxFraction,
        snapFractions: snapFractions,
        headerBuilder: headerBuilder,
        footerBuilder: footerBuilder,
        bodyBuilder: bodyBuilder,
      ),
    );
  }

  @override
  State<ShieiBottomSheet> createState() => _ShieiBottomSheetState();
}

class _ShieiBottomSheetState extends State<ShieiBottomSheet>
    with SingleTickerProviderStateMixin {
  // Drives fraction position â€” ValueNotifier avoids setState on every frame.
  late final ValueNotifier<double> _fraction;

  // Unbounded so spring simulations can overshoot slightly; clamped visually.
  late final AnimationController _ctrl;

  final ScrollController _scroll = ScrollController();

  double _dragStartFraction = 0;
  bool _isDragging = false;    // true while finger is on handle
  bool _isDismissing = false;
  bool _hasPopped = false;     // guard: Navigator.pop() fires exactly once
  double? _preKeyboardFraction;
  double _prevBottomInset = 0;

  double get _minSnap => widget.snapFractions.isNotEmpty
      ? widget.snapFractions.reduce((a, b) => a < b ? a : b)
      : widget.initialFraction;

  // Critically-overdamped snap spring: fast settle, zero overshoot/glitch.
  // Overdamped condition: damping² > 4 × stiffness × mass → 40² = 1600 > 4×300 = 1200 ✓
  static const _snapSpring = SpringDescription(mass: 1.0, stiffness: 300.0, damping: 40.0);

  // Dismiss spring: very stiff + overdamped for a snappy, no-bounce exit.
  // 50² = 2500 > 4×500 = 2000 ✓
  static const _dismissSpring = SpringDescription(mass: 1.0, stiffness: 500.0, damping: 50.0);

  @override
  void initState() {
    super.initState();
    _fraction = ValueNotifier(widget.initialFraction);
    _dragStartFraction = widget.initialFraction;
    _ctrl = AnimationController.unbounded(vsync: this)
      ..value = widget.initialFraction;
    _ctrl.addListener(_onTick);
  }

  void _onTick() {
    final v = _ctrl.value.clamp(0.0, widget.maxFraction);
    _fraction.value = v;
    // Defer pop to post-frame — calling Navigator.pop() inside an AnimationController
    // listener fires during the frame tick while Navigator holds its debug lock,
    // causing 'Bad state: No element' / '_debugLocked' assertion crashes.
    // ModalRoute.isCurrent guard prevents popping the underlying screen if this
    // route was already popped (e.g. system back button or external pop).
    if (_isDismissing && _ctrl.value <= 0.005 && mounted && !_hasPopped) {
      _hasPopped = true;
      _ctrl.stop();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) {
          Navigator.of(context).pop();
        }
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    _handleKeyboard(inset);
    _prevBottomInset = inset;
  }

  void _handleKeyboard(double inset) {
    // Never fight an active drag or a dismiss animation.
    if (_isDismissing || _isDragging) return;
    if (inset > 50 && _prevBottomInset <= 50) {
      // Keyboard opened â†’ expand to max for more room
      if (_fraction.value < widget.maxFraction) {
        _preKeyboardFraction = _fraction.value;
        _springTo(widget.maxFraction, releaseVelocity: 0);
      }
    } else if (inset <= 50 && _prevBottomInset > 50) {
      // Keyboard closed â†’ restore previous snap position
      final restore = _preKeyboardFraction;
      _preKeyboardFraction = null;
      if (restore != null) {
        _springTo(restore, releaseVelocity: 0);
      }
    }
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onTick);
    _ctrl.dispose();
    _fraction.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // â”€â”€ Gesture handlers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void _onDragStart(DragStartDetails _) {
    if (_isDismissing) return;
    _isDragging = true;
    _ctrl.stop();
    _dragStartFraction = _fraction.value;
    FocusScope.of(context).unfocus();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (_isDismissing) return;
    final h = MediaQuery.sizeOf(context).height;
    if (h <= 0) return;
    final next = (_fraction.value - d.primaryDelta! / h).clamp(0.0, widget.maxFraction);
    // Write directly to notifier â€” no setState, no rebuild of content
    _fraction.value = next;
    _ctrl.value = next;
  }

  void _onDragEnd(DragEndDetails d) {
    _isDragging = false;
    if (_isDismissing) return;
    final vel = d.primaryVelocity ?? 0; // px/s, positive = downward
    final h = MediaQuery.sizeOf(context).height;
    // Convert pixel velocity â†’ fraction/s (negative = fraction increasing = upward)
    final fracVel = h > 0 ? -vel / h : 0.0;
    final cur = _fraction.value;
    final minSnap = _minSnap;

    if (vel > 400) {
      cur <= minSnap + 0.12
          ? _dismiss(releaseVelocity: fracVel)
          : _springTo(_findLowerSnap(cur), releaseVelocity: fracVel);
      return;
    }

    if (vel < -400) {
      _springTo(widget.maxFraction, releaseVelocity: fracVel);
      return;
    }

    if (cur < widget.dismissThreshold || cur < minSnap - 0.07) {
      _dismiss(releaseVelocity: fracVel);
      return;
    }

    _springTo(_findSnap(current: cur, start: _dragStartFraction), releaseVelocity: fracVel);
  }

  // â”€â”€ Snap logic â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  double _findLowerSnap(double current) {
    final snaps = List<double>.from(widget.snapFractions)..sort();
    for (int i = snaps.length - 1; i >= 0; i--) {
      if (snaps[i] < current - 0.03) return snaps[i];
    }
    return snaps.isNotEmpty ? snaps.first : current;
  }

  double _findSnap({required double current, required double start}) {
    final snaps = List<double>.from(widget.snapFractions)..sort();
    if (snaps.isEmpty) return current;
    if (snaps.length == 1) return snaps.first;
    if (current <= snaps.first) return snaps.first;
    if (current >= snaps.last) return snaps.last;

    for (int i = 0; i < snaps.length - 1; i++) {
      final lo = snaps[i], hi = snaps[i + 1];
      if (current >= lo && current <= hi) {
        final range = hi - lo;
        final draggingUp = start < current;
        // Dragging up needs to cross 60% of range to advance; dragging down only 40% to fall back.
        final threshold = lo + range * (draggingUp ? 0.60 : 0.40);
        return current >= threshold ? hi : lo;
      }
    }
    return snaps.last;
  }

  // â”€â”€ Animation â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  void _springTo(double target, {required double releaseVelocity}) {
    if (!mounted) return;
    final sim = SpringSimulation(_snapSpring, _fraction.value, target, releaseVelocity);
    _ctrl.animateWith(sim);
    HapticFeedback.selectionClick();
  }

  void _dismiss({double releaseVelocity = 0}) {
    if (_isDismissing || !mounted) return;
    _isDismissing = true;
    // Ensure velocity is always downward (negative fraction direction)
    final vel = releaseVelocity > -0.5 ? -2.0 : releaseVelocity.clamp(-12.0, -0.5);
    final sim = SpringSimulation(_dismissSpring, _fraction.value, 0.0, vel);
    _ctrl.animateWith(sim);
    // Navigator.pop is handled in _onTick when value <= 0.005
  }

  // â”€â”€ Build â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  @override
  Widget build(BuildContext context) {
    // build() is called only on MediaQuery/theme changes â€” never on animation ticks.
    final isDark = AppTheme.isDark(context);
    final screenHeight = MediaQuery.sizeOf(context).height;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final minSnap = _minSnap;

    return Stack(
      children: [
        // Barrier
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _isDismissing
                ? null
                : () {
                    FocusManager.instance.primaryFocus?.unfocus();
                    _dismiss(releaseVelocity: -2.0);
                  },
          ),
        ),

        // Sheet â€” ValueListenableBuilder rebuilds ONLY the positioning wrapper each frame.
        // The expensive `child:` content is stable and never rebuilt during animation.
        Align(
          alignment: Alignment.bottomCenter,
          child: ValueListenableBuilder<double>(
            valueListenable: _fraction,
            builder: (_, fraction, child) {
              final rendered = fraction.clamp(minSnap, widget.maxFraction);
              final sheetH = screenHeight * rendered;
              final slideY = fraction < minSnap ? screenHeight * (minSnap - fraction) : 0.0;

              return Transform.translate(
                offset: Offset(0, slideY),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: SizedBox(height: sheetH, width: double.infinity, child: child),
                  ),
                ),
              );
            },
            // `child:` is built when MediaQuery/theme changes, not on animation frames.
            child: _SheetContent(
              isDark: isDark,
              bottomInset: bottomInset,
              bottomPadding: bottomPadding,
              fraction: _fraction,
              maxFraction: widget.maxFraction,
              onDragStart: _onDragStart,
              onDragUpdate: _onDragUpdate,
              onDragEnd: _onDragEnd,
              scroll: _scroll,
              headerBuilder: widget.headerBuilder,
              footerBuilder: widget.footerBuilder,
              bodyBuilder: widget.bodyBuilder,
            ),
          ),
        ),
      ],
    );
  }
}

/// Isolated content widget â€” only rebuilds on theme or keyboard inset changes,
/// never during the fraction animation.
class _SheetContent extends StatelessWidget {
  final bool isDark;
  final double bottomInset;
  final double bottomPadding;
  final ValueNotifier<double> fraction;
  final double maxFraction;
  final GestureDragStartCallback onDragStart;
  final GestureDragUpdateCallback onDragUpdate;
  final GestureDragEndCallback onDragEnd;
  final ScrollController scroll;
  final Widget Function(bool) headerBuilder;
  final Widget Function(bool)? footerBuilder;
  final Widget Function(ScrollController) bodyBuilder;

  const _SheetContent({
    required this.isDark,
    required this.bottomInset,
    required this.bottomPadding,
    required this.fraction,
    required this.maxFraction,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.scroll,
    required this.headerBuilder,
    required this.footerBuilder,
    required this.bodyBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final dividerColor = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);
    final pillColor = isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(), // absorb & unfocus — dismiss keyboard when tapping outside fields
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? AppTheme.surfaceDark : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(
              top: BorderSide(color: borderColor),
              left: BorderSide(color: borderColor),
              right: BorderSide(color: borderColor),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.20),
                blurRadius: 28,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            children: [
              // ── Drag handle zone ──────────────────────────────────────
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
                onVerticalDragStart: (details) {
                  FocusManager.instance.primaryFocus?.unfocus();
                  onDragStart(details);
                },
                onVerticalDragUpdate: onDragUpdate,
                onVerticalDragEnd: onDragEnd,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 10),
                      child: Center(
                        child: Container(
                          width: 44,
                          height: 4.5,
                          decoration: BoxDecoration(
                            color: pillColor,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                    // Header reacts to live fraction via nested ValueListenableBuilder
                    ValueListenableBuilder<double>(
                      valueListenable: fraction,
                      builder: (_, frac, __) => headerBuilder(frac >= maxFraction - 0.02),
                    ),
                    Container(height: 1, color: dividerColor),
                  ],
                ),
              ),

              // â”€â”€ Scrollable body â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              Expanded(
                child: ClipRect(
                  child: RepaintBoundary(
                    child: bodyBuilder(scroll),
                  ),
                ),
              ),

              // â”€â”€ Sticky footer (keyboard-aware) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              if (footerBuilder != null) ...[
                Container(height: 1, color: dividerColor),
                RepaintBoundary(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      20, 12, 20,
                      12 + (bottomInset > 0 ? bottomInset : bottomPadding),
                    ),
                    child: ValueListenableBuilder<double>(
                      valueListenable: fraction,
                      builder: (_, frac, __) => footerBuilder!(frac >= maxFraction - 0.02),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
