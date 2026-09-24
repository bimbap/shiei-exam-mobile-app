import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';

enum _DatePickerView { day, month, year }

/// Custom date picker for Project SHIEI.
/// Supports separate Month and Year pickers so users can tap Month to select Month,
/// or tap Year to select Year, with smooth animations and Indonesian localization.
class ShieiDatePicker extends StatefulWidget {
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final String title;
  final String cancelText;
  final String confirmText;

  const ShieiDatePicker({
    super.key,
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    this.title = 'PILIH TANGGAL UJIAN',
    this.cancelText = 'Batal',
    this.confirmText = 'Pilih',
  });

  /// Opens the ShieiDatePicker modal dialog.
  static Future<DateTime?> show({
    required BuildContext context,
    required DateTime initialDate,
    DateTime? firstDate,
    DateTime? lastDate,
    String title = 'PILIH TANGGAL UJIAN',
    String cancelText = 'Batal',
    String confirmText = 'Pilih',
  }) {
    final effectiveFirstDate = firstDate ?? DateTime(2020);
    final effectiveLastDate = lastDate ?? DateTime(2040);
    final clampedInitial = initialDate.isBefore(effectiveFirstDate)
        ? effectiveFirstDate
        : (initialDate.isAfter(effectiveLastDate) ? effectiveLastDate : initialDate);

    return showDialog<DateTime>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => ShieiDatePicker(
        initialDate: clampedInitial,
        firstDate: effectiveFirstDate,
        lastDate: effectiveLastDate,
        title: title,
        cancelText: cancelText,
        confirmText: confirmText,
      ),
    );
  }

  @override
  State<ShieiDatePicker> createState() => _ShieiDatePickerState();
}

class _ShieiDatePickerState extends State<ShieiDatePicker> {
  late DateTime _selectedDate;
  late DateTime _displayedDate;
  _DatePickerView _viewMode = _DatePickerView.day;
  ScrollController? _yearScrollController;

  static const List<String> _monthNames = [
    'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
    'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
  ];

  static const List<String> _monthShortNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
    'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'
  ];

  static const List<String> _weekDays = [
    'Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'
  ];

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime(
      widget.initialDate.year,
      widget.initialDate.month,
      widget.initialDate.day,
    );
    _displayedDate = DateTime(_selectedDate.year, _selectedDate.month, 1);
  }

  @override
  void dispose() {
    _yearScrollController?.dispose();
    super.dispose();
  }

  void _scrollToCurrentYear() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_yearScrollController != null && _yearScrollController!.hasClients) {
        final totalYears = widget.lastDate.year - widget.firstDate.year + 1;
        final selectedIndex = _displayedDate.year - widget.firstDate.year;
        if (selectedIndex >= 0 && selectedIndex < totalYears) {
          final row = selectedIndex ~/ 3;
          final targetOffset = (row * 50.0).clamp(0.0, _yearScrollController!.position.maxScrollExtent);
          _yearScrollController!.animateTo(
            targetOffset,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
          );
        }
      }
    });
  }

  void _prevMonth() {
    final prev = DateTime(_displayedDate.year, _displayedDate.month - 1, 1);
    if (!prev.isBefore(DateTime(widget.firstDate.year, widget.firstDate.month, 1))) {
      HapticFeedback.selectionClick();
      setState(() => _displayedDate = prev);
    }
  }

  void _nextMonth() {
    final next = DateTime(_displayedDate.year, _displayedDate.month + 1, 1);
    if (!next.isAfter(DateTime(widget.lastDate.year, widget.lastDate.month, 1))) {
      HapticFeedback.selectionClick();
      setState(() => _displayedDate = next);
    }
  }

  void _selectDay(DateTime day) {
    if (day.isBefore(widget.firstDate) || day.isAfter(widget.lastDate)) return;
    HapticFeedback.selectionClick();
    setState(() {
      _selectedDate = day;
      _displayedDate = DateTime(day.year, day.month, 1);
    });
  }

  void _selectMonth(int month) {
    HapticFeedback.selectionClick();
    final year = _displayedDate.year;
    final maxDays = DateTime(year, month + 1, 0).day;
    final day = _selectedDate.day.clamp(1, maxDays);
    final newDate = DateTime(year, month, day);

    setState(() {
      _displayedDate = DateTime(year, month, 1);
      _selectedDate = newDate;
      _viewMode = _DatePickerView.day;
    });
  }

  void _selectYear(int year) {
    HapticFeedback.selectionClick();
    final month = _displayedDate.month;
    final maxDays = DateTime(year, month + 1, 0).day;
    final day = _selectedDate.day.clamp(1, maxDays);
    final newDate = DateTime(year, month, day);

    setState(() {
      _displayedDate = DateTime(year, month, 1);
      _selectedDate = newDate;
      _viewMode = _DatePickerView.day;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    const orangePrimary = Color(0xFFEA580C);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      elevation: 0,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 340),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Header with Selected Date Display
              _buildHeader(isDark, orangePrimary),

              // 2. Navigation Control Row (Bulan Chip, Tahun Chip, < > arrows)
              _buildNavigationRow(isDark, orangePrimary),

              const Divider(height: 1, thickness: 1, color: Color(0x1F94A3B8)),

              // 3. Body: Animated Switcher between Day Calendar, Month Grid, and Year Grid
              SizedBox(
                height: 258,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _buildCurrentView(isDark, orangePrimary),
                ),
              ),

              const Divider(height: 1, thickness: 1, color: Color(0x1F94A3B8)),

              // 4. Action Buttons (Batal & Pilih)
              _buildActionFooter(isDark, orangePrimary),
            ],
          ),
        ),
      ),
    );
  }

  // --- 1. HEADER ---
  Widget _buildHeader(bool isDark, Color accentColor) {
    String formattedDayName = '';
    String formattedDate = '';
    try {
      formattedDayName = DateFormat('EEEE', 'id_ID').format(_selectedDate);
      formattedDate = DateFormat('d MMMM yyyy', 'id_ID').format(_selectedDate);
    } catch (_) {
      formattedDayName = 'Tanggal';
      formattedDate = '${_selectedDate.day} ${_monthNames[_selectedDate.month - 1]} ${_selectedDate.year}';
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141E2D) : const Color(0xFFF8FAFC),
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF27354A) : const Color(0xFFE2E8F0),
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.event_note_rounded, size: 14, color: accentColor),
              const SizedBox(width: 6),
              Text(
                widget.title.toUpperCase(),
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$formattedDayName, ',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: accentColor,
                ),
              ),
              Expanded(
                child: Text(
                  formattedDate,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- 2. NAVIGATION ROW (Pemisah Bulan & Tahun yang Mandiri) ---
  Widget _buildNavigationRow(bool isDark, Color accentColor) {
    final monthName = _monthNames[_displayedDate.month - 1];
    final yearStr = _displayedDate.year.toString();

    final isMonthActive = _viewMode == _DatePickerView.month;
    final isYearActive = _viewMode == _DatePickerView.year;

    final canGoPrev = _viewMode == _DatePickerView.day &&
        !DateTime(_displayedDate.year, _displayedDate.month - 1, 1)
            .isBefore(DateTime(widget.firstDate.year, widget.firstDate.month, 1));
    final canGoNext = _viewMode == _DatePickerView.day &&
        !DateTime(_displayedDate.year, _displayedDate.month + 1, 1)
            .isAfter(DateTime(widget.lastDate.year, widget.lastDate.month, 1));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          // 1. Selector Khusus Bulan
          InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() {
                _viewMode = isMonthActive ? _DatePickerView.day : _DatePickerView.month;
              });
            },
            borderRadius: BorderRadius.circular(10),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isMonthActive
                    ? accentColor.withValues(alpha: 0.16)
                    : (isDark ? const Color(0xFF27354A) : const Color(0xFFF1F5F9)),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isMonthActive
                      ? accentColor
                      : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                  width: isMonthActive ? 1.4 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    monthName,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isMonthActive ? FontWeight.bold : FontWeight.w600,
                      color: isMonthActive
                          ? accentColor
                          : (isDark ? Colors.white : const Color(0xFF0F172A)),
                    ),
                  ),
                  const SizedBox(width: 3),
                  Icon(
                    isMonthActive ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded,
                    size: 18,
                    color: isMonthActive ? accentColor : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),

          // 2. Selector Khusus Tahun
          InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() {
                _viewMode = isYearActive ? _DatePickerView.day : _DatePickerView.year;
              });
              if (_viewMode == _DatePickerView.year) {
                _scrollToCurrentYear();
              }
            },
            borderRadius: BorderRadius.circular(10),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isYearActive
                    ? accentColor.withValues(alpha: 0.16)
                    : (isDark ? const Color(0xFF27354A) : const Color(0xFFF1F5F9)),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isYearActive
                      ? accentColor
                      : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                  width: isYearActive ? 1.4 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    yearStr,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isYearActive ? FontWeight.bold : FontWeight.w600,
                      color: isYearActive
                          ? accentColor
                          : (isDark ? Colors.white : const Color(0xFF0F172A)),
                    ),
                  ),
                  const SizedBox(width: 3),
                  Icon(
                    isYearActive ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded,
                    size: 18,
                    color: isYearActive ? accentColor : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
          ),

          const Spacer(),

          // 3. Tombol Navigasi Cepat Bulan (< >)
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded, size: 22),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            color: canGoPrev
                ? (isDark ? Colors.white70 : const Color(0xFF475569))
                : (isDark ? Colors.white24 : const Color(0xFFCBD5E1)),
            onPressed: canGoPrev ? _prevMonth : null,
            tooltip: 'Bulan Sebelumnya',
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded, size: 22),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            color: canGoNext
                ? (isDark ? Colors.white70 : const Color(0xFF475569))
                : (isDark ? Colors.white24 : const Color(0xFFCBD5E1)),
            onPressed: canGoNext ? _nextMonth : null,
            tooltip: 'Bulan Berikutnya',
          ),
        ],
      ),
    );
  }

  // --- 3. MAIN BODY SWITCHER ---
  Widget _buildCurrentView(bool isDark, Color accentColor) {
    switch (_viewMode) {
      case _DatePickerView.month:
        return _buildMonthGridView(isDark, accentColor);
      case _DatePickerView.year:
        return _buildYearGridView(isDark, accentColor);
      case _DatePickerView.day:
        return _buildDayCalendarView(isDark, accentColor);
    }
  }

  // --- VIEW A: DAY CALENDAR GRID ---
  Widget _buildDayCalendarView(bool isDark, Color accentColor) {
    final year = _displayedDate.year;
    final month = _displayedDate.month;

    final firstDay = DateTime(year, month, 1);
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final prevMonthDays = DateTime(year, month, 0).day;

    // Weekday: Monday is 1, Sunday is 7. Prefix spaces for Monday-start column.
    final leadingSpaces = firstDay.weekday - 1;
    final totalCells = leadingSpaces + daysInMonth;
    final trailingSpaces = (7 - (totalCells % 7)) % 7;
    final totalGridItems = totalCells + trailingSpaces;

    final now = DateTime.now();
    final isTodayInThisMonth = now.year == year && now.month == month;

    return Padding(
      key: const ValueKey('day_view'),
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
      child: Column(
        children: [
          // Weekday header row (Sen, Sel, Rab, Kam, Jum, Sab, Min)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: _weekDays.map((dayName) {
              final isWeekend = dayName == 'Sab' || dayName == 'Min';
              return Expanded(
                child: Center(
                  child: Text(
                    dayName,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isWeekend
                          ? (isDark ? const Color(0xFFF87171) : const Color(0xFFEF4444))
                          : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 6),

          // Days Grid (6 rows max x 7 columns)
          Expanded(
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
                childAspectRatio: 1.15,
              ),
              itemCount: totalGridItems,
              itemBuilder: (ctx, index) {
                if (index < leadingSpaces) {
                  // Prev month trailing day
                  final dayNum = prevMonthDays - leadingSpaces + 1 + index;
                  final prevDate = DateTime(year, month - 1, dayNum);
                  return _buildOffMonthCell(dayNum, prevDate, isDark);
                } else if (index < totalCells) {
                  // Current month day
                  final dayNum = index - leadingSpaces + 1;
                  final dayDate = DateTime(year, month, dayNum);
                  final isSelected = _selectedDate.year == year &&
                      _selectedDate.month == month &&
                      _selectedDate.day == dayNum;
                  final isToday = isTodayInThisMonth && now.day == dayNum;
                  final isDisabled = dayDate.isBefore(widget.firstDate) || dayDate.isAfter(widget.lastDate);

                  return _buildDayCell(
                    dayNum: dayNum,
                    dayDate: dayDate,
                    isSelected: isSelected,
                    isToday: isToday,
                    isDisabled: isDisabled,
                    isDark: isDark,
                    accentColor: accentColor,
                  );
                } else {
                  // Next month leading day
                  final dayNum = index - totalCells + 1;
                  final nextDate = DateTime(year, month + 1, dayNum);
                  return _buildOffMonthCell(dayNum, nextDate, isDark);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayCell({
    required int dayNum,
    required DateTime dayDate,
    required bool isSelected,
    required bool isToday,
    required bool isDisabled,
    required bool isDark,
    required Color accentColor,
  }) {
    Color textColor;
    if (isSelected) {
      textColor = Colors.white;
    } else if (isDisabled) {
      textColor = isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1);
    } else if (isToday) {
      textColor = accentColor;
    } else {
      textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    }

    return InkWell(
      onTap: isDisabled ? null : () => _selectDay(dayDate),
      borderRadius: BorderRadius.circular(20),
      child: Center(
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isSelected ? accentColor : Colors.transparent,
            border: isToday && !isSelected
                ? Border.all(color: accentColor, width: 1.5)
                : null,
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: accentColor.withValues(alpha: 0.35),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              dayNum.toString(),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isSelected || isToday ? FontWeight.bold : FontWeight.w500,
                color: textColor,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOffMonthCell(int dayNum, DateTime targetDate, bool isDark) {
    final isDisabled = targetDate.isBefore(widget.firstDate) || targetDate.isAfter(widget.lastDate);

    return InkWell(
      onTap: isDisabled ? null : () => _selectDay(targetDate),
      borderRadius: BorderRadius.circular(20),
      child: Center(
        child: Text(
          dayNum.toString(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.normal,
            color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
          ),
        ),
      ),
    );
  }

  // --- VIEW B: MONTH PICKER GRID (12 BULAN LENGKAP) ---
  Widget _buildMonthGridView(bool isDark, Color accentColor) {
    return Padding(
      key: const ValueKey('month_view'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_view_month_rounded, size: 14, color: accentColor),
              const SizedBox(width: 6),
              Text(
                'Pilih Bulan (${_displayedDate.year})',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 2.1,
              ),
              itemCount: 12,
              itemBuilder: (ctx, index) {
                final monthNumber = index + 1;
                final isSelected = _displayedDate.month == monthNumber;
                final shortName = _monthShortNames[index];
                final fullName = _monthNames[index];

                return InkWell(
                  onTap: () => _selectMonth(monthNumber),
                  borderRadius: BorderRadius.circular(10),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? accentColor
                          : (isDark ? const Color(0xFF27354A) : const Color(0xFFF1F5F9)),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? accentColor
                            : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                        width: isSelected ? 1.5 : 1,
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
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            shortName,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: isSelected
                                  ? Colors.white
                                  : (isDark ? Colors.white : const Color(0xFF0F172A)),
                            ),
                          ),
                          Text(
                            fullName,
                            style: TextStyle(
                              fontSize: 9.5,
                              color: isSelected
                                  ? Colors.white.withValues(alpha: 0.85)
                                  : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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
    );
  }

  // --- VIEW C: YEAR PICKER GRID (RENTANG TAHUN DENGAN SCROLL) ---
  Widget _buildYearGridView(bool isDark, Color accentColor) {
    _yearScrollController ??= ScrollController();
    final startYear = widget.firstDate.year;
    final totalYears = widget.lastDate.year - startYear + 1;

    return Padding(
      key: const ValueKey('year_view'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.date_range_rounded, size: 14, color: accentColor),
              const SizedBox(width: 6),
              Text(
                'Pilih Tahun',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: GridView.builder(
              controller: _yearScrollController,
              physics: const BouncingScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 1.8,
              ),
              itemCount: totalYears,
              itemBuilder: (ctx, index) {
                final year = startYear + index;
                final isSelected = _displayedDate.year == year;

                return InkWell(
                  onTap: () => _selectYear(year),
                  borderRadius: BorderRadius.circular(10),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? accentColor
                          : (isDark ? const Color(0xFF27354A) : const Color(0xFFF1F5F9)),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? accentColor
                            : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                        width: isSelected ? 1.5 : 1,
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
                    child: Center(
                      child: Text(
                        year.toString(),
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                          color: isSelected
                              ? Colors.white
                              : (isDark ? Colors.white : const Color(0xFF0F172A)),
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
    );
  }

  // --- 4. ACTION FOOTER (Batal & Pilih) ---
  Widget _buildActionFooter(bool isDark, Color accentColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.of(context).pop(null),
            child: Text(
              widget.cancelText,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: accentColor,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.of(context).pop(_selectedDate);
            },
            child: Text(
              widget.confirmText,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
