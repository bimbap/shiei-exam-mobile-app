import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/auth/token_storage.dart';
import '../../../core/lockdown/volume_lock_service.dart';
import '../../../shared/theme/app_theme.dart';

/// Custom SHIEI bottom sheet for managing and selecting Google accounts
/// purely inside the app's themed UI (never triggers the white OS dialog).
class BrowserAccountPickerSheet {
  static const String addAccountSentinel = '__ADD_GOOGLE_ACCOUNT__';

  static Future<String?> pick(
    BuildContext context, {
    String? currentEmail,
  }) async {
    final savedList = await TokenStorage.getSavedBrowserEmails();
    final hiddenSet =
        (await TokenStorage.getHiddenDeviceGoogleEmails()).toSet();

    List<String> deviceList = const [];
    if (Platform.isAndroid) {
      final hasPerm = await VolumeLockService.hasGoogleAccountsPermission();
      if (hasPerm) {
        deviceList = await VolumeLockService.getDeviceGoogleAccounts() ?? const [];
      }
    }

    if (!context.mounted) return null;

    final savedSet = savedList.map((e) => e.toLowerCase()).toSet();
    final merged = <String>[];
    final seen = <String>{};

    for (final raw in savedList) {
      final email = raw.trim();
      final lower = email.toLowerCase();
      if (email.isNotEmpty && seen.add(lower)) {
        merged.add(email);
      }
    }
    for (final raw in deviceList) {
      final email = raw.trim();
      final lower = email.toLowerCase();
      if (email.isNotEmpty && !hiddenSet.contains(lower) && seen.add(lower)) {
        merged.add(email);
      }
    }

    final initialActive = currentEmail?.trim().toLowerCase();
    if (initialActive != null &&
        initialActive.isNotEmpty &&
        !hiddenSet.contains(initialActive) &&
        seen.add(initialActive)) {
      merged.insert(0, currentEmail!.trim());
    }

    return await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 600),
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        final isDark = AppTheme.isDark(sheetCtx);
        final sheetBg = isDark ? const Color(0xFF0F172A) : Colors.white;
        final sheetBorder =
            isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
        final itemBg =
            isDark ? AppTheme.surfaceDark : const Color(0xFFF8FAFC);
        final titleColor = isDark ? Colors.white : AppTheme.textPrimaryLight;
        final subColor =
            isDark ? AppTheme.textSecondary : AppTheme.textSecondaryLight;
        String? activeLower = initialActive;

        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            Future<void> removeEmail(String email) async {
              final lower = email.trim().toLowerCase();
              await TokenStorage.removeSavedBrowserEmail(lower);
              await TokenStorage.hideDeviceGoogleEmail(lower);
              if (activeLower != null && lower == activeLower) {
                await TokenStorage.clearBrowserLoginMeta();
                activeLower = null;
              }
              setSheetState(() {
                merged.removeWhere((item) => item.trim().toLowerCase() == lower);
              });
            }

            return Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              decoration: BoxDecoration(
                color: sheetBg,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border(
                  top: BorderSide(color: sheetBorder, width: 1.5),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF475569)
                              : const Color(0xFFCBD5E1),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: AppTheme.primaryShiei.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color:
                                  AppTheme.primaryShiei.withValues(alpha: 0.3),
                            ),
                          ),
                          child: const Icon(
                            Icons.account_circle_rounded,
                            color: AppTheme.primaryGlow,
                            size: 23,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Pilih Akun Google',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: titleColor,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Pilih akun cepat atau hapus akun yang tidak dipakai',
                                style: TextStyle(fontSize: 11.5, color: subColor),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (merged.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: itemBg,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: sheetBorder),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.no_accounts_rounded,
                              size: 32,
                              color: subColor,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Belum ada akun Google tersimpan di daftar.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: titleColor,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Tekan tombol di bawah untuk login ke akun Google baru.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 11.2, color: subColor),
                            ),
                          ],
                        ),
                      )
                    else
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: (MediaQuery.of(sheetCtx).size.height * 0.42)
                              .clamp(220.0, 380.0),
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: merged.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (itemCtx, idx) {
                            final email = merged[idx].trim();
                            final lower = email.toLowerCase();
                            final initial = email.isNotEmpty
                                ? email.substring(0, 1).toUpperCase()
                                : 'G';
                            final isActive =
                                activeLower != null && lower == activeLower;
                            final isSaved = savedSet.contains(lower);

                            return Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () => Navigator.pop(sheetCtx, email),
                                child: Container(
                                  padding: const EdgeInsets.fromLTRB(
                                    13,
                                    9,
                                    6,
                                    9,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isActive
                                        ? AppTheme.primaryShiei.withValues(
                                            alpha: isDark ? 0.18 : 0.08,
                                          )
                                        : itemBg,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: isActive
                                          ? AppTheme.primaryShiei
                                          : sheetBorder,
                                      width: isActive ? 1.5 : 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 38,
                                        height: 38,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          gradient: LinearGradient(
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                            colors: [
                                              AppTheme.primaryGlow.withValues(
                                                alpha: 0.28,
                                              ),
                                              AppTheme.primaryShiei.withValues(
                                                alpha: 0.14,
                                              ),
                                            ],
                                          ),
                                          border: Border.all(
                                            color: AppTheme.primaryShiei
                                                .withValues(alpha: 0.4),
                                          ),
                                        ),
                                        child: Center(
                                          child: Text(
                                            initial,
                                            style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w800,
                                              color: AppTheme.primaryGlow,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              email,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700,
                                                color: titleColor,
                                              ),
                                            ),
                                            const SizedBox(height: 1),
                                            Text(
                                              isActive
                                                  ? 'Akun terhubung saat ini'
                                                  : (isSaved
                                                      ? 'Tersimpan di SHIEI'
                                                      : 'Akun Google Perangkat'),
                                              style: TextStyle(
                                                fontSize: 10.8,
                                                fontWeight: isActive
                                                    ? FontWeight.w700
                                                    : FontWeight.w500,
                                                color: isActive
                                                    ? AppTheme.primaryGlow
                                                    : subColor,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (isActive)
                                        const Padding(
                                          padding: EdgeInsets.only(right: 2),
                                          child: Icon(
                                            Icons.check_circle_rounded,
                                            color: AppTheme.primaryGlow,
                                            size: 19,
                                          ),
                                        ),
                                      IconButton(
                                        tooltip: 'Hapus akun dari daftar',
                                        visualDensity: VisualDensity.compact,
                                        constraints: const BoxConstraints(
                                          minWidth: 34,
                                          minHeight: 34,
                                        ),
                                        icon: Icon(
                                          Icons.delete_outline_rounded,
                                          size: 18,
                                          color: AppTheme.dangerRed.withValues(
                                            alpha: 0.85,
                                          ),
                                        ),
                                        onPressed: () => removeEmail(email),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.pop(
                        sheetCtx,
                        BrowserAccountPickerSheet.addAccountSentinel,
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 42),
                        foregroundColor: AppTheme.primaryGlow,
                        side: BorderSide(
                          color: AppTheme.primaryShiei.withValues(alpha: 0.4),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.person_add_alt_1_rounded, size: 17),
                      label: const Text(
                        'Masuk dengan Akun Google Lain',
                        style: TextStyle(
                          fontSize: 12.2,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 42),
                        backgroundColor: isDark
                            ? const Color(0xFF334155)
                            : const Color(0xFFE2E8F0),
                        foregroundColor: titleColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => Navigator.pop(sheetCtx),
                      child: const Text(
                        'Batal',
                        style: TextStyle(fontWeight: FontWeight.bold),
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
}
