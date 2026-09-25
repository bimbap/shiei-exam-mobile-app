import 'package:flutter/material.dart';
import '../../core/update/app_update_service.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/app_notification.dart';
import '../../shared/widgets/shiei_skeleton.dart';
import 'app_update_dialog.dart';

class ChangelogScreen extends StatefulWidget {
  final List<VersionChangelog>? initialChangelogs;

  const ChangelogScreen({super.key, this.initialChangelogs});

  @override
  State<ChangelogScreen> createState() => _ChangelogScreenState();
}

class _ChangelogScreenState extends State<ChangelogScreen> {
  List<VersionChangelog> _changelogs = [];
  bool _isLoading = true;
  bool _isCheckingUpdate = false;
  int? _expandedIndex = 0; // Default first version expanded

  @override
  void initState() {
    super.initState();
    if (widget.initialChangelogs != null) {
      _changelogs = widget.initialChangelogs!;
      _isLoading = false;
    } else {
      _loadChangelogs();
    }
  }

  Future<void> _loadChangelogs() async {
    final logs = await AppUpdateService.instance.fetchChangelogs();
    if (mounted) {
      setState(() {
        _changelogs = logs;
        _isLoading = false;
      });
    }
  }

  Future<void> _checkUpdate() async {
    if (_isCheckingUpdate) return;
    setState(() => _isCheckingUpdate = true);

    final info = await AppUpdateService.instance.checkForUpdate();
    if (!mounted) return;
    setState(() => _isCheckingUpdate = false);

    if (info != null && info.hasUpdate) {
      AppUpdateDialog.show(context, info);
    } else if (info != null && !info.hasUpdate) {
      AppNotification.show(
        context,
        title: 'Aplikasi Mutakhir',
        subtitle: 'Aplikasi Anda sudah memakai rilis terbaru (v${AppUpdateService.displayAppVersion}).',
        type: NotificationType.success,
      );
    } else {
      AppNotification.show(
        context,
        title: 'Pemeriksaan Selesai',
        subtitle: 'Tidak ada pembaruan wajib. Versi saat ini berjalan stabil.',
        type: NotificationType.info,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);

    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(
        title: const Text('Catatan Rilis & Pembaruan'),
        elevation: 0,
      ),
      body: _isLoading
          ? const ChangelogSkeleton()
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              children: [
                // Header Status Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isDark
                          ? const [Color(0xFF0F172A), Color(0xFF1E293B)]
                          : const [Colors.white, Color(0xFFF8FAFC)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark ? AppTheme.primaryShiei.withOpacity(0.35) : const Color(0xFFE2E8F0),
                    ),
                    boxShadow: isDark
                        ? []
                        : [
                            BoxShadow(
                              color: const Color(0xFF0F172A).withOpacity(0.04),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDark ? AppTheme.primaryShiei.withOpacity(0.2) : const Color(0xFFFFF7ED),
                          border: Border.all(
                            color: isDark ? AppTheme.primaryGlow : const Color(0xFFF97316),
                            width: 1.5,
                          ),
                        ),
                        child: Icon(
                          Icons.verified_rounded,
                          color: isDark ? AppTheme.primaryGlow : const Color(0xFFEA580C),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Versi Aplikasi Terpasang',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'v${AppUpdateService.displayAppVersion} (Build ${AppUpdateService.displayBuildNumber})',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppUpdateService.isDebugBuild
                              ? const Color(0xFFF59E0B).withValues(alpha: 0.18)
                              : (isDark ? AppTheme.accentGreen.withOpacity(0.18) : const Color(0xFFECFDF5)),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppUpdateService.isDebugBuild
                                ? const Color(0xFFF59E0B).withValues(alpha: 0.5)
                                : (isDark ? AppTheme.accentGreen.withOpacity(0.4) : const Color(0xFFA7F3D0)),
                          ),
                        ),
                        child: Text(
                          AppUpdateService.isDebugBuild ? 'DEBUG' : 'AKTIF',
                          style: TextStyle(
                            color: AppUpdateService.isDebugBuild
                                ? const Color(0xFFF59E0B)
                                : (isDark ? AppTheme.accentGreen : const Color(0xFF059669)),
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                Text(
                  'Daftar Riwayat Rilis',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 10),

                // Version List Cards
                ...List.generate(_changelogs.length, (index) {
                  final log = _changelogs[index];
                  final isExpanded = _expandedIndex == index;
                  final isLatest = index == 0;

                  return _ChangelogCard(
                    key: ValueKey(log.version),
                    log: log,
                    isLatest: isLatest,
                    isExpanded: isExpanded,
                    onToggle: () {
                      setState(() {
                        _expandedIndex = isExpanded ? null : index;
                      });
                    },
                  );
                }),

                const SizedBox(height: 8),

                // Manual Check for Updates Button
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: isDark ? const Color(0xFFFB923C) : const Color(0xFFEA580C),
                    backgroundColor: isDark ? Colors.transparent : Colors.white,
                    side: BorderSide(
                      color: isDark ? const Color(0xFFF97316).withOpacity(0.5) : const Color(0xFFFDBA74),
                    ),
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _isCheckingUpdate ? null : _checkUpdate,
                  icon: _isCheckingUpdate
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: isDark ? const Color(0xFFFB923C) : const Color(0xFFEA580C),
                          ),
                        )
                      : const Icon(Icons.sync_rounded, size: 18),
                  label: Text(
                    _isCheckingUpdate ? 'Memeriksa Server...' : 'Periksa Pembaruan Sistem (OTA)',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}

class _ChangelogCard extends StatefulWidget {
  final VersionChangelog log;
  final bool isLatest;
  final bool isExpanded;
  final VoidCallback onToggle;

  const _ChangelogCard({
    super.key,
    required this.log,
    required this.isLatest,
    required this.isExpanded,
    required this.onToggle,
  });

  @override
  State<_ChangelogCard> createState() => _ChangelogCardState();
}

class _ChangelogCardState extends State<_ChangelogCard> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _expandAnimation;
  late Animation<double> _rotateAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 320),
      vsync: this,
    );
    _expandAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeInOutCubic,
    );
    _rotateAnimation = Tween<double>(begin: 0.0, end: 0.5).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOutCubic),
    );

    if (widget.isExpanded) {
      _animController.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(covariant _ChangelogCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isExpanded != oldWidget.isExpanded) {
      if (widget.isExpanded) {
        _animController.forward();
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

  String _cleanCategoryName(String category) {
    // Strip any leading emoji or symbols so that only a single icon is shown
    return category.replaceAll(RegExp(r'^[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\s]+', unicode: true), '').trim();
  }

  IconData _getCategoryIcon(String category) {
    final lower = category.toLowerCase();
    if (lower.contains('fitur')) return Icons.rocket_launch_rounded;
    if (lower.contains('keamanan') || lower.contains('kiosk')) return Icons.shield_rounded;
    return Icons.bolt_rounded;
  }

  Color _getCategoryColor(String category, bool isDark) {
    final lower = category.toLowerCase();
    if (lower.contains('fitur')) return isDark ? const Color(0xFFFB923C) : const Color(0xFFEA580C);
    if (lower.contains('keamanan') || lower.contains('kiosk')) return isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7);
    return isDark ? const Color(0xFFFACC15) : const Color(0xFFD97706);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);

    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.surfaceDark : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Color.lerp(
                widget.isLatest
                    ? (isDark ? AppTheme.primaryBlue.withOpacity(0.35) : const Color(0xFFFED7AA))
                    : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                AppTheme.primaryShiei.withOpacity(0.65),
                _expandAnimation.value,
              )!,
              width: 1.0 + (0.5 * _expandAnimation.value),
            ),
            boxShadow: _expandAnimation.value > 0
                ? [
                    BoxShadow(
                      color: AppTheme.primaryShiei.withOpacity((isDark ? 0.12 : 0.08) * _expandAnimation.value),
                      blurRadius: 16 * _expandAnimation.value,
                      offset: Offset(0, 4 * _expandAnimation.value),
                    ),
                  ]
                : (isDark
                    ? []
                    : [
                        BoxShadow(
                          color: const Color(0xFF0F172A).withOpacity(0.03),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]),
          ),
          child: Column(
            children: [
              // Clickable Version Header
              InkWell(
                borderRadius: BorderRadius.circular(15),
                onTap: widget.onToggle,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          gradient: widget.isLatest
                              ? const LinearGradient(colors: [Color(0xFFF97316), Color(0xFFEA580C)])
                              : null,
                          color: widget.isLatest
                              ? null
                              : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: widget.isLatest
                                ? const Color(0xFFFB923C)
                                : (isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1)),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              widget.isLatest ? Icons.auto_awesome_rounded : Icons.history_rounded,
                              size: 13,
                              color: widget.isLatest
                                  ? Colors.white
                                  : (isDark ? AppTheme.textSecondary : const Color(0xFF475569)),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              widget.log.version,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: widget.isLatest
                                    ? Colors.white
                                    : (isDark ? AppTheme.textSecondary : const Color(0xFF475569)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.log.releaseDate,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Build ${widget.log.buildNumber} • ${widget.isLatest ? "Rilis Terbaru" : "Arsip Riwayat"}',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      RotationTransition(
                        turns: _rotateAnimation,
                        child: Icon(
                          Icons.expand_more_rounded,
                          color: Color.lerp(
                            isDark ? AppTheme.textMuted : const Color(0xFF94A3B8),
                            AppTheme.primaryGlow,
                            _expandAnimation.value,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Smooth Pill Expansion & Collapse Animation (SizeTransition on Pill Container)
              SizeTransition(
                sizeFactor: _expandAnimation,
                axisAlignment: -1.0,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Divider(
                      color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                      height: 1,
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (widget.log.title.isNotEmpty) ...[
                            Text(
                              widget.log.title,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                                height: 1.35,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 6),
                          ],
                          if (widget.log.headline.isNotEmpty) ...[
                            Text(
                              widget.log.headline,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                                height: 1.45,
                              ),
                            ),
                            const SizedBox(height: 14),
                          ],

                          // Categories (Clean Single Icon)
                          ...widget.log.categories.map((cat) {
                            final icon = _getCategoryIcon(cat.name);
                            final iconColor = _getCategoryColor(cat.name, isDark);
                            final cleanTitle = _cleanCategoryName(cat.name);

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(icon, size: 15, color: iconColor),
                                      const SizedBox(width: 8),
                                      Text(
                                        cleanTitle,
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.bold,
                                          color: iconColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  ...cat.items.map(
                                    (item) => Padding(
                                      padding: const EdgeInsets.only(left: 12, bottom: 4),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            width: 4,
                                            height: 4,
                                            margin: const EdgeInsets.only(top: 6, right: 8),
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: iconColor.withOpacity(0.7),
                                            ),
                                          ),
                                          Expanded(
                                            child: Text(
                                              item,
                                              style: TextStyle(
                                                color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
                                                fontSize: 12,
                                                height: 1.35,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
