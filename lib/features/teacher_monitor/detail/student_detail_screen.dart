import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_notification.dart';
import '../../../../shared/widgets/shiei_select_sheet.dart';
import '../dialogs/confirm_delete_dialog.dart';
import '../dialogs/student_action_sheet.dart';
import '../dialogs/user_form_dialog.dart';
import '../teacher_portal_controller.dart';

class StudentDetailScreen extends StatefulWidget {
  final Map<String, dynamic> student;
  final TeacherPortalController controller;

  const StudentDetailScreen({
    super.key,
    required this.student,
    required this.controller,
  });

  @override
  State<StudentDetailScreen> createState() => _StudentDetailScreenState();
}

class _StudentDetailScreenState extends State<StudentDetailScreen> {
  late Map<String, dynamic> _currentStudent;

  @override
  void initState() {
    super.initState();
    _currentStudent = Map<String, dynamic>.from(widget.student);
  }

  void _confirmResetDevice() {
    final isDark = AppTheme.isDark(context);
    final studentId = _currentStudent['id'];
    final studentName = _currentStudent['name'] ?? 'Siswa';
    final deviceModel = _currentStudent['device_name'] ?? _currentStudent['serial_number'] ?? 'Perangkat Terdaftar';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppTheme.surfaceDark : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
        ),
        title: const Text('Lepaskan Kunci HP?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: Text(
          'Lepaskan kunci perangkat untuk "$studentName"?\n\n'
          'Perangkat saat ini: $deviceModel\n\n'
          'Setelah di-reset, siswa dapat login dari perangkat HP lain secara instan.',
          style: TextStyle(
            fontSize: 12.5,
            color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Batal', style: TextStyle(color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8B5CF6),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              if (studentId != null) {
                final ok = await widget.controller.resetStudentDevice(studentId);
                if (!mounted) return;
                if (ok) {
                  setState(() {
                    _currentStudent['device_name'] = null;
                    _currentStudent['device_id'] = null;
                    _currentStudent['serial_number'] = null;
                  });
                  AppNotification.showSuccess(
                    context,
                    'Kunci HP Direset',
                    subtitle: '$studentName sekarang bisa login di HP baru.',
                  );
                } else {
                  AppNotification.showError(
                    context,
                    'Gagal Mereset Perangkat',
                    subtitle: 'Tidak dapat melepaskan kunci perangkat dari server.',
                  );
                }
              }
            },
            child: const Text('Reset Kunci HP'),
          ),
        ],
      ),
    );
  }

  void _copyToClipboard(String text, String title, String subtitle) {
    Clipboard.setData(ClipboardData(text: text));
    AppNotification.showSuccess(
      context,
      title,
      subtitle: subtitle,
    );
  }

  void _showMutasiKelasDialog(BuildContext context, bool isDark) {
    final studentId = _currentStudent['id'];
    if (studentId == null) return;

    final currentClassId = _currentStudent['class_major_id'] ??
        _currentStudent['class_id'] ??
        _currentStudent['class_major']?['id'];
    final currentClassName = _currentStudent['class_major']?['name']?.toString() ??
        _currentStudent['classes']?['name']?.toString() ??
        _currentStudent['class_name']?.toString() ??
        'Tanpa Kelas';
    final studentName = _currentStudent['name']?.toString() ?? 'Siswa';

    int? targetClassId;
    bool isSubmitting = false;
    String? localError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 600),
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            final bottomInset = MediaQuery.of(modalCtx).viewInsets.bottom;
            final availableClasses = widget.controller.classes;

            return Container(
              padding: EdgeInsets.only(bottom: bottomInset),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.surfaceDark : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border.all(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                ),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),

                    // Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.swap_horiz_rounded, color: Color(0xFF3B82F6), size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Mutasi / Pindah Kelas',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                'Pindahkan "$studentName" ke rombongan belajar baru',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    if (localError != null) ...[
                      Container(
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                localError!,
                                style: const TextStyle(fontSize: 12, color: Color(0xFFEF4444), fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Current Class Info
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.school_rounded, size: 20, color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Kelas Saat Ini',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                                  ),
                                ),
                                Text(
                                  'Kelas $currentClassName',
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Asal',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF8B5CF6)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Destination Class Selector
                    Text(
                      'Pilih Kelas Tujuan *',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
                      ),
                    ),
                    const SizedBox(height: 6),
                    ShieiSelectorField<int?>(
                      label: '',
                      isDark: isDark,
                      prefixIcon: Icons.arrow_forward_rounded,
                      valueText: targetClassId == null
                          ? 'Pilih Kelas Tujuan Mutasi'
                          : availableClasses.firstWhere(
                              (c) => c['id'] == targetClassId,
                              orElse: () => {'name': 'Kelas #$targetClassId'},
                            )['name']?.toString(),
                      onTap: () async {
                        final selected = await ShieiSelectSheet.show<int?>(
                          context: context,
                          title: 'Pilih Kelas Tujuan Mutasi',
                          subtitle: 'Tentukan kelas baru untuk siswa ini',
                          selectedValue: targetClassId,
                          items: availableClasses
                              .where((c) => c['id']?.toString() != currentClassId?.toString())
                              .map((c) {
                            return ShieiSelectItem<int?>(
                              value: c['id'] as int?,
                              label: c['name']?.toString() ?? 'Kelas',
                              subtitle: 'Rombongan Belajar',
                              icon: Icons.school_rounded,
                            );
                          }).toList(),
                        );
                        if (selected != null) {
                          setModalState(() {
                            targetClassId = selected;
                            localError = null;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 20),

                    // Actions
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              side: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                            ),
                            onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                            child: Text(
                              'Batal',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF3B82F6),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: isSubmitting
                                ? null
                                : () async {
                                    if (targetClassId == null) {
                                      setModalState(() {
                                        localError = 'Pilih kelas tujuan mutasi terlebih dahulu.';
                                      });
                                      return;
                                    }

                                    setModalState(() {
                                      isSubmitting = true;
                                      localError = null;
                                    });

                                    final int sId = (studentId is int) ? studentId : int.parse(studentId.toString());
                                    final err = await widget.controller.transferStudentClass(
                                      sId,
                                      targetClassId!,
                                    );

                                    if (err == null) {
                                      if (ctx.mounted) {
                                        Navigator.pop(ctx);
                                      }
                                      if (!mounted) return;
                                      final targetClass = availableClasses.firstWhere(
                                        (c) => c['id'] == targetClassId,
                                        orElse: () => {'name': 'Kelas #$targetClassId'},
                                      );
                                      setState(() {
                                        _currentStudent['class_major_id'] = targetClassId;
                                        _currentStudent['class_major'] = targetClass;
                                        _currentStudent['class_name'] = targetClass['name'];
                                      });
                                      AppNotification.showSuccess(
                                        this.context,
                                        'Mutasi Siswa Berhasil',
                                        subtitle: '$studentName berhasil dipindahkan ke ${targetClass['name']}.',
                                      );
                                    } else {
                                      if (modalCtx.mounted) {
                                        setModalState(() {
                                          isSubmitting = false;
                                          localError = err;
                                        });
                                      }
                                    }
                                  },
                            child: isSubmitting
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Text(
                                    'Proses Mutasi Kelas',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final name = _currentStudent['name']?.toString() ?? 'Profil Siswa';
    final rawNisn = _currentStudent['nisn']?.toString().trim();
    final rawUsername = _currentStudent['username']?.toString().trim();
    final nisn = (rawNisn != null && rawNisn.isNotEmpty && rawNisn != '-')
        ? rawNisn
        : '-';
    final username = (rawUsername != null && rawUsername.isNotEmpty && rawUsername != '-')
        ? rawUsername
        : (name.isNotEmpty && name != 'Profil Siswa' ? name : 'siswa');
    final email = _currentStudent['email']?.toString() ?? '';
    final className = _currentStudent['class_major']?['name']?.toString() ??
        _currentStudent['classes']?['name']?.toString() ??
        _currentStudent['class_name']?.toString() ??
        'Umum';
    final deviceName = _currentStudent['device_name']?.toString();
    final serial = _currentStudent['serial_number']?.toString();
    final deviceId = _currentStudent['device_id']?.toString();
    final bool hasBoundDevice = (deviceName != null && deviceName.isNotEmpty) || (serial != null && serial.isNotEmpty);

    String joinDateFormatted = '-';
    if (_currentStudent['created_at'] != null) {
      try {
        final dt = DateTime.parse(_currentStudent['created_at'].toString()).toLocal();
        joinDateFormatted = DateFormat('d MMM yyyy', 'id_ID').format(dt);
      } catch (_) {
        joinDateFormatted = _currentStudent['created_at'].toString();
      }
    }

    // Check active session from monitoring records if available
    final studentId = _currentStudent['id'];
    final activeRecord = widget.controller.monitoringRecords.firstWhere(
      (r) => (r['user_id'] ?? r['user']?['id'])?.toString() == studentId?.toString(),
      orElse: () => <String, dynamic>{},
    );

    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(
        title: const Text('Detail Siswa', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          if (widget.controller.canManageStudent(_currentStudent)) ...[
            if (widget.controller.isAdmin)
              IconButton(
                icon: const Icon(Icons.swap_horiz_rounded, color: Color(0xFF3B82F6)),
                tooltip: 'Mutasi Kelas',
                onPressed: () => _showMutasiKelasDialog(context, isDark),
              ),
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit Siswa',
              onPressed: () async {
                final res = await UserFormDialog.show(
                  context: context,
                  userData: _currentStudent,
                  controller: widget.controller,
                );
                if (res == true && mounted) {
                  final updated = widget.controller.students.firstWhere(
                    (s) => s['id'] == _currentStudent['id'],
                    orElse: () => _currentStudent,
                  );
                  setState(() {
                    _currentStudent = Map<String, dynamic>.from(updated);
                  });
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444)),
              tooltip: 'Hapus Siswa',
              onPressed: () async {
                final deleted = await ConfirmDeleteDialog.show(
                  context: context,
                  title: 'Hapus Akun Siswa?',
                  itemType: 'Nama Siswa',
                  itemName: _currentStudent['name']?.toString() ?? 'Siswa',
                  message: 'Data akun siswa ini beserta riwayat sesi ujiannya akan dihapus permanen.',
                  onConfirm: () => widget.controller.deleteStudent(_currentStudent['id']),
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
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.3),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.badge_outlined, size: 13, color: Color(0xFF8B5CF6)),
                    SizedBox(width: 5),
                    Text(
                      'PROFIL IDENTITAS SISWA',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: Color(0xFF8B5CF6),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, size: 6, color: Color(0xFF10B981)),
                    SizedBox(width: 5),
                    Text(
                      'SISWA AKTIF',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF10B981),
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
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Center(
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : 'S',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF8B5CF6),
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
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.school_outlined, size: 11, color: Color(0xFF8B5CF6)),
                                const SizedBox(width: 4),
                                Text(
                                  'Kelas $className',
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF8B5CF6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.tag_rounded, size: 11, color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
                                const SizedBox(width: 3),
                                Text(
                                  'NISN: $nisn',
                                  style: TextStyle(
                                    fontSize: 10.5,
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

          // 3. Section: Informasi Profil & Biodata Siswa
          _buildCompactSection(
            title: 'Informasi Profil Siswa',
            icon: Icons.person_outline_rounded,
            isDark: isDark,
            children: [
              _buildCompactRow(
                icon: Icons.badge_outlined,
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
                icon: Icons.tag_rounded,
                label: 'NISN Siswa',
                isDark: isDark,
                onTap: () => _copyToClipboard(nisn, 'NISN Disalin', 'NISN $nisn disimpan ke clipboard.'),
                valueWidget: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      nisn,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white70 : const Color(0xFF334155),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.copy_rounded, size: 12, color: Color(0xFF8B5CF6)),
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
                icon: Icons.school_outlined,
                label: 'Kelas',
                isDark: isDark,
                valueWidget: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Kelas $className',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF8B5CF6),
                        ),
                      ),
                    ),
                    if (widget.controller.isAdmin) ...[
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: () => _showMutasiKelasDialog(context, isDark),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF3B82F6).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.3)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.swap_horiz_rounded, size: 12, color: Color(0xFF3B82F6)),
                              SizedBox(width: 3),
                              Text(
                                'Mutasi',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF3B82F6),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
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
                      (email.isNotEmpty && email != '-') ? email : 'Belum Terdaftar',
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

          // 4. Section: Perangkat Ujian & Hardware Lock
          _buildCompactSection(
            title: 'Perangkat Ujian Terikat',
            icon: Icons.phonelink_lock_rounded,
            isDark: isDark,
            children: [
              _buildCompactRow(
                icon: Icons.security_rounded,
                label: 'Status Kunci HP',
                isDark: isDark,
                valueWidget: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (hasBoundDevice ? const Color(0xFF10B981) : const Color(0xFF64748B)).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: (hasBoundDevice ? const Color(0xFF10B981) : const Color(0xFF64748B)).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        hasBoundDevice ? Icons.lock_outline_rounded : Icons.lock_open_rounded,
                        size: 11,
                        color: hasBoundDevice ? const Color(0xFF10B981) : const Color(0xFF64748B),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        hasBoundDevice ? 'TERIKAT (LOCKED)' : 'BELUM TERIKAT',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: hasBoundDevice ? const Color(0xFF10B981) : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              _buildCompactRow(
                icon: Icons.phone_android_rounded,
                label: 'Model Perangkat HP',
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
              _buildCompactRow(
                icon: Icons.fingerprint_rounded,
                label: 'Hardware Serial',
                isDark: isDark,
                onTap: (serial != null && serial.isNotEmpty)
                    ? () => _copyToClipboard(serial, 'Serial Disalin', serial)
                    : null,
                valueWidget: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 150),
                      child: Text(
                        serial ?? '-',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white70 : const Color(0xFF334155),
                        ),
                      ),
                    ),
                    if (serial != null && serial.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.copy_rounded, size: 12, color: Color(0xFF64748B)),
                    ],
                  ],
                ),
              ),
              _buildCompactRow(
                icon: Icons.perm_device_information_rounded,
                label: 'Device ID',
                showDivider: hasBoundDevice,
                isDark: isDark,
                onTap: (deviceId != null && deviceId.isNotEmpty)
                    ? () => _copyToClipboard(deviceId, 'Device ID Disalin', deviceId)
                    : null,
                valueWidget: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 150),
                      child: Text(
                        deviceId ?? '-',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white70 : const Color(0xFF334155),
                        ),
                      ),
                    ),
                    if (deviceId != null && deviceId.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.copy_rounded, size: 12, color: Color(0xFF64748B)),
                    ],
                  ],
                ),
              ),
              if (hasBoundDevice)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(
                    width: double.infinity,
                    height: 42,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF8B5CF6),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.phonelink_erase_rounded, size: 16),
                      label: const Text('Lepaskan Kunci HP Ini (Reset Binding)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      onPressed: _confirmResetDevice,
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline_rounded, size: 15, color: Color(0xFF8B5CF6)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Siswa dapat login dari HP mana saja. Saat pertama kali ujian dimulai, perangkat HP akan otomatis terikat ke akun ini.',
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.35,
                              color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),

          // 5. Section: Status Aktivitas & Sesi Ujian Terkini
          _buildCompactSection(
            title: 'Status Aktivitas & Sesi Ujian',
            icon: Icons.access_time_rounded,
            isDark: isDark,
            children: [
              _buildCompactRow(
                icon: Icons.info_outline_rounded,
                label: 'Status Sesi Siswa',
                isDark: isDark,
                valueWidget: Builder(
                  builder: (_) {
                    if (activeRecord.isEmpty) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'SIAP UJIAN (IDLE)',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                        ),
                      );
                    }
                    final status = activeRecord['status']?.toString().toLowerCase() ?? 'pending';
                    final bool isKicked = status == 'terminated' || activeRecord['lock_reason'] == 'proctor_kick' || activeRecord['is_kicked'] == true;
                    final bool isLocked = !isKicked && (activeRecord['is_locked'] == true || status == 'locked');
                    final bool isCompleted = status == 'completed' || status == 'submitted' || activeRecord['score'] != null;

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: isKicked
                            ? const Color(0xFFEF4444).withValues(alpha: 0.12)
                            : isLocked
                                ? const Color(0xFFF97316).withValues(alpha: 0.12)
                                : isCompleted
                                    ? const Color(0xFF10B981).withValues(alpha: 0.12)
                                    : const Color(0xFF3B82F6).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isKicked
                            ? 'DIKELUARKAN'
                            : isLocked
                                ? 'TERKUNCI'
                                : isCompleted
                                    ? 'UJIAN SELESAI'
                                    : 'SEDANG MENGERJAKAN',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isKicked
                              ? const Color(0xFFEF4444)
                              : isLocked
                                  ? const Color(0xFFF97316)
                                  : isCompleted
                                      ? const Color(0xFF10B981)
                                      : const Color(0xFF3B82F6),
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (activeRecord.isNotEmpty) ...[
                _buildCompactRow(
                  icon: Icons.assignment_outlined,
                  label: 'Ujian Terkini',
                  isDark: isDark,
                  valueWidget: Text(
                    activeRecord['link']?['title']?.toString() ?? activeRecord['title']?.toString() ?? 'Ujian Aktif',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                ),
                if (activeRecord['score'] != null)
                  _buildCompactRow(
                    icon: Icons.grade_rounded,
                    label: 'Skor / Nilai Akhir',
                    isDark: isDark,
                    valueWidget: Text(
                      '${activeRecord['score']}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                    ),
                  ),
              ],
              _buildCompactRow(
                icon: Icons.manage_accounts_outlined,
                label: 'Role Pengguna',
                showDivider: false,
                isDark: isDark,
                valueWidget: const Text(
                  'Siswa',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF8B5CF6),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 6. Section: Action Buttons
          if (activeRecord.isNotEmpty) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEA580C),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  elevation: 0,
                ),
                icon: const Icon(Icons.tune_rounded, size: 18),
                label: const Text('Kelola Sesi Ujian Siswa Ini', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                onPressed: () {
                  final isExamEnded = (activeRecord['link']?['status'] == 'inactive') || (activeRecord['is_exam_ended'] == true);
                  StudentActionSheet.show(
                    context: context,
                    record: activeRecord,
                    controller: widget.controller,
                    isExamEnded: isExamEnded,
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
          ],
          if (widget.controller.canManageStudent(_currentStudent)) ...[
            if (widget.controller.isAdmin) ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF3B82F6),
                    side: const BorderSide(color: Color(0xFF3B82F6)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                  label: const Text('Mutasi / Pindah Kelas', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  onPressed: () => _showMutasiKelasDialog(context, isDark),
                ),
              ),
              const SizedBox(height: 10),
            ],
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF8B5CF6),
                      side: const BorderSide(color: Color(0xFF8B5CF6)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Edit Siswa', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    onPressed: () async {
                      final res = await UserFormDialog.show(
                        context: context,
                        userData: _currentStudent,
                        controller: widget.controller,
                      );
                      if (res == true && mounted) {
                        final updated = widget.controller.students.firstWhere(
                          (s) => s['id'] == _currentStudent['id'],
                          orElse: () => _currentStudent,
                        );
                        setState(() {
                          _currentStudent = Map<String, dynamic>.from(updated);
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFEF4444),
                      side: const BorderSide(color: Color(0xFFEF4444)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.delete_outline_rounded, size: 16),
                    label: const Text('Hapus Akun', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    onPressed: () async {
                      final deleted = await ConfirmDeleteDialog.show(
                        context: context,
                        title: 'Hapus Akun Siswa?',
                        itemType: 'Nama Siswa',
                        itemName: _currentStudent['name']?.toString() ?? 'Siswa',
                        message: 'Data akun siswa ini beserta riwayat sesi ujiannya akan dihapus permanen.',
                        onConfirm: () => widget.controller.deleteStudent(_currentStudent['id']),
                      );
                      if (!context.mounted) return;
                      if (deleted == true) {
                        Navigator.of(context).pop();
                      }
                    },
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
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
              Icon(icon, size: 14, color: const Color(0xFF8B5CF6)),
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
