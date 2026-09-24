import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../shared/theme/app_theme.dart';

/// Floating glassmorphic toast banner for real-time exam announcements/revisions.
/// Features push-notification style enter & exit animations (slide down, fade in, slide up, fade out),
/// timed auto-dismissal, and swipe-up to dismiss.
class ExamAnnouncementBanner extends StatefulWidget {
  final Map<String, dynamic> announcement;
  final VoidCallback onDismiss;
  final VoidCallback? onViewAll;
  final Duration autoDismissDuration;

  const ExamAnnouncementBanner({
    super.key,
    required this.announcement,
    required this.onDismiss,
    this.onViewAll,
    this.autoDismissDuration = const Duration(seconds: 8),
  });

  @override
  State<ExamAnnouncementBanner> createState() => _ExamAnnouncementBannerState();
}

class _ExamAnnouncementBannerState extends State<ExamAnnouncementBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  Timer? _autoDismissTimer;
  bool _isDismissing = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
      reverseDuration: const Duration(milliseconds: 260),
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
        reverseCurve: Curves.easeIn,
      ),
    );

    _animController.forward();

    if (widget.autoDismissDuration > Duration.zero) {
      _autoDismissTimer = Timer(widget.autoDismissDuration, () {
        _dismissWithAnimation();
      });
    }
  }

  void _dismissWithAnimation([VoidCallback? afterDismiss]) {
    if (!mounted || _isDismissing) return;
    _isDismissing = true;
    _autoDismissTimer?.cancel();
    _animController.reverse().then((_) {
      if (mounted) {
        widget.onDismiss();
        afterDismiss?.call();
      }
    });
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final String type = (widget.announcement['type'] ?? 'warning').toString();
    final String message = (widget.announcement['message'] ?? '').toString();
    final String proctor = (widget.announcement['proctor'] ?? 'Pengawas Ruangan').toString();

    Color accentColor;
    IconData icon;
    String badgeText;

    switch (type) {
      case 'urgent':
        accentColor = AppTheme.dangerRed;
        icon = Icons.error_rounded;
        badgeText = 'PERINGATAN MENDESAK';
        break;
      case 'info':
        accentColor = const Color(0xFF38BDF8);
        icon = Icons.info_rounded;
        badgeText = 'INFO PENGAWAS';
        break;
      case 'warning':
      default:
        accentColor = const Color(0xFFF59E0B);
        icon = Icons.campaign_rounded;
        badgeText = 'PENGUMUMAN';
        break;
    }

    final bgGrad = isDark
        ? [
            const Color(0xFF0F172A).withValues(alpha: 0.94),
            const Color(0xFF1E293B).withValues(alpha: 0.96),
          ]
        : [
            Colors.white.withValues(alpha: 0.96),
            const Color(0xFFF8FAFC).withValues(alpha: 0.96),
          ];

    return SafeArea(
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: GestureDetector(
            onVerticalDragUpdate: (details) {
              if (details.primaryDelta != null && details.primaryDelta! < -4) {
                _dismissWithAnimation();
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: bgGrad,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: accentColor.withValues(alpha: 0.75),
                        width: 1.8,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: accentColor.withValues(alpha: 0.25),
                          blurRadius: 20,
                          spreadRadius: 2,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header: Tag + Proctor Name + Dismiss 'X'
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: accentColor.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: accentColor.withValues(alpha: 0.4)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(icon, size: 14, color: accentColor),
                                  const SizedBox(width: 5),
                                  Text(
                                    badgeText,
                                    style: TextStyle(
                                      color: accentColor,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                proctor,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            InkWell(
                              onTap: () => _dismissWithAnimation(),
                              borderRadius: BorderRadius.circular(20),
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 18,
                                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Announcement Message Body
                        Text(
                          message,
                          style: TextStyle(
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Actions: "Saya Mengerti" + "Riwayat"
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (widget.onViewAll != null)
                              TextButton(
                                onPressed: () => _dismissWithAnimation(widget.onViewAll),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: Text(
                                  'Semua Ralat',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
                                  ),
                                ),
                              ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: () => _dismissWithAnimation(),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: accentColor,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                elevation: 2,
                              ),
                              child: const Text(
                                'Saya Mengerti',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
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

/// Modal bottom sheet showing all proctor announcements for this exam.
class ExamAnnouncementsSheet {
  static void show(
    BuildContext context, {
    required List<Map<String, dynamic>> announcements,
    required VoidCallback onClearUnread,
  }) {
    final isDark = AppTheme.isDark(context);
    final bg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final emptyColor = isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8);

    onClearUnread();

    showModalBottomSheet(
      context: context,
      backgroundColor: bg,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.7,
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Title Row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryShiei.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.campaign_rounded,
                      color: AppTheme.primaryGlow,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Papan Pengumuman Pengawas',
                          style: TextStyle(
                            color: titleColor,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Ralat soal dan informasi resmi selama ujian berlangsung',
                          style: TextStyle(
                            color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 12),

              // List of Announcements
              if (announcements.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 36),
                  child: Column(
                    children: [
                      Icon(Icons.mark_chat_read_rounded, size: 48, color: emptyColor),
                      const SizedBox(height: 12),
                      Text(
                        'Belum Ada Pengumuman',
                        style: TextStyle(
                          color: titleColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Jika ada ralat soal dari guru pengawas, informasi akan muncul seketika di sini.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: emptyColor, fontSize: 12),
                      ),
                    ],
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: announcements.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (ctx, i) {
                      final item = announcements[i];
                      final type = (item['type'] ?? 'warning').toString();
                      final message = (item['message'] ?? '').toString();
                      final proctor = (item['proctor'] ?? 'Pengawas').toString();
                      final time = (item['created_at'] ?? '').toString();

                      Color itemColor = const Color(0xFFF59E0B);
                      if (type == 'urgent') itemColor = AppTheme.dangerRed;
                      if (type == 'info') itemColor = const Color(0xFF38BDF8);

                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B).withValues(alpha: 0.6) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.circle, size: 8, color: itemColor),
                                const SizedBox(width: 6),
                                Text(
                                  proctor,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold,
                                    color: itemColor,
                                  ),
                                ),
                                const Spacer(),
                                if (time.isNotEmpty)
                                  Text(
                                    _formatTime(time),
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              message,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  static String _formatTime(String isoString) {
    try {
      final dt = DateTime.parse(isoString).toLocal();
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m WIB';
    } catch (_) {
      return '';
    }
  }
}
