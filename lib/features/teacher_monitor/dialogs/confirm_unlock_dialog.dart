import 'package:flutter/material.dart';
import '../../../../shared/theme/app_theme.dart';

class ConfirmUnlockDialog extends StatelessWidget {
  final String studentName;
  final String? nisn;
  final String? violationReason;
  final String? examTitle;
  final String? deviceName;
  final String? timestamp;

  const ConfirmUnlockDialog({
    super.key,
    required this.studentName,
    this.nisn,
    this.violationReason,
    this.examTitle,
    this.deviceName,
    this.timestamp,
  });

  static Future<bool> show({
    required BuildContext context,
    required String studentName,
    String? nisn,
    String? violationReason,
    String? examTitle,
    String? deviceName,
    String? timestamp,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ConfirmUnlockDialog(
        studentName: studentName,
        nisn: nisn,
        violationReason: violationReason,
        examTitle: examTitle,
        deviceName: deviceName,
        timestamp: timestamp,
      ),
    );
    return result ?? false;
  }

  static String formatTimestamp(String? raw) {
    if (raw == null || raw.isEmpty) return '-';
    if (raw.contains('WIB')) return raw;
    try {
      final dt = DateTime.parse(raw).toLocal();
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
        'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'
      ];
      final day = dt.day;
      final month = months[dt.month - 1];
      final year = dt.year;
      final hour = dt.hour.toString().padLeft(2, '0');
      final minute = dt.minute.toString().padLeft(2, '0');
      final second = dt.second.toString().padLeft(2, '0');
      return '$day $month $year, $hour:$minute:$second WIB';
    } catch (_) {
      return raw;
    }
  }

  String _formatReason(String? reason) {
    if (reason == null || reason.isEmpty) return 'Indikasi Pelanggaran Keamanan';
    final lower = reason.toLowerCase();
    if (lower.contains('proctor_kick') || lower.contains('kicked')) {
      return 'Dikeluarkan Pengawas';
    } else if (lower.contains('split') || lower.contains('multi_window')) {
      return 'Layar Terbelah (Split Screen)';
    } else if (lower.contains('minimize')) {
      return 'Keluar dari Aplikasi (Minimize)';
    } else if (lower.contains('app_switch') || lower.contains('switch')) {
      return 'Pindah Aplikasi';
    } else if (lower.contains('screenshot') || lower.contains('capture')) {
      return 'Percobaan Screenshot Layar';
    } else if (lower.contains('phone_call') || lower.contains('call')) {
      return 'Panggilan Suara / Telepon Masuk';
    } else if (lower.contains('bluetooth')) {
      return 'Koneksi Bluetooth Aktif';
    } else if (lower.contains('external_display') || lower.contains('hdmi') || lower.contains('mirroring')) {
      return 'Layar Eksternal / HDMI';
    } else if (lower.contains('overlay') || lower.contains('floating')) {
      return 'Jendela Mengambang (Floating Window)';
    } else if (lower.contains('notification') || lower.contains('pulldown')) {
      return 'Buka Bar Notifikasi';
    }
    return reason;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFFED7AA),
          width: 1.2,
        ),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon & Title Header
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEA580C).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFFEA580C).withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Icon(
                      Icons.lock_open_rounded,
                      color: Color(0xFFEA580C),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Buka Kunci Siswa?',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Konfirmasi Izin Melanjutkan Ujian',
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
              const SizedBox(height: 16),

              // Student & Violation Details Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.person_rounded,
                          size: 15,
                          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            studentName,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                            ),
                          ),
                        ),
                        if (nisn != null && nisn!.isNotEmpty && nisn != '-')
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'NISN: $nisn',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (examTitle != null && examTitle!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.assignment_outlined,
                            size: 14,
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              examTitle!,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (violationReason != null && violationReason!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(0xFFEF4444).withValues(alpha: 0.25),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.report_problem_rounded,
                              size: 14,
                              color: Color(0xFFEF4444),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                _formatReason(violationReason),
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFEF4444),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (timestamp != null && timestamp!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.access_time_rounded,
                            size: 13.5,
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Waktu Kejadian: ${formatTimestamp(timestamp)}',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Security Warning Box
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.security_rounded,
                      size: 18,
                      color: Color(0xFFF59E0B),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Peringatan Pengawas Ujian',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFF59E0B),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Pastikan Anda telah memeriksa keadaan fisik dan layar perangkat siswa secara langsung di ruangan sebelum mengizinkan siswa melanjutkan ujian.',
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.35,
                              color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF475569),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Buttons (Adaptive Wrap prevents RenderFlex overflow on narrow/cover screens)
              Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      foregroundColor: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                    ),
                    child: const Text(
                      'Batal',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEA580C),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                    label: const Text(
                      'Ya, Buka Kunci',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
