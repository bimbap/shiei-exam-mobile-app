import 'dart:convert';
import 'dart:io';
import 'package:excel/excel.dart' hide Border, TextSpan;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_notification.dart';
import '../../../../shared/widgets/shiei_bottom_sheet.dart';
import '../../../../shared/widgets/shiei_select_sheet.dart';
import '../teacher_portal_controller.dart';

/// Modal bottom sheet for bulk adding students, teachers, or users
/// with systematic multi-column Excel/CSV alignment (Column A: Name, Column B: NISN/NIP, Column C: Class/Role, Column D: Password).
class BulkAddDialog extends StatefulWidget {
  final String category; // 'students', 'teachers', 'users'
  final TeacherPortalController controller;

  const BulkAddDialog({
    super.key,
    required this.category,
    required this.controller,
  });

  static Future<bool?> show({
    required BuildContext context,
    required String category,
    required TeacherPortalController controller,
  }) async {
    await ShieiSelectSheet.dismissKeyboardIfNeeded(context);
    if (!context.mounted) return null;

    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => BulkAddDialog(
        category: category,
        controller: controller,
      ),
    );
  }

  @override
  State<BulkAddDialog> createState() => _BulkAddDialogState();
}

class _BulkAddDialogState extends State<BulkAddDialog> {
  final TextEditingController _rawTextController = TextEditingController();
  final TextEditingController _defaultPasswordController = TextEditingController(text: '123456');

  int? _selectedClassId;
  String _selectedSubRole = 'guru';
  String _selectedUserRole = 'student';

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (widget.category == 'students' || widget.category == 'users') {
      if (widget.controller.selectedClassId != null) {
        _selectedClassId = widget.controller.selectedClassId;
      } else if (widget.controller.isWaliKelas && widget.controller.waliKelasId != null) {
        _selectedClassId = widget.controller.waliKelasId;
      } else if (widget.controller.classes.isNotEmpty) {
        _selectedClassId = widget.controller.classes.first['id'] as int?;
      }
    }

    _rawTextController.addListener(_onFieldChanged);
    _defaultPasswordController.addListener(_onFieldChanged);
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _rawTextController.removeListener(_onFieldChanged);
    _defaultPasswordController.removeListener(_onFieldChanged);
    _rawTextController.dispose();
    _defaultPasswordController.dispose();
    super.dispose();
  }

  /// Resolve classes map from controller with normalized keys and official object
  Map<String, Map<String, dynamic>> _buildClassLookup() {
    final map = <String, Map<String, dynamic>>{};
    for (final c in widget.controller.classes) {
      final name = c['name']?.toString().trim();
      final id = c['id'] as int?;
      if (name != null && id != null) {
        final entry = {'id': id, 'name': name};
        map[name.toLowerCase()] = entry;
        map[name.toLowerCase().replaceAll(RegExp(r'\s+'), '')] = entry;
        map[id.toString()] = entry;
      }
    }
    return map;
  }

  /// Systematically parse line-by-line inputs according to column rules with real-time validation
  List<Map<String, dynamic>> _parseLines() {
    final text = _rawTextController.text.trim();
    if (text.isEmpty) return [];

    final lines = text.split(RegExp(r'\r?\n'));
    final results = <Map<String, dynamic>>[];
    final classLookup = _buildClassLookup();

    final defaultPass = _defaultPasswordController.text.trim().isNotEmpty
        ? _defaultPasswordController.text.trim()
        : (widget.category == 'students'
            ? 'siswa123'
            : (widget.category == 'teachers' ? 'guru123' : '123456'));

    // 1. Pre-build database sets for anti-duplicate matching (Nama, NISN, NIP, Email, Username, and Class)
    final dbStudentNames = <String>{};
    final dbStudentNameToClass = <String, String>{};
    final dbStudentNisns = <String>{};
    final dbStudentNisnToClass = <String, String>{};
    final dbTeacherNames = <String>{};
    final dbAdminNames = <String>{};
    final dbTeacherNips = <String>{};
    final dbEmails = <String>{};
    final dbUsernames = <String>{};

    for (final s in widget.controller.students) {
      final name = s['name']?.toString().trim();
      final nisn = s['nisn']?.toString().trim();
      final username = s['username']?.toString().trim();
      final cmId = s['class_major_id']?.toString();
      final matchedCls = cmId != null ? classLookup[cmId] : null;
      final className = s['class_major']?['name']?.toString() ??
          s['classes']?['name']?.toString() ??
          matchedCls?['name']?.toString() ??
          '';

      if (name != null && name.isNotEmpty) {
        final lowerName = name.toLowerCase();
        dbStudentNames.add(lowerName);
        if (className.isNotEmpty) {
          dbStudentNameToClass[lowerName] = className;
        }
      }
      if (nisn != null && nisn.isNotEmpty && nisn != '-') {
        final clean = nisn.replaceAll(RegExp(r'\D'), '');
        if (clean.isNotEmpty) {
          dbStudentNisns.add(clean);
          if (className.isNotEmpty) {
            dbStudentNisnToClass[clean] = className;
          }
        }
      }
      if (username != null && username.isNotEmpty && username != '-') {
        dbUsernames.add(username.toLowerCase());
      }
    }

    for (final t in widget.controller.teachers) {
      final name = t['name']?.toString().trim();
      final nip = t['nip']?.toString().trim();
      final email = t['email']?.toString().trim().toLowerCase();
      final username = t['username']?.toString().trim();
      if (name != null && name.isNotEmpty) {
        dbTeacherNames.add(name.toLowerCase());
      }
      if (nip != null && nip.isNotEmpty && nip != '-') {
        dbTeacherNips.add(nip.replaceAll(RegExp(r'\D'), ''));
      }
      if (email != null && email.isNotEmpty && email.contains('@')) {
        dbEmails.add(email);
      }
      if (username != null && username.isNotEmpty && username != '-') {
        dbUsernames.add(username.toLowerCase());
      }
    }

    for (final u in widget.controller.allUsers) {
      final name = u['name']?.toString().trim();
      final nisn = u['nisn']?.toString().trim();
      final nip = u['nip']?.toString().trim();
      final email = u['email']?.toString().trim().toLowerCase();
      final username = u['username']?.toString().trim();
      final role = u['role']?.toString().toLowerCase() ?? '';
      final cmId = u['class_major_id']?.toString();
      final matchedCls = cmId != null ? classLookup[cmId] : null;
      final className = u['class_major']?['name']?.toString() ??
          u['classes']?['name']?.toString() ??
          matchedCls?['name']?.toString() ??
          '';

      if (name != null && name.isNotEmpty) {
        final lowerName = name.toLowerCase();
        if (role == 'student') {
          dbStudentNames.add(lowerName);
          if (className.isNotEmpty) dbStudentNameToClass[lowerName] = className;
        } else if (role == 'teacher') {
          dbTeacherNames.add(lowerName);
        } else if (role == 'school_admin' || role == 'admin') {
          dbAdminNames.add(lowerName);
        }
      }
      if (nisn != null && nisn.isNotEmpty && nisn != '-') {
        final clean = nisn.replaceAll(RegExp(r'\D'), '');
        if (clean.isNotEmpty) {
          dbStudentNisns.add(clean);
          if (className.isNotEmpty) dbStudentNisnToClass[clean] = className;
        }
      }
      if (nip != null && nip.isNotEmpty && nip != '-') {
        final clean = nip.replaceAll(RegExp(r'\D'), '');
        if (clean.isNotEmpty) dbTeacherNips.add(clean);
      }
      if (email != null && email.isNotEmpty && email.contains('@')) {
        dbEmails.add(email);
      }
      if (username != null && username.isNotEmpty && username != '-') {
        dbUsernames.add(username.toLowerCase());
      }
    }

    // 2. In-input duplicate trackers
    final seenNamesByRole = <String, Set<String>>{
      'student': {},
      'teacher': {},
      'school_admin': {},
    };
    final seenNisns = <String>{};
    final seenNips = <String>{};
    final seenEmails = <String>{};
    final seenUsernames = <String>{};

    int rowIndex = 0;
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty ||
          trimmed.startsWith('#') ||
          trimmed.startsWith('//') ||
          trimmed.toLowerCase().startsWith('sep=') ||
          trimmed.replaceAll(RegExp(r'[,;\t\s]'), '').isEmpty) {
        continue;
      }

      // Check header row skips
      final lower = trimmed.toLowerCase();
      if (lower.startsWith('nama') ||
          lower.startsWith('name') ||
          lower.startsWith('full name') ||
          lower == 'header') {
        continue;
      }

      // Detect separator: Tab (Excel paste), Semicolon, or Comma (CSV)
      List<String> rawParts;
      if (trimmed.contains('\t')) {
        rawParts = trimmed.split('\t');
      } else if (trimmed.contains(';')) {
        rawParts = trimmed.split(';');
      } else {
        rawParts = trimmed.split(',');
      }

      // Strip quotes and trim each column cell
      final parts = rawParts.map((p) => p.replaceAll(RegExp(r'^["\s]+|["\s]+$'), '')).toList();
      if (parts.isEmpty) continue;

      final firstCol = parts[0];
      if (firstCol.isEmpty) continue;

      // Skip header if detected in column contents
      final col0Lower = firstCol.toLowerCase();
      final col1Lower = parts.length > 1 ? parts[1].toLowerCase() : '';
      if (col0Lower == 'nama' ||
          col0Lower == 'name' ||
          col1Lower == 'nisn' ||
          col1Lower == 'nip' ||
          col1Lower == 'email') {
        continue;
      }

      rowIndex++;
      final name = firstCol;
      String? error;

      if (widget.category == 'students') {
        // Kolom A: Nama Lengkap
        // Kolom B: NISN
        // Kolom C: Kelas (Nama Kelas)
        // Kolom D: Password Default
        final rawNisn = parts.length > 1 && parts[1].isNotEmpty ? parts[1] : null;
        final rawClass = parts.length > 2 && parts[2].isNotEmpty ? parts[2] : null;
        final customPass = parts.length > 3 && parts[3].isNotEmpty ? parts[3] : defaultPass;

        String? cleanNisn;
        if (rawNisn != null && rawNisn != '-') {
          cleanNisn = rawNisn.replaceAll(RegExp(r'\D'), '');
          if (cleanNisn.isEmpty) cleanNisn = rawNisn.trim();
        }

        final errors = <String>[];
        final seenNames = seenNamesByRole['student']!;

        // --- 1. CEK ANTI-DUPLIKAT NAMA (Cek 1 by 1) ---
        final lowerName = name.toLowerCase();
        if (name.isEmpty) {
          errors.add('Nama lengkap siswa wajib diisi');
        } else {
          if (seenNames.contains(lowerName)) {
            errors.add('Nama duplikat dalam baris teks');
          } else if (dbStudentNames.contains(lowerName)) {
            final existCls = dbStudentNameToClass[lowerName];
            errors.add(existCls != null && existCls.isNotEmpty
                ? 'Nama sudah terdaftar (kelas $existCls)'
                : 'Nama sudah terdaftar di sekolah ini');
          }
          seenNames.add(lowerName);
        }

        // --- 2. CEK ANTI-DUPLIKAT NISN (Cek 1 by 1) ---
        if (cleanNisn != null && cleanNisn.isNotEmpty && cleanNisn != '-') {
          if (!RegExp(r'^\d+$').hasMatch(cleanNisn)) {
            errors.add('NISN harus berupa angka');
          } else if (cleanNisn.length < 4 || cleanNisn.length > 10) {
            errors.add('NISN harus 4–10 digit angka');
          } else {
            if (seenNisns.contains(cleanNisn)) {
              errors.add('NISN duplikat dalam baris teks');
            } else if (dbStudentNisns.contains(cleanNisn)) {
              final existCls = dbStudentNisnToClass[cleanNisn];
              errors.add(existCls != null && existCls.isNotEmpty
                  ? 'NISN sudah digunakan (kelas $existCls)'
                  : 'NISN sudah digunakan di sistem');
            }
            seenNisns.add(cleanNisn);
          }
        }

        // --- 3. CEK KELAS (Cek 1 by 1) ---
        int? matchedClassId;
        String? matchedClassName;

        if (rawClass != null && rawClass.isNotEmpty && rawClass != '-') {
          final norm = rawClass.toLowerCase().trim();
          final normNoSpace = norm.replaceAll(RegExp(r'\s+'), '');
          final matched = classLookup[norm] ?? classLookup[normNoSpace] ?? classLookup[rawClass.trim()];
          if (matched != null) {
            matchedClassId = matched['id'] as int?;
            matchedClassName = matched['name'] as String?;
          } else {
            errors.add('Kelas "$rawClass" tidak terdaftar di sistem');
          }
        } else {
          // Fallback to default class selector
          if (_selectedClassId != null) {
            matchedClassId = _selectedClassId;
            final defClass = widget.controller.classes.firstWhere(
              (c) => c['id'] == _selectedClassId,
              orElse: () => <String, dynamic>{},
            );
            matchedClassName = defClass['name']?.toString() ?? 'Kelas #$_selectedClassId';
          } else {
            errors.add('Kelas siswa belum diisi');
          }
        }

        final error = errors.isNotEmpty ? errors.join(', ') : null;

        results.add({
          'index': rowIndex,
          'name': name,
          if (cleanNisn != null) 'nisn': cleanNisn,
          if (matchedClassId != null) 'class_major_id': matchedClassId,
          'class_name': matchedClassName ?? rawClass ?? 'Tanpa Kelas',
          'password': customPass,
          'is_valid': errors.isEmpty,
          'error': error,
          'errors': errors,
          'status': error ?? 'Siap',
        });
      } else if (widget.category == 'teachers') {
        // Kolom A: Nama Lengkap
        // Kolom B: NIP atau Email
        // Kolom C: Penugasan (Guru / Karyawan / Staf)
        // Kolom D: Password Default
        final rawNipOrEmail = parts.length > 1 && parts[1].isNotEmpty ? parts[1] : null;
        final isEmail = rawNipOrEmail != null && rawNipOrEmail.contains('@');
        final rawSubRole = parts.length > 2 && parts[2].isNotEmpty ? parts[2].toLowerCase() : null;

        String subRole = _selectedSubRole;
        if (rawSubRole != null) {
          if (rawSubRole.contains('karyawan') ||
              rawSubRole.contains('staf') ||
              rawSubRole.contains('staff') ||
              rawSubRole.contains('tu')) {
            subRole = 'karyawan';
          } else if (rawSubRole.contains('guru')) {
            subRole = 'guru';
          }
        }
        final customPass = parts.length > 3 && parts[3].isNotEmpty ? parts[3] : defaultPass;

        // Check name anti-duplicate
        final seenNames = seenNamesByRole['teacher']!;
        if (name.isEmpty) {
          error = 'Nama lengkap guru/staf wajib diisi';
        } else if (seenNames.contains(name.toLowerCase())) {
          error = 'Nama "$name" duplikat dalam baris teks';
        } else if (dbTeacherNames.contains(name.toLowerCase())) {
          error = 'Nama "$name" sudah terdaftar di sistem sekolah';
        } else {
          seenNames.add(name.toLowerCase());
        }

        String? cleanNip;
        String? cleanEmail;

        if (rawNipOrEmail != null && rawNipOrEmail != '-') {
          if (isEmail) {
            cleanEmail = rawNipOrEmail.trim().toLowerCase();
            if (error == null) {
              if (seenEmails.contains(cleanEmail)) {
                error = 'Email "$cleanEmail" duplikat dalam teks';
              } else if (dbEmails.contains(cleanEmail)) {
                error = 'Email "$cleanEmail" sudah terdaftar di sistem';
              } else {
                seenEmails.add(cleanEmail);
              }
            }
          } else {
            cleanNip = rawNipOrEmail.replaceAll(RegExp(r'\D'), '');
            if (cleanNip.isEmpty) cleanNip = rawNipOrEmail.trim();
            if (error == null) {
              if (cleanNip.length > 18) {
                error = 'NIP "$cleanNip" maksimal 18 digit angka';
              } else if (seenNips.contains(cleanNip)) {
                error = 'NIP "$cleanNip" duplikat dalam teks';
              } else if (dbTeacherNips.contains(cleanNip)) {
                error = 'NIP "$cleanNip" sudah terdaftar di sistem';
              } else {
                seenNips.add(cleanNip);
              }
            }
          }
        }

        results.add({
          'index': rowIndex,
          'name': name,
          if (cleanEmail != null) 'email': cleanEmail,
          if (cleanNip != null) 'nip': cleanNip,
          'sub_role': subRole,
          'password': customPass,
          'is_valid': error == null,
          'error': error,
          'status': error ?? 'Siap',
        });
      } else {
        // Kolom A: Nama Lengkap
        // Kolom B: Email atau Username
        // Kolom C: Peran (admin / teacher / student)
        // Kolom D: Password Default
        final rawEmailOrUser = parts.length > 1 && parts[1].isNotEmpty ? parts[1] : null;
        final rawRole = parts.length > 2 && parts[2].isNotEmpty ? parts[2].toLowerCase() : null;

        String role = _selectedUserRole;
        if (rawRole != null) {
          if (rawRole.contains('admin')) {
            role = 'school_admin';
          } else if (rawRole.contains('guru') || rawRole.contains('teacher')) {
            role = 'teacher';
          } else if (rawRole.contains('siswa') || rawRole.contains('student')) {
            role = 'student';
          }
        }
        final customPass = parts.length > 3 && parts[3].isNotEmpty ? parts[3] : defaultPass;

        // Check name anti-duplicate (peran yang sama)
        final roleSeen = seenNamesByRole.putIfAbsent(role, () => <String>{});
        final lowerName = name.toLowerCase();
        if (name.isEmpty) {
          error = 'Nama lengkap pengguna wajib diisi';
        } else if (roleSeen.contains(lowerName)) {
          final roleLabel = role == 'student' ? 'siswa' : role == 'teacher' ? 'guru' : 'admin';
          error = 'Nama "$name" duplikat untuk peran $roleLabel dalam teks';
        } else if (role == 'student' && dbStudentNames.contains(lowerName)) {
          final existCls = dbStudentNameToClass[lowerName];
          error = existCls != null && existCls.isNotEmpty
              ? 'Nama siswa "$name" sudah terdaftar di kelas $existCls'
              : 'Nama siswa "$name" sudah terdaftar di sistem';
        } else if (role == 'teacher' && dbTeacherNames.contains(lowerName)) {
          error = 'Nama guru/staf "$name" sudah terdaftar di sistem';
        } else if ((role == 'school_admin' || role == 'admin') && dbAdminNames.contains(lowerName)) {
          error = 'Nama admin "$name" sudah terdaftar di sistem';
        } else {
          roleSeen.add(lowerName);
        }

        if (rawEmailOrUser != null && rawEmailOrUser != '-') {
          final isEmail = rawEmailOrUser.contains('@');
          if (isEmail) {
            final cleanEmail = rawEmailOrUser.trim().toLowerCase();
            if (error == null) {
              if (seenEmails.contains(cleanEmail)) {
                error = 'Email "$cleanEmail" duplikat dalam teks';
              } else if (dbEmails.contains(cleanEmail)) {
                error = 'Email "$cleanEmail" sudah terdaftar di sistem';
              } else {
                seenEmails.add(cleanEmail);
              }
            }
          } else {
            final cleanUser = rawEmailOrUser.trim().toLowerCase();
            if (error == null) {
              if (seenUsernames.contains(cleanUser)) {
                error = 'Username "$cleanUser" duplikat dalam teks';
              } else if (dbUsernames.contains(cleanUser)) {
                error = 'Username "$cleanUser" sudah terdaftar di sistem';
              } else {
                seenUsernames.add(cleanUser);
              }
            }
          }
        }

        // Validate Class matching if role is student
        int? matchedClassId;
        String? matchedClassName;
        if (role == 'student') {
          if (_selectedClassId != null) {
            matchedClassId = _selectedClassId;
            final defClass = widget.controller.classes.firstWhere(
              (c) => c['id'] == _selectedClassId,
              orElse: () => <String, dynamic>{},
            );
            matchedClassName = defClass['name']?.toString() ?? 'Kelas #$_selectedClassId';
          } else {
            error ??= 'Siswa wajib memiliki kelas terdaftar';
          }
        }

        results.add({
          'index': rowIndex,
          'name': name,
          'role': role,
          'sub_role': role == 'teacher' ? 'guru' : null,
          if (role != 'student' && rawEmailOrUser != null) 'email': rawEmailOrUser,
          if (role == 'student' && rawEmailOrUser != null && !rawEmailOrUser.contains('@')) 'username': rawEmailOrUser,
          if (matchedClassId != null) 'class_major_id': matchedClassId,
          if (matchedClassName != null) 'class_name': matchedClassName,
          'password': customPass,
          'is_valid': error == null,
          'error': error,
          'status': error ?? 'Siap',
        });
      }
    }

    return results;
  }

  /// Conditional validation: ensures all rows are valid without errors and meets constraints
  bool get _isFormValid {
    if (_isSubmitting) return false;
    final parsed = _parseLines();
    if (parsed.isEmpty) return false;
    if (_defaultPasswordController.text.trim().length < 3) return false;

    // Must have at least 1 valid row, and NO invalid rows
    final validRows = parsed.where((r) => r['is_valid'] == true).toList();
    if (validRows.isEmpty) return false;

    final invalidRows = parsed.where((r) => r['is_valid'] == false).toList();
    if (invalidRows.isNotEmpty) return false;

    return true;
  }

  void _insertSample() {
    HapticFeedback.lightImpact();
    if (widget.category == 'students') {
      final sampleClass = widget.controller.classes.isNotEmpty
          ? widget.controller.classes.first['name']?.toString() ?? 'XII RPL'
          : 'XII RPL';
      _rawTextController.text =
          'Nama Lengkap,NISN,Kelas,Password Default\n'
          'Ahmad Fauzi,0071234501,$sampleClass,siswa123\n'
          'Budi Santoso,0071234502,$sampleClass,siswa123\n'
          'Citra Lestari,0071234503,$sampleClass,siswa123\n'
          'Dewi Sartika,0071234504,$sampleClass,siswa123';
    } else if (widget.category == 'teachers') {
      _rawTextController.text =
          'Nama Lengkap,NIP atau Email,Penugasan,Password Default\n'
          'Drs. Hendra Gunawan,197801012005011001,Guru,guru123\n'
          'Nurul Hidayati S.Pd,198505122010012002,Guru,guru123\n'
          'Bambang Pamungkas,bambang@sekolah.sch.id,Staf,staf123';
    } else {
      _rawTextController.text =
          'Nama Lengkap,Email atau Username,Peran,Password Default\n'
          'Admin Ujian 2,admin2@sekolah.sch.id,admin,admin123\n'
          'Pengawas Ruang A,pengawas_a@sekolah.sch.id,teacher,pass123\n'
          'Siswa Cadangan,siswa_c@sekolah.sch.id,student,siswa123';
    }
    setState(() {});
  }

  void _clearText() {
    HapticFeedback.lightImpact();
    if (_rawTextController.text.isEmpty) return;
    setState(() {
      _rawTextController.clear();
    });
    if (mounted) {
      AppNotification.showInfo(context, 'Teks baris data telah dibersihkan.');
    }
  }

  Future<void> _pickAndUploadFile() async {
    HapticFeedback.lightImpact();
    try {
      const typeGroup = XTypeGroup(
        label: 'File Excel & Dokumen Teks',
        extensions: ['xlsx', 'xls', 'csv', 'txt', 'tsv'],
      );
      final file = await openFile(acceptedTypeGroups: [typeGroup]);
      if (file == null) return;

      final lowerName = file.name.toLowerCase();
      String content = '';

      if (lowerName.endsWith('.xlsx') || lowerName.endsWith('.xls')) {
        final bytes = await file.readAsBytes();
        final excel = Excel.decodeBytes(bytes);
        final buffer = StringBuffer();

        for (final table in excel.tables.keys) {
          final sheet = excel.tables[table];
          if (sheet == null) continue;

          for (final row in sheet.rows) {
            final rowCells = row
                .map((cell) => cell?.value?.toString().trim() ?? '')
                .toList();

            // Skip completely empty rows
            if (rowCells.every((cell) => cell.isEmpty)) continue;

            buffer.writeln(rowCells.take(4).join(','));
          }

          // Stop after extracting the first valid non-empty sheet
          if (buffer.isNotEmpty) break;
        }

        content = buffer.toString().trim();
      } else {
        content = (await file.readAsString()).trim();
      }

      if (content.isNotEmpty) {
        setState(() {
          _rawTextController.text = content;
        });
        if (mounted) {
          final count = _parseLines().length;
          AppNotification.showSuccess(
            context,
            'Berhasil memuat file "${file.name}" ($count baris data terdeteksi)',
          );
        }
      } else {
        if (mounted) {
          AppNotification.showWarning(
            context,
            'File kosong atau tidak berisi baris data yang dapat dibaca.',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        AppNotification.showError(
          context,
          'Gagal membaca file: $e',
        );
      }
    }
  }

  Color _getCategoryColor() {
    if (widget.category == 'students') {
      return const Color(0xFF8B5CF6);
    } else if (widget.category == 'teachers') {
      return const Color(0xFF10B981);
    } else {
      return const Color(0xFF3B82F6);
    }
  }

  void _showDownloadTemplateSheet() {
    HapticFeedback.lightImpact();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final categoryColor = _getCategoryColor();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: categoryColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.file_download_outlined, color: categoryColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pilih Format Template',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                        Text(
                          'Unduh format tabel resmi untuk data ${widget.category}',
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
              const SizedBox(height: 18),
              // Option 1: Excel (.xlsx)
              _buildTemplateOptionTile(
                icon: Icons.table_chart_rounded,
                iconColor: const Color(0xFF10B981),
                title: 'Template Excel (.xlsx)',
                subtitle: 'Format tabel Microsoft Excel & Google Sheets (Kolom A, B, C, D)',
                badge: 'Disarankan',
                badgeColor: const Color(0xFF10B981),
                isDark: isDark,
                onTap: () {
                  Navigator.pop(ctx);
                  _downloadTemplateXlsx();
                },
              ),
              const SizedBox(height: 10),
              // Option 2: CSV (.csv)
              _buildTemplateOptionTile(
                icon: Icons.description_rounded,
                iconColor: const Color(0xFF0284C7),
                title: 'Template CSV (.csv)',
                subtitle: 'Format teks pemisah koma standar universal',
                isDark: isDark,
                onTap: () {
                  Navigator.pop(ctx);
                  _downloadTemplateCsv();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<bool> _ensureStoragePermission() async {
    try {
      const channel = MethodChannel('id.shiei/lockdown');
      final hasPerm = await channel.invokeMethod<bool>('checkStoragePermission') ?? true;
      if (!hasPerm) {
        await channel.invokeMethod<bool>('requestStoragePermission');
        await Future.delayed(const Duration(milliseconds: 350));
        final checkAgain = await channel.invokeMethod<bool>('checkStoragePermission') ?? true;
        return checkAgain;
      }
      return true;
    } catch (e) {
      debugPrint('[BulkAddDialog] Storage permission check error: $e');
      return true;
    }
  }

  Future<void> _downloadTemplateXlsx() async {
    HapticFeedback.lightImpact();

    final hasPermission = await _ensureStoragePermission();
    if (!hasPermission) {
      if (mounted) {
        AppNotification.showError(
          context,
          'Izin penyimpanan dibutuhkan untuk mengunduh template.',
        );
      }
      return;
    }

    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet() ?? 'Sheet1';
    final sheet = excel[defaultSheet];

    String filename;
    List<String> headers;
    List<List<String>> sampleRows;

    if (widget.category == 'students') {
      filename = 'template_import_siswa.xlsx';
      headers = ['Nama Lengkap', 'NISN', 'Kelas', 'Kata Sandi Default'];
      sampleRows = [
        ['Ahmad Fauzi', '0071234501', 'XII RPL', 'siswa123'],
        ['Budi Santoso', '0071234502', 'XII RPL', 'siswa123'],
        ['Citra Lestari', '0071234503', 'XI AKL', 'siswa123'],
        ['Dewi Sartika', '0071234504', 'X TKJ', 'siswa123'],
      ];
    } else if (widget.category == 'teachers') {
      filename = 'template_import_guru_staf.xlsx';
      headers = ['Nama Lengkap', 'NIP atau Email', 'Penugasan', 'Kata Sandi Default'];
      sampleRows = [
        ['Drs. Hendra Gunawan', '197801012005011001', 'Guru', 'guru123'],
        ['Nurul Hidayati S.Pd', '198505122010012002', 'Guru', 'guru123'],
        ['Bambang Pamungkas', 'bambang@sekolah.sch.id', 'Staf', 'staf123'],
      ];
    } else {
      filename = 'template_import_pengguna.xlsx';
      headers = ['Nama Lengkap', 'Email atau Username', 'Peran', 'Kata Sandi Default'];
      sampleRows = [
        ['Admin Ujian 2', 'admin2@sekolah.sch.id', 'admin', 'admin123'],
        ['Pengawas Ruang A', 'pengawas_a@sekolah.sch.id', 'teacher', 'pass123'],
        ['Siswa Cadangan', 'siswa_01', 'student', 'siswa123'],
      ];
    }

    // Append headers
    sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());
    // Append sample rows
    for (final row in sampleRows) {
      sheet.appendRow(row.map((cell) => TextCellValue(cell)).toList());
    }

    final fileBytes = excel.save();
    if (fileBytes == null) {
      if (mounted) {
        AppNotification.showError(context, 'Gagal membuat file template Excel.');
      }
      return;
    }

    final fileSaved = await _saveBytesToDownloadFolder(
      filename,
      fileBytes,
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );

    if (!mounted) return;

    if (fileSaved) {
      AppNotification.showSuccess(
        context,
        'File "$filename" berhasil disimpan di folder Download!',
      );
    } else {
      AppNotification.showError(
        context,
        'Gagal menyimpan file ke folder Download perangkat.',
      );
    }
  }

  Future<void> _downloadTemplateCsv() async {
    HapticFeedback.lightImpact();

    final hasPermission = await _ensureStoragePermission();
    if (!hasPermission) {
      if (mounted) {
        AppNotification.showError(
          context,
          'Izin penyimpanan dibutuhkan untuk mengunduh template.',
        );
      }
      return;
    }

    String filename;
    String csvContent;

    if (widget.category == 'students') {
      filename = 'template_import_siswa.csv';
      csvContent = 'Nama Lengkap,NISN,Kelas,Password Default\n'
          'Ahmad Fauzi,0071234501,XII RPL,siswa123\n'
          'Budi Santoso,0071234502,XII RPL,siswa123\n'
          'Citra Lestari,0071234503,XI AKL,siswa123\n'
          'Dewi Sartika,0071234504,X TKJ,siswa123\n';
    } else if (widget.category == 'teachers') {
      filename = 'template_import_guru_staf.csv';
      csvContent = 'Nama Lengkap,NIP atau Email,Penugasan,Password Default\n'
          'Drs. Hendra Gunawan,197801012005011001,Guru,guru123\n'
          'Nurul Hidayati S.Pd,198505122010012002,Guru,guru123\n'
          'Bambang Pamungkas,bambang@sekolah.sch.id,Staf,staf123\n';
    } else {
      filename = 'template_import_pengguna.csv';
      csvContent = 'Nama Lengkap,Email atau Username,Peran,Password Default\n'
          'Admin Ujian 2,admin2@sekolah.sch.id,admin,admin123\n'
          'Pengawas Ruang A,pengawas_a@sekolah.sch.id,teacher,pass123\n'
          'Siswa Cadangan,siswa_01,student,siswa123\n';
    }

    final fileSaved = await _saveBytesToDownloadFolder(
      filename,
      Uint8List.fromList(utf8.encode(csvContent)),
      'text/csv',
    );

    if (!mounted) return;

    if (fileSaved) {
      AppNotification.showSuccess(
        context,
        'File "$filename" berhasil disimpan di folder Download!',
      );
    } else {
      AppNotification.showError(
        context,
        'Gagal menyimpan file ke folder Download perangkat.',
      );
    }
  }

  Future<bool> _saveBytesToDownloadFolder(String filename, List<int> bytes, String mimeType) async {
    final uint8Bytes = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);

    // 1. Try native MediaStore.Downloads (Android 10+ scoped storage compliant)
    try {
      const channel = MethodChannel('id.shiei/lockdown');
      final res = await channel.invokeMethod<String>('saveFileToDownloads', {
        'filename': filename,
        'bytes': uint8Bytes,
        'mimeType': mimeType,
      });
      if (res != null && res.isNotEmpty) {
        return true;
      }
    } catch (e) {
      debugPrint('[BulkAddDialog] Native MediaStore download error: $e');
    }

    // 2. Fallback to standard external download directory
    try {
      final downloadDir = Directory('/storage/emulated/0/Download');
      if (await downloadDir.exists()) {
        final file = File('${downloadDir.path}/$filename');
        await file.writeAsBytes(uint8Bytes, flush: true);
        return true;
      }
    } catch (e) {
      debugPrint('[BulkAddDialog] Direct file write error: $e');
    }

    return false;
  }

  Future<void> _pasteFromClipboard() async {
    HapticFeedback.lightImpact();
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.trim().isNotEmpty) {
      _rawTextController.text = data.text!;
      setState(() {});
      if (mounted) {
        AppNotification.showSuccess(context, 'Data berhasil ditempel dari clipboard.');
      }
    } else {
      if (mounted) {
        AppNotification.showInfo(context, 'Clipboard kosong atau tidak berisi teks.');
      }
    }
  }

  Future<void> _copyTemplate() async {
    HapticFeedback.lightImpact();
    String template;
    if (widget.category == 'students') {
      template = "Nama Lengkap\tNISN\tKelas\tKata Sandi Default\n"
          "Ahmad Fauzi\t0071234501\tXII RPL\tsiswa123\n"
          "Budi Santoso\t0071234502\tXII RPL\tsiswa123\n"
          "Citra Lestari\t0071234503\tXI AKL\tsiswa123";
    } else if (widget.category == 'teachers') {
      template = "Nama Lengkap\tNIP atau Email\tPenugasan\tKata Sandi Default\n"
          "Drs. Hendra Gunawan\t197801012005011001\tGuru\tguru123\n"
          "Bambang Pamungkas\tbambang@sekolah.sch.id\tStaf\tstaf123";
    } else {
      template = "Nama Lengkap\tEmail atau Username\tPeran\tKata Sandi Default\n"
          "Admin Ujian 2\tadmin2@sekolah.sch.id\tadmin\tadmin123\n"
          "Pengawas Ruang A\tpengawas_a@sekolah.sch.id\tteacher\tpass123\n"
          "Siswa Cadangan\tsiswa_01\tstudent\tsiswa123";
    }
    await Clipboard.setData(ClipboardData(text: template));
    if (mounted) {
      AppNotification.showSuccess(
        context,
        'Template format kolom berhasil disalin! Anda bisa langsung paste di Microsoft Excel.',
      );
    }
  }

  Future<void> _submit() async {
    if (!_isFormValid) return;

    final parsed = _parseLines();
    final validRows = parsed.where((r) => r['is_valid'] == true).toList();
    if (validRows.isEmpty) {
      setState(() {
        _errorMessage = 'Masukkan minimal satu baris data yang valid tanpa error.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final payload = validRows.map((r) => <String, dynamic>{
      'name': r['name'],
      if (r['nisn'] != null) 'nisn': r['nisn'],
      if (r['nip'] != null) 'nip': r['nip'],
      if (r['username'] != null) 'username': r['username'],
      if (r['role'] != 'student' && r['email'] != null) 'email': r['email'],
      if (r['class_major_id'] != null) 'class_major_id': r['class_major_id'],
      if (r['class_name'] != null) 'class_name': r['class_name'],
      if (r['sub_role'] != null) 'sub_role': r['sub_role'],
      if (r['role'] != null) 'role': r['role'],
      'password': r['password'] ?? '123456',
    }).toList();

    String? err;
    if (widget.category == 'students') {
      err = await widget.controller.bulkStoreStudents(payload, defaultClassId: _selectedClassId);
    } else if (widget.category == 'teachers') {
      err = await widget.controller.bulkStoreTeachers(payload, defaultSubRole: _selectedSubRole);
    } else {
      err = await widget.controller.bulkStoreUsers(payload);
    }

    if (!mounted) return;

    if (err == null) {
      Navigator.pop(context, true);
      AppNotification.showSuccess(
        context,
        'Berhasil menambahkan ${validRows.length} data baru sekaligus.',
      );
    } else {
      setState(() {
        _isSubmitting = false;
        _errorMessage = err;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final parsed = _parseLines();
    final validRows = parsed.where((r) => r['is_valid'] == true).toList();
    final invalidRows = parsed.where((r) => r['is_valid'] == false).toList();
    final isValid = _isFormValid;

    Color categoryColor;
    String categoryTitle;
    String exampleHint;

    if (widget.category == 'students') {
      categoryColor = const Color(0xFF8B5CF6);
      categoryTitle = 'Import Siswa Massal (By Column)';
      exampleHint = 'Format per baris: Nama, NISN, Kelas, Kata Sandi\nContoh:\nAhmad Fauzi, 0071234501, XII RPL, siswa123\nBudi Santoso, 0071234502, XII RPL, siswa123';
    } else if (widget.category == 'teachers') {
      categoryColor = const Color(0xFF10B981);
      categoryTitle = 'Import Guru & Staf Massal (By Column)';
      exampleHint = 'Format per baris: Nama Lengkap, NIP/Email, Penugasan, Kata Sandi\nContoh:\nDrs. Hendra, 197801012005011001, Guru, guru123\nBambang, bambang@sekolah.sch.id, Staf, staf123';
    } else {
      categoryColor = const Color(0xFF3B82F6);
      categoryTitle = 'Import Pengguna Massal (By Column)';
      exampleHint = 'Format per baris: Nama, Email/User, Peran, Kata Sandi\nContoh:\nOperator Sesi, op1@sekolah.sch.id, admin, admin123\nSiswa Tamu, siswa_tamu, student, siswa123';
    }

    return ShieiBottomSheet(
      initialFraction: 0.72,
      maxFraction: 0.94,
      snapFractions: const [0.72, 0.94],
      headerBuilder: (isFullscreen) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: categoryColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.table_chart_rounded, color: categoryColor, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    categoryTitle,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Input terstruktur multi-kolom Excel & CSV otomatis',
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
      ),
      footerBuilder: (isFullscreen) {
        String submitLabel;
        if (_isSubmitting) {
          submitLabel = 'Menyimpan...';
        } else if (parsed.isEmpty) {
          submitLabel = 'Isi Data Terlebih Dahulu';
        } else if (invalidRows.isNotEmpty) {
          submitLabel = 'Perbaiki ${invalidRows.length} Baris Error';
        } else {
          submitLabel = 'Simpan (${validRows.length} Data Siap)';
        }

        return Row(
          children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  side: BorderSide(
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                  ),
                ),
                onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                child: const Text('Batal', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: isValid ? 1.0 : 0.5,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: invalidRows.isNotEmpty ? const Color(0xFFEF4444) : categoryColor,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                    disabledForegroundColor: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: isValid ? 2 : 0,
                  ),
                  onPressed: isValid ? _submit : null,
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Icon(
                          invalidRows.isNotEmpty ? Icons.error_outline_rounded : Icons.cloud_upload_rounded,
                          size: 18,
                        ),
                  label: Text(
                    submitLabel,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ],
        );
      },
      bodyBuilder: (scrollController) => SingleChildScrollView(
        controller: scrollController,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Error Alert if any
            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(fontSize: 12, color: Color(0xFFEF4444)),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Column Alignment System Guide
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.view_column_rounded, size: 16, color: categoryColor),
                      const SizedBox(width: 8),
                      Text(
                        'PANDUAN PEMETAAN KOLOM (BY COLUMN)',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          color: categoryColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _buildColumnBadge('Kolom A', 'Nama Lengkap *', categoryColor, isDark),
                      _buildColumnBadge(
                        'Kolom B',
                        widget.category == 'students'
                            ? 'NISN'
                            : (widget.category == 'teachers' ? 'NIP / Email' : 'Email/User'),
                        const Color(0xFF06B6D4),
                        isDark,
                      ),
                      _buildColumnBadge(
                        'Kolom C',
                        widget.category == 'students'
                            ? 'Kelas'
                            : (widget.category == 'teachers' ? 'Penugasan' : 'Peran'),
                        const Color(0xFFF59E0B),
                        isDark,
                      ),
                      _buildColumnBadge('Kolom D', 'Kata Sandi Default', const Color(0xFF10B981), isDark),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Dapat langsung disalin dari kolom Microsoft Excel / Google Sheets (otomatis terbaca via Tab atau Koma).',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),

            // Dedicated Document & Template Import Card
            Container(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.folder_shared_outlined, size: 16, color: categoryColor),
                      const SizedBox(width: 8),
                      Text(
                        'IMPORT DOKUMEN & TEMPLATE',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          color: categoryColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Primary Upload Card
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _pickAndUploadFile,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: isDark ? categoryColor.withValues(alpha: 0.12) : categoryColor.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: categoryColor.withValues(alpha: isDark ? 0.35 : 0.25),
                            width: 1.2,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: categoryColor.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(Icons.upload_file_rounded, size: 20, color: categoryColor),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Pilih File Excel (.xlsx) / CSV (.csv)',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Ekstrak baris tabel otomatis ke formulir',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 13,
                              color: categoryColor.withValues(alpha: 0.7),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Template Download & Copy Format Buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
                            side: BorderSide(
                              color: isDark ? const Color(0xFF38BDF8).withValues(alpha: 0.35) : const Color(0xFF0284C7).withValues(alpha: 0.3),
                            ),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            backgroundColor: isDark ? const Color(0xFF38BDF8).withValues(alpha: 0.08) : const Color(0xFF0284C7).withValues(alpha: 0.05),
                          ),
                          onPressed: _showDownloadTemplateSheet,
                          icon: Icon(Icons.file_download_outlined, size: 15, color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7)),
                          label: Text(
                            'Unduh Template',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
                            side: BorderSide(
                              color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                            ),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
                          ),
                          onPressed: _copyTemplate,
                          icon: Icon(Icons.copy_rounded, size: 13.5, color: isDark ? Colors.white70 : const Color(0xFF475569)),
                          label: Text(
                            'Salin Format',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white70 : const Color(0xFF475569),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Category Context Selectors
            if (widget.category == 'students') ...[
              ShieiSelectorField<int?>(
                label: 'Kelas Default Cadangan *',
                isDark: isDark,
                prefixIcon: Icons.meeting_room_outlined,
                valueText: _selectedClassId == null
                    ? 'Gunakan Kolom C (Atau Pilih Default)'
                    : widget.controller.classes.firstWhere(
                        (c) => c['id'] == _selectedClassId,
                        orElse: () => {'name': 'Kelas #$_selectedClassId'},
                      )['name']?.toString() ?? 'Kelas #$_selectedClassId',
                onTap: (!widget.controller.isAdmin && widget.controller.isWaliKelas)
                    ? null
                    : () async {
                  FocusScope.of(context).unfocus();
                  final selected = await ShieiSelectSheet.show<int?>(
                    context: context,
                    title: 'Pilih Kelas Default',
                    subtitle: 'Digunakan otomatis jika Kolom C (Kelas) pada data baris tidak diisi',
                    selectedValue: _selectedClassId,
                    items: [
                      const ShieiSelectItem<int?>(
                        value: null,
                        label: 'Otomatis dari Kolom C',
                        subtitle: 'Wajib cantumkan nama kelas di setiap baris',
                        icon: Icons.auto_awesome_rounded,
                      ),
                      ...widget.controller.classes.map((c) {
                        return ShieiSelectItem<int?>(
                          value: c['id'] as int?,
                          label: c['name']?.toString() ?? 'Kelas',
                          subtitle: 'Kelas Terdaftar',
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
              if (!widget.controller.isAdmin && widget.controller.isWaliKelas)
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
            ] else if (widget.category == 'teachers') ...[
              _buildLabel('Penugasan Default (Jika Kolom C Kosong) *', isDark),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: _buildChoiceChip(
                      label: 'Guru Pengajar',
                      isSelected: _selectedSubRole == 'guru',
                      color: const Color(0xFF10B981),
                      isDark: isDark,
                      onTap: () => setState(() => _selectedSubRole = 'guru'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildChoiceChip(
                      label: 'Staf / Karyawan',
                      isSelected: _selectedSubRole == 'karyawan',
                      color: const Color(0xFF06B6D4),
                      isDark: isDark,
                      onTap: () => setState(() => _selectedSubRole = 'karyawan'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
            ] else ...[
              _buildLabel('Peran Akun Default (Jika Kolom C Kosong) *', isDark),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: _buildChoiceChip(
                      label: 'Siswa',
                      isSelected: _selectedUserRole == 'student',
                      color: const Color(0xFF8B5CF6),
                      isDark: isDark,
                      onTap: () => setState(() => _selectedUserRole = 'student'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildChoiceChip(
                      label: 'Guru',
                      isSelected: _selectedUserRole == 'teacher',
                      color: const Color(0xFF10B981),
                      isDark: isDark,
                      onTap: () => setState(() => _selectedUserRole = 'teacher'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildChoiceChip(
                      label: 'Admin',
                      isSelected: _selectedUserRole == 'school_admin',
                      color: const Color(0xFFF59E0B),
                      isDark: isDark,
                      onTap: () => setState(() => _selectedUserRole = 'school_admin'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
            ],

            // Default Password Field
            _buildLabel('Kata Sandi Cadangan (Jika Kolom D Kosong) *', isDark),
            const SizedBox(height: 6),
            TextField(
              controller: _defaultPasswordController,
              textInputAction: TextInputAction.next,
              onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Misal: 123456 (min. 3 karakter)',
                prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
                filled: true,
                fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
            const SizedBox(height: 16),

            // Action Bar Header (Responsive Wrap to prevent overflow)
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildLabel('Daftar Baris Data *', isDark),
                    if (_rawTextController.text.trim().isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: (invalidRows.isNotEmpty ? const Color(0xFFEF4444) : categoryColor).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: (invalidRows.isNotEmpty ? const Color(0xFFEF4444) : categoryColor).withValues(alpha: 0.25),
                          ),
                        ),
                        child: Text(
                          invalidRows.isNotEmpty
                              ? '${validRows.length} siap, ${invalidRows.length} error'
                              : '${validRows.length} baris siap',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: invalidRows.isNotEmpty ? const Color(0xFFEF4444) : categoryColor,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildTextActionButton(
                      icon: Icons.content_paste_rounded,
                      label: 'Tempel',
                      color: categoryColor,
                      isDark: isDark,
                      onTap: _pasteFromClipboard,
                    ),
                    const SizedBox(width: 6),
                    _buildTextActionButton(
                      icon: Icons.data_array_rounded,
                      label: 'Contoh',
                      color: isDark ? Colors.white70 : const Color(0xFF64748B),
                      isDark: isDark,
                      onTap: _insertSample,
                    ),
                    if (_rawTextController.text.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      _buildTextActionButton(
                        icon: Icons.delete_sweep_rounded,
                        label: 'Bersihkan',
                        color: const Color(0xFFEF4444),
                        isDark: isDark,
                        onTap: _clearText,
                      ),
                    ],
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Multi-line Text Area
            TextField(
              controller: _rawTextController,
              onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
              maxLines: 7,
              minLines: 5,
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
              decoration: InputDecoration(
                hintText: exampleHint,
                hintStyle: TextStyle(
                  fontSize: 11.5,
                  fontFamily: 'sans-serif',
                  color: isDark ? const Color(0xFF475569) : const Color(0xFF94A3B8),
                ),
                suffixIcon: _rawTextController.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(
                          Icons.clear_rounded,
                          size: 16,
                          color: isDark ? Colors.white60 : const Color(0xFF94A3B8),
                        ),
                        tooltip: 'Bersihkan Teks',
                        onPressed: _clearText,
                      )
                    : null,
                filled: true,
                fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: categoryColor, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Live Column Preview & Breakdown
            _buildLiveColumnPreview(parsed, categoryColor, isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildColumnBadge(String colKey, String colName, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              colKey,
              style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            colName,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : const Color(0xFF1E293B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveColumnPreview(List<Map<String, dynamic>> parsed, Color categoryColor, bool isDark) {
    if (parsed.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline_rounded, size: 16, color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Ketik atau tempel data di atas untuk melihat pratinjau pemisahan kolom otomatis.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final validRows = parsed.where((r) => r['is_valid'] == true).toList();
    final invalidRows = parsed.where((r) => r['is_valid'] == false).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: invalidRows.isNotEmpty
              ? const Color(0xFFEF4444).withValues(alpha: 0.4)
              : categoryColor.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Summary Row
          Row(
            children: [
              Icon(
                invalidRows.isEmpty ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded,
                size: 16,
                color: invalidRows.isEmpty ? categoryColor : const Color(0xFFEF4444),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${parsed.length} Data Terdeteksi Per Kolom',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : (invalidRows.isEmpty ? categoryColor : const Color(0xFF0F172A)),
                  ),
                ),
              ),
              // Siap Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                ),
                child: Text(
                  '${validRows.length} Siap',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                ),
              ),
              // Error Badge if any
              if (invalidRows.isNotEmpty) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    '${invalidRows.length} Error',
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFEF4444)),
                  ),
                ),
              ],
            ],
          ),

          // Realtime Error Alert Banner (similar to Web Panel)
          if (invalidRows.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.25)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Ditemukan ${invalidRows.length} baris tidak valid (duplikat atau kelas tidak terdaftar). Perbaiki baris bertanda merah untuk menyimpan.',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? const Color(0xFFFCA5A5) : const Color(0xFFDC2626),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 10),

          // Scrollable list with fixed maximum height
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 250),
            child: Scrollbar(
              thumbVisibility: parsed.length > 3,
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                physics: const BouncingScrollPhysics(),
                itemCount: parsed.length,
                itemBuilder: (context, idx) {
                  final item = parsed[idx];
                  final isValid = item['is_valid'] == true;
                  final error = item['error'] as String?;
                  final rowErrors = (item['errors'] as List<dynamic>?)?.cast<String>() ?? (error != null ? [error] : <String>[]);
                  final name = item['name']?.toString() ?? '-';
                  final nisnOrNip = widget.category == 'students'
                      ? (item['nisn']?.toString() ?? 'Tanpa NISN')
                      : (item['nip']?.toString() ?? item['email']?.toString() ?? '-');
                  final classOrRole = widget.category == 'students'
                      ? (item['class_name']?.toString() ?? 'Tanpa Kelas')
                      : (widget.category == 'teachers'
                          ? (item['sub_role'] == 'karyawan' ? 'Staf' : 'Guru')
                          : (item['role']?.toString() ?? 'Siswa'));
                  final password = item['password']?.toString() ?? '123456';

                  return Container(
                    margin: EdgeInsets.only(bottom: idx == parsed.length - 1 ? 0 : 6),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: isValid
                          ? (isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC))
                          : (isDark ? const Color(0xFF7F1D1D).withValues(alpha: 0.2) : const Color(0xFFFEF2F2)),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isValid
                            ? (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0))
                            : const Color(0xFFEF4444).withValues(alpha: 0.5),
                        width: isValid ? 1 : 1.2,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Row Index Badge
                        Container(
                          width: 22,
                          height: 22,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isValid
                                ? categoryColor.withValues(alpha: 0.15)
                                : const Color(0xFFEF4444).withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '${idx + 1}',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: isValid ? categoryColor : const Color(0xFFEF4444),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Main Details Column
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      name,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  // Live Status Badge Per Row (✓ Siap vs ⚠️ Error)
                                  if (isValid)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(5),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.check_circle_rounded, size: 10.5, color: Color(0xFF10B981)),
                                          SizedBox(width: 3),
                                          Text(
                                            'Siap',
                                            style: TextStyle(
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF10B981),
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  else
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(5),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.error_outline_rounded, size: 10.5, color: Color(0xFFEF4444)),
                                          SizedBox(width: 3),
                                          Text(
                                            'Error',
                                            style: TextStyle(
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFFEF4444),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Wrap(
                                spacing: 6,
                                runSpacing: 2,
                                children: [
                                  _buildMiniPill('ID: $nisnOrNip', const Color(0xFF06B6D4), isDark),
                                  _buildMiniPill(
                                    classOrRole,
                                    isValid ? const Color(0xFFF59E0B) : const Color(0xFFEF4444),
                                    isDark,
                                  ),
                                  _buildMiniPill('Pass: $password', const Color(0xFF10B981), isDark),
                                ],
                              ),
                              // Descriptive Error Messages (clean bulleted list)
                              if (!isValid && rowErrors.isNotEmpty) ...[
                                const SizedBox(height: 5),
                                ...rowErrors.map((err) => Padding(
                                  padding: const EdgeInsets.only(bottom: 2.5),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        margin: const EdgeInsets.only(top: 4, right: 5),
                                        width: 4.5,
                                        height: 4.5,
                                        decoration: const BoxDecoration(
                                          color: Color(0xFFEF4444),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          err,
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w600,
                                            color: isDark ? const Color(0xFFFCA5A5) : const Color(0xFFDC2626),
                                            height: 1.25,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                )),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniPill(String text, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }

  Widget _buildChoiceChip({
    required String label,
    required bool isSelected,
    required Color color,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.15)
              : (isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected
                ? (isDark ? Colors.white : color)
                : (isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text, bool isDark) {
    final isRequired = text.endsWith('*') || text.contains('*');
    if (!isRequired) {
      return Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: isDark ? Colors.white70 : const Color(0xFF334155),
        ),
      );
    }

    final cleanText = text.replaceAll('*', '').trim();
    return RichText(
      text: TextSpan(
        text: cleanText,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: isDark ? Colors.white70 : const Color(0xFF334155),
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
    );
  }

  Widget _buildTextActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(
            color: isDark ? color.withValues(alpha: 0.12) : color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: color.withValues(alpha: isDark ? 0.3 : 0.2),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12.5, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTemplateOptionTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    String? badge,
    Color? badgeColor,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
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
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: (badgeColor ?? iconColor).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              badge,
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: badgeColor ?? iconColor,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 13,
                color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

