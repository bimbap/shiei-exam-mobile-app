import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_notification.dart';
import '../../../../shared/widgets/shiei_bottom_sheet.dart';
import '../../../../shared/widgets/shiei_select_sheet.dart';
import '../teacher_portal_controller.dart';

/// Structured Class Creation & Editing Modal Bottom Sheet
/// Mirroring the School Panel standard with level presets, major suggestions, duplicate detection, and live preview.
class ClassFormDialog extends StatefulWidget {
  final Map<String, dynamic>? classData;
  final TeacherPortalController controller;

  const ClassFormDialog({
    super.key,
    this.classData,
    required this.controller,
  });

  /// Extract education level from class name (e.g. 'X RPL 1' -> 'X', '11 TKJ' -> '11')
  static String getLevel(String name) {
    final trimmed = name.trim();
    // 1. Roman numerals: XII, XI, VIII, VII, IX, IV, VI, X, V, III, II, I
    final matchRoman = RegExp(r'^(XII|XI|VIII|VII|IX|IV|VI|X|V|III|II|I)\b', caseSensitive: false).firstMatch(trimmed);
    if (matchRoman != null) return matchRoman.group(1)!.toUpperCase();

    // 2. Prefixes like "Kelas X", "Kelas 10", "Tingkat 12"
    final matchPrefix = RegExp(r'^(?:KELAS|TINGKAT)\s+(XII|XI|VIII|VII|IX|IV|VI|X|V|III|II|I|\d+)\b', caseSensitive: false).firstMatch(trimmed);
    if (matchPrefix != null) return matchPrefix.group(1)!.toUpperCase();

    // 3. Digits at start: "10 RPL", "11 TKJ", "7A", etc.
    final matchNumber = RegExp(r'^([1-9]|1[0-2])\b', caseSensitive: false).firstMatch(trimmed);
    if (matchNumber != null) return matchNumber.group(1)!;

    return 'OTHER';
  }

  /// Extract major from class name (e.g. 'X RPL 1' -> 'RPL', 'XII BDP 1' -> 'BDP')
  static String extractMajor(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    final levelRegex = RegExp(r'^(XII|XI|IX|VIII|VII|X|IV|V|VI|[1-9]|1[0-2]|KELAS)$', caseSensitive: false);
    final sectionRegex = RegExp(r'^(\d+|[A-Z])$', caseSensitive: false);

    if (parts.length >= 2 && levelRegex.hasMatch(parts[0])) {
      if (parts.length == 2) {
        if (parts[1].length >= 2 && !RegExp(r'^\d+$').hasMatch(parts[1])) {
          return parts[1].toUpperCase();
        }
      } else {
        final last = parts.last;
        final isLastSection = sectionRegex.hasMatch(last);
        final middleParts = parts.sublist(1, isLastSection ? parts.length - 1 : parts.length);
        final major = middleParts.join(' ').trim().toUpperCase();
        if (major.isNotEmpty && (major.length >= 2 || !sectionRegex.hasMatch(major))) {
          return major;
        }
      }
    }
    return '';
  }

  /// Parse class name into structured components
  static Map<String, dynamic> parseClassName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return {
        'category': 'SMK_SMA',
        'level': 'X',
        'customLevel': '',
        'hasMajor': false,
        'major': '',
        'section': '',
      };
    }

    // 1. Check SD Prefix: "Kelas 1", "Kelas 4 A", etc.
    final sdPrefixMatch = RegExp(r'^KELAS\s+([1-6])(?:\s+(.*))?$', caseSensitive: false).firstMatch(trimmed);
    if (sdPrefixMatch != null) {
      return {
        'category': 'SD',
        'level': sdPrefixMatch.group(1)!,
        'customLevel': '',
        'hasMajor': false,
        'major': '',
        'section': (sdPrefixMatch.group(2) ?? '').trim(),
      };
    }

    final parts = trimmed.split(RegExp(r'\s+'));
    const smaPresets = ['X', 'XI', 'XII', '10', '11', '12'];
    const smpPresets = ['VII', 'VIII', 'IX', '7', '8', '9'];
    const sdPresets = ['1', '2', '3', '4', '5', '6'];

    // 2. Compact format: "7A", "8B", "10A"
    final compactMatch = RegExp(r'^([1-9]|1[0-2]|VII|VIII|IX|X|XI|XII)([A-Z]|\d+)$', caseSensitive: false).firstMatch(trimmed);
    if (compactMatch != null && parts.length == 1) {
      final p1 = compactMatch.group(1)!.toUpperCase();
      final p2 = compactMatch.group(2)!.toUpperCase();
      if (smaPresets.contains(p1)) {
        return {'category': 'SMK_SMA', 'level': p1, 'customLevel': '', 'hasMajor': false, 'major': '', 'section': p2};
      }
      if (smpPresets.contains(p1)) {
        return {'category': 'SMP', 'level': p1, 'customLevel': '', 'hasMajor': false, 'major': '', 'section': p2};
      }
      if (sdPresets.contains(p1)) {
        return {'category': 'SD', 'level': p1, 'customLevel': '', 'hasMajor': false, 'major': '', 'section': p2};
      }
    }

    final first = parts[0].toUpperCase();
    String category = 'SMK_SMA';
    String level = 'X';
    String customLevel = '';

    if (smaPresets.contains(first)) {
      category = 'SMK_SMA';
      level = first;
    } else if (smpPresets.contains(first)) {
      category = 'SMP';
      level = first;
    } else if (sdPresets.contains(first)) {
      category = 'SD';
      level = first;
    } else {
      final romanMatch = RegExp(r'^(XII|XI|VIII|VII|IX|IV|VI|X|V|III|II|I)$', caseSensitive: false).firstMatch(first);
      if (romanMatch != null) {
        final rom = romanMatch.group(1)!.toUpperCase();
        if (['X', 'XI', 'XII'].contains(rom)) {
          category = 'SMK_SMA';
          level = rom;
        } else {
          category = 'SMP';
          level = rom;
        }
      } else {
        category = 'CUSTOM';
        customLevel = parts[0];
        level = '';
      }
    }

    final remaining = parts.sublist(1);
    final sectionRegex = RegExp(r'^(\d+|[A-Z])$', caseSensitive: false);

    bool hasMajor = false;
    String major = '';
    String section = '';

    if (remaining.length == 1) {
      if (sectionRegex.hasMatch(remaining[0])) {
        section = remaining[0];
        hasMajor = false;
      } else {
        hasMajor = true;
        major = remaining[0].toUpperCase();
      }
    } else if (remaining.length >= 2) {
      final last = remaining.last;
      if (sectionRegex.hasMatch(last)) {
        section = last;
        final majorTokens = remaining.sublist(0, remaining.length - 1);
        major = majorTokens.join(' ').toUpperCase();
        hasMajor = major.isNotEmpty;
      } else {
        major = remaining.join(' ').toUpperCase();
        hasMajor = true;
      }
    }

    return {
      'category': category,
      'level': level,
      'customLevel': customLevel,
      'hasMajor': hasMajor,
      'major': major,
      'section': section,
    };
  }

  static Future<bool?> show({
    required BuildContext context,
    Map<String, dynamic>? classData,
    required TeacherPortalController controller,
  }) async {
    await ShieiSelectSheet.dismissKeyboardIfNeeded(context);
    if (!context.mounted) return null;

    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ClassFormDialog(
        classData: classData,
        controller: controller,
      ),
    );
  }

  @override
  State<ClassFormDialog> createState() => _ClassFormDialogState();
}

class _ClassFormDialogState extends State<ClassFormDialog> {
  // Common state
  bool _isSubmitting = false;
  String? _errorMessage;

  bool get isEditing => widget.classData != null;

  // --- STRUCTURED BUILDER STATE ---
  // Categories: 'SMK_SMA', 'SMP', 'SD', 'CUSTOM'
  String _levelCategory = 'SMK_SMA';
  String _selectedLevel = 'X';
  final TextEditingController _customLevelController = TextEditingController();

  bool _hasMajor = false;
  final TextEditingController _majorController = TextEditingController();
  final TextEditingController _sectionController = TextEditingController();

  // --- SECTION 2: TEACHER / WALI KELAS STATE ---
  int? _selectedTeacherId;

  @override
  void initState() {
    super.initState();
    if (widget.controller.teachers.isEmpty) {
      widget.controller.loadTeachers();
    }
    if (isEditing) {
      final originalName = widget.classData?['name']?.toString() ?? '';
      final parsed = ClassFormDialog.parseClassName(originalName);
      _levelCategory = parsed['category'] as String;
      _selectedLevel = (parsed['level'] as String).isNotEmpty ? (parsed['level'] as String) : 'X';
      _customLevelController.text = parsed['customLevel'] as String;
      _hasMajor = parsed['hasMajor'] as bool;
      _majorController.text = parsed['major'] as String;
      _sectionController.text = parsed['section'] as String;

      final currentClassId = widget.classData?['id'];
      final rawTeachers = widget.classData?['teachers'];
      if (rawTeachers is List && rawTeachers.isNotEmpty) {
        final firstTeacher = rawTeachers.first;
        if (firstTeacher is Map && firstTeacher['id'] != null) {
          _selectedTeacherId = firstTeacher['id'] as int?;
        }
      } else if (currentClassId != null) {
        final match = widget.controller.teachers.cast<Map<String, dynamic>?>().firstWhere(
          (t) => t?['class_major_id']?.toString() == currentClassId.toString(),
          orElse: () => null,
        );
        if (match != null) {
          _selectedTeacherId = match['id'] as int?;
        }
      }
    }
    _customLevelController.addListener(_onFieldChanged);
    _majorController.addListener(_onFieldChanged);
    _sectionController.addListener(_onFieldChanged);
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _customLevelController.removeListener(_onFieldChanged);
    _majorController.removeListener(_onFieldChanged);
    _sectionController.removeListener(_onFieldChanged);

    _customLevelController.dispose();
    _majorController.dispose();
    _sectionController.dispose();
    super.dispose();
  }

  /// Dynamically derive existing majors & counts from database
  List<Map<String, dynamic>> _getExistingMajors() {
    final map = <String, int>{};
    for (final c in widget.controller.classes) {
      final name = c['name']?.toString() ?? '';
      final m = ClassFormDialog.extractMajor(name);
      if (m.isNotEmpty) {
        map[m] = (map[m] ?? 0) + 1;
      }
    }
    final list = map.entries.map((e) => {'name': e.key, 'count': e.value}).toList();
    list.sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));
    return list;
  }

  /// Compute preview class name for create & edit modals
  String _computedClassName() {
    final levelPart = _levelCategory == 'CUSTOM'
        ? (_customLevelController.text.trim().isNotEmpty
            ? _customLevelController.text.trim().toUpperCase()
            : 'KELAS')
        : (_levelCategory == 'SD' ? 'Kelas $_selectedLevel' : _selectedLevel);

    final parts = <String>[levelPart];
    if (_hasMajor && _majorController.text.trim().isNotEmpty) {
      parts.add(_majorController.text.trim().toUpperCase());
    }
    if (_sectionController.text.trim().isNotEmpty) {
      parts.add(_sectionController.text.trim().toUpperCase());
    }
    return parts.join(' ').toUpperCase();
  }

  /// Find duplicate class for Create Mode
  Map<String, dynamic>? _getCreateDuplicateClass() {
    final computed = _computedClassName().trim().toUpperCase();
    for (final c in widget.controller.classes) {
      final cName = c['name']?.toString().trim().toUpperCase();
      if (cName == computed) {
        return c;
      }
    }
    return null;
  }

  /// Find duplicate class for Edit Mode
  Map<String, dynamic>? _getEditDuplicateClass() {
    final currentId = widget.classData?['id']?.toString();
    final targetName = _computedClassName().trim().toUpperCase();
    for (final c in widget.controller.classes) {
      if (c['id']?.toString() != currentId && c['name']?.toString().trim().toUpperCase() == targetName) {
        return c;
      }
    }
    return null;
  }

  bool get _isFormValid {
    if (_isSubmitting) return false;
    final computed = _computedClassName().trim();
    if (computed.length < 2) return false;

    if (_levelCategory == 'CUSTOM' && _customLevelController.text.trim().isEmpty) return false;
    if (_hasMajor && _majorController.text.trim().isEmpty) return false;

    final duplicate = isEditing ? _getEditDuplicateClass() : _getCreateDuplicateClass();
    if (duplicate != null) return false;
    return true;
  }

  Future<void> _submit() async {
    if (!_isFormValid) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    String? error;
    final String finalName = _computedClassName();

    if (isEditing) {
      final id = widget.classData!['id'] as int;
      error = await widget.controller.updateClass(
        id,
        finalName,
        teacherId: _selectedTeacherId,
        updateTeacher: true,
      );
    } else {
      error = await widget.controller.createClass(
        finalName,
        teacherId: _selectedTeacherId,
      );
    }

    if (!mounted) return;

    if (error == null) {
      Navigator.of(context).pop(true);
      AppNotification.showSuccess(
        context,
        isEditing ? 'Nama Kelas Diperbarui' : 'Kelas Baru Ditambahkan',
        subtitle: 'Kelas "$finalName" berhasil disimpan ke sistem.',
      );
    } else {
      setState(() {
        _isSubmitting = false;
        _errorMessage = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final isValid = _isFormValid;
    const accentColor = Color(0xFFF59E0B); // School Panel Class Amber

    return ShieiBottomSheet(
      initialFraction: 0.78,
      dismissThreshold: 0.55,
      maxFraction: 0.94,
      snapFractions: const [0.78, 0.94],
      headerBuilder: (isFullscreen) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isEditing ? Icons.edit_note_rounded : Icons.add_home_work_rounded,
                color: accentColor,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isEditing ? 'Edit Data Kelas' : 'Tambah Kelas Baru',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isEditing
                        ? 'Perbarui format struktur atau nama kelas (ID #${widget.classData!['id']}).'
                        : 'Pilih tingkat dan konfigurasi kelas terstandardisasi',
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
      footerBuilder: (isFullscreen) => Row(
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
                  backgroundColor: accentColor,
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
                    : Icon(isEditing ? Icons.check_rounded : Icons.add_rounded, size: 18),
                label: Text(
                  _isSubmitting
                      ? 'Menyimpan...'
                      : (isEditing
                          ? (_getEditDuplicateClass() != null ? 'Nama Kelas Duplikat' : 'Simpan Perubahan')
                          : (_getCreateDuplicateClass() != null ? 'Kelas Sudah Terdaftar' : 'Buat Kelas')),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
      bodyBuilder: (scrollController) => SingleChildScrollView(
        controller: scrollController,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Server error banner if any
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

            // Form Content
            _buildFormContent(isDark, accentColor),
          ],
        ),
      ),
    );
  }

  Widget _buildFormContent(bool isDark, Color accentColor) {
    final duplicateClass = isEditing ? _getEditDuplicateClass() : _getCreateDuplicateClass();
    final isDuplicate = duplicateClass != null;
    final computedName = _computedClassName();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStructuredFields(isDark, accentColor),

        const SizedBox(height: 16),

        // Duplicate Alert Banner
        if (isDuplicate)
          _buildDuplicateAlert(isDark, duplicateClass, computedName),

        // Live Generated Preview Box
        _buildLivePreview(isDark, accentColor, computedName, isDuplicate),

        const SizedBox(height: 20),

        // Section 2: Hubungkan Guru / Wali Kelas (Opsional)
        _buildTeacherSection(isDark, accentColor),
      ],
    );
  }

  Widget _buildStructuredFields(bool isDark, Color accentColor) {
    final existingMajors = _getExistingMajors();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Tingkat Kelas Section Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildLabel('Tingkat Kelas *', isDark),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: accentColor.withValues(alpha: 0.3)),
              ),
              child: Text(
                _levelCategory == 'CUSTOM'
                    ? (_customLevelController.text.trim().isNotEmpty
                        ? _customLevelController.text.trim().toUpperCase()
                        : 'Kustom')
                    : (_levelCategory == 'SD' ? 'Kelas $_selectedLevel' : 'Tingkat $_selectedLevel'),
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: accentColor),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Category Tabs
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              _buildCategoryTab('SMA / SMK', 'SMK_SMA', isDark, accentColor),
              _buildCategoryTab('SMP / MTs', 'SMP', isDark, accentColor),
              _buildCategoryTab('SD / MI', 'SD', isDark, accentColor),
              _buildCategoryTab('Kustom', 'CUSTOM', isDark, accentColor),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Presets Grid / Input based on category
        if (_levelCategory == 'SMK_SMA')
          _buildPresetGrid(const ['X', 'XI', 'XII', '10', '11', '12'], isDark, accentColor),
        if (_levelCategory == 'SMP')
          _buildPresetGrid(const ['VII', 'VIII', 'IX', '7', '8', '9'], isDark, accentColor),
        if (_levelCategory == 'SD')
          _buildPresetGrid(const ['1', '2', '3', '4', '5', '6'], isDark, accentColor, prefix: 'Kelas '),
        if (_levelCategory == 'CUSTOM')
          TextField(
            controller: _customLevelController,
            textCapitalization: TextCapitalization.characters,
            maxLength: 20,
            textInputAction: TextInputAction.next,
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
            inputFormatters: [LengthLimitingTextInputFormatter(20)],
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
            decoration: InputDecoration(
              hintText: 'Contoh: Matrikulasi, Tingkat 1, D3, dll.',
              prefixIcon: const Icon(Icons.school_outlined, size: 18),
              filled: true,
              fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: accentColor, width: 1.5),
              ),
            ),
          ),
        const SizedBox(height: 14),

        // Jurusan Toggle Card
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sertakan Jurusan',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _hasMajor
                              ? 'Nama jurusan akan dimasukkan ke format kelas'
                              : 'Nonaktifkan jika kelas tidak memiliki jurusan (e.g. SMP, SD)',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch.adaptive(
                    value: _hasMajor,
                    activeTrackColor: accentColor,
                    activeThumbColor: Colors.white,
                    onChanged: (val) {
                      FocusScope.of(context).unfocus();
                      HapticFeedback.selectionClick();
                      setState(() {
                        _hasMajor = val;
                      });
                    },
                  ),
                ],
              ),

              if (_hasMajor) ...[
                const SizedBox(height: 10),
                const Divider(height: 1),
                const SizedBox(height: 10),
                _buildLabel('Singkatan Jurusan *', isDark),
                const SizedBox(height: 6),
                TextField(
                  controller: _majorController,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 20,
                  textInputAction: TextInputAction.next,
                  onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                  buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
                  inputFormatters: [LengthLimitingTextInputFormatter(20)],
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                  decoration: InputDecoration(
                    hintText: 'Ketik singkatan jurusan (e.g. RPL, AKL, TKJ)...',
                    prefixIcon: const Icon(Icons.workspace_premium_outlined, size: 18),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: accentColor, width: 1.5),
                    ),
                  ),
                ),

                // Quick suggestions from database
                if (existingMajors.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.auto_awesome_rounded, size: 12, color: accentColor),
                          const SizedBox(width: 4),
                          Text(
                            'PILIHAN CEPAT JURUSAN:',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                              color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${existingMajors.length} Terdaftar',
                        style: TextStyle(
                          fontSize: 10,
                          color: isDark ? AppTheme.textSecondary : const Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: existingMajors.map((m) {
                      final name = m['name'] as String;
                      final count = m['count'] as int;
                      final isSelected = _majorController.text.trim().toUpperCase() == name.toUpperCase();

                      return GestureDetector(
                        onTap: () {
                          FocusScope.of(context).unfocus();
                          HapticFeedback.selectionClick();
                          setState(() {
                            _majorController.text = name;
                          });
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? accentColor
                                : (isDark ? const Color(0xFF1E293B) : Colors.white),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected
                                  ? accentColor
                                  : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                name,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                  color: isSelected ? Colors.white : (isDark ? Colors.white : const Color(0xFF0F172A)),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? Colors.white.withValues(alpha: 0.25)
                                      : (isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9)),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '$count',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: isSelected ? Colors.white : (isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Nomor / Pararel Kelas
        _buildLabel('Nomor / Pararel Kelas (Opsional)', isDark),
        const SizedBox(height: 6),
        TextField(
          controller: _sectionController,
          textCapitalization: TextCapitalization.characters,
          maxLength: 10,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => FocusScope.of(context).unfocus(),
          onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
          buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
          inputFormatters: [LengthLimitingTextInputFormatter(10)],
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
          decoration: InputDecoration(
            hintText: 'Contoh: 1, 2, A, B (kosongkan jika tanpa kelas paralel)',
            prefixIcon: const Icon(Icons.tag_rounded, size: 18),
            filled: true,
            fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: accentColor, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDuplicateAlert(bool isDark, Map<String, dynamic> duplicateClass, String computedName) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFCD34D)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFB45309), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Format Kelas Sudah Pernah Dibuat!',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF92400E)),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFDE68A),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'ID #${duplicateClass['id']}',
                        style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF92400E)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'Kelas "$computedName" sudah terdaftar di sistem. Silakan isi Nomor / Pararel (misal: 1, 2, A) atau ubah jurusan agar tidak duplikat.',
                  style: const TextStyle(fontSize: 11.5, color: Color(0xFF92400E)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLivePreview(bool isDark, Color accentColor, String computedName, bool isDuplicate) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDuplicate
            ? const Color(0xFFFEF3C7).withValues(alpha: 0.6)
            : (isDark ? const Color(0xFF0F172A) : const Color(0xFFFFFBEB)),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDuplicate ? const Color(0xFFFCD34D) : accentColor.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Format Nama Kelas:',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (isEditing) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Semula: ${widget.classData?['name']}',
                          style: TextStyle(
                            fontSize: 9,
                            fontFamily: 'monospace',
                            color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(
                      isDuplicate ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
                      size: 13,
                      color: isDuplicate ? const Color(0xFFB45309) : const Color(0xFF10B981),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isDuplicate
                          ? 'Sudah ada di database (Duplikat)'
                          : (isEditing ? 'Format siap diperbarui' : 'Format baru & siap disimpan'),
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: isDuplicate ? const Color(0xFFB45309) : const Color(0xFF10B981),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isDuplicate
                  ? const Color(0xFFFDE68A)
                  : accentColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              computedName.isNotEmpty ? computedName : '-',
              style: TextStyle(
                fontSize: 13.5,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w800,
                color: isDuplicate ? const Color(0xFF92400E) : (isDark ? Colors.white : accentColor),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryTab(String title, String categoryId, bool isDark, Color accentColor) {
    final isSelected = _levelCategory == categoryId;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          FocusScope.of(context).unfocus();
          HapticFeedback.selectionClick();
          setState(() {
            _levelCategory = categoryId;
            if (categoryId == 'SMK_SMA') _selectedLevel = 'X';
            if (categoryId == 'SMP') _selectedLevel = 'VII';
            if (categoryId == 'SD') _selectedLevel = '1';
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark ? const Color(0xFF1E293B) : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected
                  ? (isDark ? Colors.white : accentColor)
                  : (isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPresetGrid(List<String> levels, bool isDark, Color accentColor, {String prefix = ''}) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: 1.3,
      ),
      itemCount: levels.length,
      itemBuilder: (ctx, idx) {
        final lvl = levels[idx];
        final isSelected = _selectedLevel == lvl;

        return GestureDetector(
          onTap: () {
            FocusScope.of(context).unfocus();
            HapticFeedback.selectionClick();
            setState(() {
              _selectedLevel = lvl;
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected
                  ? accentColor
                  : (isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC)),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected
                    ? accentColor
                    : (isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: accentColor.withValues(alpha: 0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Text(
              '$prefix$lvl',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: isSelected
                    ? Colors.white
                    : (isDark ? Colors.white70 : const Color(0xFF334155)),
              ),
            ),
          ),
        );
      },
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

  Widget _buildTeacherSection(bool isDark, Color accentColor) {
    final selectedTeacher = _selectedTeacherId != null
        ? widget.controller.teachers.cast<Map<String, dynamic>?>().firstWhere(
            (t) => t?['id'] == _selectedTeacherId,
            orElse: () => null,
          )
        : null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B).withValues(alpha: 0.6) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.person_pin_rounded, color: Color(0xFF6366F1), size: 16),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Wali Kelas / Guru Kelas',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'OPSIONAL',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Tugaskan guru sebagai wali kelas ini (maksimal 1 guru per kelas).',
            style: TextStyle(
              fontSize: 11,
              color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 12),
          if (selectedTeacher == null) ...[
            InkWell(
              onTap: () {
                FocusScope.of(context).unfocus();
                _openTeacherPicker(isDark, accentColor);
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A) : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.person_add_alt_1_rounded,
                      size: 20,
                      color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Pilih Guru Wali Kelas...',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: isDark ? AppTheme.textSecondary : const Color(0xFF94A3B8),
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(
                        (selectedTeacher['name']?.toString() ?? 'G').isNotEmpty
                            ? selectedTeacher['name']!.toString()[0].toUpperCase()
                            : 'G',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF6366F1),
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          selectedTeacher['name']?.toString() ?? 'Guru',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'NIP: ${selectedTeacher['nip'] ?? '-'}',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => _openTeacherPicker(isDark, accentColor),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('Ganti', style: TextStyle(fontSize: 11.5, color: Color(0xFF6366F1))),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    tooltip: 'Lepas Pilihan',
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      setState(() {
                        _selectedTeacherId = null;
                      });
                    },
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _openTeacherPicker(bool isDark, Color accentColor) {
    String query = '';
    final searchController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final allTeachers = widget.controller.teachers;
            final filtered = allTeachers.where((t) {
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
                            color: accentColor.withValues(alpha: isDark ? 0.2 : 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.supervisor_account_rounded,
                            color: accentColor,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Pilih Wali Kelas',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Pilih 1 guru pembina untuk kelas ini',
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
                            '${allTeachers.length} Guru',
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
                      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
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
                          borderSide: BorderSide(
                            color: accentColor,
                            width: 1.5,
                          ),
                        ),
                      ),
                      onChanged: (val) {
                        setModalState(() => query = val.trim());
                      },
                    ),
                  ),

                  // Option: Tidak Ada / Kosongkan Wali Kelas
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          setState(() => _selectedTeacherId = null);
                          Navigator.pop(ctx);
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: _selectedTeacherId == null
                                ? (isDark
                                    ? const Color(0xFF10B981).withValues(alpha: 0.12)
                                    : const Color(0xFFECFDF5))
                                : (isDark
                                    ? const Color(0xFF1E293B).withValues(alpha: 0.5)
                                    : const Color(0xFFF8FAFC)),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: _selectedTeacherId == null
                                  ? const Color(0xFF10B981).withValues(alpha: 0.45)
                                  : (isDark ? const Color(0xFF334155).withValues(alpha: 0.6) : const Color(0xFFE2E8F0)),
                              width: _selectedTeacherId == null ? 1.4 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: _selectedTeacherId == null
                                      ? const Color(0xFF10B981).withValues(alpha: 0.18)
                                      : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  Icons.person_off_rounded,
                                  size: 19,
                                  color: _selectedTeacherId == null
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
                                        fontWeight: _selectedTeacherId == null ? FontWeight.bold : FontWeight.w600,
                                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Kelas ini tidak memiliki wali kelas binaan',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (_selectedTeacherId == null)
                                const Icon(
                                  Icons.check_circle_rounded,
                                  color: Color(0xFF10B981),
                                  size: 20,
                                )
                              else
                                Icon(
                                  Icons.radio_button_unchecked_rounded,
                                  size: 19,
                                  color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
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
                                      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.person_search_rounded,
                                      size: 24,
                                      color: isDark ? AppTheme.textSecondary : const Color(0xFF94A3B8),
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
                                      color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 2, 16, 20),
                            itemCount: filtered.length,
                            itemBuilder: (ctx, i) {
                              final teacher = filtered[i];
                              final id = teacher['id'] as int?;
                              final name = teacher['name']?.toString() ?? 'Guru';
                              final nip = teacher['nip']?.toString();
                              final isSelected = _selectedTeacherId == id;

                              final assignedClassId = teacher['class_major_id'];
                              String? assignedClassName;
                              if (assignedClassId != null) {
                                final match = widget.controller.classes.firstWhere(
                                  (c) => c['id']?.toString() == assignedClassId.toString(),
                                  orElse: () => {},
                                );
                                assignedClassName = match['name']?.toString();
                              }

                              final isCurrentClass = assignedClassId != null &&
                                  widget.classData != null &&
                                  assignedClassId.toString() == widget.classData!['id']?.toString();

                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 3),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () {
                                      setState(() => _selectedTeacherId = id);
                                      Navigator.pop(ctx);
                                    },
                                    borderRadius: BorderRadius.circular(14),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? accentColor.withValues(alpha: isDark ? 0.15 : 0.08)
                                            : (isDark
                                                ? const Color(0xFF1E293B).withValues(alpha: 0.5)
                                                : const Color(0xFFF8FAFC)),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: isSelected
                                              ? accentColor.withValues(alpha: 0.6)
                                              : (isDark ? const Color(0xFF334155).withValues(alpha: 0.5) : const Color(0xFFE2E8F0)),
                                          width: isSelected ? 1.4 : 1,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 38,
                                            height: 38,
                                            decoration: BoxDecoration(
                                              color: isSelected
                                                  ? accentColor.withValues(alpha: 0.2)
                                                  : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: Center(
                                              child: Text(
                                                name.isNotEmpty ? name[0].toUpperCase() : 'G',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 15,
                                                  color: isSelected
                                                      ? accentColor
                                                      : (isDark ? Colors.white : const Color(0xFF0F172A)),
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
                                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  'NIP: ${nip != null && nip.isNotEmpty ? nip : '-'}',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                                                  ),
                                                ),
                                                if (assignedClassName != null) ...[
                                                  const SizedBox(height: 4),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: isCurrentClass
                                                          ? const Color(0xFF10B981).withValues(alpha: 0.12)
                                                          : const Color(0xFFF59E0B).withValues(alpha: 0.12),
                                                      borderRadius: BorderRadius.circular(6),
                                                      border: Border.all(
                                                        color: isCurrentClass
                                                            ? const Color(0xFF10B981).withValues(alpha: 0.3)
                                                            : const Color(0xFFF59E0B).withValues(alpha: 0.3),
                                                      ),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Icon(
                                                          isCurrentClass ? Icons.check_rounded : Icons.swap_horiz_rounded,
                                                          size: 11,
                                                          color: isCurrentClass ? const Color(0xFF10B981) : const Color(0xFFD97706),
                                                        ),
                                                        const SizedBox(width: 4),
                                                        Flexible(
                                                          child: Text(
                                                            isCurrentClass
                                                                ? 'Wali kelas saat ini'
                                                                : 'Wali kelas $assignedClassName (Akan dipindahkan)',
                                                            style: TextStyle(
                                                              fontSize: 10,
                                                              fontWeight: FontWeight.w700,
                                                              color: isCurrentClass ? const Color(0xFF10B981) : const Color(0xFFD97706),
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
                                          if (isSelected)
                                            Icon(
                                              Icons.check_circle_rounded,
                                              color: accentColor,
                                              size: 20,
                                            )
                                          else
                                            Icon(
                                              Icons.radio_button_unchecked_rounded,
                                              size: 19,
                                              color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
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
                  const SafeArea(
                    top: false,
                    child: SizedBox(height: 6),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
