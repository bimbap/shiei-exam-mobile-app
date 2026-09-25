import 'package:flutter/material.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_notification.dart';
import '../detail/student_detail_screen.dart';
import '../teacher_portal_controller.dart';
import 'adjust_time_dialog.dart';
import 'confirm_kick_dialog.dart';
import 'confirm_unlock_dialog.dart';

class StudentActionSheet {
  static void show({
    required BuildContext context,
    required TeacherPortalController controller,
    required Map<String, dynamic> record,
    dynamic examId,
    String? examTitle,
    bool isExamEnded = false,
    Future<void> Function()? onRefresh,
    VoidCallback? onOpenAuditDetail,
  }) {
    final isDark = AppTheme.isDark(context);
    final user = record['user'] as Map<String, dynamic>? ?? {};
    final link = record['link'] as Map<String, dynamic>? ?? {};

    final dynamic effectiveLinkId = examId ?? record['link_id'] ?? link['id'];
    final dynamic effectiveUserId = user['id'] ?? record['user_id'];
    final int? linkId = effectiveLinkId is int ? effectiveLinkId : int.tryParse(effectiveLinkId?.toString() ?? '');
    final int? userId = effectiveUserId is int ? effectiveUserId : int.tryParse(effectiveUserId?.toString() ?? '');

    final String studentName = user['name']?.toString() ?? 'Siswa';
    final String nisn = user['nisn']?.toString() ?? user['username']?.toString() ?? '-';
    final String effectiveExamTitle = examTitle ?? link['title']?.toString() ?? 'Ujian';

    final String rawStatus = (record['status'] ?? 'pending').toString().toLowerCase();
    final String? lockReason = record['lock_reason']?.toString();
    final int violationsCount = (record['violations_count'] as num?)?.toInt() ?? 0;
    final bool wasUnlocked = record['was_unlocked'] == true || record['unlocked_at'] != null;

    final bool isKicked = rawStatus == 'terminated' || lockReason == 'proctor_kick' || record['is_kicked'] == true;
    final bool isLocked = !isKicked && (record['is_locked'] == true ||
        rawStatus == 'locked' ||
        rawStatus == 'split_screen' ||
        (violationsCount > 0 && !wasUnlocked && rawStatus != 'completed' && rawStatus != 'submitted'));
    final bool isCompleted = rawStatus == 'completed' || rawStatus == 'submitted' || record['score'] != null;
    final bool isEnded = isExamEnded || rawStatus == 'ended' || rawStatus == 'expired';
    final bool isInProgress = !isKicked && !isLocked && !isCompleted && !isEnded && (rawStatus == 'in_progress' || rawStatus == 'started');

    // Resolve human-friendly status label & color
    final String statusLabel;
    final Color statusColor;
    final IconData statusIcon;

    if (isKicked) {
      statusLabel = 'DIKELUARKAN';
      statusColor = const Color(0xFFEF4444);
      statusIcon = Icons.person_off_rounded;
    } else if (isLocked) {
      statusLabel = 'TERKUNCI';
      statusColor = const Color(0xFFEF4444);
      statusIcon = Icons.lock_rounded;
    } else if (isCompleted) {
      statusLabel = 'SELESAI';
      statusColor = const Color(0xFF10B981);
      statusIcon = Icons.check_circle_rounded;
    } else if (isEnded) {
      statusLabel = 'BERAKHIR';
      statusColor = const Color(0xFF64748B);
      statusIcon = Icons.event_busy_rounded;
    } else if (isInProgress) {
      statusLabel = 'SEDANG UJIAN';
      statusColor = const Color(0xFF10B981);
      statusIcon = Icons.play_circle_fill_rounded;
    } else {
      statusLabel = 'BELUM MULAI';
      statusColor = const Color(0xFF64748B);
      statusIcon = Icons.schedule_rounded;
    }

    final int currentExtraMins = (record['extra_minutes'] as num?)?.toInt() ?? 0;

    // Authorization check: Only admin, assigned proctors, or exam creators can manage/unlock
    final bool canManageStudent = controller.isAdmin || controller.canUnlockStudentForExam(effectiveLinkId, exam: link);

    // Feature enablement conditions:
    // Buka Kunci: HANYA jika siswa sedang terkunci, ujian belum selesai, dan berwenang (pengawas/pembuat/admin)
    final bool canUnlock = !isEnded && !isCompleted && isLocked && canManageStudent;

    // Sesuaikan Waktu: Hanya jika ujian masih aktif, siswa belum selesai, belum dikeluarkan, dan berwenang
    final bool canAdjustTime = !isEnded && !isCompleted && !isKicked && canManageStudent;

    // Keluarkan Sesi: Hanya jika siswa belum dikeluarkan, belum selesai, dan berwenang
    final bool canKick = !isEnded && !isCompleted && !isKicked && canManageStudent;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 600),
      backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag Handle
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
              const SizedBox(height: 16),

              // Header: Avatar, Name, NISN & Formatted Dynamic Status Badge
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: statusColor.withValues(alpha: 0.3),
                        width: 1.2,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        studentName.isNotEmpty ? studentName[0].toUpperCase() : 'S',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          studentName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.2,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              'NISN: $nisn',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Status Pill Badge
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: statusColor.withValues(alpha: 0.28),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(statusIcon, size: 11, color: statusColor),
                                  const SizedBox(width: 4),
                                  Text(
                                    statusLabel,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: statusColor,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              Container(
                height: 1,
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
              ),
              const SizedBox(height: 8),

              // Action 1: Buka Profil & Device Siswa
              _buildActionTile(
                isDark: isDark,
                icon: Icons.person_pin_rounded,
                iconColor: const Color(0xFF8B5CF6),
                title: 'Buka Profil & Device Siswa',
                subtitle: 'Periksa detail hardware HP dan riwayat sesi lengkap',
                isEnabled: true,
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => StudentDetailScreen(
                        student: user,
                        controller: controller,
                      ),
                    ),
                  );
                },
              ),

              // Action 2: Buka Kunci Ujian (Conditional Enablement by Status & Role)
              _buildActionTile(
                isDark: isDark,
                icon: Icons.lock_open_rounded,
                iconColor: const Color(0xFF10B981),
                title: 'Buka Kunci Ujian',
                subtitle: !canManageStudent
                    ? 'Hanya pengawas atau pembuat ujian ini yang berwenang membuka kunci'
                    : canUnlock
                        ? 'Izinkan siswa melanjutkan kembali sesi ujian'
                        : isCompleted
                            ? 'Siswa sudah menyelesaikan ujian'
                            : isEnded
                                ? 'Sesi ujian telah berakhir'
                                : 'Siswa tidak dalam kondisi terkunci',
                isEnabled: canUnlock,
                disabledBadgeText: !canManageStudent ? 'TERBATAS' : (!canUnlock ? 'NONAKTIF' : null),
                onTap: canUnlock
                    ? () async {
                        Navigator.pop(ctx);
                        if (linkId != null && userId != null) {
                          final confirmed = await ConfirmUnlockDialog.show(
                            context: context,
                            studentName: studentName,
                            violationReason: lockReason,
                            examTitle: effectiveExamTitle,
                            nisn: nisn,
                            timestamp: record['locked_at']?.toString() ?? record['lock_time']?.toString() ?? record['updated_at']?.toString(),
                          );
                          if (confirmed && context.mounted) {
                            final ok = await controller.unlockStudent(linkId, userId);
                            if (context.mounted) {
                              if (ok) {
                                AppNotification.showSuccess(
                                  context,
                                  'Kunci Dibuka',
                                  subtitle: '$studentName dapat melanjutkan ujian.',
                                );
                                if (onRefresh != null) await onRefresh();
                              } else {
                                AppNotification.showError(
                                  context,
                                  'Gagal Membuka Kunci',
                                  subtitle: 'Tidak dapat membuka kunci sesi siswa. Periksa koneksi server.',
                                );
                              }
                            }
                          }
                        }
                      }
                    : null,
              ),

              // Action 3: Sesuaikan Waktu Ujian (Tambah / Potong dengan Preset & Kustom)
              _buildActionTile(
                isDark: isDark,
                icon: Icons.more_time_rounded,
                iconColor: const Color(0xFF3B82F6),
                title: 'Sesuaikan Waktu Ujian',
                subtitle: !canManageStudent
                    ? 'Hanya pengawas atau pembuat ujian ini yang berwenang'
                    : canAdjustTime
                        ? 'Tambah durasi kompensasi (+) atau potong penalti (-)'
                        : 'Ujian telah selesai / berakhir',
                isEnabled: canAdjustTime,
                disabledBadgeText: !canManageStudent ? 'TERBATAS' : (!canAdjustTime ? 'NONAKTIF' : null),
                trailingBadge: currentExtraMins != 0
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: (currentExtraMins > 0 ? const Color(0xFFF59E0B) : const Color(0xFFEF4444)).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          currentExtraMins > 0 ? '+$currentExtraMins m' : '$currentExtraMins m',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: currentExtraMins > 0 ? const Color(0xFFF59E0B) : const Color(0xFFEF4444),
                          ),
                        ),
                      )
                    : null,
                onTap: canAdjustTime
                    ? () async {
                        Navigator.pop(ctx);
                        if (linkId != null && userId != null) {
                          final deltaMinutes = await AdjustTimeDialog.show(
                            context: context,
                            studentName: studentName,
                            nisn: nisn,
                            examTitle: effectiveExamTitle,
                            currentExtraMinutes: currentExtraMins,
                          );

                          if (deltaMinutes != null && context.mounted) {
                            final ok = await controller.addExtraTime(linkId, userId, minutes: deltaMinutes);
                            if (context.mounted) {
                              if (ok) {
                                final bool isAdd = deltaMinutes > 0;
                                AppNotification.showSuccess(
                                  context,
                                  isAdd ? 'Waktu Ditambahkan' : 'Waktu Dipotong',
                                  subtitle: isAdd
                                      ? '+$deltaMinutes menit berhasil diberikan kepada $studentName.'
                                      : '$deltaMinutes menit berhasil dipotong dari sesi $studentName.',
                                );
                                if (onRefresh != null) await onRefresh();
                              } else {
                                AppNotification.showError(
                                  context,
                                  'Gagal Menyesuaikan Waktu',
                                  subtitle: 'Penyesuaian waktu ujian tidak dapat disimpan ke server.',
                                );
                              }
                            }
                          }
                        }
                      }
                    : null,
              ),

              // Action 4: Keluarkan Sesi Ujian (dengan Konfirmasi)
              _buildActionTile(
                isDark: isDark,
                icon: Icons.person_remove_rounded,
                iconColor: const Color(0xFFEF4444),
                title: 'Keluarkan Sesi Ujian',
                subtitle: !canManageStudent
                    ? 'Hanya pengawas atau pembuat ujian ini yang berwenang'
                    : canKick
                        ? 'Paksa reset sesi dan keluarkan siswa dari ujian ini'
                        : isKicked
                            ? 'Siswa sudah dikeluarkan dari ujian'
                            : isCompleted
                                ? 'Siswa sudah menyelesaikan ujian'
                                : 'Sesi ujian telah berakhir',
                isEnabled: canKick,
                disabledBadgeText: !canManageStudent ? 'TERBATAS' : (!canKick ? 'NONAKTIF' : null),
                isDanger: canKick,
                onTap: canKick
                    ? () async {
                        Navigator.pop(ctx);
                        if (linkId != null && userId != null) {
                          final confirmed = await ConfirmKickDialog.show(
                            context: context,
                            studentName: studentName,
                            nisn: nisn,
                            examTitle: effectiveExamTitle,
                          );

                          if (confirmed && context.mounted) {
                            final ok = await controller.kickStudent(linkId, userId);
                            if (context.mounted) {
                              if (ok) {
                                AppNotification.show(
                                  context,
                                  title: 'Siswa Dikeluarkan',
                                  subtitle: 'Sesi $studentName berhasil dihentikan.',
                                  type: NotificationType.warning,
                                );
                                if (onRefresh != null) await onRefresh();
                              } else {
                                AppNotification.showError(
                                  context,
                                  'Gagal Mengeluarkan Siswa',
                                  subtitle: 'Tidak dapat menghentikan sesi ujian siswa saat ini.',
                                );
                              }
                            }
                          }
                        }
                      }
                    : null,
              ),

              // Action 5: Detail & Log Audit Sesi Lengkap (Opsional jika tersedia)
              if (onOpenAuditDetail != null) ...[
                _buildActionTile(
                  isDark: isDark,
                  icon: Icons.info_outline_rounded,
                  iconColor: const Color(0xFF0EA5E9),
                  title: 'Informasi Detail & Log Audit',
                  subtitle: 'Lihat status sesi mendalam, perangkat, dan riwayat audit',
                  isEnabled: true,
                  onTap: () {
                    Navigator.pop(ctx);
                    onOpenAuditDetail();
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static Widget _buildActionTile({
    required bool isDark,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool isEnabled,
    String? disabledBadgeText,
    Widget? trailingBadge,
    bool isDanger = false,
    VoidCallback? onTap,
  }) {
    final effectiveIconColor = isEnabled
        ? iconColor
        : (isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8));
    final effectiveBgColor = isEnabled
        ? iconColor.withValues(alpha: 0.12)
        : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9));

    return Material(
      color: Colors.transparent,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        enabled: isEnabled,
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: effectiveBgColor,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: effectiveIconColor, size: 20),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.bold,
            color: isEnabled
                ? (isDanger
                    ? const Color(0xFFEF4444)
                    : (isDark ? Colors.white : const Color(0xFF0F172A)))
                : (isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8)),
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            fontSize: 11,
            color: isEnabled
                ? (isDark ? AppTheme.textSecondary : const Color(0xFF64748B))
                : (isDark ? const Color(0xFF475569) : const Color(0xFF94A3B8)),
            fontStyle: !isEnabled ? FontStyle.italic : FontStyle.normal,
          ),
        ),
        trailing: trailingBadge ??
            (disabledBadgeText != null
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: Text(
                      disabledBadgeText,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                        letterSpacing: 0.5,
                      ),
                    ),
                  )
                : null),
        onTap: isEnabled ? onTap : null,
      ),
    );
  }
}
