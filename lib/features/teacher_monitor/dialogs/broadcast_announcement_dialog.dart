import 'package:flutter/material.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/app_notification.dart';
import '../../../shared/widgets/shiei_select_sheet.dart';
import '../teacher_portal_controller.dart';

class BroadcastAnnouncementDialog extends StatefulWidget {
  final int? initialExamId;
  final TeacherPortalController controller;

  const BroadcastAnnouncementDialog({
    super.key,
    this.initialExamId,
    required this.controller,
  });

  static Future<void> show({
    required BuildContext context,
    int? initialExamId,
    required TeacherPortalController controller,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BroadcastAnnouncementDialog(
        initialExamId: initialExamId,
        controller: controller,
      ),
    );
  }

  @override
  State<BroadcastAnnouncementDialog> createState() => _BroadcastAnnouncementDialogState();
}

class _BroadcastAnnouncementDialogState extends State<BroadcastAnnouncementDialog> {
  final _messageController = TextEditingController();
  final _studentSearchController = TextEditingController();
  int? _selectedExamId;
  String _announcementType = 'warning'; // 'info', 'warning', 'urgent'
  String _targetScope = 'all'; // 'all' | 'selected'
  final Set<int> _selectedStudentIds = <int>{};
  List<Map<String, dynamic>> _activeParticipants = [];
  bool _isLoadingParticipants = false;
  bool _isSending = false;
  bool _isLoadingAnnouncements = false;
  List<Map<String, dynamic>> _activeAnnouncements = [];

  final List<String> _quickPresets = [
    'Waktu ujian sisa 15 menit lagi.',
    'Waktu ujian sisa 5 menit, segera kumpulkan.',
    'Ada ralat pada soal nomor: ',
    'Periksa kembali seluruh jawaban sebelum dikumpulkan.',
  ];

  @override
  void initState() {
    super.initState();
    _selectedExamId = widget.initialExamId;
    _loadExamContext();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _studentSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadExamContext() async {
    await Future.wait([
      _loadAnnouncements(),
      _loadParticipants(),
    ]);
  }

  static bool _isExamFinishedOrInactive(Map<String, dynamic>? exam) {
    if (exam == null) return false;
    final status = exam['status']?.toString().toLowerCase() ?? 'active';
    final isActive = exam['is_active'] ?? (status == 'active');
    if (isActive == false || status == 'inactive') return true;
    final endTimeStr = exam['end_time']?.toString();
    if (endTimeStr != null && endTimeStr.isNotEmpty) {
      final end = DateTime.tryParse(endTimeStr);
      if (end != null && DateTime.now().isAfter(end)) {
        return true;
      }
    }
    return false;
  }

  Map<String, dynamic>? _findSelectedExam() {
    if (_selectedExamId == null) return null;
    for (final e in widget.controller.exams) {
      if (e['id'] == _selectedExamId) return e;
    }
    return null;
  }

  bool get _isSelectedExamEnded => _isExamFinishedOrInactive(_findSelectedExam());

  static bool _isParticipantWorkingInExam(
    Map<String, dynamic> session, {
    bool examEnded = false,
  }) {
    if (examEnded) return false;
    final linkEndStr = session['link']?['end_time']?.toString();
    if (linkEndStr != null && linkEndStr.isNotEmpty) {
      final end = DateTime.tryParse(linkEndStr);
      if (end != null && DateTime.now().isAfter(end)) return false;
    }

    final status = (session['status'] ?? '').toString().toLowerCase();
    final hasScore = session['score'] != null;
    final isCompleted = status == 'completed' || status == 'submitted' || hasScore;
    final isTerminated = status == 'terminated' ||
        status == 'exited' ||
        session['lock_reason']?.toString() == 'proctor_kick' ||
        session['is_kicked'] == true;
    final isLocked = session['is_locked'] == true ||
        status == 'locked' ||
        status == 'split_screen';
    final secHeartbeat = int.tryParse(
      session['seconds_since_heartbeat']?.toString() ?? '',
    );
    final isOffline = session['is_online'] == false ||
        (secHeartbeat != null && secHeartbeat > 10);

    if (isCompleted || isTerminated || isLocked || isOffline) return false;
    return status == 'in_progress' || status == 'started';
  }

  static int? _extractParticipantUserId(Map<String, dynamic> session) {
    final raw = session['user_id'] ?? session['user']?['id'];
    if (raw == null) return null;
    return raw is int ? raw : int.tryParse(raw.toString());
  }

  Future<void> _loadParticipants() async {
    if (_selectedExamId == null || _isSelectedExamEnded) {
      if (mounted) {
        setState(() {
          _activeParticipants = [];
          _selectedStudentIds.clear();
          _isLoadingParticipants = false;
        });
      }
      return;
    }
    setState(() => _isLoadingParticipants = true);
    final sessions = await widget.controller.loadExamParticipants(_selectedExamId);
    final examEnded = _isSelectedExamEnded;
    final seenIds = <int>{};
    final activeList = <Map<String, dynamic>>[];
    for (final s in sessions) {
      final uid = _extractParticipantUserId(s);
      if (uid == null || !seenIds.add(uid)) continue;
      if (!_isParticipantWorkingInExam(s, examEnded: examEnded)) continue;
      activeList.add(s);
    }
    activeList.sort((a, b) {
      final nameA = (a['user']?['name'] ?? '').toString().toLowerCase();
      final nameB = (b['user']?['name'] ?? '').toString().toLowerCase();
      return nameA.compareTo(nameB);
    });
    if (mounted) {
      setState(() {
        _activeParticipants = activeList;
        _selectedStudentIds.removeWhere((id) => !seenIds.contains(id));
        _isLoadingParticipants = false;
      });
    }
  }

  Future<void> _loadAnnouncements() async {
    if (_selectedExamId == null) return;
    setState(() => _isLoadingAnnouncements = true);
    final list = await widget.controller.getAnnouncements(_selectedExamId!);
    if (mounted) {
      setState(() {
        _activeAnnouncements = list;
        _isLoadingAnnouncements = false;
      });
    }
  }

  Future<void> _handleSend() async {
    if (_isSelectedExamEnded) {
      AppNotification.showError(
        context,
        'Ujian Sudah Berakhir',
        subtitle: 'Pengiriman pengumuman dinonaktifkan untuk ujian yang sudah selesai.',
      );
      return;
    }

    final text = _messageController.text.trim();
    if (text.isEmpty) {
      AppNotification.showError(context, 'Pesan Kosong', subtitle: 'Ketik isi pengumuman terlebih dahulu.');
      return;
    }

    if (_selectedExamId == null) {
      AppNotification.showError(context, 'Pilih Ujian', subtitle: 'Tentukan jadwal ujian tujuan siaran.');
      return;
    }

    if (_targetScope == 'selected' && _selectedStudentIds.isEmpty) {
      AppNotification.showError(context, 'Pilih Murid Tujuan', subtitle: 'Pilih minimal 1 murid yang sedang ujian.');
      return;
    }

    setState(() => _isSending = true);

    final error = await widget.controller.sendAnnouncement(
      _selectedExamId!,
      text,
      type: _announcementType,
      targetScope: _targetScope,
      targetUserIds: _targetScope == 'selected' ? _selectedStudentIds.toList() : const [],
    );

    if (!mounted) return;
    setState(() => _isSending = false);

    if (error == null) {
      _messageController.clear();
      AppNotification.showSuccess(
        context,
        'Pengumuman Terkirim!',
        subtitle: _targetScope == 'selected'
            ? 'Pesan khusus dikirim ke ${_selectedStudentIds.length} murid terpilih.'
            : 'Pesan telah disiarkan ke seluruh layar ujian siswa.',
      );
      _loadAnnouncements();
    } else {
      AppNotification.showError(context, 'Gagal Menyiarkan', subtitle: error);
    }
  }

  Future<void> _handleDelete(int annId) async {
    if (_selectedExamId == null) return;
    final error = await widget.controller.deleteAnnouncement(_selectedExamId!, annId);
    if (!mounted) return;

    if (error == null) {
      _loadAnnouncements();
      AppNotification.showSuccess(context, 'Pengumuman Dihapus');
    } else {
      AppNotification.showError(context, 'Gagal Menghapus', subtitle: error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final exams = widget.controller.activeExams;
    final selectedExam = _findSelectedExam();
    final isComposerDisabled =
        _selectedExamId == null ? exams.isEmpty : _isSelectedExamEnded;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomInset),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.surfaceDark : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
        ),
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle Bar
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.campaign_rounded, color: Color(0xFFF59E0B), size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Siarkan Pengumuman',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Pesan mengambang langsung di layar ujian siswa',
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
            const SizedBox(height: 14),
            Container(
              height: 1,
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
            ),
            const SizedBox(height: 16),

            // 1. Target Exam Custom Modern Selector
            ShieiSelectorField(
              label: 'Target Ujian *',
              isDark: isDark,
              placeholder: 'Pilih Jadwal Ujian Aktif',
              prefixIcon: Icons.menu_book_rounded,
              valueText: () {
                if (selectedExam == null) return null;
                final t = selectedExam['title']?.toString() ?? 'Ujian';
                final s = selectedExam['subject']?.toString() ?? '';
                final base = s.isNotEmpty ? '$t • $s' : t;
                return _isSelectedExamEnded ? '$base (Selesai)' : base;
              }(),
              onTap: () async {
                FocusScope.of(context).unfocus();
                if (exams.isEmpty) {
                  AppNotification.showInfo(
                    context,
                    'Tidak Ada Ujian Aktif',
                    subtitle: 'Siaran pengumuman hanya dapat dikirim ke jadwal ujian yang sedang aktif.',
                  );
                  return;
                }
                final selected = await ShieiSelectSheet.show<int>(
                  context: context,
                  title: 'Pilih Jadwal Ujian Aktif',
                  subtitle: 'Tentukan ujian sasaran siaran pengumuman',
                  selectedValue: _selectedExamId,
                  searchHint: 'Cari judul ujian atau mapel...',
                  items: exams.map((e) {
                    final id = e['id'] as int;
                    final title = e['title']?.toString() ?? 'Ujian';
                    final subject = e['subject']?.toString() ?? '';
                    final code = e['token']?.toString() ?? '';
                    return ShieiSelectItem<int>(
                      value: id,
                      label: title,
                      subtitle: subject.isNotEmpty ? '$subject (PIN: $code)' : 'PIN: $code',
                      icon: Icons.assignment_outlined,
                      badge: code.isNotEmpty ? code : null,
                    );
                  }).toList(),
                );
                if (selected != null && selected != _selectedExamId) {
                  setState(() {
                    _selectedExamId = selected;
                    _selectedStudentIds.clear();
                    _studentSearchController.clear();
                  });
                  _loadExamContext();
                }
              },
            ),
            const SizedBox(height: 14),

            if (isComposerDisabled) ...[
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.event_busy_rounded,
                      size: 18,
                      color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _selectedExamId != null
                            ? 'Jadwal ujian ini telah selesai atau nonaktif. Pengiriman pengumuman dinonaktifkan.'
                            : 'Tidak ada jadwal ujian yang sedang aktif saat ini.',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            IgnorePointer(
              ignoring: isComposerDisabled,
              child: Opacity(
                opacity: isComposerDisabled ? 0.5 : 1.0,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
            // 1.5 Target Recipient Mode (All vs Selected Working Students)
            Text(
              'Sasaran Penerima',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white70 : const Color(0xFF475569),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                _buildScopeChip(
                  scope: 'all',
                  label: 'Semua Peserta',
                  icon: Icons.groups_rounded,
                  color: const Color(0xFFF59E0B),
                  isDark: isDark,
                ),
                const SizedBox(width: 8),
                _buildScopeChip(
                  scope: 'selected',
                  label: 'Pilih Murid (${_activeParticipants.length})',
                  icon: Icons.person_search_rounded,
                  color: const Color(0xFF6366F1),
                  isDark: isDark,
                ),
              ],
            ),
            if (!isComposerDisabled && _targetScope == 'selected') ...[
              const SizedBox(height: 10),
              _buildSelectedParticipantsBox(isDark),
            ],
            const SizedBox(height: 14),

            // 2. Priority Type Selector
            Text(
              'Tingkat Urgensi',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white70 : const Color(0xFF475569),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                _buildTypeChip('info', 'Info (Biru)', const Color(0xFF3B82F6), isDark),
                const SizedBox(width: 8),
                _buildTypeChip('warning', 'Ralat / Peringatan', const Color(0xFFF59E0B), isDark),
                const SizedBox(width: 8),
                _buildTypeChip('urgent', 'Mendesak (Merah)', const Color(0xFFEF4444), isDark),
              ],
            ),
            const SizedBox(height: 14),

            // 3. Quick Preset Chips
            Text(
              'Pilihan Cepat',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white70 : const Color(0xFF475569),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _quickPresets.map((preset) {
                return ActionChip(
                  label: Text(preset, style: const TextStyle(fontSize: 11)),
                  backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(
                      color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                    ),
                  ),
                  onPressed: isComposerDisabled
                      ? null
                      : () {
                          FocusScope.of(context).unfocus();
                          _messageController.text = preset;
                          _messageController.selection = TextSelection.fromPosition(
                            TextPosition(offset: _messageController.text.length),
                          );
                        },
                );
              }).toList(),
            ),
            const SizedBox(height: 14),

            // 4. Message Input
            _buildLabel('Isi Pesan Pengumuman *', isDark),
            TextField(
              controller: _messageController,
              enabled: !isComposerDisabled,
              maxLines: 3,
              maxLength: 500,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => FocusScope.of(context).unfocus(),
              onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
              style: TextStyle(fontSize: 13, color: isDark ? Colors.white : const Color(0xFF0F172A)),
              decoration: InputDecoration(
                hintText: isComposerDisabled
                    ? 'Ujian telah selesai. Pengiriman dinonaktifkan.'
                    : 'Ketik pesan pengumuman atau ralat soal di sini...',
                hintStyle: TextStyle(fontSize: 12.5, color: isDark ? AppTheme.textSecondary : const Color(0xFF94A3B8)),
                filled: true,
                fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                ),
                contentPadding: const EdgeInsets.all(14),
              ),
            ),
            const SizedBox(height: 14),

            // 5. Submit Button
            AnimatedBuilder(
              animation: _messageController,
              builder: (context, _) {
                final bool hasValidTarget =
                    _targetScope == 'all' || _selectedStudentIds.isNotEmpty;
                final bool canSubmit = !isComposerDisabled &&
                    !_isSending &&
                    _selectedExamId != null &&
                    hasValidTarget &&
                    _messageController.text.trim().isNotEmpty;

                return SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _targetScope == 'selected'
                          ? const Color(0xFF6366F1)
                          : const Color(0xFFF59E0B),
                      disabledBackgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                      foregroundColor: Colors.white,
                      disabledForegroundColor: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    icon: _isSending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded, size: 18),
                    label: Text(
                      isComposerDisabled
                          ? 'Ujian Telah Selesai'
                          : (_isSending
                              ? 'Menyiarkan...'
                              : (_targetScope == 'selected'
                                  ? 'Kirim ke ${_selectedStudentIds.length} Murid Terpilih'
                                  : 'Siarkan ke Semua Peserta')),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                    ),
                    onPressed: canSubmit ? _handleSend : null,
                  ),
                );
              },
            ),
                  ],
                ),
              ),
            ),

            // 6. Active Announcements List
            if (_activeAnnouncements.isNotEmpty) ...[
              const SizedBox(height: 20),
              Container(
                height: 1,
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Pengumuman Aktif (${_activeAnnouncements.length})',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  if (_isLoadingAnnouncements)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              ..._activeAnnouncements.map((ann) {
                final id = ann['id'] as int;
                final msg = ann['message']?.toString() ?? '';
                final type = ann['type']?.toString() ?? 'info';
                final proctor = ann['proctor']?.toString() ?? 'Pengawas';
                final targetLabel = _formatTargetLabel(ann);
                final isPersonal = ann['target_scope']?.toString() == 'selected';

                Color typeColor;
                switch (type) {
                  case 'urgent':
                    typeColor = const Color(0xFFEF4444);
                    break;
                  case 'warning':
                    typeColor = const Color(0xFFF59E0B);
                    break;
                  default:
                    typeColor = const Color(0xFF3B82F6);
                }

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: typeColor.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.campaign_outlined, color: typeColor, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              msg,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$targetLabel • Oleh: $proctor',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: isPersonal ? FontWeight.w600 : FontWeight.normal,
                                color: isPersonal
                                    ? const Color(0xFF6366F1)
                                    : (isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFFEF4444)),
                        tooltip: 'Hapus Siaran',
                        onPressed: () => _handleDelete(id),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    ),
    );
  }

  String _formatTargetLabel(Map<String, dynamic> ann) {
    if (ann['target_scope']?.toString() != 'selected') {
      return 'Semua Peserta';
    }
    final names = (ann['target_user_names'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .where((s) => s.isNotEmpty)
            .toList() ??
        const <String>[];
    final idsCount = (ann['target_user_ids'] as List<dynamic>?)?.length ?? 0;
    final count = names.isNotEmpty ? names.length : idsCount;
    if (names.isNotEmpty) {
      final preview = names.take(2).join(', ');
      return names.length > 2
          ? 'Khusus $count Murid ($preview +${names.length - 2})'
          : 'Khusus $count Murid ($preview)';
    }
    return count > 0 ? 'Khusus $count Murid' : 'Murid Terpilih';
  }

  Widget _buildScopeChip({
    required String scope,
    required String label,
    required IconData icon,
    required Color color,
    required bool isDark,
  }) {
    final isSelected = _targetScope == scope;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          FocusScope.of(context).unfocus();
          setState(() => _targetScope = scope);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? color.withValues(alpha: 0.14)
                : (isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC)),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? color
                  : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: isSelected
                    ? color
                    : (isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected
                        ? color
                        : (isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedParticipantsBox(bool isDark) {
    final query = _studentSearchController.text.trim().toLowerCase();
    final filtered = _activeParticipants.where((s) {
      if (query.isEmpty) return true;
      final name = (s['user']?['name'] ?? '').toString().toLowerCase();
      final nisn = (s['user']?['nisn'] ?? '').toString().toLowerCase();
      final cls = (s['user']?['class_major']?['name'] ?? '').toString().toLowerCase();
      return name.contains(query) || nisn.contains(query) || cls.contains(query);
    }).toList();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF6366F1).withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Murid Sedang Ujian (${_selectedStudentIds.length} dipilih)',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (filtered.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          for (final s in filtered) {
                            final uid = _extractParticipantUserId(s);
                            if (uid != null) _selectedStudentIds.add(uid);
                          }
                        });
                      },
                      child: const Text(
                        'Pilih Semua',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF6366F1),
                        ),
                      ),
                    ),
                  if (_selectedStudentIds.isNotEmpty) ...[
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: () => setState(() => _selectedStudentIds.clear()),
                      child: const Text(
                        'Reset',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFEF4444),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _studentSearchController,
            onChanged: (_) => setState(() {}),
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Cari nama, NISN, atau kelas murid...',
              hintStyle: TextStyle(
                fontSize: 11.5,
                color: isDark ? AppTheme.textSecondary : const Color(0xFF94A3B8),
              ),
              prefixIcon: const Icon(Icons.search_rounded, size: 17),
              suffixIcon: _studentSearchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded, size: 16),
                      onPressed: () {
                        _studentSearchController.clear();
                        setState(() {});
                      },
                    )
                  : null,
              filled: true,
              fillColor: isDark ? AppTheme.surfaceDark : Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (_isLoadingParticipants)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Center(
                child: Text(
                  _activeParticipants.isEmpty
                      ? 'Belum ada murid yang sedang mengerjakan ujian ini.'
                      : 'Tidak ada murid aktif yang cocok dengan pencarian.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                  ),
                ),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 175),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (_, idx) {
                  final s = filtered[idx];
                  final uid = _extractParticipantUserId(s);
                  if (uid == null) return const SizedBox.shrink();
                  final isChecked = _selectedStudentIds.contains(uid);
                  final name = (s['user']?['name'] ?? 'Siswa #$uid').toString();
                  final cls = (s['user']?['class_major']?['name'] ?? '').toString();
                  final nisn = (s['user']?['nisn'] ?? '').toString();
                  final isLocked = s['is_locked'] == true ||
                      s['status']?.toString() == 'locked' ||
                      s['status']?.toString() == 'split_screen';
                  final statusLabel = isLocked
                      ? 'Terkunci'
                      : (s['status']?.toString() == 'pending' ? 'Menunggu' : 'Sedang Ujian');
                  final statusColor = isLocked
                      ? const Color(0xFFEF4444)
                      : (s['status']?.toString() == 'pending'
                          ? const Color(0xFFF59E0B)
                          : AppTheme.accentGreen);

                  return InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      setState(() {
                        if (isChecked) {
                          _selectedStudentIds.remove(uid);
                        } else {
                          _selectedStudentIds.add(uid);
                        }
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: isChecked
                            ? const Color(0xFF6366F1).withValues(alpha: 0.1)
                            : (isDark ? AppTheme.surfaceDark : Colors.white),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isChecked
                              ? const Color(0xFF6366F1)
                              : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isChecked ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                            size: 18,
                            color: isChecked
                                ? const Color(0xFF6366F1)
                                : (isDark ? Colors.white54 : const Color(0xFF94A3B8)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                                  ),
                                ),
                                if (cls.isNotEmpty || nisn.isNotEmpty)
                                  Text(
                                    [cls, nisn].where((e) => e.isNotEmpty).join(' • '),
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              statusLabel,
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: statusColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTypeChip(String type, String label, Color color, bool isDark) {
    final isSelected = _announcementType == type;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          FocusScope.of(context).unfocus();
          setState(() => _announcementType = type);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.15) : (isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC)),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? color : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? color : (isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
              ),
            ),
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
}
