import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/utils/format_utils.dart';
import '../../../shared/widgets/app_notification.dart';
import '../../../shared/widgets/shiei_animated_counter.dart';
import '../../../shared/widgets/shiei_checkbox.dart';
import '../../../shared/widgets/shiei_empty_state.dart';
import '../../../shared/widgets/shiei_skeleton.dart';
import '../detail/exam_detail_screen.dart';
import '../dialogs/broadcast_announcement_dialog.dart';
import '../dialogs/confirm_delete_dialog.dart';
import '../dialogs/confirm_unlock_dialog.dart';
import '../dialogs/exam_form_dialog.dart';
import '../dialogs/qr_unblock_scanner_dialog.dart';
import '../dialogs/student_action_sheet.dart';
import '../dialogs/student_detail_modal.dart';
import '../teacher_portal_controller.dart';
import '../../tour/proctor_tour_dialog.dart';

class ExamsMonitorTab extends StatefulWidget {
  final TeacherPortalController controller;
  final String? initialStatusFilter;
  final int? navigationTrigger;
  final ProctorTourTargetKeys? tourKeys;

  const ExamsMonitorTab({
    super.key,
    required this.controller,
    this.initialStatusFilter,
    this.navigationTrigger,
    this.tourKeys,
  });

  @override
  State<ExamsMonitorTab> createState() => ExamsMonitorTabState();
}

class _ExamAutoStatus {
  final String status; // 'upcoming', 'ongoing', 'finished', 'inactive'
  final String label;
  final Color badgeColor;
  final Color textColor;
  final Color borderColor;
  final Color dotColor;
  final String helperText;
  final bool isLive;

  const _ExamAutoStatus({
    required this.status,
    required this.label,
    required this.badgeColor,
    required this.textColor,
    required this.borderColor,
    required this.dotColor,
    required this.helperText,
    required this.isLive,
  });
}

_ExamAutoStatus _getExamAutoStatus(dynamic startTimeRaw, dynamic endTimeRaw, bool isActive) {
  if (!isActive) {
    return const _ExamAutoStatus(
      status: 'inactive',
      label: 'NONAKTIF',
      badgeColor: Color(0x1F64748B),
      textColor: Color(0xFF94A3B8),
      borderColor: Color(0x3364748B),
      dotColor: Color(0xFF64748B),
      helperText: 'Dinonaktifkan manual oleh pengawas',
      isLive: false,
    );
  }

  if (startTimeRaw == null || endTimeRaw == null) {
    return const _ExamAutoStatus(
      status: 'ongoing',
      label: 'AKTIF',
      badgeColor: Color(0x2410B981),
      textColor: Color(0xFF10B981),
      borderColor: Color(0x4D10B981),
      dotColor: Color(0xFF10B981),
      helperText: 'Aktif tanpa batasan waktu',
      isLive: true,
    );
  }

  final startStr = startTimeRaw.toString();
  final endStr = endTimeRaw.toString();
  DateTime? start = DateTime.tryParse(startStr)?.toLocal();
  DateTime? end = DateTime.tryParse(endStr)?.toLocal();

  if (start == null || end == null) {
    return const _ExamAutoStatus(
      status: 'ongoing',
      label: 'AKTIF',
      badgeColor: Color(0x2410B981),
      textColor: Color(0xFF10B981),
      borderColor: Color(0x4D10B981),
      dotColor: Color(0xFF10B981),
      helperText: 'Aktif',
      isLive: true,
    );
  }

  final now = DateTime.now();

  if (now.isBefore(start)) {
    return const _ExamAutoStatus(
      status: 'upcoming',
      label: 'TERJADWAL',
      badgeColor: Color(0x240284C7),
      textColor: Color(0xFF38BDF8),
      borderColor: Color(0x4D0284C7),
      dotColor: Color(0xFF0284C7),
      helperText: 'Otomatis aktif sesuai jadwal waktu',
      isLive: false,
    );
  }

  if (now.isAfter(start) && now.isBefore(end)) {
    return const _ExamAutoStatus(
      status: 'ongoing',
      label: 'AKTIF (BERLANGSUNG)',
      badgeColor: Color(0x2610B981),
      textColor: Color(0xFF10B981),
      borderColor: Color(0x5910B981),
      dotColor: Color(0xFF10B981),
      helperText: 'Sedang berlangsung, siswa dapat ujian',
      isLive: true,
    );
  }

  return const _ExamAutoStatus(
    status: 'finished',
    label: 'SELESAI',
    badgeColor: Color(0x1F64748B),
    textColor: Color(0xFF94A3B8),
    borderColor: Color(0x3364748B),
    dotColor: Color(0xFF64748B),
    helperText: 'Waktu ujian telah berakhir',
    isLive: false,
  );
}

class ExamsMonitorTabState extends State<ExamsMonitorTab> with TickerProviderStateMixin {
  /// Handles internal back navigation hierarchically within ExamsMonitorTab.
  /// Returns true if an internal layer was dismissed/reverted, false if at base state.
  bool handleBackNavigation() {
    // 1. Close speed dial if open
    if (_isSpeedDialOpen) {
      _closeSpeedDial();
      return true;
    }

    // 2. Exit exam selection mode if active
    if (_isExamSelectionMode) {
      _exitExamSelectionMode();
      return true;
    }

    // 3. Clear search controllers if not empty
    if (_searchController.text.isNotEmpty) {
      _searchController.clear();
      return true;
    }
    if (_examSearchController.text.isNotEmpty) {
      _examSearchController.clear();
      return true;
    }

    // 4. Reset monitor status filter if active
    if (widget.controller.monitorFilter != null) {
      widget.controller.setMonitorFilter(null);
      return true;
    }

    return false;
  }

  int _activeSegment = 0; // 0 = Live Monitor, 1 = Jadwal Ujian
  PageController? _pageController;
  PageController get _effectivePageController {
    return _pageController ??= PageController(initialPage: _activeSegment);
  }
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _examSearchController = TextEditingController();
  String _examScheduleFilter = 'all'; // 'all', 'ongoing', 'upcoming', 'finished', 'inactive'

  // Speed Dial FAB State
  final GlobalKey _fabKey = GlobalKey();
  AnimationController? _speedDialController;
  AnimationController get _effectiveSpeedDialController {
    return _speedDialController ??= AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
      reverseDuration: const Duration(milliseconds: 180),
    );
  }
  bool _isSpeedDialOpen = false;
  OverlayEntry? _speedDialOverlayEntry;

  final Set<int> _selectedExamIds = {};
  bool _isExamSelectionMode = false;

  void _enterExamSelectionMode(int id) {
    if (_isSpeedDialOpen) _closeSpeedDial(immediate: true);
    if (!widget.controller.isAdmin) return;
    HapticFeedback.heavyImpact();
    setState(() {
      _isExamSelectionMode = true;
      _selectedExamIds.add(id);
    });
  }

  void _toggleExamSelection(int id) {
    if (!widget.controller.isAdmin) return;
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedExamIds.contains(id)) {
        _selectedExamIds.remove(id);
        if (_selectedExamIds.isEmpty) {
          _isExamSelectionMode = false;
        }
      } else {
        _selectedExamIds.add(id);
      }
    });
  }

  void _selectAllExams(List<Map<String, dynamic>> filteredExams) {
    if (!widget.controller.isAdmin) return;
    HapticFeedback.lightImpact();
    final allIds = filteredExams
        .map((e) => e['id'] is int ? e['id'] as int : int.tryParse(e['id']?.toString() ?? ''))
        .whereType<int>()
        .toSet();

    setState(() {
      if (_selectedExamIds.containsAll(allIds)) {
        _selectedExamIds.clear();
        _isExamSelectionMode = false;
      } else {
        _selectedExamIds.addAll(allIds);
        _isExamSelectionMode = true;
      }
    });
  }

  void _exitExamSelectionMode() {
    setState(() {
      _isExamSelectionMode = false;
      _selectedExamIds.clear();
    });
  }

  Future<void> _confirmBulkDeleteExams(BuildContext context) async {
    if (!widget.controller.isAdmin || _selectedExamIds.isEmpty) return;

    final count = _selectedExamIds.length;
    final confirmed = await ConfirmDeleteDialog.show(
      context: context,
      title: 'Hapus $count Jadwal Ujian Terpilih?',
      itemType: 'Jadwal Ujian',
      itemName: '$count jadwal ujian terpilih',
      message: 'Semua jadwal ujian yang dipilih beserta rekaman sesi peserta terkait akan dihapus secara permanen dari server.',
      confirmLabel: 'Hapus Massal',
      onConfirm: () async {
        final idsList = _selectedExamIds.toList();
        return await widget.controller.bulkDeleteExams(idsList);
      },
    );

    if (confirmed == true) {
      _exitExamSelectionMode();
      if (context.mounted) {
        AppNotification.showSuccess(
          context,
          'Berhasil Menghapus Jadwal Ujian',
          subtitle: '$count jadwal ujian berhasil dihapus sekaligus.',
        );
      }
    }
  }

  // --- SPEED DIAL METHODS ---
  void _toggleSpeedDial() {
    HapticFeedback.selectionClick();
    if (_isSpeedDialOpen) {
      _closeSpeedDial();
    } else {
      _openSpeedDial();
    }
  }

  void _openSpeedDial() {
    if (_isSpeedDialOpen) return;

    final renderBox = _fabKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final fabOffset = renderBox.localToGlobal(Offset.zero);
    final Size fabSize = renderBox.size;
    final isDark = AppTheme.isDark(context);
    final items = _getSpeedDialItems(isDark);
    if (items.isEmpty) return;

    setState(() => _isSpeedDialOpen = true);

    final ctrl = _effectiveSpeedDialController;
    _speedDialOverlayEntry = OverlayEntry(
      builder: (overlayContext) {
        return _ExamSpeedDialOverlayWidget(
          animation: ctrl.view,
          isDark: isDark,
          fabOffset: fabOffset,
          fabSize: fabSize,
          items: items,
          onClose: () => _closeSpeedDial(),
        );
      },
    );

    Overlay.of(context, rootOverlay: true).insert(_speedDialOverlayEntry!);
    ctrl.forward();
  }

  Future<void> _closeSpeedDial({bool immediate = false}) async {
    if (!_isSpeedDialOpen) return;
    if (immediate) {
      _speedDialController?.reset();
      _speedDialOverlayEntry?.remove();
      _speedDialOverlayEntry = null;
      if (mounted) setState(() => _isSpeedDialOpen = false);
      return;
    }
    await _speedDialController?.reverse();
    _speedDialOverlayEntry?.remove();
    _speedDialOverlayEntry = null;
    if (mounted) setState(() => _isSpeedDialOpen = false);
  }

  List<_ExamSpeedDialItem> _getSpeedDialItems(bool isDark) {
    return [
      _ExamSpeedDialItem(
        label: 'Buat Jadwal Ujian Baru',
        icon: Icons.add_task_rounded,
        color: const Color(0xFFEA580C),
        onTap: () async {
          await _closeSpeedDial();
          if (!mounted) return;
          ExamFormDialog.show(
            context: context,
            controller: widget.controller,
          );
        },
      ),
    ];
  }

  @override
  void initState() {
    super.initState();
    _speedDialController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
      reverseDuration: const Duration(milliseconds: 180),
    );
    _searchController.addListener(() {
      if (mounted) setState(() {});
    });
    _examSearchController.addListener(() {
      if (mounted) setState(() {});
    });
    if (widget.initialStatusFilter == 'locked') {
      _activeSegment = 2;
    } else if (widget.initialStatusFilter == 'active_exams' || widget.initialStatusFilter == 'exams') {
      _activeSegment = widget.controller.activeLiveExams.isNotEmpty ? 0 : 1;
    }
    _pageController = PageController(initialPage: _activeSegment);
    if (widget.initialStatusFilter != null &&
        widget.initialStatusFilter != 'locked' &&
        widget.initialStatusFilter != 'active_exams' &&
        widget.initialStatusFilter != 'exams') {
      widget.controller.setMonitorFilter(widget.initialStatusFilter);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.controller.loadExams();
        widget.controller.loadMonitoringData(silent: true);
      }
    });
  }

  @override
  void didUpdateWidget(covariant ExamsMonitorTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((widget.navigationTrigger != oldWidget.navigationTrigger ||
            widget.initialStatusFilter != oldWidget.initialStatusFilter) &&
        widget.initialStatusFilter != null) {
      if (widget.initialStatusFilter == 'locked') {
        if (_activeSegment != 2) {
          setState(() => _activeSegment = 2);
          if (_effectivePageController.hasClients) {
            _effectivePageController.animateToPage(
              2,
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeInOutCubic,
            );
          }
        }
      } else if (widget.initialStatusFilter == 'active_exams' || widget.initialStatusFilter == 'exams') {
        final target = widget.controller.activeLiveExams.isNotEmpty ? 0 : 1;
        if (_activeSegment != target) {
          setState(() => _activeSegment = target);
          if (_effectivePageController.hasClients) {
            _effectivePageController.animateToPage(
              target,
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeInOutCubic,
            );
          }
        }
      } else {
        if (_activeSegment != 0) {
          setState(() => _activeSegment = 0);
          if (_effectivePageController.hasClients) {
            _effectivePageController.animateToPage(
              0,
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeInOutCubic,
            );
          }
        }
        widget.controller.setMonitorFilter(widget.initialStatusFilter);
      }
    }
  }

  @override
  void dispose() {
    if (_speedDialOverlayEntry != null) {
      _speedDialOverlayEntry?.remove();
      _speedDialOverlayEntry = null;
    }
    _speedDialController?.dispose();
    _pageController?.dispose();
    _searchController.dispose();
    _examSearchController.dispose();
    super.dispose();
  }

  void _showStudentActionSheet(
    BuildContext context,
    Map<String, dynamic> record, {
    String modalType = 'participant',
  }) {
    final user = record['user'] as Map<String, dynamic>? ?? {};
    final link = record['link'] as Map<String, dynamic>? ?? {};

    final dynamic examId = record['link_id'] ?? link['id'];
    final String examTitle = link['title']?.toString() ?? 'Ujian';
    final bool isExamEnded = (link['status']?.toString() == 'inactive') || (record['is_exam_ended'] == true);
    final String userClass = user['class_major']?['name']?.toString() ??
        user['classes']?['name']?.toString() ??
        user['class_name']?.toString() ??
        '';

    StudentActionSheet.show(
      context: context,
      controller: widget.controller,
      record: record,
      examId: examId,
      examTitle: examTitle,
      isExamEnded: isExamEnded,
      onRefresh: () => widget.controller.loadMonitoringData(silent: true),
      onOpenAuditDetail: () => StudentDetailModal.show(
        context: context,
        controller: widget.controller,
        item: record,
        examId: examId,
        examTitle: examTitle,
        defaultClassName: userClass,
        modalType: modalType,
        isExamEnded: isExamEnded,
        onRefresh: () => widget.controller.loadMonitoringData(silent: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final records = widget.controller.filteredMonitoringRecords;
    final exams = widget.controller.exams;

    return Column(
      children: [
        // 1. Top Segmented Tabs [ Live Monitor ] vs [ Jadwal Ujian ] vs [ Catatan Pelanggaran ]
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isDark ? AppTheme.surfaceDark : Colors.white,
            border: Border(
              bottom: BorderSide(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
              ),
            ),
          ),
          child: Container(
            key: widget.tourKeys?.monitorSegmentKey,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final totalWidth = constraints.maxWidth;
                final itemWidth = totalWidth / 3;

                return Stack(
                  children: [
                    // Sliding Pill Indicator (Buttery smooth 60/120fps hardware animated)
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeInOutCubic,
                      left: _activeSegment * itemWidth,
                      top: 0,
                      bottom: 0,
                      width: itemWidth,
                      child: Container(
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B) : Colors.white,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF475569).withValues(alpha: 0.3)
                                : const Color(0xFFE2E8F0),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
                              blurRadius: 5,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Interactive Segment Buttons
                    Row(
                      children: [
                        Expanded(
                          child: _buildSegmentButton(
                            title: 'Live Monitor',
                            count: widget.controller.totalMonitoringStudents,
                            isSelected: _activeSegment == 0,
                            isDark: isDark,
                            onTap: () {
                              FocusManager.instance.primaryFocus?.unfocus();
                              if (_isSpeedDialOpen) _closeSpeedDial(immediate: true);
                              if (_isExamSelectionMode) _exitExamSelectionMode();
                              _effectivePageController.animateToPage(
                                0,
                                duration: const Duration(milliseconds: 280),
                                curve: Curves.easeInOutCubic,
                              );
                            },
                          ),
                        ),
                        Expanded(
                          child: _buildSegmentButton(
                            title: 'Jadwal Ujian',
                            count: exams.length,
                            isSelected: _activeSegment == 1,
                            isDark: isDark,
                            onTap: () {
                              FocusManager.instance.primaryFocus?.unfocus();
                              if (_isSpeedDialOpen) _closeSpeedDial(immediate: true);
                              _effectivePageController.animateToPage(
                                1,
                                duration: const Duration(milliseconds: 280),
                                curve: Curves.easeInOutCubic,
                              );
                            },
                          ),
                        ),
                        Expanded(
                          child: _buildSegmentButton(
                            title: 'Pelanggaran',
                            count: widget.controller.lockedCount,
                            isSelected: _activeSegment == 2,
                            isDark: isDark,
                            isAlert: widget.controller.lockedCount > 0,
                            onTap: () {
                              FocusManager.instance.primaryFocus?.unfocus();
                              if (_isSpeedDialOpen) _closeSpeedDial(immediate: true);
                              if (_isExamSelectionMode) _exitExamSelectionMode();
                              _effectivePageController.animateToPage(
                                2,
                                duration: const Duration(milliseconds: 280),
                                curve: Curves.easeInOutCubic,
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),

        // 2. Segment Content with Smooth Slider Motion & Swipe Gestures
        Expanded(
          child: PageView(
            controller: _effectivePageController,
            physics: const BouncingScrollPhysics(),
            onPageChanged: (page) {
              FocusManager.instance.primaryFocus?.unfocus();
              if (_isSpeedDialOpen) _closeSpeedDial(immediate: true);
              if (page != 1 && _isExamSelectionMode) {
                _exitExamSelectionMode();
              }
              setState(() => _activeSegment = page);
            },
            children: [
              _buildLiveMonitorContent(isDark, records),
              _buildExamScheduleContent(isDark, exams),
              _buildViolationLogContent(isDark, widget.controller.monitoringRecords),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSegmentButton({
    required String title,
    required int count,
    required bool isSelected,
    required bool isDark,
    required VoidCallback onTap,
    bool isAlert = false,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        color: Colors.transparent,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected
                    ? (isDark ? Colors.white : const Color(0xFF0F172A))
                    : (isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
              ),
            ),
            const SizedBox(width: 5),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: isAlert && count > 0
                    ? const Color(0xFFEF4444).withValues(alpha: 0.2)
                    : isSelected
                        ? const Color(0xFFF97316).withValues(alpha: 0.15)
                        : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                count.toString(),
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                  color: isAlert && count > 0
                      ? const Color(0xFFEF4444)
                      : isSelected
                          ? const Color(0xFFEA580C)
                          : (isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  // --- SUB-VIEW 3: LOG PELANGGARAN ---
  Widget _buildViolationLogContent(bool isDark, List<Map<String, dynamic>> records) {
    final violations = records.where((r) {
      final status = r['status']?.toString().toLowerCase() ?? 'pending';
      final lockReason = r['lock_reason']?.toString();
      final isLocked = r['is_locked'] == true || status == 'locked' || status == 'split_screen';
      final isKicked = status == 'terminated' || lockReason == 'proctor_kick' || r['is_kicked'] == true;
      return isLocked || isKicked || (lockReason != null && lockReason.isNotEmpty);
    }).toList();

    final Widget listContent = (widget.controller.isLoading || widget.controller.isMonitoringLoading)
        ? const ParticipantRowSkeleton(
            count: 5,
            padding: EdgeInsets.fromLTRB(16, 12, 16, 100),
            physics: AlwaysScrollableScrollPhysics(),
          )
        : violations.isEmpty
        ? ShieiEmptyState(
            title: 'Tidak Ada Pelanggaran Aktif',
            message: 'Semua sesi peserta yang sedang berjalan tertib dan tidak ada status terkunci.',
            icon: Icons.verified_user_rounded,
            accentColor: const Color(0xFF10B981),
            isDark: isDark,
          )
        : ListView.builder(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              itemCount: violations.length,
              itemBuilder: (ctx, index) {
                final record = violations[index];
                final user = record['user'] as Map<String, dynamic>? ?? {};
                final link = record['link'] as Map<String, dynamic>? ?? {};
                final studentName = user['name']?.toString() ?? 'Siswa';
                final rawNisn = user['nisn']?.toString().trim();
                final rawUsername = user['username']?.toString().trim();
                final nisn = (rawNisn != null && rawNisn.isNotEmpty && rawNisn != '-')
                    ? rawNisn
                    : (rawUsername != null && rawUsername.isNotEmpty && rawUsername != '-')
                        ? rawUsername
                        : '-';
                final examTitle = link['title']?.toString() ?? 'Ujian';
                final lockReason = record['lock_reason']?.toString();
                final userClass = user['class_major']?['name']?.toString() ??
                    user['classes']?['name']?.toString() ??
                    user['class_name']?.toString() ??
                    '';
                final deviceName = user['device_name']?.toString() ?? user['device_id']?.toString();
                final serial = user['serial_number']?.toString();
                final bool hasBoundDevice = (deviceName != null && deviceName.isNotEmpty) || (serial != null && serial.isNotEmpty);

                final status = record['status']?.toString().toLowerCase() ?? 'pending';
                final bool isKicked = status == 'terminated' || record['lock_reason'] == 'proctor_kick' || record['is_kicked'] == true;
                final bool isLocked = !isKicked && (record['is_locked'] == true || status == 'locked' || status == 'split_screen');
                final bool isExamEnded = (link['status']?.toString() == 'inactive') || (record['is_exam_ended'] == true);
                final bool wasUnlocked = record['unlocked_at'] != null ||
                    record['unlocked_by'] != null ||
                    (!isLocked && !isKicked && (lockReason != null && lockReason.isNotEmpty));
                final dynamic examId = link['id'] ?? record['link_id'] ?? record['exam_id'];
                final bool canManageStudent = widget.controller.isAdmin || widget.controller.canUnlockStudentForExam(examId, exam: link);

                final rawIncidentTime = record['occurred_at'] ??
                    record['locked_at'] ??
                    record['lock_time'] ??
                    record['created_at'] ??
                    record['updated_at'];
                String incidentTimeFormatted = '';
                if (rawIncidentTime != null) {
                  try {
                    final dt = DateTime.parse(rawIncidentTime.toString()).toLocal();
                    incidentTimeFormatted = '${DateFormat('d MMM, HH:mm', 'id_ID').format(dt)} WIB';
                  } catch (_) {
                    incidentTimeFormatted = rawIncidentTime.toString();
                  }
                }

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1B1E) : const Color(0xFFFFF1F2),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.35),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.security_update_warning_rounded,
                              color: Color(0xFFEF4444),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        studentName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
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
                                                ? 'TERKUNCI'
                                                : 'SUDAH DIBUKA',
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
                                const SizedBox(height: 4),
                                // Line 1: Class Badge + NISN + Exam Title
                                Row(
                                  children: [
                                    if (userClass.isNotEmpty) ...[
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(5),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.school_outlined, size: 10, color: Color(0xFF8B5CF6)),
                                            const SizedBox(width: 3),
                                            Text(
                                              'Kelas $userClass',
                                              style: const TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFF8B5CF6),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                    ],
                                    Expanded(
                                      child: Text(
                                        examTitle.isNotEmpty && examTitle != 'Ujian'
                                            ? 'NISN: $nisn • $examTitle'
                                            : 'NISN: $nisn',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                          color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                // Line 2: Device Binding Row
                                Row(
                                  children: [
                                    Icon(
                                      hasBoundDevice ? Icons.phonelink_lock_rounded : Icons.phonelink_off_rounded,
                                      size: 12,
                                      color: hasBoundDevice ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        hasBoundDevice ? '${deviceName ?? serial}' : 'Belum terikat ke perangkat',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          color: hasBoundDevice
                                              ? (isDark ? const Color(0xFF10B981) : const Color(0xFF059669))
                                              : (isDark ? AppTheme.textSecondary : const Color(0xFF94A3B8)),
                                          fontWeight: hasBoundDevice ? FontWeight.w600 : FontWeight.normal,
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
                      const SizedBox(height: 10),
                      // Violation Reason & Incident Time Box
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.2)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.warning_amber_rounded, size: 14, color: Color(0xFFEF4444)),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Pelanggaran: ${StudentDetailModal.formatViolationReason(lockReason)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFEF4444),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (incidentTimeFormatted.isNotEmpty) ...[
                              const SizedBox(height: 5),
                              Row(
                                children: [
                                  const Icon(Icons.access_time_rounded, size: 11, color: Color(0xFFEF4444)),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Kejadian: $incidentTimeFormatted',
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFFEF4444),
                                    ),
                                  ),
                                  if (wasUnlocked) ...[
                                    const SizedBox(width: 8),
                                    const Icon(Icons.lock_open_rounded, size: 11, color: Color(0xFF10B981)),
                                    const SizedBox(width: 3),
                                    const Text(
                                      'Kunci sudah dibuka',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF10B981),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isLocked && !isExamEnded
                                ? (canManageStudent
                                    ? const Color(0xFFEA580C)
                                    : (isDark ? const Color(0xFF334155) : const Color(0xFF475569)))
                                : (isDark ? const Color(0xFF334155) : const Color(0xFF475569)),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            elevation: 0,
                          ),
                          icon: Icon(
                            isLocked && !isExamEnded
                                ? (canManageStudent ? Icons.lock_open_rounded : Icons.visibility_rounded)
                                : Icons.visibility_rounded,
                            size: 15,
                          ),
                          label: Text(
                            isLocked && !isExamEnded
                                ? (canManageStudent ? 'Periksa & Buka Kunci' : 'Periksa')
                                : 'Lihat Detail Audit',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          onPressed: () => _showStudentActionSheet(context, record, modalType: 'violation'),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );

    if (widget.controller.isConnectionLost) {
      return Column(
        children: [
          _buildSyncStatusIndicator(isDark),
          Expanded(
            child: RefreshIndicator(
              color: const Color(0xFFEF4444),
              onRefresh: () => widget.controller.loadMonitoringData(clearPrevious: true),
              child: listContent,
            ),
          ),
        ],
      );
    }

    return RefreshIndicator(
      color: const Color(0xFFEF4444),
      onRefresh: () => widget.controller.loadMonitoringData(clearPrevious: true),
      child: listContent,
    );
  }

  // --- REAL-TIME CONNECTIVITY & SYNC STATUS INDICATOR ---
  Widget _buildClockCounter(DateTime time, bool isDark, {Color? customColor}) {
    final textColor = customColor ?? (isDark ? Colors.white : const Color(0xFF0F172A));
    final colonColor = customColor ?? (isDark ? AppTheme.textSecondary : const Color(0xFF94A3B8));
    final wibColor = customColor ?? (isDark ? AppTheme.textSecondary : const Color(0xFF64748B));

    final numberStyle = TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.bold,
      color: textColor,
      fontFamily: 'monospace',
    );
    final colonStyle = TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.bold,
      color: colonColor,
    );
    final wibStyle = TextStyle(
      fontSize: 9.5,
      fontWeight: FontWeight.w600,
      color: wibColor,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ShieiAnimatedCounter(
          count: time.hour,
          padDigits: 2,
          style: numberStyle,
        ),
        Text(':', style: colonStyle),
        ShieiAnimatedCounter(
          count: time.minute,
          padDigits: 2,
          style: numberStyle,
        ),
        Text(':', style: colonStyle),
        ShieiAnimatedCounter(
          count: time.second,
          padDigits: 2,
          style: numberStyle,
        ),
        Text(' WIB', style: wibStyle),
      ],
    );
  }

  Widget _buildSyncStatusIndicator(bool isDark) {
    final bool isDisconnected = widget.controller.isConnectionLost;
    final bool isAutoRefresh = widget.controller.autoRefresh;
    final DateTime? lastSyncTime = widget.controller.lastSyncTime;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isDisconnected
              ? const Color(0xFFEF4444).withValues(alpha: isDark ? 0.15 : 0.1)
              : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC)),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isDisconnected
                ? const Color(0xFFEF4444).withValues(alpha: 0.35)
                : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
          ),
        ),
        child: Row(
          children: [
            if (isDisconnected) ...[
              const Icon(Icons.wifi_off_rounded, size: 13, color: Color(0xFFEF4444)),
              const SizedBox(width: 6),
              const Text(
                'Koneksi Terputus',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFEF4444),
                ),
              ),
              Container(
                width: 1,
                height: 10,
                margin: const EdgeInsets.symmetric(horizontal: 7),
                color: const Color(0xFFEF4444).withValues(alpha: 0.35),
              ),
              Expanded(
                child: lastSyncTime != null
                    ? FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Data Terakhir: ',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFFEF4444),
                              ),
                            ),
                            _buildClockCounter(lastSyncTime, isDark, customColor: const Color(0xFFEF4444)),
                          ],
                        ),
                      )
                    : const Text(
                        'Tidak dapat terhubung ke server',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFFEF4444),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
              ),
              InkWell(
                onTap: () => widget.controller.loadMonitoringData(clearPrevious: false),
                borderRadius: BorderRadius.circular(4),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Text(
                    'Coba Lagi',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFEF4444),
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
            ] else ...[
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: isAutoRefresh ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              ValueListenableBuilder<int>(
                valueListenable: widget.controller.syncCountdown,
                builder: (context, countdown, _) {
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isAutoRefresh ? 'Live Sync (' : 'Sync Manual',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: isAutoRefresh
                              ? (isDark ? const Color(0xFF34D399) : const Color(0xFF059669))
                              : (isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
                        ),
                      ),
                      if (isAutoRefresh) ...[
                        ShieiAnimatedCounter(
                          count: countdown,
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeInOutCubic,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
                          ),
                        ),
                        Text(
                          's)',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
              Container(
                width: 1,
                height: 10,
                margin: const EdgeInsets.symmetric(horizontal: 7),
                color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
              ),
              Expanded(
                child: lastSyncTime != null
                    ? FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Pembaruan: ',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w500,
                                color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                              ),
                            ),
                            _buildClockCounter(lastSyncTime, isDark),
                          ],
                        ),
                      )
                    : Text(
                        'Menghubungkan ke server...',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                          color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
              ),
              InkWell(
                onTap: () => widget.controller.toggleAutoRefresh(!isAutoRefresh),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Text(
                    isAutoRefresh ? 'Jeda' : 'Aktifkan',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: isAutoRefresh ? const Color(0xFFEA580C) : const Color(0xFF10B981),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // --- SUB-VIEW 1: LIVE MONITOR ---
  Widget _buildLiveMonitorContent(bool isDark, List<Map<String, dynamic>> records) {
    return Column(
      children: [
        // Search & Filter Row
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            onSubmitted: (_) => FocusScope.of(context).unfocus(),
            onChanged: (val) {
              widget.controller.setMonitorSearch(val);
              setState(() {});
            },
            style: TextStyle(fontSize: 13, color: isDark ? Colors.white : const Color(0xFF0F172A)),
            decoration: InputDecoration(
              hintText: 'Cari nama siswa, NISN, atau ujian...',
              hintStyle: TextStyle(fontSize: 12, color: isDark ? AppTheme.textSecondary : const Color(0xFF94A3B8)),
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              suffixIcon: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _searchController,
                builder: (context, value, _) {
                  if (value.text.isEmpty) return const SizedBox.shrink();
                  return IconButton(
                    icon: const Icon(Icons.cancel_rounded, size: 18, color: Color(0xFF94A3B8)),
                    splashRadius: 18,
                    tooltip: 'Hapus Teks Pencarian',
                    onPressed: () {
                      _searchController.clear();
                      widget.controller.setMonitorSearch('');
                      setState(() {});
                    },
                  );
                },
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              filled: true,
              fillColor: isDark ? AppTheme.surfaceDark : Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
              ),
            ),
          ),
        ),

        // Proctor Action Bar (Scan QR + Broadcast Announcement)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => QrUnblockScannerDialog.show(context: context, controller: widget.controller),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.qr_code_scanner_rounded, size: 16, color: Color(0xFF8B5CF6)),
                        SizedBox(width: 6),
                        Text(
                          'Scan QR Siswa',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF8B5CF6)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Builder(
                  builder: (ctx) {
                    final bool hasActiveExams = widget.controller.activeExams.isNotEmpty;
                    return InkWell(
                      onTap: hasActiveExams
                          ? () => BroadcastAnnouncementDialog.show(context: context, controller: widget.controller)
                          : () => AppNotification.showInfo(
                                context,
                                'Tidak Ada Ujian Aktif',
                                subtitle: 'Siaran pengumuman hanya tersedia ketika ada ujian yang sedang berlangsung.',
                              ),
                      borderRadius: BorderRadius.circular(10),
                      child: Opacity(
                        opacity: hasActiveExams ? 1.0 : 0.55,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.campaign_rounded, size: 16, color: Color(0xFFF59E0B)),
                              SizedBox(width: 6),
                              Text(
                                'Siarkan Ralat',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFF59E0B)),
                              ),
                            ],
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

        // Filter chips horizontal scroll
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            children: [
              _buildFilterChip('Semua', null, isDark),
              const SizedBox(width: 8),
              _buildFilterChip('Sedang Ujian', 'in_progress', isDark, count: widget.controller.inProgressCount),
              const SizedBox(width: 8),
              _buildFilterChip('Terkunci / Curang', 'locked', isDark, count: widget.controller.lockedCount, isAlert: true),
              const SizedBox(width: 8),
              _buildFilterChip('Selesai', 'completed', isDark, count: widget.controller.completedCount),
            ],
          ),
        ),
        const SizedBox(height: 4),

        // Live Connectivity & Sync Status Bar
        _buildSyncStatusIndicator(isDark),

        // Students Records List
        Expanded(
          child: RefreshIndicator(
            color: const Color(0xFFF97316),
            onRefresh: () => widget.controller.loadMonitoringData(clearPrevious: true),
            child: (widget.controller.isLoading || widget.controller.isMonitoringLoading)
                ? const ParticipantRowSkeleton(
                    count: 5,
                    padding: EdgeInsets.fromLTRB(16, 6, 16, 100),
                    physics: AlwaysScrollableScrollPhysics(),
                  )
                : records.isEmpty
                ? SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Container(
                        key: widget.tourKeys?.studentSessionKey,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark ? AppTheme.surfaceDark : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFFF97316).withValues(alpha: isDark ? 0.35 : 0.25),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF97316).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.person_search_rounded, color: Color(0xFFF97316), size: 20),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Area Monitoring Sesi Peserta',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Buka Kunci • Reset Sesi • Baterai & PIN',
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
                            const SizedBox(height: 12),
                            Text(
                              'Saat jadwal ujian berlangsung, kartu peserta akan otomatis tampil di sini secara real-time untuk memantau status pengerjaan siswa.',
                              style: TextStyle(
                                fontSize: 11.5,
                                height: 1.45,
                                color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 100),
                    itemCount: records.length,
                    itemBuilder: (ctx, index) {
                      final item = records[index];
                      final card = _buildStudentCard(ctx, item, isDark);
                      if (index == 0) {
                        return KeyedSubtree(
                          key: widget.tourKeys?.studentSessionKey,
                          child: card,
                        );
                      }
                      return card;
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label, String? value, bool isDark, {int? count, bool isAlert = false}) {
    final isSelected = widget.controller.monitorStatusFilter == value;
    final activeColor = isAlert ? const Color(0xFFEF4444) : const Color(0xFFF97316);

    return GestureDetector(
      onTap: () {
        FocusManager.instance.primaryFocus?.unfocus();
        widget.controller.setMonitorFilter(value);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor.withValues(alpha: 0.15)
              : (isDark ? AppTheme.surfaceDark : Colors.white),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? activeColor
                : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
            width: isSelected ? 1.4 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected
                    ? (isDark ? Colors.white : activeColor)
                    : (isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected ? activeColor : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  count.toString(),
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? Colors.white : (isDark ? AppTheme.textSecondary : const Color(0xFF475569)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStudentCard(BuildContext context, Map<String, dynamic> record, bool isDark) {
    final user = record['user'] as Map<String, dynamic>? ?? {};
    final link = record['link'] as Map<String, dynamic>? ?? {};
    final dynamic examId = record['link_id'] ?? link['id'];
    final String examTitle = link['title']?.toString() ?? 'Ujian';
    final String status = record['status']?.toString().toLowerCase() ?? 'pending';
    final String? lockReason = record['lock_reason']?.toString();
    final bool isKicked = status == 'terminated' || lockReason == 'proctor_kick' || record['is_kicked'] == true;
    final bool isLocked = !isKicked && (record['is_locked'] == true || status == 'locked' || status == 'split_screen');
    final bool isCompleted = status == 'completed' || status == 'submitted' || record['score'] != null;
    final bool isExamEnded = (link['status']?.toString() == 'inactive') || (record['is_exam_ended'] == true);
    final bool isExpired = isExamEnded && !isKicked && !isLocked && !isCompleted;
    final bool canManageStudent = widget.controller.isAdmin || widget.controller.canUnlockStudentForExam(examId, exam: link);
    final bool canUnlock = isLocked && !isExamEnded && !isKicked && canManageStudent;

    final studentName = user['name']?.toString() ?? 'Siswa';
    final rawNisn = user['nisn']?.toString().trim();
    final rawUsername = user['username']?.toString().trim();
    final nisn = (rawNisn != null && rawNisn.isNotEmpty && rawNisn != '-')
        ? rawNisn
        : (rawUsername != null && rawUsername.isNotEmpty && rawUsername != '-')
            ? rawUsername
            : '-';
    final userClass = user['class_major']?['name']?.toString() ??
        user['classes']?['name']?.toString() ??
        user['class_name']?.toString() ??
        '';
    final deviceName = user['device_name']?.toString() ?? user['device_id']?.toString();
    final serial = user['serial_number']?.toString();
    final bool hasBoundDevice = (deviceName != null && deviceName.isNotEmpty) || (serial != null && serial.isNotEmpty);
    final extraMins = record['extra_minutes'] is int ? record['extra_minutes'] as int : int.tryParse(record['extra_minutes']?.toString() ?? '') ?? 0;
    final score = record['score'];

    Color cardBorderColor;
    Color avatarBg;
    Color iconColor;
    IconData statusIcon;
    String statusLabel;
    Color statusBadgeBg;
    Color statusBadgeTextColor;

    if (isKicked) {
      cardBorderColor = const Color(0xFFBE123C).withValues(alpha: 0.35);
      avatarBg = const Color(0xFFBE123C).withValues(alpha: 0.12);
      iconColor = const Color(0xFFBE123C);
      statusIcon = Icons.person_off_rounded;
      statusLabel = 'DIKELUARKAN';
      statusBadgeBg = const Color(0xFFBE123C).withValues(alpha: 0.12);
      statusBadgeTextColor = const Color(0xFFBE123C);
    } else if (isLocked) {
      cardBorderColor = const Color(0xFFEF4444).withValues(alpha: 0.35);
      avatarBg = const Color(0xFFEF4444).withValues(alpha: 0.12);
      iconColor = const Color(0xFFEF4444);
      statusIcon = Icons.lock_rounded;
      statusLabel = 'TERKUNCI';
      statusBadgeBg = const Color(0xFFEF4444).withValues(alpha: 0.12);
      statusBadgeTextColor = const Color(0xFFEF4444);
    } else if (isCompleted) {
      cardBorderColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
      avatarBg = const Color(0xFF10B981).withValues(alpha: 0.12);
      iconColor = const Color(0xFF10B981);
      statusIcon = Icons.check_circle_rounded;
      statusLabel = score != null ? 'SELESAI ($score)' : 'SELESAI';
      statusBadgeBg = const Color(0xFF10B981).withValues(alpha: 0.12);
      statusBadgeTextColor = const Color(0xFF10B981);
    } else if (isExpired) {
      cardBorderColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
      avatarBg = const Color(0xFF64748B).withValues(alpha: 0.12);
      iconColor = const Color(0xFF64748B);
      statusIcon = Icons.access_time_rounded;
      statusLabel = 'WAKTU HABIS';
      statusBadgeBg = const Color(0xFF64748B).withValues(alpha: 0.12);
      statusBadgeTextColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569);
    } else {
      cardBorderColor = const Color(0xFF10B981).withValues(alpha: 0.35);
      avatarBg = const Color(0xFF10B981).withValues(alpha: 0.12);
      iconColor = const Color(0xFF10B981);
      statusIcon = Icons.sensors_rounded;
      statusLabel = 'SEDANG UJIAN';
      statusBadgeBg = const Color(0xFF10B981).withValues(alpha: 0.12);
      statusBadgeTextColor = const Color(0xFF10B981);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _showStudentActionSheet(context, record, modalType: 'participant'),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: avatarBg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          studentName.isNotEmpty ? studentName[0].toUpperCase() : 'S',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: iconColor,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  studentName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                                decoration: BoxDecoration(
                                  color: statusBadgeBg,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(statusIcon, size: 11, color: statusBadgeTextColor),
                                    const SizedBox(width: 4),
                                    Text(
                                      statusLabel,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: statusBadgeTextColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.chevron_right_rounded,
                                size: 18,
                                color: isDark ? const Color(0xFF475569) : const Color(0xFF94A3B8),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          // Line 1: Class Badge + NISN
                          Row(
                            children: [
                              if (userClass.isNotEmpty) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF8B5CF6).withValues(alpha: isDark ? 0.16 : 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: const Color(0xFF8B5CF6).withValues(alpha: isDark ? 0.35 : 0.22),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.school_outlined, size: 11.5, color: Color(0xFF8B5CF6)),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Kelas $userClass',
                                        style: const TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF8B5CF6),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                              ],
                              Text(
                                'NISN: $nisn',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w500,
                                  color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          // Line 2: Exam title badge
                          if (examTitle.isNotEmpty && examTitle != '-') ...[
                            Row(
                              children: [
                                Icon(Icons.assignment_outlined, size: 12.5, color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    examTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                          ],
                          // Line 3: Device binding row + extra mins + ketuk detail
                          Row(
                            children: [
                              Icon(
                                hasBoundDevice ? Icons.phonelink_lock_rounded : Icons.phonelink_off_rounded,
                                size: 13,
                                color: hasBoundDevice ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  hasBoundDevice ? '${deviceName ?? serial}' : 'Belum terikat ke perangkat',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: hasBoundDevice
                                        ? (isDark ? const Color(0xFF10B981) : const Color(0xFF059669))
                                        : (isDark ? AppTheme.textSecondary : const Color(0xFF94A3B8)),
                                    fontWeight: hasBoundDevice ? FontWeight.w600 : FontWeight.normal,
                                  ),
                                ),
                              ),
                              if (extraMins != 0) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: extraMins > 0
                                        ? const Color(0xFFF59E0B).withValues(alpha: 0.15)
                                        : const Color(0xFFEF4444).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    extraMins > 0 ? '+$extraMins m' : '$extraMins m',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: extraMins > 0 ? const Color(0xFFF59E0B) : const Color(0xFFEF4444),
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(width: 8),
                              Text(
                                'Ketuk untuk aksi',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (isLocked && lockReason != null && lockReason.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, size: 14, color: Color(0xFFEF4444)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Pelanggaran: ${StudentDetailModal.formatViolationReason(lockReason)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFEF4444),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (canUnlock) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEA580C),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.lock_open_rounded, size: 15),
                      label: const Text('Buka Kunci Ujian Siswa Ini', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      onPressed: () async {
                        final linkId = examId;
                        final userId = user['id'];
                        if (linkId != null && userId != null) {
                          final confirmed = await ConfirmUnlockDialog.show(
                            context: context,
                            studentName: studentName,
                            violationReason: lockReason,
                            examTitle: examTitle,
                            nisn: nisn,
                            deviceName: deviceName,
                            timestamp: user['locked_at']?.toString() ?? user['lock_time']?.toString() ?? user['updated_at']?.toString(),
                          );
                          if (confirmed && mounted) {
                            final ok = await widget.controller.unlockStudent(linkId, userId);
                            if (context.mounted) {
                              if (ok) {
                                AppNotification.showSuccess(
                                  context,
                                  'Kunci Dibuka',
                                  subtitle: '$studentName dapat melanjutkan ujian.',
                                );
                                await widget.controller.loadMonitoringData(silent: true);
                              } else {
                                AppNotification.showError(
                                  context,
                                  'Gagal Membuka Kunci',
                                  subtitle: 'Tidak dapat membuka kunci sesi siswa. Periksa koneksi ke server.',
                                );
                              }
                            }
                          }
                        }
                      },
                    ),
                  ),
                ] else if (isLocked && !canManageStudent) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.lock_outline_rounded,
                          size: 14,
                          color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Hanya Pengawas/Pembuat yang Berwenang Membuka Kunci',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- SUB-VIEW 2: JADWAL UJIAN ---
  Widget _buildExamScheduleContent(bool isDark, List<Map<String, dynamic>> exams) {
    // 1. Calculate status counts
    int ongoingCount = 0;
    int upcomingCount = 0;
    int finishedCount = 0;
    int inactiveCount = 0;

    for (final exam in exams) {
      final status = exam['status']?.toString() ?? 'active';
      final isActive = exam['is_active'] ?? (status == 'active');
      final autoStatus = _getExamAutoStatus(exam['start_time'], exam['end_time'], isActive == true);

      switch (autoStatus.status) {
        case 'ongoing':
          ongoingCount++;
          break;
        case 'upcoming':
          upcomingCount++;
          break;
        case 'finished':
          finishedCount++;
          break;
        case 'inactive':
          inactiveCount++;
          break;
      }
    }

    // 2. Filter exams based on filter pill and search query
    final query = _examSearchController.text.trim().toLowerCase();
    final filteredExams = exams.where((exam) {
      final status = exam['status']?.toString() ?? 'active';
      final isActive = exam['is_active'] ?? (status == 'active');
      final autoStatus = _getExamAutoStatus(exam['start_time'], exam['end_time'], isActive == true);

      if (_examScheduleFilter != 'all' && autoStatus.status != _examScheduleFilter) {
        return false;
      }

      if (query.isNotEmpty) {
        final title = exam['title']?.toString().toLowerCase() ?? '';
        final subject = exam['subject']?.toString().toLowerCase() ?? '';
        final className = exam['class_major']?['name']?.toString().toLowerCase() ?? '';
        final classMajors = exam['class_majors'] is List
            ? (exam['class_majors'] as List).map((m) => m['name']?.toString().toLowerCase() ?? '').join(' ')
            : '';
        final token = exam['token']?.toString().toLowerCase() ?? '';

        final creator = exam['creator'] as Map<String, dynamic>?;
        String creatorName = creator?['name']?.toString().toLowerCase() ??
            exam['teacher_name']?.toString().toLowerCase() ??
            exam['creator_name']?.toString().toLowerCase() ??
            '';
        if (creatorName.isEmpty && exam['created_by'] != null) {
          final createdById = exam['created_by'];
          final matchTeacher = widget.controller.teachers.firstWhere(
            (t) => t['id'] == createdById || t['user_id'] == createdById,
            orElse: () => <String, dynamic>{},
          );
          if (matchTeacher.isNotEmpty) {
            creatorName = matchTeacher['name']?.toString().toLowerCase() ?? '';
          } else {
            final matchUser = widget.controller.allUsers.firstWhere(
              (u) => u['id'] == createdById,
              orElse: () => <String, dynamic>{},
            );
            if (matchUser.isNotEmpty) {
              creatorName = matchUser['name']?.toString().toLowerCase() ?? '';
            }
          }
        }

        if (!title.contains(query) &&
            !subject.contains(query) &&
            !className.contains(query) &&
            !classMajors.contains(query) &&
            !token.contains(query) &&
            !creatorName.contains(query)) {
          return false;
        }
      }

      return true;
    }).toList();

    final isFiltered = _examScheduleFilter != 'all' || query.isNotEmpty;

    return Stack(
      children: [
        Column(
          children: [
            // A. Search Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _examSearchController,
                textInputAction: TextInputAction.search,
                onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                onSubmitted: (_) => FocusScope.of(context).unfocus(),
                onChanged: (_) => setState(() {}),
                style: TextStyle(fontSize: 13, color: isDark ? Colors.white : const Color(0xFF0F172A)),
                decoration: InputDecoration(
                  hintText: 'Cari judul ujian, mapel, kelas, token, atau pembuat...',
                  hintStyle: TextStyle(fontSize: 12, color: isDark ? AppTheme.textSecondary : const Color(0xFF94A3B8)),
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  suffixIcon: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _examSearchController,
                    builder: (context, value, _) {
                      if (value.text.isEmpty) return const SizedBox.shrink();
                      return IconButton(
                        icon: const Icon(Icons.cancel_rounded, size: 18, color: Color(0xFF94A3B8)),
                        splashRadius: 18,
                        tooltip: 'Hapus Teks Pencarian',
                        onPressed: () {
                          _examSearchController.clear();
                          setState(() {});
                        },
                      );
                    },
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  filled: true,
                  fillColor: isDark ? AppTheme.surfaceDark : Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                  ),
                ),
              ),
            ),

            // B. Horizontal Status Filter Chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  _buildExamScheduleFilterChip(
                    label: 'Semua',
                    value: 'all',
                    count: exams.length,
                    isDark: isDark,
                    activeColor: const Color(0xFFEA580C),
                    icon: Icons.grid_view_rounded,
                  ),
                  const SizedBox(width: 8),
                  _buildExamScheduleFilterChip(
                    label: 'Sedang Ujian',
                    value: 'ongoing',
                    count: ongoingCount,
                    isDark: isDark,
                    activeColor: const Color(0xFF10B981),
                    isLiveDot: true,
                  ),
                  const SizedBox(width: 8),
                  _buildExamScheduleFilterChip(
                    label: 'Terjadwal',
                    value: 'upcoming',
                    count: upcomingCount,
                    isDark: isDark,
                    activeColor: const Color(0xFF0284C7),
                    icon: Icons.calendar_month_rounded,
                  ),
                  const SizedBox(width: 8),
                  _buildExamScheduleFilterChip(
                    label: 'Selesai',
                    value: 'finished',
                    count: finishedCount,
                    isDark: isDark,
                    activeColor: const Color(0xFF64748B),
                    icon: Icons.task_alt_rounded,
                  ),
                  const SizedBox(width: 8),
                  _buildExamScheduleFilterChip(
                    label: 'Nonaktif',
                    value: 'inactive',
                    count: inactiveCount,
                    isDark: isDark,
                    activeColor: const Color(0xFFEF4444),
                    icon: Icons.pause_circle_outline_rounded,
                  ),
                ],
              ),
            ),

            // C. Active Filter Count Indicator
            if (isFiltered)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 4),
                child: Row(
                  children: [
                    Text(
                      'Menampilkan ${filteredExams.length} dari ${exams.length} jadwal ujian',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        setState(() {
                          _examScheduleFilter = 'all';
                          _examSearchController.clear();
                        });
                      },
                      child: const Text(
                        'Reset',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFEA580C),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              const SizedBox(height: 6),

            // D. Exam List or Empty Placeholder
            Expanded(
              child: RefreshIndicator(
                color: const Color(0xFFEA580C),
                onRefresh: () => widget.controller.loadExams(clearPrevious: true),
                child: (widget.controller.isLoading || widget.controller.isExamsLoading)
                    ? const ExamCardSkeleton(
                        count: 3,
                        padding: EdgeInsets.fromLTRB(16, 6, 16, 100),
                        physics: AlwaysScrollableScrollPhysics(),
                      )
                    : filteredExams.isEmpty
                    ? (isFiltered
                        ? ShieiEmptyState.searchNotFound(
                            context: context,
                            searchQuery: _examSearchController.text.isNotEmpty
                                ? _examSearchController.text
                                : _examScheduleFilter,
                            categoryLabel: 'Jadwal Ujian',
                            accentColor: const Color(0xFFEA580C),
                            isDark: isDark,
                            onClearSearch: () {
                              setState(() {
                                _examScheduleFilter = 'all';
                                _examSearchController.clear();
                              });
                            },
                          )
                        : ShieiEmptyState(
                            title: 'Belum Ada Jadwal Ujian',
                            message: 'Belum ada jadwal ujian sekolah terdaftar. Buat jadwal ujian baru untuk memulai asesmen.',
                            icon: Icons.assignment_outlined,
                            accentColor: const Color(0xFFEA580C),
                            isDark: isDark,
                            primaryActionLabel: '+ Buat Jadwal Ujian',
                            onPrimaryAction: () => ExamFormDialog.show(context: context, controller: widget.controller),
                          ))
                    : ListView.builder(
                        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 100),
                        itemCount: filteredExams.length,
                        itemBuilder: (ctx, index) {
                          return _buildExamCard(ctx, filteredExams[index], isDark);
                        },
                      ),
              ),
            ),
          ],
        ),

        // Floating Action Button (Hidden in selection mode)
        if (!_isExamSelectionMode)
          Positioned(
            right: 18,
            bottom: 24,
            child: _buildExamFab(isDark),
          ),

        // Floating Multi-Selection Action Bar (Contextual by selection count)
        if (_isExamSelectionMode)
          Positioned(
            left: 16,
            right: 16,
            bottom: 20,
            child: _buildExamSelectionActionBar(isDark, filteredExams),
          ),
      ],
    );
  }

  // --- FLOATING ACTION BUTTON (FAB) ---
  Widget _buildExamFab(bool isDark) {
    const fabColor = Color(0xFFEA580C);
    return Material(
      key: _fabKey,
      color: Colors.transparent,
      child: InkWell(
        onTap: _toggleSpeedDial,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: fabColor,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: fabColor.withValues(alpha: 0.38),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Center(
            child: Icon(Icons.add_rounded, size: 28, color: Colors.white),
          ),
        ),
      ),
    );
  }

  // --- FLOATING MULTI-SELECTION ACTION BAR (CONDITIONAL: 1 vs >1) ---
  Widget _buildExamSelectionActionBar(bool isDark, List<Map<String, dynamic>> filteredExams) {
    final count = _selectedExamIds.length;
    const primaryColor = Color(0xFFEA580C);

    // === CONDITION 1: EXACTLY 1 ITEM SELECTED (Contextual Single Actions) ===
    if (count == 1) {
      final singleId = _selectedExamIds.first;
      final item = widget.controller.exams.cast<Map<String, dynamic>?>().firstWhere(
        (e) => e?['id'] == singleId,
        orElse: () => null,
      );

      final title = item?['title']?.toString() ?? '1 Jadwal Ujian';
      final status = item?['status']?.toString() ?? 'active';
      final isActive = item?['is_active'] ?? (status == 'active');

      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.14),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top row: Dismiss, Item Name, and "Pilih Semua"
            Row(
              children: [
                IconButton(
                  style: IconButton.styleFrom(
                    padding: const EdgeInsets.all(6),
                    backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.close_rounded, size: 16),
                  onPressed: _exitExamSelectionMode,
                  tooltip: 'Batal',
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                      const ShieiAnimatedCounter(
                        count: 1,
                        suffix: ' Ujian Terpilih',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFFEA580C),
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => _selectAllExams(filteredExams),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: primaryColor.withValues(alpha: 0.25)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.checklist_rounded, size: 14, color: primaryColor),
                        SizedBox(width: 4),
                        Text(
                          'Pilih Semua',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: primaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Bottom row: Contextual Action Buttons for this 1 item
            Row(
              children: [
                // 1. Edit Ujian
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        if (item == null) return;
                        _exitExamSelectionMode();
                        ExamFormDialog.show(
                          context: context,
                          exam: item,
                          controller: widget.controller,
                        );
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3B82F6).withValues(alpha: isDark ? 0.2 : 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.3)),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.edit_rounded, size: 15, color: Color(0xFF3B82F6)),
                            SizedBox(width: 5),
                            Text(
                              'Edit',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF3B82F6),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // 2. Ubah Status Aktif / Nonaktif
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () async {
                        if (item == null) return;
                        _exitExamSelectionMode();
                        final nextStatus = isActive ? 'inactive' : 'active';
                        final err = await widget.controller.updateExam(singleId, {'status': nextStatus});
                        if (mounted) {
                          if (err == null) {
                            AppNotification.showSuccess(
                              context,
                              nextStatus == 'active' ? 'Ujian Diaktifkan' : 'Ujian Dinonaktifkan',
                              subtitle: 'Status ujian $title berhasil diperbarui.',
                            );
                          } else {
                            AppNotification.showError(context, 'Gagal Mengubah Status', subtitle: err);
                          }
                        }
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: (isActive ? const Color(0xFFF59E0B) : const Color(0xFF10B981)).withValues(alpha: isDark ? 0.2 : 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: (isActive ? const Color(0xFFF59E0B) : const Color(0xFF10B981)).withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              isActive ? Icons.pause_circle_outline_rounded : Icons.play_circle_outline_rounded,
                              size: 15,
                              color: isActive ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              isActive ? 'Nonaktifkan' : 'Aktifkan',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: isActive ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // 3. Hapus Item
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        if (item == null) return;
                        _exitExamSelectionMode();
                        ConfirmDeleteDialog.show(
                          context: context,
                          title: 'Hapus Jadwal Ujian?',
                          itemType: 'Judul Ujian',
                          itemName: title,
                          message: 'Ujian ini dan rekaman sesi peserta terkait akan dihapus secara permanen dari server.',
                          onConfirm: () => widget.controller.deleteExam(singleId),
                        );
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withValues(alpha: isDark ? 0.2 : 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.delete_outline_rounded, size: 15, color: Color(0xFFEF4444)),
                            SizedBox(width: 5),
                            Text(
                              'Hapus',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFEF4444),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // === CONDITION 2: MORE THAN 1 ITEM SELECTED (Batch Actions Only) ===
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
            blurRadius: 18,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            style: IconButton.styleFrom(
              padding: const EdgeInsets.all(7),
              backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: _exitExamSelectionMode,
            tooltip: 'Batal Pilih',
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ShieiAnimatedCounter(
                  count: count,
                  suffix: ' Ujian Terpilih',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                GestureDetector(
                  onTap: () => _selectAllExams(filteredExams),
                  child: const Text(
                    'Pilih Semua / Batal',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: primaryColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.delete_sweep_rounded, size: 18),
            label: const Text(
              'Hapus',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
            ),
            onPressed: count > 0 ? () => _confirmBulkDeleteExams(context) : null,
          ),
        ],
      ),
    );
  }

  Widget _buildExamScheduleFilterChip({
    required String label,
    required String value,
    required int count,
    required bool isDark,
    Color activeColor = const Color(0xFFEA580C),
    IconData? icon,
    bool isLiveDot = false,
  }) {
    final isSelected = _examScheduleFilter == value;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        FocusManager.instance.primaryFocus?.unfocus();
        setState(() => _examScheduleFilter = value);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor.withValues(alpha: 0.15)
              : (isDark ? AppTheme.surfaceDark : Colors.white),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? activeColor
                : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
            width: isSelected ? 1.4 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: activeColor.withValues(alpha: 0.12),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLiveDot) ...[
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: isSelected ? activeColor : const Color(0xFF10B981),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
            ] else if (icon != null) ...[
              Icon(
                icon,
                size: 14,
                color: isSelected
                    ? activeColor
                    : (isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
              ),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected
                    ? (isDark ? Colors.white : const Color(0xFF0F172A))
                    : (isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: isSelected
                    ? activeColor.withValues(alpha: 0.2)
                    : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                count.toString(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isSelected
                      ? activeColor
                      : (isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExamCard(BuildContext context, Map<String, dynamic> exam, bool isDark) {
    final examId = exam['id'] is int ? exam['id'] as int : int.tryParse(exam['id']?.toString() ?? '') ?? 0;
    final isSelected = _selectedExamIds.contains(examId);
    final title = exam['title']?.toString() ?? 'Ujian';
    final subject = exam['subject']?.toString() ?? 'Umum';
    final token = exam['token']?.toString() ?? '-';
    final tokenMode = exam['token_mode']?.toString() ?? 'static';
    final bool hasToken = token.isNotEmpty && token != '-' && token != 'TIDAK-ADA';
    final duration = exam['duration_minutes']?.toString() ?? '60';
    String className = 'Semua Kelas';
    if (exam['class_majors'] != null && (exam['class_majors'] as List).isNotEmpty) {
      final names = (exam['class_majors'] as List)
          .map((m) => m['name']?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
      if (names.length == 1) {
        className = names.first;
      } else if (names.length > 1) {
        className = '${names.length} Kelas (${names.join(', ')})';
      }
    } else if (exam['class_major']?['name'] != null) {
      className = exam['class_major']['name'].toString();
    }
    final status = exam['status']?.toString() ?? 'active';
    final isActive = exam['is_active'] ?? (status == 'active');
    final examUrl = exam['url']?.toString() ?? '';
    final startTimeRaw = exam['start_time'];
    final endTimeRaw = exam['end_time'];

    // Resolve exam creator name
    final creator = exam['creator'] as Map<String, dynamic>?;
    String creatorName = creator?['name']?.toString() ??
        exam['teacher_name']?.toString() ??
        exam['creator_name']?.toString() ??
        '';
    if (creatorName.isEmpty && exam['created_by'] != null) {
      final createdById = exam['created_by'];
      final matchTeacher = widget.controller.teachers.firstWhere(
        (t) => t['id'] == createdById || t['user_id'] == createdById,
        orElse: () => <String, dynamic>{},
      );
      if (matchTeacher.isNotEmpty) {
        creatorName = matchTeacher['name']?.toString() ?? '';
      } else {
        final matchUser = widget.controller.allUsers.firstWhere(
          (u) => u['id'] == createdById,
          orElse: () => <String, dynamic>{},
        );
        if (matchUser.isNotEmpty) {
          creatorName = matchUser['name']?.toString() ?? '';
        }
      }
    }
    if (creatorName.isEmpty) {
      creatorName = 'Guru Pembuat Ujian';
    }

    final canManage = widget.controller.canManageExam(exam);

    // 1. Precise Auto-Status parity with School-Panel
    final autoStatus = _getExamAutoStatus(startTimeRaw, endTimeRaw, isActive == true);

    // 2. Schedule timing formatting
    String dateFormatted = 'Fleksibel';
    String timeWindowFormatted = 'Waktu Bebas';
    if (startTimeRaw != null) {
      try {
        final startDt = DateTime.parse(startTimeRaw.toString()).toLocal();
        dateFormatted = DateFormat('d MMM yyyy', 'id_ID').format(startDt);
        final startHm = DateFormat('HH:mm').format(startDt);
        if (endTimeRaw != null) {
          final endDt = DateTime.parse(endTimeRaw.toString()).toLocal();
          final endHm = DateFormat('HH:mm').format(endDt);
          timeWindowFormatted = '$startHm - $endHm WIB';
        } else {
          timeWindowFormatted = '$startHm WIB - Selesai';
        }
      } catch (_) {}
    }

    // 3. Count live students currently taking this exam
    final liveCount = widget.controller.monitoringRecords.where((r) =>
        (r['link_id'] ?? r['link']?['id'])?.toString() == examId.toString() &&
        (r['status'] == 'in_progress' || r['is_locked'] == true)).length;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: isSelected
            ? const Color(0xFFEA580C).withValues(alpha: isDark ? 0.15 : 0.08)
            : (isDark ? AppTheme.surfaceDark : Colors.white),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected
              ? const Color(0xFFEA580C)
              : (autoStatus.status == 'ongoing'
                  ? const Color(0xFF10B981).withValues(alpha: 0.35)
                  : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0))),
          width: isSelected ? 1.5 : (autoStatus.status == 'ongoing' ? 1.4 : 1),
        ),
        boxShadow: [
          BoxShadow(
            color: isSelected
                ? const Color(0xFFEA580C).withValues(alpha: 0.08)
                : (autoStatus.status == 'ongoing'
                    ? const Color(0xFF10B981).withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.02)),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (_isExamSelectionMode) {
              _toggleExamSelection(examId);
              return;
            }
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ExamDetailScreen(
                  exam: exam,
                  controller: widget.controller,
                ),
              ),
            );
          },
          onLongPress: widget.controller.isAdmin
              ? () {
                  if (!_isExamSelectionMode) {
                    _enterExamSelectionMode(examId);
                  } else {
                    _toggleExamSelection(examId);
                  }
                }
              : null,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Meta Row: Checkbox (if in selection mode) + Auto-Status Pill + Live Pill + 3-Dots Dropdown
                Row(
                  children: [
                    AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      child: _isExamSelectionMode
                          ? Padding(
                              padding: const EdgeInsets.only(right: 10),
                              child: ShieiCheckbox(
                                value: isSelected,
                                activeColor: const Color(0xFFEA580C),
                                onChanged: (_) => _toggleExamSelection(examId),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                    // Status Badge with Dot
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                      decoration: BoxDecoration(
                        color: autoStatus.badgeColor,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: autoStatus.borderColor),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: autoStatus.dotColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            autoStatus.label,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: autoStatus.textColor,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (liveCount > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.35)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.circle, color: Color(0xFF10B981), size: 6),
                            const SizedBox(width: 5),
                            Text(
                              '$liveCount SISWA LIVE',
                              style: const TextStyle(
                                color: Color(0xFF10B981),
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const Spacer(),
                    if (!_isExamSelectionMode) ...[
                      // 3-Dots Action Dropdown Menu (Under button, unobscured!)
                      Theme(
                        data: Theme.of(context).copyWith(
                          popupMenuTheme: PopupMenuThemeData(
                            color: isDark ? AppTheme.surfaceDark : Colors.white,
                            surfaceTintColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                            ),
                            elevation: 8,
                            position: PopupMenuPosition.under,
                          ),
                        ),
                        child: PopupMenuButton<String>(
                          position: PopupMenuPosition.under,
                          offset: const Offset(0, 8),
                          borderRadius: BorderRadius.circular(8),
                          surfaceTintColor: Colors.transparent,
                          clipBehavior: Clip.antiAlias,
                          constraints: const BoxConstraints(
                            maxHeight: 280, // Limit agar tidak makan layar dan bisa di-scroll
                            minWidth: 205,
                          ),
                          icon: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                            ),
                            child: Icon(
                              Icons.more_vert_rounded,
                              size: 17,
                              color: isDark ? Colors.white70 : const Color(0xFF475569),
                            ),
                          ),
                          tooltip: 'Pilihan Aksi Ujian',
                          padding: EdgeInsets.zero,
                          onSelected: (action) async {
                            if (action == 'copy_token') {
                              Clipboard.setData(ClipboardData(text: token));
                              AppNotification.showSuccess(
                                context,
                                'Token Disalin',
                                subtitle: 'Kode PIN $token tersimpan di clipboard.',
                              );
                            } else if (action == 'copy_url' && examUrl.isNotEmpty) {
                              Clipboard.setData(ClipboardData(text: examUrl));
                              AppNotification.showSuccess(
                                context,
                                'Link Soal Disalin',
                                subtitle: 'Tautan URL ujian berhasil disalin.',
                              );
                            } else if (action == 'rotate' && examId != 0) {
                              final newToken = await widget.controller.rotateToken(examId);
                              if (context.mounted) {
                                if (newToken != null) {
                                  AppNotification.showSuccess(
                                    context,
                                    'Token Diperbarui',
                                    subtitle: 'Token baru: $newToken',
                                  );
                                } else {
                                  AppNotification.showError(
                                    context,
                                    'Gagal Memperbarui Token',
                                    subtitle: 'Tidak dapat mengacak PIN token ke server. Periksa koneksi.',
                                  );
                                }
                              }
                            } else if (action == 'broadcast') {
                              BroadcastAnnouncementDialog.show(
                                context: context,
                                controller: widget.controller,
                                initialExamId: examId,
                              );
                            } else if (action == 'toggle_status' && examId != 0) {
                              final nextStatus = isActive ? 'inactive' : 'active';
                              final err = await widget.controller.updateExam(examId, {'status': nextStatus});
                              if (context.mounted) {
                                if (err == null) {
                                  AppNotification.showSuccess(
                                    context,
                                    nextStatus == 'active' ? 'Ujian Diaktifkan' : 'Ujian Dinonaktifkan',
                                    subtitle: 'Status ujian $title berhasil diperbarui.',
                                  );
                                } else {
                                  AppNotification.showError(context, 'Gagal Mengubah Status', subtitle: err);
                                }
                              }
                            } else if (action == 'edit') {
                              ExamFormDialog.show(
                                context: context,
                                exam: exam,
                                controller: widget.controller,
                              );
                            } else if (action == 'delete' && examId != 0) {
                              ConfirmDeleteDialog.show(
                                context: context,
                                title: 'Hapus Jadwal Ujian?',
                                itemType: 'Judul Ujian',
                                itemName: title,
                                message: 'Ujian ini dan rekaman sesi peserta terkait akan dihapus secara permanen dari server.',
                                onConfirm: () => widget.controller.deleteExam(examId),
                              );
                            }
                          },
                          itemBuilder: (ctx) {
                            final hasToken = token.isNotEmpty && token != '-';
                            final isEnded = autoStatus.status == 'ended';

                            return [
                              if (hasToken)
                                const PopupMenuItem(
                                  value: 'copy_token',
                                  child: Row(
                                    children: [
                                      Icon(Icons.pin_rounded, size: 18, color: Color(0xFFEA580C)),
                                      SizedBox(width: 10),
                                      Text('Salin Kode Token PIN', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500)),
                                    ],
                                  ),
                                ),
                              if (examUrl.isNotEmpty)
                                const PopupMenuItem(
                                  value: 'copy_url',
                                  child: Row(
                                    children: [
                                      Icon(Icons.link_rounded, size: 18, color: Color(0xFF0284C7)),
                                      SizedBox(width: 10),
                                      Text('Salin Link / URL Soal', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500)),
                                    ],
                                  ),
                                ),
                              if (canManage && isActive && !isEnded)
                                const PopupMenuItem(
                                  value: 'rotate',
                                  child: Row(
                                    children: [
                                      Icon(Icons.autorenew_rounded, size: 18, color: Color(0xFFF97316)),
                                      SizedBox(width: 10),
                                      Text('Acak / Putar Token PIN', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500)),
                                    ],
                                  ),
                                ),
                              if (isActive && !isEnded)
                                const PopupMenuItem(
                                  value: 'broadcast',
                                  child: Row(
                                    children: [
                                      Icon(Icons.campaign_outlined, size: 18, color: Color(0xFF3B82F6)),
                                      SizedBox(width: 10),
                                      Text('Siarkan Pengumuman', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500)),
                                    ],
                                  ),
                                ),
                              if (canManage) ...[
                              const PopupMenuDivider(),
                              PopupMenuItem(
                                value: 'toggle_status',
                                child: Row(
                                  children: [
                                    Icon(
                                      isActive ? Icons.toggle_off_outlined : Icons.toggle_on_outlined,
                                      size: 18,
                                      color: isActive ? const Color(0xFF64748B) : const Color(0xFF10B981),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      isActive ? 'Nonaktifkan Jadwal' : 'Aktifkan Jadwal',
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w500,
                                        color: isActive ? const Color(0xFF64748B) : const Color(0xFF10B981),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'edit',
                                child: Row(
                                  children: [
                                    Icon(Icons.edit_outlined, size: 18, color: Color(0xFF10B981)),
                                    SizedBox(width: 10),
                                    Text('Edit Jadwal Ujian', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500)),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFFEF4444)),
                                    SizedBox(width: 10),
                                    Text(
                                      'Hapus Ujian',
                                      style: TextStyle(fontSize: 12.5, color: Color(0xFFEF4444), fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                              ],
                            ];
                          },
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),

                // Exam Title
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 8),

                // Tags Row: Class + Subject + Creator
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.school_rounded, size: 12, color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
                          const SizedBox(width: 4),
                          Text(
                            className,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.menu_book_rounded, size: 12, color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
                          const SizedBox(width: 4),
                          Text(
                            subject,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.person_outline_rounded, size: 12, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                          const SizedBox(width: 4),
                          Text(
                            creatorName,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Schedule & Timing Box (School Panel Style)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.calendar_today_rounded,
                            size: 13,
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            dateFormatted,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            Icons.timer_outlined,
                            size: 13,
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            FormatUtils.formatDurationHoursMinutes(duration, shortSuffix: true),
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.access_time_rounded,
                            size: 13,
                            color: autoStatus.status == 'ongoing'
                                ? const Color(0xFF10B981)
                                : (autoStatus.status == 'upcoming'
                                    ? const Color(0xFF38BDF8)
                                    : (isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8))),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            timeWindowFormatted,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: autoStatus.status == 'ongoing'
                                  ? const Color(0xFF10B981)
                                  : (autoStatus.status == 'upcoming'
                                      ? const Color(0xFF38BDF8)
                                      : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B))),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            autoStatus.helperText,
                            style: TextStyle(
                              fontSize: 10.5,
                              color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Token Security & Quick Action Row
                Row(
                  children: [
                    // Token Badge with Copy
                    InkWell(
                      onTap: hasToken ? () {
                        Clipboard.setData(ClipboardData(text: token));
                        AppNotification.showSuccess(
                          context,
                          'Token Disalin',
                          subtitle: 'Kode PIN $token tersimpan di clipboard.',
                        );
                      } : null,
                      borderRadius: BorderRadius.circular(8),
                      child: Opacity(
                        opacity: hasToken ? 1.0 : 0.55,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: (hasToken ? const Color(0xFFF97316) : (isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8))).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: (hasToken ? const Color(0xFFF97316) : (isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8))).withValues(alpha: 0.35)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'PIN: ',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: hasToken ? const Color(0xFFF97316) : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                                ),
                              ),
                              Text(
                                hasToken ? token : '-',
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12.5,
                                  color: hasToken ? const Color(0xFFF97316) : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                                  letterSpacing: 1.2,
                                ),
                              ),
                              if (hasToken) ...[
                                const SizedBox(width: 6),
                                const Icon(Icons.copy_rounded, size: 12, color: Color(0xFFF97316)),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Token Mode Tag
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        tokenMode == 'dynamic'
                            ? 'Putar 5 Mnt'
                            : (tokenMode == 'disabled' ? 'Tanpa Token' : 'Token Tetap'),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Clean Action Button (Full Width Detail & Peserta)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEA580C),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    icon: const Icon(Icons.tune_rounded, size: 15),
                    label: const Text('Detail & Peserta', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                    onPressed: () {
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
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ExamSpeedDialItem {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ExamSpeedDialItem({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });
}

class _ExamSpeedDialOverlayWidget extends StatelessWidget {
  final Animation<double> animation;
  final bool isDark;
  final Offset fabOffset;
  final Size fabSize;
  final List<_ExamSpeedDialItem> items;
  final VoidCallback onClose;

  const _ExamSpeedDialOverlayWidget({
    required this.animation,
    required this.isDark,
    required this.fabOffset,
    required this.fabSize,
    required this.items,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final double rightMargin = (screenSize.width - (fabOffset.dx + fabSize.width)).clamp(0.0, screenSize.width);
    final double bottomMargin = (screenSize.height - fabOffset.dy + 12).clamp(0.0, screenSize.height);
    const fabColor = Color(0xFFEA580C);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onClose();
      },
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            // 1. Full Screen Backdrop Overlay (Blur + Dim, covers 100% of the screen including Appbar & Navbar)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onClose,
                child: AnimatedBuilder(
                  animation: animation,
                  builder: (ctx, _) {
                    final rawVal = animation.value.clamp(0.0, 1.0);
                    final blurProgress = Curves.easeOut.transform(rawVal);
                    return BackdropFilter(
                      filter: ui.ImageFilter.blur(
                        sigmaX: 3.5 * blurProgress,
                        sigmaY: 3.5 * blurProgress,
                      ),
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.50 * blurProgress),
                      ),
                    );
                  },
                ),
              ),
            ),

            // 2. Staggered Animated Flyout Items (Above the FAB)
            Positioned(
              right: rightMargin,
              bottom: bottomMargin,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int i = 0; i < items.length; i++)
                    _buildAnimatedFlyoutItem(context, items[i], i, items.length),
                ],
              ),
            ),

            // 3. Elevated Active FAB (Rotates '+' into 'x', glows above backdrop)
            Positioned(
              left: fabOffset.dx,
              top: fabOffset.dy,
              width: fabSize.width,
              height: fabSize.height,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onClose();
                  },
                  borderRadius: BorderRadius.circular(28),
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: fabColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: fabColor.withValues(alpha: 0.45),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Center(
                      child: AnimatedBuilder(
                        animation: animation,
                        builder: (ctx, child) {
                          final rawVal = animation.value.clamp(0.0, 1.0);
                          final rotateProgress = Curves.easeOutCubic.transform(rawVal);
                          return Transform.rotate(
                            angle: rotateProgress * (math.pi / 4),
                            child: const Icon(Icons.add_rounded, size: 28, color: Colors.white),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedFlyoutItem(
    BuildContext context,
    _ExamSpeedDialItem item,
    int index,
    int totalCount,
  ) {
    // Bottom-most item (closest to FAB) emerges first
    final int reverseIndex = (totalCount - 1) - index;
    final double start = (reverseIndex * 0.15).clamp(0.0, 0.40);
    final double end = (start + 0.60).clamp(0.0, 1.0);

    return AnimatedBuilder(
      animation: animation,
      builder: (ctx, child) {
        final double rawVal = animation.value.clamp(0.0, 1.0);
        double t = 0.0;
        if (rawVal > start) {
          t = ((rawVal - start) / (end - start)).clamp(0.0, 1.0);
        }
        final double curvedT = Curves.easeOutCubic.transform(t);

        // Slide in horizontally from side only (Right -> Left), identical to school_data_tab
        final double slideX = (1.0 - curvedT) * 50.0;
        final double scale = 0.88 + (0.12 * curvedT);

        return Transform.translate(
          offset: Offset(slideX, 0.0),
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.centerRight,
            child: Opacity(
              opacity: curvedT,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ExamSpeedDialItemRow(
                  item: item,
                  isDark: isDark,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ExamSpeedDialItemRow extends StatefulWidget {
  final _ExamSpeedDialItem item;
  final bool isDark;

  const _ExamSpeedDialItemRow({
    required this.item,
    required this.isDark,
  });

  @override
  State<_ExamSpeedDialItemRow> createState() => _ExamSpeedDialItemRowState();
}

class _ExamSpeedDialItemRowState extends State<_ExamSpeedDialItemRow> {
  bool _isPressed = false;

  void _handleTap() {
    HapticFeedback.selectionClick();
    widget.item.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: _handleTap,
      child: AnimatedScale(
        scale: _isPressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Text Label Pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: widget.isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: widget.isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: widget.isDark ? 0.35 : 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Text(
                widget.item.label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: widget.isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Circular Mini FAB
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: widget.isDark ? const Color(0xFF1E293B) : Colors.white,
                shape: BoxShape.circle,
                border: Border.all(
                  color: widget.item.color.withValues(alpha: 0.35),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: widget.item.color.withValues(alpha: widget.isDark ? 0.3 : 0.18),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(widget.item.icon, size: 20, color: widget.item.color),
            ),
          ],
        ),
      ),
    );
  }
}

