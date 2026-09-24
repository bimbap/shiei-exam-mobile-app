import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import 'shiei_bottom_sheet.dart';
import 'shiei_checkbox.dart';

class ShieiSelectItem<T> {
  final T value;
  final String label;
  final String? subtitle;
  final IconData? icon;
  final Widget? leading;
  final String? badge;
  final Color? badgeColor;

  const ShieiSelectItem({
    required this.value,
    required this.label,
    this.subtitle,
    this.icon,
    this.leading,
    this.badge,
    this.badgeColor,
  });
}

/// A high-end, tactile bottom sheet selector with smooth animated transitions,
/// staggered item animations, tactile haptic feedback, and search capabilities.
class ShieiSelectSheet<T> extends StatefulWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? accentColor;
  final List<ShieiSelectItem<T>> items;
  final T? selectedValue;
  final bool showSearch;
  final String searchHint;

  const ShieiSelectSheet({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.accentColor,
    required this.items,
    this.selectedValue,
    this.showSearch = false,
    this.searchHint = 'Cari opsi...',
  });

  /// Safely dismisses the software keyboard only if it is currently visible,
  /// waiting for the dismissal animation to complete smoothly.
  /// If the keyboard is not open, it returns immediately with zero delay.
  static Future<void> dismissKeyboardIfNeeded(BuildContext context) async {
    final double insetsBottom = MediaQuery.maybeViewInsetsOf(context)?.bottom ?? 0.0;
    if (insetsBottom > 0.0) {
      FocusManager.instance.primaryFocus?.unfocus();
      FocusScope.of(context).unfocus();
      await Future.delayed(const Duration(milliseconds: 280));
    } else {
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }

  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    String? subtitle,
    IconData? icon,
    Color? accentColor,
    required List<ShieiSelectItem<T>> items,
    T? selectedValue,
    bool? showSearch,
    String searchHint = 'Cari...',
  }) async {
    // Dismiss keyboard with smooth animation only if it is currently visible; otherwise open instantly
    await dismissKeyboardIfNeeded(context);
    if (!context.mounted) return null;

    final effectiveShowSearch = showSearch ?? (items.length > 5);

    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 600),
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) => ShieiSelectSheet<T>(
        title: title,
        subtitle: subtitle,
        icon: icon,
        accentColor: accentColor,
        items: items,
        selectedValue: selectedValue,
        showSearch: effectiveShowSearch,
        searchHint: searchHint,
      ),
    );
  }

  @override
  State<ShieiSelectSheet<T>> createState() => _ShieiSelectSheetState<T>();
}

class _ShieiSelectSheetState<T> extends State<ShieiSelectSheet<T>> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _query = '';
  T? _pendingSelectedValue;

  @override
  void initState() {
    super.initState();
    _pendingSelectedValue = widget.selectedValue;
    _searchFocusNode.addListener(_handleSearchFocusChange);
  }

  void _handleSearchFocusChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _searchFocusNode.removeListener(_handleSearchFocusChange);
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _handleSelectItem(T value) {
    setState(() {
      _pendingSelectedValue = value;
    });

    HapticFeedback.selectionClick();

    // Micro-delay gives user tactile visual confirmation of selection before closing
    Future.delayed(const Duration(milliseconds: 140), () {
      if (mounted) {
        Navigator.pop(context, value);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final effectiveAccent = widget.accentColor ?? const Color(0xFFEA580C);

    final filteredItems = widget.items.where((item) {
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      final labelMatches = item.label.toLowerCase().contains(q);
      final subtitleMatches = item.subtitle?.toLowerCase().contains(q) ?? false;
      return labelMatches || subtitleMatches;
    }).toList();

    return ShieiBottomSheet(
      initialFraction: 0.62,
      maxFraction: 0.925,
      snapFractions: const [0.62, 0.925],
      headerBuilder: (isFullscreen) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (widget.icon != null) ...[
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: effectiveAccent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(widget.icon, color: effectiveAccent, size: 20),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16.5,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: effectiveAccent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${widget.items.length}',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: effectiveAccent,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (widget.subtitle != null) ...[
                        const SizedBox(height: 2.5),
                        Text(
                          widget.subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                            height: 1.2,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (widget.showSearch) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                textInputAction: TextInputAction.search,
                onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                onSubmitted: (_) => FocusScope.of(context).unfocus(),
                onChanged: (val) => setState(() => _query = val.trim()),
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
                decoration: InputDecoration(
                  hintText: widget.searchHint,
                  hintStyle: TextStyle(
                    fontSize: 12.5,
                    color: isDark ? AppTheme.textSecondary : const Color(0xFF94A3B8),
                  ),
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  prefixIconColor: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                  suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 16),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  filled: true,
                  fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: isDark ? const Color(0xFF334155).withValues(alpha: 0.6) : const Color(0xFFE2E8F0),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: effectiveAccent,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      bodyBuilder: (scrollController) {
        if (filteredItems.isEmpty) {
          return Center(
            child: SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.symmetric(vertical: 38, horizontal: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                    ),
                    child: Icon(
                      Icons.search_off_rounded,
                      size: 28,
                      color: isDark ? const Color(0xFF475569) : const Color(0xFF94A3B8),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Tidak ada opsi yang cocok',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : const Color(0xFF334155),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Coba gunakan kata kunci pencarian yang berbeda',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.separated(
          controller: scrollController,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          itemCount: filteredItems.length,
          separatorBuilder: (_, __) => const SizedBox(height: 6),
          itemBuilder: (ctx, index) {
            final item = filteredItems[index];
            final isSelected = item.value == _pendingSelectedValue;

            // Staggered slide and fade animation on mount
            final animDelay = Duration(milliseconds: (index.clamp(0, 8) * 30));

            return TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0.0, end: 1.0),
              duration: Duration(milliseconds: 220 + animDelay.inMilliseconds),
              curve: Curves.easeOutCubic,
              builder: (context, animValue, child) {
                return Opacity(
                  opacity: animValue,
                  child: Transform.translate(
                    offset: Offset(0, 10 * (1.0 - animValue)),
                    child: child,
                  ),
                );
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOut,
                decoration: BoxDecoration(
                  color: isSelected
                    ? effectiveAccent.withValues(alpha: isDark ? 0.16 : 0.10)
                    : (isDark ? const Color(0xFF1E293B).withValues(alpha: 0.5) : const Color(0xFFF8FAFC)),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected
                      ? effectiveAccent.withValues(alpha: isDark ? 0.8 : 0.6)
                      : (isDark ? const Color(0xFF334155).withValues(alpha: 0.5) : const Color(0xFFE2E8F0)),
                    width: isSelected ? 1.5 : 1.0,
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    splashColor: effectiveAccent.withValues(alpha: 0.15),
                    highlightColor: effectiveAccent.withValues(alpha: 0.08),
                    onTap: () => _handleSelectItem(item.value),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(
                        children: [
                          if (item.leading != null) ...[
                            item.leading!,
                            const SizedBox(width: 12),
                          ] else if (item.icon != null) ...[
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 140),
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: isSelected
                                  ? effectiveAccent.withValues(alpha: 0.18)
                                  : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                item.icon,
                                size: 19,
                                color: isSelected
                                  ? effectiveAccent
                                  : (isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        item.label,
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                          color: isSelected
                                            ? effectiveAccent
                                            : (isDark ? Colors.white : const Color(0xFF0F172A)),
                                        ),
                                      ),
                                    ),
                                    if (item.badge != null) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6.5, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: (item.badgeColor ?? const Color(0xFF10B981)).withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          item.badge!,
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: item.badgeColor ?? const Color(0xFF10B981),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                if (item.subtitle != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    item.subtitle!,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          AnimatedScale(
                            scale: isSelected ? 1.0 : 0.85,
                            duration: const Duration(milliseconds: 140),
                            curve: Curves.easeOutBack,
                            child: AnimatedOpacity(
                              opacity: isSelected ? 1.0 : 0.4,
                              duration: const Duration(milliseconds: 140),
                              child: Icon(
                                isSelected ? Icons.check_circle_rounded : Icons.circle_outlined,
                                size: 20,
                                color: isSelected
                                  ? effectiveAccent
                                  : (isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Multi-select sheet supporting selecting multiple items with smooth checkboxes,
/// select all toggle, and dynamic action button.
class ShieiMultiSelectSheet<T> extends StatefulWidget {
  final String title;
  final String? subtitle;
  final List<ShieiSelectItem<T>> items;
  final List<T> initialSelectedValues;
  final bool showSearch;
  final String searchHint;

  const ShieiMultiSelectSheet({
    super.key,
    required this.title,
    this.subtitle,
    required this.items,
    this.initialSelectedValues = const [],
    this.showSearch = false,
    this.searchHint = 'Cari opsi...',
  });

  static Future<List<T>?> show<T>({
    required BuildContext context,
    required String title,
    String? subtitle,
    required List<ShieiSelectItem<T>> items,
    List<T> initialSelectedValues = const [],
    bool? showSearch,
    String searchHint = 'Cari...',
  }) async {
    // Dismiss keyboard with smooth animation only if it is currently visible; otherwise open instantly
    await ShieiSelectSheet.dismissKeyboardIfNeeded(context);
    if (!context.mounted) return null;

    final effectiveShowSearch = showSearch ?? (items.length > 5);

    return showModalBottomSheet<List<T>>(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 600),
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) => ShieiMultiSelectSheet<T>(
        title: title,
        subtitle: subtitle,
        items: items,
        initialSelectedValues: initialSelectedValues,
        showSearch: effectiveShowSearch,
        searchHint: searchHint,
      ),
    );
  }

  @override
  State<ShieiMultiSelectSheet<T>> createState() => _ShieiMultiSelectSheetState<T>();
}

class _ShieiMultiSelectSheetState<T> extends State<ShieiMultiSelectSheet<T>> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  late Set<T> _selectedValues;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _selectedValues = Set.from(widget.initialSelectedValues);
    _searchFocusNode.addListener(_handleSearchFocusChange);
  }

  void _handleSearchFocusChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _searchFocusNode.removeListener(_handleSearchFocusChange);
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _toggleItem(T value) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedValues.contains(value)) {
        _selectedValues.remove(value);
      } else {
        _selectedValues.add(value);
      }
    });
  }

  void _toggleSelectAll() {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedValues.length == widget.items.length) {
        _selectedValues.clear();
      } else {
        _selectedValues = widget.items.map((e) => e.value).toSet();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);

    final filteredItems = widget.items.where((item) {
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      final labelMatches = item.label.toLowerCase().contains(q);
      final subtitleMatches = item.subtitle?.toLowerCase().contains(q) ?? false;
      return labelMatches || subtitleMatches;
    }).toList();

    final isAllSelected = _selectedValues.length == widget.items.length && widget.items.isNotEmpty;

    return ShieiBottomSheet(
      initialFraction: 0.68,
      maxFraction: 0.925,
      snapFractions: const [0.68, 0.925],
      headerBuilder: (isFullscreen) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 16, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                          letterSpacing: -0.2,
                        ),
                      ),
                      if (widget.subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          widget.subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _toggleSelectAll,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    isAllSelected ? 'Batal Semua' : 'Pilih Semua',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFEA580C),
                    ),
                  ),
                ),
              ],
            ),
            if (widget.showSearch) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                textInputAction: TextInputAction.search,
                onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                onSubmitted: (_) => FocusScope.of(context).unfocus(),
                onChanged: (val) => setState(() => _query = val.trim()),
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
                decoration: InputDecoration(
                  hintText: widget.searchHint,
                  hintStyle: TextStyle(
                    fontSize: 12.5,
                    color: isDark ? AppTheme.textSecondary : const Color(0xFF94A3B8),
                  ),
                  prefixIcon: const Icon(Icons.search_rounded, size: 18),
                  prefixIconColor: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                  suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 16),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  filled: true,
                  fillColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: isDark ? const Color(0xFF334155).withValues(alpha: 0.6) : const Color(0xFFE2E8F0),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                      color: Color(0xFFEA580C),
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      footerBuilder: (isFullscreen) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: () {
              HapticFeedback.mediumImpact();
              Navigator.pop(context, _selectedValues.toList());
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEA580C),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Terapkan Pilihan',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                if (_selectedValues.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${_selectedValues.length}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      bodyBuilder: (scrollController) => ListView.separated(
        controller: scrollController,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        itemCount: filteredItems.length,
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (ctx, index) {
          final item = filteredItems[index];
          final isSelected = _selectedValues.contains(item.value);

          return Material(
            color: isSelected
              ? const Color(0xFFEA580C).withValues(alpha: isDark ? 0.16 : 0.10)
              : (isDark ? const Color(0xFF1E293B).withValues(alpha: 0.5) : const Color(0xFFF8FAFC)),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              splashColor: const Color(0xFFEA580C).withValues(alpha: 0.15),
              highlightColor: const Color(0xFFEA580C).withValues(alpha: 0.08),
              onTap: () => _toggleItem(item.value),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected
                      ? const Color(0xFFEA580C).withValues(alpha: isDark ? 0.8 : 0.6)
                      : (isDark ? const Color(0xFF334155).withValues(alpha: 0.5) : const Color(0xFFE2E8F0)),
                    width: isSelected ? 1.5 : 1.0,
                  ),
                ),
                child: Row(
                  children: [
                    ShieiCheckbox(
                      value: isSelected,
                      onChanged: (_) => _toggleItem(item.value),
                      activeColor: const Color(0xFFEA580C),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.label,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                              color: isSelected
                                ? const Color(0xFFEA580C)
                                : (isDark ? Colors.white : const Color(0xFF0F172A)),
                            ),
                          ),
                          if (item.subtitle != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              item.subtitle!,
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Custom form field trigger with smooth animated touch feedback, active scale,
/// leading icon container, and clean chevron rotation indicator.
class ShieiSelectorField<T> extends StatefulWidget {
  final String label;
  final String? placeholder;
  final String? valueText;
  final IconData? prefixIcon;
  final Color? prefixIconColor;
  final VoidCallback? onTap;
  final bool isDark;
  final bool clearable;
  final VoidCallback? onClear;
  final bool isLoading;

  const ShieiSelectorField({
    super.key,
    this.label = '',
    this.placeholder,
    this.valueText,
    this.prefixIcon,
    this.prefixIconColor,
    this.onTap,
    required this.isDark,
    this.clearable = false,
    this.onClear,
    this.isLoading = false,
  });

  @override
  State<ShieiSelectorField<T>> createState() => _ShieiSelectorFieldState<T>();
}

class _ShieiSelectorFieldState<T> extends State<ShieiSelectorField<T>> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final hasValue = widget.valueText != null && widget.valueText!.isNotEmpty;
    final isInteractive = widget.onTap != null && !widget.isLoading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label.isNotEmpty) ...[
          if (widget.label.contains('*'))
            RichText(
              text: TextSpan(
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: widget.isDark ? AppTheme.textSecondary : const Color(0xFF475569),
                ),
                children: [
                  TextSpan(text: widget.label.replaceAll('*', '').trimRight()),
                  const TextSpan(
                    text: ' *',
                    style: TextStyle(
                      color: Color(0xFFEA580C),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            )
          else
            Text(
              widget.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: widget.isDark ? AppTheme.textSecondary : const Color(0xFF475569),
              ),
            ),
          const SizedBox(height: 6),
        ],

        // Animated Touch Trigger
        GestureDetector(
          onTapDown: isInteractive ? (_) => setState(() => _isPressed = true) : null,
          onTapUp: isInteractive ? (_) => setState(() => _isPressed = false) : null,
          onTapCancel: isInteractive ? () => setState(() => _isPressed = false) : null,
          child: AnimatedScale(
            scale: _isPressed ? 0.985 : 1.0,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                onTap: isInteractive
                  ? () async {
                      await ShieiSelectSheet.dismissKeyboardIfNeeded(context);
                      HapticFeedback.lightImpact();
                      if (context.mounted) {
                        widget.onTap!();
                      }
                    }
                  : null,
                borderRadius: BorderRadius.circular(14),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: widget.isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: hasValue
                        ? (widget.isDark ? const Color(0xFF3B82F6).withValues(alpha: 0.3) : const Color(0xFFCBD5E1))
                        : (widget.isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                      width: 1.0,
                    ),
                    boxShadow: _isPressed
                      ? []
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: widget.isDark ? 0.15 : 0.03),
                            blurRadius: 4,
                            offset: const Offset(0, 1.5),
                          ),
                        ],
                  ),
                  child: Row(
                    children: [
                      if (widget.prefixIcon != null) ...[
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: (widget.prefixIconColor ?? const Color(0xFFEA580C)).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            widget.prefixIcon,
                            size: 17,
                            color: widget.prefixIconColor ?? const Color(0xFFEA580C),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: Text(
                          hasValue ? widget.valueText! : (widget.placeholder ?? 'Pilih opsi...'),
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: hasValue ? FontWeight.w600 : FontWeight.normal,
                            color: hasValue
                              ? (widget.isDark ? Colors.white : const Color(0xFF0F172A))
                              : (widget.isDark ? AppTheme.textSecondary : const Color(0xFF94A3B8)),
                          ),
                        ),
                      ),
                      if (widget.isLoading) ...[
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFEA580C)),
                          ),
                        ),
                      ] else if (widget.clearable && hasValue && widget.onClear != null) ...[
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            widget.onClear!();
                          },
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: widget.isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                            ),
                            child: Icon(
                              Icons.close_rounded,
                              size: 14,
                              color: widget.isDark ? Colors.white : const Color(0xFF64748B),
                            ),
                          ),
                        ),
                      ] else ...[
                        AnimatedRotation(
                          turns: _isPressed ? 0.05 : 0.0,
                          duration: const Duration(milliseconds: 140),
                          child: Icon(
                            widget.onTap == null ? Icons.lock_outline_rounded : Icons.keyboard_arrow_down_rounded,
                            size: 20,
                            color: widget.isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
