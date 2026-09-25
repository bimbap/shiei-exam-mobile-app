import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/utils/format_utils.dart';
import '../../../shared/widgets/app_notification.dart';
import '../../../shared/widgets/shiei_animated_counter.dart';
import '../../../shared/widgets/shiei_skeleton.dart';
import '../detail/exam_detail_screen.dart';
import '../dialogs/broadcast_announcement_dialog.dart';
import '../dialogs/confirm_unlock_dialog.dart';
import '../dialogs/qr_unblock_scanner_dialog.dart';
import '../teacher_portal_controller.dart';
import '../../tour/proctor_tour_dialog.dart';

class DashboardTab extends StatelessWidget {
  final TeacherPortalController controller;
  final Function(int targetTab, {String? statusFilter, String? dataCategory}) onNavigateTab;
  final ProctorTourTargetKeys? tourKeys;

  const DashboardTab({
    super.key,
    required this.controller,
    required this.onNavigateTab,
    this.tourKeys,
  });

  void _showAllTokensDialog(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final activeExams = controller.activeExams;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppTheme.surfaceDark : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF97316).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.key_rounded, color: Color(0xFFFB923C), size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Token Akses Ujian',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  Text(
                    'Khusus jadwal ujian yang sedang aktif',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: activeExams.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.key_off_rounded,
                          size: 36,
                          color: isDark ? AppTheme.textSecondary : const Color(0xFF94A3B8),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Tidak Ada Jadwal Ujian Aktif',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Token hanya dimunculkan untuk ujian yang sedang berlangsung atau aktif saat ini.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: activeExams.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (ctx, index) {
                    final exam = activeExams[index];
                    final token = exam['token']?.toString() ?? '-';
                    final bool hasToken = token.isNotEmpty && token != '-' && token != 'TIDAK-ADA';
                    final title = exam['title']?.toString() ?? 'Ujian';
                    final subject = exam['subject']?.toString() ?? 'Umum';

                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? AppTheme.surfaceCard : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                                  ),
                                ),
                                Text(
                                  subject,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: hasToken ? () {
                              Clipboard.setData(ClipboardData(text: token));
                              AppNotification.showSuccess(
                                context,
                                'Token Disalin',
                                subtitle: 'Kode PIN $token tersimpan di clipboard.',
                              );
                            } : null,
                            borderRadius: BorderRadius.circular(8),
                            child: Opacity(
                              opacity: hasToken ? 1.0 : 0.55,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  gradient: hasToken
                                      ? const LinearGradient(
                                          colors: [Color(0xFFF97316), Color(0xFFD97706)],
                                        )
                                      : null,
                                  color: hasToken ? null : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: hasToken
                                      ? [
                                          BoxShadow(
                                            color: const Color(0xFFF97316).withValues(alpha: 0.3),
                                            blurRadius: 6,
                                            offset: const Offset(0, 2),
                                          ),
                                        ]
                                      : null,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      hasToken ? token : '-',
                                      style: TextStyle(
                                        color: hasToken ? Colors.white : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                    if (hasToken) ...[
                                      const SizedBox(width: 6),
                                      const Icon(Icons.copy_rounded, size: 14, color: Colors.white),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final isTablet = MediaQuery.sizeOf(context).width >= 600;
    final schoolName = controller.school?['name']?.toString() ?? 'Sekolah Terdaftar';
    final rawUserName = controller.currentUser?['name']?.toString().trim();
    final userName = (rawUserName != null && rawUserName.isNotEmpty)
        ? rawUserName
        : (controller.isAdmin ? 'Admin Sekolah' : 'Pengawas Ujian');
    final roleName = controller.isAdmin ? 'Administrator Sekolah' : 'Pengawas Ujian';

    return RefreshIndicator(
      color: AppTheme.primaryShiei,
      onRefresh: () => controller.refreshDashboard(clearPrevious: true),
      child: (controller.isLoading || controller.isDashboardLoading)
          ? const DashboardSkeleton()
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              children: [
          // 1. Welcome Proctor Header Banner
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
                    : [const Color(0xFFFFF7ED), Colors.white],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFFED7AA),
              ),
              boxShadow: [
                BoxShadow(
                  color: isDark ? Colors.black26 : const Color(0xFFF97316).withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFF97316), Color(0xFFEA580C)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFF97316).withValues(alpha: 0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(Icons.shield_rounded, color: Colors.white, size: 26),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEA580C).withValues(alpha: isDark ? 0.2 : 0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: const Color(0xFFEA580C).withValues(alpha: isDark ? 0.4 : 0.25),
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              roleName,
                              style: const TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFEA580C),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () {
                              if (controller.isConnectionLost) {
                                controller.loadMonitoringData(clearPrevious: false);
                                AppNotification.showInfo(
                                  context,
                                  'Mencoba Menghubungkan Ulang',
                                  subtitle: 'Memeriksa kembali koneksi ke server ujian...',
                                );
                                return;
                              }
                              controller.toggleAutoRefresh(!controller.autoRefresh);
                              AppNotification.show(
                                context,
                                title: controller.autoRefresh ? 'Live Sync DIAKTIFKAN' : 'Live Sync DIMATIKAN',
                                subtitle: controller.autoRefresh
                                    ? 'Monitoring siswa update otomatis per 5 detik.'
                                    : 'Update otomatis dimatikan.',
                                type: controller.autoRefresh ? NotificationType.success : NotificationType.info,
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: (controller.isConnectionLost
                                        ? const Color(0xFFEF4444)
                                        : (controller.autoRefresh ? const Color(0xFF10B981) : const Color(0xFF64748B)))
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: (controller.isConnectionLost
                                          ? const Color(0xFFEF4444)
                                          : (controller.autoRefresh ? const Color(0xFF10B981) : const Color(0xFF64748B)))
                                      .withValues(alpha: 0.3),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    controller.isConnectionLost
                                        ? Icons.wifi_off_rounded
                                        : Icons.circle,
                                    color: controller.isConnectionLost
                                        ? const Color(0xFFEF4444)
                                        : (controller.autoRefresh ? const Color(0xFF10B981) : const Color(0xFF64748B)),
                                    size: controller.isConnectionLost ? 8.5 : 5,
                                  ),
                                  const SizedBox(width: 3.5),
                                  ValueListenableBuilder<int>(
                                    valueListenable: controller.syncCountdown,
                                    builder: (context, countdown, _) {
                                      final badgeColor = controller.isConnectionLost
                                          ? const Color(0xFFEF4444)
                                          : (controller.autoRefresh ? const Color(0xFF10B981) : const Color(0xFF64748B));
                                      final badgeStyle = TextStyle(
                                        color: badgeColor,
                                        fontSize: 8.5,
                                        fontWeight: FontWeight.w800,
                                      );

                                      if (controller.isConnectionLost) {
                                        return Text('OFFLINE', style: badgeStyle);
                                      }
                                      if (!controller.autoRefresh) {
                                        return Text('MANUAL', style: badgeStyle);
                                      }
                                      return Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text('LIVE (', style: badgeStyle),
                                          ShieiAnimatedCounter(
                                            count: countdown,
                                            duration: const Duration(milliseconds: 380),
                                            curve: Curves.easeInOutCubic,
                                            style: badgeStyle,
                                          ),
                                          Text('s)', style: badgeStyle),
                                        ],
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        userName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            Icons.school_outlined,
                            size: 12.5,
                            color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              schoolName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: controller.fraudAlertEnabled
                        ? const Color(0xFFF59E0B).withValues(alpha: isDark ? 0.2 : 0.12)
                        : (isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9)),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: controller.fraudAlertEnabled
                          ? const Color(0xFFF59E0B).withValues(alpha: 0.35)
                          : (isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1)),
                      width: 0.8,
                    ),
                  ),
                  child: IconButton(
                    icon: Icon(
                      controller.fraudAlertEnabled ? Icons.notifications_active_rounded : Icons.notifications_off_rounded,
                      size: 18,
                      color: controller.fraudAlertEnabled ? const Color(0xFFF59E0B) : (isDark ? AppTheme.textSecondary : const Color(0xFF94A3B8)),
                    ),
                    tooltip: controller.fraudAlertEnabled ? 'Alarm Suara/Getar Aktif' : 'Alarm Dibisukan',
                    padding: EdgeInsets.zero,
                    onPressed: () {
                      controller.toggleFraudAlertSound();
                      AppNotification.show(
                        context,
                        title: controller.fraudAlertEnabled ? 'Alarm Fraud DIAKTIFKAN' : 'Alarm Fraud DIBISUKAN',
                        subtitle: controller.fraudAlertEnabled ? 'HP akan bergetar dan membunyikan sirene jika ada siswa melanggar.' : 'Pemberitahuan suara dimatikan.',
                        type: controller.fraudAlertEnabled ? NotificationType.warning : NotificationType.info,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 2. Fraud Alert Carousel (Triggered upon student cheat / ejection)
          if (controller.activeFraudAlerts.isNotEmpty) ...[
            _FraudAlertsCarousel(
              controller: controller,
              isDark: isDark,
              onShowDetail: _showFraudAlertDetailSheet,
            ),
            const SizedBox(height: 16),
          ],

          // 3. 4 KPI Counter Cards Grid (Aligned with Web School Panel - Display Only)
          Container(
            key: tourKeys?.overviewMetricsKey,
            child: isTablet
                ? Row(
                    children: [
                      Expanded(
                        child: _buildKpiCard(
                          context,
                          title: 'UJIAN AKTIF',
                          value: controller.activeLiveExams.length.toString(),
                          icon: Icons.play_circle_fill_rounded,
                          color: const Color(0xFF10B981),
                          isDark: isDark,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildKpiCard(
                          context,
                          title: 'TERKUNCI / ALERT',
                          value: controller.lockedCount.toString(),
                          icon: Icons.warning_rounded,
                          color: controller.lockedCount > 0 ? const Color(0xFFEF4444) : const Color(0xFF64748B),
                          isDark: isDark,
                          showPulse: controller.lockedCount > 0,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildKpiCard(
                          context,
                          title: 'TOTAL SISWA',
                          value: (controller.students.isNotEmpty
                                  ? controller.students.length
                                  : (controller.allUsers.where((u) => u['role']?.toString().toLowerCase() == 'student').length))
                              .toString(),
                          icon: Icons.groups_rounded,
                          color: const Color(0xFF3B82F6),
                          isDark: isDark,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildKpiCard(
                          context,
                          title: 'TOTAL KELAS',
                          value: controller.classes.length.toString(),
                          icon: Icons.meeting_room_rounded,
                          color: const Color(0xFFF59E0B),
                          isDark: isDark,
                        ),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _buildKpiCard(
                              context,
                              title: 'UJIAN AKTIF',
                              value: controller.activeLiveExams.length.toString(),
                              icon: Icons.play_circle_fill_rounded,
                              color: const Color(0xFF10B981),
                              isDark: isDark,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildKpiCard(
                              context,
                              title: 'TERKUNCI / ALERT',
                              value: controller.lockedCount.toString(),
                              icon: Icons.warning_rounded,
                              color: controller.lockedCount > 0 ? const Color(0xFFEF4444) : const Color(0xFF64748B),
                              isDark: isDark,
                              showPulse: controller.lockedCount > 0,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _buildKpiCard(
                              context,
                              title: 'TOTAL SISWA',
                              value: (controller.students.isNotEmpty
                                      ? controller.students.length
                                      : (controller.allUsers.where((u) => u['role']?.toString().toLowerCase() == 'student').length))
                                  .toString(),
                              icon: Icons.groups_rounded,
                              color: const Color(0xFF3B82F6),
                              isDark: isDark,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildKpiCard(
                              context,
                              title: 'TOTAL KELAS',
                              value: controller.classes.length.toString(),
                              icon: Icons.meeting_room_rounded,
                              color: const Color(0xFFF59E0B),
                              isDark: isDark,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
    const SizedBox(height: 20),

    // 4. Quick Actions Grid
    Container(
      key: tourKeys?.quickActionsKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'AKSI CEPAT PENGAWAS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 10),
          // High-priority Proctor Tools: Adaptive Grid
          if (isTablet)
            Row(
              children: [
                Expanded(
                  child: _buildActionButton(
                    context,
                    label: 'Scan QR',
                    subtitle: 'Buka Kunci Kamera',
                    icon: Icons.qr_code_scanner_rounded,
                    color: const Color(0xFF8B5CF6),
                    isDark: isDark,
                    onTap: () => QrUnblockScannerDialog.show(context: context, controller: controller),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildActionButton(
                    context,
                    label: 'Pengumuman',
                    subtitle: 'Kirim Pesan ke Siswa',
                    icon: Icons.campaign_rounded,
                    color: const Color(0xFFF59E0B),
                    isDark: isDark,
                    onTap: () => BroadcastAnnouncementDialog.show(context: context, controller: controller),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildActionButton(
                    context,
                    label: 'Pelanggaran',
                    subtitle: 'Log Pelanggaran Siswa',
                    icon: Icons.security_update_warning_rounded,
                    color: const Color(0xFFEF4444),
                    isDark: isDark,
                    onTap: () => onNavigateTab(1, statusFilter: 'locked'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildActionButton(
                    context,
                    label: 'Token Ujian',
                    subtitle: 'Lihat PIN Ujian Aktif',
                    icon: Icons.vpn_key_rounded,
                    color: const Color(0xFFF97316),
                    isDark: isDark,
                    onTap: () => _showAllTokensDialog(context),
                  ),
                ),
              ],
            )
          else
            Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildActionButton(
                        context,
                        label: 'Scan QR',
                        subtitle: 'Buka Kunci Kamera',
                        icon: Icons.qr_code_scanner_rounded,
                        color: const Color(0xFF8B5CF6),
                        isDark: isDark,
                        onTap: () => QrUnblockScannerDialog.show(context: context, controller: controller),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildActionButton(
                        context,
                        label: 'Pengumuman',
                        subtitle: 'Kirim Pesan ke Siswa',
                        icon: Icons.campaign_rounded,
                        color: const Color(0xFFF59E0B),
                        isDark: isDark,
                        onTap: () => BroadcastAnnouncementDialog.show(context: context, controller: controller),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _buildActionButton(
                        context,
                        label: 'Pelanggaran',
                        subtitle: 'Log Pelanggaran Siswa',
                        icon: Icons.security_update_warning_rounded,
                        color: const Color(0xFFEF4444),
                        isDark: isDark,
                        onTap: () => onNavigateTab(1, statusFilter: 'locked'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildActionButton(
                        context,
                        label: 'Token Ujian',
                        subtitle: 'Lihat PIN Ujian Aktif',
                        icon: Icons.vpn_key_rounded,
                        color: const Color(0xFFF97316),
                        isDark: isDark,
                        onTap: () => _showAllTokensDialog(context),
                      ),
                    ),
                  ],
                ),
              ],
            ),
        ],
      ),
    ),
    const SizedBox(height: 24),

          // 5. Active Exams Preview List
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'SESI UJIAN AKTIF',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                    ),
                  ),
                  if (controller.activeLiveExams.length > 1) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.22 : 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${controller.activeLiveExams.length}',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF10B981),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              GestureDetector(
                onTap: () => onNavigateTab(1),
                child: const Text(
                  'Lihat Semua →',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFF97316),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          if (controller.activeLiveExams.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.surfaceDark : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
              ),
              child: Center(
                child: Column(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.sensors_off_rounded,
                        size: 22,
                        color: isDark ? AppTheme.textSecondary : const Color(0xFF94A3B8),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Tidak Ada Ujian yang Sedang Berjalan',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Saat ada jadwal ujian yang aktif dikerjakan siswa, sesi ujian akan langsung terpantau di sini secara real-time.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFF97316),
                        side: BorderSide(color: const Color(0xFFF97316).withValues(alpha: 0.4)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      ),
                      icon: const Icon(Icons.assignment_outlined, size: 16),
                      label: Text(
                        controller.exams.isNotEmpty
                            ? 'Buka Jadwal Ujian (${controller.exams.length} Terdaftar)'
                            : 'Buka Jadwal Ujian',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      onPressed: () => onNavigateTab(1),
                    ),
                  ],
                ),
              ),
            )
          else if (controller.activeLiveExams.length == 1)
            _buildActiveLiveExamCard(
              context,
              controller.activeLiveExams.first,
              isDark,
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              clipBehavior: Clip.none,
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (int i = 0; i < controller.activeLiveExams.length; i++) ...[
                      if (i > 0) const SizedBox(width: 12),
                      SizedBox(
                        width: (MediaQuery.of(context).size.width - 56).clamp(290.0, 360.0),
                        child: _buildActiveLiveExamCard(
                          context,
                          controller.activeLiveExams[i],
                          isDark,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActiveLiveExamCard(
    BuildContext context,
    Map<String, dynamic> exam,
    bool isDark,
  ) {
    final token = exam['token']?.toString() ?? '';
    final bool hasToken = token.isNotEmpty && token != '-' && token != 'TIDAK-ADA';
    final title = exam['title']?.toString() ?? 'Ujian';
    final subject = exam['subject']?.toString() ?? 'Umum';
    final duration = exam['duration_minutes']?.toString() ?? '60';

    // Target class name
    String className = 'Semua Kelas';
    if (exam['class_majors'] != null && (exam['class_majors'] as List).isNotEmpty) {
      final names = (exam['class_majors'] as List)
          .map((m) => m['name']?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
      if (names.length == 1) {
        className = names.first;
      } else if (names.length > 1) {
        className = '${names.length} Kelas';
      }
    } else if (exam['class_major']?['name'] != null) {
      className = exam['class_major']['name'].toString();
    }

    // Resolve creator name
    final creator = exam['creator'] as Map<String, dynamic>?;
    String creatorName = creator?['name']?.toString() ??
        exam['teacher_name']?.toString() ??
        exam['creator_name']?.toString() ??
        '';
    if (creatorName.isEmpty && exam['created_by'] != null) {
      final createdById = exam['created_by'];
      final matchTeacher = controller.teachers.firstWhere(
        (t) => t['id'] == createdById || t['user_id'] == createdById,
        orElse: () => <String, dynamic>{},
      );
      if (matchTeacher.isNotEmpty) {
        creatorName = matchTeacher['name']?.toString() ?? '';
      } else {
        final matchUser = controller.allUsers.firstWhere(
          (u) => u['id'] == createdById,
          orElse: () => <String, dynamic>{},
        );
        if (matchUser.isNotEmpty) {
          creatorName = matchUser['name']?.toString() ?? '';
        }
      }
    }
    if (creatorName.isEmpty) {
      creatorName = 'Guru Pembuat';
    }

    // Schedule date & time window
    final startTimeRaw = exam['start_time'];
    final endTimeRaw = exam['end_time'];

    String dateFormatted = 'Sesuai Jadwal';
    String timeWindowFormatted = 'Waktu Fleksibel';
    if (startTimeRaw != null) {
      try {
        final startDt = DateTime.parse(startTimeRaw.toString()).toLocal();
        dateFormatted = DateFormat('d MMM yyyy', 'id_ID').format(startDt);
        final startHm = DateFormat('HH:mm').format(startDt);
        if (endTimeRaw != null) {
          final endDt = DateTime.parse(endTimeRaw.toString()).toLocal();
          final endHm = DateFormat('HH:mm').format(endDt);
          timeWindowFormatted = '$startHm - $endHm WIB';
        } else {
          timeWindowFormatted = '$startHm WIB - Selesai';
        }
      } catch (_) {}
    }

    final activeStudentRecords = controller.monitoringRecords.where((r) {
      final linkId = r['link_id'] ?? r['link']?['id'];
      return linkId?.toString() == exam['id']?.toString() &&
             (r['status'] == 'in_progress' || r['is_locked'] == true);
    }).toList();
    final activeStudentCount = activeStudentRecords.length;
    final lockedCount = activeStudentRecords.where((r) => r['is_locked'] == true).length;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: lockedCount > 0
              ? const Color(0xFFEF4444).withValues(alpha: isDark ? 0.4 : 0.3)
              : activeStudentCount > 0
                  ? const Color(0xFF10B981).withValues(alpha: isDark ? 0.35 : 0.25)
                  : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
          width: lockedCount > 0 || activeStudentCount > 0 ? 1.2 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ExamDetailScreen(
                  exam: exam,
                  controller: controller,
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. Top Row: Live Status Badge + Token PIN + Arrow
                Row(
                  children: [
                    // Live Status Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.18 : 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.4 : 0.25),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFF10B981),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            activeStudentCount > 0
                                ? '$activeStudentCount Siswa Mengerjakan'
                                : 'Sesi Ujian Berjalan',
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF10B981),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    // Token Pill
                    if (hasToken)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEA580C).withValues(alpha: isDark ? 0.16 : 0.08),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: const Color(0xFFEA580C).withValues(alpha: isDark ? 0.35 : 0.2),
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.key_rounded, size: 10.5, color: Color(0xFFEA580C)),
                            const SizedBox(width: 4),
                            Text(
                              token,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.w800,
                                fontSize: 11,
                                color: Color(0xFFEA580C),
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          'Bebas Token',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                          ),
                        ),
                      ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 11,
                      color: isDark ? AppTheme.textSecondary : const Color(0xFF94A3B8),
                    ),
                  ],
                ),

                // 2. Alert Banner for Locked Students (Clear & Uncluttered)
                if (lockedCount > 0) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: isDark ? 0.18 : 0.08),
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(
                        color: const Color(0xFFEF4444).withValues(alpha: isDark ? 0.45 : 0.25),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.lock_clock_rounded, size: 12.5, color: Color(0xFFEF4444)),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            '$lockedCount Siswa Terkunci (Butuh Buka Kunci)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFEF4444),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 10),

                // 3. Exam Title
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                    height: 1.25,
                  ),
                ),

                const SizedBox(height: 8),

                // 4. Metadata Chips: Mapel + Kelas + Guru Pembuat
                Wrap(
                  spacing: 6,
                  runSpacing: 5,
                  children: [
                    // Subject
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6366F1).withValues(alpha: isDark ? 0.14 : 0.08),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: const Color(0xFF6366F1).withValues(alpha: isDark ? 0.3 : 0.18),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.book_outlined, size: 11, color: Color(0xFF6366F1)),
                          const SizedBox(width: 4),
                          Text(
                            subject,
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF6366F1),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Class
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.school_outlined,
                            size: 11,
                            color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                          ),
                          const SizedBox(width: 4),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 110),
                            child: Text(
                              className,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white70 : const Color(0xFF475569),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Creator (Guru Pembuat)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.person_outline_rounded,
                            size: 11,
                            color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                          ),
                          const SizedBox(width: 4),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 115),
                            child: Text(
                              creatorName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white70 : const Color(0xFF475569),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // 5. Schedule & Timing Box: Tanggal, Jam, dan Durasi
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7.5),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    children: [
                      // Date & Time
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.calendar_today_rounded,
                                  size: 11,
                                  color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                                ),
                                const SizedBox(width: 4.5),
                                Text(
                                  dateFormatted,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.white70 : const Color(0xFF334155),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                const Icon(
                                  Icons.access_time_rounded,
                                  size: 11,
                                  color: Color(0xFFEA580C),
                                ),
                                const SizedBox(width: 4.5),
                                Text(
                                  timeWindowFormatted,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFEA580C),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Divider
                      Container(
                        width: 1,
                        height: 24,
                        color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      // Duration
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Durasi',
                            style: TextStyle(
                              fontSize: 9.5,
                              color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            FormatUtils.formatDurationHoursMinutes(duration, shortSuffix: true),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildKpiCard(
    BuildContext context, {
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required bool isDark,
    bool showPulse = false,
    VoidCallback? onTap,
  }) {
    final cardContent = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: showPulse
              ? color.withValues(alpha: 0.6)
              : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
          width: showPulse ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                ),
              ),
              Icon(icon, size: 18, color: color),
            ],
          ),
          const SizedBox(height: 8),
          int.tryParse(value) != null
              ? ShieiAnimatedCounter(
                  count: int.parse(value),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                )
              : Text(
                  value,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
        ],
      ),
    );

    if (onTap == null) {
      return cardContent;
    }

    return Material(
      color: isDark ? AppTheme.surfaceDark : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: cardContent,
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context, {
    required String label,
    required String subtitle,
    required IconData icon,
    required Color color,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Material(
      color: isDark ? AppTheme.surfaceDark : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        label,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    const SizedBox(height: 1),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        subtitle,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 10,
                          color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }



  static String formatReason(String? reason) {
    if (reason == null || reason.isEmpty) return 'Pelanggaran Keamanan';
    final lower = reason.toLowerCase();
    if (lower.contains('proctor_kick') || lower.contains('kicked')) {
      return 'Dikeluarkan Pengawas';
    } else if (lower.contains('split') || lower.contains('multi_window')) {
      return 'Layar Terbelah (Split Screen)';
    } else if (lower.contains('overlay') || lower.contains('floating')) {
      return 'Jendela Mengambang (Overlay)';
    } else if (lower.contains('minimize')) {
      return 'Keluar Aplikasi (Minimize)';
    } else if (lower.contains('app_switch') || lower.contains('switch')) {
      return 'Pindah Aplikasi';
    } else if (lower.contains('screenshot') || lower.contains('capture')) {
      return 'Percobaan Tangkapan Layar';
    } else if (lower.contains('pip')) {
      return 'Mode Picture-in-Picture';
    } else if (lower.contains('phone_call') || lower.contains('call')) {
      return 'Panggilan Suara / Telepon';
    } else if (lower.contains('bluetooth')) {
      return 'Koneksi Bluetooth Aktif';
    } else if (lower.contains('external_display') || lower.contains('hdmi') || lower.contains('mirroring')) {
      return 'Layar Eksternal / Mirroring';
    } else if (lower.contains('notification') || lower.contains('pulldown')) {
      return 'Buka Bar Notifikasi';
    }
    return reason;
  }

  void _showFraudAlertDetailSheet(BuildContext context, Map<String, dynamic> alert) {
    final isDark = AppTheme.isDark(context);
    final studentName = alert['student_name']?.toString() ?? 'Siswa';
    final rawReason = alert['lock_reason']?.toString() ??
        alert['reason']?.toString() ??
        alert['event_type']?.toString();
    final reason = formatReason(rawReason);
    final examTitle = alert['exam_title']?.toString() ?? 'Sesi Ujian';
    final linkId = alert['exam_id'] ?? alert['link_id'];
    final userId = alert['student_id'] ?? alert['user_id'];
    final rawTs = alert['locked_at'] ??
        alert['timestamp'] ??
        alert['occurred_at'] ??
        alert['created_at'] ??
        alert['updated_at'];
    final formattedTimestamp = ConfirmUnlockDialog.formatTimestamp(rawTs?.toString());

    final bool isKicked = rawReason == 'proctor_kick' ||
        reason.toLowerCase().contains('pengawas') ||
        alert['is_kicked'] == true ||
        alert['status'] == 'terminated';
    final bool isExamEnded = alert['is_exam_ended'] == true;
    final bool canManageStudent = controller.isAdmin || controller.canUnlockStudentForExam(linkId);
    final bool canUnlock = linkId != null && userId != null && !isKicked && !isExamEnded && canManageStudent;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 600),
      backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.security_update_warning_rounded,
                      color: Color(0xFFEF4444),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Detail Pelanggaran Ujian',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'Sesi terkunci otomatis oleh sistem keamanan kiosk',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Column(
                  children: [
                    _buildAlertDetailRow('Nama Siswa', studentName, isDark, isBold: true),
                    const Divider(height: 16),
                    _buildAlertDetailRow('Jadwal Ujian', examTitle, isDark),
                    const Divider(height: 16),
                    _buildAlertDetailRow(
                      'Jenis Pelanggaran',
                      reason,
                      isDark,
                      valueColor: const Color(0xFFEF4444),
                      isBold: true,
                    ),
                    if (rawTs != null) ...[
                      const Divider(height: 16),
                      _buildAlertDetailRow(
                        'Waktu Kejadian',
                        formattedTimestamp,
                        isDark,
                        valueColor: isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A),
                        isBold: true,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                        side: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () => Navigator.pop(sheetCtx),
                      child: const Text('Tutup', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  if (canUnlock) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFEA580C),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          elevation: 0,
                        ),
                        icon: const Icon(Icons.lock_open_rounded, size: 17),
                        label: const Text('Buka Kunci Siswa', style: TextStyle(fontWeight: FontWeight.w900)),
                        onPressed: () async {
                          final intLinkId = linkId is int ? linkId : int.tryParse(linkId.toString()) ?? 0;
                          final intUserId = userId is int ? userId : int.tryParse(userId.toString()) ?? 0;
                          if (intLinkId <= 0 || intUserId <= 0) return;

                          // Show explicit confirmation dialog
                          final confirmed = await ConfirmUnlockDialog.show(
                            context: context,
                            studentName: studentName,
                            violationReason: rawReason ?? reason,
                            examTitle: examTitle,
                            timestamp: rawTs != null ? formattedTimestamp : null,
                          );

                          if (confirmed && context.mounted) {
                            Navigator.pop(sheetCtx);
                            final ok = await controller.unlockStudent(intLinkId, intUserId);
                            if (context.mounted && ok) {
                              controller.removeFraudAlertForStudent(intUserId);
                              AppNotification.showSuccess(
                                context,
                                'Kunci Berhasil Dibuka',
                                subtitle: '$studentName sekarang dapat melanjutkan ujian.',
                              );
                            }
                          }
                        },
                      ),
                    ),
                  ] else if (!canManageStudent && !isKicked && !isExamEnded) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.lock_outline_rounded, size: 15, color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Akses Terbatas',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else if (isKicked) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.person_off_rounded, size: 16, color: Color(0xFFEF4444)),
                            SizedBox(width: 6),
                            Text(
                              'Siswa Dikeluarkan',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Color(0xFFEF4444)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAlertDetailRow(
    String label,
    String value,
    bool isDark, {
    Color? valueColor,
    bool isBold = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: valueColor ?? (isDark ? Colors.white : const Color(0xFF0F172A)),
            ),
          ),
        ),
      ],
    );
  }
}

class _FraudAlertsCarousel extends StatefulWidget {
  final TeacherPortalController controller;
  final bool isDark;
  final void Function(BuildContext context, Map<String, dynamic> alert) onShowDetail;

  const _FraudAlertsCarousel({
    required this.controller,
    required this.isDark,
    required this.onShowDetail,
  });

  @override
  State<_FraudAlertsCarousel> createState() => _FraudAlertsCarouselState();
}

class _FraudAlertsCarouselState extends State<_FraudAlertsCarousel> {
  late final PageController _pageController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  String _formatReason(String? reason) => DashboardTab.formatReason(reason);

  @override
  Widget build(BuildContext context) {
    final alerts = widget.controller.activeFraudAlerts;
    if (alerts.isEmpty) return const SizedBox.shrink();

    // Clamp current page if list shrank
    if (_currentPage >= alerts.length) {
      _currentPage = alerts.length - 1;
    }

    final isMulti = alerts.length > 1;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 136,
          child: PageView.builder(
            controller: _pageController,
            itemCount: alerts.length,
            onPageChanged: (idx) {
              setState(() {
                _currentPage = idx;
              });
            },
            itemBuilder: (context, index) {
              final alert = alerts[index];
              final studentName = alert['student_name']?.toString() ?? 'Siswa';
              final rawReason = alert['lock_reason']?.toString() ??
                  alert['reason']?.toString() ??
                  alert['event_type']?.toString();
              final cleanReason = _formatReason(rawReason);

              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF2E1114),
                      Color(0xFF1B0B0E),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.45),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Header row
                    Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444).withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.warning_amber_rounded,
                            color: Color(0xFFEF4444),
                            size: 19,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  const Text(
                                    '🚨 PELANGGARAN TERDETEKSI!',
                                    style: TextStyle(
                                      color: Color(0xFFF87171),
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                  if (isMulti) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFEF4444).withValues(alpha: 0.25),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        '${index + 1}/${alerts.length}',
                                        style: const TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFFFCA5A5),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              RichText(
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                text: TextSpan(
                                  children: [
                                    TextSpan(
                                      text: studentName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const TextSpan(
                                      text: '  •  ',
                                      style: TextStyle(
                                        color: Color(0xFF94A3B8),
                                        fontSize: 12,
                                      ),
                                    ),
                                    TextSpan(
                                      text: cleanReason,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                        color: Color(0xFFFDA4AF),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => widget.controller.dismissFraudAlert(index),
                            child: const Padding(
                              padding: EdgeInsets.all(4),
                              child: Icon(
                                Icons.close_rounded,
                                size: 18,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    // Actions row: PRIORITIZE "Lihat Detail", Secondary "Scan QR"
                    Row(
                      children: [
                        // Primary: Lihat Detail & Buka Kunci
                        Expanded(
                          flex: 3,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFDC2626),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 9),
                              elevation: 0,
                            ),
                            icon: const Icon(Icons.remove_red_eye_outlined, size: 16),
                            label: const Text(
                              'Lihat Detail & Buka Kunci',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12.5,
                              ),
                            ),
                            onPressed: () => widget.onShowDetail(context, alert),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Secondary: Scan QR (compact)
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFA78BFA),
                            side: BorderSide(
                              color: const Color(0xFF8B5CF6).withValues(alpha: 0.5),
                              width: 1,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 10),
                          ),
                          icon: const Icon(Icons.qr_code_scanner_rounded, size: 15),
                          label: const Text(
                            'Scan QR',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                          onPressed: () => QrUnblockScannerDialog.show(
                            context: context,
                            controller: widget.controller,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        if (isMulti) ...[
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final screenWidth = MediaQuery.of(context).size.width;
              // Responsive max dots: 5 for small screens (< 380px), 10 for normal/large screens
              final int maxDots = screenWidth < 380 ? 5 : 10;
              final int total = alerts.length;

              if (total <= maxDots) {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(total, (i) {
                    final isCurrent = i == _currentPage;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: isCurrent ? 14 : 5,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isCurrent ? const Color(0xFFEF4444) : Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    );
                  }),
                );
              }

              // Sliding window centered around _currentPage
              int startIndex = _currentPage - (maxDots ~/ 2);
              if (startIndex < 0) {
                startIndex = 0;
              } else if (startIndex + maxDots > total) {
                startIndex = total - maxDots;
              }

              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(maxDots, (index) {
                  final actualIndex = startIndex + index;
                  final isCurrent = actualIndex == _currentPage;
                  final isEdge = (index == 0 && startIndex > 0) ||
                      (index == maxDots - 1 && startIndex + maxDots < total);

                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: isCurrent ? 14 : (isEdge ? 3.5 : 5),
                    height: 4,
                    decoration: BoxDecoration(
                      color: isCurrent
                          ? const Color(0xFFEF4444)
                          : (isEdge ? Colors.white12 : Colors.white24),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  );
                }),
              );
            },
          ),
        ],
      ],
    );
  }
}
