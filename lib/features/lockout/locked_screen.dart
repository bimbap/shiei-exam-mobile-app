import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../config/routes.dart';
import '../../core/api/api_client.dart';
import '../../core/api/endpoints.dart';
import '../../core/auth/token_storage.dart';
import '../../core/lockdown/alarm_player_service.dart';
import '../../core/lockdown/lockdown_service.dart';
import '../../core/lockdown/volume_lock_service.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/app_notification.dart';

class LockedScreen extends StatefulWidget {
  final Map<String, dynamic>? arguments;

  const LockedScreen({super.key, this.arguments});

  @override
  State<LockedScreen> createState() => _LockedScreenState();
}

class _LockedScreenState extends State<LockedScreen> {
  final ApiClient _api = ApiClient();
  bool _isChecking = false;
  bool _isAlarmMuted = false;
  bool _isAntiAlarmBypassed = false;
  int? _examId;
  Timer? _autoPollTimer;
  Map<String, dynamic>? _currentUser;
  String? _qrPayload;
  bool _isQrExpanded = false;

  void _toggleQr() {
    HapticFeedback.lightImpact();
    setState(() {
      _isQrExpanded = !_isQrExpanded;
    });
  }

  @override
  void initState() {
    super.initState();
    final rawId = widget.arguments?['exam_id'];
    _examId = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
    _loadStudentData();

    // Restore normal system bars and status overlay upon ejection
    VolumeLockService.setKioskSystemBarsBlocked(false);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
    AppTheme.applySystemOverlayStyle();
    
    // Check if debug anti-alarm bypass is active
    if (kDebugMode) {
      TokenStorage.isAntiAlarmBypassEnabled().then((bypassed) {
        if (bypassed && mounted) {
          setState(() {
            _isAlarmMuted = true;
            _isAntiAlarmBypassed = true;
          });
        }
      });
    }

    // Ensure the loud security siren continues blasting continuously (unless bypassed in debug)
    // lockHardwareVolume: false allows the student to lower volume with physical volume buttons
    AlarmPlayerService.playSiren(lockHardwareVolume: false);

    // Auto-poll unlock status every 4 seconds — only for anti-cheat lockouts, NOT for proctor_kick (terminated)
    final eventType = widget.arguments?['event_type'] ?? '';
    final bool isProctorKick = eventType == 'proctor_kick';
    if (_examId != null && !isProctorKick) {
      _autoPollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
        if (!_isChecking && mounted) {
          _silentCheckUnlock();
        }
      });
    }
  }

  Future<void> _loadStudentData() async {
    try {
      final user = await TokenStorage.getUser();
      if (user != null && mounted) {
        setState(() {
          _currentUser = user;
          final studentId = user['id'];
          final studentName = user['name'] ?? 'Siswa';
          final nisn = user['nisn'] ?? user['username'] ?? '-';
          _qrPayload = jsonEncode({
            'app': 'shiei',
            'action': 'unblock',
            'exam_id': _examId ?? 0,
            'student_id': studentId,
            'name': studentName,
            'nisn': nisn,
            'time': DateTime.now().millisecondsSinceEpoch,
          });
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _autoPollTimer?.cancel();
    AppNotification.hide();
    AlarmPlayerService.stopSiren();
    LockdownService().resetViolationState();
    AppTheme.applySystemOverlayStyle();
    super.dispose();
  }

  /// Silent background polling without blocking the UI
  Future<void> _silentCheckUnlock() async {
    if (_examId == null) return;
    try {
      final devCharging = await VolumeLockService.isDeviceCharging();
      final bat = await VolumeLockService.getBatteryLevel();
      final net = await VolumeLockService.getNetworkType();
      final res = await _api.get(
        ApiEndpoints.progressByExam(_examId!),
        queryParameters: {
          'is_charging': devCharging ? 1 : 0,
          'battery_level': bat,
          'network_type': net,
        },
      );
      final progress = res.data['data'];
      if (progress == null) return;

      final dynamic rawLocked = progress['is_locked'];
      final bool isLocked = rawLocked == true ||
          rawLocked == 1 ||
          rawLocked == '1' ||
          progress['status'] == 'locked' ||
          progress['status'] == 'terminated';
      final bool wasUnlocked = progress['was_unlocked'] == true ||
          progress['unlocked_at'] != null;

      if (!isLocked && wasUnlocked && mounted) {
        _handleUnlockedSuccess();
      }
    } catch (_) {}
  }

  Future<void> _checkUnlockStatus() async {
    if (_examId == null) {
      _returnToExamList();
      return;
    }

    setState(() => _isChecking = true);

    try {
      final devCharging = await VolumeLockService.isDeviceCharging();
      final bat = await VolumeLockService.getBatteryLevel();
      final net = await VolumeLockService.getNetworkType();
      final res = await _api.get(
        ApiEndpoints.progressByExam(_examId!),
        queryParameters: {
          'is_charging': devCharging ? 1 : 0,
          'battery_level': bat,
          'network_type': net,
        },
      );
      setState(() => _isChecking = false);

      final progress = res.data['data'];
      final dynamic rawLocked = progress != null ? progress['is_locked'] : true;
      final bool isLocked = progress == null ||
          rawLocked == true ||
          rawLocked == 1 ||
          rawLocked == '1' ||
          progress['status'] == 'locked' ||
          progress['status'] == 'terminated';
      final bool wasUnlocked = progress != null &&
          (progress['was_unlocked'] == true || progress['unlocked_at'] != null);

      if (!isLocked && wasUnlocked && mounted) {
        _handleUnlockedSuccess();
      } else if (mounted) {
        AppNotification.showError(
          context,
          'Ujian Masih Terkunci',
          subtitle: 'Silakan temui pengawas di ruang ujian untuk membuka sesi.',
        );
      }
    } catch (_) {
      setState(() => _isChecking = false);
      if (mounted) {
        AppNotification.showError(
          context,
          'Pemeriksaan Gagal',
          subtitle: 'Periksa koneksi ke server ujian.',
        );
      }
    }
  }

  void _handleUnlockedSuccess() {
    _autoPollTimer?.cancel();
    AlarmPlayerService.stopSiren();
    LockdownService().resetViolationState();
    final isDark = AppTheme.isDark(context);
    final dialogBg = isDark ? AppTheme.surfaceDark : Colors.white;
    final dialogBorder = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final contentColor = isDark ? AppTheme.textSecondary : const Color(0xFF475569);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: dialogBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: dialogBorder),
        ),
        title: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: AppTheme.accentGreen, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Kunci Telah Dibuka!', style: TextStyle(color: titleColor, fontSize: 17, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        content: Text(
          'Pengawas telah membuka kunci sesi ujian Anda. Anda sekarang dapat memulai kembali ujian.',
          style: TextStyle(color: contentColor, fontSize: 13, height: 1.4),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _returnToExamList();
            },
            child: const Text('Kembali ke Daftar Ujian'),
          ),
        ],
      ),
    );
  }

  void _returnToExamList() {
    _autoPollTimer?.cancel();
    AlarmPlayerService.stopSiren();
    LockdownService().resetViolationState();
    AppTheme.applySystemOverlayStyle();
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.examList, (r) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final rawEventType = widget.arguments?['event_type'] ?? 'other';
    final rawDetails = widget.arguments?['details'] ??
        widget.arguments?['lock_reason'] ??
        'Aplikasi kehilangan fokus atau terjadi pelanggaran sistem.';

    String formatViolationTitle(String type) {
      switch (type) {
        case 'screenshot_attempt':
          return 'Percobaan Tangkapan Layar (Screenshot)';
        case 'app_minimize':
          return 'Keluar dari Aplikasi Ujian';
        case 'tab_switch':
        case 'loss_of_focus':
          return 'Peralihan Aplikasi / Kehilangan Fokus';
        case 'split_screen':
          return 'Layar Terbelah (Split Screen)';
        case 'bluetooth_enabled':
          return 'Koneksi Bluetooth Aktif';
        case 'external_display':
          return 'Layar Eksternal / Screen Mirroring Tersambung';
        case 'overlay_detected':
          return 'Aplikasi Overlay / Tirai Notifikasi';
        case 'notification_pulldown':
          return 'Membuka Notifikasi Sistem';
        case 'volume_tamper':
          return 'Manipulasi Volume Suara';
        case 'phone_call_detected':
          return 'Panggilan Suara / Telepon Aktif';
        case 'proctor_kick':
          return 'Dikeluarkan oleh Pengawas Ujian';
        default:
          return 'Pelanggaran Keamanan Kiosk';
      }
    }

    String formatViolationDescription(String type, String details) {
      switch (type) {
        case 'proctor_kick':
          return details.isNotEmpty ? details : 'Sesi ujian Anda telah dihentikan secara langsung oleh Pengawas Ujian di ruang monitoring.';
        case 'phone_call_detected':
          return 'Sistem mendeteksi adanya panggilan suara atau telepon yang aktif saat ujian berlangsung.';
        case 'screenshot_attempt':
          return 'Sistem mendeteksi upaya pengambilan tangkapan layar (screenshot/screen recording). Demi integritas ujian, tindakan ini dilarang keras.';
        case 'app_minimize':
          return 'Siswa meminimalkan atau keluar dari aplikasi ujian ke menu beranda HP.';
        case 'tab_switch':
        case 'loss_of_focus':
          return 'Aplikasi ujian kehilangan fokus utama karena beralih ke aplikasi lain, menekan tombol recent apps, atau membuka jendela lain.';
        case 'split_screen':
          return 'Sistem mendeteksi pembagian layar (split-screen / multi-window) saat ujian berlangsung.';
        case 'bluetooth_enabled':
          return 'Koneksi Bluetooth terdeteksi aktif saat ujian berjalan.';
        case 'external_display':
          return 'Kabel HDMI, adapter display, atau screen mirroring nirkabel terdeteksi tersambung ke perangkat.';
        case 'overlay_detected':
          return 'Aplikasi overlay atau tirai notifikasi terdeteksi di atas layar ujian. Pastikan tidak ada aplikasi mengambang (floating app, bubble chat, atau translation overlay) yang aktif.';
        case 'notification_pulldown':
          return 'Bilah status atau panel notifikasi ditarik ke bawah saat ujian sedang berlangsung.';
        default:
          return details;
      }
    }

    final displayTitle = formatViolationTitle(rawEventType);
    final displayDesc = formatViolationDescription(rawEventType, rawDetails);
    final pageBg = isDark ? const Color(0xFF140A0A) : AppTheme.backgroundLight;

    return PopScope(
      canPop: false, // Prevent physical back navigation while locked
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: AppTheme.systemOverlayStyle,
        child: Scaffold(
          backgroundColor: pageBg,
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Flashing Danger Icon with Concentric Bezel
                      Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          color: AppTheme.dangerRed.withOpacity(isDark ? 0.15 : 0.10),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppTheme.dangerRed.withOpacity(isDark ? 0.6 : 0.45),
                            width: 3,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.dangerRed.withOpacity(isDark ? 0.25 : 0.15),
                              blurRadius: 32,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        child: Icon(
                          rawEventType == 'proctor_kick' ? Icons.person_off_rounded : Icons.lock_person_rounded,
                          size: 46,
                          color: AppTheme.dangerRed,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Title
                      Text(
                        rawEventType == 'proctor_kick' ? 'SESI UJIAN DIHENTIKAN' : 'UJIAN TERKUNCI!',
                        style: const TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.dangerRed,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Subtitle
                      Text(
                        rawEventType == 'proctor_kick'
                            ? 'Pengawas ujian telah mengeluarkan Anda dari sesi ujian ini. Akses pengerjaan soal dihentikan.'
                            : 'Sistem mendeteksi aktivitas mencurigakan saat ujian berlangsung. Sesi ujian Anda telah dihentikan otomatis.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Violation Detail Box
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(15),
                        decoration: BoxDecoration(
                          color: isDark ? AppTheme.surfaceDark : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isDark ? AppTheme.dangerDark.withOpacity(0.7) : const Color(0xFFFECACA),
                          ),
                          boxShadow: isDark
                              ? []
                              : [
                                  BoxShadow(
                                    color: const Color(0xFFEF4444).withOpacity(0.06),
                                    blurRadius: 12,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.warning_amber_rounded,
                                  color: isDark ? AppTheme.accentYellow : const Color(0xFFD97706),
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    displayTitle,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? Colors.white : const Color(0xFF991B1B),
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              displayDesc,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Instructions Box
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isDark ? AppTheme.primaryShiei.withOpacity(0.08) : const Color(0xFFFFF7ED),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isDark ? AppTheme.primaryShiei.withOpacity(0.25) : const Color(0xFFFED7AA),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.directions_walk_rounded,
                              color: isDark ? AppTheme.primaryGlow : const Color(0xFFEA580C),
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                rawEventType == 'proctor_kick'
                                    ? 'Silakan temui Pengawas Ujian di meja pengawas untuk konfirmasi dan arahan lebih lanjut.'
                                    : 'Silakan bawa HP ini ke Pengawas Ujian untuk membuka status kunci ujian Anda.',
                                style: TextStyle(
                                  color: isDark ? Colors.white : const Color(0xFF9A3412),
                                  fontSize: 12,
                                  height: 1.35,
                                  fontWeight: isDark ? FontWeight.normal : FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // QR Code Unblock Card — only shown for anti-cheat lockouts, not proctor_kick
                      if (_qrPayload != null && rawEventType != 'proctor_kick') ...[
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 240),
                          curve: Curves.easeInOutCubic,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: isDark ? AppTheme.surfaceDark : Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: _isQrExpanded
                                  ? const Color(0xFF8B5CF6).withOpacity(isDark ? 0.6 : 0.4)
                                  : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _isQrExpanded
                                    ? const Color(0xFF8B5CF6).withOpacity(isDark ? 0.15 : 0.08)
                                    : Colors.black.withOpacity(isDark ? 0.25 : 0.05),
                                blurRadius: _isQrExpanded ? 18 : 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(20),
                            child: InkWell(
                              onTap: _toggleQr,
                              borderRadius: BorderRadius.circular(20),
                              splashColor: const Color(0xFF8B5CF6).withOpacity(0.08),
                              highlightColor: const Color(0xFF8B5CF6).withOpacity(0.04),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 16),
                                child: Column(
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF8B5CF6).withOpacity(0.12),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(Icons.qr_code_2_rounded, color: Color(0xFF8B5CF6), size: 19),
                                        ),
                                        const SizedBox(width: 8),
                                        const Text(
                                          'QR Buka Kunci Pengawas',
                                          style: TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      'Tunjukkan QR ini ke Pengawas untuk scan buka kunci instan',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    // Interactive Toggle Pill
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: _isQrExpanded
                                            ? const Color(0xFF8B5CF6).withOpacity(isDark ? 0.20 : 0.10)
                                            : const Color(0xFF8B5CF6).withOpacity(isDark ? 0.12 : 0.06),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: const Color(0xFF8B5CF6).withOpacity(_isQrExpanded ? 0.45 : 0.25),
                                          width: 1,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            _isQrExpanded ? Icons.visibility_off_rounded : Icons.qr_code_rounded,
                                            size: 14,
                                            color: const Color(0xFF8B5CF6),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            _isQrExpanded ? 'Sembunyikan QR' : 'Tampilkan QR',
                                            style: const TextStyle(
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF8B5CF6),
                                              letterSpacing: 0.2,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          AnimatedRotation(
                                            turns: _isQrExpanded ? 0.5 : 0.0,
                                            duration: const Duration(milliseconds: 240),
                                            curve: Curves.easeInOutCubic,
                                            child: const Icon(
                                              Icons.keyboard_arrow_down_rounded,
                                              size: 16,
                                              color: Color(0xFF8B5CF6),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Expandable QR Container
                                    ClipRect(
                                      child: AnimatedSize(
                                        duration: const Duration(milliseconds: 280),
                                        curve: Curves.easeInOutCubic,
                                        alignment: Alignment.topCenter,
                                        child: _isQrExpanded
                                            ? Column(
                                                children: [
                                                  const SizedBox(height: 14),
                                                  Container(
                                                    padding: const EdgeInsets.all(12),
                                                    decoration: BoxDecoration(
                                                      color: Colors.white,
                                                      borderRadius: BorderRadius.circular(16),
                                                      border: Border.all(color: const Color(0xFFCBD5E1)),
                                                      boxShadow: [
                                                        BoxShadow(
                                                          color: Colors.black.withOpacity(0.04),
                                                          blurRadius: 8,
                                                          offset: const Offset(0, 2),
                                                        ),
                                                      ],
                                                    ),
                                                    child: QrImageView(
                                                      data: _qrPayload!,
                                                      version: QrVersions.auto,
                                                      size: 175.0,
                                                      eyeStyle: const QrEyeStyle(
                                                        eyeShape: QrEyeShape.square,
                                                        color: Color(0xFF0F172A),
                                                      ),
                                                      dataModuleStyle: const QrDataModuleStyle(
                                                        dataModuleShape: QrDataModuleShape.square,
                                                        color: Color(0xFF0F172A),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 12),
                                                  Builder(
                                                    builder: (context) {
                                                      final String studentName = (_currentUser?['name'] ?? 'Siswa').toString().trim();
                                                      final String rawNisn = (_currentUser?['nisn'] ?? '').toString().trim();
                                                      final bool hasNisn = rawNisn.isNotEmpty && rawNisn != '-';

                                                      return Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                                        decoration: BoxDecoration(
                                                          color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                                                          borderRadius: BorderRadius.circular(10),
                                                          border: Border.all(
                                                            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                                                          ),
                                                        ),
                                                        child: hasNisn
                                                            ? Column(
                                                                mainAxisSize: MainAxisSize.min,
                                                                children: [
                                                                  Text(
                                                                    studentName,
                                                                    textAlign: TextAlign.center,
                                                                    style: TextStyle(
                                                                      fontSize: 12,
                                                                      fontWeight: FontWeight.bold,
                                                                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                                                                    ),
                                                                  ),
                                                                  const SizedBox(height: 2),
                                                                  Text(
                                                                    rawNisn,
                                                                    textAlign: TextAlign.center,
                                                                    style: TextStyle(
                                                                      fontSize: 10.5,
                                                                      fontWeight: FontWeight.w500,
                                                                      color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                                                                    ),
                                                                  ),
                                                                ],
                                                              )
                                                            : Text(
                                                                studentName,
                                                                textAlign: TextAlign.center,
                                                                style: TextStyle(
                                                                  fontSize: 11.5,
                                                                  fontWeight: FontWeight.w600,
                                                                  color: isDark ? Colors.white70 : const Color(0xFF334155),
                                                                ),
                                                              ),
                                                      );
                                                    },
                                                  ),
                                                ],
                                              )
                                            : const SizedBox.shrink(),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Primary Action: proctor_kick = go home; anti-cheat lockout = check unlock
                      if (rawEventType == 'proctor_kick') ...[  
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF334155),
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 50),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          icon: const Icon(Icons.home_rounded, size: 20),
                          label: const Text('Kembali ke Beranda Ujian'),
                          onPressed: _returnToExamList,
                        ),
                      ] else ...[  
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryShiei,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 50),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          icon: _isChecking
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : const Icon(Icons.refresh_rounded, size: 20),
                          label: const Text('Cek Status Buka Kunci dari Pengawas'),
                          onPressed: _isChecking ? null : _checkUnlockStatus,
                        ),
                      ],
                      const SizedBox(height: 12),

                      // Secondary Action: Mute or Restart Alarm Siren
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _isAlarmMuted
                                ? (isDark ? AppTheme.textSecondary : const Color(0xFF475569))
                                : (isDark ? AppTheme.dangerRed : const Color(0xFFDC2626)),
                            backgroundColor: _isAlarmMuted
                                ? (isDark ? Colors.transparent : Colors.white)
                                : (isDark ? AppTheme.dangerRed.withOpacity(0.12) : const Color(0xFFFEF2F2)),
                            side: BorderSide(
                              color: _isAlarmMuted
                                  ? (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1))
                                  : (isDark ? AppTheme.dangerRed.withOpacity(0.6) : const Color(0xFFFCA5A5)),
                              width: 1.5,
                            ),
                            minimumSize: const Size(double.infinity, 48),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          icon: Icon(
                            _isAlarmMuted ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                            size: 20,
                            color: _isAlarmMuted
                                ? (isDark ? AppTheme.textSecondary : const Color(0xFF475569))
                                : (isDark ? AppTheme.dangerRed : const Color(0xFFDC2626)),
                          ),
                          label: Text(
                            _isAlarmMuted ? 'Bunyikan Sirine Kembali' : 'Matikan Suara Alarm Sirine',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _isAlarmMuted
                                  ? (isDark ? AppTheme.textSecondary : const Color(0xFF475569))
                                  : (isDark ? Colors.white : const Color(0xFFB91C1C)),
                            ),
                          ),
                          onPressed: () async {
                            if (_isAlarmMuted) {
                              await AlarmPlayerService.playSiren(lockHardwareVolume: false, force: true);
                              if (!mounted || !context.mounted) return;
                              setState(() => _isAlarmMuted = false);
                              AppNotification.showWarning(
                                context,
                                'Sirine Dinyalakan',
                                subtitle: 'Suara sirine peringatan kembali aktif.',
                              );
                            } else {
                              await AlarmPlayerService.stopSiren();
                              if (!mounted || !context.mounted) return;
                              setState(() => _isAlarmMuted = true);
                              AppNotification.showInfo(
                                context,
                                'Sirine Dimatikan',
                                subtitle: 'Suara sirine peringatan telah dimatikan.',
                              );
                            }
                          },
                        ),
                      ),
                      if (_isAntiAlarmBypassed) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: const Color(0xFFEF4444).withValues(alpha: 0.35),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.volume_off_rounded, size: 14, color: Color(0xFFDC2626)),
                              const SizedBox(width: 6),
                              Text(
                                'DEBUG: Anti-Alarm Aktif (Sirine Dibisukan Otomatis)',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: isDark ? const Color(0xFFFCA5A5) : const Color(0xFFB91C1C),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        'Tip: Kamu juga bisa mengecilkan suara sirine langsung lewat tombol volume HP.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: isDark ? AppTheme.textSecondary.withOpacity(0.7) : const Color(0xFF94A3B8),
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Bottom Action: Return to Exam Home List (Preserves Login Session!)
                      TextButton.icon(
                        onPressed: _returnToExamList,
                        icon: Icon(
                          Icons.arrow_back_rounded,
                          size: 16,
                          color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                        ),
                        label: Text(
                          'Kembali ke Beranda Ujian',
                          style: TextStyle(
                            color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
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
  }
}
