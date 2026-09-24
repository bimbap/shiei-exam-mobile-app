import 'package:flutter/material.dart';
import '../../config/app_config.dart';
import '../../config/routes.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/app_exit_dialog.dart';
import '../../shared/widgets/app_notification.dart';
import '../../shared/widgets/shiei_brand_logo.dart';
import 'login_controller.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _controller = LoginController();
  final _nameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    AppExitDialog.resetLock();
    _nameController.addListener(_onFieldChanged);
    _passwordController.addListener(_onFieldChanged);
  }

  void _onFieldChanged() {
    if (_controller.errorMessage != null) {
      _controller.clearError();
    }
  }

  @override
  void dispose() {
    _nameController.removeListener(_onFieldChanged);
    _passwordController.removeListener(_onFieldChanged);
    _nameController.dispose();
    _passwordController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _showServerSettingsDialog() {
    final serverController = TextEditingController(text: AppConfig.baseUrl);
    final isDark = AppTheme.isDark(context);
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: isDark ? AppTheme.surfaceDark : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
              width: 1.2,
            ),
          ),
          title: Row(
            children: [
              const Icon(Icons.dns_rounded, color: AppTheme.primaryGlow, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Pengaturan Server',
                  style: TextStyle(
                    color: isDark ? Colors.white : AppTheme.textPrimaryLight,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tentukan URL backend Shiei Core / Shiei Panel sekolah Anda:',
                style: TextStyle(
                  color: isDark ? AppTheme.textSecondary : AppTheme.textSecondaryLight,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: serverController,
                onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                style: TextStyle(
                  color: isDark ? Colors.white : AppTheme.textPrimaryLight,
                  fontSize: 13,
                ),
                decoration: const InputDecoration(
                  hintText: 'http://192.168.1.100:8000/api/v1',
                  prefixIcon: Icon(Icons.link_rounded, color: AppTheme.primaryGlow, size: 20),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'Batal',
                style: TextStyle(
                  color: isDark ? AppTheme.textSecondary : AppTheme.textSecondaryLight,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(90, 42),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              onPressed: () {
                AppConfig.setCustomBaseUrl(serverController.text);
                Navigator.pop(ctx);
                AppNotification.showSuccess(
                  context,
                  'Server Aktif',
                  subtitle: AppConfig.baseUrl,
                );
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
  }

  void _showLoginHelpDialog() {
    final isDark = AppTheme.isDark(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppTheme.surfaceDark : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            width: 1.2,
          ),
        ),
        title: Row(
          children: [
            const Icon(Icons.help_outline_rounded, color: AppTheme.primaryGlow, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Bantuan Masuk',
                style: TextStyle(
                  color: isDark ? Colors.white : AppTheme.textPrimaryLight,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Panduan masuk ke sistem ujian Shiei Exam:',
              style: TextStyle(
                color: isDark ? AppTheme.textSecondary : AppTheme.textSecondaryLight,
                fontSize: 12.5,
              ),
            ),
            const SizedBox(height: 14),
            _buildLoginHelpItem(
              icon: Icons.school_outlined,
              title: 'Siswa / Peserta Ujian',
              desc: 'Gunakan NISN atau nama pengguna yang diberikan oleh operator sekolah.',
              isDark: isDark,
            ),
            const SizedBox(height: 10),
            _buildLoginHelpItem(
              icon: Icons.badge_outlined,
              title: 'Guru / Pengawas',
              desc: 'Gunakan NIP atau nama pengguna guru yang terdaftar di Shiei Panel.',
              isDark: isDark,
            ),
            const SizedBox(height: 10),
            _buildLoginHelpItem(
              icon: Icons.vpn_key_outlined,
              title: 'Lupa Kata Sandi?',
              desc: 'Hubungi pengawas atau operator sekolah untuk melakukan atur ulang kata sandi.',
              isDark: isDark,
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Mengerti'),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginHelpItem({
    required IconData icon,
    required String title,
    required String desc,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceCard : AppTheme.surfaceCardLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppTheme.borderSubtle : AppTheme.borderSubtleLight,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppTheme.primaryGlow, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: isDark ? Colors.white : AppTheme.textPrimaryLight,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  desc,
                  style: TextStyle(
                    color: isDark ? AppTheme.textSecondary : AppTheme.textSecondaryLight,
                    fontSize: 11.5,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _submitLogin() async {
    final name = _nameController.text.trim();
    final password = _passwordController.text;

    if (name.isEmpty || password.isEmpty) {
      _controller.setError('Silakan masukkan nama/username dan kata sandi.');
      AppNotification.showWarning(
        context,
        'Validasi Login',
        subtitle: 'Silakan masukkan nama/username dan kata sandi.',
      );
      return;
    }

    final success = await _controller.login(
      name: name,
      password: password,
    );

    if (success && mounted) {
      final role = _controller.userRole;
      if (role == 'teacher' || role == 'school_admin' || role == 'super_admin') {
        Navigator.of(context).pushReplacementNamed(AppRoutes.teacherMonitor);
      } else {
        Navigator.of(context).pushReplacementNamed(AppRoutes.examList);
      }
    } else if (!success && mounted) {
      AppNotification.showError(
        context,
        'Gagal Masuk',
        subtitle: _controller.errorMessage ?? 'Nama pengguna atau kata sandi salah.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final isDark = AppTheme.isDark(context);
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            await AppExitDialog.show(context);
          },
          child: Scaffold(
            backgroundColor: AppTheme.background(context),
          appBar: AppBar(
            actions: [
              IconButton(
                icon: Icon(Icons.dns_outlined, color: isDark ? AppTheme.textSecondary : AppTheme.textSecondaryLight),
                tooltip: 'Pengaturan Server',
                onPressed: _showServerSettingsDialog,
              ),
              IconButton(
                icon: Icon(Icons.settings_outlined, color: isDark ? AppTheme.textSecondary : AppTheme.textSecondaryLight),
                tooltip: 'Pengaturan Kiosk',
                onPressed: () => Navigator.of(context).pushNamed(AppRoutes.settings),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: SafeArea(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
              child: Center(
                child: SingleChildScrollView(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Official Horizontal Brand Lockup
                      const ShieiBrandLogo(
                        logoSize: 48,
                        fontSize: 26,
                        mainAxisAlignment: MainAxisAlignment.center,
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Menjaga Integritas, Mengawal Kejujuran Ujian',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.primaryGlow,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 28),

                      // Double-Bezel Nested Outer Card
                      Container(
                        decoration: BoxDecoration(
                          color: isDark ? AppTheme.surfaceDark.withOpacity(0.85) : Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: isDark ? AppTheme.borderSubtle.withOpacity(0.7) : const Color(0xFFE2E8F0)),
                          boxShadow: [
                            BoxShadow(
                              color: isDark ? Colors.black.withOpacity(0.35) : Colors.black.withOpacity(0.06),
                              blurRadius: 30,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Error Banner with Full Light/Dark Mode Contrast Support
                            if (_controller.errorMessage != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                margin: const EdgeInsets.only(bottom: 18),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? AppTheme.dangerDark.withValues(alpha: 0.35)
                                      : const Color(0xFFFEF2F2), // Light Mode: clean soft Red-50
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isDark
                                        ? AppTheme.dangerRed.withValues(alpha: 0.5)
                                        : const Color(0xFFFECACA), // Light Mode: crisp Red-200 border
                                    width: 1.2,
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.error_outline_rounded,
                                      color: isDark ? AppTheme.dangerRed : const Color(0xFFDC2626), // Light Mode: Red-600
                                      size: 19,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        _controller.errorMessage!,
                                        style: TextStyle(
                                          color: isDark ? const Color(0xFFFCA5A5) : const Color(0xFF991B1B), // Light Mode: high-contrast deep Red-800
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                          height: 1.35,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                            // Field: Username / NISN / NIP
                            TextField(
                              controller: _nameController,
                              onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                              textInputAction: TextInputAction.next,
                              style: TextStyle(
                                color: isDark ? Colors.white : AppTheme.textPrimaryLight,
                                fontSize: 14,
                              ),
                              decoration: const InputDecoration(
                                labelText: 'Nama / NISN / NIP',
                                hintText: 'Ketik identitas akun Anda',
                                prefixIcon: Icon(Icons.person_outline_rounded,
                                    color: AppTheme.textSecondary, size: 20),
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Field: Kata Sandi
                            TextField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _submitLogin(),
                              style: TextStyle(
                                color: isDark ? Colors.white : AppTheme.textPrimaryLight,
                                fontSize: 14,
                              ),
                              decoration: InputDecoration(
                                labelText: 'Kata Sandi',
                                hintText: '••••••••',
                                prefixIcon: const Icon(Icons.lock_outline_rounded,
                                    color: AppTheme.textSecondary, size: 20),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    color: AppTheme.textSecondary,
                                    size: 20,
                                  ),
                                  onPressed: () =>
                                      setState(() => _obscurePassword = !_obscurePassword),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Primary Action Button
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
                              onPressed: _controller.isLoading ? null : _submitLogin,
                              child: _controller.isLoading
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2.2,
                                      ),
                                    )
                                  : const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text('Masuk'),
                                        SizedBox(width: 8),
                                        Icon(Icons.arrow_forward_rounded, size: 18),
                                      ],
                                    ),
                            ),
                            const SizedBox(height: 16),

                            // Secondary Clickable Link Below Button
                            Center(
                              child: InkWell(
                                onTap: _showLoginHelpDialog,
                                borderRadius: BorderRadius.circular(8),
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.info_outline_rounded, size: 14, color: AppTheme.textSecondary),
                                      SizedBox(width: 6),
                                      Text(
                                        'Mengalami kendala? ',
                                        style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                                      ),
                                      Text(
                                        'Buka Panduan Login',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.primaryGlow,
                                          fontWeight: FontWeight.w600,
                                          decoration: TextDecoration.underline,
                                          decorationColor: AppTheme.primaryGlow,
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
                      const SizedBox(height: 24),

                      // Official Tagline
                      Text(
                        'Menjaga Integritas, Mengawal Kejujuran Ujian',
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? AppTheme.textMuted : AppTheme.textMutedLight,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  },
);
  }
}
