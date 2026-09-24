import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

/// A rich, actionable empty state with Shiei branding, glowing ambient rings,
/// contextual search query recovery, and quick action buttons.
class ShieiEmptyState extends StatelessWidget {
  final String title;
  final String message;
  final IconData? icon;
  final String? assetImage;
  final Color? accentColor;
  final String? searchQuery;
  final VoidCallback? onClearSearch;
  final String? primaryActionLabel;
  final VoidCallback? onPrimaryAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;
  final bool isDark;

  const ShieiEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon,
    this.assetImage,
    this.accentColor,
    this.searchQuery,
    this.onClearSearch,
    this.primaryActionLabel,
    this.onPrimaryAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
    required this.isDark,
  });

  /// Factory for empty search query results
  factory ShieiEmptyState.searchNotFound({
    required BuildContext context,
    required String searchQuery,
    required VoidCallback onClearSearch,
    required bool isDark,
    Color? accentColor,
    String? categoryLabel,
  }) {
    final label = categoryLabel ?? 'data';
    return ShieiEmptyState(
      title: 'Tidak Ada $label Ditemukan',
      message: 'Pencarian untuk "$searchQuery" tidak menemukan hasil yang cocok. Periksa kembali ejaan nama atau kata kunci Anda.',
      icon: Icons.search_off_rounded,
      accentColor: accentColor ?? const Color(0xFF8B5CF6),
      searchQuery: searchQuery,
      onClearSearch: onClearSearch,
      primaryActionLabel: 'Hapus Teks Pencarian',
      onPrimaryAction: onClearSearch,
      isDark: isDark,
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectiveColor = accentColor ?? const Color(0xFF8B5CF6);

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 80),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 1. Contextual Icon
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                    ),
                    child: Center(
                      child: Icon(
                        icon ?? Icons.inbox_outlined,
                        size: 32,
                        color: isDark ? AppTheme.textSecondary : const Color(0xFF94A3B8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // 2. Title Typography
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // 3. Informative Subtitle
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: Text(
                      message,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                        height: 1.45,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 4. Action Buttons
                  if (primaryActionLabel != null && onPrimaryAction != null) ...[
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          onPrimaryAction!();
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                          decoration: BoxDecoration(
                            color: effectiveColor,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: effectiveColor.withValues(alpha: 0.35),
                                blurRadius: 14,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                searchQuery != null ? Icons.backspace_outlined : Icons.add_rounded,
                                size: 16,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                primaryActionLabel!,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],

                  if (secondaryActionLabel != null && onSecondaryAction != null) ...[
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        onSecondaryAction!();
                      },
                      child: Text(
                        secondaryActionLabel!,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: effectiveColor,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
