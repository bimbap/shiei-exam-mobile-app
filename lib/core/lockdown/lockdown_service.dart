import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../config/routes.dart';
import '../../main.dart' show appNavigatorKey;
import '../../shared/widgets/app_notification.dart';
import '../api/api_client.dart';
import '../api/endpoints.dart';
import '../auth/token_storage.dart';
import 'alarm_player_service.dart';
import 'cheat_reporter.dart';
import 'volume_lock_service.dart';

class LockdownService with WidgetsBindingObserver {
  static final LockdownService _instance = LockdownService._internal();
  factory LockdownService() => _instance;

  LockdownService._internal();

  final ApiClient _api = ApiClient();
  int? _activeExamId;
  BuildContext? _currentContext;
  bool _isLockdownActive = false;
  bool _isHandlingViolation = false;
  bool _isOnPhoneCall = false;
  bool _isCharging = false;
  StreamSubscription<dynamic>? _screenshotSubscription;

  static const EventChannel _screenshotEventChannel =
      EventChannel('id.shiei/lockdown_events');

  bool get isHandlingViolation => _isHandlingViolation;
  bool get isLockdownActive => _isLockdownActive;
  bool get isOnPhoneCall => _isOnPhoneCall;
  bool get isCharging => _isCharging;

  /**
   * Start lockdown enforcement for an active exam.
   */
  void startExamMonitoring({
    required int examId,
    required BuildContext context,
  }) {
    _activeExamId = examId;
    _currentContext = context;
    _isLockdownActive = true;
    _isHandlingViolation = false;
    _isOnPhoneCall = false;
    _isCharging = false;

    // Keep screen awake during exam
    WakelockPlus.enable();

    // Enforce bright screen (>= 40% minimum)
    VolumeLockService.setWindowBrightness(60);

    // Native protection relies on FLAG_SECURE (anti-screenshot/recents),
    // setHideOverlayWindows, and PopScope back-button blocking for 100% smooth entry
    // without triggering heavy Android OS Screen Pinning freezes.

    // Initial check for charging status
    VolumeLockService.isDeviceCharging().then((charging) {
      _isCharging = charging;
      if (charging && _activeExamId != null) {
        _api.post(
          ApiEndpoints.chargingStatus,
          data: {'link_id': _activeExamId, 'is_charging': true},
        ).then((_) => null, onError: (_) => null);
      }
    });

    // Register lifecycle observer
    WidgetsBinding.instance.addObserver(this);

    // Subscribe to native screenshot detection (Android 14+ ScreenCaptureCallback)
    _screenshotSubscription?.cancel();
    _screenshotSubscription = _screenshotEventChannel
        .receiveBroadcastStream()
        .listen((event) async {
      if (!_isLockdownActive || _isHandlingViolation) return;
      if (event == 'screenshot_attempt') {
        final isProtected = await TokenStorage.isScreenshotProtectionEnabled();
        if (!isProtected) {
          debugPrint('[LockdownService] Screenshot attempt detected, but bypassed in debug mode.');
          return;
        }
        handleViolation(
          eventType: 'screenshot_attempt',
          details: 'Tangkapan layar berhasil diambil saat ujian berlangsung.',
        );
      }
    }, onError: (_) {});
  }

  /**
   * Stop lockdown enforcement when exam is submitted safely or on violation.
   */
  void stopExamMonitoring({bool stopAlarm = true, bool keepViolationFlag = false}) {
    if (_isOnPhoneCall && _activeExamId != null) {
      _api.post(
        ApiEndpoints.phoneCallStatus,
        data: {'link_id': _activeExamId, 'is_on_call': false},
      ).then((_) => null, onError: (_) => null);
    }

    // Do NOT falsely notify backend that charging stopped when device might still be physically plugged in!
    // The device hardware status poller handles notifying when the cable is physically detached.

    _isLockdownActive = false;
    _activeExamId = null;
    _currentContext = null;
    if (!keepViolationFlag) {
      _isHandlingViolation = false;
    }
    _isOnPhoneCall = false;
    _isCharging = false;

    // Stop native Kiosk mode pinning
    VolumeLockService.stopLockTask();

    WakelockPlus.disable();
    WidgetsBinding.instance.removeObserver(this);
    _screenshotSubscription?.cancel();
    _screenshotSubscription = null;
    if (stopAlarm) {
      AlarmPlayerService.stopSiren();
    }
  }

  /**
   * Reset violation state flag when user exits lockout screen.
   */
  void resetViolationState() {
    _isHandlingViolation = false;
  }

  /**
   * Monitor active phone call state during exam session.
   * Business Logic Requirement: Phone calls during exams are permitted without lockout penalty,
   * but the active call state is automatically and immediately reported to proctors on panel & app.
   */
  Future<void> checkPhoneCallState() async {
    if (!_isLockdownActive || _activeExamId == null) return;

    final isCall = await VolumeLockService.isPhoneCallActive();
    if (isCall != _isOnPhoneCall) {
      _isOnPhoneCall = isCall;
      debugPrint('[LockdownService] Voice Call status changed: $isCall. Reporting to proctor live monitor.');
      try {
        await _api.post(
          ApiEndpoints.phoneCallStatus,
          data: {
            'link_id': _activeExamId,
            'is_on_call': isCall,
          },
        );
      } catch (e) {
        debugPrint('[LockdownService] Error updating phone call status: $e');
      }
    }
  }

  /**
   * Monitor device charging state during exam session.
   * Requirement: Charging is permitted at all times without penalty/alarm.
   * Notifies backend so Live Monitoring displays a charging indicator to proctors.
   */
  Future<void> checkChargingState() async {
    if (!_isLockdownActive || _activeExamId == null) return;

    final isChargingNow = await VolumeLockService.isDeviceCharging();
    if (isChargingNow != _isCharging) {
      _isCharging = isChargingNow;
      debugPrint('[LockdownService] Charging state changed: $isChargingNow. Notifying live monitoring.');
      try {
        await _api.post(
          ApiEndpoints.chargingStatus,
          data: {
            'link_id': _activeExamId,
            'is_charging': isChargingNow,
          },
        );
      } catch (e) {
        debugPrint('[LockdownService] Error updating charging status: $e');
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (!_isLockdownActive || _activeExamId == null || _isHandlingViolation) return;

    // Check if app changed state due to an incoming or active phone call (WhatsApp, Discord, Cellular)
    // Business Requirement: Phone call during exam does NOT lock the exam, but auto-reports to panel & app!
    final bool isPhoneCall = await VolumeLockService.isPhoneCallActive();
    if (isPhoneCall) {
      if (!_isOnPhoneCall) {
        _isOnPhoneCall = true;
        try {
          await _api.post(
            ApiEndpoints.phoneCallStatus,
            data: {
              'link_id': _activeExamId,
              'is_on_call': true,
            },
          );
        } catch (_) {}
      }
      debugPrint('[LockdownService] Voice call active during lifecycle change. Bypassing lockout ejection.');
      return; // Do NOT trigger app_minimize or overlay_detected
    }

    if (state == AppLifecycleState.paused) {
      // Allow brief 250ms debounce window for VoIP audio pipeline (WhatsApp, Telegram, Discord)
      // to bind audio focus when full-screen incoming call activity launches
      await Future.delayed(const Duration(milliseconds: 250));
      if (!_isLockdownActive || _isHandlingViolation) return;

      final isPhoneCallOnPause = await VolumeLockService.isPhoneCallActive();
      if (isPhoneCallOnPause) {
        if (!_isOnPhoneCall) {
          _isOnPhoneCall = true;
          try {
            await _api.post(
              ApiEndpoints.phoneCallStatus,
              data: {
                'link_id': _activeExamId,
                'is_on_call': true,
              },
            );
          } catch (_) {}
        }
        debugPrint('[LockdownService] Voice call active on pause. Bypassing app_minimize.');
        return; // Do NOT trigger app_minimize
      }

      final isExitBypass = await TokenStorage.isAppExitBypassEnabled();
      if (isExitBypass) {
        debugPrint('[LockdownService] App minimize / pause bypassed in debug mode.');
        return;
      }
      // User minimized the app or switched tasks
      handleViolation(
        eventType: 'app_minimize',
        details: 'Aplikasi diminimalkan atau siswa mencoba keluar ke menu utama.',
      );
    } else if (state == AppLifecycleState.inactive) {
      // Debounce: plugging in a charger, transient system battery HUD, or screenshot preview
      // can trigger a brief inactive state.
      await Future.delayed(const Duration(milliseconds: 650));
      if (!_isLockdownActive || WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        return;
      }

      // Check if focus loss was triggered by an incoming phone call / VoIP call heads-up banner
      final isCallNow = await VolumeLockService.isPhoneCallActive();
      if (isCallNow) {
        if (!_isOnPhoneCall) {
          _isOnPhoneCall = true;
          try {
            await _api.post(
              ApiEndpoints.phoneCallStatus,
              data: {
                'link_id': _activeExamId,
                'is_on_call': true,
              },
            );
          } catch (_) {}
        }
        debugPrint('[LockdownService] Voice call banner active during inactive state. Bypassing overlay.');
        return; // Do NOT trigger overlay_detected
      }

      // Check if focus loss was triggered by hardware screenshot shortcut (Power + Volume Down)
      final wasScreenshot = await VolumeLockService.wasRecentScreenshotKey();
      if (wasScreenshot) {
        final isProtected = await TokenStorage.isScreenshotProtectionEnabled();
        if (!isProtected) {
          debugPrint('[LockdownService] Screenshot key combo detected, but bypassed in debug mode.');
          return;
        }
        handleViolation(
          eventType: 'screenshot_attempt',
          details: 'Percobaan tangkapan layar (kombinasi tombol hardware screenshot) terdeteksi.',
        );
        return;
      }

      final isExitBypass = await TokenStorage.isAppExitBypassEnabled();
      if (isExitBypass) {
        debugPrint('[LockdownService] Overlay / inactive state bypassed in debug mode.');
        return;
      }

      // Non-system overlay, floating chat heads, or status bar pulled down
      handleViolation(
        eventType: 'overlay_detected',
        details: 'Tirai notifikasi, jendela mengambang, atau aplikasi overlay terdeteksi di atas layar ujian.',
      );
    }
  }

  /**
   * Check for multi-window / split-screen mode on Android.
   */
  Future<void> checkSplitScreen() async {
    if (!_isLockdownActive || _activeExamId == null) return;

    final isExitBypass = await TokenStorage.isAppExitBypassEnabled();
    if (isExitBypass) return;

    final inMulti = await VolumeLockService.isMultiWindow();
    if (inMulti) {
      await handleViolation(
        eventType: 'split_screen',
        details: 'Mode layar terbagi (Split Screen / Multi-Window) terdeteksi aktif saat ujian berlangsung.',
      );
    }
  }

  /**
   * Check whether any floating window, Picture-in-Picture, or overlay is active during exam.
   */
  Future<void> checkOverlay() async {
    if (!_isLockdownActive || _activeExamId == null || _isHandlingViolation) return;

    final isExitBypass = await TokenStorage.isAppExitBypassEnabled();
    if (isExitBypass) return;

    // Check if phone or VoIP call is active first so call heads-up HUD is never misclassified as overlay
    final isCall = await VolumeLockService.isPhoneCallActive();
    if (isCall) {
      await checkPhoneCallState();
      return;
    }

    final overlayResult = await VolumeLockService.detectFloatingWindowOrOverlay();
    if (overlayResult['is_call_active'] == true) {
      await checkPhoneCallState();
      return;
    }

    if (overlayResult['has_overlay'] == true) {
      final reason = overlayResult['reason']?.toString() ?? 'Jendela mengambang atau overlay terdeteksi aktif.';
      await handleViolation(
        eventType: 'overlay_detected',
        details: 'Aplikasi mengambang terdeteksi aktif: $reason',
      );
    }
  }

  /**
   * Check whether Bluetooth has been activated during exam session.
   * Anti-cheat requirement: Bluetooth must remain OFF throughout the exam.
   */
  Future<void> checkBluetooth() async {
    if (!_isLockdownActive || _activeExamId == null) return;

    final isBtOn = await VolumeLockService.isBluetoothEnabled();
    if (isBtOn) {
      await handleViolation(
        eventType: 'bluetooth_enabled',
        details: 'Bluetooth terdeteksi aktif saat sesi ujian berlangsung.',
      );
    }
  }

  /**
   * Check whether an external display, HDMI, or screen mirror is connected.
   */
  Future<void> checkExternalDisplay() async {
    if (!_isLockdownActive || _activeExamId == null) return;

    final hasExternal = await VolumeLockService.isExternalDisplayConnected();
    if (hasExternal) {
      await handleViolation(
        eventType: 'external_display',
        details: 'Layar eksternal, kabel HDMI, atau screen mirror nirkabel terdeteksi tersambung.',
      );
    }
  }

  /**
   * Trigger the anti-cheat sequence:
   * 1. 100% Volume Loud Alarm
   * 2. Eject from exam / wipe progress
   * 3. Report to server
   * 4. Navigate to persistent red lockout screen
   */
  Future<void> handleViolation({
    required String eventType,
    required String details,
  }) async {
    if (_isHandlingViolation) return;
    _isHandlingViolation = true;

    final examId = _activeExamId;
    final context = _currentContext;

    // 1. Play loud siren (lockHardwareVolume = false so student can lower volume with physical buttons)
    await AlarmPlayerService.playSiren(lockHardwareVolume: false);

    // 2. Report incident to backend with current device telemetry
    if (examId != null) {
      final battery = await VolumeLockService.getBatteryLevel();
      final network = await VolumeLockService.getNetworkType();
      final isCharging = await VolumeLockService.isDeviceCharging();
      await CheatReporter.reportViolation(
        linkId: examId,
        eventType: eventType,
        metadata: {
          'reason': details,
          'alarm_triggered': true,
          'battery_level': battery,
          'network_type': network,
          'is_charging': isCharging,
        },
      );
    }

    // Hide any active push notification overlay first so it doesn't leak into lockout screen
    AppNotification.hide();

    // Stop active lifecycle observer before route push without killing the siren alarm,
    // and keep violation flag so ExamPlayerScreen.dispose does not silence the siren!
    stopExamMonitoring(stopAlarm: false, keepViolationFlag: true);

    // 3. Eject and navigate to locked screen cleanly via root navigator after current frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final nav = appNavigatorKey.currentState;
      if (nav != null) {
        nav.pushNamedAndRemoveUntil(
          AppRoutes.lockout,
          (route) => false,
          arguments: {
            'exam_id': examId,
            'event_type': eventType,
            'details': details,
          },
        );
      } else if (context != null && context.mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          AppRoutes.lockout,
          (route) => false,
          arguments: {
            'exam_id': examId,
            'event_type': eventType,
            'details': details,
          },
        );
      }
    });
  }
}
