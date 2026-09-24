import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_notification.dart';
import '../../../../shared/widgets/shiei_bottom_sheet.dart';
import '../../../../shared/widgets/shiei_select_sheet.dart';
import '../../../../shared/widgets/shiei_checkbox.dart';
import '../teacher_portal_controller.dart';

class _RoleOption {
  final String role;
  final String label;
  final IconData icon;
  final Color color;

  const _RoleOption({
    required this.role,
    required this.label,
    required this.icon,
    required this.color,
  });
}

class UserFormDialog extends StatefulWidget {
  final Map<String, dynamic>? userData;
  final String? initialRole; // 'student', 'teacher', 'school_admin'
  final bool? allowRoleChange;
  final TeacherPortalController controller;

  const UserFormDialog({
    super.key,
    this.userData,
    this.initialRole,
    this.allowRoleChange,
    required this.controller,
  });

  static Future<bool?> show({
    required BuildContext context,
    Map<String, dynamic>? userData,
    String? initialRole,
    bool? allowRoleChange,
    required TeacherPortalController controller,
  }) async {
    FocusScope.of(context).unfocus();

    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => UserFormDialog(
        userData: userData,
        initialRole: initialRole,
        allowRoleChange: allowRoleChange,
        controller: controller,
      ),
    );
  }

  /// Snap fractions for the sheet.
  static const _snapFractions = [0.62, 0.925];

  @override
  State<UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends State<UserFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _nipController;
  late TextEditingController _nisnController;
  late TextEditingController _passwordController;

  // Sheet state is managed by ShieiBottomSheet internally
  late String _role; // 'student', 'teacher', 'school_admin'
  String? _subRole; // 'guru', 'kepala_sekolah', 'wakil_kepala_sekolah', 'karyawan'
  int? _selectedClassId;
  bool _resetDevice = false;
  bool _obscurePassword = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  // Cached values per role so form data switches cleanly and leaves zero ghost traces
  String _cachedStudentNisn = '';
  int? _cachedStudentClassId;
  String _cachedTeacherNip = '';
  String? _cachedTeacherSubRole;
  int? _cachedTeacherClassId;
  String _cachedAdminNip = '';

  bool get isEditing => widget.userData != null;

  bool get canChangeRole {
    if (!widget.controller.isAdmin) return false;
    if (widget.userData != null) return false;
    if (widget.allowRoleChange != null) return widget.allowRoleChange!;
    return widget.initialRole == null;
  }

  String get _dialogTitle {
    if (isEditing) {
      if (_role == 'student') return 'Edit Data Siswa';
      if (_role == 'teacher') return 'Edit Data Guru & Staf';
      if (_role == 'school_admin') return 'Edit Data Administrator';
      return 'Edit Data Pengguna';
    }
    if (canChangeRole) {
      return 'Tambah Pengguna Baru';
    }
    if (_role == 'student') return 'Tambah Siswa Baru';
    if (_role == 'teacher') return 'Tambah Guru & Staf';
    if (_role == 'school_admin') return 'Tambah Admin Baru';
    return 'Tambah Pengguna Baru';
  }

  String get _submitButtonLabel {
    if (isEditing) return 'Simpan Perubahan';
    if (canChangeRole) return 'Buat Akun Pengguna';
    if (_role == 'student') return 'Buat Akun Siswa';
    if (_role == 'teacher') return 'Buat Akun Guru';
    if (_role == 'school_admin') return 'Buat Akun Admin';
    return 'Buat Akun Pengguna';
  }

  @override
  void initState() {
    super.initState();
    final user = widget.userData;

    _nameController = TextEditingController(text: user?['name']?.toString() ?? '');
    _nipController = TextEditingController(text: user?['nip']?.toString() ?? '');
    _nisnController = TextEditingController(text: user?['nisn']?.toString() ?? '');
    _passwordController = TextEditingController();

    if (user != null) {
      _role = user['role']?.toString() ?? 'student';
      _subRole = user['sub_role']?.toString();
      _selectedClassId = user['class_major_id'] ?? user['class_id'] ?? user['class_major']?['id'];
      if (_role == 'student') {
        _cachedStudentNisn = _nisnController.text;
        _cachedStudentClassId = _selectedClassId;
      } else if (_role == 'teacher') {
        _cachedTeacherNip = _nipController.text;
        _cachedTeacherSubRole = _subRole;
        _cachedTeacherClassId = _selectedClassId;
      } else if (_role == 'school_admin') {
        _cachedAdminNip = _nipController.text;
      }
    } else {
      _role = widget.initialRole ?? 'student';
      if (_role == 'teacher') {
        _subRole = 'guru';
      }
      if (!widget.controller.isAdmin && widget.controller.isWaliKelas) {
        _role = 'student';
        _selectedClassId = widget.controller.waliKelasId;
        _cachedStudentClassId = _selectedClassId;
      }
    }

    _emailController = TextEditingController(
      text: _role == 'student' ? '' : (user?['email']?.toString() ?? ''),
    );

    if (!widget.controller.isAdmin) {
      // Non-admin (teacher) is locked strictly to student role
      _role = 'student';
      if (widget.controller.isWaliKelas && _selectedClassId == null) {
        _selectedClassId = widget.controller.waliKelasId;
        _cachedStudentClassId = _selectedClassId;
      }
    }

    _nameController.addListener(_onFieldChanged);
    _passwordController.addListener(_onFieldChanged);
    _nisnController.addListener(_onFieldChanged);
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  bool get _isFormValid {
    // 1. Nama Lengkap is required (min 3 chars)
    if (_nameController.text.trim().length < 3) return false;

    // 2. Password is required for new accounts (min 3 chars)
    if (!isEditing && _passwordController.text.trim().length < 3) return false;

    // 3. For student role: Class is required. NISN is optional, but if entered must be at least 4 digits
    if (_role == 'student') {
      final nisnTrimmed = _nisnController.text.trim();
      if (nisnTrimmed.isNotEmpty && nisnTrimmed.length < 4) return false;
      if (_selectedClassId == null) return false;
    }

    return true;
  }

  @override
  void dispose() {
    _nameController.removeListener(_onFieldChanged);
    _passwordController.removeListener(_onFieldChanged);
    _nisnController.removeListener(_onFieldChanged);
    _nameController.dispose();
    _emailController.dispose();
    _nipController.dispose();
    _nisnController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final nip = _nipController.text.trim();
    final nisn = _nisnController.text.trim();
    final password = _passwordController.text.trim();

    // 1-by-1 Class validation for student
    if (_role == 'student') {
      if (_selectedClassId == null) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = 'Silakan tentukan kelas siswa terlebih dahulu.';
        });
        return;
      }

      final targetCls = widget.controller.classes.firstWhere(
        (c) => c['id'] == _selectedClassId,
        orElse: () => <String, dynamic>{},
      );
      if (targetCls.isEmpty) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = 'Kelas yang dipilih tidak terdaftar di sistem sekolah.';
        });
        return;
      }

      final currentId = widget.userData?['id'];
      final existsInClass = widget.controller.students.any((s) {
        if (s['id'] == currentId) return false;
        final matchName = s['name']?.toString().trim().toLowerCase() == name.toLowerCase();
        final matchClass = s['class_major_id'] == _selectedClassId;
        return matchName && matchClass;
      });
      if (existsInClass) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = 'Siswa "$name" sudah terdaftar di kelas ${targetCls['name']}.';
        });
        return;
      }
    }

    final payload = <String, dynamic>{
      'name': name,
      'role': _role,
      if (_role != 'student') 'email': email.isNotEmpty ? email : null,
      if (_role == 'student') 'email': null,
    };

    if (_role == 'student') {
      payload['nisn'] = nisn.isNotEmpty ? nisn : null;
      payload['nip'] = null; // Clean up previous teacher/admin NIP
      payload['sub_role'] = null; // Clean up teacher sub-role
      payload['email'] = null; // Siswa tidak menggunakan email
      payload['class_major_id'] = _selectedClassId;
      if (isEditing && _resetDevice) {
        payload['reset_device'] = true;
      }
    } else if (_role == 'teacher') {
      payload['nip'] = nip.isNotEmpty ? nip : null;
      payload['nisn'] = null; // Clean up previous student NISN
      payload['sub_role'] = _subRole ?? 'guru';
      payload['class_major_id'] = _selectedClassId;
      // If switching from student to teacher, auto-free kiosk device bindings
      if (isEditing && widget.userData?['role'] == 'student') {
        payload['reset_device'] = true;
      }
    } else if (_role == 'school_admin') {
      payload['nip'] = nip.isNotEmpty ? nip : null;
      payload['nisn'] = null; // Clean up previous student NISN
      payload['sub_role'] = null; // Clean up teacher sub-role
      payload['class_major_id'] = null; // Admin has no class
      // If switching from student to admin, auto-free kiosk device bindings
      if (isEditing && widget.userData?['role'] == 'student') {
        payload['reset_device'] = true;
      }
    }

    if (password.isNotEmpty) {
      payload['password'] = password;
    }

    String? error;
    if (_role == 'student') {
      if (isEditing) {
        final userId = widget.userData!['id'];
        error = await widget.controller.updateStudentData(userId, payload);
      } else {
        error = await widget.controller.createStudent(payload);
      }
    } else {
      if (isEditing) {
        final userId = widget.userData!['id'];
        error = await widget.controller.updateUser(userId, payload);
      } else {
        error = await widget.controller.createUser(payload);
      }
    }

    if (mounted) {
      if (error == null) {
        Navigator.of(context).pop(true);
        AppNotification.showSuccess(
          context,
          isEditing ? 'Akun Diperbarui' : 'Akun Berhasil Dibuat',
          subtitle: 'Pengguna "$name" tersimpan di server.',
        );
      } else {
        setState(() {
          _isSubmitting = false;
          _errorMessage = error;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);

    Color themeColor;
    IconData headerIcon;
    switch (_role) {
      case 'school_admin':
        themeColor = const Color(0xFFF59E0B);
        headerIcon = Icons.admin_panel_settings_rounded;
        break;
      case 'teacher':
        themeColor = const Color(0xFF10B981);
        headerIcon = Icons.badge_rounded;
        break;
      default:
        themeColor = const Color(0xFF8B5CF6);
        headerIcon = Icons.school_rounded;
    }

    return ShieiBottomSheet(
      initialFraction: 0.62,
      maxFraction: 0.925,
      snapFractions: UserFormDialog._snapFractions,
      headerBuilder: (isFullscreen) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 16, 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: themeColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(headerIcon, color: themeColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _dialogTitle,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
            ),
          ],
        ),
      ),
      footerBuilder: (isFullscreen) {
        final isValid = _isFormValid && !_isSubmitting;

        return Row(
          children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(false),
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
                  backgroundColor: isValid
                      ? themeColor
                      : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                  foregroundColor: isValid
                      ? Colors.white
                      : (isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8)),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: isValid ? _submit : null,
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        _submitButtonLabel,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                      ),
              ),
            ),
          ],
        );
      },
      bodyBuilder: (scrollController) => SingleChildScrollView(
        controller: scrollController,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                    // Error banner
                    if (_errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFFEF4444),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // 1. Role Selector Slider (Only when canChangeRole is true)
                    if (canChangeRole) ...[
                      _buildLabel('Peran Pengguna *', isDark),
                      _buildSlidingRoleSelector(isDark),
                      const SizedBox(height: 14),
                    ] else ...[
                      _buildSingleRoleIndicator(isDark, themeColor, headerIcon),
                      const SizedBox(height: 14),
                    ],

                    // 2. Sub-Role (If teacher)
                    if (_role == 'teacher') ...[
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ShieiSelectorField<String>(
                            label: 'Penugasan / Jabatan Guru',
                            isDark: isDark,
                            prefixIcon: Icons.badge_outlined,
                            valueText: _subRole == 'kepala_sekolah'
                                ? 'Kepala Sekolah'
                                : _subRole == 'wakil_kepala_sekolah'
                                    ? 'Wakil Kepala Sekolah'
                                    : _subRole == 'karyawan'
                                        ? 'Staf TU / Karyawan'
                                        : 'Guru Pengajar',
                            onTap: () async {
                              FocusScope.of(context).unfocus();
                              final selected = await ShieiSelectSheet.show<String>(
                                context: context,
                                title: 'Pilih Penugasan Guru',
                                subtitle: 'Jabatan struktural atau fungsional guru di sekolah',
                                selectedValue: _subRole ?? 'guru',
                                items: const [
                                  ShieiSelectItem(
                                    value: 'guru',
                                    label: 'Guru Pengajar',
                                    subtitle: 'Pengajar mata pelajaran reguler',
                                    icon: Icons.school_rounded,
                                  ),
                                  ShieiSelectItem(
                                    value: 'kepala_sekolah',
                                    label: 'Kepala Sekolah',
                                    subtitle: 'Pimpinan tertinggi satuan pendidikan',
                                    icon: Icons.account_balance_rounded,
                                  ),
                                  ShieiSelectItem(
                                    value: 'wakil_kepala_sekolah',
                                    label: 'Wakil Kepala Sekolah',
                                    subtitle: 'Kurikulum / Kesiswaan / Sarpras / Humas',
                                    icon: Icons.assignment_ind_rounded,
                                  ),
                                  ShieiSelectItem(
                                    value: 'karyawan',
                                    label: 'Staf TU / Karyawan',
                                    subtitle: 'Tenaga kependidikan dan administrasi',
                                    icon: Icons.badge_rounded,
                                  ),
                                ],
                              );
                              if (mounted && selected != null) {
                                setState(() => _subRole = selected);
                              }
                            },
                          ),
                          const SizedBox(height: 14),
                        ],
                      ),
                    ],

                    // 3. Nama Lengkap
                    _buildLabel('Nama Lengkap *', isDark),
                    TextFormField(
                      controller: _nameController,
                      inputFormatters: [LengthLimitingTextInputFormatter(255)],
                      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                      style: TextStyle(color: isDark ? Colors.white : const Color(0xFF0F172A), fontSize: 13.5),
                      decoration: _buildInputDecoration(
                        hint: 'Nama lengkap tanpa gelar atau sesuai data resmi',
                        icon: Icons.person_rounded,
                        isDark: isDark,
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Nama lengkap wajib diisi';
                        final trimmed = v.trim();
                        if (trimmed.length < 3) return 'Nama lengkap minimal 3 karakter';
                        if (trimmed.length > 255) return 'Nama lengkap maksimal 255 karakter';
                        final lowerName = trimmed.toLowerCase();
                        final currentId = widget.userData?['id'];

                        if (_role == 'student') {
                          final dupStudent = widget.controller.students.firstWhere(
                            (s) => s['id'] != currentId && s['name']?.toString().trim().toLowerCase() == lowerName,
                            orElse: () => <String, dynamic>{},
                          );
                          if (dupStudent.isNotEmpty) {
                            final cls = dupStudent['class_major']?['name']?.toString() ??
                                dupStudent['classes']?['name']?.toString() ??
                                '';
                            return cls.isNotEmpty
                                ? 'Nama siswa sudah terdaftar di kelas $cls'
                                : 'Nama siswa ini sudah terdaftar di sistem sekolah';
                          }
                        } else if (_role == 'teacher') {
                          final dupTeacher = widget.controller.allUsers.firstWhere(
                            (u) => u['id'] != currentId && (u['role'] == 'teacher') && u['name']?.toString().trim().toLowerCase() == lowerName,
                            orElse: () => <String, dynamic>{},
                          );
                          if (dupTeacher.isNotEmpty) {
                            return 'Nama guru/staf sudah terdaftar di sistem sekolah';
                          }
                        } else if (_role == 'school_admin') {
                          final dupAdmin = widget.controller.allUsers.firstWhere(
                            (u) => u['id'] != currentId && (u['role'] == 'school_admin') && u['name']?.toString().trim().toLowerCase() == lowerName,
                            orElse: () => <String, dynamic>{},
                          );
                          if (dupAdmin.isNotEmpty) {
                            return 'Nama administrator sudah terdaftar di sistem sekolah';
                          }
                        }

                        return null;
                      },
                    ),
                    const SizedBox(height: 14),

                    // 4. Identitas (NISN for student, NIP for teacher/admin)
                    if (_role == 'student') ...[
                      _buildLabel('NISN Siswa (Opsional)', isDark, badge: '${_nisnController.text.length}/10 digit'),
                      TextFormField(
                        controller: _nisnController,
                        keyboardType: TextInputType.number,
                        maxLength: 10,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(10),
                        ],
                        onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                        style: TextStyle(color: isDark ? Colors.white : const Color(0xFF0F172A), fontSize: 13.5),
                        decoration: _buildInputDecoration(
                          hint: '10 digit angka NISN...',
                          icon: Icons.tag_rounded,
                          isDark: isDark,
                          counterText: '',
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return null;
                          final raw = v.trim();
                          if (!RegExp(r'^[0-9]+$').hasMatch(raw)) return 'NISN harus berupa angka';
                          final clean = raw.replaceAll(RegExp(r'\D'), '');
                          if (clean.length < 4 || clean.length > 10) return 'NISN harus 4–10 digit angka';
                          final currentId = widget.userData?['id'];
                          final dupStudent = widget.controller.students.firstWhere(
                            (s) {
                              if (s['id'] == currentId) return false;
                              final sNisn = s['nisn']?.toString().replaceAll(RegExp(r'\D'), '');
                              return sNisn != null && sNisn.isNotEmpty && sNisn == clean;
                            },
                            orElse: () => <String, dynamic>{},
                          );
                          if (dupStudent.isNotEmpty) {
                            final cls = dupStudent['class_major']?['name']?.toString() ??
                                dupStudent['classes']?['name']?.toString() ??
                                '';
                            return cls.isNotEmpty
                                ? 'NISN "$clean" sudah terdaftar di kelas $cls'
                                : 'NISN "$clean" sudah terdaftar di sistem sekolah';
                          }
                          final dupUser = widget.controller.allUsers.firstWhere(
                            (u) {
                              if (u['id'] == currentId) return false;
                              return u['role'] == 'student' && u['nisn']?.toString().replaceAll(RegExp(r'\D'), '') == clean;
                            },
                            orElse: () => <String, dynamic>{},
                          );
                          if (dupUser.isNotEmpty) {
                            return 'NISN "$clean" sudah terdaftar di sistem sekolah';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                    ] else ...[
                      _buildLabel('NIP Pegawai (Opsional)', isDark, badge: '${_nipController.text.length}/18 digit'),
                      TextFormField(
                        controller: _nipController,
                        keyboardType: TextInputType.number,
                        maxLength: 18,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(18),
                        ],
                        onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                        style: TextStyle(color: isDark ? Colors.white : const Color(0xFF0F172A), fontSize: 13.5),
                        decoration: _buildInputDecoration(
                          hint: '18 digit angka NIP...',
                          icon: Icons.badge_outlined,
                          isDark: isDark,
                          counterText: '',
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return null;
                          final raw = v.trim();
                          if (!RegExp(r'^[0-9]+$').hasMatch(raw)) return 'NIP harus berupa angka';
                          final clean = raw.replaceAll(RegExp(r'\D'), '');
                          if (clean.length < 4 || clean.length > 18) return 'NIP maksimal 18 digit angka';
                          final currentId = widget.userData?['id'];
                          final dup = widget.controller.allUsers.firstWhere(
                            (u) {
                              if (u['id'] == currentId) return false;
                              final uNip = u['nip']?.toString().replaceAll(RegExp(r'\D'), '');
                              return uNip != null && uNip.isNotEmpty && uNip == clean;
                            },
                            orElse: () => <String, dynamic>{},
                          );
                          if (dup.isNotEmpty) {
                            return 'NIP "$clean" sudah terdaftar di sistem sekolah';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                    ],

                    // 5. Kelas (Only for student and teacher)
                    if (_role != 'school_admin') ...[
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ShieiSelectorField<int?>(
                            label: _role == 'student' ? 'Kelas Siswa *' : 'Wali Kelas (Opsional)',
                            isDark: isDark,
                            prefixIcon: Icons.class_outlined,
                            valueText: _selectedClassId == null
                                ? (_role == 'student' ? 'Pilih Kelas Siswa' : 'Bukan Wali Kelas')
                                : widget.controller.classes.firstWhere(
                                    (c) => c['id'] == _selectedClassId,
                                    orElse: () => {'name': 'Kelas #$_selectedClassId'},
                                  )['name'],
                            onTap: !widget.controller.isAdmin
                                ? null
                                : () async {
                              FocusScope.of(context).unfocus();
                              final selected = await ShieiSelectSheet.show<int?>(
                                context: context,
                                title: _role == 'student' ? 'Pilih Kelas Siswa' : 'Pilih Kelas Binaan Wali Kelas',
                                subtitle: 'Tentukan kelas dari data kelas resmi sekolah',
                                selectedValue: _selectedClassId,
                                items: [
                                  ShieiSelectItem<int?>(
                                    value: null,
                                    label: _role == 'student' ? '-- Belum Ditentukan --' : '-- Bukan Wali Kelas --',
                                    subtitle: _role == 'student' ? 'Kelas belum diatur' : 'Tidak ditugaskan sebagai wali kelas',
                                    icon: Icons.remove_circle_outline_rounded,
                                  ),
                                  ...widget.controller.classes.map((c) {
                                    return ShieiSelectItem<int?>(
                                      value: c['id'] as int?,
                                      label: c['name']?.toString() ?? 'Kelas',
                                      subtitle: 'Kelas Sekolah',
                                      icon: Icons.school_rounded,
                                    );
                                  }),
                                ],
                              );
                              if (mounted && selected != _selectedClassId) {
                                setState(() => _selectedClassId = selected);
                              }
                            },
                          ),
                          if (!widget.controller.isAdmin)
                            Padding(
                              padding: const EdgeInsets.only(top: 6, left: 4),
                              child: Text(
                                'Kelas terkunci pada kelas yang Anda ampu sebagai wali kelas.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          const SizedBox(height: 14),
                        ],
                      ),
                    ],

                    // 6. Email (Opsional) - Khusus Guru dan Admin, tidak untuk Siswa
                    if (_role != 'student') ...[
                      _buildLabel('Email (Opsional)', isDark),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        inputFormatters: [LengthLimitingTextInputFormatter(255)],
                        onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                        style: TextStyle(color: isDark ? Colors.white : const Color(0xFF0F172A), fontSize: 13.5),
                        decoration: _buildInputDecoration(
                          hint: 'nama@sekolah.sch.id',
                          icon: Icons.email_outlined,
                          isDark: isDark,
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return null;
                          final email = v.trim().toLowerCase();
                          if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
                            return 'Format email tidak valid (contoh: user@sekolah.sch.id)';
                          }
                          final currentId = widget.userData?['id'];
                          final dup = widget.controller.allUsers.firstWhere(
                            (u) {
                              if (u['id'] == currentId) return false;
                              return u['email']?.toString().trim().toLowerCase() == email;
                            },
                            orElse: () => <String, dynamic>{},
                          );
                          if (dup.isNotEmpty) {
                            return 'Email "$email" sudah digunakan oleh akun lain';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                    ],

                    // 7. Password
                    _buildLabel(
                      isEditing ? 'Kata Sandi Baru (Kosongkan jika tidak ingin diubah)' : 'Kata Sandi Masuk *',
                      isDark,
                    ),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      inputFormatters: [LengthLimitingTextInputFormatter(100)],
                      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                      style: TextStyle(color: isDark ? Colors.white : const Color(0xFF0F172A), fontSize: 13.5),
                      decoration: _buildInputDecoration(
                        hint: isEditing ? 'Biarkan kosong untuk mempertahankan sandi lama' : 'Minimal 3 karakter',
                        icon: Icons.lock_outline_rounded,
                        isDark: isDark,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                            size: 19,
                            color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                          ),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      validator: (v) {
                        if (!isEditing && (v == null || v.trim().length < 3)) {
                          return 'Kata sandi login awal minimal 3 karakter';
                        }
                        if (isEditing && v != null && v.isNotEmpty && v.trim().length < 3) {
                          return 'Kata sandi baru minimal 3 karakter';
                        }
                        if (v != null && v.trim().length > 100) {
                          return 'Kata sandi maksimal 100 karakter';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),

                    // 8. Device Reset Checkbox (If editing student)
                    if (isEditing && _role == 'student') ...[
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ShieiCheckboxTile(
                            value: _resetDevice,
                            isDark: isDark,
                            activeColor: const Color(0xFF8B5CF6),
                            icon: Icons.phonelink_erase_rounded,
                            title: 'Reset Kunci Perangkat HP Siswa',
                            subtitle: 'Lepaskan binding serial HP sehingga siswa bisa login di HP baru.',
                            onChanged: (val) => setState(() => _resetDevice = val ?? false),
                          ),
                          const SizedBox(height: 10),
                        ],
                      ),
                    ],

                          ],
                        ),
                      ),
                    ),
                  );
  }

  Widget _buildLabel(String text, bool isDark, {String? badge}) {
    final isRequired = text.endsWith('*') || text.contains('*');
    final cleanText = text.replaceAll('*', '').trim();

    final labelWidget = isRequired
        ? RichText(
            text: TextSpan(
              text: cleanText,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
                fontFamily: 'Inter',
              ),
              children: const [
                TextSpan(
                  text: ' *',
                  style: TextStyle(
                    color: Color(0xFFEA580C),
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          )
        : Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
            ),
          );

    if (badge != null && badge.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            labelWidget,
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isDark ? const Color(0xFF475569) : const Color(0xFFE2E8F0),
                  width: 0.8,
                ),
              ),
              child: Text(
                badge,
                style: TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: labelWidget,
    );
  }

  static const List<_RoleOption> _roleOptions = [
    _RoleOption(
      role: 'student',
      label: 'Siswa',
      icon: Icons.school_rounded,
      color: Color(0xFF8B5CF6),
    ),
    _RoleOption(
      role: 'teacher',
      label: 'Guru',
      icon: Icons.badge_rounded,
      color: Color(0xFF10B981),
    ),
    _RoleOption(
      role: 'school_admin',
      label: 'Admin',
      icon: Icons.admin_panel_settings_rounded,
      color: Color(0xFFF59E0B),
    ),
  ];

  void _onSelectRole(String newRole) {
    if (_role == newRole) return;
    HapticFeedback.lightImpact();

    FocusScope.of(context).unfocus();
    // Cache current form values before switching
    if (_role == 'student') {
      _cachedStudentNisn = _nisnController.text.trim();
      _cachedStudentClassId = _selectedClassId;
    } else if (_role == 'teacher') {
      _cachedTeacherNip = _nipController.text.trim();
      _cachedTeacherSubRole = _subRole;
      _cachedTeacherClassId = _selectedClassId;
    } else if (_role == 'school_admin') {
      _cachedAdminNip = _nipController.text.trim();
    }

    setState(() {
      _role = newRole;

      // Auto-switch & clean up fields of previous role
      if (newRole == 'student') {
        _nisnController.text = _cachedStudentNisn;
        _nipController.clear();
        _emailController.clear();
        _subRole = null;
        _selectedClassId = _cachedStudentClassId;
      } else if (newRole == 'teacher') {
        _nipController.text = _cachedTeacherNip.isNotEmpty ? _cachedTeacherNip : _cachedAdminNip;
        _nisnController.clear();
        _subRole = _cachedTeacherSubRole ?? 'guru';
        _selectedClassId = _cachedTeacherClassId;
      } else if (newRole == 'school_admin') {
        _nipController.text = _cachedAdminNip.isNotEmpty ? _cachedAdminNip : _cachedTeacherNip;
        _nisnController.clear();
        _subRole = null;
        _selectedClassId = null; // Admin has no class
      }
    });
  }

  Widget _buildSingleRoleIndicator(bool isDark, Color themeColor, IconData headerIcon) {
    String roleName = 'Siswa';
    String roleDesc = 'Hak akses akun peserta ujian sekolah';

    if (!widget.controller.isAdmin && widget.controller.isWaliKelas) {
      roleDesc = 'Sebagai Wali Kelas ${widget.controller.waliKelasName ?? ""}, Anda mengelola data siswa.';
    } else if (!widget.controller.isAdmin) {
      roleDesc = 'Sebagai Guru Pengajar, Anda mengelola data siswa.';
    } else if (_role == 'teacher') {
      roleName = 'Guru & Tenaga Pendidik';
      roleDesc = 'Hak akses pembuatan jadwal ujian & pengawas';
    } else if (_role == 'school_admin') {
      roleName = 'Administrator Sekolah';
      roleDesc = 'Hak akses penuh konfigurasi portal sekolah';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: themeColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: themeColor.withValues(alpha: 0.22),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: themeColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(headerIcon, color: themeColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Peran: ',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                      ),
                    ),
                    Text(
                      roleName,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: themeColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  roleDesc,
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
    );
  }

  Widget _buildSlidingRoleSelector(bool isDark) {
    final selectedIndex = _roleOptions.indexWhere((opt) => opt.role == _role);
    final activeIndex = selectedIndex == -1 ? 0 : selectedIndex;
    final activeOption = _roleOptions[activeIndex];

    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF334155).withValues(alpha: 0.6) : const Color(0xFFE2E8F0),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final totalWidth = constraints.maxWidth;
          final itemWidth = totalWidth / _roleOptions.length;
          final thumbLeft = activeIndex * itemWidth;

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (velocity > 150 && activeIndex < _roleOptions.length - 1) {
                // Swiped right -> next role
                _onSelectRole(_roleOptions[activeIndex + 1].role);
              } else if (velocity < -150 && activeIndex > 0) {
                // Swiped left -> prev role
                _onSelectRole(_roleOptions[activeIndex - 1].role);
              }
            },
            child: Stack(
              children: [
                // Sliding Pill Indicator
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  left: thumbLeft,
                  top: 0,
                  bottom: 0,
                  width: itemWidth,
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF334155) : Colors.white,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                        color: isDark
                            ? activeOption.color.withValues(alpha: 0.35)
                            : activeOption.color.withValues(alpha: 0.2),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: activeOption.color.withValues(alpha: isDark ? 0.22 : 0.12),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
                          blurRadius: 3,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ),

                // Interactive Role Buttons
                Row(
                  children: _roleOptions.asMap().entries.map((entry) {
                    final index = entry.key;
                    final option = entry.value;
                    final isSelected = activeIndex == index;

                    return Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _onSelectRole(option.role),
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOut,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12.5,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                              color: isSelected
                                  ? (isDark ? Colors.white : option.color)
                                  : (isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  option.icon,
                                  size: 15,
                                  color: isSelected
                                      ? option.color
                                      : (isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
                                ),
                                const SizedBox(width: 5),
                                Text(option.label),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  InputDecoration _buildInputDecoration({
    required String hint,
    required IconData icon,
    required bool isDark,
    String? counterText = '',
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        fontSize: 12.5,
        color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
      ),
      prefixIcon: Icon(icon, size: 19, color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      counterText: counterText,
      errorMaxLines: 3,
      errorStyle: const TextStyle(
        fontSize: 11.5,
        height: 1.3,
        color: Color(0xFFEF4444),
        fontWeight: FontWeight.w500,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
        ),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: Color(0xFF8B5CF6), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
      ),
    );
  }
}
