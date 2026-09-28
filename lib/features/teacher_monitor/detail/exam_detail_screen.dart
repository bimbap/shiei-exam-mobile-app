import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/utils/format_utils.dart';
import '../../../../shared/widgets/app_notification.dart';
import '../../../../shared/widgets/shiei_skeleton.dart';
import '../dialogs/broadcast_announcement_dialog.dart';
import '../dialogs/confirm_delete_dialog.dart';
import '../dialogs/exam_form_dialog.dart';
import '../dialogs/qr_unblock_scanner_dialog.dart';
import '../dialogs/student_action_sheet.dart';
import '../dialogs/student_detail_modal.dart';
import '../teacher_portal_controller.dart';

class ExamDetailScreen extends StatefulWidget {
  final Map<String, dynamic> exam;
  final TeacherPortalController controller;

  const ExamDetailScreen({
    super.key,
    required this.exam,
    required this.controller,
  });

  @override
  State<ExamDetailScreen> createState() => _ExamDetailScreenState();
}

class _ExamDetailScreenState extends State<ExamDetailScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late Map<String, dynamic> _currentExam;

  List<Map<String, dynamic>> _examStudentsList = [];
  bool _isLoadingStudents = true;
  final TextEditingController _studentSearchController = TextEditingController();
  String _participantFilter = 'all'; // 'all', 'in_progress', 'completed', 'locked'

  // Proctors & Violations Search state
  List<Map<String, dynamic>> _examProctorsList = [];
  bool _isLoadingProctors = true;
  final TextEditingController _violationSearchController = TextEditingController();
  final TextEditingController _proctorSearchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _currentExam = Map<String, dynamic>.from(widget.exam);
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        FocusManager.instance.primaryFocus?.unfocus();
      }
    });
    _studentSearchController.addListener(() {
      if (mounted) setState(() {});
    });
    _violationSearchController.addListener(() {
      if (mounted) setState(() {});
    });
    _proctorSearchController.addListener(() {
      if (mounted) setState(() {});
    });
    _fetchExamParticipants();
    _fetchExamProctors();
  }

  Future<void> _fetchExamParticipants({bool silent = false}) async {
    final examId = _currentExam['id'];
    if (examId == null) {
      if (mounted) setState(() => _isLoadingStudents = false);
      return;
    }
    if (!silent) {
      setState(() => _isLoadingStudents = true);
    }
    final list = await widget.controller.loadExamParticipants(examId);
    if (mounted) {
      setState(() {
        _examStudentsList = list;
        _isLoadingStudents = false;
      });
    }
  }

  Future<void> _fetchExamProctors({bool silent = false}) async {
    final examId = _currentExam['id'];
    if (examId == null) {
      if (mounted) setState(() => _isLoadingProctors = false);
      return;
    }
    if (!silent && mounted) {
      setState(() => _isLoadingProctors = true);
    }
    final list = await widget.controller.loadExamProctors(examId);
    if (mounted) {
      setState(() {
        _examProctorsList = list;
        _isLoadingProctors = false;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _studentSearchController.dispose();
    _violationSearchController.dispose();
    _proctorSearchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _examProctors {
    final list = List<Map<String, dynamic>>.from(_examProctorsList);
    // Also check embedded 'proctors' in _currentExam if list is empty
    if (list.isEmpty && _currentExam['proctors'] != null && _currentExam['proctors'] is List) {
      for (final p in (_currentExam['proctors'] as List)) {
        if (p is Map) {
          final user = p['user'] as Map<String, dynamic>? ?? {};
          list.add({
            'id': p['user_id'] ?? user['id'],
            'proctor_id': p['id'],
            'name': user['name'] ?? 'Guru Pengawas',
            'nip': user['nip'] ?? '-',
            'email': user['email'] ?? '-',
            'assigned_at': p['created_at']?.toString() ?? '',
          });
        }
      }
    }
    // Include creator as lead proctor if available and not already in list
    final creator = _currentExam['creator'] as Map<String, dynamic>?;
    if (creator != null && creator['id'] != null) {
      final creatorId = creator['id'];
      final exists = list.any((p) => (p['id'] ?? p['user_id']) == creatorId);
      if (!exists) {
        list.insert(0, {
          'id': creatorId,
          'name': creator['name'] ?? 'Guru Pembuat Ujian',
          'nip': creator['nip'] ?? '-',
          'email': creator['email'] ?? '-',
          'is_creator': true,
          'role_label': 'Pembuat Ujian',
        });
      }
    }
    return list;
  }

  List<Map<String, dynamic>> get _examStudents {
    if (_examStudentsList.isNotEmpty) {
      return _examStudentsList;
    }
    if (_isLoadingStudents) {
      return [];
    }
    final examId = _currentExam['id'];
    return widget.controller.monitoringRecords.where((r) {
      final link = r['link'] as Map<String, dynamic>? ?? {};
      final linkId = r['link_id'] ?? link['id'];
      return linkId?.toString() == examId?.toString();
    }).toList();
  }

  void _copyToken(String token) {
    Clipboard.setData(ClipboardData(text: token));
    AppNotification.showSuccess(
      context,
      'Token Disalin',
      subtitle: 'Kode token $token disalin ke clipboard.',
    );
  }

  String _formatViolationReason(String? reason) {
    switch (reason) {
      case 'proctor_kick':
        return 'Dikeluarkan Pengawas';
      case 'split_screen':
        return 'Layar Terbelah';
      case 'app_switch':
      case 'app_minimize':
        return 'Pindah Aplikasi';
      case 'screenshot_attempt':
        return 'Percobaan Screenshot';
      case 'phone_call_detected':
        return 'Panggilan Suara';
      case 'bluetooth_enabled':
        return 'Bluetooth Aktif';
      case 'external_display':
        return 'Layar Eksternal';
      case 'overlay_detected':
        return 'Jendela Mengambang';
      case 'notification_pulldown':
        return 'Buka Notifikasi';
      default:
        return reason ?? 'Pelanggaran Keamanan';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final examId = _currentExam['id'];
    final title = _currentExam['title']?.toString() ?? 'Detail Ujian';
    final subject = _currentExam['subject']?.toString() ?? 'Umum';
    final token = _currentExam['token']?.toString() ?? '-';
    final duration = _currentExam['duration_minutes']?.toString() ?? '60';
    String className = 'Semua Kelas';
    List<String> classList = [];
    if (_currentExam['class_majors'] != null && (_currentExam['class_majors'] as List).isNotEmpty) {
      final names = (_currentExam['class_majors'] as List)
          .map((m) => m['name']?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
      classList = List<String>.from(names);
      if (names.length == 1) {
        className = names.first;
      } else if (names.length > 1) {
        className = '${names.length} Kelas (${names.join(', ')})';
      }
    } else if (_currentExam['class_major']?['name'] != null) {
      className = _currentExam['class_major']['name'].toString();
      classList = [className];
    }
    if (classList.isEmpty) {
      classList = ['Semua Kelas'];
    }
    final examUrl = _currentExam['url']?.toString() ?? '';
    final students = _examStudents;
    final lockedCount = students.where((s) => s['is_locked'] == true || s['status'] == 'locked' || s['status'] == 'split_screen').length;

    final canManage = widget.controller.canManageExam(_currentExam);

    // Extract exam creator info
    final creator = _currentExam['creator'] as Map<String, dynamic>?;
    String creatorName = creator?['name']?.toString() ??
        _currentExam['teacher_name']?.toString() ??
        _currentExam['creator_name']?.toString() ??
        '';
    String? creatorNip = creator?['nip']?.toString();
    String? creatorEmail = creator?['email']?.toString();

    if (creatorName.isEmpty && _currentExam['created_by'] != null) {
      final createdById = _currentExam['created_by'];
      final matchTeacher = widget.controller.teachers.firstWhere(
        (t) => t['id'] == createdById || t['user_id'] == createdById,
        orElse: () => <String, dynamic>{},
      );
      if (matchTeacher.isNotEmpty) {
        creatorName = matchTeacher['name']?.toString() ?? '';
        creatorNip ??= matchTeacher['nip']?.toString();
        creatorEmail ??= matchTeacher['email']?.toString();
      } else {
        final matchUser = widget.controller.allUsers.firstWhere(
          (u) => u['id'] == createdById,
          orElse: () => <String, dynamic>{},
        );
        if (matchUser.isNotEmpty) {
          creatorName = matchUser['name']?.toString() ?? '';
          creatorNip ??= matchUser['nip']?.toString();
          creatorEmail ??= matchUser['email']?.toString();
        }
      }
    }
    if (creatorName.isEmpty) {
      creatorName = 'Guru Pembuat Ujian';
    }

    // Format schedule dates & times
    final startTime = _currentExam['start_time'];
    final endTime = _currentExam['end_time'];

    String dateFormatted = 'Sesuai Jadwal';
    String timeWindowFormatted = 'Waktu Fleksibel';
    String autoStatusLabel = 'AKTIF';
    Color autoStatusColor = const Color(0xFF10B981);

    if (startTime != null) {
      try {
        final startDt = DateTime.parse(startTime.toString()).toLocal();
        dateFormatted = DateFormat('d MMM yyyy', 'id_ID').format(startDt);
        final startHm = DateFormat('HH:mm').format(startDt);
        if (endTime != null) {
          final endDt = DateTime.parse(endTime.toString()).toLocal();
          final endHm = DateFormat('HH:mm').format(endDt);
          timeWindowFormatted = '$startHm - $endHm WIB';

          final now = DateTime.now();
          if (now.isBefore(startDt)) {
            autoStatusLabel = 'TERJADWAL';
            autoStatusColor = const Color(0xFF3B82F6);
          } else if (now.isAfter(endDt)) {
            autoStatusLabel = 'SELESAI';
            autoStatusColor = const Color(0xFF64748B);
          } else {
            autoStatusLabel = 'SEDANG BERLANGSUNG';
            autoStatusColor = const Color(0xFF10B981);
          }
        } else {
          timeWindowFormatted = '$startHm WIB - Selesai';
        }
      } catch (_) {}
    }

    if ((_currentExam['status']?.toString() ?? 'active') != 'active') {
      autoStatusLabel = 'NONAKTIF';
      autoStatusColor = const Color(0xFF64748B);
    }

    final bool isExamEnded = autoStatusLabel == 'SELESAI' ||
        autoStatusLabel == 'NONAKTIF' ||
        (_currentExam['status']?.toString() == 'inactive');

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // Layer 1: Clear student search if active
        if (_studentSearchController.text.isNotEmpty) {
          _studentSearchController.clear();
          return;
        }
        // Layer 2: Clear violation search if active
        if (_violationSearchController.text.isNotEmpty) {
          _violationSearchController.clear();
          return;
        }
        // Layer 3: Clear proctor search if active
        if (_proctorSearchController.text.isNotEmpty) {
          _proctorSearchController.clear();
          return;
        }
        // Layer 4: Reset participant filter if active
        if (_participantFilter != 'all') {
          setState(() => _participantFilter = 'all');
          return;
        }
        // Layer 5: Return to session info tab (0) if on other sub-tabs
        if (_tabController.index != 0) {
          _tabController.animateTo(0);
          return;
        }
        // Layer 6: Pop screen back
        Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: AppTheme.background(context),
        appBar: AppBar(
        title: Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: _isLoadingStudents
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFEA580C)),
                  )
                : const Icon(Icons.refresh_rounded),
            tooltip: 'Muat Ulang Peserta & Sesi',
            onPressed: _isLoadingStudents ? null : () => _fetchExamParticipants(),
          ),
          PopupMenuButton<String>(
            position: PopupMenuPosition.under,
            offset: const Offset(0, 8),
            icon: const Icon(Icons.more_vert_rounded),
            tooltip: 'Menu Aksi Ujian',
            padding: EdgeInsets.zero,
            borderRadius: BorderRadius.circular(12),
            surfaceTintColor: Colors.transparent,
            clipBehavior: Clip.antiAlias,
            constraints: const BoxConstraints(
              maxHeight: 280,
              minWidth: 210,
            ),
            color: isDark ? AppTheme.surfaceDark : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
            ),
            onSelected: (value) async {
              switch (value) {
                case 'copy_token':
                  _copyToken(token);
                  break;
                case 'copy_url':
                  final examUrl = _currentExam['url']?.toString() ?? '';
                  if (examUrl.isNotEmpty) {
                    Clipboard.setData(ClipboardData(text: examUrl));
                    AppNotification.showSuccess(
                      context,
                      'Link Soal Disalin',
                      subtitle: 'Tautan URL ujian berhasil disalin ke clipboard.',
                    );
                  }
                  break;
                case 'rotate':
                  if (examId != null) {
                    final newToken = await widget.controller.rotateToken(examId);
                    if (context.mounted) {
                      if (newToken != null) {
                        setState(() {
                          _currentExam = {
                            ..._currentExam,
                            'token': newToken,
                          };
                        });
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
                  }
                  break;
                case 'toggle_status':
                  if (examId != null) {
                    final isCurrentlyActive = (_currentExam['status']?.toString() ?? 'active') == 'active';
                    final nextStatus = isCurrentlyActive ? 'inactive' : 'active';
                    final err = await widget.controller.updateExam(examId, {'status': nextStatus});
                    if (context.mounted) {
                      if (err == null) {
                        setState(() {
                          _currentExam = {
                            ..._currentExam,
                            'status': nextStatus,
                            'is_active': nextStatus == 'active',
                          };
                        });
                        AppNotification.showSuccess(
                          context,
                          nextStatus == 'active' ? 'Ujian Diaktifkan' : 'Ujian Dinonaktifkan',
                          subtitle: 'Status ujian berhasil diperbarui.',
                        );
                      } else {
                        AppNotification.showError(context, 'Gagal Mengubah Status', subtitle: err);
                      }
                    }
                  }
                  break;
                case 'qr':
                  QrUnblockScannerDialog.show(context: context, controller: widget.controller);
                  break;
                case 'broadcast':
                  BroadcastAnnouncementDialog.show(
                    context: context,
                    initialExamId: examId,
                    controller: widget.controller,
                  );
                  break;
                case 'edit':
                  final updated = await ExamFormDialog.show(
                    context: context,
                    exam: _currentExam,
                    controller: widget.controller,
                  );
                  if (updated == true && mounted) {
                    final latestExam = widget.controller.exams.firstWhere(
                      (e) => e['id'] == examId,
                      orElse: () => _currentExam,
                    );
                    setState(() => _currentExam = latestExam);
                  }
                  break;
                case 'delete':
                  final deleted = await ConfirmDeleteDialog.show(
                    context: context,
                    title: 'Hapus Jadwal Ujian?',
                    itemType: 'Judul Ujian',
                    itemName: title,
                    message: 'Ujian ini dan seluruh sesi siswa terkait akan dihapus secara permanen.',
                    onConfirm: () => widget.controller.deleteExam(examId!),
                  );
                  if (deleted == true && context.mounted) {
                    Navigator.of(context).pop();
                  }
                  break;
              }
            },
            itemBuilder: (ctx) {
              final isCurrentlyActive = (_currentExam['status']?.toString() ?? 'active') == 'active';
              final examUrl = _currentExam['url']?.toString() ?? '';
              final hasToken = token.isNotEmpty && token != '-';

              return [
                if (hasToken)
                  const PopupMenuItem(
                    value: 'copy_token',
                    child: Row(
                      children: [
                        Icon(Icons.pin_rounded, size: 18, color: Color(0xFFEA580C)),
                        SizedBox(width: 10),
                        Text('Salin Kode Token PIN', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
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
                        Text('Salin Link / URL Soal', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                if (canManage && !isExamEnded && isCurrentlyActive)
                  const PopupMenuItem(
                    value: 'rotate',
                    child: Row(
                      children: [
                        Icon(Icons.autorenew_rounded, size: 18, color: Color(0xFFF97316)),
                        SizedBox(width: 10),
                        Text('Acak / Putar Token PIN', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                if (!isExamEnded)
                  const PopupMenuItem(
                    value: 'qr',
                    child: Row(
                      children: [
                        Icon(Icons.qr_code_scanner_rounded, size: 18, color: Color(0xFF8B5CF6)),
                        SizedBox(width: 10),
                        Text('Scan QR Buka Kunci', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                if (!isExamEnded && isCurrentlyActive)
                  const PopupMenuItem(
                    value: 'broadcast',
                    child: Row(
                      children: [
                        Icon(Icons.campaign_rounded, size: 18, color: Color(0xFFF59E0B)),
                        SizedBox(width: 10),
                        Text('Siarkan Ralat / Pengumuman', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                if (canManage && examId != null) ...[
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'toggle_status',
                    child: Row(
                      children: [
                        Icon(
                          isCurrentlyActive ? Icons.toggle_off_outlined : Icons.toggle_on_outlined,
                          size: 18,
                          color: isCurrentlyActive ? const Color(0xFF64748B) : const Color(0xFF10B981),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          isCurrentlyActive ? 'Nonaktifkan Jadwal' : 'Aktifkan Jadwal',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: isCurrentlyActive ? const Color(0xFF64748B) : const Color(0xFF10B981),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined, size: 18, color: Color(0xFF3B82F6)),
                        SizedBox(width: 10),
                        Text('Edit Pengaturan Ujian', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFFEF4444)),
                        SizedBox(width: 10),
                        Text('Hapus Ujian', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFFEF4444))),
                      ],
                    ),
                  ),
                ],
              ];
            },
          ),
        ],
      ),
      body: Builder(
        builder: (context) {
          final headerCard = _buildHeaderSummaryCard(
            context: context,
            isDark: isDark,
            examId: examId,
            title: title,
            subject: subject,
            token: token,
            duration: duration,
            classList: classList,
            dateFormatted: dateFormatted,
            timeWindowFormatted: timeWindowFormatted,
            autoStatusLabel: autoStatusLabel,
            autoStatusColor: autoStatusColor,
            students: students,
            lockedCount: lockedCount,
            isExamEnded: isExamEnded,
            canManage: canManage,
          );
          return Column(
            children: [
              // Sticky Pinned 4-Tab Bar
              Container(
                color: AppTheme.background(context),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                alignment: Alignment.center,
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: TabBar(
                    onTap: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                    controller: _tabController,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
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
                    labelColor: isDark ? Colors.white : const Color(0xFF0F172A),
                    unselectedLabelColor: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                    labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
                    tabs: [
                      const Tab(text: 'Informasi Ujian'),
                      Tab(text: 'Peserta (${students.length})'),
                      Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('Pelanggaran'),
                            if (lockedCount > 0) ...[
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEF4444),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '$lockedCount',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Tab(text: 'Pengawas (${_examProctors.length})'),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // Tab 1: Informasi Ujian
                    _buildSessionInfoTab(
                      isDark: isDark,
                      headerCard: headerCard,
                      title: title,
                      subject: subject,
                      className: className,
                      creatorName: creatorName,
                      creatorNip: creatorNip,
                      creatorEmail: creatorEmail,
                      dateFormatted: dateFormatted,
                      timeWindowFormatted: timeWindowFormatted,
                      duration: duration,
                      autoStatusLabel: autoStatusLabel,
                      autoStatusColor: autoStatusColor,
                      token: token,
                      examUrl: examUrl,
                    ),

                    // Tab 2: Peserta Ujian
                    _buildParticipantsTab(
                      isDark: isDark,
                      students: students,
                      autoStatusLabel: autoStatusLabel,
                      examId: examId,
                      examTitle: title,
                      className: className,
                    ),

                    // Tab 3: Log Pelanggaran
                    _buildViolationLogTab(
                      isDark: isDark,
                      students: students,
                      examId: examId,
                      examTitle: title,
                      isExamEnded: isExamEnded,
                    ),

                    // Tab 4: Pengawas Ujian
                    _buildProctorsTab(
                      isDark: isDark,
                      examId: examId,
                      examTitle: title,
                      isExamEnded: isExamEnded,
                    ),
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

  Widget _buildHeaderSummaryCard({
    required BuildContext context,
    required bool isDark,
    required dynamic examId,
    required String title,
    required String subject,
    required String token,
    required String duration,
    required List<String> classList,
    required String dateFormatted,
    required String timeWindowFormatted,
    required String autoStatusLabel,
    required Color autoStatusColor,
    required List<Map<String, dynamic>> students,
    required int lockedCount,
    required bool isExamEnded,
    bool canManage = true,
  }) {
    final completedCount = students.where((s) => s['status'] == 'completed' || s['status'] == 'submitted' || (s['score'] != null)).length;
    final pendingCount = students.where((s) => !isExamEnded && s['status'] == 'pending' && s['is_locked'] != true && s['status'] != 'terminated').length;
    final inProgressCount = students.where((s) => !isExamEnded && (s['status'] == 'in_progress' || s['status'] == 'started') && s['is_locked'] != true && s['status'] != 'terminated').length;
    final bool hasToken = token.isNotEmpty && token != '-';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
              : [const Color(0xFFFFF7ED), Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFFED7AA),
        ),
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black26 : const Color(0xFFF97316).withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Subject Badge on Left, Status Badge on Top-Right Corner
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.menu_book_rounded, size: 12, color: Color(0xFF3B82F6)),
                    const SizedBox(width: 4),
                    Text(
                      subject,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF3B82F6),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: autoStatusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: autoStatusColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.circle, color: autoStatusColor, size: 6),
                    const SizedBox(width: 4),
                    Text(
                      autoStatusLabel,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        color: autoStatusColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Exam Title
          Text(
            title,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.3,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 6),

          // Class Badges (Wrapped under Title)
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: classList.map((cName) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.groups_rounded, size: 12, color: Color(0xFF8B5CF6)),
                  const SizedBox(width: 4),
                  Text(
                    cName,
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF8B5CF6),
                    ),
                  ),
                ],
              ),
            )).toList(),
          ),
          const SizedBox(height: 10),

          // Schedule Details (Date & Time Window without truncation)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFFDE68A),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.calendar_today_rounded,
                  size: 13,
                  color: isDark ? const Color(0xFFF97316) : const Color(0xFFEA580C),
                ),
                const SizedBox(width: 6),
                Text(
                  dateFormatted,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: isDark ? const Color(0xFFF97316) : const Color(0xFFEA580C),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '•',
                  style: TextStyle(
                    color: isDark ? const Color(0xFF64748B) : const Color(0xFFCBD5E1),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '$timeWindowFormatted (${FormatUtils.formatDurationHoursMinutes(duration)})',
                    maxLines: 2,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : const Color(0xFF475569),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Dedicated Token Box with 1-Tap Copy & Rotate Action
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFFED7AA),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TOKEN AKSES UJIAN',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                          color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        token,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                          color: Color(0xFFEA580C),
                        ),
                      ),
                    ],
                  ),
                ),
                // Copy Token Button
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: hasToken ? () => _copyToken(token) : null,
                    borderRadius: BorderRadius.circular(8),
                    child: Opacity(
                      opacity: hasToken ? 1.0 : 0.45,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: hasToken
                                ? const [Color(0xFFF97316), Color(0xFFEA580C)]
                                : const [Color(0xFF94A3B8), Color(0xFF64748B)],
                          ),
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: hasToken
                              ? [
                                  BoxShadow(
                                    color: const Color(0xFFF97316).withValues(alpha: 0.25),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : null,
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.copy_rounded, size: 13, color: Colors.white),
                            SizedBox(width: 5),
                            Text(
                              'Salin',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (examId != null && !isExamEnded && canManage) ...[
                  const SizedBox(width: 8),
                  // Rotate Token Button
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () async {
                        final newToken = await widget.controller.rotateToken(examId);
                        if (context.mounted && newToken != null) {
                          setState(() {
                            _currentExam['token'] = newToken;
                          });
                          AppNotification.showSuccess(
                            context,
                            'Token Berhasil Diacak',
                            subtitle: 'Token baru: $newToken',
                          );
                        }
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.autorenew_rounded,
                              size: 13,
                              color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Acak',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),

          // KPI Stat Pills (Centered horizontally and vertically)
          Row(
            children: [
              Expanded(child: _buildStatPill('Total: ${students.length}', const Color(0xFF0284C7), isDark)),
              const SizedBox(width: 6),
              Expanded(
                child: isExamEnded
                    ? _buildStatPill('Selesai: $completedCount', const Color(0xFF10B981), isDark)
                    : _buildStatPill('Aktif: $inProgressCount', const Color(0xFF10B981), isDark),
              ),
              if (!isExamEnded && pendingCount > 0) ...[
                const SizedBox(width: 6),
                Expanded(
                  child: _buildStatPill('Menunggu: $pendingCount', const Color(0xFFF59E0B), isDark),
                ),
              ],
              const SizedBox(width: 6),
              Expanded(
                child: _buildStatPill('Terkunci: $lockedCount', lockedCount > 0 ? const Color(0xFFEF4444) : const Color(0xFF64748B), isDark),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildParticipantsTab({
    required bool isDark,
    required List<Map<String, dynamic>> students,
    required String autoStatusLabel,
    required dynamic examId,
    required String examTitle,
    required String className,
  }) {
    if (_isLoadingStudents) {
      return const ParticipantRowSkeleton(
        count: 6,
        padding: EdgeInsets.fromLTRB(16, 12, 16, 100),
      );
    }

    final searchQuery = _studentSearchController.text.trim().toLowerCase();
    final bool isExamEnded = autoStatusLabel == 'SELESAI' || autoStatusLabel == 'NONAKTIF';

    final completedCount = students.where((s) => s['status'] == 'completed' || s['status'] == 'submitted' || (s['score'] != null)).length;
    final lockedCount = students.where((s) => s['is_locked'] == true || s['status'] == 'locked' || s['status'] == 'split_screen').length;
    final pendingCount = students.where((s) => !isExamEnded && s['status'] == 'pending' && s['is_locked'] != true && s['status'] != 'terminated').length;
    final onCallCount = students.where((s) => s['is_on_call'] == true || s['is_on_call'] == 1 || s['is_on_call']?.toString() == 'true').length;
    final inProgressCount = students.where((s) => !isExamEnded && (s['status'] == 'in_progress' || s['status'] == 'started') && s['is_locked'] != true && s['status'] != 'terminated').length;

    final filteredStudents = students.where((item) {
      final user = item['user'] as Map<String, dynamic>? ?? {};
      final name = (user['name']?.toString() ?? '').toLowerCase();
      final nisn = (user['nisn']?.toString() ?? user['username']?.toString() ?? '').toLowerCase();
      final userClass = (user['class_major']?['name']?.toString() ?? user['class_name']?.toString() ?? '').toLowerCase();

      final matchesSearch = searchQuery.isEmpty ||
          name.contains(searchQuery) ||
          nisn.contains(searchQuery) ||
          userClass.contains(searchQuery);
      if (!matchesSearch) return false;

      final status = item['status']?.toString().toLowerCase() ?? 'pending';
      final isLocked = item['is_locked'] == true || status == 'locked' || status == 'split_screen';
      final isCompleted = status == 'completed' || status == 'submitted' || item['score'] != null;
      final isPending = !isExamEnded && !isLocked && !isCompleted && status == 'pending';
      final isInProgress = !isExamEnded && !isLocked && !isCompleted && (status == 'in_progress' || status == 'started');
      final isOnCall = item['is_on_call'] == true || item['is_on_call'] == 1 || item['is_on_call']?.toString() == 'true';

      switch (_participantFilter) {
        case 'in_progress':
          return isInProgress;
        case 'pending':
          return isPending;
        case 'on_call':
          return isOnCall;
        case 'completed':
          return isCompleted;
        case 'locked':
          return isLocked;
        case 'all':
        default:
          return true;
      }
    }).toList();

    return RefreshIndicator(
      color: const Color(0xFFEA580C),
      onRefresh: () async {
        await Future.wait([
          _fetchExamParticipants(silent: false),
          _fetchExamProctors(silent: true),
        ]);
      },
      child: CustomScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // Pinned Search & Filter Bar
          SliverPersistentHeader(
            pinned: true,
            delegate: _SliverTabBarDelegate(
              Container(
                color: AppTheme.background(context),
                padding: const EdgeInsets.only(top: 2, bottom: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Search Bar
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: _studentSearchController,
                        textInputAction: TextInputAction.search,
                        onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                        onSubmitted: (_) => FocusScope.of(context).unfocus(),
                        style: TextStyle(fontSize: 13, color: isDark ? Colors.white : const Color(0xFF0F172A)),
                        decoration: InputDecoration(
                          hintText: 'Cari nama peserta atau NISN...',
                          hintStyle: TextStyle(fontSize: 12, color: isDark ? AppTheme.textSecondary : const Color(0xFF94A3B8)),
                          prefixIcon: const Icon(Icons.search_rounded, size: 18),
                          suffixIcon: _studentSearchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded, size: 16),
                                  onPressed: () => _studentSearchController.clear(),
                                )
                              : null,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                    const SizedBox(height: 6),
                    // Filter Chips
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          _buildFilterChip('Semua (${students.length})', 'all', isDark),
                          const SizedBox(width: 8),
                          _buildFilterChip('Mengerjakan ($inProgressCount)', 'in_progress', isDark),
                          if (pendingCount > 0) ...[
                            const SizedBox(width: 8),
                            _buildFilterChip('Menunggu ($pendingCount)', 'pending', isDark),
                          ],
                          if (onCallCount > 0) ...[
                            const SizedBox(width: 8),
                            _buildFilterChip('Telponan ($onCallCount)', 'on_call', isDark, isAlert: true),
                          ],
                          const SizedBox(width: 8),
                          _buildFilterChip('Selesai ($completedCount)', 'completed', isDark),
                          const SizedBox(width: 8),
                          _buildFilterChip('Terkunci ($lockedCount)', 'locked', isDark, isAlert: lockedCount > 0),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              height: 104.0,
            ),
          ),

          // 3. Students List or Empty State
          if (students.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.people_outline_rounded,
                          size: 28,
                          color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Belum Ada Siswa yang Masuk',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Pastikan siswa memasukkan token ujian di Shiei Exam.\nTarik ke bawah untuk memuat ulang data.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.4,
                          color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (filteredStudents.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.search_off_rounded, size: 42, color: isDark ? AppTheme.textSecondary : const Color(0xFFCBD5E1)),
                      const SizedBox(height: 10),
                      Text(
                        'Tidak ada peserta yang cocok dengan filter.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12.5, color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 30),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, index) {
                    final item = filteredStudents[index];
                    return _buildParticipantCard(
                      context: ctx,
                      item: item,
                      isDark: isDark,
                      autoStatusLabel: autoStatusLabel,
                      examId: examId,
                      examTitle: examTitle,
                      defaultClassName: className,
                    );
                  },
                  childCount: filteredStudents.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value, bool isDark, {bool isAlert = false}) {
    final isSelected = _participantFilter == value;
    Color activeColor = const Color(0xFFEA580C);
    if (isAlert) activeColor = const Color(0xFFEF4444);

    return InkWell(
      onTap: () => setState(() => _participantFilter = value),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor.withValues(alpha: 0.15)
              : (isDark ? AppTheme.surfaceDark : Colors.white),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? activeColor
                : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
            width: isSelected ? 1.4 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected
                ? activeColor
                : (isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
          ),
        ),
      ),
    );
  }

  Widget _buildParticipantCard({
    required BuildContext context,
    required Map<String, dynamic> item,
    required bool isDark,
    required String autoStatusLabel,
    required dynamic examId,
    required String examTitle,
    required String defaultClassName,
  }) {
    final user = item['user'] as Map<String, dynamic>? ?? {};
    final String status = item['status']?.toString().toLowerCase() ?? 'pending';
    final String? lockReason = item['lock_reason']?.toString();
    final bool isKicked = status == 'terminated' || lockReason == 'proctor_kick' || item['is_kicked'] == true;
    final bool isLocked = !isKicked && (item['is_locked'] == true || status == 'locked' || status == 'split_screen');
    final bool isCompleted = status == 'completed' || status == 'submitted' || item['score'] != null;
    final bool isExamEnded = autoStatusLabel == 'SELESAI' || autoStatusLabel == 'NONAKTIF';
    final bool isExpired = isExamEnded && !isKicked && !isLocked && !isCompleted;

    final studentName = user['name']?.toString() ?? 'Peserta #${item['user_id'] ?? ''}';
    final rawNisn = user['nisn']?.toString().trim();
    final rawUsername = user['username']?.toString().trim();
    final nisn = (rawNisn != null && rawNisn.isNotEmpty && rawNisn != '-')
        ? rawNisn
        : (rawUsername != null && rawUsername.isNotEmpty && rawUsername != '-')
            ? rawUsername
            : '-';
    final email = user['email']?.toString() ?? '';
    final userClass = user['class_major']?['name']?.toString() ??
        user['classes']?['name']?.toString() ??
        user['class_name']?.toString() ??
        defaultClassName;
    final deviceName = user['device_name']?.toString();
    final serial = user['serial_number']?.toString();
    final bool hasBoundDevice = (deviceName != null && deviceName.isNotEmpty) || (serial != null && serial.isNotEmpty);
    final extraMins = item['extra_minutes'] is int ? item['extra_minutes'] as int : int.tryParse(item['extra_minutes']?.toString() ?? '') ?? 0;
    final score = item['score'];
    final rawBattery = item['battery_level'] ?? (item['metadata'] is Map ? item['metadata']['battery_level'] : null);
    final int? batteryLevel = rawBattery is int
        ? rawBattery
        : int.tryParse(rawBattery?.toString() ?? '');
    final dynamic rawCharging = item['is_charging'] ?? (item['metadata'] is Map ? item['metadata']['is_charging'] : null);
    final bool isCharging = rawCharging == true ||
        rawCharging == 1 ||
        rawCharging == '1' ||
        rawCharging?.toString().toLowerCase() == 'true';
    final rawOnline = item['is_online'];
    final rawSecondsSince = item['seconds_since_heartbeat'];
    final int? secondsSince = rawSecondsSince is int ? rawSecondsSince : int.tryParse(rawSecondsSince?.toString() ?? '');
    final bool isLost = rawOnline == false || (secondsSince != null && secondsSince > 10);
    // Waiting: unlocked by proctor but student hasn't resumed active live exam yet
    final bool isWaiting = !isKicked &&
        !isLocked &&
        !isCompleted &&
        !isExpired &&
        item['unlocked_at'] != null &&
        (status == 'pending' || isLost);
    final String? networkType = item['network_type']?.toString() ?? (item['metadata'] is Map ? item['metadata']['network_type']?.toString() : null);
    final dynamic rawOnCall = item['is_on_call'] ?? (item['metadata'] is Map ? item['metadata']['is_on_call'] : null);
    final bool isOnCall = rawOnCall == true ||
        rawOnCall == 1 ||
        rawOnCall == '1' ||
        rawOnCall?.toString().toLowerCase() == 'true';

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
    } else if (isLost) {
      cardBorderColor = isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1);
      avatarBg = const Color(0xFF64748B).withValues(alpha: 0.12);
      iconColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
      statusIcon = Icons.wifi_off_rounded;
      statusLabel = 'TERPUTUS';
      statusBadgeBg = const Color(0xFF64748B).withValues(alpha: 0.12);
      statusBadgeTextColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    } else if (isWaiting) {
      // Unlocked by proctor — student hasn't resumed live exam yet
      cardBorderColor = const Color(0xFFF59E0B).withValues(alpha: 0.45);
      avatarBg = const Color(0xFFF59E0B).withValues(alpha: 0.12);
      iconColor = const Color(0xFFF59E0B);
      statusIcon = Icons.hourglass_top_rounded;
      statusLabel = 'MENUNGGU';
      statusBadgeBg = const Color(0xFFF59E0B).withValues(alpha: 0.12);
      statusBadgeTextColor = const Color(0xFFF59E0B);
    } else if (status == 'pending') {
      cardBorderColor = const Color(0xFFF59E0B).withValues(alpha: 0.35);
      avatarBg = const Color(0xFFF59E0B).withValues(alpha: 0.12);
      iconColor = const Color(0xFFF59E0B);
      statusIcon = Icons.hourglass_top_rounded;
      statusLabel = 'MENUNGGU SISWA';
      statusBadgeBg = const Color(0xFFF59E0B).withValues(alpha: 0.12);
      statusBadgeTextColor = const Color(0xFFD97706);
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
          onTap: () => StudentActionSheet.show(
            context: context,
            controller: widget.controller,
            record: item,
            examId: examId,
            examTitle: examTitle,
            isExamEnded: isExamEnded,
            onRefresh: () => _fetchExamParticipants(silent: true),
            onOpenAuditDetail: () => _showStudentDetailModal(
              context: context,
              item: item,
              isDark: isDark,
              examId: examId,
              examTitle: examTitle,
              defaultClassName: defaultClassName,
              modalType: 'participant',
              isExamEnded: isExamEnded,
            ),
          ),
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
                              if ((batteryLevel != null && batteryLevel >= 0) || isCharging) ...[
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: isLost
                                        ? (isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9))
                                        : isCharging
                                            ? const Color(0xFFF59E0B).withValues(alpha: 0.15)
                                            : (batteryLevel != null && batteryLevel <= 15)
                                                ? const Color(0xFFEF4444).withValues(alpha: 0.15)
                                                : const Color(0xFF10B981).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: isLost
                                          ? (isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1))
                                          : isCharging
                                              ? const Color(0xFFF59E0B).withValues(alpha: 0.4)
                                              : (batteryLevel != null && batteryLevel <= 15)
                                                  ? const Color(0xFFEF4444).withValues(alpha: 0.4)
                                                  : const Color(0xFF10B981).withValues(alpha: 0.4),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        isLost
                                            ? Icons.battery_std_rounded
                                            : isCharging
                                                ? Icons.bolt_rounded
                                                : (batteryLevel != null && batteryLevel <= 15)
                                                    ? Icons.battery_alert_rounded
                                                    : Icons.battery_std_rounded,
                                        size: 11,
                                        color: isLost
                                            ? (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B))
                                            : isCharging
                                                ? const Color(0xFFD97706)
                                                : (batteryLevel != null && batteryLevel <= 15)
                                                    ? const Color(0xFFEF4444)
                                                    : const Color(0xFF10B981),
                                      ),
                                      const SizedBox(width: 2),
                                      Text(
                                        isCharging && (batteryLevel == null || batteryLevel < 0)
                                            ? 'CAS'
                                            : '$batteryLevel%${isCharging && !isLost ? ' CAS' : ''}',
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w700,
                                          color: isLost
                                              ? (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B))
                                              : isCharging
                                                  ? const Color(0xFFD97706)
                                                  : (batteryLevel != null && batteryLevel <= 15)
                                                      ? const Color(0xFFEF4444)
                                                      : const Color(0xFF10B981),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              if (networkType != null && networkType.isNotEmpty) ...[
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: isLost
                                        ? (isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9))
                                        : const Color(0xFF10B981).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: isLost
                                          ? (isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1))
                                          : const Color(0xFF10B981).withValues(alpha: 0.4),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        networkType.toLowerCase().contains('wifi')
                                            ? Icons.wifi_rounded
                                            : Icons.signal_cellular_alt_rounded,
                                        size: 11,
                                        color: isLost
                                            ? (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B))
                                            : const Color(0xFF10B981),
                                      ),
                                      const SizedBox(width: 2),
                                      Text(
                                        networkType.toLowerCase().contains('wifi') ? 'Wi-Fi' : 'Seluler',
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w700,
                                          color: isLost
                                              ? (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B))
                                              : const Color(0xFF10B981),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              if (isOnCall) ...[
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: const Color(0xFFEF4444).withValues(alpha: 0.5),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.phone_in_talk_rounded,
                                        size: 11,
                                        color: Color(0xFFEF4444),
                                      ),
                                      SizedBox(width: 2.5),
                                      Text(
                                        'SEDANG TELPONAN',
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
                              const SizedBox(width: 4),
                              Icon(
                                Icons.chevron_right_rounded,
                                size: 18,
                                color: isDark ? const Color(0xFF475569) : const Color(0xFF94A3B8),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          // Line 1: Badge Kelas
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
                          const SizedBox(height: 4),
                          // Line 2: NISN
                          Text(
                            'NISN: $nisn',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                              color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                            ),
                          ),
                          // Line 3: Email (jika ada)
                          if (email.isNotEmpty && email != '-') ...[
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Icon(Icons.email_outlined, size: 12, color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    email,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 4),
                          // Line 4: Device binding row + extra mins + ketuk detail
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
                                'Ketuk untuk detail',
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
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.warning_rounded, size: 12, color: Color(0xFFEF4444)),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            'Pelanggaran: ${_formatViolationReason(lockReason)}',
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildViolationLogTab({
    required bool isDark,
    required List<Map<String, dynamic>> students,
    required dynamic examId,
    required String examTitle,
    required bool isExamEnded,
  }) {
    final searchQuery = _violationSearchController.text.trim().toLowerCase();

    final allViolationStudents = students.where((s) {
      final status = s['status']?.toString().toLowerCase() ?? 'pending';
      final lockReason = s['lock_reason']?.toString();
      final isKicked = status == 'terminated' || lockReason == 'proctor_kick' || s['is_kicked'] == true;
      final isLocked = s['is_locked'] == true || status == 'locked' || status == 'split_screen';
      return isLocked || isKicked || (lockReason != null && lockReason.isNotEmpty);
    }).toList();

    final filteredViolations = allViolationStudents.where((item) {
      if (searchQuery.isEmpty) return true;
      final user = item['user'] as Map<String, dynamic>? ?? {};
      final name = (user['name']?.toString() ?? '').toLowerCase();
      final nisn = (user['nisn']?.toString() ?? user['username']?.toString() ?? '').toLowerCase();
      final userClass = (user['class_major']?['name']?.toString() ?? user['class_name']?.toString() ?? '').toLowerCase();
      final lockReason = (item['lock_reason']?.toString() ?? '').toLowerCase();
      final formattedReason = _formatViolationReason(item['lock_reason']?.toString()).toLowerCase();

      return name.contains(searchQuery) ||
          nisn.contains(searchQuery) ||
          userClass.contains(searchQuery) ||
          lockReason.contains(searchQuery) ||
          formattedReason.contains(searchQuery);
    }).toList();

    if (_isLoadingStudents) {
      return const ParticipantRowSkeleton(
        count: 5,
        padding: EdgeInsets.fromLTRB(16, 12, 16, 100),
      );
    }

    return RefreshIndicator(
      color: const Color(0xFFEA580C),
      onRefresh: () async {
        await Future.wait([
          _fetchExamParticipants(silent: false),
          _fetchExamProctors(silent: true),
        ]);
      },
      child: CustomScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
        slivers: [
          // Pinned Search Filter Bar
          SliverPersistentHeader(
            pinned: true,
            delegate: _SliverTabBarDelegate(
              Container(
                color: AppTheme.background(context),
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                alignment: Alignment.center,
                child: TextField(
                  controller: _violationSearchController,
                  textInputAction: TextInputAction.search,
                  onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                  onSubmitted: (_) => FocusScope.of(context).unfocus(),
                  style: TextStyle(fontSize: 13, color: isDark ? Colors.white : const Color(0xFF0F172A)),
                  decoration: InputDecoration(
                    hintText: 'Cari pelanggar, NISN, atau alasan...',
                    hintStyle: TextStyle(fontSize: 12, color: isDark ? AppTheme.textSecondary : const Color(0xFF94A3B8)),
                    prefixIcon: const Icon(Icons.search_rounded, size: 18),
                    suffixIcon: _violationSearchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 16),
                            onPressed: () => _violationSearchController.clear(),
                          )
                        : null,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
              height: 58.0,
            ),
          ),

          // 3. Violation Items or Empty State
          if (allViolationStudents.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.verified_user_rounded,
                          size: 32,
                          color: Color(0xFF10B981),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Tidak Ada Catatan Pelanggaran',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Seluruh peserta mematuhi tata tertib ujian tanpa peringatan keamanan atau lock.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (filteredViolations.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.search_off_rounded, size: 42, color: isDark ? AppTheme.textSecondary : const Color(0xFFCBD5E1)),
                      const SizedBox(height: 10),
                      Text(
                        'Tidak ada catatan pelanggaran yang cocok dengan pencarian.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12.5, color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, index) {
                    final item = filteredViolations[index];
                    return _buildViolationCard(
                      context: ctx,
                      item: item,
                      isDark: isDark,
                      examId: examId,
                      examTitle: examTitle,
                      isExamEnded: isExamEnded,
                    );
                  },
                  childCount: filteredViolations.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildViolationCard({
    required BuildContext context,
    required Map<String, dynamic> item,
    required bool isDark,
    required dynamic examId,
    required String examTitle,
    required bool isExamEnded,
  }) {
    final user = item['user'] as Map<String, dynamic>? ?? {};
    final String status = item['status']?.toString().toLowerCase() ?? 'pending';
    final String? lockReason = item['lock_reason']?.toString();
    final bool isKicked = status == 'terminated' || lockReason == 'proctor_kick' || item['is_kicked'] == true;
    final bool isLocked = !isKicked && (item['is_locked'] == true || status == 'locked' || status == 'split_screen');
    final rawOnline = item['is_online'];
    final rawSecondsSince = item['seconds_since_heartbeat'];
    final int? secondsSince = rawSecondsSince is int ? rawSecondsSince : int.tryParse(rawSecondsSince?.toString() ?? '');
    final bool isLost = rawOnline == false || (secondsSince != null && secondsSince > 10);
    final bool isWaiting = !isKicked &&
        !isLocked &&
        item['unlocked_at'] != null &&
        (status == 'pending' || isLost) &&
        status != 'completed' &&
        status != 'submitted';
    final bool wasUnlocked = item['unlocked_at'] != null ||
        item['unlocked_by'] != null ||
        (!isLocked && !isKicked && (lockReason != null && lockReason.isNotEmpty));
    final bool canManageStudent = widget.controller.isAdmin ||
        widget.controller.canProctorExam(_currentExam, proctors: _examProctors) ||
        widget.controller.canUnlockStudentForExam(examId, exam: _currentExam);

    final rawIncidentTime = item['occurred_at'] ??
        item['locked_at'] ??
        item['lock_time'] ??
        item['created_at'] ??
        item['updated_at'];
    String incidentTimeFormatted = '';
    if (rawIncidentTime != null) {
      try {
        final dt = DateTime.parse(rawIncidentTime.toString()).toLocal();
        incidentTimeFormatted = '${DateFormat('d MMM, HH:mm').format(dt)} WIB';
      } catch (_) {}
    }

    final studentName = user['name']?.toString() ?? 'Peserta #${item['user_id'] ?? ''}';
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
                                    : isWaiting
                                        ? const Color(0xFFF59E0B).withValues(alpha: 0.15)
                                        : const Color(0xFF10B981).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isKicked
                                ? 'DIKELUARKAN'
                                : isLocked
                                    ? 'TERKUNCI'
                                    : isWaiting
                                        ? 'MENUNGGU'
                                        : 'SUDAH DIBUKA',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: isKicked
                                  ? const Color(0xFFBE123C)
                                  : isLocked
                                      ? const Color(0xFFEF4444)
                                      : isWaiting
                                          ? const Color(0xFFF59E0B)
                                          : const Color(0xFF10B981),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Line 1: Class Badge + NISN
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
                        Text(
                          'NISN: $nisn',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
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
                        'Pelanggaran: ${_formatViolationReason(lockReason)}',
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
              onPressed: () => StudentActionSheet.show(
                context: context,
                controller: widget.controller,
                record: item,
                examId: examId,
                examTitle: examTitle,
                isExamEnded: isExamEnded,
                onRefresh: () => _fetchExamParticipants(silent: true),
                onOpenAuditDetail: () => _showStudentDetailModal(
                  context: context,
                  item: item,
                  isDark: isDark,
                  examId: examId,
                  examTitle: examTitle,
                  defaultClassName: userClass,
                  modalType: 'violation',
                  isExamEnded: isExamEnded,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProctorsTab({
    required bool isDark,
    required dynamic examId,
    required String examTitle,
    required bool isExamEnded,
  }) {
    final proctors = _examProctors;
    final searchQuery = _proctorSearchController.text.trim().toLowerCase();

    final filteredProctors = proctors.where((p) {
      if (searchQuery.isEmpty) return true;
      final name = (p['name']?.toString() ?? '').toLowerCase();
      final nip = (p['nip']?.toString() ?? '').toLowerCase();
      final email = (p['email']?.toString() ?? '').toLowerCase();
      return name.contains(searchQuery) || nip.contains(searchQuery) || email.contains(searchQuery);
    }).toList();

    return RefreshIndicator(
      color: const Color(0xFFEA580C),
      onRefresh: () async {
        await Future.wait([
          _fetchExamParticipants(silent: true),
          _fetchExamProctors(silent: false),
        ]);
      },
      child: CustomScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
        slivers: [
          // Pinned Search & Action Bar
          SliverPersistentHeader(
            pinned: true,
            delegate: _SliverTabBarDelegate(
              Container(
                color: AppTheme.background(context),
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                alignment: Alignment.center,
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _proctorSearchController,
                        textInputAction: TextInputAction.search,
                        onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                        onSubmitted: (_) => FocusScope.of(context).unfocus(),
                        style: TextStyle(fontSize: 13, color: isDark ? Colors.white : const Color(0xFF0F172A)),
                        decoration: InputDecoration(
                          hintText: 'Cari nama atau NIP guru...',
                          hintStyle: TextStyle(fontSize: 12, color: isDark ? AppTheme.textSecondary : const Color(0xFF94A3B8)),
                          prefixIcon: const Icon(Icons.search_rounded, size: 18),
                          suffixIcon: _proctorSearchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded, size: 16),
                                  onPressed: () => _proctorSearchController.clear(),
                                )
                              : null,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                    if (widget.controller.canManageExam(_currentExam) && !isExamEnded) ...[
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFEA580C),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
                        label: const Text(
                          'Tugaskan',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        onPressed: () => _showAssignProctorModal(isDark: isDark, examId: examId),
                      ),
                    ],
                  ],
                ),
              ),
              height: 58.0,
            ),
          ),

          // 3. Proctors List
          if (_isLoadingProctors)
            const SliverToBoxAdapter(
              child: ParticipantRowSkeleton(
                count: 3,
                padding: EdgeInsets.fromLTRB(16, 8, 16, 30),
              ),
            )
          else if (proctors.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.supervisor_account_outlined,
                          size: 28,
                          color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Belum Ada Pengawas Ditugaskan',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.controller.canManageExam(_currentExam)
                            ? 'Ketuk tombol "Tugaskan" untuk menugaskan guru sebagai pengawas ujian ini.'
                            : 'Belum ada guru yang ditugaskan sebagai pengawas untuk sesi ujian ini.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.4,
                          color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (filteredProctors.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.search_off_rounded, size: 42, color: isDark ? AppTheme.textSecondary : const Color(0xFFCBD5E1)),
                      const SizedBox(height: 10),
                      Text(
                        'Tidak ada pengawas yang cocok dengan pencarian.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12.5, color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, index) {
                    final item = filteredProctors[index];
                    return _buildProctorCard(
                      context: ctx,
                      proctor: item,
                      isDark: isDark,
                      examId: examId,
                      isExamEnded: isExamEnded,
                    );
                  },
                  childCount: filteredProctors.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProctorCard({
    required BuildContext context,
    required Map<String, dynamic> proctor,
    required bool isDark,
    required dynamic examId,
    required bool isExamEnded,
  }) {
    final name = proctor['name']?.toString() ?? 'Guru Pengawas';
    final nip = proctor['nip']?.toString() ?? '-';
    final email = proctor['email']?.toString() ?? '';
    final bool isCreator = proctor['is_creator'] == true;
    final assignedAt = proctor['assigned_at']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCreator
              ? const Color(0xFF3B82F6).withValues(alpha: 0.35)
              : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: isCreator
                    ? const Color(0xFF3B82F6).withValues(alpha: 0.15)
                    : const Color(0xFF10B981).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : 'G',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: isCreator ? const Color(0xFF3B82F6) : const Color(0xFF10B981),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
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
                          color: isCreator
                              ? const Color(0xFF3B82F6).withValues(alpha: 0.12)
                              : const Color(0xFF10B981).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isCreator ? 'PEMBUAT UJIAN' : 'PENGAWAS',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: isCreator ? const Color(0xFF3B82F6) : const Color(0xFF10B981),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.badge_outlined, size: 12, color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
                      const SizedBox(width: 4),
                      Text(
                        'NIP: $nip',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                  if (email.isNotEmpty && email != '-') ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(Icons.email_outlined, size: 12, color: isDark ? AppTheme.textSecondary : const Color(0xFF94A3B8)),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (assignedAt.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      'Ditugaskan: ${_formatAssignedDate(assignedAt)}',
                      style: TextStyle(
                        fontSize: 10,
                        color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Action button (unassign) if not creator, exam not ended, and user has authority to manage
            if (widget.controller.canManageExam(_currentExam) && !isCreator && examId != null && !isExamEnded)
              IconButton(
                icon: const Icon(Icons.person_remove_outlined, size: 18, color: Color(0xFFEF4444)),
                tooltip: 'Hapus Penugasan',
                onPressed: () => _confirmRemoveProctor(proctor: proctor, examId: examId),
              ),
          ],
        ),
      ),
    );
  }

  String _formatAssignedDate(String dateStr) {
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      return DateFormat('d MMM yyyy, HH:mm', 'id_ID').format(dt);
    } catch (_) {
      return dateStr;
    }
  }

  void _showAssignProctorModal({
    required bool isDark,
    required dynamic examId,
  }) {
    if (widget.controller.teachers.isEmpty) {
      widget.controller.loadTeachers();
    }

    final searchCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 600),
      backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (modalCtx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final teachers = widget.controller.teachers;
            final assignedProctorUserIds = _examProctors.map((p) => p['id'] ?? p['user_id']).toSet();
            final query = searchCtrl.text.trim().toLowerCase();

            final filteredTeachers = teachers.where((t) {
              if (query.isEmpty) return true;
              final name = (t['name']?.toString() ?? '').toLowerCase();
              final nip = (t['nip']?.toString() ?? '').toLowerCase();
              final email = (t['email']?.toString() ?? '').toLowerCase();
              return name.contains(query) || nip.contains(query) || email.contains(query);
            }).toList();

            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.72,
                    child: Column(
                  children: [
                    // Drag Handle
                    const SizedBox(height: 12),
                    Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Modal Header
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEA580C).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.person_add_alt_1_rounded, size: 20, color: Color(0xFFEA580C)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Tugaskan Pengawas Ujian',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Pilih guru dari sekolah untuk mengawasi sesi ujian ini.',
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
                    const SizedBox(height: 12),

                    // Search field
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: TextField(
                        controller: searchCtrl,
                        textInputAction: TextInputAction.search,
                        onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                        onSubmitted: (_) => FocusScope.of(context).unfocus(),
                        onChanged: (_) => setModalState(() {}),
                        style: TextStyle(fontSize: 13, color: isDark ? Colors.white : const Color(0xFF0F172A)),
                        decoration: InputDecoration(
                          hintText: 'Cari guru atau NIP...',
                          hintStyle: TextStyle(fontSize: 12, color: isDark ? AppTheme.textSecondary : const Color(0xFF94A3B8)),
                          prefixIcon: const Icon(Icons.search_rounded, size: 18),
                          suffixIcon: searchCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded, size: 16),
                                  onPressed: () {
                                    searchCtrl.clear();
                                    setModalState(() {});
                                  },
                                )
                              : null,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          filled: true,
                          fillColor: isDark ? AppTheme.surfaceDark : const Color(0xFFF8FAFC),
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
                    const SizedBox(height: 10),

                    // Teacher List
                    Expanded(
                      child: filteredTeachers.isEmpty
                          ? Center(
                              child: Text(
                                'Tidak ada guru yang ditemukan.',
                                style: TextStyle(fontSize: 12.5, color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
                              ),
                            )
                          : ListView.separated(
                              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                              padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
                              itemCount: filteredTeachers.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (itemCtx, index) {
                                final teacher = filteredTeachers[index];
                                final teacherId = teacher['id'];
                                final teacherName = teacher['name']?.toString() ?? 'Guru';
                                final teacherNip = teacher['nip']?.toString() ?? '-';
                                final isAssigned = assignedProctorUserIds.contains(teacherId);

                                return Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: isDark ? AppTheme.surfaceDark : const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: isAssigned
                                          ? const Color(0xFF10B981).withValues(alpha: 0.3)
                                          : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 38,
                                        height: 38,
                                        decoration: BoxDecoration(
                                          color: isAssigned
                                              ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                              : const Color(0xFFEA580C).withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Center(
                                          child: Text(
                                            teacherName.isNotEmpty ? teacherName[0].toUpperCase() : 'G',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                              color: isAssigned ? const Color(0xFF10B981) : const Color(0xFFEA580C),
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
                                              teacherName,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              'NIP: $teacherNip',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (isAssigned)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: const Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.check_circle_rounded, size: 12, color: Color(0xFF10B981)),
                                              SizedBox(width: 4),
                                              Text(
                                                'Ditugaskan',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color: Color(0xFF10B981),
                                                ),
                                              ),
                                            ],
                                          ),
                                        )
                                      else
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFFEA580C),
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                            elevation: 0,
                                            minimumSize: Size.zero,
                                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          ),
                                          onPressed: () async {
                                            Navigator.of(ctx).pop();
                                            final ok = await widget.controller.assignExamProctor(examId, teacherId);
                                            if (!mounted) return;
                                            if (ok) {
                                              await _fetchExamProctors();
                                              if (!mounted) return;
                                              AppNotification.showSuccess(
                                                context,
                                                'Pengawas Berhasil Ditugaskan',
                                                subtitle: '$teacherName telah ditugaskan sebagai pengawas.',
                                              );
                                            } else {
                                              AppNotification.showError(
                                                context,
                                                'Gagal Menugaskan Pengawas',
                                                subtitle: 'Terjadi kesalahan saat menyimpan data.',
                                              );
                                            }
                                          },
                                          child: const Text('Tugaskan', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                                        ),
                                    ],
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

  Future<void> _confirmRemoveProctor({
    required Map<String, dynamic> proctor,
    required dynamic examId,
  }) async {
    final name = proctor['name']?.toString() ?? 'Pengawas';
    final teacherId = proctor['id'] ?? proctor['user_id'];

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Hapus Pengawas Ujian?'),
        content: Text('Apakah Anda yakin ingin membatalkan penugasan $name sebagai pengawas ujian ini?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Hapus Penugasan', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final ok = await widget.controller.removeExamProctor(examId, teacherId);
      if (!mounted) return;
      if (ok) {
        await _fetchExamProctors();
        if (!mounted) return;
        AppNotification.showSuccess(
          context,
          'Penugasan Dibatalkan',
          subtitle: '$name tidak lagi menjadi pengawas ujian ini.',
        );
      } else {
        AppNotification.showError(
          context,
          'Gagal Menghapus Penugasan',
          subtitle: 'Tidak dapat membatalkan penugasan pengawas dari server.',
        );
      }
    }
  }

  Widget _buildSessionInfoTab({
    required bool isDark,
    required Widget headerCard,
    required String title,
    required String subject,
    required String className,
    required String creatorName,
    String? creatorNip,
    String? creatorEmail,
    required String dateFormatted,
    required String timeWindowFormatted,
    required String duration,
    required String autoStatusLabel,
    required Color autoStatusColor,
    required String token,
    required String examUrl,
  }) {
    return RefreshIndicator(
      color: const Color(0xFFEA580C),
      onRefresh: () async {
        await Future.wait([
          _fetchExamParticipants(silent: true),
          _fetchExamProctors(silent: true),
        ]);
      },
      child: CustomScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
        slivers: [
          // 1. Header Summary Card
          SliverToBoxAdapter(child: headerCard),

          // 2. Session Info Sections
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
            sliver: SliverToBoxAdapter(
              child: Column(
                children: [
                  // Section 1: Spesifikasi & Jadwal Ujian
                  _buildCompactSection(
                    title: 'Spesifikasi & Jadwal Ujian',
                    icon: Icons.calendar_month_rounded,
                    isDark: isDark,
                    children: [
                      _buildCompactRow(
                        icon: Icons.assignment_outlined,
                        label: 'Judul Ujian',
                        isDark: isDark,
                        valueWidget: Text(
                          title,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                      ),
                      _buildCompactRow(
                        icon: Icons.person_outline_rounded,
                        label: 'Pembuat Ujian',
                        isDark: isDark,
                        valueWidget: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.badge_outlined, size: 12, color: Color(0xFF3B82F6)),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      creatorName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF3B82F6),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (creatorNip != null && creatorNip.isNotEmpty && creatorNip != '-') ...[
                              const SizedBox(height: 2),
                              Text(
                                'NIP: $creatorNip',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w500,
                                  color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      _buildCompactRow(
                        icon: Icons.menu_book_rounded,
                        label: 'Mata Pelajaran',
                        isDark: isDark,
                        valueWidget: Text(
                          subject,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                      ),
                      _buildCompactRow(
                        icon: Icons.groups_rounded,
                        label: 'Kelas Sasaran',
                        isDark: isDark,
                        valueWidget: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            className,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF8B5CF6),
                            ),
                          ),
                        ),
                      ),
                      _buildCompactRow(
                        icon: Icons.event_rounded,
                        label: 'Tanggal Pelaksanaan',
                        isDark: isDark,
                        valueWidget: Text(
                          dateFormatted,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                      ),
                      _buildCompactRow(
                        icon: Icons.schedule_rounded,
                        label: 'Waktu / Jam Ujian',
                        isDark: isDark,
                        valueWidget: Text(
                          timeWindowFormatted,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                      ),
                      _buildCompactRow(
                        icon: Icons.timer_outlined,
                        label: 'Durasi Pengerjaan',
                        showDivider: false,
                        isDark: isDark,
                        valueWidget: Text(
                          FormatUtils.formatDurationHoursMinutes(duration),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Section 2: Akses & Keamanan Sesi
                  _buildCompactSection(
                    title: 'Akses & Keamanan Sesi',
                    icon: Icons.security_rounded,
                    isDark: isDark,
                    children: [
                      _buildCompactRow(
                        icon: Icons.info_outline_rounded,
                        label: 'Status Pelaksanaan',
                        isDark: isDark,
                        valueWidget: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                          decoration: BoxDecoration(
                            color: autoStatusColor.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: autoStatusColor.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            autoStatusLabel,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                              color: autoStatusColor,
                            ),
                          ),
                        ),
                      ),
                      _buildCompactRow(
                        icon: Icons.pin_rounded,
                        label: 'Token PIN Akses',
                        showDivider: examUrl.isNotEmpty,
                        isDark: isDark,
                        onTap: (token.isNotEmpty && token != '-') ? () => _copyToken(token) : null,
                        valueWidget: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEA580C).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFEA580C).withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                token,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12.5,
                                  letterSpacing: 1.1,
                                  color: Color(0xFFEA580C),
                                ),
                              ),
                              const SizedBox(width: 5),
                              const Icon(Icons.copy_rounded, size: 12, color: Color(0xFFEA580C)),
                            ],
                          ),
                        ),
                      ),
                      if (examUrl.isNotEmpty)
                        _buildCompactRow(
                          icon: Icons.link_rounded,
                          label: 'Tautan URL Soal',
                          showDivider: false,
                          isDark: isDark,
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: examUrl));
                            AppNotification.showSuccess(
                              context,
                              'Link Soal Disalin',
                              subtitle: 'Tautan URL disimpan di clipboard.',
                            );
                          },
                          valueWidget: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 150),
                                child: Text(
                                  examUrl,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF0284C7),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.copy_rounded, size: 12, color: Color(0xFF0284C7)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showStudentDetailModal({
    required BuildContext context,
    required Map<String, dynamic> item,
    required bool isDark,
    required dynamic examId,
    required String examTitle,
    required String defaultClassName,
    String modalType = 'participant',
    bool isExamEnded = false,
  }) {
    StudentDetailModal.show(
      context: context,
      controller: widget.controller,
      item: item,
      examId: examId,
      examTitle: examTitle,
      defaultClassName: defaultClassName,
      modalType: modalType,
      isExamEnded: isExamEnded,
      onRefresh: () => _fetchExamParticipants(silent: true),
    );
  }

  Widget _buildStatPill(String text, Color color, bool isDark) {
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildCompactSection({
    required String title,
    required IconData icon,
    required bool isDark,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Row(
            children: [
              Icon(icon, size: 14, color: const Color(0xFFEA580C)),
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

class _SliverTabBarDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double height;

  _SliverTabBarDelegate(this.child, {this.height = 56.0});

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return SizedBox(height: height, child: child);
  }

  @override
  bool shouldRebuild(_SliverTabBarDelegate oldDelegate) {
    return oldDelegate.child != child || oldDelegate.height != height;
  }
}
