import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../shared/theme/app_theme.dart';

class AdjustTimeDialog extends StatefulWidget {
  final String studentName;
  final String? nisn;
  final String? examTitle;
  final int currentExtraMinutes;

  const AdjustTimeDialog({
    super.key,
    required this.studentName,
    this.nisn,
    this.examTitle,
    this.currentExtraMinutes = 0,
  });

  static Future<int?> show({
    required BuildContext context,
    required String studentName,
    String? nisn,
    String? examTitle,
    int currentExtraMinutes = 0,
  }) async {
    return showDialog<int>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AdjustTimeDialog(
        studentName: studentName,
        nisn: nisn,
        examTitle: examTitle,
        currentExtraMinutes: currentExtraMinutes,
      ),
    );
  }

  @override
  State<AdjustTimeDialog> createState() => _AdjustTimeDialogState();
}

class _AdjustTimeDialogState extends State<AdjustTimeDialog> {
  // 'add' for + minutes, 'reduce' for - minutes
  String _mode = 'add';
  int _selectedMinutes = 15;
  late final TextEditingController _customMinutesController;

  static const List<int> _presetOptions = [5, 10, 15, 30];

  @override
  void initState() {
    super.initState();
    _customMinutesController = TextEditingController(text: '$_selectedMinutes');
  }

  @override
  void dispose() {
    _customMinutesController.dispose();
    super.dispose();
  }

  void _selectPreset(int mins) {
    FocusScope.of(context).unfocus();
    setState(() {
      _selectedMinutes = mins;
      _customMinutesController.text = '$mins';
    });
  }

  void _onCustomChanged(String val) {
    final parsed = int.tryParse(val.trim());
    if (parsed != null && parsed >= 1) {
      final clamped = parsed.clamp(1, 180);
      setState(() {
        _selectedMinutes = clamped;
      });
    }
  }

  void _submit() {
    if (_selectedMinutes <= 0) return;
    final int delta = _mode == 'reduce' ? -_selectedMinutes : _selectedMinutes;
    Navigator.of(context).pop(delta);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final isAdd = _mode == 'add';

    final Color activeColor = isAdd ? const Color(0xFFEA580C) : const Color(0xFFEF4444);
    final Color activeLightBg = isAdd
        ? (isDark ? const Color(0xFF451A03) : const Color(0xFFFFF7ED))
        : (isDark ? const Color(0xFF4C0519) : const Color(0xFFFFF1F2));
    final Color activeBorder = isAdd
        ? (isDark ? const Color(0xFF7C2D12) : const Color(0xFFFED7AA))
        : (isDark ? const Color(0xFF881337) : const Color(0xFFFECDD3));

    return RepaintBoundary(
      child: Dialog(
        backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            width: 1.2,
          ),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: activeLightBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: activeBorder),
                    ),
                    child: Icon(
                      isAdd ? Icons.more_time_rounded : Icons.schedule_send_rounded,
                      color: activeColor,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sesuaikan Waktu Ujian',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.3,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.studentName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Mode Toggle (Tambah vs Potong)
              Container(
                height: 44,
                padding: const EdgeInsets.all(3.5),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          FocusScope.of(context).unfocus();
                          setState(() => _mode = 'add');
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          decoration: BoxDecoration(
                            color: isAdd
                                ? (isDark ? const Color(0xFFEA580C) : Colors.white)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(9),
                            boxShadow: isAdd
                                ? [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.08),
                                      blurRadius: 4,
                                      offset: const Offset(0, 1),
                                    ),
                                  ]
                                : null,
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.add_rounded,
                                size: 16,
                                color: isAdd
                                    ? (isDark ? Colors.white : const Color(0xFFEA580C))
                                    : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Tambah Waktu (+)',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isAdd ? FontWeight.w800 : FontWeight.w600,
                                  color: isAdd
                                      ? (isDark ? Colors.white : const Color(0xFFEA580C))
                                      : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          FocusScope.of(context).unfocus();
                          setState(() => _mode = 'reduce');
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          decoration: BoxDecoration(
                            color: !isAdd
                                ? (isDark ? const Color(0xFFEF4444) : Colors.white)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(9),
                            boxShadow: !isAdd
                                ? [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.08),
                                      blurRadius: 4,
                                      offset: const Offset(0, 1),
                                    ),
                                  ]
                                : null,
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.remove_rounded,
                                size: 16,
                                color: !isAdd
                                    ? (isDark ? Colors.white : const Color(0xFFEF4444))
                                    : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Potong Waktu (-)',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: !isAdd ? FontWeight.w800 : FontWeight.w600,
                                  color: !isAdd
                                      ? (isDark ? Colors.white : const Color(0xFFEF4444))
                                      : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Info Banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: activeLightBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: activeBorder),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      isAdd ? Icons.info_outline_rounded : Icons.warning_amber_rounded,
                      size: 16,
                      color: activeColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isAdd ? 'Perpanjangan Timer Mandiri' : 'Pengurangan Waktu / Penalti',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: activeColor,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            isAdd
                                ? 'Waktu tambahan langsung tersinkronisasi ke aplikasi siswa secara live tanpa mengubah durasi peserta lainnya.'
                                : 'Waktu pengerjaan siswa akan dipotong secara live. Jika sisa waktu habis (0 menit), sesi ujian akan otomatis timeout.',
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.35,
                              color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF475569),
                            ),
                          ),
                          if (widget.currentExtraMinutes != 0) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Total penyesuaian saat ini: ${widget.currentExtraMinutes > 0 ? '+${widget.currentExtraMinutes}' : '${widget.currentExtraMinutes}'} menit',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: activeColor,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Quick Presets Label
              Text(
                'Pilih Cepat Durasi (${isAdd ? 'Tambahan' : 'Potongan'})',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
                ),
              ),
              const SizedBox(height: 8),

              // Preset Buttons
              Row(
                children: _presetOptions.map((mins) {
                  final isSelected = _selectedMinutes == mins;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: InkWell(
                        onTap: () => _selectPreset(mins),
                        borderRadius: BorderRadius.circular(10),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? activeColor
                                : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC)),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected
                                  ? activeColor
                                  : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                              width: 1.2,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            isAdd ? '+$mins m' : '-$mins m',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: isSelected
                                  ? Colors.white
                                  : (isDark ? Colors.white70 : const Color(0xFF334155)),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),

              // Custom Minutes Input
              Text(
                'Atau Tentukan Menit Kustom (1 - 180 Menit)',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
                ),
              ),
              const SizedBox(height: 6),

              TextField(
                controller: _customMinutesController,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => FocusScope.of(context).unfocus(),
                onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(3),
                ],
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
                decoration: InputDecoration(
                  hintText: 'Misal 20',
                  hintStyle: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                  ),
                  filled: true,
                  fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                  prefixIcon: Padding(
                    padding: const EdgeInsets.only(left: 12, right: 8),
                    child: Icon(
                      Icons.timer_outlined,
                      size: 20,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                  ),
                  prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 44),
                  suffixIcon: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Align(
                      alignment: Alignment.centerRight,
                      widthFactor: 1.0,
                      child: Text(
                        'Menit',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                        ),
                      ),
                    ),
                  ),
                  suffixIconConstraints: const BoxConstraints(minHeight: 44),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                      width: 1.2,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                      width: 1.2,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: activeColor,
                      width: 1.8,
                    ),
                  ),
                ),
                onChanged: _onCustomChanged,
              ),
              const SizedBox(height: 20),

              // Action Buttons (Batal & Simpan)
              LayoutBuilder(
                builder: (context, constraints) {
                  final isCompact = constraints.maxWidth < 280;
                  final actionLabel = isCompact
                      ? (isAdd ? '+$_selectedMinutes mnt' : '-$_selectedMinutes mnt')
                      : (isAdd ? 'Tambahkan +$_selectedMinutes Menit' : 'Potong -$_selectedMinutes Menit');

                  return Row(
                    children: [
                      Expanded(
                        flex: isCompact ? 1 : 1,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            side: BorderSide(
                              color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                            ),
                          ),
                          onPressed: () => Navigator.of(context).pop(null),
                          child: Text(
                            'Batal',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white70 : const Color(0xFF475569),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: isCompact ? 1 : 2,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: activeColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: Icon(
                            isAdd ? Icons.add_rounded : Icons.remove_rounded,
                            size: 16,
                          ),
                          label: Text(
                            actionLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          onPressed: _selectedMinutes > 0 ? _submit : null,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
      ),
      ),
    );
  }
}
