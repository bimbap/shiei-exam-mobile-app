import 'package:flutter/material.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_notification.dart';
import '../dialogs/class_form_dialog.dart';
import '../dialogs/confirm_delete_dialog.dart';
import '../teacher_portal_controller.dart';
import 'student_detail_screen.dart';

class ClassDetailScreen extends StatefulWidget {
  final Map<String, dynamic> classData;
  final TeacherPortalController controller;

  const ClassDetailScreen({
    super.key,
    required this.classData,
    required this.controller,
  });

  @override
  State<ClassDetailScreen> createState() => _ClassDetailScreenState();
}

class _ClassDetailScreenState extends State<ClassDetailScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  late Map<String, dynamic> _currentClassData;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _currentClassData = Map<String, dynamic>.from(widget.classData);
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    if (widget.controller.teachers.isEmpty) {
      widget.controller.loadTeachers();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _classStudents {
    final classId = _currentClassData['id'];
    return widget.controller.students.where((s) {
      final sClassId = s['class_major_id'] ??
          s['class_id'] ??
          s['class_major']?['id'] ??
          s['classes']?['id'];
      if (sClassId?.toString() != classId?.toString()) return false;

      if (_searchQuery.isNotEmpty) {
        final name = (s['name'] ?? '').toString().toLowerCase();
        final username = (s['username'] ?? '').toString().toLowerCase();
        final nisn = (s['nisn'] ?? '').toString().toLowerCase();
        final q = _searchQuery.toLowerCase();
        if (!name.contains(q) && !username.contains(q) && !nisn.contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  Map<String, dynamic>? get _classTeacher {
    final classId = _currentClassData['id'];
    if (classId == null) return null;

    for (final t in widget.controller.teachers) {
      if (t['class_major_id']?.toString() == classId.toString()) {
        return t;
      }
    }

    final raw = _currentClassData['teachers'];
    if (raw is List && raw.isNotEmpty && raw.first is Map) {
      return Map<String, dynamic>.from(raw.first);
    }
    return null;
  }

  void _confirmResetDevice(BuildContext context, Map<String, dynamic> student) {
    final isDark = AppTheme.isDark(context);
    final studentId = student['id'];
    final studentName = student['name'] ?? 'Siswa';
    final deviceModel = student['device_name'] ??
        student['serial_number'] ??
        'Perangkat Terdaftar';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppTheme.surfaceDark : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
        ),
        title: const Text(
          'Reset Kunci HP Siswa?',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Lepaskan kunci perangkat untuk "$studentName"?\n\n'
          'Perangkat terikat: $deviceModel\n\n'
          'Setelah di-reset, siswa dapat langsung login dengan perangkat HP baru.',
          style: TextStyle(
            fontSize: 12.5,
            color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Batal',
              style: TextStyle(
                color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8B5CF6),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 0,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              if (studentId != null) {
                final ok = await widget.controller.resetStudentDevice(studentId);
                if (context.mounted) {
                  if (ok) {
                    setState(() {});
                    AppNotification.showSuccess(
                      context,
                      'Kunci HP Direset',
                      subtitle: '$studentName dapat login di HP cadangan.',
                    );
                  } else {
                    AppNotification.showError(
                      context,
                      'Gagal Mereset Perangkat',
                      subtitle: 'Tidak dapat melepaskan kunci perangkat dari server.',
                    );
                  }
                }
              }
            },
            child: const Text('Reset Kunci HP'),
          ),
        ],
      ),
    );
  }

  void _confirmDetachTeacher(BuildContext context, Map<String, dynamic> teacher) {
    final isDark = AppTheme.isDark(context);
    final teacherName = teacher['name'] ?? 'Guru';
    final className = _currentClassData['name'] ?? 'Kelas';
    final classId = _currentClassData['id'] as int;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppTheme.surfaceDark : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
        ),
        title: const Text(
          'Lepaskan Wali Kelas?',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Lepaskan "$teacherName" dari status Wali Kelas di "$className"?\n\n'
          'Guru ini tidak akan lagi terhubung sebagai wali kelas pada kelas ini.',
          style: TextStyle(
            fontSize: 12.5,
            color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Batal',
              style: TextStyle(
                color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 0,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              final err = await widget.controller.assignClassTeacher(classId, null);
              if (context.mounted) {
                if (err == null) {
                  setState(() {
                    _currentClassData['teachers'] = [];
                  });
                  AppNotification.showSuccess(
                    context,
                    'Wali Kelas Dilepaskan',
                    subtitle: '$teacherName berhasil dilepaskan dari $className.',
                  );
                } else {
                  AppNotification.showError(
                    context,
                    'Gagal Melepas Hubungan',
                    subtitle: err,
                  );
                }
              }
            },
            child: const Text('Lepas Hubungan'),
          ),
        ],
      ),
    );
  }

  void _openAssignTeacherSheet(BuildContext context) {
    if (!widget.controller.isAdmin) {
      AppNotification.showError(
        context,
        'Akses Dibatasi',
        subtitle: 'Hanya administrator sekolah yang dapat mengelola wali kelas.',
      );
      return;
    }

    final isDark = AppTheme.isDark(context);
    final classId = _currentClassData['id'] as int;
    final className = _currentClassData['name'] ?? 'Kelas';
    String query = '';

    final searchController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 600),
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final teachers = widget.controller.teachers;
            final currentTeacherId = _classTeacher?['id'];
            final filtered = teachers.where((t) {
              if (query.isEmpty) return true;
              final q = query.toLowerCase();
              final name = (t['name'] ?? '').toString().toLowerCase();
              final nip = (t['nip'] ?? '').toString().toLowerCase();
              return name.contains(q) || nip.contains(q);
            }).toList();

            return Container(
              height: MediaQuery.of(ctx).size.height * 0.75,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border(
                  top: BorderSide(
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                  ),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  children: [
                    // Drag Handle
                    Container(
                      width: 38,
                      height: 4,
                      margin: const EdgeInsets.only(top: 12, bottom: 12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),

                    // Header with Icon & Teacher Counter (No Close 'X' Button)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: const Color(0xFF8B5CF6).withValues(alpha: isDark ? 0.2 : 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.supervisor_account_rounded,
                              color: Color(0xFF8B5CF6),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Hubungkan Wali Kelas',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Pilih guru pembimbing untuk kelas $className',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Text(
                              '${teachers.length} Guru',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Search Field with Instant Clear Affordance
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                      child: TextField(
                        controller: searchController,
                        autofocus: false,
                        textInputAction: TextInputAction.search,
                        onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                        onSubmitted: (_) => FocusScope.of(context).unfocus(),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                        decoration: InputDecoration(
                          hintText: 'Cari nama guru atau NIP...',
                          hintStyle: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: isDark ? AppTheme.textSecondary : const Color(0xFF94A3B8),
                          ),
                          prefixIcon: Icon(
                            Icons.search_rounded,
                            size: 19,
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                          ),
                          suffixIcon: query.isNotEmpty
                              ? GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () {
                                    searchController.clear();
                                    setModalState(() => query = '');
                                  },
                                  child: Icon(
                                    Icons.cancel_rounded,
                                    size: 18,
                                    color: isDark ? AppTheme.textSecondary : const Color(0xFF94A3B8),
                                  ),
                                )
                              : null,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          filled: true,
                          fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFF8B5CF6),
                              width: 1.5,
                            ),
                          ),
                        ),
                        onChanged: (val) {
                          setModalState(() => query = val.trim());
                        },
                      ),
                    ),

                    // Option: Lepaskan / Kosongkan Wali Kelas
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () async {
                            Navigator.pop(ctx);
                            if (currentTeacherId == null) return;

                            final err = await widget.controller.assignClassTeacher(classId, null);
                            if (context.mounted) {
                              if (err == null) {
                                setState(() {
                                  _currentClassData['teachers'] = [];
                                });
                                AppNotification.showSuccess(
                                  context,
                                  'Wali Kelas Dikosongkan',
                                  subtitle: 'Kelas $className kini tidak memiliki wali kelas binaan.',
                                );
                              } else {
                                AppNotification.showError(
                                  context,
                                  'Gagal Mengosongkan Wali Kelas',
                                  subtitle: err,
                                );
                              }
                            }
                          },
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: currentTeacherId == null
                                  ? (isDark
                                      ? const Color(0xFF10B981).withValues(alpha: 0.12)
                                      : const Color(0xFFECFDF5))
                                  : (isDark
                                      ? const Color(0xFF1E293B).withValues(alpha: 0.5)
                                      : const Color(0xFFF8FAFC)),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: currentTeacherId == null
                                    ? const Color(0xFF10B981).withValues(alpha: 0.45)
                                    : (isDark
                                        ? const Color(0xFF334155).withValues(alpha: 0.6)
                                        : const Color(0xFFE2E8F0)),
                                width: currentTeacherId == null ? 1.4 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: currentTeacherId == null
                                        ? const Color(0xFF10B981).withValues(alpha: 0.18)
                                        : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    Icons.person_off_rounded,
                                    size: 19,
                                    color: currentTeacherId == null
                                        ? const Color(0xFF10B981)
                                        : (isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Tidak Ada / Kosongkan Wali Kelas',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: currentTeacherId == null
                                              ? FontWeight.bold
                                              : FontWeight.w600,
                                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Kelas ini tidak memiliki wali kelas binaan',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isDark
                                              ? AppTheme.textSecondary
                                              : const Color(0xFF64748B),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (currentTeacherId == null)
                                  const Icon(
                                    Icons.check_circle_rounded,
                                    color: Color(0xFF10B981),
                                    size: 20,
                                  )
                                else
                                  Icon(
                                    Icons.radio_button_unchecked_rounded,
                                    size: 19,
                                    color: isDark
                                        ? const Color(0xFF475569)
                                        : const Color(0xFFCBD5E1),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 4),

                    // Teachers List or Empty State
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 30),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? const Color(0xFF1E293B)
                                            : const Color(0xFFF1F5F9),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.person_search_rounded,
                                        size: 24,
                                        color: isDark
                                            ? AppTheme.textSecondary
                                            : const Color(0xFF94A3B8),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      'Guru Tidak Ditemukan',
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.bold,
                                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      query.isEmpty
                                          ? 'Belum ada guru terdaftar di sekolah ini.'
                                          : 'Tidak ada guru yang cocok dengan "$query".',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: isDark
                                            ? AppTheme.textSecondary
                                            : const Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListView.builder(
                              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                              padding: const EdgeInsets.fromLTRB(16, 2, 16, 20),
                              itemCount: filtered.length,
                              itemBuilder: (ctx, i) {
                                final teacher = filtered[i];
                                final id = teacher['id'] as int?;
                                final name = teacher['name']?.toString() ?? 'Guru';
                                final nip = teacher['nip']?.toString();
                                final isCurrent = currentTeacherId == id;

                                final assignedClassId = teacher['class_major_id'];
                                String? assignedClassName;
                                if (assignedClassId != null) {
                                  final match = widget.controller.classes.firstWhere(
                                    (c) => c['id']?.toString() == assignedClassId.toString(),
                                    orElse: () => {},
                                  );
                                  assignedClassName = match['name']?.toString();
                                }

                                final isAssignedHere = assignedClassId != null &&
                                    assignedClassId.toString() == classId.toString();

                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 3),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () async {
                                        Navigator.pop(ctx);
                                        if (isCurrent) return;

                                        final err = await widget.controller
                                            .assignClassTeacher(classId, id);
                                        if (context.mounted) {
                                          if (err == null) {
                                            setState(() {
                                              _currentClassData['teachers'] = [teacher];
                                            });
                                            AppNotification.showSuccess(
                                              context,
                                              'Wali Kelas Terhubung',
                                              subtitle:
                                                  '$name berhasil ditugaskan sebagai wali kelas $className.',
                                            );
                                          } else {
                                            AppNotification.showError(
                                              context,
                                              'Gagal Menghubungkan Guru',
                                              subtitle: err,
                                            );
                                          }
                                        }
                                      },
                                      borderRadius: BorderRadius.circular(14),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 14, vertical: 10),
                                        decoration: BoxDecoration(
                                          color: isCurrent
                                              ? const Color(0xFF8B5CF6)
                                                  .withValues(alpha: isDark ? 0.15 : 0.08)
                                              : (isDark
                                                  ? const Color(0xFF1E293B)
                                                      .withValues(alpha: 0.5)
                                                  : const Color(0xFFF8FAFC)),
                                          borderRadius: BorderRadius.circular(14),
                                          border: Border.all(
                                            color: isCurrent
                                              ? const Color(0xFF8B5CF6).withValues(alpha: 0.6)
                                              : (isDark
                                                  ? const Color(0xFF334155).withValues(alpha: 0.5)
                                                  : const Color(0xFFE2E8F0)),
                                            width: isCurrent ? 1.4 : 1,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 38,
                                              height: 38,
                                              decoration: BoxDecoration(
                                                color: isCurrent
                                                    ? const Color(0xFF8B5CF6).withValues(alpha: 0.2)
                                                    : (isDark
                                                        ? const Color(0xFF334155)
                                                        : const Color(0xFFE2E8F0)),
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: Center(
                                                child: Text(
                                                  name.isNotEmpty ? name[0].toUpperCase() : 'G',
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 15,
                                                    color: isCurrent
                                                        ? const Color(0xFF8B5CF6)
                                                        : (isDark
                                                            ? Colors.white
                                                            : const Color(0xFF0F172A)),
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
                                                    name,
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      fontWeight: isCurrent
                                                          ? FontWeight.bold
                                                          : FontWeight.w600,
                                                      color: isDark
                                                          ? Colors.white
                                                          : const Color(0xFF0F172A),
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    'NIP: ${nip != null && nip.isNotEmpty ? nip : '-'}',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: isDark
                                                          ? AppTheme.textSecondary
                                                          : const Color(0xFF64748B),
                                                    ),
                                                  ),
                                                  if (assignedClassName != null) ...[
                                                    const SizedBox(height: 4),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(
                                                          horizontal: 7, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: isAssignedHere
                                                            ? const Color(0xFF10B981)
                                                                .withValues(alpha: 0.12)
                                                            : const Color(0xFFF59E0B)
                                                                .withValues(alpha: 0.12),
                                                        borderRadius: BorderRadius.circular(6),
                                                        border: Border.all(
                                                          color: isAssignedHere
                                                              ? const Color(0xFF10B981)
                                                                  .withValues(alpha: 0.3)
                                                              : const Color(0xFFF59E0B)
                                                                  .withValues(alpha: 0.3),
                                                        ),
                                                      ),
                                                      child: Row(
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          Icon(
                                                            isAssignedHere
                                                                ? Icons.check_rounded
                                                                : Icons.swap_horiz_rounded,
                                                            size: 11,
                                                            color: isAssignedHere
                                                                ? const Color(0xFF10B981)
                                                                : const Color(0xFFD97706),
                                                          ),
                                                          const SizedBox(width: 4),
                                                          Flexible(
                                                            child: Text(
                                                              isAssignedHere
                                                                  ? 'Wali kelas saat ini'
                                                                  : 'Wali kelas $assignedClassName (Akan dipindahkan)',
                                                              style: TextStyle(
                                                                fontSize: 10,
                                                                fontWeight: FontWeight.w700,
                                                                color: isAssignedHere
                                                                    ? const Color(0xFF10B981)
                                                                    : const Color(0xFFD97706),
                                                              ),
                                                              maxLines: 1,
                                                              overflow: TextOverflow.ellipsis,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            if (isCurrent)
                                              const Icon(
                                                Icons.check_circle_rounded,
                                                color: Color(0xFF8B5CF6),
                                                size: 20,
                                              )
                                            else
                                              Icon(
                                                Icons.radio_button_unchecked_rounded,
                                                size: 19,
                                                color: isDark
                                                    ? const Color(0xFF475569)
                                                    : const Color(0xFFCBD5E1),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
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
    final className = _currentClassData['name']?.toString() ?? 'Kelas';
    final teacher = _classTeacher;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // Layer 1: Clear student search if active
        if (_searchController.text.isNotEmpty) {
          setState(() {
            _searchController.clear();
            _searchQuery = '';
          });
          return;
        }
        // Layer 2: Return to students tab if on Wali Kelas tab
        if (_tabController.index != 0) {
          _tabController.animateTo(0);
          return;
        }
        // Layer 3: Pop screen back to SchoolDataTab
        Navigator.of(context).pop();
      },
      child: Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(
        title: Text(className, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Muat Ulang Data',
            onPressed: () {
              widget.controller.loadStudents();
              widget.controller.loadTeachers();
            },
          ),
          if (widget.controller.isAdmin) ...[
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit Kelas',
              onPressed: () async {
                final res = await ClassFormDialog.show(
                  context: context,
                  classData: _currentClassData,
                  controller: widget.controller,
                );
                if (res == true && mounted) {
                  final updated = widget.controller.classes.firstWhere(
                    (c) => c['id'] == _currentClassData['id'],
                    orElse: () => _currentClassData,
                  );
                  setState(() {
                    _currentClassData = Map<String, dynamic>.from(updated);
                  });
                }
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444)),
              tooltip: 'Hapus Kelas',
              onPressed: () async {
                final classId = _currentClassData['id'];
                final rawCount = _currentClassData['student_count'] ??
                    _currentClassData['students_count'] ??
                    _currentClassData['users_count'];
                final classStudents = widget.controller.students.where((s) {
                  final sClassId = s['class_major_id'] ??
                      s['class_id'] ??
                      s['class_major']?['id'] ??
                      s['classes']?['id'];
                  return sClassId?.toString() == classId?.toString();
                }).toList();
                final totalStudents = rawCount != null
                    ? (int.tryParse(rawCount.toString()) ?? classStudents.length)
                    : classStudents.length;
                final hasStudents = totalStudents > 0;
                final name = _currentClassData['name']?.toString() ?? 'Kelas';

                final deleted = await ConfirmDeleteDialog.show(
                  context: context,
                  title: hasStudents ? 'Hapus Kelas & Seluruh Siswa?' : 'Hapus Kelas?',
                  itemType: 'Nama Kelas',
                  itemName: name,
                  message: hasStudents
                      ? 'Kelas "$name" saat ini memiliki $totalStudents siswa aktif terdaftar.'
                      : 'Apakah Anda yakin ingin menghapus kelas "$name"? Tidak ada siswa yang terdaftar di kelas ini.',
                  warningNote: hasStudents
                      ? 'PERHATIAN PENTING: Menghapus kelas ini akan secara otomatis MENGHAPUS SEMUA $totalStudents SISWA di dalamnya beserta seluruh akun login, ikatan perangkat HP, dan riwayat ujian mereka. Tindakan ini bersifat permanen!'
                      : null,
                  confirmLabel: hasStudents ? 'Hapus Kelas & $totalStudents Siswa' : 'Hapus Kelas',
                  onConfirm: () => widget.controller.deleteClass(classId),
                );
                if (deleted == true && context.mounted) {
                  Navigator.pop(context);
                }
              },
            ),
          ],
        ],
      ),
      floatingActionButton: (widget.controller.isAdmin &&
              _tabController.index == 1 &&
              teacher == null)
          ? FloatingActionButton.extended(
              backgroundColor: const Color(0xFF8B5CF6),
              foregroundColor: Colors.white,
              elevation: 4,
              onPressed: () => _openAssignTeacherSheet(context),
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
              label: const Text(
                'Hubungkan Guru',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
              ),
            )
          : null,
      body: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final students = _classStudents;
          final currentTeacher = _classTeacher;
          final totalBound = students.where((s) {
            final sn = s['serial_number']?.toString();
            final dn = s['device_name']?.toString();
            return (sn != null && sn.isNotEmpty) || (dn != null && dn.isNotEmpty);
          }).length;

          return Column(
            children: [
              // Enhanced Class Header Card
              _buildHeaderCard(isDark, className, students.length, totalBound, currentTeacher),

              // Segmented Navigation TabBar
              _buildTabBar(isDark, students.length, currentTeacher),

              // TabBarView
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // Tab 0: Students List
                    _buildStudentsTab(isDark, className, students),

                    // Tab 1: Wali Kelas / Guru Kelas
                    _buildTeacherTab(isDark, currentTeacher),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      ),
    );
  }

  Widget _buildHeaderCard(
    bool isDark,
    String className,
    int studentCount,
    int totalBound,
    Map<String, dynamic>? teacher,
  ) {
    final teacherName = teacher?['name']?.toString();
    final hasTeacher = teacherName != null && teacherName.isNotEmpty;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
              : [const Color(0xFFF5F3FF), Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFDDD6FE),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Center(
              child: Icon(Icons.school_rounded, color: Color(0xFF8B5CF6), size: 26),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  className,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 6),
                // Line 1: Total Siswa & HP Terikat
                Row(
                  children: [
                    // Total Siswa
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6366F1).withValues(alpha: isDark ? 0.16 : 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: const Color(0xFF6366F1).withValues(alpha: isDark ? 0.35 : 0.22),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.people_alt_outlined, size: 11.5, color: Color(0xFF6366F1)),
                          const SizedBox(width: 4),
                          Text(
                            '$studentCount Siswa',
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF6366F1),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    // HP Terikat
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: (totalBound > 0 ? const Color(0xFF10B981) : const Color(0xFF64748B))
                            .withValues(alpha: isDark ? 0.16 : 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: (totalBound > 0 ? const Color(0xFF10B981) : const Color(0xFF64748B))
                              .withValues(alpha: isDark ? 0.35 : 0.22),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            totalBound > 0 ? Icons.phonelink_lock_rounded : Icons.phonelink_off_rounded,
                            size: 11.5,
                            color: totalBound > 0 ? const Color(0xFF10B981) : const Color(0xFF64748B),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$totalBound HP Terikat',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: totalBound > 0 ? const Color(0xFF10B981) : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                // Line 2: Wali Kelas Badge (Full width line to avoid truncation)
                Row(
                  children: [
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                        decoration: BoxDecoration(
                          color: (hasTeacher ? const Color(0xFF8B5CF6) : const Color(0xFFF59E0B))
                              .withValues(alpha: isDark ? 0.16 : 0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: (hasTeacher ? const Color(0xFF8B5CF6) : const Color(0xFFF59E0B))
                                .withValues(alpha: isDark ? 0.35 : 0.22),
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              hasTeacher ? Icons.person_pin_rounded : Icons.person_outline_rounded,
                              size: 11.5,
                              color: hasTeacher ? const Color(0xFF8B5CF6) : const Color(0xFFF59E0B),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                hasTeacher ? 'Wali: $teacherName' : 'Belum Ada Wali Kelas',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: hasTeacher ? const Color(0xFF8B5CF6) : const Color(0xFFF59E0B),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(bool isDark, int studentCount, Map<String, dynamic>? teacher) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      height: 38,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: isDark ? const Color(0xFF334155) : Colors.white,
          borderRadius: BorderRadius.circular(9),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        labelColor: isDark ? Colors.white : const Color(0xFF0F172A),
        unselectedLabelColor: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        unselectedLabelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        tabs: [
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.people_alt_outlined, size: 15),
                const SizedBox(width: 6),
                Text('Daftar Siswa ($studentCount)'),
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.supervisor_account_rounded, size: 15),
                const SizedBox(width: 6),
                Text(teacher != null ? 'Wali Kelas (1)' : 'Wali Kelas'),
                if (teacher == null) ...[
                  const SizedBox(width: 5),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF59E0B),
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentsTab(
    bool isDark,
    String className,
    List<Map<String, dynamic>> students,
  ) {
    return Column(
      children: [
        // Search Field
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            onSubmitted: (_) => FocusScope.of(context).unfocus(),
            onChanged: (val) => setState(() => _searchQuery = val.trim()),
            style: TextStyle(fontSize: 13, color: isDark ? Colors.white : const Color(0xFF0F172A)),
            decoration: InputDecoration(
              hintText: 'Cari siswa di kelas $className...',
              hintStyle: TextStyle(
                fontSize: 12,
                color: isDark ? AppTheme.textSecondary : const Color(0xFF94A3B8),
              ),
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              filled: true,
              fillColor: isDark ? AppTheme.surfaceDark : Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                ),
              ),
            ),
          ),
        ),

        // Students List in this Class
        Expanded(
          child: students.isEmpty
              ? Center(
                  child: Text(
                    'Tidak ada siswa ditemukan di kelas ini.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                    ),
                  ),
                )
              : ListView.builder(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                  itemCount: students.length,
                  itemBuilder: (ctx, index) {
                    final student = students[index];
                    final name = student['name']?.toString() ?? 'Siswa';
                    final rawNisn = student['nisn']?.toString().trim();
                    final rawUsername = student['username']?.toString().trim();
                    final nisn = (rawNisn != null && rawNisn.isNotEmpty && rawNisn != '-')
                        ? rawNisn
                        : (rawUsername != null && rawUsername.isNotEmpty && rawUsername != '-')
                            ? rawUsername
                            : '-';
                    final deviceName = student['device_name']?.toString();
                    final serial = student['serial_number']?.toString();
                    final hasBoundDevice = (deviceName != null && deviceName.isNotEmpty) ||
                        (serial != null && serial.isNotEmpty);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark ? AppTheme.surfaceDark : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: hasBoundDevice
                                  ? const Color(0xFF8B5CF6).withValues(alpha: 0.12)
                                  : (isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9)),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Center(
                              child: Text(
                                name.isNotEmpty ? name[0].toUpperCase() : 'S',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: hasBoundDevice
                                      ? const Color(0xFF8B5CF6)
                                      : const Color(0xFF94A3B8),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: InkWell(
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => StudentDetailScreen(
                                      student: student,
                                      controller: widget.controller,
                                    ),
                                  ),
                                );
                              },
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13.5,
                                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'NISN: $nisn',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w500,
                                      color: isDark
                                          ? AppTheme.textSecondary
                                          : const Color(0xFF64748B),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Icon(
                                        hasBoundDevice
                                            ? Icons.phonelink_lock_rounded
                                            : Icons.phonelink_off_rounded,
                                        size: 12,
                                        color: hasBoundDevice
                                            ? const Color(0xFF10B981)
                                            : const Color(0xFF94A3B8),
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          hasBoundDevice
                                              ? '${deviceName ?? serial}'
                                              : 'Belum terikat ke perangkat',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            color: hasBoundDevice
                                                ? (isDark
                                                    ? const Color(0xFF10B981)
                                                    : const Color(0xFF059669))
                                                : (isDark
                                                    ? AppTheme.textSecondary
                                                    : const Color(0xFF94A3B8)),
                                            fontWeight: hasBoundDevice
                                                ? FontWeight.w600
                                                : FontWeight.normal,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (hasBoundDevice && widget.controller.canManageStudent(student))
                            IconButton(
                              icon: const Icon(
                                Icons.phonelink_erase_rounded,
                                color: Color(0xFF8B5CF6),
                                size: 18,
                              ),
                              tooltip: 'Reset Binding HP',
                              onPressed: () => _confirmResetDevice(context, student),
                            ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildTeacherTab(bool isDark, Map<String, dynamic>? teacher) {
    if (teacher == null) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Icon(
                    Icons.person_off_rounded,
                    size: 36,
                    color: Color(0xFFF59E0B),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Belum Ada Wali Kelas Terhubung',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'Kelas ini belum memiliki guru wali kelas pembimbing. Hubungkan guru agar dapat memantau data dan rekapitulasi ujian siswa kelas ini.',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final name = teacher['name']?.toString() ?? 'Guru';
    final nip = teacher['nip']?.toString();
    final email = teacher['email']?.toString();
    final assignedClassName = _currentClassData['name']?.toString() ?? '';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.surfaceDark : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                // Avatar
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF8B5CF6).withValues(alpha: 0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : 'G',
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Name
                Text(
                  name,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 8),

                // Single focused badge (Opsi A)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6).withValues(alpha: isDark ? 0.18 : 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFF8B5CF6).withValues(alpha: isDark ? 0.4 : 0.25),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.school_rounded, size: 13, color: Color(0xFF8B5CF6)),
                      const SizedBox(width: 5),
                      Text(
                        assignedClassName.isNotEmpty
                            ? 'Pembina Kelas $assignedClassName'
                            : 'Wali Kelas Resmi',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF8B5CF6),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Divider(height: 1),
                const SizedBox(height: 16),

                // Info Rows
                _buildInfoRow(
                  isDark: isDark,
                  icon: Icons.badge_outlined,
                  label: 'NIP / Identitas',
                  value: (nip != null && nip.isNotEmpty) ? nip : '-',
                ),
                const SizedBox(height: 12),
                _buildInfoRow(
                  isDark: isDark,
                  icon: Icons.alternate_email_rounded,
                  label: 'Email / Akun',
                  value: (email != null && email.isNotEmpty) ? email : '-',
                ),
                const SizedBox(height: 12),
                _buildInfoRow(
                  isDark: isDark,
                  icon: Icons.school_outlined,
                  label: 'Kelas Binaan',
                  value: _currentClassData['name']?.toString() ?? '-',
                ),

                // Admin Action Buttons
                if (widget.controller.isAdmin) ...[
                  const SizedBox(height: 20),
                  const Divider(height: 1),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            side: BorderSide(
                              color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                            ),
                          ),
                          onPressed: () => _openAssignTeacherSheet(context),
                          icon: const Icon(Icons.sync_alt_rounded, size: 16),
                          label: const Text(
                            'Ganti Guru',
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            foregroundColor: const Color(0xFFEF4444),
                            side: BorderSide(
                              color: const Color(0xFFEF4444).withValues(alpha: 0.4),
                            ),
                          ),
                          onPressed: () => _confirmDetachTeacher(context, teacher),
                          icon: const Icon(Icons.link_off_rounded, size: 16),
                          label: const Text(
                            'Lepas Hubungan',
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required bool isDark,
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: isDark ? AppTheme.textSecondary : const Color(0xFF94A3B8),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
