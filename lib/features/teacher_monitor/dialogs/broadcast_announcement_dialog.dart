import 'package:flutter/material.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../shared/widgets/app_notification.dart';
import '../../../../shared/widgets/shiei_select_sheet.dart';
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
  int? _selectedExamId;
  String _announcementType = 'warning'; // 'info', 'warning', 'urgent'
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
    _loadAnnouncements();
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
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
    final text = _messageController.text.trim();
    if (text.isEmpty) {
      AppNotification.showError(context, 'Pesan Kosong', subtitle: 'Ketik isi pengumuman terlebih dahulu.');
      return;
    }

    if (_selectedExamId == null) {
      AppNotification.showError(context, 'Pilih Ujian', subtitle: 'Tentukan jadwal ujian tujuan siaran.');
      return;
    }

    setState(() => _isSending = true);

    final error = await widget.controller.sendAnnouncement(
      _selectedExamId!,
      text,
      type: _announcementType,
    );

    if (!mounted) return;
    setState(() => _isSending = false);

    if (error == null) {
      _messageController.clear();
      AppNotification.showSuccess(
        context,
        'Pengumuman Terkirim!',
        subtitle: 'Pesan telah disiarkan ke seluruh layar ujian siswa.',
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
                final cur = exams.cast<Map<String, dynamic>?>().firstWhere(
                  (e) => e?['id'] == _selectedExamId,
                  orElse: () => null,
                );
                if (cur == null) return null;
                final t = cur['title']?.toString() ?? 'Ujian';
                final s = cur['subject']?.toString() ?? '';
                return s.isNotEmpty ? '$t • $s' : t;
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
                  setState(() => _selectedExamId = selected);
                  _loadAnnouncements();
                }
              },
            ),
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
                  onPressed: () {
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
              maxLines: 3,
              maxLength: 500,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => FocusScope.of(context).unfocus(),
              onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
              style: TextStyle(fontSize: 13, color: isDark ? Colors.white : const Color(0xFF0F172A)),
              decoration: InputDecoration(
                hintText: 'Ketik pesan pengumuman atau ralat soal di sini...',
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
                final bool canSubmit = !_isSending &&
                    _selectedExamId != null &&
                    _messageController.text.trim().isNotEmpty;

                return SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF59E0B),
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
                      _isSending ? 'Menyiarkan...' : 'Siarkan ke Layar Ujian Siswa',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                    ),
                    onPressed: canSubmit ? _handleSend : null,
                  ),
                );
              },
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
                              'Oleh: $proctor',
                              style: TextStyle(
                                fontSize: 10.5,
                                color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
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
