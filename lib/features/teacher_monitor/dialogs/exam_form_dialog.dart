import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/utils/format_utils.dart';
import '../../../../shared/widgets/app_notification.dart';
import '../../../../shared/widgets/shiei_bottom_sheet.dart';
import '../../../../shared/widgets/shiei_select_sheet.dart';
import '../../../../shared/widgets/shiei_checkbox.dart';
import '../../../../shared/widgets/shiei_date_picker.dart';
import '../teacher_portal_controller.dart';

class ExamFormDialog extends StatefulWidget {
  final Map<String, dynamic>? exam;
  final TeacherPortalController controller;

  const ExamFormDialog({
    super.key,
    this.exam,
    required this.controller,
  });

  static Future<bool?> show({
    required BuildContext context,
    Map<String, dynamic>? exam,
    required TeacherPortalController controller,
  }) async {
    FocusScope.of(context).unfocus();

    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => ExamFormDialog(
        exam: exam,
        controller: controller,
      ),
    );
  }

  @override
  State<ExamFormDialog> createState() => _ExamFormDialogState();
}

class _ExamFormDialogState extends State<ExamFormDialog> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _titleController;
  late TextEditingController _subjectController;
  late TextEditingController _urlController;
  late TextEditingController _tokenController;

  late TabController _tokenModeTabController;
  late DateTime _selectedDate;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  late int _durationMinutes;

  // Sheet state managed by ShieiBottomSheet internally
  List<int> _selectedClassIds = [];
  String _tokenMode = 'permanent'; // permanent, rotating_5m, none
  bool _isActive = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  bool get isEditing => widget.exam != null;

  @override
  void initState() {
    super.initState();
    final exam = widget.exam;

    _titleController = TextEditingController(text: exam?['title']?.toString() ?? '');
    _subjectController = TextEditingController(text: exam?['subject']?.toString() ?? '');
    _urlController = TextEditingController(text: exam?['url']?.toString() ?? '');
    _tokenController = TextEditingController(text: exam?['token']?.toString() ?? '');

    // Parse date & time
    final startTimeStr = exam?['start_time']?.toString();
    final endTimeStr = exam?['end_time']?.toString();

    if (startTimeStr != null && startTimeStr.isNotEmpty) {
      try {
        final parsedStart = DateTime.parse(startTimeStr).toLocal();
        _selectedDate = DateTime(parsedStart.year, parsedStart.month, parsedStart.day);
        _startTime = TimeOfDay(hour: parsedStart.hour, minute: parsedStart.minute);
      } catch (_) {
        _selectedDate = DateTime.now();
        _startTime = const TimeOfDay(hour: 8, minute: 0);
      }
    } else {
      _selectedDate = DateTime.now();
      _startTime = const TimeOfDay(hour: 8, minute: 0);
    }

    if (endTimeStr != null && endTimeStr.isNotEmpty) {
      try {
        final parsedEnd = DateTime.parse(endTimeStr).toLocal();
        _endTime = TimeOfDay(hour: parsedEnd.hour, minute: parsedEnd.minute);
      } catch (_) {
        _endTime = _addMinutesToTimeOfDay(_startTime, 60);
      }
    } else {
      final initialDur = (exam?['duration_minutes'] ?? exam?['duration'] ?? 60) as int;
      _endTime = _addMinutesToTimeOfDay(_startTime, initialDur > 0 ? initialDur : 60);
    }

    _durationMinutes = _calcDurationMinutes(_startTime, _endTime);

    if (exam != null) {
      if (exam['class_major_ids'] != null && exam['class_major_ids'] is List) {
        _selectedClassIds = (exam['class_major_ids'] as List)
            .map((e) => int.tryParse(e.toString()))
            .whereType<int>()
            .toList();
      } else if (exam['class_majors'] != null && exam['class_majors'] is List) {
        _selectedClassIds = (exam['class_majors'] as List)
            .map((c) => int.tryParse(c['id']?.toString() ?? ''))
            .whereType<int>()
            .toList();
      } else if (exam['class_major_id'] != null) {
        final cid = int.tryParse(exam['class_major_id'].toString());
        if (cid != null) _selectedClassIds = [cid];
      }
      _tokenMode = exam['token_mode']?.toString() ?? 'permanent';
      _isActive = (exam['status']?.toString() ?? 'active') == 'active';
    } else {
      _generateRandomToken();
    }

    int initialIndex = 0;
    if (_tokenMode == 'rotating_5m') initialIndex = 1;
    if (_tokenMode == 'none') initialIndex = 2;
    _tokenModeTabController = TabController(length: 3, vsync: this, initialIndex: initialIndex);
    _tokenModeTabController.addListener(() {
      if (!_tokenModeTabController.indexIsChanging) {
        final modes = ['permanent', 'rotating_5m', 'none'];
        final newMode = modes[_tokenModeTabController.index];
        if (_tokenMode != newMode) {
          setState(() {
            _tokenMode = newMode;
          });
        }
      }
    });

    _titleController.addListener(_onFieldChanged);
    _urlController.addListener(_onFieldChanged);
    _tokenController.addListener(_onFieldChanged);
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  bool get _isFormValid {
    // 1. Judul Ujian * (min 3 chars)
    if (_titleController.text.trim().length < 3) return false;
    // 2. Link Soal / URL CBT * (valid URL)
    final url = _urlController.text.trim();
    if (url.isEmpty || !RegExp(r'^https?:\/\/.+', caseSensitive: false).hasMatch(url)) return false;
    // 3. Token if not 'none' (exactly 6 chars)
    if (_tokenMode != 'none' && _tokenController.text.trim().length != 6) return false;
    return true;
  }

  @override
  void dispose() {
    _titleController.removeListener(_onFieldChanged);
    _urlController.removeListener(_onFieldChanged);
    _tokenController.removeListener(_onFieldChanged);
    _titleController.dispose();
    _subjectController.dispose();
    _urlController.dispose();
    _tokenController.dispose();
    _tokenModeTabController.dispose();
    super.dispose();
  }

  TimeOfDay _addMinutesToTimeOfDay(TimeOfDay time, int minutes) {
    final totalMinutes = time.hour * 60 + time.minute + minutes;
    final newHour = (totalMinutes ~/ 60) % 24;
    final newMin = totalMinutes % 60;
    return TimeOfDay(hour: newHour, minute: newMin);
  }

  int _calcDurationMinutes(TimeOfDay start, TimeOfDay end) {
    final startMin = start.hour * 60 + start.minute;
    var endMin = end.hour * 60 + end.minute;
    if (endMin <= startMin) {
      endMin += 24 * 60;
    }
    return endMin - startMin;
  }

  Future<void> _pickDate() async {
    FocusScope.of(context).unfocus();
    final picked = await ShieiDatePicker.show(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2023),
      lastDate: DateTime(2035),
      title: 'Pilih Tanggal Ujian',
      cancelText: 'Batal',
      confirmText: 'Pilih',
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _pickStartTime() async {
    FocusScope.of(context).unfocus();
    final isDark = AppTheme.isDark(context);
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime,
      initialEntryMode: TimePickerEntryMode.dial,
      cancelText: 'Batal',
      confirmText: 'Pilih',
      helpText: 'Pilih Jam Mulai Ujian',
      hourLabelText: 'Jam',
      minuteLabelText: 'Menit',
      builder: (ctx, child) => Theme(
        data: isDark
            ? ThemeData.dark().copyWith(
                colorScheme: const ColorScheme.dark(
                  primary: Color(0xFFEA580C),
                  onPrimary: Colors.white,
                  surface: Color(0xFF1E293B),
                ),
              )
            : ThemeData.light().copyWith(
                colorScheme: const ColorScheme.light(
                  primary: Color(0xFFEA580C),
                  onPrimary: Colors.white,
                ),
              ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _startTime = picked;
        final startMin = _startTime.hour * 60 + _startTime.minute;
        final endMin = _endTime.hour * 60 + _endTime.minute;
        if (endMin <= startMin) {
          _endTime = _addMinutesToTimeOfDay(_startTime, _durationMinutes > 0 ? _durationMinutes : 60);
        }
        _durationMinutes = _calcDurationMinutes(_startTime, _endTime);
      });
    }
  }

  Future<void> _pickEndTime() async {
    FocusScope.of(context).unfocus();
    final isDark = AppTheme.isDark(context);
    final picked = await showTimePicker(
      context: context,
      initialTime: _endTime,
      initialEntryMode: TimePickerEntryMode.dial,
      cancelText: 'Batal',
      confirmText: 'Pilih',
      helpText: 'Pilih Jam Selesai Ujian',
      hourLabelText: 'Jam',
      minuteLabelText: 'Menit',
      builder: (ctx, child) => Theme(
        data: isDark
            ? ThemeData.dark().copyWith(
                colorScheme: const ColorScheme.dark(
                  primary: Color(0xFFEA580C),
                  onPrimary: Colors.white,
                  surface: Color(0xFF1E293B),
                ),
              )
            : ThemeData.light().copyWith(
                colorScheme: const ColorScheme.light(
                  primary: Color(0xFFEA580C),
                  onPrimary: Colors.white,
                ),
              ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _endTime = picked;
        _durationMinutes = _calcDurationMinutes(_startTime, _endTime);
      });
    }
  }

  void _generateRandomToken() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    final token = List.generate(6, (index) => chars[random.nextInt(chars.length)]).join();
    setState(() {
      _tokenController.text = token;
    });
  }

  String _formatSelectedClassesText() {
    if (_selectedClassIds.isEmpty) {
      return 'Semua Kelas (Terbuka untuk Umum)';
    }
    final names = _selectedClassIds.map((id) {
      final c = widget.controller.classes.firstWhere(
        (cls) => (cls['id']?.toString() == id.toString()),
        orElse: () => {'name': 'Kelas #$id'},
      );
      return c['name']?.toString() ?? 'Kelas #$id';
    }).toList();

    if (names.length == 1) {
      return '1 Kelas (${names.first})';
    }
    return '${names.length} Kelas (${names.take(3).join(', ')}${names.length > 3 ? ', ...' : ''})';
  }

  Future<void> _showClassMultiSelectSheet(BuildContext context, bool isDark) async {
    await ShieiSelectSheet.dismissKeyboardIfNeeded(context);
    if (!context.mounted) return;

    List<int> tempSelected = List.from(_selectedClassIds);
    final classes = widget.controller.classes;

    final result = await showModalBottomSheet<List<int>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final isAllSelected = tempSelected.isEmpty;
            final maxHeight = MediaQuery.of(context).size.height * 0.8;

            return Container(
              constraints: BoxConstraints(maxHeight: maxHeight),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.surfaceDark : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Handle Bar
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 12, bottom: 8),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Title & Action Row
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Pilih Sasaran Kelas Ujian',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Pilih satu, beberapa, atau semua kelas',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setModalState(() {
                              if (tempSelected.length == classes.length) {
                                tempSelected.clear(); // Set to Semua Kelas
                              } else {
                                tempSelected = classes
                                    .map((c) => int.tryParse(c['id']?.toString() ?? ''))
                                    .whereType<int>()
                                    .toList();
                              }
                            });
                          },
                          child: Text(
                            tempSelected.length == classes.length ? 'Batal Semua' : 'Pilih Semua',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFEA580C),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Divider(height: 1),

                  // List of Options
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      children: [
                        // Option 1: Semua Kelas (Terbuka untuk Umum)
                        _buildClassCheckboxTile(
                          label: 'Semua Kelas (Terbuka untuk Umum)',
                          subtitle: 'Semua siswa di sekolah dapat mengikuti ujian ini',
                          icon: Icons.public_rounded,
                          isSelected: isAllSelected,
                          isDark: isDark,
                          onTap: () {
                            setModalState(() {
                              tempSelected.clear(); // Empty list means all classes
                            });
                          },
                        ),
                        const SizedBox(height: 10),

                        // Section label
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                          child: Text(
                            'ATAU PILIH KELAS SPESIFIK (${classes.length} TERSEDIA):',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.4,
                              color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                            ),
                          ),
                        ),

                        // Individual Class Options
                        ...classes.map((c) {
                          final classId = int.tryParse(c['id']?.toString() ?? '') ?? 0;
                          final className = c['name']?.toString() ?? 'Kelas';
                          final count = widget.controller.students.where((s) {
                            final sClassId = s['class_major_id'] ?? s['class_id'] ?? s['class_major']?['id'] ?? s['classes']?['id'];
                            return sClassId?.toString() == classId.toString();
                          }).length;
                          final isChecked = tempSelected.contains(classId);

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _buildClassCheckboxTile(
                              label: className,
                              subtitle: '$count Siswa Terdaftar',
                              icon: Icons.school_rounded,
                              isSelected: isChecked,
                              isDark: isDark,
                              onTap: () {
                                setModalState(() {
                                  if (isChecked) {
                                    tempSelected.remove(classId);
                                  } else {
                                    tempSelected.add(classId);
                                  }
                                });
                              },
                            ),
                          );
                        }),
                      ],
                    ),
                  ),

                  // Bottom Confirmation Button
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                      border: Border(
                        top: BorderSide(
                          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                        ),
                      ),
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFEA580C),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () {
                          Navigator.pop(context, tempSelected);
                        },
                        child: Text(
                          tempSelected.isEmpty
                              ? 'Terapkan (Semua Kelas)'
                              : 'Terapkan (${tempSelected.length} Kelas Dipilih)',
                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (result != null && mounted) {
      setState(() {
        _selectedClassIds = result;
      });
    }
  }

  Widget _buildClassCheckboxTile({
    required String label,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        splashColor: const Color(0xFFEA580C).withValues(alpha: 0.12),
        highlightColor: const Color(0xFFEA580C).withValues(alpha: 0.06),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFFEA580C).withValues(alpha: isDark ? 0.18 : 0.08)
                : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC)),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFFEA580C)
                  : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
              width: isSelected ? 1.4 : 1.0,
            ),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFFEA580C).withValues(alpha: 0.2)
                      : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: isSelected
                      ? const Color(0xFFEA580C)
                      : (isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
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
              ShieiCheckbox(
                value: isSelected,
                onChanged: (_) => onTap(),
                enableHaptics: false,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final title = _titleController.text.trim();
    final subject = _subjectController.text.trim();
    final url = _urlController.text.trim();
    final token = _tokenMode == 'none' ? null : _tokenController.text.trim().toUpperCase();

    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final startStr = '${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}:00';
    final endStr = '${_endTime.hour.toString().padLeft(2, '0')}:${_endTime.minute.toString().padLeft(2, '0')}:00';
    final fullStartTime = '$dateStr $startStr';
    final fullEndTime = '$dateStr $endStr';

    final payload = <String, dynamic>{
      'title': title,
      'subject': subject.isNotEmpty ? subject : null,
      'url': url,
      'class_major_ids': _selectedClassIds,
      'class_major_id': _selectedClassIds.isNotEmpty ? _selectedClassIds.first : null,
      'duration_minutes': _durationMinutes,
      'duration': _durationMinutes,
      'start_time': fullStartTime,
      'end_time': fullEndTime,
      'token_mode': _tokenMode,
      'token': token,
      'use_token': _tokenMode != 'none',
      if (isEditing) 'status': _isActive ? 'active' : 'inactive' else 'status': 'active',
      'is_active': isEditing ? _isActive : true,
    };

    String? error;
    if (isEditing) {
      final examId = widget.exam!['id'];
      error = await widget.controller.updateExam(examId, payload);
    } else {
      error = await widget.controller.createExam(payload);
    }

    if (mounted) {
      if (error == null) {
        Navigator.of(context).pop(true);
        AppNotification.showSuccess(
          context,
          isEditing ? 'Ujian Diperbarui' : 'Ujian Berhasil Dibuat',
          subtitle: '"$title" berhasil disimpan ke server.',
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

    return ShieiBottomSheet(
      initialFraction: 0.65,
      maxFraction: 0.925,
      snapFractions: const [0.65, 0.925],
      headerBuilder: (isFullscreen) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFEA580C).withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.assignment_rounded,
                color: Color(0xFFEA580C),
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                isEditing ? 'Edit Jadwal Ujian' : 'Buat Jadwal Ujian Baru',
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
                      ? const Color(0xFFEA580C)
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
                        isEditing ? 'Simpan Perubahan' : 'Buat Ujian Baru',
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

                    // 1. Judul Ujian
                    _buildLabel('Judul Ujian *', isDark),
                    TextFormField(
                      controller: _titleController,
                      inputFormatters: [LengthLimitingTextInputFormatter(255)],
                      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                      style: TextStyle(color: isDark ? Colors.white : const Color(0xFF0F172A), fontSize: 13.5),
                      decoration: _buildInputDecoration(
                        hint: 'Contoh: PTS Matematika Wajib X-A',
                        icon: Icons.title_rounded,
                        isDark: isDark,
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Judul ujian wajib diisi';
                        if (v.trim().length < 3) return 'Judul ujian minimal 3 karakter';
                        if (v.trim().length > 255) return 'Judul ujian maksimal 255 karakter';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),

                    // 2. Mata Pelajaran
                    _buildLabel('Mata Pelajaran', isDark),
                    TextFormField(
                      controller: _subjectController,
                      inputFormatters: [LengthLimitingTextInputFormatter(100)],
                      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                      style: TextStyle(color: isDark ? Colors.white : const Color(0xFF0F172A), fontSize: 13.5),
                      decoration: _buildInputDecoration(
                        hint: 'Contoh: Matematika',
                        icon: Icons.book_rounded,
                        isDark: isDark,
                      ),
                    ),
                    const SizedBox(height: 14),

                    // 3. Link Soal CBT / URL
                    _buildLabel('Link Soal / URL CBT *', isDark),
                    TextFormField(
                      controller: _urlController,
                      keyboardType: TextInputType.url,
                      inputFormatters: [LengthLimitingTextInputFormatter(2048)],
                      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                      style: TextStyle(color: isDark ? Colors.white : const Color(0xFF0F172A), fontSize: 13),
                      decoration: _buildInputDecoration(
                        hint: 'https://docs.google.com/forms/d/... atau web CBT',
                        icon: Icons.link_rounded,
                        isDark: isDark,
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'URL soal ujian wajib diisi';
                        final trimmed = v.trim();
                        if (!RegExp(r'^https?:\/\/.+', caseSensitive: false).hasMatch(trimmed)) {
                          return 'Format URL tidak valid (harus diawali http:// atau https://)';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),

                    // 4. Target Kelas
                    ShieiSelectorField(
                      label: 'Target Kelas',
                      isDark: isDark,
                      prefixIcon: Icons.school_rounded,
                      valueText: _formatSelectedClassesText(),
                      onTap: () => _showClassMultiSelectSheet(context, isDark),
                    ),
                    const SizedBox(height: 14),

                    // 5. Tanggal Pelaksanaan Ujian (DatePicker)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildLabel('Tanggal Pelaksanaan Ujian *', isDark),
                        Text(
                          'Otomatis aktif sesuai jam',
                          style: TextStyle(fontSize: 10.5, color: isDark ? AppTheme.textSecondary : const Color(0xFF94A3B8)),
                        ),
                      ],
                    ),
                    InkWell(
                      onTap: _pickDate,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_month_rounded, color: Color(0xFFEA580C), size: 19),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                DateFormat('EEEE, d MMMM yyyy', 'id_ID').format(_selectedDate),
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                                ),
                              ),
                            ),
                            Icon(Icons.edit_calendar_rounded, size: 16, color: isDark ? AppTheme.textSecondary : const Color(0xFF94A3B8)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // 6. Jam Mulai & Selesai WIB (TimePicker) + Durasi Auto
                    Row(
                      children: [
                        // Jam Mulai
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildLabel('Mulai (WIB) *', isDark),
                              InkWell(
                                onTap: _pickStartTime,
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.access_time_rounded, size: 17, color: Color(0xFFEA580C)),
                                      const SizedBox(width: 8),
                                      Text(
                                        '${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}',
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.bold,
                                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Jam Selesai
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildLabel('Selesai (WIB) *', isDark),
                              InkWell(
                                onTap: _pickEndTime,
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.alarm_off_rounded, size: 17, color: Color(0xFFEA580C)),
                                      const SizedBox(width: 8),
                                      Text(
                                        '${_endTime.hour.toString().padLeft(2, '0')}:${_endTime.minute.toString().padLeft(2, '0')}',
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.bold,
                                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Durasi Otomatis Chip
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEA580C).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFEA580C).withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.timelapse_rounded, size: 16, color: Color(0xFFEA580C)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Durasi: ${FormatUtils.formatDurationHoursMinutes(_durationMinutes)}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFEA580C),
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEA580C).withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Auto Hitung',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFEA580C),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // 7. Mode Keamanan Token (Sliding TabBar Pill Slider)
                    _buildLabel('Mode Keamanan Token', isDark),
                    Container(
                      height: 42,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: TabBar(
                        controller: _tokenModeTabController,
                        onTap: (_) => FocusScope.of(context).unfocus(),
                        dividerColor: Colors.transparent,
                        dividerHeight: 0.0,
                        indicatorSize: TabBarIndicatorSize.tab,
                        indicator: BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B) : Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        labelColor: isDark ? Colors.white : const Color(0xFFEA580C),
                        unselectedLabelColor: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                        labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
                        tabs: const [
                          Tab(text: 'Tetap'),
                          Tab(text: 'Putar 5 Mnt'),
                          Tab(text: 'Tanpa Token'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    if (_tokenMode != 'none') ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildLabel('Kode PIN Token *', isDark),
                                 TextFormField(
                                  controller: _tokenController,
                                  textCapitalization: TextCapitalization.characters,
                                  maxLength: 6,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
                                    LengthLimitingTextInputFormatter(6),
                                  ],
                                  onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    letterSpacing: 2,
                                    color: Color(0xFFF97316),
                                  ),
                                  decoration: _buildInputDecoration(
                                    hint: '6 digit PIN',
                                    icon: Icons.key_rounded,
                                    isDark: isDark,
                                    counterText: '',
                                  ),
                                  validator: (v) {
                                    if (_tokenMode != 'none') {
                                      if (v == null || v.trim().isEmpty) {
                                        return 'Kode token ujian wajib diisi';
                                      }
                                      if (v.trim().length != 6) {
                                        return 'Kode token harus tepat 6 karakter';
                                      }
                                    }
                                    return null;
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            height: 48,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFF97316).withValues(alpha: 0.15),
                                foregroundColor: const Color(0xFFF97316),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(color: const Color(0xFFF97316).withValues(alpha: 0.4)),
                                ),
                              ),
                              icon: const Icon(Icons.shuffle_rounded, size: 16),
                              label: const Text('Acak PIN', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              onPressed: _generateRandomToken,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                    ],

                    // 8. Status Switch (Hanya Muncul saat Edit Ujian)
                    if (isEditing) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _isActive ? Icons.check_circle_rounded : Icons.pause_circle_rounded,
                              color: _isActive ? const Color(0xFF10B981) : const Color(0xFF64748B),
                              size: 22,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _isActive ? 'Status: Aktif' : 'Status: Nonaktif',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                                    ),
                                  ),
                                  Text(
                                    _isActive
                                        ? 'Ujian dapat diakses siswa sesuai jadwal'
                                        : 'Ujian dinonaktifkan secara manual',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch.adaptive(
                              value: _isActive,
                              activeTrackColor: const Color(0xFF10B981),
                              onChanged: (val) => setState(() => _isActive = val),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ] else ...[
                      // Info Banner Otomatisasi Jadwal (Saat Buat Ujian Baru)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.schedule_rounded, size: 18, color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Status pelaksanaan ujian akan otomatis aktif dan selesai mengikuti tanggal & rentang jam pengerjaan yang ditentukan.',
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
                      const SizedBox(height: 20),
                    ],
                          ],
                        ),
                      ),
                    ),
                  );
  }

  Widget _buildLabel(String text, bool isDark) {
    final isRequired = text.endsWith('*') || text.contains('*');
    if (!isRequired) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
          ),
        ),
      );
    }

    final cleanText = text.replaceAll('*', '').trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
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
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFEA580C), width: 1.5),
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
