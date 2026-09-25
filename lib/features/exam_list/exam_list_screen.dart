import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/routes.dart';
import '../../core/api/api_client.dart';
import '../../core/api/endpoints.dart';
import '../../core/auth/token_storage.dart';
import '../../core/lockdown/cheat_reporter.dart';
import '../../core/lockdown/volume_lock_service.dart';
import '../../core/notifications/exam_reminder_service.dart';
import '../../core/update/app_update_service.dart';
import '../../shared/dialogs/change_password_dialog.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/utils/format_utils.dart';
import '../../shared/widgets/app_exit_dialog.dart';
import '../../shared/widgets/app_notification.dart';
import '../../shared/widgets/fluid_curved_bottom_bar.dart';
import '../../shared/widgets/shiei_brand_logo.dart';
import '../../shared/widgets/shiei_skeleton.dart';
import '../tour/app_tour_dialog.dart';
import '../update/app_update_dialog.dart';
import 'exam_list_controller.dart';

class ExamListScreen extends StatefulWidget {
  const ExamListScreen({super.key});

  @override
  State<ExamListScreen> createState() => _ExamListScreenState();
}

class _ExamListScreenState extends State<ExamListScreen> {
  final _controller = ExamListController();
  final _api = ApiClient();
  int _currentTabIndex = 0;
  bool _hasCheckedStartupFlow = false;

  bool _isAudioFeedbackEnabled = true;

  final TextEditingController _examSearchController = TextEditingController();
  String _examSearchQuery = '';

  final TextEditingController _historySearchController = TextEditingController();
  String _historySearchQuery = '';

  late final TourTargetKeys _tourKeys = TourTargetKeys();

  @override
  void initState() {
    super.initState();
    AppExitDialog.resetLock();
    _controller.loadExams();
    CheatReporter.flushPendingViolations();
    _loadAudioFeedback();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ExamReminderService.requestPermission();
      _handleStartupFlow();
    });
  }

  Future<void> _loadAudioFeedback() async {
    final enabled = await TokenStorage.isAudioFeedbackEnabled();
    if (mounted) setState(() => _isAudioFeedbackEnabled = enabled);
  }

  void _handleStartupFlow() {
    if (_hasCheckedStartupFlow) return;
    _hasCheckedStartupFlow = true;

    Future.delayed(const Duration(milliseconds: 600), () async {
      if (!mounted) return;

      // 1. Version tracking
      const currentVersion = AppUpdateService.currentAppVersion;
      await TokenStorage.setLastAppVersion(currentVersion);
      await TokenStorage.setFirstOpenDone();

      // 2. Check for available updates from server first
      AppUpdateInfo? updateInfo;
      try {
        updateInfo = await AppUpdateService.instance.checkForUpdate();
      } catch (_) {}

      if (!mounted) return;

      // If there is an app update, show update dialog only! The tour must not show.
      if (updateInfo != null && updateInfo.hasUpdate) {
        AppUpdateDialog.show(context, updateInfo);
        return;
      }

      // 3. Tour check: Strictly 1x Per Account!
      final isTourCompleted = await TokenStorage.isMobileTourCompleted();
      if (!isTourCompleted && mounted) {
        AppTourDialog.show(
          context,
          targetKeys: _tourKeys,
          forceShow: false,
          onSwitchTab: (index) {
            if (mounted) {
              setState(() => _currentTabIndex = index);
              if (index == 1 && !_controller.hasLoadedHistory) {
                _controller.loadHistory(isManualRefresh: false);
              } else if (index == 2 && _controller.currentUser == null) {
                _controller.refreshProfile(isManualRefresh: false);
              }
            }
          },
          onComplete: () {
            if (mounted) setState(() => _currentTabIndex = 0);
          },
        );
      }
    });
  }

  @override
  void dispose() {
    _examSearchController.dispose();
    _historySearchController.dispose();
    _controller.dispose();
    super.dispose();
  }

  String _formatLockReason(String? reason) {
    if (reason == null || reason.trim().isEmpty) {
      return 'Sesi ujian terkunci karena pelanggaran keamanan. Silakan temui pengawas di ruang ujian untuk membuka kunci.';
    }
    final r = reason.trim();
    if (r.contains('Exam session is locked') || r.contains('security violation')) {
      return 'Sesi ujian terkunci karena pelanggaran keamanan. Silakan temui pengawas di ruang ujian untuk membuka kunci.';
    }
    switch (r) {
      case 'screenshot_attempt':
        return 'Percobaan tangkapan layar (screenshot) terdeteksi. Temui pengawas untuk membuka.';
      case 'app_minimize':
        return 'Meninggalkan atau meminimalkan aplikasi ujian. Temui pengawas untuk membuka.';
      case 'tab_switch':
      case 'loss_of_focus':
        return 'Aplikasi kehilangan fokus utama. Temui pengawas untuk membuka.';
      case 'split_screen':
        return 'Layar terbelah (split screen) terdeteksi. Temui pengawas untuk membuka.';
      case 'bluetooth_enabled':
        return 'Koneksi Bluetooth aktif saat ujian. Temui pengawas untuk membuka.';
      case 'external_display':
        return 'Layar eksternal tersambung ke perangkat. Temui pengawas untuk membuka.';
      case 'overlay_detected':
        return 'Aplikasi mengambang atau panel notifikasi ditarik. Temui pengawas untuk membuka.';
      case 'notification_pulldown':
        return 'Panel notifikasi sistem ditarik ke bawah. Temui pengawas untuk membuka.';
      case 'volume_tamper':
        return 'Manipulasi volume suara terdeteksi. Temui pengawas untuk membuka.';
      default:
        return r;
    }
  }

  /**
   * Pre-Flight Diagnostic Check:
   * Scans 5 security & hardware parameters before permitting student to enter an exam:
   * 1. Bluetooth (must be completely OFF)
   * 2. Battery (must be >= 20% to prevent mid-exam power cuts)
   * 3. Hardware Volume (100% capacity locked)
   * 4. Kiosk Pinning / Overlay Protection (Ready)
   * 5. Server Latency / Ping (School network stability)
   */
  Future<void> _showPreFlightDiagnosticsModal(Map<String, dynamic> exam) async {
    bool isBtOff = false;
    bool isNoCallActive = true;
    bool isNoExternalDisplay = true;
    bool isNoUsbDebugging = true;
    bool isUsbDebuggingDetected = false;
    bool isUsbHostConnected = false;
    bool isDeviceIntegrityOk = true;
    String integrityReason = '';
    int brightnessPercent = 50;
    bool isBrightnessOk = true;
    int batteryLevel = 100;
    bool isCharging = false;
    bool isBatteryOk = true;
    bool isVolumeReady = false;
    bool isOverlayReady = false;
    String? overlayReason;
    bool isServerOk = false;
    int latencyMs = 0;
    bool isChecking = true;
    int currentStep = 0; // 0..9 for each parameter, 10 when complete
    bool isInspecting = false;
    bool hasAutoStarted = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 600),
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            Future<void> runInspection({bool resetTouch = false}) async {
              if (isInspecting) return;
              isInspecting = true;

              setModalState(() {
                isChecking = true;
                currentStep = 0;
                isBtOff = false;
                isNoCallActive = true;
                isNoExternalDisplay = true;
                isNoUsbDebugging = true;
                isUsbDebuggingDetected = false;
                isUsbHostConnected = false;
                isDeviceIntegrityOk = true;
                integrityReason = '';
                isBrightnessOk = true;
                isBatteryOk = true;
                isVolumeReady = false;
                isOverlayReady = false;
                overlayReason = null;
                isServerOk = false;
              });

              // Only reset touch tracking if explicitly requested by manual rescan
              if (resetTouch) {
                await VolumeLockService.resetOverlayTouchDetection();
              }

              // Brief yield for smooth bottom-sheet entrance
              await Future.delayed(const Duration(milliseconds: 40));

              // Step 0: Bluetooth check (Must be OFF)
              try {
                final btEnabled = await VolumeLockService.isBluetoothEnabled();
                isBtOff = !btEnabled;
              } catch (_) {
                isBtOff = false;
              }
              if (!modalCtx.mounted) {
                isInspecting = false;
                return;
              }
              setModalState(() => currentStep = 1);
              await Future.delayed(const Duration(milliseconds: 50));

              // Step 1: Active Call check (Anti-Jockey)
              try {
                final isCallActive = await VolumeLockService.isPhoneCallActive();
                isNoCallActive = !isCallActive;
                final examId = exam['id'];
                if (examId != null) {
                  try {
                    await _api.post(
                      ApiEndpoints.phoneCallStatus,
                      data: {
                        'link_id': examId,
                        'is_on_call': isCallActive,
                      },
                    );
                  } catch (_) {}
                }
              } catch (_) {
                isNoCallActive = true;
              }
              if (!modalCtx.mounted) {
                isInspecting = false;
                return;
              }
              setModalState(() => currentStep = 2);
              await Future.delayed(const Duration(milliseconds: 50));

              // Step 2: External Display check (HDMI / Mirroring)
              try {
                final hasExternal = await VolumeLockService.isExternalDisplayConnected();
                isNoExternalDisplay = !hasExternal;
              } catch (_) {
                isNoExternalDisplay = true;
              }
              if (!modalCtx.mounted) {
                isInspecting = false;
                return;
              }
              setModalState(() => currentStep = 3);
              await Future.delayed(const Duration(milliseconds: 50));

              // Step 3: USB Debugging Check (Active Host Link Detection)
              try {
                final usbStatus = await VolumeLockService.getUsbDebuggingStatus();
                final isAdb = usbStatus['isAdbEnabled'] ?? false;
                final isUsbConnected = usbStatus['isUsbConnected'] ?? false;
                final isAdbActiveWithHost = usbStatus['isAdbActiveWithHost'] ?? false;

                isUsbDebuggingDetected = isAdb;
                isUsbHostConnected = isUsbConnected;

                if (kDebugMode) {
                  // Mode developer (debug build): selalu di-bypass agar proses development lancar
                  isNoUsbDebugging = true;
                } else {
                  // Mode release (siswa):
                  // HANYA dilarang jika kabel USB SEDANG terhubung ke komputer/laptop!
                  // Jika USB debugging ON di setelan tapi kabel TIDAK dicolok ke PC, TETAP LOLOS (Aman).
                  isNoUsbDebugging = !isAdbActiveWithHost;
                }
              } catch (_) {
                isNoUsbDebugging = true;
              }
              if (!modalCtx.mounted) {
                isInspecting = false;
                return;
              }
              setModalState(() => currentStep = 4);
              await Future.delayed(const Duration(milliseconds: 50));

              // Step 4: Security & System Integrity Check (Root, Frida, App Signature)
              try {
                final integrity = await VolumeLockService.checkSecurityIntegrity();
                final bool isDebug = integrity['isDebug'] == true;
                final bool isRoot = integrity['isRooted'] == true;
                final bool isFrida = integrity['isFrida'] == true;
                final bool isSigValid = integrity['isSignatureValid'] == true;

                if (isDebug) {
                  isDeviceIntegrityOk = true;
                } else {
                  isDeviceIntegrityOk = !isRoot && !isFrida && isSigValid;
                  if (isRoot) {
                    integrityReason = 'Perangkat Root terdeteksi';
                  } else if (isFrida) {
                    integrityReason = 'Frida hooking terdeteksi';
                  } else if (!isSigValid) {
                    integrityReason = 'Tanda tangan aplikasi tidak resmi';
                  }
                }
              } catch (_) {
                isDeviceIntegrityOk = true;
              }
              if (!modalCtx.mounted) {
                isInspecting = false;
                return;
              }
              setModalState(() => currentStep = 5);
              await Future.delayed(const Duration(milliseconds: 50));

              // Step 5: Screen Brightness check (Must be >= 40% minimum)
              try {
                final brightness = await VolumeLockService.getScreenBrightness();
                brightnessPercent = brightness;
                isBrightnessOk = (brightness >= 40);
              } catch (_) {
                brightnessPercent = 50;
                isBrightnessOk = true;
              }
              if (!modalCtx.mounted) {
                isInspecting = false;
                return;
              }
              setModalState(() => currentStep = 6);
              await Future.delayed(const Duration(milliseconds: 50));

              // Step 6: Battery & Charging check
              try {
                final bat = await VolumeLockService.getBatteryLevel();
                final devCharging = await VolumeLockService.isDeviceCharging();
                batteryLevel = bat;
                isCharging = devCharging;
                isBatteryOk = true; // Non-blocking: warning popup handled upon launch
              } catch (_) {
                batteryLevel = 100;
                isCharging = false;
                isBatteryOk = true;
              }
              if (!modalCtx.mounted) {
                isInspecting = false;
                return;
              }
              setModalState(() => currentStep = 7);
              await Future.delayed(const Duration(milliseconds: 50));

              // Step 7: Force volume
              try {
                await VolumeLockService.forceMaxVolume();
                isVolumeReady = true;
              } catch (_) {
                isVolumeReady = true;
              }
              if (!modalCtx.mounted) {
                isInspecting = false;
                return;
              }
              setModalState(() => currentStep = 8);
              await Future.delayed(const Duration(milliseconds: 50));

              // Step 8: Overlay, PiP & Floating Window protection
              try {
                await VolumeLockService.setOverlayProtection(true);
                final overlayResult = await VolumeLockService.detectFloatingWindowOrOverlay();
                final bool hasOverlay = overlayResult['has_overlay'] == true;
                if (hasOverlay) {
                  isOverlayReady = false;
                  overlayReason = overlayResult['reason']?.toString() ?? 'Tutup jendela mengambang / PiP sebelum ujian';
                } else {
                  isOverlayReady = true;
                  overlayReason = null;
                }
              } catch (_) {
                isOverlayReady = true;
                overlayReason = null;
              }
              if (!modalCtx.mounted) {
                isInspecting = false;
                return;
              }
              setModalState(() => currentStep = 9);
              await Future.delayed(const Duration(milliseconds: 50));

              // Step 9: Server latency ping
              final sw = Stopwatch()..start();
              try {
                await _api.get(ApiEndpoints.studentExams);
                sw.stop();
                latencyMs = sw.elapsedMilliseconds;
                isServerOk = true;
              } catch (_) {
                sw.stop();
                latencyMs = sw.elapsedMilliseconds;
                isServerOk = false;
              }

              if (modalCtx.mounted) {
                setModalState(() {
                  currentStep = 10;
                  isChecking = false;
                });
              }
              isInspecting = false;
            }

            // Run initial check once modal mounts (strictly single trigger)
            if (!hasAutoStarted) {
              hasAutoStarted = true;
              WidgetsBinding.instance.addPostFrameCallback((_) => runInspection());
            }

            final bool allPassed = isBtOff &&
                isNoCallActive &&
                isNoExternalDisplay &&
                isNoUsbDebugging &&
                isDeviceIntegrityOk &&
                isBrightnessOk &&
                isBatteryOk &&
                isVolumeReady &&
                isOverlayReady &&
                isServerOk;

            final isDark = AppTheme.isDark(modalCtx);
            final sheetBg = isDark ? AppTheme.surfaceDark : Colors.white;
            final sheetBorder = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
            final handleColor = isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1);
            final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
            final descColor = isDark ? Colors.white70 : const Color(0xFF475569);
            final listBg = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
            final listBorder = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);
            final listDivider = isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);

            return Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) async {
                if (!isChecking) {
                  final check = await VolumeLockService.detectFloatingWindowOrOverlay();
                  if (check['has_overlay'] == true && isOverlayReady) {
                    if (modalCtx.mounted) {
                      setModalState(() {
                        isOverlayReady = false;
                        overlayReason = check['reason']?.toString() ?? 'Jendela mengambang terdeteksi di atas layar';
                      });
                    }
                  }
                }
              },
              child: Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              decoration: BoxDecoration(
                color: sheetBg,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border(
                  top: BorderSide(color: sheetBorder, width: 1.5),
                ),
                boxShadow: isDark
                    ? null
                    : [
                        const BoxShadow(
                          color: Color(0x180F172A),
                          blurRadius: 24,
                          offset: Offset(0, -6),
                        ),
                      ],
              ),
              child: SafeArea(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.of(modalCtx).size.height * 0.88),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    // Handle pill
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: handleColor,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Title Header with Shiei-kun Scanner Mascot
                    Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppTheme.primaryShiei.withOpacity(0.12),
                            border: Border.all(
                              color: AppTheme.primaryShiei.withOpacity(0.6),
                              width: 1.8,
                            ),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.security_rounded,
                              color: AppTheme.primaryGlow,
                              size: 20,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Diagnostik Kesiapan Ujian',
                                    style: TextStyle(color: titleColor, fontSize: 16, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isChecking
                                          ? const Color(0xFFF59E0B).withOpacity(0.15)
                                          : (allPassed
                                              ? AppTheme.accentGreen.withOpacity(0.15)
                                              : AppTheme.dangerRed.withOpacity(0.15)),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      isChecking
                                          ? 'MEMERIKSA ${currentStep < 10 ? currentStep + 1 : 10}/10...'
                                          : (allPassed ? 'SIAP UJIAN' : 'BELUM SIAP'),
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.bold,
                                        color: isChecking
                                            ? const Color(0xFFF59E0B)
                                            : (allPassed ? AppTheme.accentGreen : AppTheme.dangerRed),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                exam['title'] ?? 'Pemeriksaan Kesiapan Ujian',
                                style: TextStyle(color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B), fontSize: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    Text(
                      'Sistem sedang memeriksa kondisi HP dan ketentuan ujian agar kamu dapat mengerjakan ujian dengan tertib dan lancar:',
                      style: TextStyle(color: descColor, fontSize: 12, height: 1.4),
                    ),
                    const SizedBox(height: 14),

                    // Diagnostic Items List
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: listBg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: listBorder),
                      ),
                      child: Column(
                        children: [
                          _buildDiagnosticRow(
                            icon: Icons.bluetooth_disabled_rounded,
                            title: 'Koneksi Bluetooth',
                            subtitle: currentStep == 0 && isChecking
                                ? 'Memeriksa hardware...'
                                : (currentStep < 0
                                    ? 'Menunggu antrean...'
                                    : (isBtOff ? 'MATI (Sesuai Standar)' : 'DILARANG! Harap matikan Bluetooth')),
                            isPassed: isBtOff,
                            isLoading: isChecking && currentStep == 0,
                            isPending: isChecking && currentStep < 0,
                            isDark: isDark,
                            onTap: !isBtOff ? () => VolumeLockService.openBluetoothSettings() : null,
                          ),
                          Divider(color: listDivider, height: 1),
                          _buildDiagnosticRow(
                            icon: Icons.phone_disabled_rounded,
                            title: 'Panggilan Telepon & Suara (VoIP)',
                            subtitle: currentStep == 1 && isChecking
                                ? 'Memeriksa panggilan seluler & VoIP (WhatsApp/Discord)...'
                                : (currentStep < 1
                                    ? 'Menunggu antrean...'
                                    : (isNoCallActive
                                        ? 'TIDAK ADA PANGGILAN (Aman)'
                                        : 'DILARANG! Tutup panggilan seluler / WhatsApp sebelum ujian')),
                            isPassed: isNoCallActive,
                            isLoading: isChecking && currentStep == 1,
                            isPending: isChecking && currentStep < 1,
                            isDark: isDark,
                          ),
                          Divider(color: listDivider, height: 1),
                          _buildDiagnosticRow(
                            icon: Icons.tv_off_rounded,
                            title: 'Layar Eksternal & Mirroring',
                            subtitle: currentStep == 2 && isChecking
                                ? 'Memeriksa display...'
                                : (currentStep < 2
                                    ? 'Menunggu antrean...'
                                    : (isNoExternalDisplay
                                        ? 'TIDAK TERHUBUNG (Aman)'
                                        : 'DILARANG! Lepas kabel display/mirroring')),
                            isPassed: isNoExternalDisplay,
                            isLoading: isChecking && currentStep == 2,
                            isPending: isChecking && currentStep < 2,
                            isDark: isDark,
                          ),
                          Divider(color: listDivider, height: 1),
                          _buildDiagnosticRow(
                            icon: Icons.usb_off_rounded,
                            title: 'USB Debugging (Mode Pengembang)',
                            subtitle: currentStep == 3 && isChecking
                                ? 'Memeriksa status sambungan USB...'
                                : (currentStep < 3
                                    ? 'Menunggu antrean...'
                                    : (kDebugMode
                                        ? (isUsbDebuggingDetected
                                            ? 'Mode Debug Developer (Bypass Aktif)'
                                            : 'NONAKTIF (Sesuai Standar)')
                                        : (isNoUsbDebugging
                                            ? (isUsbDebuggingDetected
                                                ? 'Opsi Pengembang Aktif (Kabel Tidak Terhubung — Aman)'
                                                : 'NONAKTIF (Sesuai Standar)')
                                            : 'DILARANG! Terhubung ke PC. Cabut Kabel USB.'))),
                            isPassed: isNoUsbDebugging,
                            isLoading: isChecking && currentStep == 3,
                            isPending: isChecking && currentStep < 3,
                            isDark: isDark,
                            onTap: !isNoUsbDebugging ? () => VolumeLockService.openDeveloperSettings() : null,
                          ),
                          Divider(color: listDivider, height: 1),
                          _buildDiagnosticRow(
                            icon: Icons.verified_user_rounded,
                            title: 'Integritas Sistem & Anti-Mod',
                            subtitle: currentStep == 4 && isChecking
                                ? 'Memverifikasi keaslian sistem...'
                                : (currentStep < 4
                                    ? 'Menunggu antrean...'
                                    : (isDeviceIntegrityOk
                                        ? 'TERVERIFIKASI RESMI (Aman)'
                                        : 'DILARANG! $integrityReason')),
                            isPassed: isDeviceIntegrityOk,
                            isLoading: isChecking && currentStep == 4,
                            isPending: isChecking && currentStep < 4,
                            isDark: isDark,
                          ),
                          Divider(color: listDivider, height: 1),
                          _buildDiagnosticRow(
                            icon: Icons.brightness_high_rounded,
                            title: 'Kecerahan Layar (Min. 40%)',
                            subtitle: currentStep == 5 && isChecking
                                ? 'Memeriksa sensor kecerahan...'
                                : (currentStep < 5
                                    ? 'Menunggu antrean...'
                                    : (isBrightnessOk
                                        ? '$brightnessPercent% (Sesuai Standar ≥ 40%)'
                                        : '$brightnessPercent% (Terlalu Redup! Harap naikkan ≥ 40%)')),
                            isPassed: isBrightnessOk,
                            isLoading: isChecking && currentStep == 5,
                            isPending: isChecking && currentStep < 5,
                            isDark: isDark,
                          ),
                          Divider(color: listDivider, height: 1),
                          _buildDiagnosticRow(
                            icon: isCharging
                                ? Icons.battery_charging_full_rounded
                                : (batteryLevel != -1 && batteryLevel <= 25
                                    ? Icons.battery_alert_rounded
                                    : Icons.battery_std_rounded),
                            title: 'Kapasitas Baterai & Daya',
                            subtitle: currentStep == 6 && isChecking
                                ? 'Memeriksa daya...'
                                : (currentStep < 6
                                    ? 'Menunggu antrean...'
                                    : (batteryLevel == -1
                                        ? 'Baterai Siaga'
                                        : isCharging
                                            ? '$batteryLevel% (Sedang Mengisi Daya — Aman)'
                                            : (batteryLevel <= 25
                                                ? '$batteryLevel% (Peringatan Baterai Rendah ≤ 25%)'
                                                : '$batteryLevel% (Baterai Aman)'))),
                            isPassed: true,
                            isWarning: !isCharging && batteryLevel != -1 && batteryLevel <= 25,
                            isLoading: isChecking && currentStep == 6,
                            isPending: isChecking && currentStep < 6,
                            isDark: isDark,
                          ),
                          Divider(color: listDivider, height: 1),
                          _buildDiagnosticRow(
                            icon: Icons.volume_up_rounded,
                            title: 'Audio & Sirene Kiosk',
                            subtitle: currentStep == 7 && isChecking
                                ? 'Menyiapkan volume...'
                                : (currentStep < 7
                                    ? 'Menunggu antrean...'
                                    : (isVolumeReady ? 'Volume 100% Siaga (Sirene Siap)' : 'DILARANG! Volume Belum Maksimal / Izin Dibutuhkan')),
                            isPassed: isVolumeReady,
                            isLoading: isChecking && currentStep == 7,
                            isPending: isChecking && currentStep < 7,
                            isDark: isDark,
                          ),
                          Divider(color: listDivider, height: 1),
                          _buildDiagnosticRow(
                            icon: Icons.picture_in_picture_alt_rounded,
                            title: 'Anti-Overlay & Jendela Mengambang',
                            subtitle: currentStep == 8 && isChecking
                                ? 'Memindai jendela mengambang & PiP...'
                                : (currentStep < 8
                                    ? 'Menunggu antrean...'
                                    : (isOverlayReady
                                        ? 'Mode Kiosk Bersih (Bebas Overlay / PiP)'
                                        : 'DILARANG! ${overlayReason ?? "Jendela Mengambang / PiP Terdeteksi!"}')),
                            isPassed: isOverlayReady,
                            isLoading: isChecking && currentStep == 8,
                            isPending: isChecking && currentStep < 8,
                            isDark: isDark,
                            onTap: !isOverlayReady ? () => VolumeLockService.openOverlaySettings() : null,
                          ),
                          Divider(color: listDivider, height: 1),
                          _buildDiagnosticRow(
                            icon: Icons.wifi_rounded,
                            title: 'Koneksi Server',
                            subtitle: currentStep == 9 && isChecking
                                ? 'Menguji latensi...'
                                : (currentStep < 9
                                    ? 'Menunggu antrean...'
                                    : (isServerOk ? '${latencyMs}ms (Koneksi Stabil)' : 'DILARANG! Koneksi Terganggu (Gagal Menghubungi Server)')),
                            isPassed: isServerOk,
                            isLoading: isChecking && currentStep == 9,
                            isPending: isChecking && currentStep < 9,
                            isDark: isDark,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Action Buttons
                    Row(
                      children: [
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: isDark ? Colors.white : const Color(0xFF0F172A),
                            backgroundColor: isDark ? Colors.transparent : const Color(0xFFF1F5F9),
                            side: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: isChecking ? null : () => runInspection(resetTouch: true),
                          icon: const Icon(Icons.refresh_rounded, size: 16),
                          label: const Text('Pindai Ulang', style: TextStyle(fontSize: 12)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: allPassed ? AppTheme.accentGreen : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                              foregroundColor: allPassed ? Colors.white : (isDark ? Colors.white60 : const Color(0xFF94A3B8)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: allPassed ? 4 : 0,
                            ),
                            onPressed: (allPassed && !isChecking)
                                ? () async {
                                    // 1. Final security re-verification of overlays and floating windows
                                    final overlayCheck = await VolumeLockService.detectFloatingWindowOrOverlay();
                                    if (overlayCheck['has_overlay'] == true) {
                                      if (modalCtx.mounted) {
                                        setModalState(() {
                                          isOverlayReady = false;
                                          overlayReason = overlayCheck['reason']?.toString() ?? 'Jendela mengambang terdeteksi';
                                        });
                                        AppNotification.showError(
                                          modalCtx,
                                          'Aplikasi Mengambang Terdeteksi!',
                                          subtitle: overlayCheck['reason']?.toString() ?? 'Tutup semua jendela mengambang, bubble chat, atau split screen sebelum masuk ujian.',
                                        );
                                      }
                                      return;
                                    }

                                    // 2. Final Bluetooth re-verification
                                    final btActive = await VolumeLockService.isBluetoothEnabled();
                                    if (btActive) {
                                      if (modalCtx.mounted) {
                                        setModalState(() {
                                          isBtOff = false;
                                        });
                                        AppNotification.showError(
                                          modalCtx,
                                          'Koneksi Bluetooth Aktif!',
                                          subtitle: 'Matikan Bluetooth sebelum melanjutkan masuk ke ujian.',
                                        );
                                      }
                                      return;
                                    }

                                    // 3. Final Phone Call re-verification
                                    final callActive = await VolumeLockService.isPhoneCallActive();
                                    final examId = exam['id'];
                                    if (examId != null) {
                                      try {
                                        await _api.post(
                                          ApiEndpoints.phoneCallStatus,
                                          data: {
                                            'link_id': examId,
                                            'is_on_call': callActive,
                                          },
                                        );
                                      } catch (_) {}
                                    }
                                    if (callActive) {
                                      if (modalCtx.mounted) {
                                        setModalState(() {
                                          isNoCallActive = false;
                                        });
                                        AppNotification.showError(
                                          modalCtx,
                                          'Panggilan Suara Aktif!',
                                          subtitle: 'Tutup panggilan telepon sebelum masuk ke ruang ujian.',
                                        );
                                      }
                                      return;
                                    }

                                    final currentNet = await VolumeLockService.getNetworkType();
                                    if (currentNet == 'none') {
                                      if (modalCtx.mounted) {
                                        AppNotification.showWarning(
                                          modalCtx,
                                          'Koneksi Internet Terputus',
                                          subtitle: 'Perangkat tidak terhubung ke jaringan. Sambungkan Wi-Fi atau data sebelum masuk ujian.',
                                        );
                                      }
                                      return;
                                    }

                                    if (!isCharging && batteryLevel != -1 && batteryLevel <= 25) {
                                      final shouldProceed = await _confirmLowBatteryProceed(modalCtx, batteryLevel);
                                      if (!shouldProceed) return;
                                    }

                                    Navigator.pop(ctx);
                                    // Allow bottom sheet dismissal animation to finish smoothly
                                    // before transitioning to the exam screen
                                    await Future.delayed(const Duration(milliseconds: 250));
                                    if (mounted) {
                                      _processExamLaunch(exam);
                                    }
                                  }
                                : null,
                            icon: Icon(allPassed ? Icons.play_arrow_rounded : Icons.lock_rounded, size: 18),
                            label: Text(
                              allPassed ? 'Siap, Lanjut Masuk Ujian' : 'Syarat Belum Terpenuhi',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
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
    },
    );
  },
);
  }

  Future<bool> _confirmLowBatteryProceed(BuildContext context, int batteryLevel) async {
    final isDark = AppTheme.isDark(context);
    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dlgCtx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
        ),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        actionsPadding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.battery_alert_rounded, color: Color(0xFFF59E0B), size: 22),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Peringatan Baterai Rendah',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sisa daya baterai perangkat Anda saat ini $batteryLevel% dan tidak sedang diisi daya.',
              style: TextStyle(
                fontSize: 13.5,
                color: isDark ? Colors.white70 : const Color(0xFF334155),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFFEF3C7).withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? const Color(0xFF475569) : const Color(0xFFFDE68A),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline_rounded, color: Color(0xFFF59E0B), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Ujian berjalan dalam mode kiosk layar penuh yang mengonsumsi daya lebih banyak. Sangat disarankan menyambungkan charger.',
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.4,
                        color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF92400E),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Apakah Anda yakin ingin tetap melanjutkan ujian?',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            onPressed: () => Navigator.pop(dlgCtx, false),
            child: Text(
              'Cas Dulu / Batal',
              style: TextStyle(
                color: isDark ? Colors.white60 : const Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF59E0B),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            onPressed: () => Navigator.pop(dlgCtx, true),
            child: const Text('Tetap Lanjut Ujian', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    return proceed == true;
  }

  Widget _buildDiagnosticRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isPassed,
    required bool isLoading,
    bool isPending = false,
    bool isWarning = false,
    bool isDark = true,
    VoidCallback? onTap,
  }) {
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subColor = isPending
        ? (isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8))
        : (isWarning
            ? const Color(0xFFF59E0B)
            : (isPassed
                ? (isDark ? AppTheme.textSecondary : const Color(0xFF64748B))
                : AppTheme.dangerRed));
    final iconColor = isPending
        ? (isDark ? const Color(0xFF475569) : const Color(0xFF94A3B8))
        : (isWarning
            ? const Color(0xFFF59E0B)
            : (isPassed
                ? (isDark ? Colors.white70 : const Color(0xFF475569))
                : AppTheme.dangerRed));

    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: titleColor, fontSize: 12, fontWeight: FontWeight.w600)),
                Text(subtitle, style: TextStyle(color: subColor, fontSize: 11)),
              ],
            ),
          ),
          if (isLoading)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryBlue),
            )
          else if (isPending)
            Icon(
              Icons.hourglass_empty_rounded,
              size: 15,
              color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
            )
          else if (isWarning)
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFF59E0B), size: 18)
          else if (isPassed)
            const Icon(Icons.check_circle_rounded, color: AppTheme.accentGreen, size: 18)
          else
            const Icon(Icons.cancel_rounded, color: AppTheme.dangerRed, size: 18),
        ],
      ),
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: content,
      );
    }

    return content;
  }

  /**
   * Main entry point when student clicks on an exam card.
   */
  Future<void> _enterExam(Map<String, dynamic> exam) async {
    if (exam['is_locked'] == true) {
      Navigator.of(context).pushNamed(
        AppRoutes.lockout,
        arguments: {
          'exam_id': exam['id'],
          'exam_title': exam['title'],
          'lock_reason': exam['lock_reason'],
        },
      );
      return;
    }

    if (exam['is_available'] != true || exam['url'] == null) {
      AppNotification.showWarning(
        context,
        'Ujian Belum Tersedia',
        subtitle: 'Ujian belum dapat dimulai sesuai jadwal yang ditetapkan.',
      );
      return;
    }

    // Trigger pre-flight diagnostic inspection
    await _showPreFlightDiagnosticsModal(exam);
  }

  void _processExamLaunch(Map<String, dynamic> exam) {
    final pendingUpdate = AppUpdateService.instance.latestUpdateInfo;
    if (pendingUpdate != null && pendingUpdate.forceUpdate) {
      AppUpdateDialog.show(context, pendingUpdate);
      return;
    }

    final rawToken = exam['token'];
    final tokenMode = exam['token_mode'];
    final bool requiresToken = rawToken != null &&
        rawToken.toString().trim().isNotEmpty &&
        tokenMode != 'none';

    if (!requiresToken) {
      _launchExam(exam);
    } else {
      _showTokenModal(exam);
    }
  }

  void _launchExam(Map<String, dynamic> exam) {
    final examId = exam['id'];
    if (examId is int) {
      ExamReminderService.cancelExamReminders(examId);
    }
    Navigator.of(context).pushNamed(
      AppRoutes.examPlayer,
      arguments: exam,
    ).then((_) {
      _controller.loadExams();
      _controller.loadHistory();
    });
  }

  void _showTokenModal(Map<String, dynamic> exam) {
    final tokenController = TextEditingController();
    String? tokenError;
    final expectedToken = (exam['token'] ?? '').toString().trim().toUpperCase();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final isDark = AppTheme.isDark(context);
            final dialogBg = isDark ? AppTheme.surfaceDark : Colors.white;
            final dialogBorder = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
            final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
            final descColor = isDark ? AppTheme.textSecondary : const Color(0xFF475569);
            final inputFill = isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9);
            final inputBorder = isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1);
            final inputTextColor = isDark ? Colors.white : const Color(0xFF0F172A);

            return RepaintBoundary(
              child: AlertDialog(
                backgroundColor: dialogBg,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: dialogBorder),
                ),
                title: Row(
                  children: [
                    const Icon(Icons.vpn_key_rounded, color: AppTheme.accentYellow, size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Masukkan Token Ujian',
                        style: TextStyle(color: titleColor, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ujian "${exam['title']}" memerlukan 6 karakter token yang dibagikan oleh pengawas ruangan.',
                      style: TextStyle(color: descColor, fontSize: 12, height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: tokenController,
                      autofocus: true,
                      textAlign: TextAlign.center,
                      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                      textCapitalization: TextCapitalization.characters,
                      maxLength: 6,
                      style: TextStyle(
                        color: inputTextColor,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 6,
                      ),
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: '••••••',
                        hintStyle: TextStyle(
                          color: isDark ? Colors.white.withOpacity(0.2) : const Color(0xFF94A3B8),
                          letterSpacing: 6,
                        ),
                        filled: true,
                        fillColor: inputFill,
                        errorText: tokenError,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: inputBorder),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: AppTheme.primaryShiei, width: 2),
                        ),
                      ),
                      onChanged: (_) {
                        if (tokenError != null) {
                          setModalState(() => tokenError = null);
                        }
                      },
                      onSubmitted: (val) {
                        _validateAndSubmitToken(
                          val,
                          expectedToken,
                          exam,
                          ctx,
                          setModalState,
                          (err) => tokenError = err,
                        );
                      },
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(
                      'Batal',
                      style: TextStyle(color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
                    ),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryShiei,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    onPressed: () {
                      _validateAndSubmitToken(
                        tokenController.text,
                        expectedToken,
                        exam,
                        ctx,
                        setModalState,
                        (err) => tokenError = err,
                      );
                    },
                    child: const Text('Mulai Ujian'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _validateAndSubmitToken(
    String input,
    String expectedToken,
    Map<String, dynamic> exam,
    BuildContext dialogContext,
    void Function(void Function()) setModalState,
    void Function(String?) setError,
  ) {
    final sanitizedInput = input.trim().toUpperCase();

    if (sanitizedInput.isEmpty) {
      setModalState(() {
        setError('Token tidak boleh kosong.');
      });
      return;
    }

    if (sanitizedInput == expectedToken) {
      Navigator.pop(dialogContext);
      _launchExam(exam);
    } else {
      setModalState(() {
        setError('Token ujian salah atau sudah kadaluarsa!');
      });
    }
  }

  void _confirmLogout() {
    final isDark = AppTheme.isDark(context);
    final dialogBg = isDark ? AppTheme.surfaceDark : Colors.white;
    final dialogBorder = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final contentColor = isDark ? AppTheme.textSecondary : const Color(0xFF475569);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: dialogBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: dialogBorder),
        ),
        title: Text('Konfirmasi Keluar Akun', style: TextStyle(color: titleColor, fontWeight: FontWeight.bold)),
        content: Text(
          'Keluar dari akun ujian? Anda harus masuk kembali menggunakan NISN/Nama Pengguna dan kata sandi.',
          style: TextStyle(color: contentColor, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Batal', style: TextStyle(color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.dangerRed,
              foregroundColor: Colors.white,
              minimumSize: const Size(80, 36),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await _controller.logout();
              if (mounted) {
                Navigator.of(context).pushReplacementNamed(AppRoutes.login);
              }
            },
            child: const Text('Keluar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final user = _controller.currentUser;

        String getAppBarTitle() {
          switch (_currentTabIndex) {
            case 1:
              return 'Riwayat Ujian Siswa';
            case 2:
              return 'Profil Siswa';
            case 0:
            default:
              return 'Jadwal Ujian Siswa';
          }
        }

        List<Widget> getAppBarActions() {
          switch (_currentTabIndex) {
            case 1:
              return [
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: 'Muat Ulang Riwayat',
                  onPressed: () => _controller.loadHistory(isManualRefresh: true),
                ),
              ];
            case 2:
              return [
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: 'Muat Ulang Profil',
                  onPressed: () => _controller.refreshProfile(isManualRefresh: true),
                ),
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: 'Pengaturan Kiosk',
                  onPressed: () => Navigator.of(context).pushNamed(AppRoutes.settings),
                ),
                IconButton(
                  icon: const Icon(Icons.logout_rounded, color: AppTheme.dangerRed),
                  tooltip: 'Keluar Akun',
                  onPressed: _confirmLogout,
                ),
              ];
            case 0:
            default:
              return [
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: 'Muat Ulang Daftar Ujian',
                  onPressed: () {
                    _controller.loadExams(clearPrevious: true);
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: 'Pengaturan Kiosk',
                  onPressed: () => Navigator.of(context).pushNamed(AppRoutes.settings),
                ),
              ];
          }
        }

        final isDark = AppTheme.isDark(context);

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            // Check if any modal sheet/dialog is open
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
              return;
            }
            // Bottom navigation bar root (Any tab: Ujian, Riwayat, Profil)
            await AppExitDialog.show(context);
          },
          child: Scaffold(
            backgroundColor: AppTheme.background(context),
            appBar: AppBar(
              title: _currentTabIndex == 0
                  ? const ShieiBrandLogo(logoSize: 26, fontSize: 17)
                  : Text(getAppBarTitle()),
              actions: getAppBarActions(),
            ),
            body: IndexedStack(
              index: _currentTabIndex,
              children: [
                _buildExamsTab(user),
                _buildHistoryTab(),
                _buildProfileTab(user),
              ],
            ),
            bottomNavigationBar: FluidCurvedBottomBar(
              currentIndex: _currentTabIndex,
              backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
              activeColor: AppTheme.primaryGlow,
              inactiveColor: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
              borderColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
              items: const [
                FluidNavItem(
                  icon: Icons.assignment_rounded,
                  activeIcon: Icons.assignment_rounded,
                  label: 'Ujian',
                ),
                FluidNavItem(
                  icon: Icons.history_edu_rounded,
                  activeIcon: Icons.history_edu_rounded,
                  label: 'Riwayat',
                ),
                FluidNavItem(
                  icon: Icons.person_rounded,
                  activeIcon: Icons.person_rounded,
                  label: 'Profil',
                ),
              ],
              onTap: (index) {
                FocusManager.instance.primaryFocus?.unfocus();
                setState(() {
                  _currentTabIndex = index;
                });
                if (index == 1 && !_controller.hasLoadedHistory) {
                  _controller.loadHistory(isManualRefresh: false);
                } else if (index == 2 && _controller.currentUser == null) {
                  _controller.refreshProfile(isManualRefresh: false);
                }
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildExamsTab(Map<String, dynamic>? user) {
    final isDark = AppTheme.isDark(context);
    final now = DateTime.now();
    final oneWeekLater = now.add(const Duration(days: 7));

    // 1. Identify all exams already completed/submitted in student history
    final completedExamIds = _controller.history
        .where((h) {
          final st = (h['status'] ?? '').toString().toLowerCase();
          return st == 'completed' || st == 'submitted';
        })
        .map((h) => h['link_id'] ?? h['link']?['id'] ?? h['id'])
        .whereType<int>()
        .toSet();

    // 2. Exclude finished & ended exams from active exam schedule,
    //    and strictly limit to exams scheduled within 1 week (now to now + 7 days)
    final activeExams = _controller.exams.where((exam) {
      // 2a. Exclude completed/submitted exams
      final progressStatus = (exam['progress']?['status'] ?? '').toString().toLowerCase();
      if (progressStatus == 'completed' || progressStatus == 'submitted') return false;
      final examId = exam['id'];
      if (examId is int && completedExamIds.contains(examId)) return false;

      // 2b. Exclude expired / ended exams (status sudah berakhir -> pindah ke riwayat)
      if (exam['is_expired'] == true) return false;
      final rawEnd = exam['end_time'];
      if (rawEnd != null) {
        final endDt = DateTime.tryParse(rawEnd.toString())?.toLocal();
        if (endDt != null && now.isAfter(endDt)) {
          return false;
        }
      }

      // 2c. Only show if within 1 week (hanya show kalo dalam seminggu aja)
      final rawStart = exam['start_time'];
      if (rawStart != null) {
        final startDt = DateTime.tryParse(rawStart.toString())?.toLocal();
        if (startDt != null && startDt.isAfter(oneWeekLater)) {
          return false; // Jadwal lebih dari 7 hari ke depan
        }
      }

      return true;
    }).toList();

    // 3. Apply live search filter across title, subject, class, and teacher
    final filteredExams = activeExams.where((exam) {
      if (_examSearchQuery.isEmpty) return true;
      final title = (exam['title'] ?? '').toString().toLowerCase();
      final subject = (exam['subject'] ?? '').toString().toLowerCase();
      final className = (exam['class_major']?['name'] ?? '').toString().toLowerCase();
      final teacher = (exam['teacher_name'] ?? '').toString().toLowerCase();
      return title.contains(_examSearchQuery) ||
          subject.contains(_examSearchQuery) ||
          className.contains(_examSearchQuery) ||
          teacher.contains(_examSearchQuery);
    }).toList();

    return RefreshIndicator(
      onRefresh: () => _controller.loadExams(clearPrevious: true),
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          // Student Profile Summary Banner (Targeted by Tour Step 0)
          Container(
            key: _tourKeys.studentCardKey,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              gradient: isDark
                  ? const LinearGradient(
                      colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : const LinearGradient(
                      colors: [Colors.white, Color(0xFFF1F5F9)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? AppTheme.primaryShiei.withOpacity(0.35) : AppTheme.primaryShiei.withOpacity(0.25),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: isDark ? AppTheme.primaryShiei.withOpacity(0.08) : Colors.black.withOpacity(0.04),
                  blurRadius: 18,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: _controller.isLoading
                ? const ShieiShimmer(
                    child: Row(
                      children: [
                        ShieiSkeletonCircle(size: 44),
                        SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  ShieiSkeletonBox(width: 130, height: 16, borderRadius: 4),
                                  ShieiSkeletonBox(width: 48, height: 18, borderRadius: 6),
                                ],
                              ),
                              SizedBox(height: 6),
                              ShieiSkeletonBox(width: 90, height: 16, borderRadius: 6),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                : Row(
                    children: [
                      // Styled Student Avatar with Gradient Ring
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [Color(0xFFF97316), Color(0xFFEA580C)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primaryShiei.withOpacity(0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(2.0),
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isDark ? const Color(0xFF0F172A) : Colors.white,
                            ),
                            child: const Icon(
                              Icons.school_rounded,
                              color: AppTheme.primaryGlow,
                              size: 22,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Text(
                                    user?['name'] ?? 'Siswa Ujian',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: isDark ? Colors.white : AppTheme.textPrimaryLight,
                                      letterSpacing: 0.2,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryShiei.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: AppTheme.primaryShiei.withOpacity(0.3)),
                                  ),
                                  child: Text(
                                    '${user?['class_name'] ?? user?['class_major']?['name'] ?? '-'}',
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      color: AppTheme.primaryGlow,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF0B1120) : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                                ),
                              ),
                              child: Text(
                                'NISN: ${user?['nisn'] ?? '-'}',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 14),

          // Live Search Bar for Exams (Targeted by Tour Step 1)
          Container(
            key: _tourKeys.examSearchKey,
            decoration: BoxDecoration(
              color: isDark ? AppTheme.surfaceDark : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _examSearchQuery.isNotEmpty
                    ? AppTheme.primaryGlow.withOpacity(0.6)
                    : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                width: _examSearchQuery.isNotEmpty ? 1.5 : 1,
              ),
              boxShadow: [
                if (!isDark)
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
              ],
            ),
            child: TextField(
              controller: _examSearchController,
              textInputAction: TextInputAction.search,
              onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
              onSubmitted: (_) => FocusScope.of(context).unfocus(),
              style: TextStyle(
                color: isDark ? Colors.white : AppTheme.textPrimaryLight,
                fontSize: 13,
              ),
              decoration: InputDecoration(
                hintText: 'Cari ujian atau mata pelajaran...',
                hintStyle: TextStyle(
                  color: isDark ? AppTheme.textMuted : AppTheme.textMutedLight,
                  fontSize: 13,
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: isDark ? AppTheme.textSecondary : AppTheme.textSecondaryLight,
                  size: 20,
                ),
                suffixIcon: _examSearchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(
                          Icons.clear_rounded,
                          color: isDark ? AppTheme.textSecondary : AppTheme.textSecondaryLight,
                          size: 18,
                        ),
                        onPressed: () {
                          _examSearchController.clear();
                          setState(() => _examSearchQuery = '');
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              onChanged: (val) {
                setState(() => _examSearchQuery = val.trim().toLowerCase());
              },
            ),
          ),
          const SizedBox(height: 16),

          Row(
            key: _tourKeys.examSectionKey,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    'Daftar Ujian Terjadwal',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : AppTheme.textPrimaryLight,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryShiei.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppTheme.primaryShiei.withOpacity(0.3)),
                    ),
                    child: const Text(
                      '7 Hari',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryGlow,
                      ),
                    ),
                  ),
                ],
              ),
              if (_examSearchQuery.isNotEmpty)
                Text(
                  '${filteredExams.length} ditemukan',
                  style: const TextStyle(fontSize: 11, color: AppTheme.primaryGlow, fontWeight: FontWeight.bold),
                ),
            ],
          ),
          const SizedBox(height: 12),

          if (_controller.isLoading)
            const StudentExamCardSkeleton(count: 3, padding: EdgeInsets.zero)
          else if (_controller.errorMessage != null && _controller.exams.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  children: [
                    const Icon(Icons.cloud_off_rounded, size: 48, color: AppTheme.textSecondary),
                    const SizedBox(height: 12),
                    Text(
                      _controller.errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(minimumSize: const Size(120, 38)),
                      onPressed: () => _controller.loadExams(clearPrevious: true),
                      child: const Text('Coba Lagi'),
                    ),
                  ],
                ),
              ),
            )
          else if (activeExams.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  children: [
                    const Icon(Icons.assignment_turned_in_outlined, size: 48, color: AppTheme.accentGreen),
                    const SizedBox(height: 12),
                    Text(
                      'Semua Ujian Telah Selesai',
                      style: TextStyle(
                        color: isDark ? Colors.white : AppTheme.textPrimaryLight,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tidak ada jadwal ujian aktif dalam 7 hari ke depan. Anda dapat memeriksa riwayat dan hasil ujian di tab "Riwayat".',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isDark ? AppTheme.textSecondary : AppTheme.textSecondaryLight,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (filteredExams.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  children: [
                    const Icon(Icons.search_off_rounded, size: 44, color: AppTheme.textSecondary),
                    const SizedBox(height: 12),
                    Text(
                      'Tidak Ditemukan Hasil',
                      style: TextStyle(
                        color: isDark ? Colors.white : AppTheme.textPrimaryLight,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tidak ada ujian yang cocok dengan kata kunci "$_examSearchQuery".',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isDark ? AppTheme.textSecondary : AppTheme.textSecondaryLight,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ...filteredExams.map((exam) => _buildExamCard(exam)).toList(),
        ],
      ),
    );
  }

  void _showHistoryDetailModal(Map<String, dynamic> item) {
    final link = item['link'] ?? {};
    final rawStatus = (item['status'] ?? 'completed').toString().toLowerCase();
    final isLocked = item['is_locked'] == true || rawStatus == 'locked' || rawStatus == 'terminated' || rawStatus == 'exited';
    final isCompleted = rawStatus == 'completed' || rawStatus == 'submitted';
    final isEnded = rawStatus == 'ended' || rawStatus == 'expired' || item['is_expired'] == true;
    final isInProgress = !isLocked && !isCompleted && !isEnded;

    final score = item['score'];
    final title = link['title'] ?? 'Ujian Digital';
    final subject = link['subject'] ?? 'Umum';
    final duration = link['duration_minutes'] ?? 60;
    final startTime = item['start_time'] ?? item['created_at'];
    final endTime = item['end_time'] ?? item['updated_at'];

    // Calculate actual elapsed student duration
    int elapsedSec = 0;
    if (item['elapsed_seconds'] is int) {
      elapsedSec = item['elapsed_seconds'] as int;
    } else if (item['elapsed_seconds'] is num) {
      elapsedSec = (item['elapsed_seconds'] as num).toInt();
    } else if (startTime != null) {
      try {
        final startDt = DateTime.parse(startTime.toString()).toLocal();
        final endDt = (isCompleted && endTime != null)
            ? DateTime.parse(endTime.toString()).toLocal()
            : DateTime.now();
        elapsedSec = endDt.difference(startDt).inSeconds;
        if (elapsedSec < 0) elapsedSec = 0;
      } catch (_) {}
    }

    String formatDurationSpent(int seconds) {
      if (isEnded && seconds <= 0) return 'Tidak Dikerjakan (Waktu Berakhir)';
      if (seconds <= 0) return 'Baru dimulai (< 1 menit)';
      final hours = seconds ~/ 3600;
      final minutes = (seconds % 3600) ~/ 60;
      final remainingSeconds = seconds % 60;

      if (hours > 0) {
        return '$hours Jam $minutes Menit $remainingSeconds Detik';
      } else if (minutes > 0) {
        return '$minutes Menit $remainingSeconds Detik';
      } else {
        return '$remainingSeconds Detik';
      }
    }

    // Violation & integrity tracking
    final violationsCount = (item['violations_count'] as num?)?.toInt() ?? 0;
    final unlockedByName = item['unlocked_by_name']?.toString();
    final bool wasUnlocked = item['was_unlocked'] == true;
    final bool effectiveLocked = isLocked || (violationsCount > 0 && !isCompleted && !wasUnlocked);

    String integrityText;
    Color integrityColor;

    if (effectiveLocked) {
      integrityText = violationsCount > 0
          ? '$violationsCount Pelanggaran Terdeteksi\n(Sesi Terkunci)'
          : 'Sesi Terkunci /\nDihentikan Pengawas';
      integrityColor = AppTheme.dangerRed;
    } else if (violationsCount > 0) {
      integrityText = '$violationsCount Pelanggaran\n(Telah Dibuka Pengawas${unlockedByName != null ? ': $unlockedByName' : ''})';
      integrityColor = const Color(0xFFF59E0B);
    } else if (isEnded && elapsedSec <= 0) {
      integrityText = 'Tidak Mengerjakan\n(Waktu Ujian Berakhir)';
      integrityColor = const Color(0xFF94A3B8);
    } else {
      integrityText = 'Tertib / Bersih\n(0 Pelanggaran)';
      integrityColor = AppTheme.accentGreen;
    }

    String formatDate(dynamic dateStr) {
      if (dateStr == null) return '-';
      try {
        final dt = DateTime.parse(dateStr.toString()).toLocal();
        return DateFormat('d MMMM yyyy, HH:mm', 'id_ID').format(dt);
      } catch (_) {
        return dateStr.toString();
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 600),
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = AppTheme.isDark(ctx);
        final Color bannerColor = isDark
            ? (effectiveLocked
                ? AppTheme.dangerRed
                : (isCompleted
                    ? AppTheme.accentGreen
                    : (isEnded ? const Color(0xFF94A3B8) : AppTheme.primaryBlue)))
            : (effectiveLocked
                ? const Color(0xFFDC2626)
                : (isCompleted
                    ? const Color(0xFF16A34A)
                    : (isEnded ? const Color(0xFF64748B) : const Color(0xFF2563EB))));

        final List<Color> bannerGradient = isDark
            ? (effectiveLocked
                ? [const Color(0xFF2A0A0A), const Color(0xFF140707)]
                : (isCompleted
                    ? [const Color(0xFF06281D), const Color(0xFF091F18)]
                    : (isEnded
                        ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
                        : [const Color(0xFF0C2440), const Color(0xFF08182B)])))
            : (effectiveLocked
                ? [const Color(0xFFFEF2F2), const Color(0xFFFEE2E2)]
                : (isCompleted
                    ? [const Color(0xFFF0FDF4), const Color(0xFFDCFCE7)]
                    : (isEnded
                        ? [const Color(0xFFF1F5F9), const Color(0xFFE2E8F0)]
                        : [const Color(0xFFEFF6FF), const Color(0xFFDBEAFE)])));

        final String bannerStatusTitle = effectiveLocked
            ? 'STATUS: TERKUNCI / DIHENTIKAN'
            : (isCompleted
                ? 'STATUS: SELESAI & TERVERIFIKASI'
                : (isEnded ? 'STATUS: UJIAN TELAH BERAKHIR' : 'STATUS: SEDANG DIKERJAKAN'));

        final String bannerSubtitle = effectiveLocked
            ? 'Sesi dihentikan karena pelanggaran / pengawas'
            : (isCompleted
                ? (score != null ? 'Nilai: $score / 100' : 'Jawaban tersimpan otomatis')
                : (isEnded ? 'Batas waktu pengerjaan ujian telah selesai' : 'Sesi pengerjaan aktif sedang berlangsung'));

        final IconData bannerIcon = isLocked
            ? Icons.lock_rounded
            : (isCompleted
                ? (score != null ? Icons.military_tech_rounded : Icons.task_alt_rounded)
                : (isEnded ? Icons.event_busy_rounded : Icons.timelapse_rounded));

        return Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(
              top: BorderSide(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                width: 1.5,
              ),
            ),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryShiei.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              subject.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryGlow,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : AppTheme.textPrimaryLight,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Status & Score Banner (3-Tier dynamic)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: bannerGradient),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: bannerColor.withOpacity(0.5)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: bannerColor.withOpacity(0.2),
                        ),
                        child: Icon(bannerIcon, color: bannerColor, size: 26),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              bannerStatusTitle,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.6,
                                color: bannerColor,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              bannerSubtitle,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: isDark
                                    ? Colors.white
                                    : (isLocked
                                        ? const Color(0xFF991B1B)
                                        : (isEnded
                                            ? const Color(0xFF475569)
                                            : (isInProgress
                                                ? const Color(0xFF1E40AF)
                                                : const Color(0xFF166534)))),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Info Rows
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark ? AppTheme.surfaceDark : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Column(
                    children: [
                      _buildHistoryDetailRow(ctx, 'Lama Pengerjaan:', formatDurationSpent(elapsedSec), valueColor: AppTheme.primaryGlow),
                      Divider(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0), height: 16),
                      _buildHistoryDetailRow(ctx, 'Batas Alokasi Waktu:', FormatUtils.formatDurationHoursMinutes(duration)),
                      Divider(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0), height: 16),
                      _buildHistoryDetailRow(
                        ctx,
                        (isEnded && elapsedSec <= 0) ? 'Jadwal Mulai:' : 'Waktu Mulai:',
                        formatDate(startTime),
                      ),
                      Divider(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0), height: 16),
                      _buildHistoryDetailRow(
                        ctx,
                        isCompleted
                            ? 'Waktu Selesai:'
                            : (isEnded ? 'Waktu Berakhir:' : 'Aktivitas Terakhir:'),
                        formatDate(endTime),
                      ),
                      Divider(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0), height: 16),
                      _buildHistoryDetailRow(
                        ctx,
                        'Riwayat Integritas:',
                        integrityText,
                        valueColor: integrityColor,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 44),
                    backgroundColor: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                    foregroundColor: isDark ? Colors.white : AppTheme.textPrimaryLight,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Tutup Rincian', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHistoryDetailRow(BuildContext context, String label, String value, {Color? valueColor}) {
    final isDark = AppTheme.isDark(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? AppTheme.textSecondary : AppTheme.textSecondaryLight,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.35,
              color: valueColor ?? (isDark ? Colors.white : AppTheme.textPrimaryLight),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryTab() {
    final isDark = AppTheme.isDark(context);
    final now = DateTime.now();

    // 1. Base student history records from server (strictly completed or expired/ended only)
    final history = _controller.history.where((item) {
      final status = (item['status'] ?? '').toString().toLowerCase();
      final isCompleted = status == 'completed' || status == 'submitted';
      bool isEnded = item['is_expired'] == true || status == 'ended' || status == 'expired';
      final link = item['link'] is Map ? item['link'] as Map : null;
      final rawEnd = link?['end_time'] ?? item['end_time'];
      if (rawEnd != null) {
        final endDt = DateTime.tryParse(rawEnd.toString())?.toLocal();
        if (endDt != null && now.isAfter(endDt)) {
          isEnded = true;
        }
      }
      return isCompleted || isEnded;
    }).toList();
    final historyLinkIds = history
        .map((h) => h['link_id'] ?? h['link']?['id'] ?? h['id'])
        .whereType<int>()
        .toSet();

    // 2. Automatically merge completed or ended/expired exams from _controller.exams
    for (final exam in _controller.exams) {
      final examId = exam['id'];
      if (examId is! int || historyLinkIds.contains(examId)) continue;

      final progressStatus = (exam['progress']?['status'] ?? '').toString().toLowerCase();
      final bool isCompleted = progressStatus == 'completed' || progressStatus == 'submitted';
      bool isEnded = exam['is_expired'] == true;
      if (!isEnded && exam['end_time'] != null) {
        final endDt = DateTime.tryParse(exam['end_time'].toString())?.toLocal();
        if (endDt != null && now.isAfter(endDt)) {
          isEnded = true;
        }
      }

      if (isCompleted || isEnded) {
        final violationsCount = (exam['progress']?['violations_count'] as num?)?.toInt() ?? (exam['violations_count'] as num?)?.toInt() ?? 0;
        final bool isExamLocked = exam['is_locked'] == true || exam['progress']?['is_locked'] == true || (violationsCount > 0 && !isCompleted);
        history.add({
          'id': examId,
          'link_id': examId,
          'link': exam,
          'status': isExamLocked ? 'locked' : (isCompleted ? progressStatus : 'ended'),
          'is_expired': true,
          'is_locked': isExamLocked,
          'violations_count': violationsCount,
          'unlocked_by_name': exam['progress']?['unlocked_by_name'] ?? exam['unlocked_by_name'],
          'score': exam['progress']?['score'] ?? exam['score'],
          'created_at': exam['start_time'] ?? exam['created_at'],
          'updated_at': exam['end_time'],
          'elapsed_seconds': (exam['progress']?['elapsed_seconds'] as num?)?.toInt() ?? (exam['elapsed_seconds'] as num?)?.toInt() ?? 0,
        });
        historyLinkIds.add(examId);
      }
    }

    final filteredHistory = history.where((item) {
      if (_historySearchQuery.isEmpty) return true;
      final link = item['link'] ?? {};
      final title = (link['title'] ?? '').toString().toLowerCase();
      final subject = (link['subject'] ?? '').toString().toLowerCase();
      return title.contains(_historySearchQuery) || subject.contains(_historySearchQuery);
    }).toList();

    return RefreshIndicator(
      onRefresh: () => _controller.loadHistory(isManualRefresh: true),
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          // Live Search Bar for History (Targeted by Tour Step 2)
          Container(
            key: _tourKeys.historyKey,
            decoration: BoxDecoration(
              color: isDark ? AppTheme.surfaceDark : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _historySearchQuery.isNotEmpty
                    ? AppTheme.primaryGlow.withOpacity(0.6)
                    : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                width: _historySearchQuery.isNotEmpty ? 1.5 : 1,
              ),
              boxShadow: [
                if (!isDark)
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
              ],
            ),
            child: TextField(
              controller: _historySearchController,
              textInputAction: TextInputAction.search,
              onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
              onSubmitted: (_) => FocusScope.of(context).unfocus(),
              style: TextStyle(
                color: isDark ? Colors.white : AppTheme.textPrimaryLight,
                fontSize: 13,
              ),
              decoration: InputDecoration(
                hintText: 'Cari riwayat ujian atau mata pelajaran...',
                hintStyle: TextStyle(
                  color: isDark ? AppTheme.textMuted : AppTheme.textMutedLight,
                  fontSize: 13,
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: isDark ? AppTheme.textSecondary : AppTheme.textSecondaryLight,
                  size: 20,
                ),
                suffixIcon: _historySearchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(
                          Icons.clear_rounded,
                          color: isDark ? AppTheme.textSecondary : AppTheme.textSecondaryLight,
                          size: 18,
                        ),
                        onPressed: () {
                          _historySearchController.clear();
                          setState(() => _historySearchQuery = '');
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              onChanged: (val) {
                setState(() => _historySearchQuery = val.trim().toLowerCase());
              },
            ),
          ),
          const SizedBox(height: 16),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Daftar Riwayat Ujian',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : AppTheme.textPrimaryLight,
                ),
              ),
              if (_historySearchQuery.isNotEmpty)
                Text(
                  '${filteredHistory.length} ditemukan',
                  style: const TextStyle(fontSize: 11, color: AppTheme.primaryGlow, fontWeight: FontWeight.bold),
                ),
            ],
          ),
          const SizedBox(height: 12),

          if ((!_controller.hasLoadedHistory && _controller.isHistoryLoading) || _controller.isHistoryManualRefreshing)
            const StudentHistoryCardSkeleton(count: 3, padding: EdgeInsets.zero)
          else if (history.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.history_toggle_off_rounded, size: 54, color: AppTheme.textSecondary),
                    const SizedBox(height: 14),
                    Text(
                      'Belum Ada Riwayat Ujian',
                      style: TextStyle(
                        color: isDark ? Colors.white : AppTheme.textPrimaryLight,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Hasil dan riwayat ujian yang telah Anda selesaikan atau telah berakhir akan tercatat di sini.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isDark ? AppTheme.textSecondary : AppTheme.textSecondaryLight,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primaryBlue,
                        side: const BorderSide(color: AppTheme.primaryBlue),
                      ),
                      onPressed: () => _controller.loadHistory(isManualRefresh: true),
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Muat Ulang Riwayat'),
                    ),
                  ],
                ),
              ),
            )
          else if (filteredHistory.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  children: [
                    const Icon(Icons.search_off_rounded, size: 44, color: AppTheme.textSecondary),
                    const SizedBox(height: 12),
                    Text(
                      'Tidak Ditemukan Hasil',
                      style: TextStyle(
                        color: isDark ? Colors.white : AppTheme.textPrimaryLight,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tidak ada riwayat yang cocok dengan kata kunci "$_historySearchQuery".',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isDark ? AppTheme.textSecondary : AppTheme.textSecondaryLight,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ...filteredHistory.map((item) {
              final link = item['link'] ?? {};
              final rawStatus = (item['status'] ?? 'completed').toString().toLowerCase();
              final violationsCount = (item['violations_count'] as num?)?.toInt() ?? 0;
              final bool wasUnlocked = item['was_unlocked'] == true;
              final isCompleted = rawStatus == 'completed' || rawStatus == 'submitted';
              final isLocked = item['is_locked'] == true ||
                  rawStatus == 'locked' ||
                  rawStatus == 'terminated' ||
                  rawStatus == 'exited' ||
                  (violationsCount > 0 && !isCompleted && !wasUnlocked);
              final isEnded = !isLocked && (rawStatus == 'ended' || rawStatus == 'expired' || item['is_expired'] == true);
              final isInProgress = !isLocked && !isCompleted && !isEnded;

              final score = item['score'];

              // 4 Dynamic Status Badge Configuration
              final String statusLabel = isLocked
                  ? 'TERKUNCI'
                  : (isInProgress
                      ? 'SEDANG DIKERJAKAN'
                      : (isCompleted
                          ? 'SELESAI'
                          : (isEnded ? 'BERAKHIR' : 'AKTIF')));

              final Color statusColor = isLocked
                  ? AppTheme.dangerRed
                  : (isInProgress
                      ? const Color(0xFFF59E0B)
                      : (isCompleted
                          ? AppTheme.accentGreen
                          : (isEnded ? (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)) : AppTheme.primaryBlue)));

              final IconData statusIcon = isLocked
                  ? Icons.lock_rounded
                  : (isInProgress
                      ? Icons.play_circle_fill_rounded
                      : (isCompleted
                          ? Icons.check_circle_rounded
                          : (isEnded ? Icons.event_busy_rounded : Icons.timelapse_rounded)));

              // Date formatting
              final subject = (link['subject'] ?? 'Umum').toString();
              String dateFormattedText = 'Waktu Fleksibel';
              final rawDate = item['start_time'] ?? item['created_at'];
              if (rawDate != null) {
                try {
                  final dt = DateTime.parse(rawDate.toString()).toLocal();
                  dateFormattedText = '${DateFormat('d MMM yyyy, HH:mm', 'id_ID').format(dt)} WIB';
                } catch (_) {
                  final s = rawDate.toString().trim();
                  if (s.isNotEmpty && s != '-') {
                    dateFormattedText = s;
                  }
                }
              }

              // Duration spent calculation
              int elapsedSec = 0;
              if (item['elapsed_seconds'] is int) {
                elapsedSec = item['elapsed_seconds'] as int;
              } else if (item['elapsed_seconds'] is num) {
                elapsedSec = (item['elapsed_seconds'] as num).toInt();
              } else if (rawDate != null) {
                try {
                  final startDt = DateTime.parse(rawDate.toString()).toLocal();
                  final rawEnd = item['end_time'] ?? item['updated_at'];
                  final endDt = (isCompleted && rawEnd != null)
                      ? DateTime.parse(rawEnd.toString()).toLocal()
                      : DateTime.now();
                  elapsedSec = endDt.difference(startDt).inSeconds;
                  if (elapsedSec < 0) elapsedSec = 0;
                } catch (_) {}
              }

              String durationFormatted;
              if (isLocked) {
                durationFormatted = 'Terkunci';
              } else if (isInProgress) {
                if (elapsedSec <= 0) {
                  durationFormatted = 'Sedang Berjalan';
                } else {
                  final hours = elapsedSec ~/ 3600;
                  final minutes = (elapsedSec % 3600) ~/ 60;
                  if (hours > 0) {
                    durationFormatted = '${hours}j ${minutes}m';
                  } else {
                    durationFormatted = '$minutes Menit';
                  }
                }
              } else if (isEnded && elapsedSec <= 0) {
                durationFormatted = 'Tidak Dikerjakan';
              } else if (elapsedSec <= 0) {
                durationFormatted = '< 1 Menit';
              } else {
                final hours = elapsedSec ~/ 3600;
                final minutes = (elapsedSec % 3600) ~/ 60;
                if (hours > 0) {
                  durationFormatted = '${hours}j ${minutes}m';
                } else {
                  durationFormatted = '$minutes Menit';
                }
              }

              // Score / Result text
              String scoreText;
              if (score != null) {
                scoreText = '$score / 100';
              } else if (isLocked) {
                scoreText = 'Sesi Terhenti';
              } else if (isInProgress) {
                scoreText = 'Sedang Ujian';
              } else if (isEnded) {
                scoreText = 'Waktu Habis';
              } else {
                scoreText = 'Terkirim';
              }

              // Integrity summary
              String integritySummary;
              Color integritySummaryColor;
              IconData integritySummaryIcon;

              if (isLocked) {
                integritySummary = violationsCount > 0 ? '$violationsCount Pelanggaran' : 'Sesi Terkunci';
                integritySummaryColor = AppTheme.dangerRed;
                integritySummaryIcon = Icons.gpp_bad_rounded;
              } else if (violationsCount > 0) {
                integritySummary = '$violationsCount Pelanggaran';
                integritySummaryColor = const Color(0xFFF59E0B);
                integritySummaryIcon = Icons.gpp_maybe_rounded;
              } else if (isEnded && elapsedSec <= 0) {
                integritySummary = 'Tidak Mengerjakan';
                integritySummaryColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
                integritySummaryIcon = Icons.remove_circle_outline_rounded;
              } else {
                integritySummary = 'Integritas Bersih (0)';
                integritySummaryColor = isDark ? AppTheme.textSecondary : const Color(0xFF64748B);
                integritySummaryIcon = Icons.verified_user_rounded;
              }

              final Color scoreColor = score != null
                  ? AppTheme.accentGreen
                  : (isLocked
                      ? AppTheme.dangerRed
                      : (isInProgress
                          ? const Color(0xFFF59E0B)
                          : (isEnded
                              ? (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B))
                              : const Color(0xFF38BDF8))));

              final IconData scoreIcon = score != null
                  ? Icons.military_tech_rounded
                  : (isLocked
                      ? Icons.error_outline_rounded
                      : (isInProgress
                          ? Icons.timelapse_rounded
                          : (isEnded
                              ? Icons.event_busy_rounded
                              : Icons.task_alt_rounded)));

              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  child: Ink(
                    decoration: BoxDecoration(
                      gradient: isDark
                          ? const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color(0xFF1E293B),
                                Color(0xFF0F172A),
                              ],
                            )
                          : const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Colors.white,
                                Color(0xFFF8FAFC),
                              ],
                            ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isLocked
                            ? AppTheme.dangerRed.withOpacity(0.5)
                            : (isInProgress
                                ? const Color(0xFFF59E0B).withOpacity(0.5)
                                : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0))),
                        width: isLocked || isInProgress ? 1.5 : 1,
                      ),
                      boxShadow: [
                        if (isLocked)
                          BoxShadow(
                            color: AppTheme.dangerRed.withOpacity(0.08),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          )
                        else if (isInProgress)
                          BoxShadow(
                            color: const Color(0xFFF59E0B).withOpacity(0.08),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          )
                        else if (!isDark)
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 12,
                            offset: const Offset(0, 3),
                          ),
                      ],
                    ),
                    child: InkWell(
                      onTap: () => _showHistoryDetailModal(item),
                      borderRadius: BorderRadius.circular(16),
                      splashColor: statusColor.withOpacity(0.12),
                      highlightColor: statusColor.withOpacity(0.06),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Top Badges Row: Subject Badge + Status Badge
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryShiei.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: AppTheme.primaryShiei.withOpacity(0.35)),
                                  ),
                                  child: Text(
                                    subject.toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.primaryGlow,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                                  decoration: BoxDecoration(
                                    color: statusColor.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: statusColor.withOpacity(0.4), width: 1),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(statusIcon, size: 12, color: statusColor),
                                      const SizedBox(width: 4),
                                      Text(
                                        statusLabel,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: statusColor,
                                          letterSpacing: 0.4,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Title & Date Row
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: statusColor.withOpacity(0.15),
                                    border: Border.all(color: statusColor.withOpacity(0.35)),
                                  ),
                                  child: Icon(statusIcon, color: statusColor, size: 20),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        link['title'] ?? 'Ujian Digital',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                          color: isDark ? Colors.white : AppTheme.textPrimaryLight,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.schedule_rounded,
                                            size: 13,
                                            color: isDark ? AppTheme.textSecondary : AppTheme.textSecondaryLight,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            dateFormattedText,
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              color: isDark ? AppTheme.textSecondary : AppTheme.textSecondaryLight,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),

                            // Bento Metadata Strip (Waktu Pengerjaan & STATUS)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF090D16).withOpacity(0.6) : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isDark ? const Color(0xFF334155).withOpacity(0.7) : const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: Row(
                                children: [
                                  // Duration spent
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'WAKTU PENGERJAAN',
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.textMuted,
                                            letterSpacing: 0.3,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Row(
                                          children: [
                                            const Icon(Icons.timelapse_rounded, size: 13, color: AppTheme.primaryGlow),
                                            const SizedBox(width: 4),
                                            Text(
                                              durationFormatted,
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: isDark ? Colors.white : AppTheme.textPrimaryLight,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    width: 1,
                                    height: 26,
                                    color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                                  ),
                                  const SizedBox(width: 12),
                                  // Score or Result Status
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'STATUS',
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.textMuted,
                                            letterSpacing: 0.3,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Row(
                                          children: [
                                            Icon(
                                              scoreIcon,
                                              size: 13,
                                              color: scoreColor,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              scoreText,
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: scoreColor,
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
                            const SizedBox(height: 12),

                            // Bottom Footer: Integrity badge + CTA button
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      integritySummaryIcon,
                                      size: 14,
                                      color: integritySummaryColor,
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      integritySummary,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: integritySummaryColor,
                                      ),
                                    ),
                                  ],
                                ),
                                const Row(
                                  children: [
                                    Text(
                                      'Lihat Rincian',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.primaryGlow,
                                      ),
                                    ),
                                    SizedBox(width: 3),
                                    Icon(Icons.chevron_right_rounded, size: 16, color: AppTheme.primaryGlow),
                                  ],
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
            }).toList(),
        ],
      ),
    );
  }

  Widget _buildProfileTab(Map<String, dynamic>? user) {
    if (user == null || _controller.isProfileManualRefreshing) {
      return RefreshIndicator(
        color: AppTheme.primaryShiei,
        onRefresh: () => _controller.refreshProfile(isManualRefresh: true),
        child: const StudentProfileSkeleton(),
      );
    }

    final school = user['school'] as Map<String, dynamic>?;
    final schoolName = school?['name'] ?? 'SEKOLAH DIGITAL SHIEI';

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDark = AppTheme.isDark(context);
        return RefreshIndicator(
          color: AppTheme.primaryShiei,
          onRefresh: () => _controller.refreshProfile(isManualRefresh: true),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight > 50 ? constraints.maxHeight - 40 : 400,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Digital Exam Pass ID Card (Official Exam Passport)
                    Container(
                      key: _tourKeys.profileCardKey,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        gradient: isDark
                            ? const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color(0xFF1E293B),
                                  Color(0xFF0F172A),
                                  Color(0xFF0B1120),
                                ],
                              )
                            : const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Colors.white,
                                  Color(0xFFF8FAFC),
                                  Color(0xFFF1F5F9),
                                ],
                              ),
                        border: Border.all(
                          color: isDark ? AppTheme.primaryShiei.withOpacity(0.4) : AppTheme.primaryShiei.withOpacity(0.25),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: isDark ? AppTheme.primaryShiei.withOpacity(0.16) : AppTheme.primaryShiei.withOpacity(0.08),
                            blurRadius: 28,
                            offset: const Offset(0, 8),
                          ),
                          BoxShadow(
                            color: isDark ? Colors.black45 : Colors.black.withOpacity(0.04),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Card Top Header Ribbon
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                            decoration: BoxDecoration(
                              color: isDark ? AppTheme.surfaceCard.withOpacity(0.6) : const Color(0xFFF1F5F9),
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(21)),
                              border: Border(
                                bottom: BorderSide(
                                  color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                                  width: 1,
                                ),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: AppTheme.primaryShiei.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(Icons.school_rounded, color: AppTheme.primaryGlow, size: 16),
                                    ),
                                    const SizedBox(width: 8),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          schoolName.toUpperCase(),
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            color: isDark ? Colors.white : AppTheme.textPrimaryLight,
                                            letterSpacing: 0.6,
                                          ),
                                        ),
                                        Text(
                                          'KARTU TANDA PESERTA',
                                          style: TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w600,
                                            color: isDark ? AppTheme.textSecondary : AppTheme.textSecondaryLight,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppTheme.accentGreen.withOpacity(0.18),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: AppTheme.accentGreen.withOpacity(0.4)),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.verified_rounded, color: AppTheme.accentGreen, size: 12),
                                      SizedBox(width: 4),
                                      Text(
                                        'AKTIF',
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.accentGreen,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Student Main Profile Info
                          Padding(
                            padding: const EdgeInsets.all(20),
                            child: Row(
                              children: [
                                Container(
                                  width: 68,
                                  height: 68,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        AppTheme.primaryGlow.withOpacity(0.35),
                                        AppTheme.primaryShiei.withOpacity(0.15),
                                      ],
                                    ),
                                    border: Border.all(
                                      color: AppTheme.primaryShiei.withOpacity(0.6),
                                      width: 2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppTheme.primaryShiei.withOpacity(0.25),
                                        blurRadius: 14,
                                      ),
                                    ],
                                  ),
                                  child: const Center(
                                    child: Icon(Icons.person_rounded, size: 38, color: AppTheme.primaryGlow),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        user['name'] ?? 'Peserta Ujian',
                                        style: TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w800,
                                          color: isDark ? Colors.white : AppTheme.textPrimaryLight,
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: isDark ? const Color(0xFF0F172A) : Colors.white,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(
                                            color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                                          ),
                                        ),
                                        child: Text(
                                          'NISN: ${user['nisn'] ?? '-'}',
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w600,
                                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
                                            fontFamily: 'monospace',
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          const Icon(Icons.lock_person_rounded, size: 13, color: AppTheme.primaryGlow),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Peran: Siswa / Peserta Didik',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: isDark ? AppTheme.textSecondary.withOpacity(0.9) : AppTheme.textSecondaryLight,
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
                        ],
                      ),
                    ),



                    // 2. Pengaturan Akun & Preferensi (Grouped Bento Surface)
                    const SizedBox(height: 18),
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 8),
                      child: Text(
                        'PENGATURAN & PREFERENSI',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                        ),
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        color: isDark ? AppTheme.surfaceDark : Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          // Ubah Kata Sandi
                          Material(
                            color: Colors.transparent,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(17)),
                            child: InkWell(
                              onTap: () => ChangePasswordDialog.show(context),
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(17)),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFEA580C).withValues(alpha: isDark ? 0.2 : 0.1),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(Icons.lock_reset_rounded, color: Color(0xFFEA580C), size: 19),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Ubah Kata Sandi',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                                            ),
                                          ),
                                          const SizedBox(height: 1),
                                          Text(
                                            'Perbarui kata sandi akun untuk keamanan ujian',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(
                                      Icons.chevron_right_rounded,
                                      color: isDark ? AppTheme.textSecondary : const Color(0xFF94A3B8),
                                      size: 20,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Divider(height: 1, indent: 62, color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9)),

                          // Efek Suara & Audio
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF3B82F6).withValues(alpha: isDark ? 0.2 : 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    _isAudioFeedbackEnabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                                    color: const Color(0xFF3B82F6),
                                    size: 19,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Efek Suara & Audio',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                                        ),
                                      ),
                                      const SizedBox(height: 1),
                                      Text(
                                        'Peringatan suara sisa waktu & notifikasi ujian',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Switch.adaptive(
                                  value: _isAudioFeedbackEnabled,
                                  activeTrackColor: const Color(0xFFEA580C),
                                  onChanged: (val) async {
                                    await TokenStorage.setAudioFeedbackEnabled(val);
                                    if (mounted) setState(() => _isAudioFeedbackEnabled = val);
                                  },
                                ),
                              ],
                            ),
                          ),
                          Divider(height: 1, indent: 62, color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9)),

                          // Pengaturan & Info Aplikasi
                          Material(
                            color: Colors.transparent,
                            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(17)),
                            child: InkWell(
                              onTap: () => Navigator.of(context).pushNamed(AppRoutes.settings),
                              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(17)),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF64748B).withValues(alpha: isDark ? 0.2 : 0.1),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(Icons.tune_rounded, color: Color(0xFF64748B), size: 19),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Pengaturan & Info Aplikasi',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                                            ),
                                          ),
                                          const SizedBox(height: 1),
                                          Text(
                                            'Versi aplikasi, cache data, dan preferensi umum',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(
                                      Icons.chevron_right_rounded,
                                      color: isDark ? AppTheme.textSecondary : const Color(0xFF94A3B8),
                                      size: 20,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                // Action Buttons at Bottom
                Padding(
                  padding: const EdgeInsets.only(top: 24, bottom: 8),
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFEF4444),
                      backgroundColor: const Color(0xFFEF4444).withValues(alpha: isDark ? 0.12 : 0.06),
                      side: BorderSide(
                        color: const Color(0xFFEF4444).withValues(alpha: isDark ? 0.35 : 0.25),
                        width: 1.2,
                      ),
                      minimumSize: const Size(double.infinity, 46),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: _confirmLogout,
                    icon: const Icon(Icons.logout_rounded, size: 18),
                    label: const Text(
                      'Keluar dari Akun Ujian',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

  Widget _buildExamCard(Map<String, dynamic> exam) {
    final isDark = AppTheme.isDark(context);
    final subject = exam['subject'] ?? 'Umum';
    final className = exam['class_major']?['name'] ?? 'Semua Kelas';
    final teacherName = (exam['teacher_name'] ?? exam['creator']?['name'])?.toString();
    final duration = exam['duration'] ?? exam['duration_minutes'] ?? 60;
    final startTime = exam['start_time'];
    final endTime = exam['end_time'];

    // Format comprehensive date & time schedule
    String dateFormatted = 'Sesuai Jadwal';
    String timeWindowFormatted = 'Waktu Fleksibel';
    if (startTime != null) {
      try {
        final startDt = DateTime.parse(startTime.toString()).toLocal();
        dateFormatted = DateFormat('d MMM yyyy', 'id_ID').format(startDt);
        final startHm = DateFormat('HH:mm').format(startDt);
        if (endTime != null) {
          final endDt = DateTime.parse(endTime.toString()).toLocal();
          final endHm = DateFormat('HH:mm').format(endDt);
          timeWindowFormatted = '$startHm - $endHm WIB';
        } else {
          timeWindowFormatted = 'Mulai pk $startHm WIB';
        }
      } catch (_) {
        dateFormatted = 'Sesuai Jadwal';
        timeWindowFormatted = 'Waktu Fleksibel';
      }
    }

    final isLocked = exam['is_locked'] == true;
    final isUpcoming = exam['is_upcoming'] == true;
    final isExpired = exam['is_expired'] == true;
    final isAvailable = exam['is_available'] == true;
    final progressStatus = (exam['progress']?['status'] ?? '').toString().toLowerCase();
    final isInProgress = progressStatus == 'in_progress' && !isLocked;

    final rawToken = exam['token'];
    final tokenMode = exam['token_mode'];
    final bool requiresToken = (rawToken != null &&
        rawToken.toString().trim().isNotEmpty &&
        tokenMode != 'none') || tokenMode == 'rotating_5m';

    String tokenModeLabel;
    IconData tokenModeIcon;
    Color tokenModeColor;

    if (requiresToken) {
      tokenModeLabel = 'Wajib Token';
      tokenModeIcon = Icons.vpn_key_rounded;
      tokenModeColor = AppTheme.accentYellow;
    } else {
      tokenModeLabel = 'Tanpa Token';
      tokenModeIcon = Icons.lock_open_rounded;
      tokenModeColor = AppTheme.accentGreen;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isLocked
              ? AppTheme.dangerRed.withValues(alpha: 0.6)
              : (isInProgress
                  ? const Color(0xFFF59E0B).withValues(alpha: 0.6)
                  : (isAvailable
                      ? AppTheme.primaryBlue.withValues(alpha: 0.45)
                      : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)))),
          width: isLocked || isInProgress || isAvailable ? 1.5 : 1,
        ),
        boxShadow: [
          if (isAvailable && !isLocked)
            BoxShadow(
              color: AppTheme.primaryBlue.withValues(alpha: isDark ? 0.08 : 0.12),
              blurRadius: 14,
              offset: const Offset(0, 4),
            )
          else if (!isDark)
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row: Subject Badge, Class Badge, Status Badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Subject Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.primaryBlue.withValues(alpha: 0.3), width: 0.8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.menu_book_rounded, size: 12, color: AppTheme.primaryBlue),
                    const SizedBox(width: 4),
                    Text(
                      subject,
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppTheme.primaryBlue),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              // Class / Target Audience Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.3), width: 0.8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.school_rounded, size: 12, color: Color(0xFFA78BFA)),
                    const SizedBox(width: 4),
                    Text(
                      className,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isDark ? const Color(0xFFA78BFA) : const Color(0xFF7C3AED),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // Status Badge
              _buildStatusBadge(
                isLocked: isLocked,
                isInProgress: isInProgress,
                isUpcoming: isUpcoming,
                isExpired: isExpired,
                isAvailable: isAvailable,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Exam Title
          Text(
            exam['title'] ?? 'Ujian Tanpa Judul',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : AppTheme.textPrimaryLight,
              height: 1.3,
            ),
          ),

          // Teacher / Creator Name (if present)
          if (teacherName != null && teacherName.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.person_pin_rounded,
                  size: 13,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
                const SizedBox(width: 4),
                Text(
                  'Pengampu: $teacherName',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),

          // Detailed Info Box (Bento Details)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF090D1A) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                // Top Row: Duration & Token Mode
                Row(
                  children: [
                    // Duration
                    Expanded(
                      child: Row(
                        children: [
                          const Icon(Icons.timer_rounded, size: 14, color: Color(0xFFF59E0B)),
                          const SizedBox(width: 6),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Alokasi Waktu',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  color: isDark ? AppTheme.textSecondary : AppTheme.textSecondaryLight,
                                ),
                              ),
                              Text(
                                FormatUtils.formatDurationHoursMinutes(duration),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : AppTheme.textPrimaryLight,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Container(
                      height: 24,
                      width: 1,
                      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFCBD5E1),
                    ),
                    const SizedBox(width: 12),
                    // Token Mode
                    Expanded(
                      child: Row(
                        children: [
                          Icon(tokenModeIcon, size: 14, color: tokenModeColor),
                          const SizedBox(width: 6),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Pengaturan Token',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  color: isDark ? AppTheme.textSecondary : AppTheme.textSecondaryLight,
                                ),
                              ),
                              Text(
                                tokenModeLabel,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                  color: tokenModeColor,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Divider(
                    color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                    height: 1,
                  ),
                ),
                // Bottom Row: Date & Time Window
                Row(
                  children: [
                    const Icon(Icons.event_note_rounded, size: 14, color: Color(0xFF38BDF8)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            dateFormatted,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF334155),
                            ),
                          ),
                          Text(
                            timeWindowFormatted,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Security Violation Lock Notice (if locked)
          if (isLocked) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.dangerDark.withValues(alpha: 0.25) : const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDark ? AppTheme.dangerRed.withValues(alpha: 0.4) : const Color(0xFFFECACA),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lock_rounded, color: AppTheme.dangerRed, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Sesi Ujian Terkunci',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.dangerRed),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatLockReason(exam['lock_reason']?.toString()),
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? const Color(0xFFFCA5A5) : const Color(0xFF991B1B),
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 14),

          // Primary CTA Action Button
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: isLocked
                    ? AppTheme.dangerRed
                    : (isInProgress
                        ? const Color(0xFFF59E0B)
                        : (isAvailable
                            ? AppTheme.primaryBlue
                            : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)))),
                foregroundColor: isAvailable || isInProgress || isLocked
                    ? Colors.white
                    : (isDark ? Colors.white60 : const Color(0xFF475569)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: isAvailable || isInProgress ? 2 : 0,
              ),
              onPressed: () => _enterExam(exam),
              icon: Icon(
                isLocked
                    ? Icons.lock_open_rounded
                    : (isInProgress
                        ? Icons.play_circle_fill_rounded
                        : (isAvailable
                            ? (requiresToken ? Icons.vpn_key_rounded : Icons.play_arrow_rounded)
                            : (isExpired ? Icons.event_busy_rounded : Icons.schedule_rounded))),
                size: 18,
              ),
              label: Text(
                isLocked
                    ? 'Lihat Status Terkunci'
                    : (isInProgress
                        ? 'Lanjutkan Pengerjaan'
                        : (isAvailable
                            ? (requiresToken ? 'Mulai (Masukkan Token)' : 'Mulai Mengerjakan')
                            : (isExpired ? 'Ujian Telah Berakhir' : 'Belum Waktunya ($timeWindowFormatted)'))),
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge({
    required bool isLocked,
    required bool isInProgress,
    required bool isUpcoming,
    required bool isExpired,
    required bool isAvailable,
  }) {
    if (isLocked) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
        decoration: BoxDecoration(
          color: AppTheme.dangerRed.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppTheme.dangerRed.withValues(alpha: 0.4), width: 0.8),
        ),
        child: const Text('TERKUNCI', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.dangerRed)),
      );
    }
    if (isInProgress) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
        decoration: BoxDecoration(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4), width: 0.8),
        ),
        child: const Text('SEDANG DIKERJAKAN', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFFBBF24))),
      );
    }
    if (isAvailable) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
        decoration: BoxDecoration(
          color: AppTheme.accentGreen.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppTheme.accentGreen.withValues(alpha: 0.4), width: 0.8),
        ),
        child: const Text('AKTIF', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.accentGreen)),
      );
    }
    if (isExpired) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
        decoration: BoxDecoration(
          color: const Color(0xFF64748B).withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF64748B).withValues(alpha: 0.3), width: 0.8),
        ),
        child: const Text('BERAKHIR', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF94A3B8))),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.3), width: 0.8),
      ),
      child: const Text('AKAN DATANG', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF38BDF8))),
    );
  }
}
