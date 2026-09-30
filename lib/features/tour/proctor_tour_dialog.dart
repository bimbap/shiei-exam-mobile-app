import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../core/auth/token_storage.dart';
import '../../shared/theme/app_theme.dart';
import '../teacher_monitor/teacher_portal_controller.dart';

/// Target keys for pixel-perfect coachmark spotlight targeting on Proctor & Teacher screens.
class ProctorTourTargetKeys {
  final GlobalKey overviewMetricsKey;
  final GlobalKey quickActionsKey;
  final GlobalKey monitorSegmentKey;
  final GlobalKey studentSessionKey;
  final GlobalKey schoolCategoryKey;
  final GlobalKey deviceBindingKey;
  final GlobalKey proctorBadgeKey;
  final GlobalKey adminLicenseKey;

  ProctorTourTargetKeys({
    GlobalKey? overviewMetricsKey,
    GlobalKey? quickActionsKey,
    GlobalKey? monitorSegmentKey,
    GlobalKey? studentSessionKey,
    GlobalKey? schoolCategoryKey,
    GlobalKey? deviceBindingKey,
    GlobalKey? proctorBadgeKey,
    GlobalKey? adminLicenseKey,
  })  : overviewMetricsKey = overviewMetricsKey ?? GlobalKey(),
        quickActionsKey = quickActionsKey ?? GlobalKey(),
        monitorSegmentKey = monitorSegmentKey ?? GlobalKey(),
        studentSessionKey = studentSessionKey ?? GlobalKey(),
        schoolCategoryKey = schoolCategoryKey ?? GlobalKey(),
        deviceBindingKey = deviceBindingKey ?? GlobalKey(),
        proctorBadgeKey = proctorBadgeKey ?? GlobalKey(),
        adminLicenseKey = adminLicenseKey ?? GlobalKey();
}

class ProctorTourKeys {
  static GlobalKey overviewMetricsKey = GlobalKey();
  static GlobalKey quickActionsKey = GlobalKey();
  static GlobalKey monitorSegmentKey = GlobalKey();
  static GlobalKey studentSessionKey = GlobalKey();
  static GlobalKey schoolCategoryKey = GlobalKey();
  static GlobalKey deviceBindingKey = GlobalKey();
  static GlobalKey proctorBadgeKey = GlobalKey();
  static GlobalKey adminLicenseKey = GlobalKey();

  static void reset() {
    overviewMetricsKey = GlobalKey();
    quickActionsKey = GlobalKey();
    monitorSegmentKey = GlobalKey();
    studentSessionKey = GlobalKey();
    schoolCategoryKey = GlobalKey();
    deviceBindingKey = GlobalKey();
    proctorBadgeKey = GlobalKey();
    adminLicenseKey = GlobalKey();
  }
}

/// Comprehensive 2-phase Onboarding Tour for Teacher / Proctor / Admin Portal:
/// Phase 1: Welcome bottom sheet with 16:9 mascot banner & drop shadow.
/// Phase 2: Coachmark spotlight overlay with live tab switching and notch tooltip bubble.
class ProctorTourDialog extends StatefulWidget {
  final ProctorTourTargetKeys? targetKeys;
  final TeacherPortalController? controller;
  final VoidCallback? onTourCompleted;
  final void Function(int tabIndex, {String? statusFilter, String? dataCategory})? onSwitchTab;
  final bool startInCoachmark;
  final bool isAdmin;

  const ProctorTourDialog({
    super.key,
    this.targetKeys,
    this.controller,
    this.onTourCompleted,
    this.onSwitchTab,
    this.startInCoachmark = false,
    this.isAdmin = false,
  });

  static bool _isShowing = false;

  static Future<void> show(
    BuildContext context, {
    ProctorTourTargetKeys? targetKeys,
    TeacherPortalController? controller,
    bool forceShow = false,
    VoidCallback? onComplete,
    void Function(int tabIndex, {String? statusFilter, String? dataCategory})? onSwitchTab,
    bool startInCoachmark = false,
    bool isAdmin = false,
  }) async {
    if (_isShowing) return;
    if (!forceShow) {
      final isCompleted = await TokenStorage.isProctorTourCompleted(isAdmin: isAdmin);
      if (isCompleted) return;
    }

    if (!context.mounted) return;

    controller?.setTourActive(true);
    _isShowing = true;
    try {
      await showGeneralDialog(
        context: context,
        barrierDismissible: false,
        barrierLabel: 'ProctorTourModal',
        barrierColor: Colors.transparent,
        transitionDuration: Duration.zero,
        pageBuilder: (ctx, anim1, anim2) {
          return ProctorTourDialog(
            targetKeys: targetKeys,
            controller: controller,
            onTourCompleted: onComplete,
            onSwitchTab: onSwitchTab,
            startInCoachmark: startInCoachmark,
            isAdmin: isAdmin,
          );
        },
      );
    } finally {
      _isShowing = false;
      controller?.stopFraudAlertSound();
      controller?.setTourActive(false);
    }
  }

  @override
  State<ProctorTourDialog> createState() => _ProctorTourDialogState();
}

class _ProctorTourDialogState extends State<ProctorTourDialog> with TickerProviderStateMixin {
  late bool _isWelcomePhase;
  int _currentStep = 0;
  late AnimationController _welcomeAnimController;
  late Animation<Offset> _welcomeSlideAnimation;
  late Animation<double> _welcomeFadeAnimation;
  late final List<Map<String, dynamic>> _steps;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  Rect? _previousRect;
  bool _isTransitioning = false;

  @override
  void initState() {
    super.initState();
    final keys = widget.targetKeys;
    if (widget.isAdmin) {
      _steps = [
        {
          'title': 'Pusat Komando & Metrik Institusi',
          'desc':
              'Pantau kesehatan sistem ujian seluruh sekolah: total ujian berjalan, agregat siswa aktif, deteksi pelanggaran sistem, serta total basis data siswa & kelas.',
          'tip': 'Tips Admin: Angka metrik terhubung langsung ke Shiei Core backend dan disinkronkan real-time setiap 5 detik.',
          'tabIndex': 0,
          'key': keys?.overviewMetricsKey ?? ProctorTourKeys.overviewMetricsKey,
        },
        {
          'title': 'Alat Taktis & Kendali Darurat',
          'desc':
              'Aksi cepat administrator: Scan QR untuk unblock darurat, siarkan pengumuman massal ke seluruh tablet/HP siswa, dan tinjau seluruh PIN token ujian aktif.',
          'tip': 'Tips Admin: Gunakan "Siarkan Ralat" bila terdapat revisi soal atau instruksi darurat dari panitia ujian pusat.',
          'tabIndex': 0,
          'key': keys?.quickActionsKey ?? ProctorTourKeys.quickActionsKey,
        },
        {
          'title': 'Pusat Monitoring & Manajemen Ujian Global',
          'desc':
              'Kendali pelaksanaan ujian serentak: Live Monitor seluruh peserta lintas kelas, arsip Jadwal Ujian sekolah (buat jadwal baru & hapus massal), dan filter khusus Siswa Terkunci.',
          'tip': 'Tips Admin: Pada subtab Jadwal Ujian, tekan tombol "+" (FAB) untuk membuat jadwal ujian baru atau tekan lama kartu untuk multi-select hapus massal.',
          'tabIndex': 1,
          'statusFilter': 'all',
          'key': keys?.monitorSegmentKey ?? ProctorTourKeys.monitorSegmentKey,
        },
        {
          'title': 'Supervisi Otoritas & Tindakan Sesi',
          'desc':
              'Kendali otoritas sesi: pantau persentase baterai, IP perangkat, sisa waktu, serta riwayat pelanggaran. Lakukan Buka Kunci, Reset Sesi mengulang, atau Kick siswa.',
          'tip': 'Tips Admin: Opsi "Reset Sesi" digunakan jika siswa mengalami kendala fatal pada HP dan harus mengulang sesi dari awal di perangkat pengganti.',
          'tabIndex': 1,
          'statusFilter': 'all',
          'key': keys?.studentSessionKey ?? ProctorTourKeys.studentSessionKey,
        },
        {
          'title': 'Tata Kelola Data Induk & Pengguna Sekolah',
          'desc':
              'Kelola 4 pilar data institusi: Siswa, Guru & Staf, Kelas, dan Semua Pengguna. Tambah data massal dengan Import CSV/Excel atau gunakan Speed Dial "+" untuk input perorangan.',
          'tip': 'Tips Admin: Manfaatkan template CSV/Excel resmi sistem untuk mengimpor ratusan akun siswa & guru dalam sekali klik.',
          'tabIndex': 2,
          'dataCategory': 'students',
          'key': keys?.schoolCategoryKey ?? ProctorTourKeys.schoolCategoryKey,
        },
        {
          'title': 'Validasi Perangkat',
          'desc':
              'Kebijakan keamanan Shiei mengikat 1 akun siswa pada 1 HP resmi. Pantau status ikatan HP seluruh sekolah dan reset ikatan bila ada pergantian ponsel resmi.',
          'tip': 'Tips Admin: Filter "Belum Terikat" memudahkan panitia mengidentifikasi siswa yang belum melakukan uji coba perangkat sebelum hari H.',
          'tabIndex': 2,
          'dataCategory': 'students',
          'key': keys?.deviceBindingKey ?? ProctorTourKeys.deviceBindingKey,
        },
        {
          'title': 'Infrastruktur Server & Lisensi Sekolah',
          'desc':
              'Pantau status live koneksi URL backend Shiei Core serta sisa batas kuota siswa aktif pada tier lisensi institusi sekolah Anda.',
          'tip': 'Tips Admin: Pastikan status backend bertanda "TERHUBUNG" dan kuota lisensi mencukupi sebelum ujian serentak diselenggarakan.',
          'tabIndex': 3,
          'key': keys?.adminLicenseKey ?? ProctorTourKeys.adminLicenseKey,
        },
      ];
    } else {
      _steps = [
        {
          'title': 'Ringkasan & Metrik Pengawasan',
          'desc':
              'Pantau kesiapan ruangan ujian Anda: jumlah sesi ujian aktif hari ini, siswa yang sedang mengerjakan, dan peringatan jika ada peserta yang terkunci.',
          'tip': 'Tips Guru: Perhatikan kotak "TERKUNCI / ALERT". Angka merah menandakan ada peserta di ruangan yang mencoba curang.',
          'tabIndex': 0,
          'key': keys?.overviewMetricsKey ?? ProctorTourKeys.overviewMetricsKey,
        },
        {
          'title': 'Aksi Taktis Pengawas Ruangan',
          'desc':
              'Alat taktis pengawas di meja ujian: Scan QR code siswa via kamera untuk buka kunci instan tanpa repot mencari nama siswa di daftar.',
          'tip': 'Tips Guru: Scan QR siswa sangat ampuh saat keliling ruangan — arahkan kamera ke layar siswa dan ketuk buka kunci dalam 2 detik.',
          'tabIndex': 0,
          'key': keys?.quickActionsKey ?? ProctorTourKeys.quickActionsKey,
        },
        {
          'title': 'Ruang Pantau & Pembuatan Jadwal Ujian',
          'desc':
              'Beralih antara Live Monitor peserta yang sedang aktif, subtab Jadwal Ujian (tekan tombol "+" FAB untuk membuat ujian baru mapel Anda), dan daftar Pelanggaran.',
          'tip': 'Tips Guru: Guru dapat membuat jadwal ujian kapan saja untuk mata pelajaran yang diampu lewat tombol "+" di subtab Jadwal Ujian.',
          'tabIndex': 1,
          'statusFilter': 'all',
          'key': keys?.monitorSegmentKey ?? ProctorTourKeys.monitorSegmentKey,
        },
        {
          'title': 'Penanganan & Buka Kunci Siswa',
          'desc':
              'Setiap kartu peserta menampilkan status baterai, countdown, dan alasan kunci. Ketuk kartu siswa untuk Buka Kunci (Unlock) agar siswa dapat lanjut ujian.',
          'tip': 'Tips Guru: Buka Kunci mengizinkan siswa melanjutkan ujian dengan aman — seluruh jawaban yang telah diisi tetap tersimpan utuh.',
          'tabIndex': 1,
          'statusFilter': 'all',
          'key': keys?.studentSessionKey ?? ProctorTourKeys.studentSessionKey,
        },
        {
          'title': 'Direktori Siswa & Ruang Kelas Binaan',
          'desc':
              'Akses direktori peserta ujian: cari profil siswa, periksa status kesiapan akun, serta kelola dan pantau data siswa khusus kelas binaan bagi Wali Kelas.',
          'tip': 'Tips Guru: Wali Kelas dapat memeriksa kelengkapan data siswa dan memastikan seluruh peserta binaan siap menghadapi ujian.',
          'tabIndex': 2,
          'dataCategory': 'students',
          'key': keys?.schoolCategoryKey ?? ProctorTourKeys.schoolCategoryKey,
        },
        {
          'title': 'Ikatan HP Siswa (Validasi Sesi Tunggal)',
          'desc':
              'Akun siswa terkunci pada HP resmi yang didaftarkan. Jika ada siswa di ruangan yang HP-nya drop/rusak dan harus pakai HP cadangan, reset ikatan HP di sini.',
          'tip': 'Tips Guru: Setelah ikatan di-reset, siswa dapat login di HP cadangan pengawas dan perangkat tersebut otomatis terikat secara aman.',
          'tabIndex': 2,
          'dataCategory': 'students',
          'key': keys?.deviceBindingKey ?? ProctorTourKeys.deviceBindingKey,
        },
        {
          'title': 'Kartu Pengawas Ujian Resmi',
          'desc':
              'Identitas digital resmi pengawas ujian yang sah dan terverifikasi untuk bertugas mengawal integritas dan ketertiban di ruangan ujian sekolah.',
          'tip': 'Tips Guru: Selamat bertugas! Shiei Exam siap mengawal kejujuran dan ketertiban pelaksanaan ujian di sekolah Anda.',
          'tabIndex': 3,
          'key': keys?.proctorBadgeKey ?? ProctorTourKeys.proctorBadgeKey,
        },
      ];
    }

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
    _pulseAnimation = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    );

    if (_isWelcomePhase) {
      _welcomeAnimController.forward();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startCoachmarkTour();
      });
    }
  }

  @override
  void dispose() {
    widget.controller?.stopFraudAlertSound();
    widget.controller?.setTourActive(false);
    _pulseController.dispose();
    _welcomeAnimController.dispose();
    super.dispose();
  }

  Future<void> _scrollToKey(GlobalKey? key) async {
    final ctx = key?.currentContext;
    if (ctx != null && ctx.mounted) {
      try {
        final scrollable = Scrollable.maybeOf(ctx);
        if (scrollable != null && axisDirectionToAxis(scrollable.axisDirection) == Axis.vertical) {
          await Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOutCubic,
            alignment: 0.25,
          );
        }
      } catch (_) {}
    }
  }

  Future<void> _startCoachmarkTour() async {
    _previousRect = null;
    setState(() {
      _isWelcomePhase = false;
      _currentStep = 0;
    });
    final step = _steps[0];
    final int targetTab = step['tabIndex'] as int;
    final String? statusFilter = step['statusFilter'] as String?;
    final String? dataCategory = step['dataCategory'] as String?;
    widget.onSwitchTab?.call(targetTab, statusFilter: statusFilter, dataCategory: dataCategory);
    await Future.delayed(const Duration(milliseconds: 220));
    final key = step['key'] as GlobalKey?;
    await _scrollToKey(key);
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _handleNext() async {
    if (_isTransitioning) return;
    if (_currentStep < _steps.length - 1) {
      _isTransitioning = true;
      try {
        final currentRect = _getTargetRect(context, _steps[_currentStep]);
        _previousRect = currentRect;
        final nextStep = _currentStep + 1;
        final nextStepData = _steps[nextStep];
        final currentTab = _steps[_currentStep]['tabIndex'] as int?;
        final targetTab = nextStepData['tabIndex'] as int?;
        final String? statusFilter = nextStepData['statusFilter'] as String?;
        final String? dataCategory = nextStepData['dataCategory'] as String?;

        final targetKey = nextStepData['key'] as GlobalKey?;
        final isMonitorSegmentStep = targetKey == (widget.targetKeys?.monitorSegmentKey ?? ProctorTourKeys.monitorSegmentKey) || nextStep == 2;

        if (isMonitorSegmentStep) {
          widget.controller?.playTourFraudAudioDemo();
        } else {
          widget.controller?.stopFraudAlertSound();
        }

        if (targetTab != null && (targetTab != currentTab || statusFilter != null || dataCategory != null)) {
          widget.onSwitchTab?.call(targetTab, statusFilter: statusFilter, dataCategory: dataCategory);
          await Future.delayed(const Duration(milliseconds: 260));
        } else {
          await Future.delayed(const Duration(milliseconds: 80));
        }

        await _scrollToKey(targetKey);
        await WidgetsBinding.instance.endOfFrame;
        if (mounted) {
          setState(() => _currentStep = nextStep);
        }
      } finally {
        _isTransitioning = false;
      }
    } else {
      await _handleFinish();
    }
  }

  Future<void> _handlePrevious() async {
    if (_isTransitioning) return;
    if (_currentStep > 0) {
      _isTransitioning = true;
      try {
        final currentRect = _getTargetRect(context, _steps[_currentStep]);
        _previousRect = currentRect;
        final prevStep = _currentStep - 1;
        final prevStepData = _steps[prevStep];
        final currentTab = _steps[_currentStep]['tabIndex'] as int?;
        final targetTab = prevStepData['tabIndex'] as int?;
        final String? statusFilter = prevStepData['statusFilter'] as String?;
        final String? dataCategory = prevStepData['dataCategory'] as String?;

        final targetKey = prevStepData['key'] as GlobalKey?;
        final isMonitorSegmentStep = targetKey == (widget.targetKeys?.monitorSegmentKey ?? ProctorTourKeys.monitorSegmentKey) || prevStep == 2;

        if (isMonitorSegmentStep) {
          widget.controller?.playTourFraudAudioDemo();
        } else {
          widget.controller?.stopFraudAlertSound();
        }

        if (targetTab != null && (targetTab != currentTab || statusFilter != null || dataCategory != null)) {
          widget.onSwitchTab?.call(targetTab, statusFilter: statusFilter, dataCategory: dataCategory);
          await Future.delayed(const Duration(milliseconds: 260));
        } else {
          await Future.delayed(const Duration(milliseconds: 80));
        }

        await _scrollToKey(targetKey);
        await WidgetsBinding.instance.endOfFrame;
        if (mounted) {
          setState(() => _currentStep = prevStep);
        }
      } finally {
        _isTransitioning = false;
      }
    }
  }

  bool _isClosing = false;

  Future<void> _handleSkip() async {
    if (_isClosing) return;
    _isClosing = true;
    widget.controller?.stopFraudAlertSound();
    widget.controller?.setTourActive(false);
    await TokenStorage.setProctorTourCompleted(true, isAdmin: widget.isAdmin);
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
    widget.controller?.stopFraudAlertSound();
    widget.controller?.setTourActive(false);
    await TokenStorage.setProctorTourCompleted(true, isAdmin: widget.isAdmin);
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
      onPopInvoked: (didPop) async {
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
        // 1. Dark backdrop scrim
        FadeTransition(
          opacity: _welcomeFadeAnimation,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _handleSkip,
            child: Container(
              color: Colors.black.withOpacity(0.75),
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

                    // Framed Mascot Illustration with deep bottom-left drop shadow
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
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: widget.isAdmin
                                  ? const Color(0xFF3B82F6).withValues(alpha: 0.15)
                                  : const Color(0xFFEA580C).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: widget.isAdmin
                                    ? const Color(0xFF3B82F6).withValues(alpha: 0.4)
                                    : const Color(0xFFEA580C).withValues(alpha: 0.4),
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  widget.isAdmin ? Icons.admin_panel_settings_rounded : Icons.shield_rounded,
                                  size: 13,
                                  color: widget.isAdmin ? const Color(0xFF3B82F6) : const Color(0xFFEA580C),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  widget.isAdmin ? 'PANDUAN ADMINISTRATOR' : 'PANDUAN GURU & STAFF',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                    color: widget.isAdmin ? const Color(0xFF3B82F6) : const Color(0xFFEA580C),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            widget.isAdmin
                                ? 'Selamat Datang di Portal Administrator'
                                : 'Selamat Datang di Portal Pengawas Ujian',
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
                            widget.isAdmin
                                ? 'Panduan komprehensif tata kelola pusat komando ujian, struktur data induk sekolah, dan kuota lisensi institusi.'
                                : 'Panduan taktis pengawasan live ujian ruangan, aksi cepat scan QR buka kunci, dan penanganan ketertiban peserta.',
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
                                  child: Text(
                                    widget.isAdmin ? 'Mulai Tur' : 'Mulai Tur',
                                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
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
    final key = step['key'] as GlobalKey?;
    final ctx = key?.currentContext;
    if (ctx != null && ctx.mounted) {
      final renderBox = ctx.findRenderObject() as RenderBox?;
      if (renderBox != null && renderBox.hasSize && renderBox.attached) {
        final screenSize = MediaQuery.of(context).size;
        final offset = renderBox.localToGlobal(Offset.zero);
        final size = renderBox.size;
        final rawRect = (offset & size).inflate(6);

        final clampLeft = rawRect.left.clamp(8.0, screenSize.width - 32.0);
        final clampRight = rawRect.right.clamp(clampLeft + 24.0, screenSize.width - 8.0);
        final clampTop = rawRect.top.clamp(0.0, screenSize.height - 40.0);
        final clampBottom = rawRect.bottom.clamp(clampTop + 20.0, screenSize.height);

        return Rect.fromLTRB(clampLeft, clampTop, clampRight, clampBottom);
      }
    }

    // High-precision fallback calculation
    final screenSize = MediaQuery.of(context).size;
    final topPadding = MediaQuery.of(context).padding.top;
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
    final placeAbove = (targetRect.bottom + 260 > screenSize.height - 70);

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
                    painter: _ProctorSpotlightOverlayPainter(
                      targetRect: rect,
                      borderRadius: 16,
                      overlayColor: Colors.black.withValues(alpha: 0.78),
                      pulseValue: _pulseAnimation.value,
                      isAdmin: widget.isAdmin,
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
                          left: (targetRect.left + (targetRect.width / 2) - 25.0).clamp(12.0, screenSize.width - 56.0),
                        ),
                        child: CustomPaint(
                          size: const Size(18, 9),
                          painter: _ProctorTriangleNotchPainter(
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
                      color: const Color(0xFFF97316).withOpacity(isDark ? 0.45 : 0.35),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(isDark ? 0.6 : 0.18),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                      BoxShadow(
                        color: const Color(0xFFF97316).withOpacity(0.12),
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
                          Row(
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
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
                                decoration: BoxDecoration(
                                  color: widget.isAdmin
                                      ? const Color(0xFF3B82F6).withValues(alpha: 0.15)
                                      : const Color(0xFF10B981).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: widget.isAdmin
                                        ? const Color(0xFF3B82F6).withValues(alpha: 0.35)
                                        : const Color(0xFF10B981).withValues(alpha: 0.35),
                                    width: 0.8,
                                  ),
                                ),
                                child: Text(
                                  widget.isAdmin ? 'ADMIN' : 'GURU & STAFF',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                    color: widget.isAdmin ? const Color(0xFF2563EB) : const Color(0xFF059669),
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ),
                            ],
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

                      // Mascot Avatar & Step Title
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: const Color(0xFFF97316).withOpacity(0.7), width: 1.5),
                            ),
                            child: ClipOval(
                              child: Image.asset(
                                'assets/images/shiei_proctor_male_half.jpg',
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
                            color: const Color(0xFFF97316).withOpacity(isDark ? 0.3 : 0.25),
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
                                duration: const Duration(milliseconds: 200),
                                margin: const EdgeInsets.only(right: 4),
                                width: isCurrent ? 16 : 5,
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
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    side: BorderSide(
                                      color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                                    ),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  onPressed: _handlePrevious,
                                  child: Text(
                                    'Kembali',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFF97316),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  elevation: 2,
                                ),
                                onPressed: _handleNext,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      isLast ? 'Selesai' : 'Lanjut',
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(
                                      isLast ? Icons.check_rounded : Icons.arrow_forward_rounded,
                                      size: 14,
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
                      left: (targetRect.left + (targetRect.width / 2) - 25.0).clamp(12.0, screenSize.width - 56.0),
                    ),
                    child: CustomPaint(
                      size: const Size(18, 9),
                      painter: _ProctorTriangleNotchPainter(
                        isPointingUp: false,
                        color: isDark ? const Color(0xFF0F172A) : Colors.white,
                        borderColor: const Color(0xFFF97316).withOpacity(0.6),
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

/// Custom painter to cut out the spotlight hole and draw an illuminated accent border
class _ProctorSpotlightOverlayPainter extends CustomPainter {
  final Rect targetRect;
  final double borderRadius;
  final Color overlayColor;
  final double pulseValue;
  final bool isAdmin;

  _ProctorSpotlightOverlayPainter({
    required this.targetRect,
    required this.borderRadius,
    required this.overlayColor,
    this.pulseValue = 1.0,
    this.isAdmin = false,
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

    final themeColor = isAdmin ? const Color(0xFF3B82F6) : const Color(0xFFF97316);

    // Glowing border with dynamic breathing pulse
    final glowAlpha = (0.55 + (0.35 * pulseValue)).clamp(0.0, 1.0);
    final borderPaint = Paint()
      ..color = themeColor.withValues(alpha: glowAlpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8 + (0.8 * pulseValue);
    canvas.drawRRect(targetRRect, borderPaint);

    // Soft outer glow bloom
    final outerBloomPaint = Paint()
      ..color = themeColor.withValues(alpha: 0.16 * pulseValue)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0;
    canvas.drawRRect(targetRRect.inflate(2.0), outerBloomPaint);
  }

  @override
  bool shouldRepaint(covariant _ProctorSpotlightOverlayPainter oldDelegate) =>
      oldDelegate.targetRect != targetRect ||
      oldDelegate.overlayColor != overlayColor ||
      oldDelegate.pulseValue != pulseValue ||
      oldDelegate.isAdmin != isAdmin;
}

/// Custom painter for speech bubble notch pointer arrow
class _ProctorTriangleNotchPainter extends CustomPainter {
  final bool isPointingUp;
  final Color color;
  final Color? borderColor;

  _ProctorTriangleNotchPainter({
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
  bool shouldRepaint(covariant _ProctorTriangleNotchPainter oldDelegate) =>
      oldDelegate.isPointingUp != isPointingUp ||
      oldDelegate.color != color ||
      oldDelegate.borderColor != borderColor;
}
