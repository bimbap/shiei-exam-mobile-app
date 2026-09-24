import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../../config/routes.dart';
import '../../core/api/api_client.dart';
import '../../core/api/endpoints.dart';
import '../../core/auth/token_storage.dart';
import '../../core/lockdown/cheat_reporter.dart';
import '../../core/lockdown/lockdown_service.dart';
import '../../core/lockdown/volume_lock_service.dart';
import '../../core/notifications/exam_reminder_service.dart';
import '../../main.dart' show appNavigatorKey;
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/app_notification.dart';
import 'exam_timer_widget.dart';
import 'url_exam_player.dart';
import 'widgets/exam_announcement_banner.dart';

class ExamPlayerScreen extends StatefulWidget {
  final Map<String, dynamic> exam;

  const ExamPlayerScreen({
    super.key,
    required this.exam,
  });

  @override
  State<ExamPlayerScreen> createState() => _ExamPlayerScreenState();
}

class _ExamPlayerScreenState extends State<ExamPlayerScreen> {
  final _api = ApiClient();
  final _lockdown = LockdownService();
  InAppWebViewController? _webViewController;
  Timer? _monitoringPoller;
  Timer? _clockTimer;
  Timer? _heartbeatTimer;
  String _timeString = '';
  int _batteryLevel = 100;
  bool _isCharging = false;
  String _networkType = 'wifi';
  bool _isSubmitting = false;
  bool _isReadyToRenderWebView = false;
  bool _isHandshakeVerified = false;
  bool _isHandshakeInProgress = true;
  String? _handshakeErrorMessage;
  bool _isTrackingInterrupted = false;
  int _consecutiveHeartbeatFailures = 0;
  int _examDurationMinutes = 60;
  int _extraMinutes = 0;
  DateTime? _examStartTime;
  DateTime? _examEndTime;
  Duration _serverClockOffset = Duration.zero;
  bool _isRefreshing = false;
  List<Map<String, dynamic>> _announcements = [];
  final Set<int> _readAnnouncementIds = {};
  Map<String, dynamic>? _activeToastAnnouncement;
  Timer? _toastDismissTimer;

  void _updateClock() {
    final now = DateTime.now();
    final h = now.hour.toString().padLeft(2, '0');
    final m = now.minute.toString().padLeft(2, '0');
    final formatted = '$h:$m';
    if (formatted != _timeString && mounted) {
      setState(() => _timeString = formatted);
    }
  }

  Widget _buildNetworkIcon({bool isDark = true}) {
    final iconColor = isDark ? const Color(0xFFCBD5E1) : const Color(0xFF64748B);
    switch (_networkType) {
      case 'wifi':
        return Icon(
          Icons.wifi_rounded,
          size: 13,
          color: iconColor,
        );
      case 'cellular':
        return Icon(
          Icons.signal_cellular_alt_rounded,
          size: 13,
          color: iconColor,
        );
      case 'ethernet':
        return Icon(
          Icons.settings_ethernet_rounded,
          size: 13,
          color: iconColor,
        );
      case 'none':
      default:
        return const Icon(
          Icons.wifi_off_rounded,
          size: 13,
          color: AppTheme.dangerRed,
        );
    }
  }

  @override
  void initState() {
    super.initState();
    final examId = widget.exam['id'] as int;
    _examDurationMinutes = widget.exam['duration_minutes'] ?? widget.exam['duration'] ?? 60;
    _extraMinutes = (widget.exam['extra_minutes'] as num?)?.toInt() ?? (widget.exam['progress']?['extra_minutes'] as num?)?.toInt() ?? 0;
    if (widget.exam['start_time'] != null) {
      _examStartTime = DateTime.tryParse(widget.exam['start_time'].toString())?.toLocal();
    }
    if (widget.exam['end_time'] != null) {
      _examEndTime = DateTime.tryParse(widget.exam['end_time'].toString())?.toLocal();
    }

    // Suppress and cancel local reminders for this exam during active test
    ExamReminderService.cancelExamReminders(examId);

    _updateClock();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) => _updateClock());
    _fetchAnnouncements();

    // 1. Enforce native screen pinning (LockTask) and suppress external system status bar (WhatsApp/Alarm/Wi-Fi icons)
    VolumeLockService.startLockTask();
    VolumeLockService.setKioskSystemBarsBlocked(true);
    VolumeLockService.lockOrientationPortrait(true);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // Enforce native anti-screenshot protection strictly during active exam
    // In release mode: permanently enforced. In debug mode: follow setting toggle.
    if (!kDebugMode) {
      VolumeLockService.setFlagSecure(true);
    } else {
      TokenStorage.isScreenshotProtectionEnabled().then((enabled) {
        VolumeLockService.setFlagSecure(enabled);
      });
    }

    // 2. Start anti-cheat lockdown monitoring (Wakelock & Brightness)
    _lockdown.startExamMonitoring(
      examId: examId,
      context: context,
    );

    // 3. Initial hardware & network fetch
    VolumeLockService.getNetworkType().then((net) {
      if (mounted) setState(() => _networkType = net);
    });
    VolumeLockService.getBatteryLevel().then((b) {
      if (mounted && b >= 0) setState(() => _batteryLevel = b);
    });
    VolumeLockService.isDeviceCharging().then((c) {
      if (mounted) setState(() => _isCharging = c);
    });

    // 4. Perform mandatory initial handshake before rendering exam
    _performInitialHandshake();

    // 5. Fetch live exam schedule & duration from server to ensure any live panel edits take effect immediately
    _syncExamDetailsFromServer();
  }

  Future<void> _performInitialHandshake() async {
    if (!mounted) return;
    setState(() {
      _isHandshakeInProgress = true;
      _handshakeErrorMessage = null;
    });

    final currentNet = await VolumeLockService.getNetworkType();
    if (currentNet == 'none') {
      if (mounted) {
        setState(() {
          _isHandshakeInProgress = false;
          _networkType = 'none';
          _handshakeErrorMessage = 'Perangkat tidak terhubung ke jaringan internet atau Wi-Fi sekolah.\nSesi ujian wajib terhubung aktif ke server pengawas demi integritas.';
        });
      }
      return;
    }

    final ok = await _recordProgress('in_progress');
    if (!mounted) return;

    if (ok) {
      setState(() {
        _isHandshakeInProgress = false;
        _isHandshakeVerified = true;
        _isReadyToRenderWebView = true;
      });
      _startUnifiedMonitoring();
      _startHeartbeatTicker();
      _fetchAnnouncements();
    } else {
      setState(() {
        _isHandshakeInProgress = false;
        _handshakeErrorMessage = 'Gagal melakukan otorisasi sesi dengan server pengawas.\nPastikan server sekolah aktif dan koneksi internet stabil.';
      });
    }
  }

  void _startHeartbeatTicker() {
    // Continuous 12-second heartbeat & live announcement sync
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 12), (_) async {
      if (!mounted || _isSubmitting) return;
      await _recordProgress('in_progress');
      _fetchAnnouncements();
    });
  }

  void _startUnifiedMonitoring() {
    // Single consolidated ticker every 4 seconds to prevent main-thread timer spam
    _monitoringPoller = Timer.periodic(const Duration(seconds: 4), (_) async {
      if (!mounted || _isSubmitting) return;

      _lockdown.checkSplitScreen();
      _lockdown.checkBluetooth();
      _lockdown.checkPhoneCallState();
      _lockdown.checkExternalDisplay();

      final net = await VolumeLockService.getNetworkType();
      final b = await VolumeLockService.getBatteryLevel();
      final c = await VolumeLockService.isDeviceCharging();
      if (mounted && (b != _batteryLevel || c != _isCharging || net != _networkType)) {
        setState(() {
          if (b >= 0) _batteryLevel = b;
          _isCharging = c;
          _networkType = net;
          if (net == 'none' && !_isTrackingInterrupted && !_isSubmitting) {
            _isTrackingInterrupted = true;
          }
        });
      }

      // Auto-recovery ping when tracking is interrupted
      if (_isTrackingInterrupted && !_isSubmitting) {
        await _recordProgress('in_progress');
      }
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _monitoringPoller?.cancel();
    _heartbeatTimer?.cancel();
    _toastDismissTimer?.cancel();
    VolumeLockService.setKioskSystemBarsBlocked(false);
    VolumeLockService.lockOrientationPortrait(false);
    VolumeLockService.stopLockTask();
    // Always restore screenshots and orientations when exiting active exam screen
    VolumeLockService.setFlagSecure(false);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
    AppTheme.applySystemOverlayStyle();
    // Do not stop alarm siren if screen is disposed due to an active violation ejection
    final isViolation = _lockdown.isHandlingViolation;
    _lockdown.stopExamMonitoring(stopAlarm: !isViolation);
    super.dispose();
  }

  Future<bool> _recordProgress(String status) async {
    try {
      final isCharging = await VolumeLockService.isDeviceCharging();
      final battery = await VolumeLockService.getBatteryLevel();
      final network = await VolumeLockService.getNetworkType();
      final res = await _api.post(
        ApiEndpoints.recordProgress,
        data: {
          'link_id': widget.exam['id'],
          'status': status,
          'is_charging': isCharging,
          'battery_level': battery,
          'network_type': network,
        },
      );

      _consecutiveHeartbeatFailures = 0;
      if (_isTrackingInterrupted && mounted) {
        setState(() => _isTrackingInterrupted = false);
        CheatReporter.flushPendingViolations();
        AppNotification.show(
          context,
          title: 'Koneksi Pengawas Pulih',
          subtitle: 'Perangkat telah terhubung kembali ke server monitoring ujian.',
          type: NotificationType.success,
        );
      }

      if (res.data != null && res.data['data'] != null) {
        final data = res.data['data'];
        if (data is Map) {
          if (data['is_kicked'] == true || data['status'] == 'terminated') {
            _handleProctorKick(data['reason']?.toString() ?? '');
            return false;
          }

          final liveExtra = (data['extra_minutes'] as num?)?.toInt();
          if (liveExtra != null && liveExtra != _extraMinutes) {
            final added = liveExtra - _extraMinutes;
            setState(() => _extraMinutes = liveExtra);
            if (added > 0) {
              try { HapticFeedback.mediumImpact(); } catch (_) {}
              if (mounted) {
                AppNotification.show(
                  context,
                  title: 'Waktu Tambahan Personal Diberikan',
                  subtitle: 'Pengawas telah memberikan kompensasi waktu tambahan +$added menit khusus untuk Anda.',
                  type: NotificationType.info,
                  duration: const Duration(seconds: 6),
                );
              }
            } else if (added < 0) {
              final reduced = added.abs();
              try { HapticFeedback.heavyImpact(); } catch (_) {}
              if (mounted) {
                AppNotification.show(
                  context,
                  title: 'Waktu Ujian Dikurangi',
                  subtitle: 'Pengawas telah memotong waktu ujian Anda sebesar -$reduced menit.',
                  type: NotificationType.warning,
                  duration: const Duration(seconds: 6),
                );
              }
            }
          }

          if (data['announcements'] is List) {
            _handleReceivedAnnouncements(List<Map<String, dynamic>>.from(
              (data['announcements'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)),
            ));
          }
        }
      }
      return true;
    } catch (e) {
      if (e is DioException) {
        final respData = e.response?.data;
        if (respData is Map && respData['data'] is Map) {
          final inner = respData['data'] as Map;
          if (inner['is_kicked'] == true || inner['status'] == 'terminated') {
            _handleProctorKick(inner['reason']?.toString() ?? '');
            return false;
          }
        }
      }

      if (status == 'in_progress') {
        _consecutiveHeartbeatFailures++;
        if (_consecutiveHeartbeatFailures >= 2 || _networkType == 'none') {
          if (!_isTrackingInterrupted && mounted && !_isSubmitting) {
            setState(() => _isTrackingInterrupted = true);
          }
        }
      }
      return false;
    }
  }

  Future<void> _syncExamDetailsFromServer({bool isManualRefresh = false}) async {
    final examId = widget.exam['id'] as int;
    try {
      dynamic res;
      try {
        res = await _api.get(ApiEndpoints.studentExamDetail(examId));
      } catch (_) {
        // Fallback to studentExams listing
        res = await _api.get(ApiEndpoints.studentExams);
      }

      if (!mounted || res == null || res.data == null) return;

      // Extract server date header for clock skew compensation
      try {
        final dateHeader = res.headers?.value('date');
        if (dateHeader != null) {
          final serverDt = HttpDate.parse(dateHeader).toLocal();
          _serverClockOffset = serverDt.difference(DateTime.now());
        }
      } catch (_) {}

      Map<String, dynamic>? examObj;
      final data = res.data['data'];
      if (data is Map) {
        examObj = Map<String, dynamic>.from(data);
      } else if (data is List) {
        for (final item in data) {
          if (item is Map && item['id'] == examId) {
            examObj = Map<String, dynamic>.from(item);
            break;
          }
        }
      }

      if (examObj != null && mounted) {
        if (examObj['is_kicked'] == true || examObj['progress']?['status'] == 'terminated') {
          final kickReason = examObj['kick_reason']?.toString() ?? examObj['progress']?['kick_reason']?.toString() ?? '';
          _handleProctorKick(kickReason);
          return;
        }

        final liveDur = examObj['duration_minutes'] ?? examObj['duration'];
        final liveExtra = (examObj['extra_minutes'] as num?)?.toInt() ?? (examObj['progress']?['extra_minutes'] as num?)?.toInt();
        final rawStart = examObj['start_time'];
        final rawEnd = examObj['end_time'];
        final newStart = rawStart != null ? DateTime.tryParse(rawStart.toString())?.toLocal() : _examStartTime;
        final newEnd = rawEnd != null ? DateTime.tryParse(rawEnd.toString())?.toLocal() : _examEndTime;

        if (liveExtra != null && liveExtra != _extraMinutes) {
          final added = liveExtra - _extraMinutes;
          setState(() => _extraMinutes = liveExtra);
          if (added > 0) {
            try { HapticFeedback.mediumImpact(); } catch (_) {}
            AppNotification.show(
              context,
              title: 'Waktu Tambahan Personal Diberikan',
              subtitle: 'Pengawas telah memberikan kompensasi waktu tambahan +$added menit khusus untuk Anda.',
              type: NotificationType.info,
              duration: const Duration(seconds: 6),
            );
          } else if (added < 0) {
            final reduced = added.abs();
            try { HapticFeedback.heavyImpact(); } catch (_) {}
            AppNotification.show(
              context,
              title: 'Waktu Ujian Dikurangi',
              subtitle: 'Pengawas telah memotong waktu ujian Anda sebesar -$reduced menit.',
              type: NotificationType.warning,
              duration: const Duration(seconds: 6),
            );
          }
        }

        setState(() {
          if (liveDur is int && liveDur > 0) {
            _examDurationMinutes = liveDur;
          }
          if (newStart != null) _examStartTime = newStart;
          if (newEnd != null) _examEndTime = newEnd;
        });
      }
    } catch (_) {}
  }

  Future<void> _handleManualRefresh() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);

    try {
      HapticFeedback.selectionClick();
    } catch (_) {}

    AppNotification.show(
      context,
      title: 'Menyinkronkan Ujian',
      subtitle: 'Memuat ulang halaman soal & jadwal waktu dari server...',
      type: NotificationType.info,
      duration: const Duration(seconds: 2),
    );

    // 1. Reload WebView
    try {
      await _webViewController?.reload();
    } catch (_) {}

    // 2. Sync latest exam schedule & duration from server
    await _syncExamDetailsFromServer(isManualRefresh: true);

    // 3. Sync latest announcements
    await _fetchAnnouncements();

    if (mounted) {
      setState(() => _isRefreshing = false);
      AppNotification.show(
        context,
        title: 'Sinkronisasi Berhasil',
        subtitle: 'Halaman soal, jadwal waktu, dan pengumuman diperbarui.',
        type: NotificationType.success,
        duration: const Duration(seconds: 3),
      );
    }
  }

  Future<void> _fetchAnnouncements() async {
    try {
      final examId = widget.exam['id'] as int;
      final res = await _api.get(ApiEndpoints.examAnnouncements(examId));
      if (res.data != null && res.data['data'] is List) {
        _handleReceivedAnnouncements(List<Map<String, dynamic>>.from(
          (res.data['data'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)),
        ));
      }
    } catch (_) {}
  }

  void _handleReceivedAnnouncements(List<Map<String, dynamic>> list) {
    if (!mounted || list.isEmpty) return;

    Map<String, dynamic>? latestUnread;
    for (final ann in list) {
      final id = ann['id'];
      final intId = id is int ? id : int.tryParse(id.toString()) ?? 0;
      if (intId > 0 && !_readAnnouncementIds.contains(intId)) {
        latestUnread ??= ann;
      }
    }

    setState(() {
      _announcements = list;
    });

    if (latestUnread != null) {
      final id = latestUnread['id'];
      final intId = id is int ? id : int.tryParse(id.toString()) ?? 0;
      _readAnnouncementIds.add(intId);

      _toastDismissTimer?.cancel();
      setState(() {
        _activeToastAnnouncement = latestUnread;
      });
      try { HapticFeedback.mediumImpact(); } catch (_) {}
    }
  }

  void _openAnnouncementsSheet() {
    for (final a in _announcements) {
      final id = a['id'];
      final intId = id is int ? id : int.tryParse(id.toString()) ?? 0;
      if (intId > 0) _readAnnouncementIds.add(intId);
    }
    ExamAnnouncementsSheet.show(
      context,
      announcements: _announcements,
      onClearUnread: () {
        if (mounted) setState(() {});
      },
    );
  }

  void _handleProctorKick(String reason) {
    if (_isSubmitting) return;
    _isSubmitting = true;

    _heartbeatTimer?.cancel();
    _monitoringPoller?.cancel();
    _clockTimer?.cancel();
    _toastDismissTimer?.cancel();
    _lockdown.stopExamMonitoring(stopAlarm: true);
    AppNotification.hide();

    final nav = appNavigatorKey.currentState;
    final args = {
      'exam_id': widget.exam['id'],
      'event_type': 'proctor_kick',
      'details': reason.isNotEmpty ? reason : 'Sesi ujian Anda telah dihentikan secara langsung oleh Pengawas Ujian di ruang monitoring.',
    };

    if (nav != null) {
      nav.pushNamedAndRemoveUntil(AppRoutes.lockout, (route) => false, arguments: args);
    } else if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.lockout, (route) => false, arguments: args);
    }
  }

  void _onTimeout() async {
    if (_isSubmitting) return;
    _isSubmitting = true;

    _lockdown.stopExamMonitoring();
    await _recordProgress('completed');

    if (mounted) {
      final isDark = AppTheme.isDark(context);
      showGeneralDialog(
        context: context,
        barrierDismissible: false,
        barrierLabel: 'Ujian Habis',
        barrierColor: Colors.black.withValues(alpha: 0.65),
        transitionDuration: const Duration(milliseconds: 320),
        pageBuilder: (ctx, anim1, anim2) => AlertDialog(
          backgroundColor: isDark ? AppTheme.surfaceDark : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
              width: 1.2,
            ),
          ),
          title: Text(
            'Waktu Ujian Habis',
            style: TextStyle(
              color: isDark ? Colors.white : const Color(0xFF0F172A),
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            'Waktu pengerjaan telah selesai. Jawaban Anda telah tersimpan otomatis.',
            style: TextStyle(color: isDark ? AppTheme.textSecondary : const Color(0xFF475569)),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryShiei,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context);
              },
              child: const Text('Kembali ke Menu'),
            ),
          ],
        ),
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
  }

  void _confirmFinishExam() {
    final isDark = AppTheme.isDark(context);
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Batal',
      barrierColor: Colors.black.withValues(alpha: 0.6),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (ctx, anim1, anim2) => AlertDialog(
        backgroundColor: isDark ? AppTheme.surfaceDark : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            width: 1.2,
          ),
        ),
        title: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: AppTheme.accentGreen, size: 22),
            const SizedBox(width: 8),
            Text(
              'Selesaikan Ujian?',
              style: TextStyle(
                color: isDark ? Colors.white : const Color(0xFF0F172A),
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          'Pastikan Anda telah mengisi seluruh jawaban sebelum menyelesaikan ujian.\nAnda tidak dapat membuka kembali lembar ujian ini setelah dikirim.',
          style: TextStyle(
            color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
            fontSize: 13,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Lanjutkan Mengerjakan',
              style: TextStyle(color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentGreen,
              foregroundColor: Colors.white,
              minimumSize: const Size(96, 38),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              _isSubmitting = true;
              _lockdown.stopExamMonitoring();
              await _recordProgress('completed');
              if (mounted) {
                Navigator.pop(context);
              }
            },
            child: const Text('Ya, Selesai', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
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
  Widget build(BuildContext context) {
    final duration = _examDurationMinutes;
    final url = widget.exam['url'] as String? ?? '';
    final isDark = AppTheme.isDark(context);

    return PopScope(
      canPop: false, // Prevent physical back button from escaping kiosk
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        // If WebView has navigation history (e.g. nested form link), navigate back inside WebView
        if (_webViewController != null && await _webViewController!.canGoBack()) {
          await _webViewController!.goBack();
          return;
        }
        // If cannot go back, student cannot exit except by submitting via "Selesai"
        if (context.mounted) {
          AppNotification.show(
            context,
            title: 'Sesi Ujian Terkunci',
            subtitle: 'Anda tidak dapat keluar dari aplikasi. Selesaikan ujian dengan menekan tombol "Selesai".',
            type: NotificationType.warning,
          );
        }
      },
      child: Scaffold(
        backgroundColor: isDark ? Colors.black : const Color(0xFFF8FAFC),
        body: Stack(
          children: [
            SafeArea(
              top: false, // Anchor razor-thin custom status bar flush to the absolute top edge of the display
              bottom: false,
              child: Column(
            children: [
              // Top Razor-Thin Kiosk Status Bar (Clock, WiFi/Network, and Battery)
              Container(
                height: 24,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF090D1A) : const Color(0xFFF1F5F9),
                  border: Border(
                    bottom: BorderSide(
                      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                      width: 0.8,
                    ),
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Digital Clock (Left)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _timeString.isNotEmpty ? _timeString : '--:--',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF334155),
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                    // Network & Battery (Right)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Live Network / WiFi indicator
                        _buildNetworkIcon(isDark: isDark),
                        const SizedBox(width: 8),
                        // Live Battery Level
                        Text(
                          '$_batteryLevel%',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _batteryLevel < 20
                                ? AppTheme.dangerRed
                                : (isDark ? const Color(0xFFE2E8F0) : const Color(0xFF334155)),
                          ),
                        ),
                        const SizedBox(width: 3),
                        Icon(
                          _isCharging
                              ? Icons.battery_charging_full_rounded
                              : (_batteryLevel > 80
                                  ? Icons.battery_full_rounded
                                  : (_batteryLevel > 40
                                      ? Icons.battery_5_bar_rounded
                                      : (_batteryLevel > 15
                                          ? Icons.battery_3_bar_rounded
                                          : Icons.battery_alert_rounded))),
                          size: 13,
                          color: _isCharging
                              ? AppTheme.accentGreen
                              : (_batteryLevel < 20
                                  ? AppTheme.dangerRed
                                  : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B))),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Top Single-Line Kiosk Navbar (Countdown Timer + Refresh + Selesai)
              Container(
                height: 54,
                decoration: BoxDecoration(
                  gradient: isDark
                      ? const LinearGradient(
                          colors: [Color(0xFF0F172A), Color(0xFF090D1A)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        )
                      : const LinearGradient(
                          colors: [Colors.white, Color(0xFFF8FAFC)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                  border: Border(
                    bottom: BorderSide(
                      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                      width: 1.5,
                    ),
                  ),
                  boxShadow: [
                    isDark
                        ? BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          )
                        : const BoxShadow(
                            color: Color(0x100F172A),
                            blurRadius: 8,
                            offset: Offset(0, 2),
                          ),
                  ],
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    // Left: Exam Countdown Timer (Synchronously bound to endTime + extraMinutes)
                    ExamTimerWidget(
                      durationMinutes: duration,
                      extraMinutes: _extraMinutes,
                      endTime: _examEndTime,
                      startTime: _examStartTime,
                      serverClockOffset: _serverClockOffset,
                      onTimeout: _onTimeout,
                    ),
                    const Spacer(),
                    // Right 0: Loudspeaker / Proctor Announcement Button with Unread Badge
                    Builder(
                      builder: (ctx) {
                        final unreadCount = _announcements.where((a) {
                          final id = a['id'];
                          final intId = id is int ? id : int.tryParse(id.toString()) ?? 0;
                          return intId > 0 && !_readAnnouncementIds.contains(intId);
                        }).length;

                        return IconButton(
                          icon: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Icon(
                                Icons.campaign_rounded,
                                color: unreadCount > 0
                                    ? const Color(0xFFF59E0B)
                                    : (isDark ? AppTheme.textSecondary : const Color(0xFF475569)),
                                size: 20,
                              ),
                              if (unreadCount > 0)
                                Positioned(
                                  top: -4,
                                  right: -4,
                                  child: Container(
                                    padding: const EdgeInsets.all(3),
                                    decoration: const BoxDecoration(
                                      color: AppTheme.dangerRed,
                                      shape: BoxShape.circle,
                                    ),
                                    constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                                    child: Text(
                                      '$unreadCount',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          tooltip: 'Papan Pengumuman Pengawas',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
                          style: IconButton.styleFrom(
                            backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(
                                color: unreadCount > 0
                                    ? const Color(0xFFF59E0B).withValues(alpha: 0.5)
                                    : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                                width: 1,
                              ),
                            ),
                          ),
                          onPressed: _openAnnouncementsSheet,
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    // Right 1: Refresh Button (Muat ulang webview & sinkronkan jadwal server)
                    IconButton(
                      icon: _isRefreshing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTheme.primaryShiei,
                              ),
                            )
                          : Icon(
                              Icons.refresh_rounded,
                              color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
                              size: 20,
                            ),
                      tooltip: 'Muat Ulang Halaman & Sinkronkan Waktu',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
                      style: IconButton.styleFrom(
                        backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(
                            color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                            width: 1,
                          ),
                        ),
                      ),
                      onPressed: _handleManualRefresh,
                    ),
                    const SizedBox(width: 10),
                    // Right 2: Selesai Button
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accentGreen,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(96, 38),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 2,
                      ),
                      onPressed: _confirmFinishExam,
                      icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                      label: const Text(
                        'Selesai',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),

              // WebView Exam Surface (Mounted after route transition and verified handshake)
              Expanded(
                child: !_isHandshakeVerified
                    ? _buildHandshakeScreen(isDark)
                    : (_isReadyToRenderWebView
                        ? UrlExamPlayer(
                            url: url,
                            onPageLoaded: () {},
                            onControllerCreated: (ctrl) => _webViewController = ctrl,
                          )
                        : const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 32,
                                  height: 32,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: AppTheme.primaryGlow,
                                  ),
                                ),
                                SizedBox(height: 14),
                                Text(
                                  'Menyiapkan lembar ujian...',
                                  style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          )),
              ),
            ],
          ),
        ),
        // Security Shield Overlay: Activates if network drops or proctor heartbeat is severed
        if (_isTrackingInterrupted)
          Positioned.fill(
            child: _buildTrackingShield(isDark),
          ),
        // Floating Top Announcement Banner
        if (_activeToastAnnouncement != null)
          Positioned(
            top: 26,
            left: 0,
            right: 0,
            child: ExamAnnouncementBanner(
              key: ValueKey(_activeToastAnnouncement!['id'] ?? _activeToastAnnouncement!['message']),
              announcement: _activeToastAnnouncement!,
              onDismiss: () {
                if (mounted) {
                  setState(() => _activeToastAnnouncement = null);
                }
              },
              onViewAll: () {
                _openAnnouncementsSheet();
              },
            ),
          ),
      ],
    ),
  ),
);
}

  Widget _buildHandshakeScreen(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isHandshakeInProgress) ...[
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppTheme.primaryGlow.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: AppTheme.primaryBlue,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Menghubungkan Sesi Ujian...',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Memverifikasi otorisasi perangkat ke server monitoring sekolah',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                ),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.dangerRed.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.wifi_off_rounded,
                  size: 38,
                  color: AppTheme.dangerRed,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Gagal Menghubungkan Sesi',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _handshakeErrorMessage ??
                    'Perangkat tidak dapat terhubung ke server pengawas. Sesi ujian wajib terpantau secara real-time demi integritas ujian.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                      side: BorderSide(
                        color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
                      ),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () {
                      _lockdown.stopExamMonitoring();
                      Navigator.pop(context);
                    },
                    child: Text(
                      'Kembali ke Beranda',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white70 : const Color(0xFF475569),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                    onPressed: _performInitialHandshake,
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text(
                      'Coba Hubungkan',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTrackingShield(bool isDark) {
    return Container(
      color: isDark ? Colors.black.withValues(alpha: 0.94) : const Color(0xFF0F172A).withValues(alpha: 0.92),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 26),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.wifi_off_rounded,
                    size: 42,
                    color: Color(0xFFF59E0B),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Koneksi Pengawas Terputus',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Sistem mendeteksi koneksi pelacakan ke server pengawas terhenti. Demi integritas ujian dan mencegah kecurangan, tampilan lembar soal ditangguhkan sementara.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    color: Color(0xFFCBD5E1),
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.timer_outlined, color: Color(0xFFF59E0B), size: 16),
                      SizedBox(width: 8),
                      Text(
                        'Waktu ujian di server tetap berjalan',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFFDE68A),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 3,
                  ),
                  onPressed: () async {
                    final ok = await _recordProgress('in_progress');
                    if (!ok && mounted) {
                      AppNotification.showWarning(
                        context,
                        'Masih Belum Terhubung',
                        subtitle: 'Pastikan sinyal Wi-Fi atau data seluler Anda sudah aktif.',
                      );
                    }
                  },
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text(
                    'Periksa Sambungan Sekarang',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
