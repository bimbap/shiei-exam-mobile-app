import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/lockdown/volume_lock_service.dart';
import '../../../shared/theme/app_theme.dart';

/// Custom SHIEI bottom sheet for choosing a device Google account.
/// Automatically inherits AppTheme light/dark styling and matches the Riwayat
/// dialog transition. Falls back cleanly to Android system picker only when
/// GET_ACCOUNTS permission was denied or no device Google account was returned.
class BrowserAccountPickerSheet {
  static Future<String?> pick(
    BuildContext context, {
    String? currentEmail,
  }) async {
    if (!Platform.isAndroid) return null;

    final accounts = await VolumeLockService.getDeviceGoogleAccounts();
    if (!context.mounted) return null;

    // Permission denied -> graceful fallback to Android's system AccountManager picker.
    if (accounts == null) {
      return await VolumeLockService.pickDeviceGoogleAccount();
    }

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 600),
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        final isDark = AppTheme.isDark(sheetCtx);
        final sheetBg = isDark ? const Color(0xFF0F172A) : Colors.white;
        final sheetBorder = isDark
            ? const Color(0xFF334155)
            : const Color(0xFFE2E8F0);
        final itemBg = isDark
            ? AppTheme.surfaceDark
            : const Color(0xFFF8FAFC);
        final titleColor = isDark ? Colors.white : AppTheme.textPrimaryLight;
        final subColor = isDark
            ? AppTheme.textSecondary
            : AppTheme.textSecondaryLight;
        final activeLower = currentEmail?.trim().toLowerCase();

        return Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          decoration: BoxDecoration(
            color: sheetBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
                          color: AppTheme.primaryShiei.withValues(alpha: 0.3),
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
                            'Pilih akun perangkat untuk dihubungkan ke peramban ujian',
                            style: TextStyle(fontSize: 11.5, color: subColor),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (accounts.isEmpty)
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
                          'Belum ada akun Google terdeteksi di perangkat ini.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: titleColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Tambahkan atau pilih lewat sistem Android di bawah.',
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
                      itemCount: accounts.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (ctx, idx) {
                        final email = accounts[idx].trim();
                        final initial = email.isNotEmpty
                            ? email.substring(0, 1).toUpperCase()
                            : 'G';
                        final isActive =
                            activeLower != null &&
                            email.toLowerCase() == activeLower;

                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => Navigator.pop(sheetCtx, email),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 13,
                                vertical: 11,
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
                                        color: AppTheme.primaryShiei.withValues(
                                          alpha: 0.4,
                                        ),
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
                                              : 'Akun Google Perangkat',
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
                                  const SizedBox(width: 8),
                                  Icon(
                                    isActive
                                        ? Icons.check_circle_rounded
                                        : Icons.chevron_right_rounded,
                                    color: isActive
                                        ? AppTheme.primaryGlow
                                        : subColor,
                                    size: 20,
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
                  onPressed: () => Navigator.pop(sheetCtx, '__USE_OS_PICKER__'),
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
                    'Tambah atau Pilih Akun Lain',
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

    if (result == '__USE_OS_PICKER__') {
      return await VolumeLockService.pickDeviceGoogleAccount();
    }
    return result;
  }
}
