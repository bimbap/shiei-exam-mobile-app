import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// ShieiShimmer provides an animated shimmer pulse across child skeleton components.
///
/// Uses a lightweight opacity pulse animation instead of ShaderMask.
/// ShaderMask creates a separate RenderShaderMask render layer that requires
/// valid layout bounds for its shaderCallback. When multiple instances animate
/// at 60fps inside IndexedStack (all tabs mounted simultaneously), the render
/// pipeline's layout and semantics phases race — causing persistent
/// `!semantics.parentDataDirty` and `RenderBox was not laid out` assertions.
///
/// The opacity pulse approach:
/// - Zero render layers (no ShaderMask, no ColorFiltered)
/// - No shaderCallback (no layout-bounds dependency)
/// - Safe inside IndexedStack, DraggableScrollableSheet, or any constrained parent
/// - Visually clean: subtle brightness oscillation on skeleton boxes
class ShieiShimmer extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final Color? baseColor;
  final Color? highlightColor;

  const ShieiShimmer({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 1400),
    this.baseColor,
    this.highlightColor,
  });

  @override
  State<ShieiShimmer> createState() => _ShieiShimmerState();
}

class _ShieiShimmerState extends State<ShieiShimmer> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat(reverse: true);
    _opacity = Tween<double>(begin: 1.0, end: 0.4).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: widget.child,
    );
  }
}

/// Atomic rounded rectangle skeleton box.
class ShieiSkeletonBox extends StatelessWidget {
  final double? width;
  final double? height;
  final double borderRadius;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;
  final Widget? child;

  const ShieiSkeletonBox({
    super.key,
    this.width,
    this.height,
    this.borderRadius = 8,
    this.margin,
    this.padding,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    return Container(
      width: width,
      height: height,
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: child,
    );
  }
}

/// Atomic circular skeleton widget for avatars and icons.
class ShieiSkeletonCircle extends StatelessWidget {
  final double size;
  final EdgeInsetsGeometry? margin;

  const ShieiSkeletonCircle({
    super.key,
    required this.size,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    return Container(
      width: size,
      height: size,
      margin: margin,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
        shape: BoxShape.circle,
      ),
    );
  }
}

/// Composite: Exam Card Skeleton (Matches student & teacher exam schedule cards).
class ExamCardSkeleton extends StatelessWidget {
  final int count;
  final EdgeInsetsGeometry padding;
  final ScrollPhysics? physics;
  final bool scrollable;

  const ExamCardSkeleton({
    super.key,
    this.count = 3,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    this.physics,
    this.scrollable = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final cardBg = isDark ? const Color(0xFF131C2E) : Colors.white;
    final cardBorder = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final bentoBorder = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

    final cardList = List.generate(count, (index) {
          return Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cardBorder, width: 1.2),
            ),
            child: ShieiShimmer(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header Row: Circle Icon + Title & Schedule
                  const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ShieiSkeletonCircle(size: 40),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ShieiSkeletonBox(width: 180, height: 16, borderRadius: 4),
                            SizedBox(height: 6),
                            ShieiSkeletonBox(width: 120, height: 12, borderRadius: 4),
                          ],
                        ),
                      ),
                      SizedBox(width: 8),
                      ShieiSkeletonBox(width: 68, height: 24, borderRadius: 6),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Bento Metadata Bar (Duration & Class)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: bentoBorder),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        ShieiSkeletonBox(width: 90, height: 14, borderRadius: 4),
                        ShieiSkeletonBox(width: 80, height: 14, borderRadius: 4),
                        ShieiSkeletonBox(width: 70, height: 14, borderRadius: 4),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Action Button Strip
                  const ShieiSkeletonBox(
                    width: double.infinity,
                    height: 40,
                    borderRadius: 10,
                  ),
                ],
              ),
            ),
          );
        });

    if (physics != null || scrollable) {
      return ListView(
        padding: padding,
        physics: physics ?? const AlwaysScrollableScrollPhysics(),
        children: cardList,
      );
    }

    return Padding(
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: cardList,
      ),
    );
  }
}

/// Composite: Student Exam Card Skeleton (Matches student exam schedule cards pixel-perfect).
class StudentExamCardSkeleton extends StatelessWidget {
  final int count;
  final EdgeInsetsGeometry padding;
  final ScrollPhysics? physics;
  final bool scrollable;

  const StudentExamCardSkeleton({
    super.key,
    this.count = 3,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    this.physics,
    this.scrollable = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final cardBg = isDark ? const Color(0xFF131C2E) : Colors.white;
    final cardBorder = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final bentoBorder = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);

    final cardList = List.generate(count, (index) {
          return Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cardBorder, width: 1.2),
            ),
            child: ShieiShimmer(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Header Row: Subject Badge + Class Badge + Status Badge
                  const Row(
                    children: [
                      ShieiSkeletonBox(width: 82, height: 24, borderRadius: 8),
                      SizedBox(width: 6),
                      ShieiSkeletonBox(width: 74, height: 24, borderRadius: 8),
                      Spacer(),
                      ShieiSkeletonBox(width: 72, height: 24, borderRadius: 8),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // 2. Exam Title (Two lines for natural hierarchy)
                  const ShieiSkeletonBox(width: double.infinity, height: 16, borderRadius: 4),
                  const SizedBox(height: 6),
                  const ShieiSkeletonBox(width: 170, height: 16, borderRadius: 4),
                  const SizedBox(height: 8),

                  // 3. Teacher Row (Icon + Name)
                  const Row(
                    children: [
                      ShieiSkeletonCircle(size: 13),
                      SizedBox(width: 6),
                      ShieiSkeletonBox(width: 135, height: 11, borderRadius: 4),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // 4. Bento Details Box (Duration, Token Mode, Date, Time Window)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: bentoBorder),
                    ),
                    child: Column(
                      children: [
                        // Row 1: Duration & Token Mode
                        const Row(
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  ShieiSkeletonCircle(size: 14),
                                  SizedBox(width: 6),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      ShieiSkeletonBox(width: 52, height: 9, borderRadius: 3),
                                      SizedBox(height: 4),
                                      ShieiSkeletonBox(width: 64, height: 12, borderRadius: 4),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(width: 8),
                            ShieiSkeletonBox(width: 1, height: 22, borderRadius: 1),
                            SizedBox(width: 12),
                            Expanded(
                              child: Row(
                                children: [
                                  ShieiSkeletonCircle(size: 14),
                                  SizedBox(width: 6),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      ShieiSkeletonBox(width: 68, height: 9, borderRadius: 3),
                                      SizedBox(height: 4),
                                      ShieiSkeletonBox(width: 72, height: 12, borderRadius: 4),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Divider(
                          color: bentoBorder,
                          height: 1,
                        ),
                        const SizedBox(height: 8),
                        // Row 2: Date & Time
                        const Row(
                          children: [
                            ShieiSkeletonCircle(size: 14),
                            SizedBox(width: 6),
                            Expanded(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  ShieiSkeletonBox(width: 80, height: 11, borderRadius: 4),
                                  ShieiSkeletonBox(width: 95, height: 11, borderRadius: 4),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 5. Action CTA Button
                  const ShieiSkeletonBox(
                    width: double.infinity,
                    height: 44,
                    borderRadius: 12,
                  ),
                ],
              ),
            ),
          );
        });

    if (physics != null || scrollable) {
      return ListView(
        padding: padding,
        physics: physics ?? const AlwaysScrollableScrollPhysics(),
        children: cardList,
      );
    }

    return Padding(
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: cardList,
      ),
    );
  }
}

/// Composite: Student History Card Skeleton (Matches student completed & past exam cards pixel-perfect).
class StudentHistoryCardSkeleton extends StatelessWidget {
  final int count;
  final EdgeInsetsGeometry padding;
  final ScrollPhysics? physics;
  final bool scrollable;

  const StudentHistoryCardSkeleton({
    super.key,
    this.count = 3,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    this.physics,
    this.scrollable = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final cardBg = isDark ? const Color(0xFF131C2E) : Colors.white;
    final cardBorder = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final bentoBorder = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);

    final cardList = List.generate(count, (index) {
          return Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cardBorder, width: 1.2),
            ),
            child: ShieiShimmer(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Badges Row: Subject Badge + Status Badge
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ShieiSkeletonBox(width: 80, height: 22, borderRadius: 6),
                      ShieiSkeletonBox(width: 74, height: 22, borderRadius: 6),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Icon Circle + Title & Date Row
                  const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ShieiSkeletonCircle(size: 40),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ShieiSkeletonBox(width: double.infinity, height: 16, borderRadius: 4),
                            SizedBox(height: 6),
                            ShieiSkeletonBox(width: 140, height: 12, borderRadius: 4),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Bento Metadata Strip (Waktu Pengerjaan & Status)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: bentoBorder),
                    ),
                    child: const Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ShieiSkeletonBox(width: 85, height: 9, borderRadius: 3),
                              SizedBox(height: 5),
                              ShieiSkeletonBox(width: 70, height: 13, borderRadius: 4),
                            ],
                          ),
                        ),
                        ShieiSkeletonBox(width: 1, height: 26, borderRadius: 1),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ShieiSkeletonBox(width: 50, height: 9, borderRadius: 3),
                              SizedBox(height: 5),
                              ShieiSkeletonBox(width: 65, height: 13, borderRadius: 4),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        });

    if (physics != null || scrollable) {
      return ListView(
        padding: padding,
        physics: physics ?? const AlwaysScrollableScrollPhysics(),
        children: cardList,
      );
    }

    return Padding(
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: cardList,
      ),
    );
  }
}

/// Composite: Student Profile Skeleton (Matches Digital Exam Pass ID Card & profile controls).
class StudentProfileSkeleton extends StatelessWidget {
  /// Whether to render the Tour Banner skeleton (controlled via showTour flag).
  final bool showTour;

  const StudentProfileSkeleton({
    super.key,
    this.showTour = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final cardBg = isDark ? const Color(0xFF131C2E) : Colors.white;
    final cardBorder = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight > 50 ? constraints.maxHeight - 40 : 400,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. Digital Exam Pass ID Card Skeleton
                    Container(
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: cardBorder, width: 1.5),
                      ),
                      child: ShieiShimmer(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Header Ribbon
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                              decoration: BoxDecoration(
                                color: Colors.transparent,
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(21)),
                                border: Border(bottom: BorderSide(color: cardBorder)),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      ShieiSkeletonBox(width: 28, height: 28, borderRadius: 8),
                                      SizedBox(width: 8),
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          ShieiSkeletonBox(width: 140, height: 11, borderRadius: 4),
                                          SizedBox(height: 4),
                                          ShieiSkeletonBox(width: 100, height: 9, borderRadius: 3),
                                        ],
                                      ),
                                    ],
                                  ),
                                  ShieiSkeletonBox(width: 52, height: 22, borderRadius: 8),
                                ],
                              ),
                            ),

                            // Profile Main Info Row
                            const Padding(
                              padding: EdgeInsets.all(20),
                              child: Row(
                                children: [
                                  ShieiSkeletonCircle(size: 68),
                                  SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        ShieiSkeletonBox(width: 130, height: 16, borderRadius: 4),
                                        SizedBox(height: 8),
                                        ShieiSkeletonBox(width: 85, height: 20, borderRadius: 6),
                                        SizedBox(height: 10),
                                        ShieiSkeletonBox(width: 160, height: 11, borderRadius: 4),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // 2. Guide & Tour Banner Skeleton (Toggleable via showTour)
                    if (showTour) ...[
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: cardBorder),
                        ),
                        child: const ShieiShimmer(
                          child: Row(
                            children: [
                              ShieiSkeletonCircle(size: 46),
                              SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ShieiSkeletonBox(width: 160, height: 14, borderRadius: 4),
                                    SizedBox(height: 5),
                                    ShieiSkeletonBox(width: 200, height: 11, borderRadius: 4),
                                  ],
                                ),
                              ),
                              SizedBox(width: 8),
                              ShieiSkeletonBox(width: 68, height: 26, borderRadius: 8),
                            ],
                          ),
                        ),
                      ),
                    ],

                    // 2. Pengaturan & Preferensi Grouped Card Skeleton
                    const SizedBox(height: 18),
                    const Padding(
                      padding: EdgeInsets.only(left: 4, bottom: 8),
                      child: ShieiShimmer(
                        child: ShieiSkeletonBox(width: 140, height: 11, borderRadius: 3),
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: cardBorder),
                      ),
                      child: ShieiShimmer(
                        child: Column(
                          children: [
                            // Tile 1: Ubah Kata Sandi
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              child: Row(
                                children: [
                                  ShieiSkeletonBox(width: 36, height: 36, borderRadius: 10),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        ShieiSkeletonBox(width: 120, height: 13, borderRadius: 4),
                                        SizedBox(height: 4),
                                        ShieiSkeletonBox(width: 190, height: 11, borderRadius: 4),
                                      ],
                                    ),
                                  ),
                                  Icon(Icons.chevron_right_rounded, color: Colors.grey, size: 20),
                                ],
                              ),
                            ),
                            Divider(height: 1, indent: 62, color: cardBorder),

                            // Tile 2: Efek Suara & Audio
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              child: Row(
                                children: [
                                  ShieiSkeletonBox(width: 36, height: 36, borderRadius: 10),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        ShieiSkeletonBox(width: 135, height: 13, borderRadius: 4),
                                        SizedBox(height: 4),
                                        ShieiSkeletonBox(width: 180, height: 11, borderRadius: 4),
                                      ],
                                    ),
                                  ),
                                  ShieiSkeletonBox(width: 38, height: 22, borderRadius: 12),
                                ],
                              ),
                            ),
                            Divider(height: 1, indent: 62, color: cardBorder),

                            // Tile 3: Pengaturan & Info Aplikasi
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              child: Row(
                                children: [
                                  ShieiSkeletonBox(width: 36, height: 36, borderRadius: 10),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        ShieiSkeletonBox(width: 150, height: 13, borderRadius: 4),
                                        SizedBox(height: 4),
                                        ShieiSkeletonBox(width: 200, height: 11, borderRadius: 4),
                                      ],
                                    ),
                                  ),
                                  Icon(Icons.chevron_right_rounded, color: Colors.grey, size: 20),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                // 3. Action Buttons Skeleton (Single modern logout button)
                const Padding(
                  padding: EdgeInsets.only(top: 24, bottom: 8),
                  child: ShieiShimmer(
                    child: ShieiSkeletonBox(
                      width: double.infinity,
                      height: 46,
                      borderRadius: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Composite: Participant Row Skeleton (for Exam Detail & Monitoring student rosters).
class ParticipantRowSkeleton extends StatelessWidget {
  final int count;
  final EdgeInsetsGeometry padding;
  final ScrollPhysics? physics;
  final bool scrollable;

  const ParticipantRowSkeleton({
    super.key,
    this.count = 5,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    this.physics,
    this.scrollable = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final rowBg = isDark ? const Color(0xFF131C2E) : Colors.white;
    final rowBorder = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

    final rowList = List.generate(count, (index) {
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: rowBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: rowBorder),
              ),
              child: const Row(
                children: [
                  ShieiSkeletonCircle(size: 38),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ShieiSkeletonBox(width: 140, height: 14, borderRadius: 4),
                        SizedBox(height: 6),
                        ShieiSkeletonBox(width: 90, height: 11, borderRadius: 4),
                      ],
                    ),
                  ),
                  SizedBox(width: 8),
                  ShieiSkeletonBox(width: 64, height: 24, borderRadius: 6),
                  SizedBox(width: 8),
                  ShieiSkeletonBox(width: 28, height: 28, borderRadius: 8),
                ],
              ),
            );
          });

    if (physics != null || scrollable) {
      return ShieiShimmer(
        child: ListView(
          padding: padding,
          physics: physics ?? const AlwaysScrollableScrollPhysics(),
          children: rowList,
        ),
      );
    }

    return ShieiShimmer(
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: rowList,
        ),
      ),
    );
  }
}

/// Composite: Dashboard Skeleton (Teacher Portal initial loading).
class DashboardSkeleton extends StatelessWidget {
  final ScrollPhysics physics;
  final EdgeInsetsGeometry padding;

  const DashboardSkeleton({
    super.key,
    this.physics = const AlwaysScrollableScrollPhysics(),
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 100),
  });

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final cardBg = isDark ? const Color(0xFF131C2E) : Colors.white;
    final cardBorder = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

    return ShieiShimmer(
      child: SingleChildScrollView(
        physics: physics,
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Welcome & School Banner Skeleton
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: cardBorder),
              ),
              child: const Row(
                children: [
                  ShieiSkeletonCircle(size: 48),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ShieiSkeletonBox(width: 160, height: 16, borderRadius: 4),
                        SizedBox(height: 8),
                        ShieiSkeletonBox(width: 110, height: 12, borderRadius: 4),
                      ],
                    ),
                  ),
                  SizedBox(width: 8),
                  ShieiSkeletonBox(width: 50, height: 26, borderRadius: 8),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // 2. 4 Stat Cards in 2x2 Grid
            Row(
              children: [
                Expanded(child: _buildStatCard(cardBg, cardBorder)),
                const SizedBox(width: 12),
                Expanded(child: _buildStatCard(cardBg, cardBorder)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _buildStatCard(cardBg, cardBorder)),
                const SizedBox(width: 12),
                Expanded(child: _buildStatCard(cardBg, cardBorder)),
              ],
            ),
            const SizedBox(height: 22),

            // 3. Quick Action Chips Row
            const ShieiSkeletonBox(width: 130, height: 16, borderRadius: 4),
            const SizedBox(height: 12),
            const Row(
              children: [
                Expanded(child: ShieiSkeletonBox(height: 44, borderRadius: 12)),
                SizedBox(width: 10),
                Expanded(child: ShieiSkeletonBox(height: 44, borderRadius: 12)),
                SizedBox(width: 10),
                Expanded(child: ShieiSkeletonBox(height: 44, borderRadius: 12)),
              ],
            ),
            const SizedBox(height: 24),

            // 4. Active Live Exams Section Header
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ShieiSkeletonBox(width: 150, height: 16, borderRadius: 4),
                ShieiSkeletonBox(width: 60, height: 14, borderRadius: 4),
              ],
            ),
            const SizedBox(height: 14),

            // 5. 2 Live Exam Card Skeletons
            const ExamCardSkeleton(count: 2, padding: EdgeInsets.zero),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(Color bg, Color border) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ShieiSkeletonCircle(size: 28),
              ShieiSkeletonBox(width: 32, height: 14, borderRadius: 4),
            ],
          ),
          SizedBox(height: 12),
          ShieiSkeletonBox(width: 50, height: 20, borderRadius: 4),
          SizedBox(height: 6),
          ShieiSkeletonBox(width: 80, height: 11, borderRadius: 4),
        ],
      ),
    );
  }
}

/// Composite: School Data Tab Skeleton (Kelas / Siswa / Guru / Admin loading).
class SchoolDataSkeleton extends StatelessWidget {
  const SchoolDataSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final cardBg = isDark ? const Color(0xFF131C2E) : Colors.white;
    final cardBorder = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

    return ShieiShimmer(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          children: [
            // Search Bar Placeholder
            Container(
              width: double.infinity,
              height: 46,
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cardBorder),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: const Row(
                children: [
                  ShieiSkeletonCircle(size: 18),
                  SizedBox(width: 10),
                  ShieiSkeletonBox(width: 150, height: 14, borderRadius: 4),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Entity Cards List
            Expanded(
              child: Column(
                children: List.generate(6, (i) => Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: cardBorder),
                  ),
                  child: const Row(
                    children: [
                      ShieiSkeletonCircle(size: 40),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ShieiSkeletonBox(width: 140, height: 14, borderRadius: 4),
                            SizedBox(height: 6),
                            ShieiSkeletonBox(width: 90, height: 11, borderRadius: 4),
                          ],
                        ),
                      ),
                      SizedBox(width: 8),
                      ShieiSkeletonBox(width: 50, height: 22, borderRadius: 6),
                      SizedBox(width: 6),
                      ShieiSkeletonCircle(size: 24),
                    ],
                  ),
                )),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Composite: Changelog Version Milestone Skeleton.
class ChangelogSkeleton extends StatelessWidget {
  const ChangelogSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final cardBg = isDark ? const Color(0xFF131C2E) : Colors.white;
    final cardBorder = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

    return ShieiShimmer(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          children: List.generate(3, (i) => Container(
            margin: const EdgeInsets.only(bottom: 18),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: cardBorder),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ShieiSkeletonBox(width: 80, height: 24, borderRadius: 6),
                    ShieiSkeletonBox(width: 100, height: 12, borderRadius: 4),
                  ],
                ),
                SizedBox(height: 14),
                ShieiSkeletonBox(width: 200, height: 15, borderRadius: 4),
                SizedBox(height: 12),
                ShieiSkeletonBox(width: double.infinity, height: 12, borderRadius: 4),
                SizedBox(height: 8),
                ShieiSkeletonBox(width: double.infinity, height: 12, borderRadius: 4),
                SizedBox(height: 8),
                ShieiSkeletonBox(width: 220, height: 12, borderRadius: 4),
              ],
            ),
          )),
        ),
      ),
    );
  }
}

/// Composite: Proctor Profile Skeleton (Matches Official Proctor ID Badge Card, Tour banner & controls).
class ProctorProfileSkeleton extends StatelessWidget {
  final bool showTour;

  const ProctorProfileSkeleton({
    super.key,
    this.showTour = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final cardBg = isDark ? const Color(0xFF131C2E) : Colors.white;
    final cardBorder = isDark ? const Color(0xFF334155) : const Color(0xFFFED7AA);

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight > 50 ? constraints.maxHeight - 36 : 400,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. Official Proctor ID Badge Card Skeleton
                    Container(
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: cardBorder, width: 1.2),
                      ),
                      child: ShieiShimmer(
                        child: Column(
                          children: [
                            // Card Top Ribbon
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.transparent,
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(19)),
                                border: Border(
                                  bottom: BorderSide(
                                    color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                                  ),
                                ),
                              ),
                              child: const Row(
                                children: [
                                  ShieiSkeletonCircle(size: 16),
                                  SizedBox(width: 6),
                                  ShieiSkeletonBox(width: 140, height: 11, borderRadius: 4),
                                ],
                              ),
                            ),
                            // Card Body
                            const Padding(
                              padding: EdgeInsets.all(20),
                              child: Row(
                                children: [
                                  ShieiSkeletonCircle(size: 64),
                                  SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        ShieiSkeletonBox(width: 160, height: 17, borderRadius: 4),
                                        SizedBox(height: 8),
                                        ShieiSkeletonBox(width: 130, height: 20, borderRadius: 6),
                                        SizedBox(height: 8),
                                        ShieiSkeletonBox(width: 100, height: 12, borderRadius: 4),
                                        SizedBox(height: 10),
                                        ShieiSkeletonBox(width: 180, height: 22, borderRadius: 8),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // 2. Proctor Tour Banner Skeleton
                    if (showTour) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: isDark ? const Color(0xFF334155) : const Color(0xFFFED7AA),
                          ),
                        ),
                        child: const ShieiShimmer(
                          child: Row(
                            children: [
                              ShieiSkeletonCircle(size: 46),
                              SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ShieiSkeletonBox(width: 150, height: 14, borderRadius: 4),
                                    SizedBox(height: 6),
                                    ShieiSkeletonBox(width: 190, height: 11, borderRadius: 4),
                                  ],
                                ),
                              ),
                              SizedBox(width: 10),
                              ShieiSkeletonBox(width: 70, height: 28, borderRadius: 8),
                            ],
                          ),
                        ),
                      ),
                    ],

                    // 2. Pengaturan & Preferensi Grouped Card Skeleton
                    const SizedBox(height: 18),
                    const Padding(
                      padding: EdgeInsets.only(left: 4, bottom: 8),
                      child: ShieiShimmer(
                        child: ShieiSkeletonBox(width: 140, height: 11, borderRadius: 3),
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: cardBorder),
                      ),
                      child: ShieiShimmer(
                        child: Column(
                          children: [
                            // Tile 1: Ubah Kata Sandi
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              child: Row(
                                children: [
                                  ShieiSkeletonBox(width: 36, height: 36, borderRadius: 10),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        ShieiSkeletonBox(width: 120, height: 13, borderRadius: 4),
                                        SizedBox(height: 4),
                                        ShieiSkeletonBox(width: 190, height: 11, borderRadius: 4),
                                      ],
                                    ),
                                  ),
                                  Icon(Icons.chevron_right_rounded, color: Colors.grey, size: 20),
                                ],
                              ),
                            ),
                            Divider(height: 1, indent: 62, color: cardBorder),

                            // Tile 2: Alarm Suara Kecurangan
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              child: Row(
                                children: [
                                  ShieiSkeletonBox(width: 36, height: 36, borderRadius: 10),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        ShieiSkeletonBox(width: 135, height: 13, borderRadius: 4),
                                        SizedBox(height: 4),
                                        ShieiSkeletonBox(width: 180, height: 11, borderRadius: 4),
                                      ],
                                    ),
                                  ),
                                  ShieiSkeletonBox(width: 38, height: 22, borderRadius: 12),
                                ],
                              ),
                            ),
                            Divider(height: 1, indent: 62, color: cardBorder),

                            // Tile 3: Pengaturan & Info Aplikasi
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              child: Row(
                                children: [
                                  ShieiSkeletonBox(width: 36, height: 36, borderRadius: 10),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        ShieiSkeletonBox(width: 150, height: 13, borderRadius: 4),
                                        SizedBox(height: 4),
                                        ShieiSkeletonBox(width: 200, height: 11, borderRadius: 4),
                                      ],
                                    ),
                                  ),
                                  Icon(Icons.chevron_right_rounded, color: Colors.grey, size: 20),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                // 3. Logout Button Skeleton
                const Padding(
                  padding: EdgeInsets.only(top: 24, bottom: 8),
                  child: ShieiShimmer(
                    child: ShieiSkeletonBox(
                      width: double.infinity,
                      height: 46,
                      borderRadius: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

