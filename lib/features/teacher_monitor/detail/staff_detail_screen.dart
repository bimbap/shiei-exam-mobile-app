import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_notification.dart';
import '../../../../shared/widgets/shiei_select_sheet.dart';
import '../dialogs/confirm_delete_dialog.dart';
import '../dialogs/user_form_dialog.dart';
import '../teacher_portal_controller.dart';
import 'class_detail_screen.dart';
import 'exam_detail_screen.dart';

class StaffDetailScreen extends StatefulWidget {
  final Map<String, dynamic> staff;
  final TeacherPortalController controller;

  const StaffDetailScreen({
    super.key,
    required this.staff,
    required this.controller,
  });

  @override
  State<StaffDetailScreen> createState() => _StaffDetailScreenState();
}

class _StaffDetailScreenState extends State<StaffDetailScreen> {
  late Map<String, dynamic> _currentStaff;

  @override
  void initState() {
    super.initState();
    _currentStaff = Map<String, dynamic>.from(widget.staff);
    widget.controller.loadExams();
    widget.controller.loadClasses();
  }

  void _syncFromController() {
    final staffId = _currentStaff['id'];
    if (staffId == null) return;

    // Check in teachers list
    final teacherMatch = widget.controller.teachers.firstWhere(
      (t) => t['id'] == staffId,
      orElse: () => <String, dynamic>{},
    );
    if (teacherMatch.isNotEmpty) {
      setState(() {
        _currentStaff = Map<String, dynamic>.from(teacherMatch);
      });
      return;
    }

    // Check in allUsers list
    final userMatch = widget.controller.allUsers.firstWhere(
      (u) => u['id'] == staffId,
      orElse: () => <String, dynamic>{},
    );
    if (userMatch.isNotEmpty) {
      setState(() {
        _currentStaff = Map<String, dynamic>.from(userMatch);
      });
    }
  }

  void _copyToClipboard(String text, String title, String subtitle) {
    Clipboard.setData(ClipboardData(text: text));
    AppNotification.showSuccess(
      context,
      title,
      subtitle: subtitle,
    );
  }

  Future<void> _openClassAssignSheet(BuildContext context, bool isDark) async {
    final staffId = _currentStaff['id'];
    if (staffId == null) return;

    // Find currently assigned class
    final availableClasses = widget.controller.classes;
    final currentAssigned = availableClasses.firstWhere(
      (c) => c['teacher_id']?.toString() == staffId.toString() ||
             _currentStaff['class_major']?['id']?.toString() == c['id']?.toString(),
      orElse: () => <String, dynamic>{},
    );
    final currentClassId = currentAssigned['id'] as int?;

    final selectedClassId = await ShieiSelectSheet.show<int?>(
      context: context,
      title: 'Tugaskan Sebagai Wali Kelas',
      subtitle: 'Pilih kelas yang akan dibina oleh ${_currentStaff['name'] ?? 'guru ini'}',
      selectedValue: currentClassId,
      items: [
        const ShieiSelectItem<int?>(
          value: null,
          label: 'Lepaskan Tugas Wali Kelas (Non-Aktif)',
          subtitle: 'Guru hanya mengajar dan tidak membina kelas',
          icon: Icons.link_off_rounded,
        ),
        ...availableClasses.map((c) {
          final cId = c['id'] as int?;
          final isSame = cId == currentClassId;
          final existingTeacher = c['teacher']?['name']?.toString() ??
              c['teacher_name']?.toString();
          return ShieiSelectItem<int?>(
            value: cId,
            label: c['name']?.toString() ?? 'Kelas',
            subtitle: isSame
                ? 'Sedang Ditugaskan ke Guru Ini'
                : (existingTeacher != null
                    ? 'Wali Kelas Saat Ini: $existingTeacher'
                    : 'Belum Ada Wali Kelas'),
            icon: Icons.meeting_room_outlined,
          );
        }),
      ],
    );

    if (selectedClassId != null || currentClassId != null) {
      final targetId = selectedClassId;
      String? err;

      if (targetId == null && currentClassId != null) {
        // Disconnect
        err = await widget.controller.assignClassTeacher(currentClassId, null);
      } else if (targetId != null) {
        // Disconnect old class if any
        if (currentClassId != null && currentClassId != targetId) {
          await widget.controller.assignClassTeacher(currentClassId, null);
        }
        err = await widget.controller.assignClassTeacher(targetId, staffId);
      }

      if (!mounted) return;
      if (err == null) {
        _syncFromController();
        AppNotification.showSuccess(
          this.context,
          'Penugasan Wali Kelas Diperbarui',
          subtitle: targetId != null
              ? 'Guru berhasil ditugaskan sebagai Wali Kelas.'
              : 'Penugasan Wali Kelas berhasil dilepas.',
        );
      } else {
        AppNotification.showError(
          this.context,
          'Gagal Mengatur Wali Kelas',
          subtitle: err,
        );
      }
    }
  }

  Future<void> _confirmUnlinkClass(Map<String, dynamic> assignedClass) async {
    final isDark = AppTheme.isDark(context);
    final className = assignedClass['name'] ?? 'ini';
    final classId = assignedClass['id'] as int?;
    if (classId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppTheme.surfaceDark : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.link_off_rounded, color: AppTheme.dangerRed, size: 24),
            SizedBox(width: 10),
            Text('Lepas Wali Kelas', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Text(
          'Apakah Anda yakin ingin melepas penugasan wali kelas untuk Kelas $className dari guru ini?',
          style: TextStyle(
            fontSize: 13,
            color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Batal',
              style: TextStyle(color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.dangerRed,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Lepas Penugasan'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final err = await widget.controller.assignClassTeacher(classId, null);
      if (!mounted) return;
      if (err == null) {
        _syncFromController();
        AppNotification.showSuccess(
          context,
          'Wali Kelas Dilepas',
          subtitle: 'Penugasan wali kelas untuk Kelas $className berhasil dilepas.',
        );
      } else {
        AppNotification.showError(
          context,
          'Gagal Melepas Wali Kelas',
          subtitle: err,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final staffId = _currentStaff['id'];
    final name = _currentStaff['name']?.toString() ?? 'Profil Staf';
    final nip = _currentStaff['nip']?.toString().trim();
    final hasNip = nip != null && nip.isNotEmpty && nip != '-';
    final rawUsername = _currentStaff['username']?.toString().trim();
    final username = (rawUsername != null && rawUsername.isNotEmpty && rawUsername != '-')
        ? rawUsername
        : (name.isNotEmpty && name != 'Profil Staf' ? name : '-');
    final email = _currentStaff['email']?.toString() ?? '';
    final role = _currentStaff['role']?.toString().toLowerCase() ?? 'teacher';
    final isAdmin = role == 'school_admin' || role == 'super_admin';
    final subRole = _currentStaff['sub_role']?.toString() ?? (isAdmin ? 'admin' : 'guru');
    final isSelf = widget.controller.currentUser?['id']?.toString() == staffId?.toString();

    // Determine sub-role styling
    String roleBadgeTitle;
    Color themeColor;
    IconData roleIcon;

    if (isAdmin) {
      roleBadgeTitle = 'Administrator Sekolah';
      themeColor = const Color(0xFFF59E0B);
      roleIcon = Icons.admin_panel_settings_rounded;
    } else {
      switch (subRole.toLowerCase()) {
        case 'kepala_sekolah':
          roleBadgeTitle = 'Kepala Sekolah';
          themeColor = const Color(0xFF6366F1);
          roleIcon = Icons.military_tech_rounded;
          break;
        case 'wakil_kepala_sekolah':
          roleBadgeTitle = 'Wakil Kepala Sekolah';
          themeColor = const Color(0xFF3B82F6);
          roleIcon = Icons.supervisor_account_rounded;
          break;
        case 'karyawan':
          roleBadgeTitle = 'Karyawan / Staf TU';
          themeColor = const Color(0xFFF97316);
          roleIcon = Icons.work_outline_rounded;
          break;
        default:
          roleBadgeTitle = 'Guru Pengajar';
          themeColor = const Color(0xFF10B981);
          roleIcon = Icons.school_rounded;
      }
    }

    // Check assigned homeroom class (Wali Kelas)
    Map<String, dynamic>? assignedClass;
    for (final c in widget.controller.classes) {
      if (c['teacher_id']?.toString() == staffId?.toString() ||
          _currentStaff['class_major']?['id']?.toString() == c['id']?.toString()) {
        assignedClass = c;
        break;
      }
    }
    final assignedClassName = assignedClass?['name']?.toString() ??
        _currentStaff['class_major']?['name']?.toString();

    // Filter proctored & created exams for this teacher
    final proctoredExams = widget.controller.exams.where((e) {
      if (isAdmin) return false; // Admin oversees everything
      final createdById = (e['created_by'] ?? e['creator_id'] ?? e['creator']?['id'])?.toString();
      final isCreator = createdById != null && createdById == staffId?.toString();

      bool isProctor = false;
      final proctors = e['proctors'];
      if (proctors is List) {
        isProctor = proctors.any((p) {
          if (p is Map) {
            final uid = (p['user_id'] ?? p['id'] ?? p['user']?['id'])?.toString();
            return uid == staffId?.toString();
          }
          return p?.toString() == staffId?.toString();
        });
      }
      return isCreator || isProctor;
    }).toList();

    // Formatted join date
    String joinDateFormatted = '-';
    if (_currentStaff['created_at'] != null) {
      try {
        final dt = DateTime.parse(_currentStaff['created_at'].toString()).toLocal();
        joinDateFormatted = DateFormat('d MMMM yyyy', 'id_ID').format(dt);
      } catch (_) {
        joinDateFormatted = _currentStaff['created_at'].toString();
      }
    }

    final schoolName = widget.controller.school?['name']?.toString() ?? 'SMK Negeri 10 Surabaya';

    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(
        title: Text(
          isAdmin ? 'Detail Administrator' : 'Detail Guru & Staf',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Segarkan Data',
            onPressed: () async {
              await widget.controller.loadTeachers();
              await widget.controller.loadAllUsers();
              await widget.controller.loadClasses();
              await widget.controller.loadExams();
              if (mounted) {
                _syncFromController();
                AppNotification.showSuccess(
                  this.context,
                  'Data Disinkronkan',
                  subtitle: 'Informasi akun berhasil diperbarui.',
                );
              }
            },
          ),
          if (widget.controller.isAdmin) ...[
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit Profil',
              onPressed: () async {
                final res = await UserFormDialog.show(
                  context: context,
                  userData: _currentStaff,
                  initialRole: role,
                  controller: widget.controller,
                );
                if (res == true && mounted) {
                  _syncFromController();
                }
              },
            ),
            if (!isSelf)
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444)),
                tooltip: 'Hapus Akun',
                onPressed: () async {
                  final deleted = await ConfirmDeleteDialog.show(
                    context: context,
                    title: isAdmin ? 'Hapus Akun Administrator?' : 'Hapus Akun Guru & Staf?',
                    itemType: 'Nama Akun',
                    itemName: name,
                    message: 'Akun ini beserta seluruh data penugasan terkait akan dihapus secara permanen dari server sekolah.',
                    onConfirm: () => widget.controller.deleteUser(_currentStaff['id']),
                  );
                  if (!context.mounted) return;
                  if (deleted == true) {
                    Navigator.of(context).pop();
                  }
                },
              ),
          ],
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
        children: [
          // 1. Top Context / Identification Badge
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                decoration: BoxDecoration(
                  color: themeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: themeColor.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(roleIcon, size: 13, color: themeColor),
                    const SizedBox(width: 5),
                    Text(
                      isAdmin ? 'PROFIL ADMINISTRATOR SEKOLAH' : 'PROFIL GURU & TENAGA PENDIDIK',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: themeColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 2. Profile Avatar & Name Header Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.surfaceDark : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: themeColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: themeColor.withValues(alpha: 0.25)),
                  ),
                  child: Center(
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : (isAdmin ? 'A' : 'G'),
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: themeColor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: themeColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(roleIcon, size: 11, color: themeColor),
                                const SizedBox(width: 4),
                                Text(
                                  roleBadgeTitle,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                    color: themeColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (assignedClassName != null && assignedClassName.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                              decoration: BoxDecoration(
                                color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.meeting_room_outlined, size: 11, color: Color(0xFF3B82F6)),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Wali Kelas $assignedClassName',
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF3B82F6),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (isSelf)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.person_rounded, size: 11, color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
                                  const SizedBox(width: 3),
                                  Text(
                                    'Akun Anda',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
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
          ),
          const SizedBox(height: 18),

          // 3. Section: Informasi Identitas & Kontak Kepegawaian
          _buildCompactSection(
            title: 'Informasi Identitas & Kontak',
            icon: Icons.badge_outlined,
            isDark: isDark,
            children: [
              _buildCompactRow(
                icon: Icons.person_outline_rounded,
                label: 'Nama Lengkap',
                isDark: isDark,
                valueWidget: Text(
                  name,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
              ),
              _buildCompactRow(
                icon: Icons.credit_card_rounded,
                label: 'NIP Pegawai',
                isDark: isDark,
                onTap: hasNip
                    ? () => _copyToClipboard(nip, 'NIP Disalin', 'NIP $nip disimpan ke clipboard.')
                    : null,
                valueWidget: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      hasNip ? nip : 'Belum Ditentukan',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: hasNip
                            ? (isDark ? Colors.white70 : const Color(0xFF334155))
                            : (isDark ? AppTheme.textSecondary : const Color(0xFF94A3B8)),
                      ),
                    ),
                    if (hasNip) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.copy_rounded, size: 12, color: themeColor),
                    ],
                  ],
                ),
              ),
              _buildCompactRow(
                icon: Icons.alternate_email_rounded,
                label: 'Akun / Nama Pengguna',
                isDark: isDark,
                onTap: () => _copyToClipboard('@$username', 'Nama Pengguna Disalin', 'Nama pengguna @$username disimpan ke papan klip.'),
                valueWidget: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '@$username',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF3B82F6),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.copy_rounded, size: 12, color: Color(0xFF3B82F6)),
                  ],
                ),
              ),
              _buildCompactRow(
                icon: Icons.email_outlined,
                label: 'Alamat Email',
                isDark: isDark,
                onTap: (email.isNotEmpty && email != '-')
                    ? () => _copyToClipboard(email, 'Email Disalin', email)
                    : null,
                valueWidget: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      (email.isNotEmpty && email != '-') ? email : 'Tidak Ada Email',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: (email.isNotEmpty && email != '-')
                            ? (isDark ? Colors.white70 : const Color(0xFF334155))
                            : (isDark ? AppTheme.textSecondary : const Color(0xFF94A3B8)),
                      ),
                    ),
                    if (email.isNotEmpty && email != '-') ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.copy_rounded, size: 12, color: Color(0xFF64748B)),
                    ],
                  ],
                ),
              ),
              _buildCompactRow(
                icon: Icons.apartment_rounded,
                label: 'Sekolah Induk',
                isDark: isDark,
                valueWidget: Text(
                  schoolName,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : const Color(0xFF334155),
                  ),
                ),
              ),
              _buildCompactRow(
                icon: Icons.calendar_today_rounded,
                label: 'Terdaftar Sejak',
                showDivider: false,
                isDark: isDark,
                valueWidget: Text(
                  joinDateFormatted,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white70 : const Color(0xFF334155),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // 4. Role-Specific Section: Wali Kelas (For Teacher) OR Otoritas Sistem (For Admin)
          if (!isAdmin) ...[
            // Teacher: Homeroom Class Assignment
            _buildCompactSection(
              title: 'Tugas Pembinaan Kelas (Wali Kelas)',
              icon: Icons.meeting_room_outlined,
              isDark: isDark,
              children: [
                if (assignedClass != null) ...[
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.school_rounded, color: Color(0xFF3B82F6), size: 22),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        'Kelas ${assignedClass['name'] ?? assignedClassName}',
                                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Text(
                                          'WALI KELAS AKTIF',
                                          style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Builder(
                                    builder: (_) {
                                      final enrolledCount = widget.controller.students.where((s) {
                                        final sCid = s['class_major_id'] ?? s['class_id'] ?? s['class_major']?['id'];
                                        return sCid?.toString() == assignedClass?['id']?.toString();
                                      }).length;
                                      return Text(
                                        'Membina $enrolledCount Siswa terdaftar pada kelas ini',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  side: BorderSide(color: const Color(0xFF3B82F6).withValues(alpha: 0.5)),
                                  foregroundColor: const Color(0xFF3B82F6),
                                ),
                                icon: const Icon(Icons.open_in_new_rounded, size: 15),
                                label: const Text('Buka Detail Kelas', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => ClassDetailScreen(
                                        classData: assignedClass!,
                                        controller: widget.controller,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            if (widget.controller.isAdmin) ...[
                              const SizedBox(width: 8),
                              IconButton(
                                style: IconButton.styleFrom(
                                  backgroundColor: isDark
                                      ? const Color(0xFF450A0A).withValues(alpha: 0.5)
                                      : const Color(0xFFFEE2E2),
                                  padding: const EdgeInsets.all(10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                icon: const Icon(Icons.link_off_rounded, size: 18, color: AppTheme.dangerRed),
                                tooltip: 'Lepaskan Wali Kelas',
                                onPressed: () => _confirmUnlinkClass(assignedClass!),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)).withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.meeting_room_outlined,
                                size: 20,
                                color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Belum Ditugaskan Sebagai Wali Kelas',
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Guru ini saat ini fokus sebagai tenaga pengajar / pengawas ujian.',
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
                        if (widget.controller.isAdmin) ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 9),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                side: BorderSide(color: const Color(0xFF10B981).withValues(alpha: 0.6)),
                                foregroundColor: const Color(0xFF10B981),
                              ),
                              icon: const Icon(Icons.add_link_rounded, size: 16),
                              label: const Text('Tugaskan Sebagai Wali Kelas', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              onPressed: () => _openClassAssignSheet(context, isDark),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 18),

            // Teacher: Proctored & Created Exams (Penugasan Ujian)
            _buildCompactSection(
              title: 'Penugasan Ujian (Pengawas & Pembuat)',
              icon: Icons.assignment_outlined,
              isDark: isDark,
              children: [
                if (proctoredExams.isNotEmpty) ...[
                  ...proctoredExams.map((exam) {
                    final isLast = exam == proctoredExams.last;
                    final title = exam['title']?.toString() ?? 'Ujian';
                    final subject = exam['subject']?.toString() ?? exam['code']?.toString() ?? 'Umum';
                    final status = exam['status']?.toString().toLowerCase() ?? 'active';
                    final isActive = exam['is_active'] ?? (status == 'active');

                    final isCreator = (exam['created_by'] ?? exam['creator_id'] ?? exam['creator']?['id'])?.toString() == staffId?.toString();
                    bool isProctor = false;
                    final proctors = exam['proctors'];
                    if (proctors is List) {
                      isProctor = proctors.any((p) {
                        if (p is Map) {
                          final uid = (p['user_id'] ?? p['id'] ?? p['user']?['id'])?.toString();
                          return uid == staffId?.toString();
                        }
                        return p?.toString() == staffId?.toString();
                      });
                    }

                    return Column(
                      children: [
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                          leading: Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: (isActive ? const Color(0xFF10B981) : const Color(0xFF64748B)).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.fact_check_outlined,
                              size: 19,
                              color: isActive ? const Color(0xFF10B981) : const Color(0xFF64748B),
                            ),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isCreator) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF6366F1).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'PEMBUAT UJIAN',
                                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF6366F1)),
                                  ),
                                ),
                              ],
                              if (isProctor) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'PENGAWAS',
                                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          subtitle: Text(
                            'Mapel: $subject • ${isActive ? 'Aktif' : 'Selesai'}',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                            ),
                          ),
                          trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 13, color: Color(0xFF94A3B8)),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ExamDetailScreen(
                                  exam: exam,
                                  controller: widget.controller,
                                ),
                              ),
                            );
                          },
                        ),
                        if (!isLast)
                          Divider(
                            height: 1,
                            thickness: 1,
                            color: isDark ? const Color(0xFF27354A) : const Color(0xFFF1F5F9),
                            indent: 52,
                          ),
                      ],
                    );
                  }),
                ] else ...[
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Icon(Icons.event_busy_rounded, size: 18, color: isDark ? AppTheme.textSecondary : const Color(0xFF94A3B8)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Belum ada penugasan mengawas atau pembuatan ujian aktif.',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ] else ...[
            // Admin: System Authority & Privileges
            _buildCompactSection(
              title: 'Hak Akses & Otoritas Sistem',
              icon: Icons.security_rounded,
              isDark: isDark,
              children: [
                _buildAuthorityItem(
                  icon: Icons.lock_reset_rounded,
                  color: const Color(0xFF8B5CF6),
                  title: 'Manajemen Ujian & Token Keamanan',
                  desc: 'Rotasi dynamic token kiosk, reset darurat, dan supervisi anti-curang.',
                  isDark: isDark,
                ),
                _buildAuthorityItem(
                  icon: Icons.phonelink_lock_rounded,
                  color: const Color(0xFF3B82F6),
                  title: 'Binding Perangkat & Hardware Kiosk',
                  desc: 'Membuka kunci HP siswa, reset serial binding, dan proteksi multi-device.',
                  isDark: isDark,
                ),
                _buildAuthorityItem(
                  icon: Icons.school_rounded,
                  color: const Color(0xFF10B981),
                  title: 'Pengelolaan Siswa, Guru & Kelas',
                  desc: 'Membuat akun, mutasi kelas siswa, dan penugasan Wali Kelas.',
                  isDark: isDark,
                ),
                _buildAuthorityItem(
                  icon: Icons.verified_user_rounded,
                  color: const Color(0xFFF59E0B),
                  title: 'Konfigurasi Lisensi Sekolah SHIEI',
                  desc: 'Supervisi hak cipta, sinkronisasi offline-first, dan lisensi instansi.',
                  isDark: isDark,
                  showDivider: false,
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Admin: Quick School Statistics Overview
            _buildCompactSection(
              title: 'Ringkasan Data Sekolah Saat Ini',
              icon: Icons.analytics_outlined,
              isDark: isDark,
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildMiniStat(
                          label: 'Total Siswa',
                          value: '${widget.controller.students.length}',
                          color: const Color(0xFF8B5CF6),
                          icon: Icons.people_outline_rounded,
                          isDark: isDark,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildMiniStat(
                          label: 'Guru & Staf',
                          value: '${widget.controller.teachers.length}',
                          color: const Color(0xFF10B981),
                          icon: Icons.badge_outlined,
                          isDark: isDark,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildMiniStat(
                          label: 'Kelas',
                          value: '${widget.controller.classes.length}',
                          color: const Color(0xFF3B82F6),
                          icon: Icons.meeting_room_outlined,
                          isDark: isDark,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildMiniStat(
                          label: 'Ujian Aktif',
                          value: '${widget.controller.activeExams.length}',
                          color: const Color(0xFFF59E0B),
                          icon: Icons.fact_check_outlined,
                          isDark: isDark,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 24),

          // 5. Bottom Action Buttons
          if (widget.controller.isAdmin) ...[
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: themeColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: Text(
                      isAdmin ? 'Edit Akun Admin' : 'Edit Profil Guru',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    onPressed: () async {
                      final res = await UserFormDialog.show(
                        context: context,
                        userData: _currentStaff,
                        initialRole: role,
                        controller: widget.controller,
                      );
                      if (res == true && mounted) {
                        _syncFromController();
                      }
                    },
                  ),
                ),
                if (!isSelf) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFEF4444),
                        side: const BorderSide(color: Color(0xFFEF4444)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      icon: const Icon(Icons.delete_outline_rounded, size: 16),
                      label: const Text('Hapus Akun', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      onPressed: () async {
                        final deleted = await ConfirmDeleteDialog.show(
                          context: context,
                          title: isAdmin ? 'Hapus Akun Administrator?' : 'Hapus Akun Guru & Staf?',
                          itemType: 'Nama Akun',
                          itemName: name,
                          message: 'Akun ini beserta seluruh data penugasan terkait akan dihapus secara permanen dari server sekolah.',
                          onConfirm: () => widget.controller.deleteUser(_currentStaff['id']),
                        );
                        if (!context.mounted) return;
                        if (deleted == true) {
                          Navigator.of(context).pop();
                        }
                      },
                    ),
                  ),
                ],
              ],
            ),
            if (!isAdmin) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF3B82F6),
                    side: const BorderSide(color: Color(0xFF3B82F6)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: const Icon(Icons.link_rounded, size: 17),
                  label: Text(
                    assignedClass != null ? 'Ganti Penugasan Wali Kelas' : 'Tautkan Sebagai Wali Kelas',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  onPressed: () => _openClassAssignSheet(context, isDark),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildMiniStat({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 9.5,
              color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthorityItem({
    required IconData icon,
    required Color color,
    required String title,
    required String desc,
    required bool isDark,
    bool showDivider = true,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      desc,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.3,
                        color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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

  Widget _buildCompactSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
    required bool isDark,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Row(
            children: [
              Icon(icon, size: 14, color: const Color(0xFF10B981)),
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

  Widget _buildCompactRow({
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
}
