import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

/// Modern confirmation dialog when user attempts to exit the application.
/// Prevents accidental app closure on system back gesture or button press.
class AppExitDialog extends StatelessWidget {
  const AppExitDialog({super.key});

  static bool _isShowing = false;
  static const MethodChannel _channel = MethodChannel('id.shiei/lockdown');

  /// Force reset the lock (e.g. on route change or screen init)
  static void resetLock() {
    _isShowing = false;
  }

  /// Displays the confirmation dialog. If confirmed, closes the application gracefully.
  static Future<bool> show(BuildContext context) async {
    if (_isShowing) return false;
    if (!context.mounted) return false;
    _isShowing = true;

    try {
      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => const AppExitDialog(),
      );

      // ALWAYS release the lock as soon as the dialog closes
      _isShowing = false;

      if (result == true) {
        try {
          await _channel.invokeMethod('exitApp');
        } catch (_) {}
        await SystemNavigator.pop();
        if (Platform.isAndroid || Platform.isIOS) {
          exit(0);
        }
        return true;
      }
      return false;
    } catch (_) {
      _isShowing = false;
      return false;
    } finally {
      _isShowing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      backgroundColor: isDark ? AppTheme.surfaceDark : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          width: 1.2,
        ),
      ),
      contentPadding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
      actionsPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Icon Container with Subtle Ambient Glow
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444).withValues(alpha: isDark ? 0.18 : 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFFEF4444).withValues(alpha: isDark ? 0.35 : 0.2),
                width: 1.2,
              ),
            ),
            child: const Center(
              child: Icon(
                Icons.power_settings_new_rounded,
                color: Color(0xFFEF4444),
                size: 28,
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Title
          Text(
            'Keluar dari Aplikasi?',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 8),

          // Description
          Text(
            'Apakah Anda yakin ingin menutup dan keluar dari aplikasi Shiei Exam?',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
            ),
          ),
          const SizedBox(height: 16),

          // Informative Reassurance Container
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.shield_outlined,
                  size: 16,
                  color: isDark ? AppTheme.primaryGlow : AppTheme.primaryShiei,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Sesi masuk akun Anda tetap tersimpan dengan aman.',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF64748B),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 42),
                  foregroundColor: isDark ? Colors.white70 : const Color(0xFF475569),
                  side: BorderSide(
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text(
                  'Batal',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(0, 42),
                  backgroundColor: const Color(0xFFEF4444),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text(
                  'Keluar',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
