import 'package:flutter/material.dart';
import '../../../config/app_config.dart';
import '../../../config/routes.dart';
import '../../../shared/dialogs/change_password_dialog.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/shiei_skeleton.dart';
import '../../tour/proctor_tour_dialog.dart';
import '../teacher_portal_controller.dart';

class ProctorProfileTab extends StatelessWidget {
  final TeacherPortalController controller;
  final VoidCallback? onLogout;
  final ProctorTourTargetKeys? tourKeys;
  final VoidCallback? onOpenTour;


  const ProctorProfileTab({
    super.key,
    required this.controller,
    this.onLogout,
    this.tourKeys,
    this.onOpenTour,
  });

  void _confirmLogout(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppTheme.surfaceDark : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
        ),
        title: const Text(
          'Keluar dari Portal?',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: Text(
          'Apakah Anda yakin ingin keluar dari sesi pengawas ujian sekolah?',
          style: TextStyle(
            fontSize: 12.5,
            color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Batal',
              style: TextStyle(color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await controller.logout();
              if (context.mounted) {
                Navigator.of(context).pushReplacementNamed(AppRoutes.login);
              }
            },
            child: const Text('Keluar Akun'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final user = controller.currentUser ?? {};
    final school = controller.school ?? {};
    final userName = user['name']?.toString() ?? 'Pengawas Ujian';
    final userIdentifier = user['nip']?.toString() ?? user['username']?.toString() ?? user['email']?.toString() ?? '-';
    final schoolName = school['name']?.toString() ?? user['school']?['name']?.toString() ?? 'Sekolah Terdaftar';
    final roleName = controller.isAdmin ? 'Administrator Ujian Sekolah' : 'Pengawas Ujian Resmi';

    if (controller.isLoading || controller.isProfileLoading) {
      return RefreshIndicator(
        color: AppTheme.primaryShiei,
        onRefresh: () => controller.refreshProfile(clearPrevious: true),
        child: const ProctorProfileSkeleton(),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return RefreshIndicator(
          color: AppTheme.primaryShiei,
          onRefresh: () => controller.refreshProfile(clearPrevious: true),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
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
        // 1. Official Proctor ID Badge Card
        Container(
          key: tourKeys?.proctorBadgeKey,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
                  : [Colors.white, const Color(0xFFFAFAFA)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: isDark ? Colors.black38 : Colors.black.withOpacity(0.04),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              // Card Top Ribbon
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A).withOpacity(0.8) : const Color(0xFFF8FAFC),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(19)),
                  border: Border(
                    bottom: BorderSide(
                      color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.verified_user_rounded, color: Color(0xFFEA580C), size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'KARTU TANDA PENGAWAS',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: isDark ? Colors.white70 : const Color(0xFF475569),
                      ),
                    ),
                  ],
                ),
              ),

              // Card Body
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFF97316), Color(0xFFEA580C)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFF97316).withValues(alpha: 0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(Icons.person_rounded, color: Colors.white, size: 30),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
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
                          Text(
                            roleName,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFEA580C),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'NIP / ID: $userIdentifier',
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
              ),

              // Card Footer: Institution Strip (Clean integration without nested double border)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0B1120).withValues(alpha: 0.5) : const Color(0xFFF8FAFC),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(19)),
                  border: Border(
                    top: BorderSide(
                      color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.school_rounded, color: Color(0xFFEA580C), size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'Instansi:',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        schoolName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),



        // 2. Pengaturan Akun & Preferensi (Grouped Bento Surface)
        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'PENGATURAN & PREFERENSI',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: isDark ? AppTheme.surfaceDark : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            children: [
              // Ubah Kata Sandi
              Material(
                color: Colors.transparent,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(17)),
                child: InkWell(
                  onTap: () => ChangePasswordDialog.show(context),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(17)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEA580C).withValues(alpha: isDark ? 0.2 : 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.lock_reset_rounded, color: Color(0xFFEA580C), size: 19),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Ubah Kata Sandi',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                'Perbarui kata sandi login akun pengawas',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: isDark ? AppTheme.textSecondary : const Color(0xFF94A3B8),
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Divider(height: 1, indent: 62, color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9)),

              // Alarm Suara Kecurangan
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withValues(alpha: isDark ? 0.2 : 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        controller.fraudAlertEnabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                        color: const Color(0xFFEF4444),
                        size: 19,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Alarm Suara Kecurangan',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            'Sirine audio saat ada siswa melanggar',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                            ),
                          ),
                          if (controller.fraudAlertEnabled)
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => controller.testFraudSound(),
                              child: Container(
                                margin: const EdgeInsets.only(top: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEF4444).withValues(alpha: isDark ? 0.2 : 0.08),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: const Color(0xFFEF4444).withValues(alpha: 0.25),
                                  ),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.play_arrow_rounded, size: 13, color: Color(0xFFEF4444)),
                                    SizedBox(width: 3),
                                    Text(
                                      'Uji Coba Sirine',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFFEF4444),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Switch.adaptive(
                      value: controller.fraudAlertEnabled,
                      activeTrackColor: const Color(0xFFEA580C),
                      onChanged: (val) => controller.setFraudAlertSound(val),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, indent: 62, color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9)),

              // Pengaturan & Info Aplikasi
              Material(
                color: Colors.transparent,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(17)),
                child: InkWell(
                  onTap: () => Navigator.of(context).pushNamed(AppRoutes.settings),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(17)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: const Color(0xFF64748B).withValues(alpha: isDark ? 0.2 : 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.tune_rounded, color: Color(0xFF64748B), size: 19),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Pengaturan & Info Aplikasi',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                'Versi aplikasi, cache data, dan preferensi umum',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: isDark ? AppTheme.textSecondary : const Color(0xFF94A3B8),
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // 3. Server Status & License Card (Only if Admin, strictly hidden for Teachers)
        if (controller.isAdmin && !controller.isTeacher)
          Container(
            key: tourKeys?.adminLicenseKey,
            margin: const EdgeInsets.only(top: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 8),
                  child: Text(
                    'SISTEM & LISENSI SERVER',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                    ),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: isDark ? AppTheme.surfaceDark : Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: const Color(0xFF3B82F6).withValues(alpha: isDark ? 0.2 : 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.dns_rounded, color: Color(0xFF3B82F6), size: 19),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'URL Backend Shiei Core',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    AppConfig.baseUrl,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 11,
                                      color: Color(0xFFF97316),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'TERHUBUNG',
                                style: TextStyle(
                                  color: Color(0xFF10B981),
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (controller.school != null) ...[
                        Divider(height: 1, indent: 62, color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Tier Lisensi Sekolah',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                                ),
                              ),
                              Text(
                                controller.school!['tier']?.toString().toUpperCase() ?? 'STANDARD',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                        Divider(height: 1, indent: 14, color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Batas Kuota Siswa',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                                ),
                              ),
                              Text(
                                '${controller.school!['max_students'] ?? 0} Siswa',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
                  ],
                ),

                // 4. Action Buttons Pinned at Bottom
                Padding(
                  padding: const EdgeInsets.only(top: 24, bottom: 8),
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFEF4444),
                      backgroundColor: const Color(0xFFEF4444).withValues(alpha: isDark ? 0.12 : 0.06),
                      side: BorderSide(
                        color: const Color(0xFFEF4444).withValues(alpha: isDark ? 0.35 : 0.25),
                        width: 1.2,
                      ),
                      minimumSize: const Size(double.infinity, 46),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () => onLogout != null ? onLogout!() : _confirmLogout(context),
                    icon: const Icon(Icons.logout_rounded, size: 18),
                    label: const Text(
                      'Keluar dari Portal Pengawas',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
}
