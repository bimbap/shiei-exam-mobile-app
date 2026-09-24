import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/api/api_client.dart';
import '../../core/api/endpoints.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/app_notification.dart';

class ChangePasswordDialog extends StatefulWidget {
  const ChangePasswordDialog({super.key});

  /// Shows the Change Password Dialog with smooth iOS-style fade-in-scale transition.
  static Future<bool?> show(BuildContext context) {
    return showGeneralDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Ubah Kata Sandi',
      barrierColor: Colors.black.withValues(alpha: 0.6),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (ctx, anim1, anim2) => const ChangePasswordDialog(),
      transitionBuilder: (ctx, anim1, anim2, child) {
        final curved = CurvedAnimation(
          parent: anim1,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;
  String? _errorMessage;

  // Live verification state for current password (matching Web Panel behavior)
  bool? _isCurrentPassValid; // null = idle/unverified, true = matches, false = incorrect
  bool _isVerifyingPass = false;
  Timer? _verifyDebounceTimer;

  @override
  void initState() {
    super.initState();
    _currentPasswordController.addListener(_onCurrentPasswordChanged);
    _newPasswordController.addListener(_onFieldChanged);
    _confirmPasswordController.addListener(_onFieldChanged);
  }

  void _onCurrentPasswordChanged() {
    final text = _currentPasswordController.text.trim();
    _verifyDebounceTimer?.cancel();

    if (text.isEmpty) {
      if (mounted) {
        setState(() {
          _isCurrentPassValid = null;
          _isVerifyingPass = false;
          _errorMessage = null;
        });
      }
      return;
    }

    // Reset status when user starts typing again
    if (mounted) {
      setState(() {
        _isCurrentPassValid = null;
        _errorMessage = null;
      });
    }

    // 450ms debounce before hitting backend /user/verify-password
    _verifyDebounceTimer = Timer(const Duration(milliseconds: 450), () async {
      if (!mounted) return;
      setState(() => _isVerifyingPass = true);

      try {
        final res = await ApiClient().post(
          ApiEndpoints.verifyPassword,
          data: {'password': text},
        );

        if (!mounted) return;
        final isValid = res.data != null && (res.data['valid'] == true);
        setState(() {
          _isCurrentPassValid = isValid;
          _isVerifyingPass = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _isVerifyingPass = false;
          // Graceful fallback: do not mark invalid if network hiccup occurs
          _isCurrentPassValid = null;
        });
      }
    });
  }

  void _onFieldChanged() {
    if (mounted) {
      if (_errorMessage != null) {
        setState(() => _errorMessage = null);
      } else {
        setState(() {});
      }
    }
  }

  @override
  void dispose() {
    _verifyDebounceTimer?.cancel();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // --- Real-time Field-by-Field Validation Status ---
  bool get _isCurrentValid =>
      _currentPasswordController.text.trim().isNotEmpty &&
      _isCurrentPassValid == true;

  bool get _isNewValid => _newPasswordController.text.trim().length >= 6;

  bool get _isConfirmFilled => _confirmPasswordController.text.trim().isNotEmpty;

  bool get _isConfirmMatched =>
      _isConfirmFilled &&
      _confirmPasswordController.text.trim() == _newPasswordController.text.trim();

  bool get _isFormValid =>
      _isCurrentValid &&
      !_isVerifyingPass &&
      _isNewValid &&
      _isConfirmMatched;

  Future<void> _submitChangePassword() async {
    if (_isLoading || !_isFormValid) return;
    setState(() => _errorMessage = null);

    final currentPw = _currentPasswordController.text.trim();
    final newPw = _newPasswordController.text.trim();
    final confirmPw = _confirmPasswordController.text.trim();

    if (currentPw.isEmpty) {
      setState(() => _errorMessage = 'Kata sandi saat ini wajib diisi.');
      return;
    }
    if (_isCurrentPassValid == false) {
      setState(() => _errorMessage = 'Kata sandi saat ini tidak cocok dengan akun Anda.');
      return;
    }
    if (newPw.length < 6) {
      setState(() => _errorMessage = 'Kata sandi baru minimal 6 karakter.');
      return;
    }
    if (newPw != confirmPw) {
      setState(() => _errorMessage = 'Konfirmasi kata sandi baru tidak cocok.');
      return;
    }

    setState(() => _isLoading = true);
    HapticFeedback.lightImpact();

    try {
      final res = await ApiClient().put(
        ApiEndpoints.updatePassword,
        data: {
          'current_password': currentPw,
          'new_password': newPw,
          'new_password_confirmation': confirmPw,
        },
      );

      if (!mounted) return;

      if (res.data != null && (res.data['status'] == 'success' || res.statusCode == 200)) {
        HapticFeedback.mediumImpact();
        Navigator.of(context).pop(true);
        AppNotification.showSuccess(
          context,
          'Kata Sandi Berhasil Diperbarui',
          subtitle: res.data['message']?.toString() ?? 'Gunakan kata sandi baru Anda untuk sesi masuk berikutnya.',
        );
      } else {
        setState(() {
          _errorMessage = res.data?['message']?.toString() ?? 'Gagal memperbarui kata sandi. Silakan coba lagi.';
          _isLoading = false;
        });
      }
    } on DioException catch (dioErr) {
      if (!mounted) return;
      String errorText = 'Gagal menghubungi server. Periksa koneksi internet Anda.';
      if (dioErr.response?.data != null && dioErr.response!.data is Map) {
        final data = dioErr.response!.data as Map;
        if (data['message'] != null) {
          errorText = data['message'].toString();
        } else if (data['errors'] != null && data['errors'] is Map) {
          final errors = data['errors'] as Map;
          final firstKey = errors.keys.firstOrNull;
          if (firstKey != null && errors[firstKey] is List && (errors[firstKey] as List).isNotEmpty) {
            errorText = errors[firstKey][0].toString();
          }
        }
      }
      setState(() {
        _errorMessage = errorText;
        _isLoading = false;
      });
      HapticFeedback.heavyImpact();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Terjadi kesalahan sistem: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);

    final newText = _newPasswordController.text.trim();
    final confirmText = _confirmPasswordController.text.trim();

    return Dialog(
      backgroundColor: isDark ? AppTheme.surfaceDark : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
        ),
      ),
      elevation: 12,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
            child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header with Shield Lock Icon
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEA580C).withValues(alpha: isDark ? 0.2 : 0.12),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFFEA580C).withValues(alpha: 0.35),
                          width: 1.5,
                        ),
                      ),
                      child: const Icon(
                        Icons.lock_reset_rounded,
                        color: Color(0xFFEA580C),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Ubah Kata Sandi',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Perbarui kata sandi akun untuk keamanan',
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

                const SizedBox(height: 18),

                // Error Banner
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: isDark ? 0.18 : 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.error_outline_rounded, size: 16, color: Color(0xFFEF4444)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFEF4444),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                // 1. Current Password (Live Server Verified)
                _buildPasswordField(
                  controller: _currentPasswordController,
                  label: 'Kata Sandi Saat Ini',
                  hint: 'Masukkan kata sandi lama Anda',
                  obscureText: _obscureCurrent,
                  onToggleObscure: () => setState(() => _obscureCurrent = !_obscureCurrent),
                  isDark: isDark,
                  isRequired: true,
                  isValid: _isCurrentPassValid == true,
                  isError: _isCurrentPassValid == false,
                  statusWidget: _buildCurrentPasswordFeedback(isDark: isDark),
                  textInputAction: TextInputAction.next,
                ),

                const SizedBox(height: 14),

                // 2. New Password (Wajib * Min 6 Karakter)
                _buildPasswordField(
                  controller: _newPasswordController,
                  label: 'Kata Sandi Baru',
                  hintNote: '(Min. 6 Karakter)',
                  hint: 'Minimal 6 karakter kombinasi',
                  obscureText: _obscureNew,
                  onToggleObscure: () => setState(() => _obscureNew = !_obscureNew),
                  isDark: isDark,
                  isRequired: true,
                  isValid: newText.length >= 6,
                  isError: newText.isNotEmpty && newText.length < 6,
                  statusWidget: newText.isNotEmpty
                      ? _buildStatusFeedback(
                          isValid: newText.length >= 6,
                          text: newText.length >= 6
                              ? 'Minimal 6 karakter terpenuhi'
                              : 'Minimal 6 karakter (${newText.length}/6)',
                          isDark: isDark,
                        )
                      : null,
                  textInputAction: TextInputAction.next,
                ),

                const SizedBox(height: 14),

                // 3. Confirm New Password (Wajib *)
                _buildPasswordField(
                  controller: _confirmPasswordController,
                  label: 'Konfirmasi Kata Sandi Baru',
                  hint: 'Ulangi kata sandi baru',
                  obscureText: _obscureConfirm,
                  onToggleObscure: () => setState(() => _obscureConfirm = !_obscureConfirm),
                  isDark: isDark,
                  isRequired: true,
                  isValid: _isConfirmMatched,
                  isError: confirmText.isNotEmpty && !_isConfirmMatched,
                  statusWidget: confirmText.isNotEmpty
                      ? _buildStatusFeedback(
                          isValid: _isConfirmMatched,
                          text: _isConfirmMatched
                              ? 'Konfirmasi kata sandi cocok'
                              : 'Konfirmasi kata sandi belum cocok',
                          isDark: isDark,
                        )
                      : null,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) {
                    if (_isFormValid) _submitChangePassword();
                  },
                ),

                const SizedBox(height: 22),

                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                          side: BorderSide(
                            color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                          ),
                          minimumSize: const Size(0, 44),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                        child: const Text('Batal', style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFEA580C),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: isDark
                              ? const Color(0xFF1E293B)
                              : const Color(0xFFE2E8F0),
                          disabledForegroundColor: isDark
                              ? const Color(0xFF64748B)
                              : const Color(0xFF94A3B8),
                          minimumSize: const Size(0, 44),
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: (_isFormValid && !_isLoading) ? _submitChangePassword : null,
                        child: _isLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (_isFormValid)
                                    const Padding(
                                      padding: EdgeInsets.only(right: 6),
                                      child: Icon(Icons.check_circle_rounded, size: 16),
                                    ),
                                  const Text(
                                    'Simpan Perubahan',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }

  /// Live current password feedback matching Web Panel parity.
  Widget? _buildCurrentPasswordFeedback({required bool isDark}) {
    if (_isVerifyingPass) {
      return Padding(
        padding: const EdgeInsets.only(top: 5, left: 2),
        child: Row(
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.8,
                valueColor: AlwaysStoppedAnimation<Color>(
                  isDark ? AppTheme.textSecondary : const Color(0xFF94A3B8),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'Memverifikasi kata sandi akun...',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      );
    }

    if (_isCurrentPassValid == true) {
      return _buildStatusFeedback(
        isValid: true,
        text: 'Kata sandi saat ini cocok',
        isDark: isDark,
      );
    }

    if (_isCurrentPassValid == false && _currentPasswordController.text.trim().isNotEmpty) {
      return _buildStatusFeedback(
        isValid: false,
        text: 'Kata sandi saat ini tidak cocok dengan akun Anda',
        isDark: isDark,
      );
    }

    return null;
  }

  Widget _buildStatusFeedback({
    required bool isValid,
    required String text,
    required bool isDark,
  }) {
    final color = isValid ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    final icon = isValid ? Icons.check_circle_rounded : Icons.info_outline_rounded;

    return Padding(
      padding: const EdgeInsets.only(top: 5, left: 2),
      child: Row(
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required bool obscureText,
    required VoidCallback onToggleObscure,
    required bool isDark,
    bool isRequired = false,
    String? hintNote,
    bool isValid = false,
    bool isError = false,
    Widget? statusWidget,
    TextInputAction? textInputAction,
    ValueChanged<String>? onSubmitted,
  }) {
    Color borderColor;
    if (isError) {
      borderColor = const Color(0xFFEF4444);
    } else if (isValid) {
      borderColor = const Color(0xFF10B981).withValues(alpha: 0.8);
    } else {
      borderColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF334155),
              ),
            ),
            if (isRequired) ...[
              const SizedBox(width: 3),
              const Text(
                '*',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFEA580C),
                ),
              ),
            ],
            if (hintNote != null) ...[
              const SizedBox(width: 5),
              Text(
                hintNote,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? AppTheme.textSecondary : const Color(0xFF94A3B8),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscureText,
          textInputAction: textInputAction,
          onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
          onSubmitted: onSubmitted,
          style: TextStyle(
            fontSize: 13,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              fontSize: 12,
              color: isDark ? AppTheme.textSecondary : const Color(0xFF94A3B8),
            ),
            prefixIcon: Icon(
              Icons.key_rounded,
              size: 18,
              color: isError
                  ? const Color(0xFFEF4444)
                  : (isValid ? const Color(0xFF10B981) : (isDark ? AppTheme.textSecondary : const Color(0xFF94A3B8))),
            ),
            suffixIcon: IconButton(
              icon: Icon(
                obscureText ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                size: 18,
                color: isDark ? AppTheme.textSecondary : const Color(0xFF94A3B8),
              ),
              splashRadius: 18,
              onPressed: onToggleObscure,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            filled: true,
            fillColor: isError
                ? const Color(0xFFEF4444).withValues(alpha: isDark ? 0.12 : 0.04)
                : (isValid
                    ? const Color(0xFF10B981).withValues(alpha: isDark ? 0.08 : 0.03)
                    : (isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC))),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: borderColor,
                width: isError || isValid ? 1.3 : 1.0,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: isError
                    ? const Color(0xFFEF4444)
                    : (isValid ? const Color(0xFF10B981) : const Color(0xFFEA580C)),
                width: 1.5,
              ),
            ),
          ),
        ),
        if (statusWidget != null) statusWidget,
      ],
    );
  }
}
