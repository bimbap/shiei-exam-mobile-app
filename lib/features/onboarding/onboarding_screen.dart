import 'package:flutter/material.dart';
import '../../config/routes.dart';
import '../../core/auth/token_storage.dart';
import '../../core/notifications/exam_reminder_service.dart';
import '../../core/theme/theme_controller.dart';
import '../../core/update/app_update_service.dart';
import '../../shared/theme/app_theme.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> with WidgetsBindingObserver {
  final PageController _pageController = PageController();
  int _currentIndex = 0;

  bool _isNotificationGranted = false;
  bool _canInstallPackages = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
    }
  }

  Future<void> _checkPermissions() async {
    final notifGranted = await ExamReminderService.isPermissionGranted();
    final installGranted = await AppUpdateService.instance.canRequestPackageInstalls();
    if (mounted) {
      setState(() {
        _isNotificationGranted = notifGranted;
        _canInstallPackages = installGranted;
      });
    }
  }

  bool get _canProceed {
    if (_currentIndex == 2) {
      return _isNotificationGranted;
    }
    if (_currentIndex == 3) {
      return _canInstallPackages;
    }
    return true;
  }

  Future<void> _requestNotification() async {
    await ExamReminderService.requestPermission();
    // Fast polling (up to 5s) to detect permission grant immediately when dialog resolves
    for (int i = 0; i < 10; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      final granted = await ExamReminderService.isPermissionGranted();
      if (granted) {
        setState(() {
          _isNotificationGranted = true;
        });
        break;
      }
    }
    await _checkPermissions();
  }

  Future<void> _requestInstallPermission() async {
    await AppUpdateService.instance.openInstallPermissionSettings();
    // Poll to detect when user toggles permission in settings and returns
    for (int i = 0; i < 20; i++) {
      await Future.delayed(const Duration(milliseconds: 1000));
      if (!mounted) return;
      final canInstall = await AppUpdateService.instance.canRequestPackageInstalls();
      if (canInstall) {
        setState(() {
          _canInstallPackages = true;
        });
        break;
      }
    }
    await _checkPermissions();
  }

  void _onNext() async {
    if (!_canProceed) return;
    if (_currentIndex < 4) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    } else {
      await _finishOnboarding();
    }
  }

  Future<void> _finishOnboarding() async {
    await TokenStorage.setOnboardingCompleted(true);
    if (mounted) {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      } else {
        Navigator.of(context).pushReplacementNamed(AppRoutes.login);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isLast = _currentIndex == 4;
    final isDark = AppTheme.isDark(context);
    final bg = AppTheme.background(context);
    final skipColor = isDark ? AppTheme.textSecondary : const Color(0xFF64748B);
    final dotInactive = isDark ? AppTheme.borderSubtle : const Color(0xFFCBD5E1);
    final bool canSkip = !isLast && _isNotificationGranted && _canInstallPackages;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar: Back button on left, Skip button on right (only if all mandatory permissions are granted)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (_currentIndex > 0)
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                      color: skipColor,
                      tooltip: 'Kembali',
                      onPressed: () {
                        _pageController.previousPage(
                          duration: const Duration(milliseconds: 350),
                          curve: Curves.easeOutCubic,
                        );
                      },
                    )
                  else
                    const SizedBox(width: 40),
                  Opacity(
                    opacity: canSkip ? 1.0 : 0.0,
                    child: IgnorePointer(
                      ignoring: !canSkip,
                      child: TextButton(
                        onPressed: _finishOnboarding,
                        style: TextButton.styleFrom(
                          foregroundColor: skipColor,
                          textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                        ),
                        child: const Text('Lewati'),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Middle: Swipeable Carousel Content (5 Slides)
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: _canProceed ? const BouncingScrollPhysics() : const NeverScrollableScrollPhysics(),
                onPageChanged: (idx) {
                  setState(() => _currentIndex = idx);
                  _checkPermissions();
                },
                children: [
                  _buildSlide1Welcome(isDark),
                  _buildSlideThemeSelector(isDark),
                  _buildSlide2Notification(isDark),
                  _buildSlide3AppInstall(isDark),
                  _buildSlide4Rules(isDark),
                ],
              ),
            ),

            // Bottom Navigation & Dynamic Action Buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
              child: Column(
                children: [
                  // Animated Dots Indicator (5 dots)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      5,
                      (idx) => AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        height: 7,
                        width: _currentIndex == idx ? 28 : 7,
                        decoration: BoxDecoration(
                          color: _currentIndex == idx ? AppTheme.primaryShiei : dotInactive,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Primary Next / Finish Button (Disabled if mandatory permission is not active)
                  ElevatedButton(
                    onPressed: _canProceed ? _onNext : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryShiei,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                      disabledForegroundColor: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                      minimumSize: const Size(double.infinity, 52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: _canProceed
                            ? BorderSide.none
                            : BorderSide(
                                color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                                width: 1.0,
                              ),
                      ),
                      elevation: _canProceed ? 4 : 0,
                      shadowColor: _canProceed ? AppTheme.primaryShiei.withValues(alpha: 0.4) : Colors.transparent,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          isLast
                              ? 'Saya Setuju & Siap Ujian'
                              : (!_canProceed ? 'Aktifkan Izin untuk Lanjut' : 'Lanjutkan'),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.3,
                            color: _canProceed
                                ? Colors.white
                                : (isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          !_canProceed
                              ? Icons.lock_outline_rounded
                              : (isLast ? Icons.check_circle_rounded : Icons.arrow_forward_rounded),
                          size: 19,
                          color: _canProceed
                              ? Colors.white
                              : (isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- SLIDE 1: WELCOME ---
  Widget _buildSlide1Welcome(bool isDark) {
    return _buildSlideContainer(
      isDark: isDark,
      tag: 'SELAMAT DATANG',
      title: 'Selamat Datang di Shiei Exam',
      description:
          'Halo! Saya pengawas digitalmu. Saya akan mendampingi dan memastikan seluruh ujianmu berlangsung aman, tertib, dan lancar.',
      imageAsset: 'assets/images/shiei_proctor_female_half.jpg',
    );
  }

  // --- SLIDE 2: THEME SELECTION (standalone, no _buildSlideContainer) ---

  // --- SLIDE 2: THEME SELECTION ---
  Widget _buildSlideThemeSelector(bool isDark) {
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final descColor = isDark ? AppTheme.textSecondary : const Color(0xFF475569);
    final tagBg = isDark ? AppTheme.surfaceCard : const Color(0xFFF1F5F9);
    final tagBorder = isDark ? AppTheme.borderSubtle : const Color(0xFFE2E8F0);
    final circleGradColors = isDark
        ? [AppTheme.primaryGlow.withValues(alpha: 0.22), AppTheme.surfaceDark.withValues(alpha: 0.9)]
        : [AppTheme.primaryGlow.withValues(alpha: 0.18), Colors.white];

    final currentMode = ThemeController.instance.themeMode;

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
          // Mascot / Theme Avatar Frame
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: circleGradColors),
              border: Border.all(
                color: AppTheme.primaryShiei.withValues(alpha: 0.35),
                width: 2.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: isDark ? AppTheme.primaryShiei.withValues(alpha: 0.25) : const Color(0x180F172A),
                  blurRadius: 28,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: ClipOval(
              child: Image.asset(
                'assets/images/shiei_mascot_theme.jpg',
                fit: BoxFit.cover,
                cacheWidth: 360,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.palette_rounded,
                  size: 50,
                  color: AppTheme.primaryGlow,
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Tag
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: tagBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: tagBorder),
            ),
            child: const Text(
              'PILIHAN TEMA',
              style: TextStyle(
                color: AppTheme.primaryGlow,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Title
          Text(
            'Pilih Mode Tema',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: titleColor,
              fontSize: 21,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 8),

          // Description
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Text(
              'Sesuaikan kenyamanan visual tampilan saat membaca naskah soal dan mengikuti ujian.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: descColor,
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ),
          const SizedBox(height: 18),

          // 3 Theme Option Cards
          _buildThemeCard(
            title: 'Mode Terang',
            subtitle: 'Tampilan bersih dan kontras jelas di ruangan terang',
            icon: Icons.light_mode_rounded,
            iconColor: const Color(0xFFF59E0B),
            mode: ThemeMode.light,
            isSelected: currentMode == ThemeMode.light,
            isDark: isDark,
          ),
          const SizedBox(height: 10),
          _buildThemeCard(
            title: 'Mode Gelap',
            subtitle: 'Mata lebih rileks dan hemat konsumsi baterai',
            icon: Icons.dark_mode_rounded,
            iconColor: const Color(0xFF818CF8),
            mode: ThemeMode.dark,
            isSelected: currentMode == ThemeMode.dark,
            isDark: isDark,
          ),
          const SizedBox(height: 10),
          _buildThemeCard(
            title: 'Ikuti Sistem HP',
            subtitle: 'Otomatis mengikuti preferensi tema perangkat',
            icon: Icons.settings_brightness_rounded,
            iconColor: const Color(0xFF10B981),
            mode: ThemeMode.system,
            isSelected: currentMode == ThemeMode.system,
            isDark: isDark,
          ),
        ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildThemeCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required ThemeMode mode,
    required bool isSelected,
    required bool isDark,
  }) {
    final activeBg = isDark
        ? AppTheme.primaryShiei.withValues(alpha: 0.18)
        : AppTheme.primaryShiei.withValues(alpha: 0.08);
    final idleBg = isDark ? const Color(0xFF1E293B).withValues(alpha: 0.7) : const Color(0xFFF8FAFC);
    const activeBorder = AppTheme.primaryShiei;
    final idleBorder = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

    return InkWell(
      onTap: () {
        ThemeController.instance.setThemeMode(mode);
        setState(() {});
      },
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: const BoxConstraints(minHeight: 68),
        decoration: BoxDecoration(
          color: isSelected ? activeBg : idleBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? activeBorder : idleBorder,
            width: 1.5,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppTheme.primaryShiei.withValues(alpha: isDark ? 0.25 : 0.12),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: isSelected ? 0.2 : 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: TextStyle(
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                            fontSize: 14.5,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isSelected) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryShiei,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Aktif',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                      fontSize: 11.5,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? AppTheme.primaryShiei : Colors.transparent,
                border: Border.all(
                  color: isSelected
                      ? AppTheme.primaryShiei
                      : (isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8)),
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  // --- SLIDE 3: NOTIFICATION PERMISSION ---
  Widget _buildSlide2Notification(bool isDark) {
    return _buildSlideContainer(
      isDark: isDark,
      tag: 'IZIN PENTING',
      title: 'Aktifkan Izin Notifikasi',
      description:
          'Dapatkan ralat soal seketika dari pengawas saat ujian berlangsung, serta pengingat jadwal ujian H-1 dan 30 menit sebelum mulai.',
      imageAsset: 'assets/images/shiei_mascot_notif.jpg',
      extraContent: Container(
        margin: const EdgeInsets.only(top: 18),
        child: _isNotificationGranted
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.accentGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.accentGreen.withValues(alpha: 0.35)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_rounded, color: AppTheme.accentGreen, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Izin Notifikasi Sudah Aktif',
                      style: TextStyle(
                        color: AppTheme.accentGreen,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              )
            : OutlinedButton.icon(
                onPressed: _requestNotification,
                style: OutlinedButton.styleFrom(
                  backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                  foregroundColor: AppTheme.primaryGlow,
                  side: const BorderSide(color: AppTheme.primaryShiei, width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                icon: const Icon(Icons.notifications_active_rounded, size: 18),
                label: const Text(
                  'Izinkan Notifikasi Sekarang',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
      ),
    );
  }

  // --- SLIDE 4: APP INSTALL / UPDATE PERMISSION ---
  Widget _buildSlide3AppInstall(bool isDark) {
    return _buildSlideContainer(
      isDark: isDark,
      tag: 'PEMBARUAN SISTEM',
      title: 'Izinkan Pembaruan Otomatis',
      description:
          'Agar Shiei Exam selalu mendapatkan pembaruan sistem dan keamanan terbaru dari sekolah secara instan tanpa perlu download manual dari browser.',
      imageAsset: 'assets/images/shiei_mascot_update.jpg',
      extraContent: Container(
        margin: const EdgeInsets.only(top: 18),
        child: _canInstallPackages
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.accentGreen.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.accentGreen.withValues(alpha: 0.35)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.verified_rounded, color: AppTheme.accentGreen, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Izin Pembaruan Sudah Aktif',
                      style: TextStyle(
                        color: AppTheme.accentGreen,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              )
            : OutlinedButton.icon(
                onPressed: _requestInstallPermission,
                style: OutlinedButton.styleFrom(
                  backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                  foregroundColor: AppTheme.primaryGlow,
                  side: const BorderSide(color: AppTheme.primaryShiei, width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                icon: const Icon(Icons.system_update_rounded, size: 18),
                label: const Text(
                  'Buka Setelan Izin Instalasi',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
      ),
    );
  }

  // --- SLIDE 4: GENERAL EXAM RULES ---
  Widget _buildSlide4Rules(bool isDark) {
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final cardBg = isDark ? const Color(0xFF1E293B).withValues(alpha: 0.65) : const Color(0xFFF8FAFC);
    final cardBorder = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final textHead = isDark ? Colors.white : const Color(0xFF0F172A);
    final textDesc = isDark ? AppTheme.textSecondary : const Color(0xFF64748B);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        children: [
          // Trio Banner illustration
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isDark ? AppTheme.borderSubtle : const Color(0xFFE2E8F0),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(17),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.asset(
                  'assets/images/shiei_trio_banner.jpg',
                  fit: BoxFit.cover,
                  cacheWidth: 800,
                ),
              ),
            ),
          ),

          // Tag
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.surfaceCard : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: isDark ? AppTheme.borderSubtle : const Color(0xFFE2E8F0)),
            ),
            child: const Text(
              'TATA TERTIB UJIAN',
              style: TextStyle(
                color: AppTheme.primaryGlow,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 12),

          Text(
            'Tata Tertib & Etika Ujian',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: titleColor,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Harap patuhi ketentuan berikut demi ketertiban dan kejujuran ujian:',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: textDesc,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),

          // Rule 1: Ketenangan
          _buildRuleItem(
            icon: Icons.volume_off_rounded,
            iconColor: const Color(0xFF38BDF8),
            title: 'Jaga Ketenangan Ruangan',
            desc: 'Dilarang membuat kegaduhan, berbicara, atau mengganggu konsentrasi peserta ujian lain.',
            cardBg: cardBg,
            cardBorder: cardBorder,
            textHead: textHead,
            textDesc: textDesc,
          ),
          const SizedBox(height: 10),

          // Rule 2: Kejujuran & Mandiri
          _buildRuleItem(
            icon: Icons.edit_note_rounded,
            iconColor: const Color(0xFFF59E0B),
            title: 'Jujur & Mengerjakan Mandiri',
            desc: 'Dilarang mencontek, bekerja sama, membawa catatan, atau membuka aplikasi lain di luar ujian.',
            cardBg: cardBg,
            cardBorder: cardBorder,
            textHead: textHead,
            textDesc: textDesc,
          ),
          const SizedBox(height: 10),

          // Rule 3: Disiplin & Patuh Pengawas
          _buildRuleItem(
            icon: Icons.school_rounded,
            iconColor: AppTheme.accentGreen,
            title: 'Patuhi Arahan Pengawas',
            desc: 'Disiplin mengikuti seluruh instruksi, waktu pengerjaan, dan ketentuan dari guru pengawas.',
            cardBg: cardBg,
            cardBorder: cardBorder,
            textHead: textHead,
            textDesc: textDesc,
          ),
        ],
      ),
    );
  }

  Widget _buildRuleItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String desc,
    required Color cardBg,
    required Color cardBorder,
    required Color textHead,
    required Color textDesc,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorder, width: 1.2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: textHead,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  desc,
                  style: TextStyle(
                    color: textDesc,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- GENERIC SLIDE LAYOUT (vertically centered) ---
  Widget _buildSlideContainer({
    required bool isDark,
    required String tag,
    required String title,
    required String description,
    required String imageAsset,
    Widget? extraContent,
  }) {
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final descColor = isDark ? AppTheme.textSecondary : const Color(0xFF475569);
    final tagBg = isDark ? AppTheme.surfaceCard : const Color(0xFFF1F5F9);
    final tagBorder = isDark ? AppTheme.borderSubtle : const Color(0xFFE2E8F0);
    final circleGradColors = isDark
        ? [AppTheme.primaryGlow.withValues(alpha: 0.22), AppTheme.surfaceDark.withValues(alpha: 0.9)]
        : [AppTheme.primaryGlow.withValues(alpha: 0.18), Colors.white];

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Avatar Frame
                Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: circleGradColors),
                    border: Border.all(
                      color: AppTheme.primaryShiei.withValues(alpha: 0.35),
                      width: 2.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: isDark ? AppTheme.primaryShiei.withValues(alpha: 0.25) : const Color(0x180F172A),
                        blurRadius: 36,
                        spreadRadius: 3,
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      imageAsset,
                      fit: BoxFit.cover,
                      cacheWidth: 660,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.person_rounded,
                        size: 70,
                        color: AppTheme.primaryGlow,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Eyebrow Tag
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: tagBg,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: tagBorder),
                  ),
                  child: Text(
                    tag,
                    style: const TextStyle(
                      color: AppTheme.primaryGlow,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Title
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: titleColor,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 10),

                // Description
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 340),
                  child: Text(
                    description,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: descColor,
                      fontSize: 13,
                      height: 1.48,
                    ),
                  ),
                ),

                if (extraContent != null) extraContent,
              ],
            ),
          ),
        );
      },
    );
  }
}
