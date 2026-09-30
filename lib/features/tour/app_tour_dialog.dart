import 'package:flutter/material.dart';
import '../../core/auth/token_storage.dart';
import '../../shared/theme/app_theme.dart';

/// Comprehensive 2-phase Onboarding Tour for Students:
/// Phase 1: Welcome bottom sheet with 16:9 mascot banner, "Lewatkan" & "Mulai Tur Siswa"
/// Phase 2: Coachmark spotlight overlay with live tab switching, speech bubble card,
///          mascot avatar, tip box, step pills, animated dots, and notch pointer.
class TourTargetKeys {
  final GlobalKey studentCardKey;
  final GlobalKey examSearchKey;
  final GlobalKey examSectionKey;
  final GlobalKey historyKey;
  final GlobalKey profileCardKey;
  final GlobalKey examRulesKey;

  TourTargetKeys({
    GlobalKey? studentCardKey,
    GlobalKey? examSearchKey,
    GlobalKey? examSectionKey,
    GlobalKey? historyKey,
    GlobalKey? profileCardKey,
    GlobalKey? examRulesKey,
  })  : studentCardKey = studentCardKey ?? GlobalKey(),
        examSearchKey = examSearchKey ?? GlobalKey(),
        examSectionKey = examSectionKey ?? GlobalKey(),
        historyKey = historyKey ?? GlobalKey(),
        profileCardKey = profileCardKey ?? GlobalKey(),
        examRulesKey = examRulesKey ?? GlobalKey();
}

class AppTourKeys {
  static GlobalKey studentCardKey = GlobalKey();
  static GlobalKey examSearchKey = GlobalKey();
  static GlobalKey examSectionKey = GlobalKey();
  static GlobalKey historyKey = GlobalKey();
  static GlobalKey profileCardKey = GlobalKey();
  static GlobalKey examRulesKey = GlobalKey();

  static void reset() {
    studentCardKey = GlobalKey();
    examSearchKey = GlobalKey();
    examSectionKey = GlobalKey();
    historyKey = GlobalKey();
    profileCardKey = GlobalKey();
    examRulesKey = GlobalKey();
  }
}

class AppTourDialog extends StatefulWidget {
  final TourTargetKeys? targetKeys;
  final VoidCallback? onTourCompleted;
  final void Function(int tabIndex)? onSwitchTab;
  final bool startInCoachmark;

  const AppTourDialog({
    super.key,
    this.targetKeys,
    this.onTourCompleted,
    this.onSwitchTab,
    this.startInCoachmark = false,
  });

  static bool _isShowing = false;

  static Future<void> show(
    BuildContext context, {
    TourTargetKeys? targetKeys,
    bool forceShow = false,
    VoidCallback? onComplete,
    void Function(int tabIndex)? onSwitchTab,
    bool startInCoachmark = false,
  }) async {
    if (_isShowing) return;
    if (!forceShow) {
      final isCompleted = await TokenStorage.isMobileTourCompleted();
      if (isCompleted) return;
    }

    if (!context.mounted) return;

    _isShowing = true;
    try {
      await showGeneralDialog(
        context: context,
        barrierDismissible: false,
        barrierLabel: 'AppTourModal',
        barrierColor: Colors.transparent,
        transitionDuration: Duration.zero,
        pageBuilder: (ctx, anim1, anim2) {
          return AppTourDialog(
            targetKeys: targetKeys,
            onTourCompleted: onComplete,
            onSwitchTab: onSwitchTab,
            startInCoachmark: startInCoachmark,
          );
        },
      );
    } finally {
      _isShowing = false;
    }
  }

  @override
  State<AppTourDialog> createState() => _AppTourDialogState();
}

class _AppTourDialogState extends State<AppTourDialog> with TickerProviderStateMixin {
  late bool _isWelcomePhase;
  int _currentStep = 0;
  late AnimationController _welcomeAnimController;
  late Animation<Offset> _welcomeSlideAnimation;
  late Animation<double> _welcomeFadeAnimation;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  Rect? _previousRect;

  late final List<Map<String, dynamic>> _steps;

  @override
  void initState() {
    super.initState();
    final keys = widget.targetKeys;
    _steps = [
      {
        'title': 'Identitas & Status Siswa',
        'desc':
            'Kartu digital resmi menampilkan nama lengkap, NISN, kelas, dan status kehadiran akunmu yang terdaftar resmi di sekolah.',
        'tip': 'Tips: Pastikan data nama dan kelas sesuai dengan akun terdaftar di sekolahmu.',
        'tabIndex': 0,
        'key': keys?.studentCardKey ?? AppTourKeys.studentCardKey,
      },
      {
        'title': 'Pencarian Jadwal Ujian',
        'desc':
            'Temukan mata pelajaran, judul ujian, atau guru pengampu secara instan tanpa perlu menggulir daftar panjang.',
        'tip': 'Tips: Cukup ketik sebagian nama mapel untuk langsung menyaring jadwal ujian yang ingin kamu ikuti.',
        'tabIndex': 0,
        'key': keys?.examSearchKey ?? AppTourKeys.examSearchKey,
      },
      {
        'title': 'Daftar Ujian Terjadwal',
        'desc':
            'Daftar ujian aktif untuk kelasmu. Menampilkan durasi pengerjaan, jumlah butir soal, dan kesiapan perangkat sebelum mulai.',
        'tip': 'Tips: Pastikan daya baterai ponselmu minimal 20% sebelum menekan tombol Mulai Ujian.',
        'tabIndex': 0,
        'key': keys?.examSectionKey ?? AppTourKeys.examSectionKey,
      },
      {
        'title': 'Riwayat Ujian & Hasil',
        'desc':
            'Pantau rekap seluruh ujian yang telah kamu selesaikan. Lembar jawaban tersimpan aman dan terenkripsi langsung ke server sekolah.',
        'tip': 'Tips: Gunakan kolom pencarian riwayat untuk mengecek status dan rekam jejak ujian terdahulu.',
        'tabIndex': 1,
        'key': keys?.historyKey ?? AppTourKeys.historyKey,
      },
      {
        'title': 'Kartu Digital & Mode Kiosk',
        'desc':
            'Tanda pengenal digital resmi peserta ujian. Akunmu terikat aman pada HP ini dan layar otomatis terkunci ke Mode Kiosk selama ujian berlangsung.',
        'tip': 'Selamat menempuh ujian! Dilarang berpindah aplikasi atau split screen. Kerjakan dengan jujur & percaya diri!',
        'tabIndex': 2,
        'key': keys?.profileCardKey ?? AppTourKeys.profileCardKey,
      },
    ];

    _isWelcomePhase = !widget.startInCoachmark;
    _welcomeAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _welcomeSlideAnimation = Tween<Offset>(
      begin: const Offset(0, 1.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _welcomeAnimController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ));
    _welcomeFadeAnimation = CurvedAnimation(
      parent: _welcomeAnimController,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    if (_isWelcomePhase) {
      _welcomeAnimController.forward();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _welcomeAnimController.dispose();
    super.dispose();
  }

  Future<void> _scrollToKey(GlobalKey? key) async {
    if (key?.currentContext != null) {
      try {
        await Scrollable.ensureVisible(
          key!.currentContext!,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
          alignment: 0.35,
        );
      } catch (_) {}
    }
  }

  Future<void> _startCoachmarkTour() async {
    widget.onSwitchTab?.call(0);
    _previousRect = null;
    setState(() {
      _isWelcomePhase = false;
      _currentStep = 0;
    });
    await Future.delayed(const Duration(milliseconds: 220));
    final key = _steps[0]['key'] as GlobalKey?;
    await _scrollToKey(key);
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _handleNext() async {
    if (_currentStep < _steps.length - 1) {
      final currentRect = _getTargetRect(context, _steps[_currentStep]);
      _previousRect = currentRect;
      final nextStep = _currentStep + 1;
      final currentTab = _steps[_currentStep]['tabIndex'] as int?;
      final targetTab = _steps[nextStep]['tabIndex'] as int?;
      if (targetTab != null && targetTab != currentTab) {
        widget.onSwitchTab?.call(targetTab);
        await Future.delayed(const Duration(milliseconds: 220));
      } else {
        await Future.delayed(const Duration(milliseconds: 80));
      }
      final nextKey = _steps[nextStep]['key'] as GlobalKey?;
      await _scrollToKey(nextKey);
      if (mounted) {
        setState(() => _currentStep = nextStep);
      }
    } else {
      await _handleFinish();
    }
  }

  Future<void> _handlePrevious() async {
    if (_currentStep > 0) {
      final currentRect = _getTargetRect(context, _steps[_currentStep]);
      _previousRect = currentRect;
      final prevStep = _currentStep - 1;
      final currentTab = _steps[_currentStep]['tabIndex'] as int?;
      final targetTab = _steps[prevStep]['tabIndex'] as int?;
      if (targetTab != null && targetTab != currentTab) {
        widget.onSwitchTab?.call(targetTab);
        await Future.delayed(const Duration(milliseconds: 220));
      } else {
        await Future.delayed(const Duration(milliseconds: 80));
      }
      final prevKey = _steps[prevStep]['key'] as GlobalKey?;
      await _scrollToKey(prevKey);
      if (mounted) {
        setState(() => _currentStep = prevStep);
      }
    }
  }

  bool _isClosing = false;

  Future<void> _handleSkip() async {
    if (_isClosing) return;
    _isClosing = true;
    await TokenStorage.setMobileTourCompleted(true);
    if (mounted && _isWelcomePhase) {
      await _welcomeAnimController.reverse();
    }
    if (mounted) {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      widget.onTourCompleted?.call();
    }
  }

  Future<void> _handleFinish() async {
    await TokenStorage.setMobileTourCompleted(true);
    if (mounted) {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      widget.onTourCompleted?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleSkip();
      },
      child: Material(
        type: MaterialType.transparency,
        child: DefaultTextStyle(
          style: const TextStyle(
            decoration: TextDecoration.none,
          ),
          child: _isWelcomePhase ? _buildWelcomeCard(context) : _buildCoachmarkSpotlight(context),
        ),
      ),
    );
  }

  /// Phase 1: Welcome Bottom Card with Framed Mascot Banner & Drop Shadow
  Widget _buildWelcomeCard(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final cardBg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569);
    final handleColor = isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1);

    return Stack(
      children: [
        // 1. Dark backdrop scrim (fades in and out)
        FadeTransition(
          opacity: _welcomeFadeAnimation,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _handleSkip,
            child: Container(
              color: Colors.black.withValues(alpha: 0.75),
            ),
          ),
        ),

        // 2. Sliding Welcome Modal Card
        Align(
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () {},
            onVerticalDragUpdate: (details) {
              if (details.primaryDelta != null && details.primaryDelta! > 0) {
                final double delta = details.primaryDelta! / 320;
                _welcomeAnimController.value = (_welcomeAnimController.value - delta).clamp(0.0, 1.0);
              } else if (details.primaryDelta != null && details.primaryDelta! < 0 && _welcomeAnimController.value < 1.0) {
                final double delta = -details.primaryDelta! / 320;
                _welcomeAnimController.value = (_welcomeAnimController.value + delta).clamp(0.0, 1.0);
              }
            },
            onVerticalDragEnd: (details) async {
              if (_welcomeAnimController.value < 0.75 ||
                  (details.primaryVelocity != null && details.primaryVelocity! > 250)) {
                await _handleSkip();
              } else {
                _welcomeAnimController.forward();
              }
            },
            child: SlideTransition(
              position: _welcomeSlideAnimation,
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxWidth: 480),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  border: Border(
                    top: BorderSide(
                      color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                      width: 1.5,
                    ),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Handle drag bar indicator
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        margin: const EdgeInsets.only(top: 12, bottom: 8),
                        decoration: BoxDecoration(
                          color: handleColor,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),

                    // Framed Mascot Illustration with prominent bottom-left drop shadow
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: isDark
                                  ? Colors.black.withValues(alpha: 0.70)
                                  : const Color(0xFF0F172A).withValues(alpha: 0.22),
                              blurRadius: 20,
                              spreadRadius: 1,
                              offset: const Offset(-8, 10),
                            ),
                            BoxShadow(
                              color: isDark
                                  ? const Color(0xFFF97316).withValues(alpha: 0.20)
                                  : const Color(0xFF0F172A).withValues(alpha: 0.12),
                              blurRadius: 8,
                              spreadRadius: 0,
                              offset: const Offset(-3, 4),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: Image.asset(
                              'assets/images/shiei_trio_banner.jpg',
                              fit: BoxFit.cover,
                              cacheWidth: 720,
                              errorBuilder: (_, __, ___) => Container(
                                color: const Color(0xFF0F172A),
                                child: const Center(
                                  child: Icon(Icons.shield_rounded, size: 48, color: Color(0xFFF97316)),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Content Body
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            'Selamat Datang di Shiei Exam',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: titleColor,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Ikuti tur panduan interaktif untuk mengenal fitur aplikasi, tata tertib ujian, dan panduan keamanan Shiei Exam.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: subColor,
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                                    foregroundColor: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
                                    side: BorderSide(
                                      color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                                      width: 1.2,
                                    ),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    minimumSize: const Size(0, 46),
                                  ),
                                  onPressed: _handleSkip,
                                  child: const Text(
                                    'Lewatkan',
                                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFF97316),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    minimumSize: const Size(0, 46),
                                    elevation: 4,
                                  ),
                                  onPressed: _startCoachmarkTour,
                                  child: const Text(
                                    'Mulai Tur Siswa',
                                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Rect _getTargetRect(BuildContext context, Map<String, dynamic> step) {
    final screenSize = MediaQuery.of(context).size;
    final topPadding = MediaQuery.of(context).padding.top;
    final key = step['key'] as GlobalKey?;
    if (key?.currentContext != null) {
      final renderBox = key!.currentContext!.findRenderObject() as RenderBox?;
      if (renderBox != null && renderBox.hasSize) {
        final offset = renderBox.localToGlobal(Offset.zero);
        final size = renderBox.size;
        return (offset & size).inflate(6);
      }
    }

    // High-precision fallback calculation
    final fallbackTop = topPadding + kToolbarHeight + 16;
    return Rect.fromLTWH(16, fallbackTop, screenSize.width - 32, 90);
  }

  /// Phase 2: Coachmark Spotlight with Glassmorphic Bubble & Pointer Notch
  Widget _buildCoachmarkSpotlight(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final step = _steps[_currentStep];
    final isLast = _currentStep == _steps.length - 1;
    final isFirst = _currentStep == 0;
    final isDark = AppTheme.isDark(context);

    final targetRect = _getTargetRect(context, step);
    final placeAbove = (targetRect.bottom + 270 > screenSize.height - 60);

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, _) {
        return SizedBox(
          width: double.infinity,
          height: double.infinity,
          child: Stack(
            children: [
              // Smooth morphing spotlight cutout canvas
              TweenAnimationBuilder<Rect?>(
                key: ValueKey<int>(_currentStep),
                tween: RectTween(
                  begin: _previousRect ?? targetRect,
                  end: targetRect,
                ),
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeInOutCubic,
                builder: (context, animatedRect, _) {
                  final rect = animatedRect ?? targetRect;
                  return CustomPaint(
                    size: screenSize,
                    painter: _StudentSpotlightOverlayPainter(
                      targetRect: rect,
                      borderRadius: 16,
                      overlayColor: Colors.black.withValues(alpha: 0.78),
                      pulseValue: _pulseAnimation.value,
                    ),
                  );
                },
              ),

              // Pointer Tooltip Bubble with smooth sliding AnimatedPositioned
              AnimatedPositioned(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeInOutCubic,
                left: 16,
                right: 16,
                top: placeAbove ? null : (targetRect.bottom + 8),
                bottom: placeAbove ? (screenSize.height - targetRect.top + 8) : null,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!placeAbove)
                      AnimatedPadding(
                        duration: const Duration(milliseconds: 320),
                        curve: Curves.easeInOutCubic,
                        padding: EdgeInsets.only(
                          left: (targetRect.left + (targetRect.width / 2) - 26).clamp(24.0, screenSize.width - 48.0),
                        ),
                        child: CustomPaint(
                          size: const Size(18, 9),
                          painter: _StudentTriangleNotchPainter(
                            isPointingUp: true,
                            color: isDark ? const Color(0xFF0F172A) : Colors.white,
                            borderColor: const Color(0xFFF97316).withValues(alpha: 0.6),
                          ),
                        ),
                      ),

                    // Main Tooltip Box
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0F172A) : Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: const Color(0xFFF97316).withValues(alpha: isDark ? 0.45 : 0.35),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isDark ? 0.6 : 0.18),
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                          ),
                          BoxShadow(
                            color: const Color(0xFFF97316).withValues(alpha: 0.12),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Header: Step pill & Close button
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF97316).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: const Color(0xFFF97316).withValues(alpha: 0.35),
                                    width: 0.8,
                                  ),
                                ),
                                child: Text(
                                  'Langkah ${_currentStep + 1} dari ${_steps.length}',
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFFEA580C),
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: _handleSkip,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'Lewati',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),

                          // Animated Step Content (Title, desc, tip)
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 240),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (child, animation) {
                              return FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0, 0.05),
                                    end: Offset.zero,
                                  ).animate(animation),
                                  child: child,
                                ),
                              );
                            },
                            child: KeyedSubtree(
                              key: ValueKey<int>(_currentStep),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Mascot Avatar & Step Title
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Container(
                                        width: 36,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: const Color(0xFFF97316).withValues(alpha: 0.7),
                                            width: 1.5,
                                          ),
                                        ),
                                        child: ClipOval(
                                          child: Image.asset(
                                            'assets/images/shiei_student_half.jpg',
                                            fit: BoxFit.cover,
                                            cacheWidth: 120,
                                            errorBuilder: (_, __, ___) => Image.asset(
                                              'assets/images/shiei_mascot_guide.jpg',
                                              fit: BoxFit.cover,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          step['title'] as String,
                                          style: TextStyle(
                                            fontSize: 14.5,
                                            fontWeight: FontWeight.bold,
                                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),

                                  // Step Description
                                  Text(
                                    step['desc'] as String,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                                      height: 1.45,
                                    ),
                                  ),
                                  const SizedBox(height: 10),

                                  // Tip Container
                                  Container(
                                    padding: const EdgeInsets.all(9),
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFFFF7ED),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: const Color(0xFFF97316).withValues(alpha: isDark ? 0.3 : 0.25),
                                      ),
                                    ),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Icon(
                                          Icons.lightbulb_outline_rounded,
                                          size: 15,
                                          color: Color(0xFFEA580C),
                                        ),
                                        const SizedBox(width: 7),
                                        Expanded(
                                          child: Text(
                                            step['tip'] as String,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF9A3412),
                                              height: 1.35,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Navigation Footer: Step Dots & Previous/Next Buttons
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // Dot Indicators
                              Row(
                                children: List.generate(_steps.length, (idx) {
                                  final isCurrent = idx == _currentStep;
                                  return AnimatedContainer(
                                    duration: const Duration(milliseconds: 250),
                                    curve: Curves.easeOutCubic,
                                    margin: const EdgeInsets.only(right: 4),
                                    width: isCurrent ? 18 : 5,
                                    height: 5,
                                    decoration: BoxDecoration(
                                      color: isCurrent
                                          ? const Color(0xFFF97316)
                                          : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                                      borderRadius: BorderRadius.circular(2.5),
                                    ),
                                  );
                                }),
                              ),

                              // Buttons (Back & Next)
                              Row(
                                children: [
                                  if (!isFirst) ...[
                                    OutlinedButton(
                                      onPressed: _handlePrevious,
                                      style: OutlinedButton.styleFrom(
                                        backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                                        foregroundColor: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                                        side: BorderSide(
                                          color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                                          width: 1.0,
                                        ),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                        minimumSize: const Size(0, 34),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.chevron_left_rounded, size: 16),
                                          SizedBox(width: 2),
                                          Text('Kembali', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  ElevatedButton(
                                    onPressed: _handleNext,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFF97316),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                      minimumSize: const Size(0, 34),
                                      elevation: 2,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          isLast ? 'Selesai' : 'Lanjut',
                                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                                        ),
                                        const SizedBox(width: 4),
                                        Icon(
                                          isLast ? Icons.check_circle_outline_rounded : Icons.arrow_forward_rounded,
                                          size: 15,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    if (placeAbove)
                      AnimatedPadding(
                        duration: const Duration(milliseconds: 320),
                        curve: Curves.easeInOutCubic,
                        padding: EdgeInsets.only(
                          left: (targetRect.left + (targetRect.width / 2) - 26).clamp(24.0, screenSize.width - 48.0),
                        ),
                        child: CustomPaint(
                          size: const Size(18, 9),
                          painter: _StudentTriangleNotchPainter(
                            isPointingUp: false,
                            color: isDark ? const Color(0xFF0F172A) : Colors.white,
                            borderColor: const Color(0xFFF97316).withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Custom painter to carve out a spotlight cutout in the dark barrier
class _StudentSpotlightOverlayPainter extends CustomPainter {
  final Rect targetRect;
  final double borderRadius;
  final Color overlayColor;
  final double pulseValue;

  _StudentSpotlightOverlayPainter({
    required this.targetRect,
    required this.borderRadius,
    required this.overlayColor,
    this.pulseValue = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final fullRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final backgroundPath = Path()..addRect(fullRect);
    final targetRRect = RRect.fromRectAndRadius(targetRect, Radius.circular(borderRadius));
    final cutoutPath = Path()..addRRect(targetRRect);

    final combinedPath = Path.combine(
      PathOperation.difference,
      backgroundPath,
      cutoutPath,
    );

    final paint = Paint()..color = overlayColor;
    canvas.drawPath(combinedPath, paint);

    // Glowing border with dynamic breathing pulse
    final glowAlpha = (0.55 + (0.35 * pulseValue)).clamp(0.0, 1.0);
    final borderPaint = Paint()
      ..color = const Color(0xFFF97316).withValues(alpha: glowAlpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8 + (0.8 * pulseValue);
    canvas.drawRRect(targetRRect, borderPaint);

    // Soft outer glow bloom
    final outerBloomPaint = Paint()
      ..color = const Color(0xFFF97316).withValues(alpha: 0.16 * pulseValue)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0;
    canvas.drawRRect(targetRRect.inflate(2.0), outerBloomPaint);
  }

  @override
  bool shouldRepaint(covariant _StudentSpotlightOverlayPainter oldDelegate) =>
      oldDelegate.targetRect != targetRect ||
      oldDelegate.overlayColor != overlayColor ||
      oldDelegate.pulseValue != pulseValue;
}

/// Custom painter for the speech bubble notch pointer arrow
class _StudentTriangleNotchPainter extends CustomPainter {
  final bool isPointingUp;
  final Color color;
  final Color? borderColor;

  _StudentTriangleNotchPainter({
    required this.isPointingUp,
    required this.color,
    this.borderColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    if (isPointingUp) {
      path.moveTo(size.width / 2, 0);
      path.lineTo(size.width, size.height);
      path.lineTo(0, size.height);
    } else {
      path.moveTo(0, 0);
      path.lineTo(size.width, 0);
      path.lineTo(size.width / 2, size.height);
    }
    path.close();
    canvas.drawPath(path, paint);

    if (borderColor != null) {
      final borderPaint = Paint()
        ..color = borderColor!
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      canvas.drawPath(path, borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _StudentTriangleNotchPainter oldDelegate) =>
      oldDelegate.isPointingUp != isPointingUp ||
      oldDelegate.color != color ||
      oldDelegate.borderColor != borderColor;
}
