import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_notification.dart';
import '../detail/student_detail_screen.dart';
import '../teacher_portal_controller.dart';
import 'adjust_time_dialog.dart';
import 'confirm_kick_dialog.dart';
import 'confirm_unlock_dialog.dart';

class StudentDetailModal {
  static String formatViolationReason(String? reason) {
    switch (reason) {
      case 'proctor_kick':
        return 'Dikeluarkan Pengawas';
      case 'split_screen':
        return 'Layar Terbelah';
      case 'app_switch':
      case 'app_minimize':
        return 'Pindah Aplikasi';
      case 'screenshot_attempt':
        return 'Percobaan Screenshot';
      case 'phone_call_detected':
        return 'Panggilan Suara';
      case 'bluetooth_enabled':
        return 'Bluetooth Aktif';
      case 'external_display':
        return 'Layar Eksternal';
      case 'overlay_detected':
        return 'Jendela Mengambang';
      case 'notification_pulldown':
        return 'Buka Notifikasi';
      default:
        return reason ?? 'Pelanggaran Keamanan';
    }
  }

  static void show({
    required BuildContext context,
    required TeacherPortalController controller,
    required Map<String, dynamic> item,
    dynamic examId,
    String? examTitle,
    String? defaultClassName,
    String modalType = 'participant',
    bool isExamEnded = false,
    Future<void> Function()? onRefresh,
  }) {
    final isDark = AppTheme.isDark(context);
    final user = item['user'] as Map<String, dynamic>? ?? {};
    final link = item['link'] as Map<String, dynamic>? ?? {};

    final dynamic effectiveExamId = examId ?? item['link_id'] ?? link['id'];
    final String effectiveExamTitle = examTitle ?? link['title']?.toString() ?? 'Detail Ujian';
    final String effectiveDefaultClass = defaultClassName ?? '';

    final String status = item['status']?.toString().toLowerCase() ?? 'pending';
    final String? lockReason = item['lock_reason']?.toString();
    final bool isKicked = status == 'terminated' || lockReason == 'proctor_kick' || item['is_kicked'] == true;
    final bool isLocked = !isKicked && (item['is_locked'] == true || status == 'locked' || status == 'split_screen');
    final bool isCompleted = status == 'completed' || status == 'submitted' || item['score'] != null;
    final bool isExpired = isExamEnded && !isKicked && !isLocked && !isCompleted;
    final bool canManageExam = controller.isAdmin || controller.canUnlockStudentForExam(effectiveExamId, exam: link);
    final bool canAdjustTime = !isExamEnded && !isCompleted && !isKicked && canManageExam;
    final bool wasUnlocked = item['unlocked_at'] != null ||
        item['unlocked_by'] != null ||
        (!isLocked && !isKicked && (lockReason != null && lockReason.isNotEmpty));

    final rawIncidentTime = item['occurred_at'] ??
        item['locked_at'] ??
        item['lock_time'] ??
        item['created_at'] ??
        item['updated_at'];
    String incidentTimeFormatted = 'Terekam saat sesi aktif';
    if (rawIncidentTime != null) {
      try {
        final dt = DateTime.parse(rawIncidentTime.toString()).toLocal();
        incidentTimeFormatted = '${DateFormat('d MMM yyyy, HH:mm:ss', 'id_ID').format(dt)} WIB';
      } catch (_) {
        incidentTimeFormatted = rawIncidentTime.toString();
      }
    }

    String unlockTimeFormatted = '';
    if (item['unlocked_at'] != null) {
      try {
        final uDt = DateTime.parse(item['unlocked_at'].toString()).toLocal();
        unlockTimeFormatted = '${DateFormat('d MMM yyyy, HH:mm:ss', 'id_ID').format(uDt)} WIB';
      } catch (_) {
        unlockTimeFormatted = item['unlocked_at'].toString();
      }
    }

    final studentName = user['name']?.toString() ?? 'Peserta #${item['user_id'] ?? ''}';
    final rawNisn = user['nisn']?.toString().trim();
    final rawUsername = user['username']?.toString().trim();
    final nisn = (rawNisn != null && rawNisn.isNotEmpty && rawNisn != '-')
        ? rawNisn
        : '-';
    final username = (rawUsername != null && rawUsername.isNotEmpty && rawUsername != '-')
        ? rawUsername
        : (studentName.isNotEmpty && !studentName.startsWith('Peserta #') ? studentName : 'siswa');
    final email = user['email']?.toString() ?? '';
    final userId = user['id'] ?? item['user_id'];
    final userClass = user['class_major']?['name']?.toString() ??
        user['classes']?['name']?.toString() ??
        user['class_name']?.toString() ??
        effectiveDefaultClass;
    final deviceName = user['device_name']?.toString() ?? user['device_id']?.toString() ?? user['serial_number']?.toString();
    final serial = user['serial_number']?.toString();
    final androidVersion = user['android_version']?.toString();
    final bool hasBoundDevice = (deviceName != null && deviceName.isNotEmpty) || (serial != null && serial.isNotEmpty);
    final rawBattery = item['battery_level'] ?? (item['metadata'] is Map ? item['metadata']['battery_level'] : null);
    final int? batteryLevel = rawBattery is int
        ? rawBattery
        : int.tryParse(rawBattery?.toString() ?? '');
    final dynamic rawCharging = item['is_charging'] ?? (item['metadata'] is Map ? item['metadata']['is_charging'] : null);
    final bool isCharging = rawCharging == true ||
        rawCharging == 1 ||
        rawCharging == '1' ||
        rawCharging?.toString().toLowerCase() == 'true';
    final String networkType = (item['network_type'] ?? (item['metadata'] is Map ? item['metadata']['network_type'] : null))?.toString().toLowerCase() ?? '';
    final bool isWifi = networkType == 'wifi';
    final bool isCellular = networkType == 'cellular' || networkType == 'seluler' || networkType == 'mobile';
    final String networkLabel = isWifi
        ? 'Wi-Fi'
        : isCellular
            ? 'Data Seluler'
            : (networkType.isNotEmpty ? networkType.toUpperCase() : 'Tidak Terdeteksi');

    final dynamic rawCall = item['is_on_call'] ?? (item['metadata'] is Map ? item['metadata']['is_on_call'] : null);
    final bool isOnCall = rawCall == true || rawCall == 1 || rawCall == '1' || rawCall?.toString().toLowerCase() == 'true';
    final extraMins = item['extra_minutes'] is int ? item['extra_minutes'] as int : int.tryParse(item['extra_minutes']?.toString() ?? '') ?? 0;
    final score = item['score'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 600),
      backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (modalCtx) => SafeArea(
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
              const SizedBox(height: 14),

              // Context Badge (Distinguishing Tab Peserta vs Tab Pelanggaran)
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                    decoration: BoxDecoration(
                      color: modalType == 'violation'
                          ? const Color(0xFFEF4444).withValues(alpha: 0.12)
                          : const Color(0xFF3B82F6).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: modalType == 'violation'
                            ? const Color(0xFFEF4444).withValues(alpha: 0.3)
                            : const Color(0xFF3B82F6).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          modalType == 'violation'
                              ? Icons.shield_outlined
                              : Icons.badge_outlined,
                          size: 13,
                          color: modalType == 'violation'
                              ? const Color(0xFFEF4444)
                              : const Color(0xFF3B82F6),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          modalType == 'violation'
                              ? 'AUDIT PELANGGARAN SISWA'
                              : 'DETAIL PROGRES PESERTA',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                            color: modalType == 'violation'
                                ? const Color(0xFFEF4444)
                                : const Color(0xFF3B82F6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (isExamEnded)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF64748B).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF64748B).withValues(alpha: 0.3)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.lock_clock_rounded, size: 12, color: Color(0xFF64748B)),
                          SizedBox(width: 4),
                          Text(
                            'UJIAN SELESAI',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),

              // Header Card: Avatar and Name
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: modalType == 'violation'
                          ? const Color(0xFFEF4444).withValues(alpha: 0.15)
                          : isLocked
                              ? const Color(0xFFEF4444).withValues(alpha: 0.15)
                              : isCompleted
                                  ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                  : isExpired
                                      ? const Color(0xFF64748B).withValues(alpha: 0.15)
                                      : const Color(0xFFEA580C).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: modalType == 'violation'
                          ? const Icon(Icons.security_update_warning_rounded, color: Color(0xFFEF4444), size: 24)
                          : Text(
                              studentName.isNotEmpty ? studentName[0].toUpperCase() : 'S',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                color: isLocked
                                    ? const Color(0xFFEF4444)
                                    : isCompleted
                                        ? const Color(0xFF10B981)
                                        : isExpired
                                            ? const Color(0xFF64748B)
                                            : const Color(0xFFEA580C),
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
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Modal Body: Violation Audit vs Participant Progress
              if (modalType == 'violation') ...[
                // Section 1: Catatan Temuan Pelanggaran Keamanan & Waktu Kejadian
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.35),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, size: 18, color: Color(0xFFEF4444)),
                          const SizedBox(width: 8),
                          const Text(
                            'TEMUAN PELANGGARAN KEAMANAN',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFFEF4444),
                              letterSpacing: 0.5,
                            ),
                          ),
                          const Spacer(),
                          // Real Condition Badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: isKicked
                                  ? const Color(0xFFBE123C).withValues(alpha: 0.15)
                                  : isLocked
                                      ? const Color(0xFFEF4444).withValues(alpha: 0.15)
                                      : const Color(0xFF10B981).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isKicked
                                  ? 'DIKELUARKAN'
                                  : isLocked
                                      ? (isExamEnded ? 'DIBEKUKAN' : 'TERKUNCI')
                                      : (wasUnlocked ? 'SUDAH DIBUKA' : 'BEBAS'),
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                                color: isKicked
                                    ? const Color(0xFFBE123C)
                                    : isLocked
                                        ? const Color(0xFFEF4444)
                                        : const Color(0xFF10B981),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Indikasi: ${formatViolationReason(lockReason)}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFEF4444),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Waktu Kejadian Chip
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF2D1619) : const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.access_time_filled_rounded, size: 12, color: Color(0xFFEF4444)),
                            const SizedBox(width: 5),
                            Text(
                              'Waktu Kejadian: $incidentTimeFormatted',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFEF4444),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isKicked
                            ? 'Peserta telah dikeluarkan dari sesi ujian oleh pengawas karena pelanggaran berat.'
                            : isExamEnded && isLocked
                                ? 'Sistem Shiei Kiosk mendeteksi insiden selama ujian berlangsung. Karena jadwal ujian telah selesai, status sesi telah dibekukan permanen dan diarsipkan ke laporan pengawas.'
                                : isLocked
                                    ? 'Sistem Shiei Kiosk mendeteksi aktivitas mencurigakan saat ujian berlangsung. Sesi peserta dibekukan demi integritas evaluasi dan belum dibuka oleh pengawas.'
                                    : 'Kunci sesi peserta telah dibuka kembali oleh pengawas${unlockTimeFormatted.isNotEmpty ? ' pada $unlockTimeFormatted' : ''}. Peserta diizinkan melanjutkan ujian.',
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.45,
                          color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF334155),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Section 2: Informasi Profil Siswa
                buildCompactSection(
                  title: 'Informasi Profil Siswa',
                  icon: Icons.person_outline_rounded,
                  isDark: isDark,
                  children: [
                    buildCompactRow(
                      icon: Icons.badge_outlined,
                      label: 'Nama Lengkap',
                      isDark: isDark,
                      valueWidget: Text(
                        studentName,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    buildCompactRow(
                      icon: Icons.tag_rounded,
                      label: 'NISN Siswa',
                      isDark: isDark,
                      valueWidget: Text(
                        nisn,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white70 : const Color(0xFF334155),
                        ),
                      ),
                    ),
                    buildCompactRow(
                      icon: Icons.alternate_email_rounded,
                      label: 'Akun / Username',
                      isDark: isDark,
                      valueWidget: Text(
                        '@$username',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF3B82F6),
                        ),
                      ),
                    ),
                    buildCompactRow(
                      icon: Icons.school_outlined,
                      label: 'Kelas',
                      isDark: isDark,
                      valueWidget: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Kelas $userClass',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF8B5CF6),
                          ),
                        ),
                      ),
                    ),
                    if (email.isNotEmpty && email != '-')
                      buildCompactRow(
                        icon: Icons.email_outlined,
                        label: 'Alamat Email',
                        isDark: isDark,
                        valueWidget: Text(
                          email,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.white70 : const Color(0xFF334155),
                          ),
                        ),
                      ),
                    buildCompactRow(
                      icon: Icons.phone_android_rounded,
                      label: 'Perangkat Ujian',
                      isDark: isDark,
                      valueWidget: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            hasBoundDevice ? Icons.phonelink_lock_rounded : Icons.phonelink_off_rounded,
                            size: 13,
                            color: hasBoundDevice ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            hasBoundDevice ? '${deviceName ?? serial}' : 'Belum Terikat',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: hasBoundDevice
                                  ? (isDark ? const Color(0xFF10B981) : const Color(0xFF059669))
                                  : (isDark ? AppTheme.textSecondary : const Color(0xFF94A3B8)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (androidVersion != null && androidVersion.isNotEmpty)
                      buildCompactRow(
                        icon: Icons.android_rounded,
                        label: 'Versi OS',
                        isDark: isDark,
                        valueWidget: Text(
                          androidVersion,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
                          ),
                        ),
                      ),
                    buildCompactRow(
                      icon: isCharging
                          ? Icons.battery_charging_full_rounded
                          : batteryLevel != null && batteryLevel <= 20
                              ? Icons.battery_alert_rounded
                              : Icons.battery_full_rounded,
                      label: 'Baterai HP',
                      isDark: isDark,
                      valueWidget: batteryLevel != null
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isCharging
                                    ? const Color(0xFF3B82F6).withValues(alpha: 0.12)
                                    : batteryLevel <= 20
                                        ? const Color(0xFFEF4444).withValues(alpha: 0.12)
                                        : batteryLevel <= 50
                                            ? const Color(0xFFF59E0B).withValues(alpha: 0.12)
                                            : const Color(0xFF10B981).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '$batteryLevel%${isCharging ? ' ⚡' : ''}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: isCharging
                                      ? const Color(0xFF3B82F6)
                                      : batteryLevel <= 20
                                          ? const Color(0xFFEF4444)
                                          : batteryLevel <= 50
                                              ? const Color(0xFFF59E0B)
                                              : const Color(0xFF10B981),
                                ),
                              ),
                            )
                          : Text(
                              'Tidak terbaca',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: isDark ? const Color(0xFF475569) : const Color(0xFF94A3B8),
                              ),
                            ),
                    ),
                    buildCompactRow(
                      icon: isWifi
                          ? Icons.wifi_rounded
                          : isCellular
                              ? Icons.signal_cellular_alt_rounded
                              : Icons.wifi_off_rounded,
                      label: 'Jaringan Internet',
                      isDark: isDark,
                      valueWidget: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isWifi
                              ? const Color(0xFF3B82F6).withValues(alpha: 0.12)
                              : isCellular
                                  ? const Color(0xFF8B5CF6).withValues(alpha: 0.12)
                                  : (isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9)),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          networkLabel,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isWifi
                                ? const Color(0xFF3B82F6)
                                : isCellular
                                    ? const Color(0xFF8B5CF6)
                                    : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                          ),
                        ),
                      ),
                    ),
                    buildCompactRow(
                      icon: isOnCall ? Icons.phone_in_talk_rounded : Icons.phone_disabled_rounded,
                      label: 'Status Panggilan',
                      showDivider: false,
                      isDark: isDark,
                      valueWidget: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isOnCall
                              ? const Color(0xFFEF4444).withValues(alpha: 0.15)
                              : const Color(0xFF10B981).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                          border: isOnCall
                              ? Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.4), width: 0.8)
                              : null,
                        ),
                        child: Text(
                          isOnCall ? 'SEDANG TELPONAN ⚠️' : 'Tidak Ada',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: isOnCall ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // Section 3: Informasi Status Audit & Akses Sesi
                buildCompactSection(
                  title: 'Informasi Status Audit & Sesi',
                  icon: Icons.phonelink_lock_rounded,
                  isDark: isDark,
                  children: [
                    buildCompactRow(
                      icon: Icons.security_rounded,
                      label: 'Kondisi Akses Sesi',
                      isDark: isDark,
                      valueWidget: _buildAccessConditionBadge(
                        isKicked: isKicked,
                        isExamEnded: isExamEnded,
                        isLocked: isLocked,
                        isWaiting: status == 'pending' || wasUnlocked,
                        isDark: isDark,
                      ),
                    ),
                    buildCompactRow(
                      icon: Icons.access_time_rounded,
                      label: 'Waktu Pelanggaran',
                      isDark: isDark,
                      valueWidget: Text(
                        incidentTimeFormatted,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white70 : const Color(0xFF334155),
                        ),
                      ),
                    ),
                    if (unlockTimeFormatted.isNotEmpty)
                      buildCompactRow(
                        icon: Icons.lock_open_rounded,
                        label: 'Waktu Buka Kunci',
                        isDark: isDark,
                        valueWidget: Text(
                          unlockTimeFormatted,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF10B981),
                          ),
                        ),
                      ),
                    if (score != null)
                      buildCompactRow(
                        icon: Icons.grade_rounded,
                        label: 'Skor Akhir',
                        isDark: isDark,
                        showDivider: false,
                        valueWidget: Text(
                          '$score',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                        ),
                      ),
                  ],
                ),
              ] else ...[
                // Section 1: Informasi Profil Lengkap Siswa
                buildCompactSection(
                  title: 'Informasi Profil Siswa',
                  icon: Icons.person_outline_rounded,
                  isDark: isDark,
                  children: [
                    buildCompactRow(
                      icon: Icons.badge_outlined,
                      label: 'Nama Lengkap',
                      isDark: isDark,
                      valueWidget: Text(
                        studentName,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    buildCompactRow(
                      icon: Icons.tag_rounded,
                      label: 'NISN Siswa',
                      isDark: isDark,
                      valueWidget: Text(
                        nisn,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white70 : const Color(0xFF334155),
                        ),
                      ),
                    ),
                    buildCompactRow(
                      icon: Icons.alternate_email_rounded,
                      label: 'Akun / Username',
                      isDark: isDark,
                      valueWidget: Text(
                        '@$username',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF3B82F6),
                        ),
                      ),
                    ),
                    buildCompactRow(
                      icon: Icons.school_outlined,
                      label: 'Kelas',
                      isDark: isDark,
                      valueWidget: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Kelas $userClass',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF8B5CF6),
                          ),
                        ),
                      ),
                    ),
                    if (email.isNotEmpty && email != '-')
                      buildCompactRow(
                        icon: Icons.email_outlined,
                        label: 'Alamat Email',
                        isDark: isDark,
                        valueWidget: Text(
                          email,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.white70 : const Color(0xFF334155),
                          ),
                        ),
                      ),
                    buildCompactRow(
                      icon: Icons.phone_android_rounded,
                      label: 'Perangkat Ujian',
                      isDark: isDark,
                      valueWidget: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            hasBoundDevice ? Icons.phonelink_lock_rounded : Icons.phonelink_off_rounded,
                            size: 13,
                            color: hasBoundDevice ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            hasBoundDevice ? '${deviceName ?? serial}' : 'Belum Terikat',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: hasBoundDevice
                                  ? (isDark ? const Color(0xFF10B981) : const Color(0xFF059669))
                                  : (isDark ? AppTheme.textSecondary : const Color(0xFF94A3B8)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (androidVersion != null && androidVersion.isNotEmpty)
                      buildCompactRow(
                        icon: Icons.android_rounded,
                        label: 'Versi OS',
                        isDark: isDark,
                        valueWidget: Text(
                          androidVersion,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
                          ),
                        ),
                      ),
                    buildCompactRow(
                      icon: isCharging
                          ? Icons.battery_charging_full_rounded
                          : batteryLevel != null && batteryLevel <= 20
                              ? Icons.battery_alert_rounded
                              : Icons.battery_full_rounded,
                      label: 'Baterai HP',
                      isDark: isDark,
                      valueWidget: batteryLevel != null
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isCharging
                                    ? const Color(0xFF3B82F6).withValues(alpha: 0.12)
                                    : batteryLevel <= 20
                                        ? const Color(0xFFEF4444).withValues(alpha: 0.12)
                                        : batteryLevel <= 50
                                            ? const Color(0xFFF59E0B).withValues(alpha: 0.12)
                                            : const Color(0xFF10B981).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '$batteryLevel%${isCharging ? ' ⚡' : ''}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: isCharging
                                      ? const Color(0xFF3B82F6)
                                      : batteryLevel <= 20
                                          ? const Color(0xFFEF4444)
                                          : batteryLevel <= 50
                                              ? const Color(0xFFF59E0B)
                                              : const Color(0xFF10B981),
                                ),
                              ),
                            )
                          : Text(
                              'Tidak terbaca',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: isDark ? const Color(0xFF475569) : const Color(0xFF94A3B8),
                              ),
                            ),
                    ),
                    buildCompactRow(
                      icon: isWifi
                          ? Icons.wifi_rounded
                          : isCellular
                              ? Icons.signal_cellular_alt_rounded
                              : Icons.wifi_off_rounded,
                      label: 'Jaringan Internet',
                      isDark: isDark,
                      valueWidget: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isWifi
                              ? const Color(0xFF3B82F6).withValues(alpha: 0.12)
                              : isCellular
                                  ? const Color(0xFF8B5CF6).withValues(alpha: 0.12)
                                  : (isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9)),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          networkLabel,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isWifi
                                ? const Color(0xFF3B82F6)
                                : isCellular
                                    ? const Color(0xFF8B5CF6)
                                    : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                          ),
                        ),
                      ),
                    ),
                    buildCompactRow(
                      icon: isOnCall ? Icons.phone_in_talk_rounded : Icons.phone_disabled_rounded,
                      label: 'Status Panggilan',
                      showDivider: false,
                      isDark: isDark,
                      valueWidget: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isOnCall
                              ? const Color(0xFFEF4444).withValues(alpha: 0.15)
                              : const Color(0xFF10B981).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                          border: isOnCall
                              ? Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.4), width: 0.8)
                              : null,
                        ),
                        child: Text(
                          isOnCall ? 'SEDANG TELPONAN ⚠️' : 'Tidak Ada',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: isOnCall ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),


                // Section 2: Informasi Sesi Ujian & Hasil Evaluasi
                buildCompactSection(
                  title: 'Informasi Sesi Ujian',
                  icon: Icons.access_time_rounded,
                  isDark: isDark,
                  children: [
                    buildCompactRow(
                      icon: Icons.info_outline_rounded,
                      label: 'Status Siswa',
                      isDark: isDark,
                      valueWidget: Text(
                        isLocked
                            ? 'TERKUNCI'
                            : isCompleted
                                ? (score != null ? 'SELESAI ($score)' : 'SELESAI')
                                : isKicked
                                    ? 'DIKELUARKAN'
                                    : isExpired
                                        ? 'WAKTU HABIS'
                                        : status == 'pending'
                                            ? 'MENUNGGU SISWA'
                                            : 'SEDANG UJIAN',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isLocked
                              ? const Color(0xFFEF4444)
                              : isCompleted
                                  ? const Color(0xFF10B981)
                                  : isKicked
                                      ? const Color(0xFFBE123C)
                                      : isExpired
                                          ? const Color(0xFF64748B)
                                          : status == 'pending'
                                              ? const Color(0xFFF59E0B)
                                              : const Color(0xFF10B981),
                        ),
                      ),
                    ),
                    if (score != null)
                      buildCompactRow(
                        icon: Icons.grade_rounded,
                        label: 'Nilai / Skor Akhir',
                        isDark: isDark,
                        valueWidget: Text(
                          '$score',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF10B981),
                          ),
                        ),
                      ),
                    if (extraMins != 0)
                      buildCompactRow(
                        icon: Icons.more_time_rounded,
                        label: 'Kompensasi Waktu',
                        isDark: isDark,
                        valueWidget: Text(
                          extraMins > 0 ? '+$extraMins Menit' : '$extraMins Menit',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: extraMins > 0 ? const Color(0xFFF59E0B) : const Color(0xFFEF4444),
                          ),
                        ),
                      ),
                    buildCompactRow(
                      icon: Icons.security_rounded,
                      label: 'Status Akses Sesi',
                      showDivider: false,
                      isDark: isDark,
                      valueWidget: Text(
                        isExamEnded
                            ? 'SESI BERAKHIR'
                            : isLocked
                                ? 'TERBLOKIR'
                                : (status == 'pending' || wasUnlocked)
                                    ? 'MENUNGGU SISWA'
                                    : 'DIIZINKAN',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: (isExamEnded || isLocked)
                              ? const Color(0xFFEF4444)
                              : (status == 'pending' || wasUnlocked)
                                  ? const Color(0xFFF59E0B)
                                  : const Color(0xFF10B981),
                        ),
                      ),
                    ),
                  ],
                ),

                // Catatan Pelanggaran Keamanan jika ada
                if (isLocked || (lockReason != null && lockReason.isNotEmpty)) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFEF4444)),
                            SizedBox(width: 6),
                            Text(
                              'CATATAN PELANGGARAN KEAMANAN',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFFEF4444),
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Indikasi: ${formatViolationReason(lockReason)}',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFEF4444),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Sistem mendeteksi aktivitas mencurigakan saat ujian berlangsung.',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF475569),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 18),

              // Action Buttons
              // 1. Tombol Buka Kunci (HANYA MUNCUL JIKA UJIAN BELUM SELESAI DAN SISWA TERKUNCI)
              if (!isExamEnded && isLocked && effectiveExamId != null && userId != null) ...[
                if (canManageExam) ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEA580C),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.lock_open_rounded, size: 18),
                      label: const Text(
                        'Buka Kunci Sesi Siswa',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
                      ),
                      onPressed: () async {
                        final confirmed = await ConfirmUnlockDialog.show(
                          context: context,
                          studentName: studentName,
                          nisn: nisn,
                          violationReason: lockReason,
                          examTitle: effectiveExamTitle,
                          deviceName: deviceName,
                          timestamp: incidentTimeFormatted != 'Terekam saat sesi aktif' ? incidentTimeFormatted : null,
                        );

                        if (confirmed && context.mounted) {
                          Navigator.pop(modalCtx);
                          final ok = await controller.unlockStudent(effectiveExamId, userId);
                          if (context.mounted) {
                            if (ok) {
                              AppNotification.showSuccess(
                                context,
                                'Kunci Berhasil Dibuka',
                                subtitle: '$studentName sekarang dapat melanjutkan ujian.',
                              );
                              if (onRefresh != null) await onRefresh();
                            } else {
                              AppNotification.showError(
                                context,
                                'Gagal Membuka Kunci',
                                subtitle: 'Tidak dapat membuka kunci sesi siswa. Periksa koneksi ke server.',
                              );
                            }
                          }
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                ] else ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.lock_outline_rounded,
                          size: 18,
                          color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Hanya pengawas atau pembuat ujian ini yang berwenang membuka kunci sesi.',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ],

              // 2. Tombol Tambahan Waktu & Profil Siswa
              if (!canAdjustTime) ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF8B5CF6),
                      side: const BorderSide(color: Color(0xFF8B5CF6)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                    ),
                    icon: const Icon(Icons.person_pin_rounded, size: 16),
                    label: const Text('Profil Siswa', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                    onPressed: () {
                      Navigator.pop(modalCtx);
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
                ),
              ] else ...[
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF3B82F6),
                          side: const BorderSide(color: Color(0xFF3B82F6)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        icon: const Icon(Icons.more_time_rounded, size: 16),
                        label: const Text('Atur Waktu', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        onPressed: () async {
                          if (effectiveExamId != null && userId != null) {
                            final deltaMinutes = await AdjustTimeDialog.show(
                              context: context,
                              studentName: studentName,
                              nisn: nisn,
                              examTitle: effectiveExamTitle,
                              currentExtraMinutes: extraMins,
                            );
                            if (deltaMinutes != null && context.mounted) {
                              Navigator.pop(modalCtx);
                              final ok = await controller.addExtraTime(effectiveExamId, userId, minutes: deltaMinutes);
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
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF8B5CF6),
                          side: const BorderSide(color: Color(0xFF8B5CF6)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        icon: const Icon(Icons.person_pin_rounded, size: 16),
                        label: const Text('Profil Siswa', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        onPressed: () {
                          Navigator.pop(modalCtx);
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
                    ),
                  ],
                ),
                // Tombol Keluarkan Siswa jika belum dikeluarkan
                if (!isExamEnded && !isCompleted && !isKicked && effectiveExamId != null && userId != null) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFEF4444),
                        side: BorderSide(color: const Color(0xFFEF4444).withValues(alpha: 0.5)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      icon: const Icon(Icons.person_remove_rounded, size: 16),
                      label: const Text('Keluarkan Siswa dari Ujian', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      onPressed: () async {
                        final confirmed = await ConfirmKickDialog.show(
                          context: context,
                          studentName: studentName,
                          nisn: nisn,
                          examTitle: effectiveExamTitle,
                        );
                        if (confirmed && context.mounted) {
                          Navigator.pop(modalCtx);
                          final ok = await controller.kickStudent(effectiveExamId, userId);
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
                                subtitle: 'Terjadi kesalahan saat mengakhiri sesi ujian siswa.',
                              );
                            }
                          }
                        }
                      },
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  static Widget buildStatPill(String text, Color color, bool isDark) {
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  static Widget buildCompactSection({
    required String title,
    required IconData icon,
    required bool isDark,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Row(
            children: [
              Icon(icon, size: 14, color: const Color(0xFFEA580C)),
              const SizedBox(width: 6),
              Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: isDark ? AppTheme.surfaceDark : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Column(
              children: children,
            ),
          ),
        ),
      ],
    );
  }

  static Widget buildCompactRow({
    required IconData icon,
    required String label,
    required Widget valueWidget,
    required bool isDark,
    bool showDivider = true,
    VoidCallback? onTap,
  }) {
    final rowContent = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11.5),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(5.5),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                width: 0.8,
              ),
            ),
            child: Icon(
              icon,
              size: 14,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: valueWidget,
            ),
          ),
        ],
      ),
    );

    return Column(
      children: [
        if (onTap != null)
          InkWell(onTap: onTap, child: rowContent)
        else
          rowContent,
        if (showDivider)
          Divider(
            height: 1,
            thickness: 1,
            color: isDark ? const Color(0xFF27354A) : const Color(0xFFF1F5F9),
            indent: 48,
          ),
      ],
    );
  }

  static Widget _buildAccessConditionBadge({
    required bool isKicked,
    required bool isExamEnded,
    required bool isLocked,
    bool isWaiting = false,
    required bool isDark,
  }) {
    final String label;
    final IconData icon;
    final Color color;

    if (isKicked) {
      label = 'Dikeluarkan';
      icon = Icons.person_off_rounded;
      color = const Color(0xFFBE123C);
    } else if (isExamEnded) {
      if (isLocked) {
        label = 'Sesi Berakhir';
        icon = Icons.lock_clock_rounded;
        color = const Color(0xFF64748B);
      } else {
        label = 'Selesai';
        icon = Icons.check_circle_outline_rounded;
        color = const Color(0xFF10B981);
      }
    } else if (isLocked) {
      label = 'Terkunci';
      icon = Icons.lock_rounded;
      color = const Color(0xFFEF4444);
    } else if (isWaiting) {
      label = 'Menunggu Siswa';
      icon = Icons.hourglass_top_rounded;
      color = const Color(0xFFF59E0B);
    } else {
      label = 'Akses Terbuka';
      icon = Icons.lock_open_rounded;
      color = const Color(0xFF10B981);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.18 : 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: color.withValues(alpha: 0.35),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4.5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.2,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

