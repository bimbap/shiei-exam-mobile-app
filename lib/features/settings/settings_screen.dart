import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/app_config.dart';
import '../../config/routes.dart';
import '../../core/api/api_client.dart';
import '../../core/api/endpoints.dart';
import '../../core/auth/auth_service.dart';
import '../../core/auth/token_storage.dart';
import '../../core/lockdown/volume_lock_service.dart';
import '../../core/theme/theme_controller.dart';
import '../../core/update/app_update_service.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/app_notification.dart';
import '../exam_player/url_exam_player.dart';
import 'legal_document_screen.dart';
import 'widgets/browser_account_picker_sheet.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _serverUrlController = TextEditingController(text: AppConfig.inputBaseUrl);
  final _authService = AuthService();
  bool _isSavingServer = false;

  String _deviceSerial = 'Memuat...';
  String _deviceName = 'Memuat...';
  String _deviceModel = 'Memuat...';
  bool _isScreenshotProtectionEnabled = true;
  bool _isAppExitBypassEnabled = false;
  bool _isAntiAlarmBypassEnabled = false;

  // Admin License State
  bool _isAdmin = false;
  bool _isLoggedIn = false;
  Map<String, dynamic>? _schoolData;
  bool _isLoadingLicense = false;
  bool _showFullLicenseKey = false;

  // Browser Login Connection State
  bool _keepBrowserLogin = false;
  bool _browserLoginConnected = false;
  bool _isChoosingBrowserMode = false;
  String? _browserLoginLabel;
  String? _browserLoginEmail;
  String? _browserLoginUrl;

  @override
  void initState() {
    super.initState();
    _serverUrlController.text = AppConfig.inputBaseUrl;
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    final serial = await _authService.getDeviceUniqueIdentifier();
    final name = await VolumeLockService.getDeviceName();
    final model = await VolumeLockService.getDeviceId();
    final isSec = await TokenStorage.isScreenshotProtectionEnabled();
    final isExitBypass = await TokenStorage.isAppExitBypassEnabled();
    final isAlarmBypass = await TokenStorage.isAntiAlarmBypassEnabled();
    final keepBrowserLogin = await TokenStorage.isKeepBrowserLoginEnabled();
    final browserMeta = await TokenStorage.getBrowserLoginMeta();

    // Determine admin role status and school context
    final token = await TokenStorage.getToken();
    final role = await TokenStorage.getRole();
    final user = await TokenStorage.getUser();
    final isLoggedIn = token != null && token.isNotEmpty;
    final isAdmin = (role?.toLowerCase() == 'school_admin' ||
            role?.toLowerCase() == 'super_admin' ||
            role?.toLowerCase() == 'admin') ||
        (user?['role']?.toString().toLowerCase() == 'school_admin');

    Map<String, dynamic>? school;
    if (user?['school'] is Map) {
      school = Map<String, dynamic>.from(user!['school']);
    }

    // Ensure settings screen itself is always capturable
    await VolumeLockService.setFlagSecure(false);
    if (mounted) {
      setState(() {
        _deviceSerial = serial;
        _deviceName = name;
        _deviceModel = model;
        _isScreenshotProtectionEnabled = isSec;
        _isAppExitBypassEnabled = isExitBypass;
        _isAntiAlarmBypassEnabled = isAlarmBypass;
        _isLoggedIn = isLoggedIn;
        _isAdmin = isAdmin;
        _schoolData = school;
        _keepBrowserLogin = keepBrowserLogin;
        _browserLoginConnected = browserMeta['connected'] == true;
        _browserLoginLabel = browserMeta['label']?.toString();
        _browserLoginEmail = browserMeta['email']?.toString();
        _browserLoginUrl = browserMeta['url']?.toString();
      });
    }

    if (isAdmin) {
      _fetchLicenseStatus(showToast: false);
    }
  }

  Future<void> _fetchLicenseStatus({bool showToast = false}) async {
    if (!_isAdmin) return;
    setState(() => _isLoadingLicense = true);
    try {
      final res = await ApiClient().get(ApiEndpoints.schoolProfile);
      if (res.data != null && (res.data['status'] == 'success' || res.data['data'] != null)) {
        final raw = res.data['data'] ?? res.data['school'];
        if (raw is Map && mounted) {
          setState(() {
            _schoolData = Map<String, dynamic>.from(raw);
          });
          if (showToast) {
            AppNotification.showSuccess(
              context,
              'Lisensi Berhasil Disinkronkan',
              subtitle: 'Data kuota dan status lisensi sekolah terverifikasi.',
            );
          }
        }
      }
    } catch (e) {
      if (showToast && mounted) {
        AppNotification.show(
          context,
          title: 'Gagal Sinkronisasi Lisensi',
          subtitle: 'Periksa koneksi jaringan atau URL backend server.',
          type: NotificationType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingLicense = false);
    }
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    super.dispose();
  }

  Future<void> _saveServerUrl() async {
    if (_isSavingServer) return;

    if (_isLoggedIn && !_isAdmin) {
      AppNotification.show(
        context,
        title: 'Akses Dibatasi',
        subtitle: 'Logout terlebih dahulu sebelum mengubah alamat server sekolah.',
        type: NotificationType.warning,
        duration: const Duration(milliseconds: 3200),
      );
      return;
    }

    final rawUrl = _serverUrlController.text.trim();
    if (rawUrl.isEmpty) {
      AppNotification.show(
        context,
        title: 'Pengaturan Database Gagal Tersimpan',
        subtitle: 'Alamat URL server database tidak boleh kosong.',
        type: NotificationType.error,
        duration: const Duration(milliseconds: 3200),
      );
      return;
    }

    final normalizedUrl = AppConfig.validateAndNormalizeServerUrl(rawUrl);
    if (normalizedUrl == null) {
      AppNotification.show(
        context,
        title: 'Alamat Server Ditolak',
        subtitle: 'Koneksi HTTP polos hanya diizinkan untuk IP jaringan lokal sekolah. Domain publik wajib HTTPS.',
        type: NotificationType.error,
        duration: const Duration(milliseconds: 4000),
      );
      return;
    }

    setState(() => _isSavingServer = true);

    bool urlChanged = false;
    try {
      urlChanged = normalizedUrl != AppConfig.baseUrl;
      if (urlChanged) {
        await TokenStorage.clear();
        if (mounted) {
          setState(() {
            _isLoggedIn = false;
            _isAdmin = false;
            _schoolData = null;
          });
        }
      }
      AppConfig.setCustomBaseUrl(normalizedUrl);
      _serverUrlController.text = AppConfig.baseUrl;

      // 1. Notifikasi pertama: Pengaturan database berhasil tersimpan
      if (mounted) {
        AppNotification.show(
          context,
          title: 'Pengaturan Database Berhasil Disimpan',
          subtitle: urlChanged ? '${AppConfig.baseUrl} (Sesi lama dibersihkan)' : AppConfig.baseUrl,
          type: NotificationType.success,
          duration: const Duration(milliseconds: 2500),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSavingServer = false);
      AppNotification.show(
        context,
        title: 'Pengaturan Database Gagal Tersimpan',
        subtitle: 'Terjadi kegagalan saat menyimpan konfigurasi ke memori.',
        type: NotificationType.error,
        duration: const Duration(milliseconds: 3200),
      );
      return;
    }

    // Jeda waktu yang cukup agar pengguna dapat membaca notifikasi pertama
    await Future.delayed(const Duration(milliseconds: 1800));

    // 2. Verifikasi koneksi aktif ke server backend & database (Push Notif ke-2)
    try {
      final res = await ApiClient().dio.get(
        '/health',
        options: Options(
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );
      if (res.statusCode == 200) {
        if (mounted) {
          AppNotification.show(
            context,
            title: 'Koneksi Berhasil Tersambung',
            subtitle: 'Database & backend terhubung aktif (${AppConfig.baseUrl})',
            type: NotificationType.success,
            duration: const Duration(milliseconds: 3500),
          );
        }
      } else {
        throw Exception('Server returned ${res.statusCode}');
      }
    } catch (_) {
      if (mounted) {
        AppNotification.show(
          context,
          title: 'Koneksi Gagal Tersambung',
          subtitle: 'Pengaturan tersimpan, tapi server backend tidak merespons.',
          type: NotificationType.error,
          duration: const Duration(milliseconds: 3500),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingServer = false);
      }
    }
  }

  Future<void> _toggleScreenshotProtection(bool val) async {
    setState(() {
      _isScreenshotProtectionEnabled = val;
    });
    // Save preference for active exams without locking down current settings screen
    await TokenStorage.setScreenshotProtection(val);
    await VolumeLockService.setFlagSecure(false);

    if (mounted) {
      if (val) {
        AppNotification.show(
          context,
          title: 'Proteksi Layar Ujian DIAKTIFKAN',
          subtitle: 'Anti-screenshot otomatis aktif saat masuk ke lembar ujian.',
          type: NotificationType.info,
        );
      } else {
        AppNotification.show(
          context,
          title: 'Proteksi Layar Ujian DINONAKTIFKAN',
          subtitle: 'Tangkapan layar diizinkan saat ujian (Bypass aktif tanpa penalti).',
          type: NotificationType.warning,
        );
      }
    }
  }

  Future<void> _toggleAppExitBypass(bool val) async {
    setState(() {
      _isAppExitBypassEnabled = val;
    });
    await TokenStorage.setAppExitBypass(val);

    if (mounted) {
      if (val) {
        AppNotification.show(
          context,
          title: 'Bypass Keluar Aplikasi DIAKTIFKAN',
          subtitle: 'Keluar/minimize app diizinkan tanpa memicu lockout ujian.',
          type: NotificationType.warning,
        );
      } else {
        AppNotification.show(
          context,
          title: 'Bypass Keluar Aplikasi DINONAKTIFKAN',
          subtitle: 'Proteksi fullscreen & lockout ujian kembali normal.',
          type: NotificationType.info,
        );
      }
    }
  }

  Future<void> _toggleAntiAlarmBypass(bool val) async {
    setState(() {
      _isAntiAlarmBypassEnabled = val;
    });
    await TokenStorage.setAntiAlarmBypass(val);

    if (mounted) {
      if (val) {
        AppNotification.show(
          context,
          title: 'Bypass Suara Alarm DIAKTIFKAN',
          subtitle: 'Sirine darurat & pemaksaan volume max dinonaktifkan saat lockout.',
          type: NotificationType.warning,
        );
      } else {
        AppNotification.show(
          context,
          title: 'Bypass Suara Alarm DINONAKTIFKAN',
          subtitle: 'Sirine keamanan & volume 100% kembali aktif saat lockout.',
          type: NotificationType.info,
        );
      }
    }
  }

  Future<void> _toggleKeepBrowserLogin(bool val) async {
    setState(() {
      _keepBrowserLogin = val;
      _isChoosingBrowserMode = false;
    });
    await TokenStorage.setKeepBrowserLoginEnabled(val);
    if (!val) {
      await UrlExamPlayer.clearBrowserSessionCookies();
      await TokenStorage.clearBrowserLoginMeta();
      if (mounted) {
        setState(() {
          _browserLoginConnected = false;
          _browserLoginLabel = null;
          _browserLoginEmail = null;
          _browserLoginUrl = null;
        });
      }
    }
    await VolumeLockService.setFlagSecure(false);
    if (mounted) {
      AppNotification.show(
        context,
        title: val ? 'Mode Akun Terhubung Dipilih' : 'Mode Guest (Incognito) Aktif',
        subtitle: val
            ? 'Silakan hubungkan akun Google atau portal CBT sekolah sebelum ujian.'
            : 'Nol history & cookie direset otomatis setiap kali sesi ujian dimulai atau berakhir.',
        type: val ? NotificationType.success : NotificationType.info,
      );
    }
  }

  Future<void> _openBrowserLoginConnect({
    String? customUrl,
    String? providerLabel,
  }) async {
    String? targetUrl = customUrl;
    String? pickedEmail;
    if (customUrl == null) {
      if (Platform.isAndroid &&
          !(await VolumeLockService.hasGoogleAccountsPermission())) {
        await VolumeLockService.requestGoogleAccountsPermission();
      }
      if (!mounted) return;
      pickedEmail = await BrowserAccountPickerSheet.pick(
        context,
        currentEmail: _browserLoginEmail,
      );
      await _loadInfo();
      if (pickedEmail == null || pickedEmail.isEmpty) {
        return;
      }
      if (pickedEmail == BrowserAccountPickerSheet.addAccountSentinel) {
        targetUrl =
            'https://accounts.google.com/AddSession?continue=https%3A%2F%2Fdocs.google.com%2Fforms';
        pickedEmail = null;
      }
    }

    if (!_keepBrowserLogin) {
      await TokenStorage.setKeepBrowserLoginEnabled(true);
      if (mounted) {
        setState(() {
          _keepBrowserLogin = true;
          _isChoosingBrowserMode = false;
        });
      }
    }

    if (!mounted) return;
    final result = await Navigator.of(context).pushNamed(
      AppRoutes.browserConnect,
      arguments: <String, dynamic>{
        if (targetUrl != null) 'initialUrl': targetUrl,
        if (pickedEmail != null) 'prefillEmail': pickedEmail,
        if (providerLabel != null)
          'providerLabel': providerLabel
        else if (customUrl == null)
          'providerLabel': 'Akun Google',
      },
    );
    await _loadInfo();
    if (mounted) {
      setState(() => _isChoosingBrowserMode = false);
    }
    if (result == true && mounted) {
      final accountDisplay = _browserLoginEmail ?? _browserLoginLabel ?? 'Akun Browser';
      AppNotification.showSuccess(
        context,
        'Akun Browser Terhubung',
        subtitle: 'Sesi $accountDisplay aktif dan siap dipakai saat membuka ujian.',
      );
    }
  }

  Future<void> _openCustomPortalDialog() async {
    final ctrl = TextEditingController(
      text: (_browserLoginUrl != null &&
              !_browserLoginUrl!.contains('google.com'))
          ? _browserLoginUrl
          : '',
    );
    final isDark = AppTheme.isDark(context);
    final target = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppTheme.surfaceDark : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Hubungkan Portal CBT',
          style: TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Masukkan alamat web portal sekolah (HTTPS atau IP LAN) untuk menyimpan sesi login sebelum ujian:',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                hintText: 'https://cbt.sekolah.sch.id',
                prefixIcon: Icon(Icons.link_rounded, size: 18),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryShiei,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Lanjutkan'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (target != null && target.isNotEmpty) {
      await _openBrowserLoginConnect(customUrl: target);
    }
  }

  Future<void> _confirmDisconnectBrowserLogin() async {
    final isDark = AppTheme.isDark(context);
    final accountDisplay =
        (_browserLoginEmail?.isNotEmpty == true)
            ? _browserLoginEmail!
            : (_browserLoginLabel ?? 'akun ini');

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppTheme.surfaceDark : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.dangerRed.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.link_off_rounded,
                color: AppTheme.dangerRed,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Putuskan Koneksi Akun?',
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
            ),
          ],
        ),
        content: Text(
          'Status koneksi untuk $accountDisplay akan diputuskan.\n\n• "Putuskan & Hapus Sesi" memutus akun, membersihkan cookie browser, dan menghapusnya dari daftar cepat.\n• "Lepas Saja" menjaga email & sesi web agar bisa disambung ulang tanpa ketik sandi.',
          style: TextStyle(
            fontSize: 12.2,
            height: 1.45,
            color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
        actions: [
          SizedBox(
            width: double.infinity,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 44),
                    backgroundColor: AppTheme.dangerRed,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => Navigator.pop(ctx, 'purge'),
                  child: const Text(
                    'Putuskan & Hapus Sesi',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 42),
                    foregroundColor: AppTheme.primaryGlow,
                    side: BorderSide(
                      color: AppTheme.primaryShiei.withValues(alpha: 0.45),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => Navigator.pop(ctx, 'disconnect'),
                  child: const Text(
                    'Lepas Saja (Simpan Sesi)',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(double.infinity, 40),
                    foregroundColor: isDark
                        ? AppTheme.textSecondary
                        : const Color(0xFF475569),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text(
                    'Batal',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (action != null) {
      await _disconnectBrowserLogin(clearCookies: action == 'purge');
    }
  }

  Future<void> _disconnectBrowserLogin({bool clearCookies = false}) async {
    final removedEmail = _browserLoginEmail?.trim().toLowerCase();
    if (clearCookies) {
      await UrlExamPlayer.clearBrowserSessionCookies();
      if (removedEmail != null && removedEmail.isNotEmpty) {
        await TokenStorage.removeSavedBrowserEmail(removedEmail);
        await TokenStorage.hideDeviceGoogleEmail(removedEmail);
      }
    }
    await TokenStorage.clearBrowserLoginMeta();
    await TokenStorage.setKeepBrowserLoginEnabled(false);
    if (!mounted) return;
    setState(() {
      _keepBrowserLogin = false;
      _browserLoginConnected = false;
      _browserLoginLabel = null;
      _browserLoginEmail = null;
      _browserLoginUrl = null;
      _isChoosingBrowserMode = true;
    });
    AppNotification.showSuccess(
      context,
      clearCookies ? 'Akun Diputuskan & Sesi Dihapus' : 'Koneksi Akun Dilepas',
      subtitle: clearCookies
          ? 'Cookie & daftar akun dibersihkan total. Pilih akun baru atau Mode Guest.'
          : 'Akun dilepas sementara. Email & sesi tersimpan agar bisa disambungkan ulang dengan cepat.',
    );
  }

  Widget _buildBrowserLoginCard(
    bool isDark,
    Color cardBg,
    Color cardBorder,
    Color titleColor,
    Color textColor,
    Color dividerColor,
  ) {
    final isAndroid = Platform.isAndroid;
    final showConnectedView =
        _keepBrowserLogin && _browserLoginConnected && !_isChoosingBrowserMode;
    final showGuestView = !_keepBrowserLogin && !_isChoosingBrowserMode;

    Widget child;
    if (showConnectedView) {
      final rawDisplay = _browserLoginEmail?.isNotEmpty == true
          ? _browserLoginEmail!.trim()
          : (_browserLoginLabel?.trim().isNotEmpty == true
              ? _browserLoginLabel!.trim()
              : 'Akun Browser Terhubung');
      final avatarInitial =
          rawDisplay.isNotEmpty ? rawDisplay.substring(0, 1).toUpperCase() : 'A';
      final accountDisplay = rawDisplay;

      child = Column(
        key: const ValueKey('browser_connected'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.accentGreen.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppTheme.accentGreen.withValues(alpha: 0.45),
                  ),
                ),
                child: Center(
                  child: Text(
                    avatarInitial,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.accentGreen,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      accountDisplay,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        color: titleColor,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.accentGreen.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: AppTheme.accentGreen.withValues(alpha: 0.35),
                              ),
                            ),
                            child: Text(
                              'TERHUBUNG • ${_browserLoginLabel ?? 'Sesi Aktif'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 9.8,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.accentGreen,
                                letterSpacing: 0.3,
                              ),
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
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cardBorder),
            ),
            child: Text(
              'Sesi login tersimpan aman hanya di peramban ujian. Putuskan koneksi jika ingin mengganti mode ke Guest.',
              style: TextStyle(fontSize: 11, color: textColor, height: 1.38),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 42),
                    backgroundColor: AppTheme.primaryShiei,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: Icon(
                    isAndroid ? Icons.account_circle_outlined : Icons.login_rounded,
                    size: 18,
                  ),
                  label: Text(
                    isAndroid ? 'Ganti Akun' : 'Kelola Akun',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onPressed: () => _openBrowserLoginConnect(),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 42),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  foregroundColor: AppTheme.dangerRed,
                  side: BorderSide(
                    color: AppTheme.dangerRed.withValues(alpha: 0.45),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: _confirmDisconnectBrowserLogin,
                icon: const Icon(Icons.link_off_rounded, size: 17),
                label: const Text(
                  'Putuskan',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _openCustomPortalDialog,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              ),
              child: const Text(
                'Login ke portal CBT sekolah (non-Google)',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primaryGlow,
                ),
              ),
            ),
          ),
        ],
      );
    } else if (showGuestView) {
      child = Column(
        key: const ValueKey('browser_guest'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.accentGreen.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppTheme.accentGreen.withValues(alpha: 0.4),
                  ),
                ),
                child: const Icon(
                  Icons.privacy_tip_rounded,
                  color: AppTheme.accentGreen,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mode Guest (Incognito)',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        color: titleColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Aktif • Nol history & nol cookie tersimpan',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.accentGreen,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: AppTheme.accentGreen.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: AppTheme.accentGreen.withValues(alpha: 0.25),
              ),
            ),
            child: Text(
              'Ujian selalu dimulai dari sesi bersih: tidak menyimpan login, nol riwayat browser, nol cache form, dan cookie dihapus otomatis.',
              style: TextStyle(fontSize: 11.2, color: textColor, height: 1.4),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 42),
              foregroundColor: AppTheme.primaryGlow,
              side: BorderSide(
                color: AppTheme.primaryGlow.withValues(alpha: 0.45),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => setState(() => _isChoosingBrowserMode = true),
            icon: const Icon(Icons.swap_horiz_rounded, size: 18),
            label: const Text(
              'Ubah Opsi / Hubungkan Akun',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      );
    } else {
      child = Column(
        key: const ValueKey('browser_picker'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  'Pilih cara akses peramban saat membuka lembar soal:',
                  style: TextStyle(fontSize: 11.8, color: textColor, height: 1.4),
                ),
              ),
              if (!_keepBrowserLogin && _isChoosingBrowserMode) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => setState(() => _isChoosingBrowserMode = false),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  ),
                  child: const Text(
                    'Batal',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Divider(color: dividerColor, height: 1),
          _buildBrowserModeRow(
            icon: isAndroid
                ? Icons.account_circle_rounded
                : Icons.verified_user_rounded,
            iconColor: AppTheme.primaryGlow,
            title: isAndroid ? 'Hubungkan Akun Google' : 'Hubungkan Akun Web',
            subtitle: 'Simpan sesi agar langsung siap membuka soal Google Form',
            badgeText: 'Rekomendasi',
            titleColor: titleColor,
            textColor: textColor,
            onTap: () => _openBrowserLoginConnect(),
          ),
          Divider(color: dividerColor, height: 1),
          _buildBrowserModeRow(
            icon: Icons.language_rounded,
            iconColor: const Color(0xFF0EA5E9),
            title: 'Portal CBT Sekolah (URL Kustom)',
            subtitle: 'Login ke web CBT mandiri / Moodle (non-Google)',
            titleColor: titleColor,
            textColor: textColor,
            onTap: _openCustomPortalDialog,
          ),
          Divider(color: dividerColor, height: 1),
          _buildBrowserModeRow(
            icon: Icons.privacy_tip_outlined,
            iconColor: AppTheme.accentGreen,
            title: 'Mode Guest (Incognito)',
            subtitle: 'Tanpa akun tersimpan · cookie & cache otomatis bersih',
            titleColor: titleColor,
            textColor: textColor,
            onTap: () => _toggleKeepBrowserLogin(false),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cardBorder),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: child,
      ),
    );
  }

  Widget _buildBrowserModeRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    String? badgeText,
    required Color titleColor,
    required Color textColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 2),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: titleColor,
                          ),
                        ),
                      ),
                      if (badgeText != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryShiei.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            badgeText,
                            style: const TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.primaryGlow,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 11, color: textColor, height: 1.3),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded, color: textColor.withValues(alpha: 0.7), size: 20),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final cardBg = isDark ? AppTheme.surfaceDark : Colors.white;
    final cardBorder = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final titleColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final textColor = isDark ? AppTheme.textSecondary : const Color(0xFF475569);
    final dividerColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(
        title: const Text('Pengaturan & Informasi'),
      ),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(16),
        children: [
          // Section 1: Server Connection
          _buildSectionHeader('KONEKSI SERVER UJIAN', Icons.dns_rounded),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Alamat IP / Domain Backend Sekolah:',
                  style: TextStyle(fontSize: 12, color: textColor),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _serverUrlController,
                  enabled: !_isLoggedIn,
                  onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                  decoration: const InputDecoration(
                    hintText: 'Contoh: 192.168.1.100:8000 atau https://exam.sekolah.sch.id',
                    prefixIcon: Icon(Icons.link_rounded, color: AppTheme.primaryGlow),
                  ),
                ),
                if (_isLoggedIn) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Alamat server dikunci selama sesi aktif. Logout dulu untuk mengganti server.',
                    style: TextStyle(fontSize: 11, color: textColor),
                  ),
                ] else ...[
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 42),
                      backgroundColor: AppTheme.primaryShiei,
                      foregroundColor: Colors.white,
                    ),
                    icon: _isSavingServer
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save_rounded, size: 18),
                    label: Text(
                      _isSavingServer ? 'Menguji Koneksi...' : 'Simpan Pengaturan Server',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    onPressed: _isSavingServer ? null : _saveServerUrl,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Section 1.5: Status & Pengaturan Lisensi Sekolah (Khusus Administrator)
          if (_isAdmin) ...[
            _buildSectionHeader('STATUS & PENGATURAN LISENSI SEKOLAH', Icons.workspace_premium_rounded),
            _buildAdminLicenseCard(isDark, cardBg, cardBorder, titleColor, textColor, dividerColor),
            const SizedBox(height: 20),
          ],

          // Section 1.8: Connect Login for Browser
          _buildSectionHeader('KONEKSI LOGIN BROWSER', Icons.public_rounded),
          _buildBrowserLoginCard(isDark, cardBg, cardBorder, titleColor, textColor, dividerColor),
          const SizedBox(height: 20),

          // Section 2: Hardware & Device Lock
          _buildSectionHeader('INFORMASI PERANGKAT & HARDWARE LOCK', Icons.phonelink_lock_rounded),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cardBorder),
            ),
            child: Column(
              children: [
                _buildInfoRow('Tipe Perangkat HP:', _deviceName, isDark: isDark),
                Divider(color: dividerColor, height: 18),
                _buildInfoRow('Model Hardware ID:', _deviceModel, isDark: isDark),
                Divider(color: dividerColor, height: 18),
                _buildInfoRow('Hardware Serial Binding:', _deviceSerial, isDark: isDark),
                Divider(color: dividerColor, height: 18),
                _buildInfoRow('Status Sesi Siswa:', '1 Sesi Aktif', valueColor: AppTheme.accentGreen, isDark: isDark),
                if (kDebugMode) ...[
                  Divider(color: dividerColor, height: 18),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  'Anti-Screenshot Lembar Ujian',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: titleColor),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF97316).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: const Color(0xFFF97316).withValues(alpha: 0.4),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: const Text(
                                    'DEBUG ONLY',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFFEA580C),
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _isScreenshotProtectionEnabled
                                  ? 'Aktif saat ujian (Home & Pengaturan tetap bisa ditangkap)'
                                  : 'Proteksi dinonaktifkan (Bisa Screenshot & Dokumentasi)',
                              style: TextStyle(
                                fontSize: 11,
                                color: _isScreenshotProtectionEnabled ? AppTheme.primaryGlow : const Color(0xFFFBBF24),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _isScreenshotProtectionEnabled,
                        activeThumbColor: AppTheme.primaryGlow,
                        activeTrackColor: AppTheme.primaryShiei.withValues(alpha: 0.4),
                        inactiveThumbColor: isDark ? Colors.white70 : const Color(0xFF94A3B8),
                        inactiveTrackColor: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                        onChanged: _toggleScreenshotProtection,
                      ),
                    ],
                  ),
                  Divider(color: dividerColor, height: 18),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  'Bypass Keluar Aplikasi (Testing)',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: titleColor),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF97316).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: const Color(0xFFF97316).withValues(alpha: 0.4),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: const Text(
                                    'DEBUG ONLY',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFFEA580C),
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _isAppExitBypassEnabled
                                  ? 'Bypass aktif: Bebas minimize/keluar app tanpa memicu lockout'
                                  : 'Standar: Proteksi fullscreen & deteksi keluar app aktif',
                              style: TextStyle(
                                fontSize: 11,
                                color: _isAppExitBypassEnabled ? const Color(0xFFFBBF24) : AppTheme.primaryGlow,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _isAppExitBypassEnabled,
                        activeThumbColor: const Color(0xFFFBBF24),
                        activeTrackColor: const Color(0xFFF59E0B).withValues(alpha: 0.4),
                        inactiveThumbColor: isDark ? Colors.white70 : const Color(0xFF94A3B8),
                        inactiveTrackColor: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                        onChanged: _toggleAppExitBypass,
                      ),
                    ],
                  ),
                  Divider(color: dividerColor, height: 18),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  'Bypass Suara Alarm (Anti-Berisik)',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: titleColor),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: const Color(0xFFEF4444).withValues(alpha: 0.4),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: const Text(
                                    'DEBUG ONLY',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFFDC2626),
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _isAntiAlarmBypassEnabled
                                  ? 'Bypass aktif: Sirine hening & volume tidak dipaksa 100% saat lockout'
                                  : 'Standar: Sirine keamanan berbunyi kencang & volume dipaksa 100%',
                              style: TextStyle(
                                fontSize: 11,
                                color: _isAntiAlarmBypassEnabled ? const Color(0xFFFBBF24) : AppTheme.primaryGlow,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _isAntiAlarmBypassEnabled,
                        activeThumbColor: const Color(0xFFFBBF24),
                        activeTrackColor: const Color(0xFFF59E0B).withValues(alpha: 0.4),
                        inactiveThumbColor: isDark ? Colors.white70 : const Color(0xFF94A3B8),
                        inactiveTrackColor: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                        onChanged: _toggleAntiAlarmBypass,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Section 3: Tema & Tampilan Aplikasi (White / Dark / System Mode)
          _buildSectionHeader('TEMA & TAMPILAN APLIKASI', Icons.palette_rounded),
          _buildThemeSelector(isDark, cardBg, cardBorder, titleColor, textColor),
          const SizedBox(height: 20),

          // Section: Catatan Rilis & Pembaruan Aplikasi (Navigates to dedicated ChangelogScreen)
          _buildSectionHeader('PEMBARUAN SISTEM', Icons.campaign_rounded),
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => Navigator.of(context).pushNamed(AppRoutes.changelog),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: cardBorder),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF97316).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFF97316).withValues(alpha: 0.35)),
                      ),
                      child: const Icon(Icons.history_edu_rounded, color: Color(0xFFFB923C), size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Catatan Rilis & Changelog',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: titleColor,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Lihat daftar pembaruan fitur & pengumuman resmi',
                            style: TextStyle(fontSize: 11.5, color: textColor),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Section 4: Ketentuan Layanan & Kebijakan Privasi
          _buildSectionHeader('KETENTUAN & PRIVASI', Icons.gavel_rounded),
          Material(
            color: cardBg,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: cardBorder),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(
                    Icons.description_outlined,
                    color: AppTheme.primaryGlow,
                  ),
                  title: Text(
                    'Ketentuan Layanan (ToS)',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: titleColor,
                    ),
                  ),
                  subtitle: Text(
                    'Perjanjian penggunaan, hardware lock & aturan pengawasan',
                    style: TextStyle(fontSize: 12, color: textColor),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right_rounded,
                    color: AppTheme.textMuted,
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const LegalDocumentScreen(
                        title: 'Ketentuan Layanan (ToS)',
                        subtitle:
                            'Perjanjian penggunaan, hardware lock & aturan pengawasan',
                        effectiveLabel:
                            'SHIEI Exam Pro · Berlaku efektif 16 Nov 2026',
                        sections: LegalDocumentScreen.termsSections,
                        icon: Icons.description_outlined,
                      ),
                    ),
                  ),
                ),
                Divider(height: 1, color: dividerColor),
                ListTile(
                  leading: const Icon(
                    Icons.privacy_tip_outlined,
                    color: AppTheme.accentGreen,
                  ),
                  title: Text(
                    'Kebijakan Privasi',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: titleColor,
                    ),
                  ),
                  subtitle: Text(
                    'Transparansi izin perangkat, server sekolah & proteksi data',
                    style: TextStyle(fontSize: 12, color: textColor),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right_rounded,
                    color: AppTheme.textMuted,
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const LegalDocumentScreen(
                        title: 'Kebijakan Privasi',
                        subtitle:
                            'Transparansi izin perangkat, server sekolah & proteksi data',
                        effectiveLabel:
                            'Pembaruan Kebijakan Privasi SHIEI · 16 Nov 2026',
                        sections: LegalDocumentScreen.privacySections,
                        icon: Icons.privacy_tip_outlined,
                        accentColor: AppTheme.accentGreen,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Section 5: Tentang Aplikasi
          _buildSectionHeader('TENTANG APLIKASI', Icons.info_outline_rounded),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.primaryShiei.withValues(alpha: 0.5), width: 1.5),
                      ),
                      child: ClipOval(
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Image.asset(
                            'assets/images/shiei_logo.png',
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.shield_rounded,
                              color: AppTheme.primaryGlow,
                              size: 22,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                'Versi ${AppUpdateService.displayAppVersion} (Build ${AppUpdateService.displayBuildNumber})',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: titleColor),
                              ),
                              if (AppUpdateService.isDebugBuild)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.5)),
                                  ),
                                  child: const Text(
                                    'DEBUG',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFFF59E0B),
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Menjaga Integritas, Mengawal Kejujuran Ujian',
                            style: TextStyle(fontSize: 10.5, color: AppTheme.primaryGlow),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Platform ujian browser terproteksi dengan kiosk lockdown, deteksi split-screen, proteksi panggilan suara, dan sesi tunggal aktif (single active session).',
                  style: TextStyle(fontSize: 12, color: textColor, height: 1.4),
                ),
                Divider(color: dividerColor, height: 22),
                _buildInfoRow('Versi Rilis Kiosk:', AppUpdateService.fullVersionString, valueColor: AppTheme.primaryGlow, isDark: isDark),
                const SizedBox(height: 8),
                _buildInfoRow('Pengembang:', 'HexaDev', isDark: isDark),
                const SizedBox(height: 8),
                _buildActionInfoRow(
                  label: 'Email:',
                  value: 'contact@hexadev.my.id',
                  icon: Icons.mail_outline_rounded,
                  isDark: isDark,
                  onTap: () => _confirmExternalLaunch(
                    icon: Icons.mail_outline_rounded,
                    title: 'Buka Aplikasi Email?',
                    body: 'Anda akan mengirim email ke contact@hexadev.my.id melalui aplikasi email perangkat.',
                    confirmLabel: 'Buka Email',
                    targetUrl: 'mailto:contact@hexadev.my.id',
                    failureMessage: 'Tidak ditemukan aplikasi email terpasang. Hubungi contact@hexadev.my.id secara manual.',
                  ),
                ),
                const SizedBox(height: 8),
                _buildActionInfoRow(
                  label: 'Situs:',
                  value: 'shiei.hexadev.my.id',
                  icon: Icons.open_in_new_rounded,
                  isDark: isDark,
                  onTap: () => _confirmExternalLaunch(
                    icon: Icons.open_in_browser_rounded,
                    title: 'Buka Situs Web?',
                    body: 'Anda akan membuka shiei.hexadev.my.id melalui browser perangkat Anda.',
                    confirmLabel: 'Buka Browser',
                    targetUrl: 'https://shiei.hexadev.my.id',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeSelector(bool isDark, Color cardBg, Color cardBorder, Color titleColor, Color textColor) {
    final currentMode = ThemeController.instance.themeMode;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pilih preferensi tema tampilan aplikasi:',
            style: TextStyle(fontSize: 12, color: textColor),
          ),
          const SizedBox(height: 14),

          // Unified Segmented Sliding Pill Container
          Container(
            height: 52,
            padding: const EdgeInsets.all(4.0),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                width: 1.2,
              ),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final double innerWidth = constraints.maxWidth;
                final double segmentWidth = innerWidth / 3;

                final int activeIndex = currentMode == ThemeMode.light
                    ? 0
                    : (currentMode == ThemeMode.dark ? 1 : 2);

                return Stack(
                  children: [
                    // Sliding Indicator Thumb
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeInOutCubic,
                      left: activeIndex * segmentWidth,
                      top: 0,
                      bottom: 0,
                      width: segmentWidth,
                      child: Container(
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B) : Colors.white,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: isDark
                                ? AppTheme.primaryShiei.withValues(alpha: 0.5)
                                : const Color(0xFFCBD5E1),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: isDark
                                  ? AppTheme.primaryShiei.withValues(alpha: 0.2)
                                  : const Color(0x180F172A),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Three Interactive Icon Buttons
                    Row(
                      children: [
                        _buildPillSegmentIcon(
                          icon: Icons.light_mode_rounded,
                          tooltip: 'Mode Terang',
                          isSelected: activeIndex == 0,
                          isDark: isDark,
                          onTap: () {
                            ThemeController.instance.setThemeMode(ThemeMode.light);
                            setState(() {});
                          },
                        ),
                        _buildPillSegmentIcon(
                          icon: Icons.dark_mode_rounded,
                          tooltip: 'Mode Gelap',
                          isSelected: activeIndex == 1,
                          isDark: isDark,
                          onTap: () {
                            ThemeController.instance.setThemeMode(ThemeMode.dark);
                            setState(() {});
                          },
                        ),
                        _buildPillSegmentIcon(
                          icon: Icons.phone_android_rounded,
                          tooltip: 'Ikuti Sistem HP',
                          isSelected: activeIndex == 2,
                          isDark: isDark,
                          onTap: () {
                            ThemeController.instance.setThemeMode(ThemeMode.system);
                            setState(() {});
                          },
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 12),

          // Mode Description Active Text below the Pill Slider
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.15),
                  end: Offset.zero,
                ).animate(anim),
                child: child,
              ),
            ),
            child: _buildActiveModeInfo(currentMode, isDark, titleColor, textColor),
          ),
        ],
      ),
    );
  }

  Widget _buildPillSegmentIcon({
    required IconData icon,
    required String tooltip,
    required bool isSelected,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    const activeColor = AppTheme.primaryShiei;
    final inactiveColor = isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8);

    return Expanded(
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: onTap,
            child: Center(
              child: AnimatedScale(
                scale: isSelected ? 1.12 : 1.0,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutBack,
                child: Icon(
                  icon,
                  size: 23,
                  color: isSelected ? activeColor : inactiveColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActiveModeInfo(ThemeMode mode, bool isDark, Color titleColor, Color textColor) {
    String title;
    String subtitle;
    IconData icon;

    switch (mode) {
      case ThemeMode.light:
        title = 'Mode Terang';
        subtitle = 'Tampilan putih bersih dengan kontras tinggi';
        icon = Icons.wb_sunny_rounded;
        break;
      case ThemeMode.dark:
        title = 'Mode Gelap';
        subtitle = 'Nuansa gelap obsidian OLED hemat baterai';
        icon = Icons.nightlight_round;
        break;
      case ThemeMode.system:
        title = 'Ikuti Sistem HP (Otomatis)';
        subtitle = 'Otomatis menyesuaikan dengan setelan tema perangkat HP Anda';
        icon = Icons.brightness_auto_rounded;
        break;
    }

    return Container(
      key: ValueKey(mode),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A).withValues(alpha: 0.6) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.primaryShiei),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: titleColor,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: textColor,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppTheme.primaryGlow),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryGlow,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? valueColor, bool isDark = true}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: isDark ? AppTheme.textSecondary : const Color(0xFF475569)),
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: valueColor ?? (isDark ? Colors.white : const Color(0xFF0F172A)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAdminLicenseCard(
    bool isDark,
    Color cardBg,
    Color cardBorder,
    Color titleColor,
    Color textColor,
    Color dividerColor,
  ) {
    final schoolName = _schoolData?['name']?.toString() ?? 'Sekolah Terdaftar';
    final tier = (_schoolData?['tier']?.toString() ?? 'STANDARD').toUpperCase();
    final usedStudents = _schoolData?['used_students'] ?? 0;
    final maxStudents = _schoolData?['max_students'] ?? 1000;
    final status = (_schoolData?['license_status']?.toString() ?? 'active').toUpperCase();
    final isVerified = status == 'ACTIVE' || status == 'VALID' || status == 'SETTLEMENT';
    final rawKey = _schoolData?['license_key']?.toString() ?? '';
    final licenseKey = rawKey.isNotEmpty ? rawKey : 'SHIEI-PRO-LOCAL-LICENSED';
    final maskedKey = licenseKey.length > 8
        ? '${licenseKey.substring(0, 4)}-****-****-${licenseKey.substring(licenseKey.length - 4)}'
        : 'SHIEI-****-****-****';
    final expiresAt = _schoolData?['license_expires_at'] != null
        ? _schoolData!['license_expires_at'].toString().split('T')[0]
        : 'Permanen / Aktif';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.workspace_premium_rounded, size: 14, color: Color(0xFFF59E0B)),
                    const SizedBox(width: 5),
                    Text(
                      tier,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFF59E0B),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isVerified
                      ? const Color(0xFF10B981).withValues(alpha: 0.14)
                      : const Color(0xFFEF4444).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isVerified ? 'TERVERIFIKASI & AKTIF' : status,
                  style: TextStyle(
                    color: isVerified ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          Divider(color: dividerColor, height: 20),
          _buildInfoRow('Nama Sekolah Terdaftar:', schoolName, isDark: isDark),
          Divider(color: dividerColor, height: 18),
          _buildInfoRow('Batas Kuota Siswa Aktif:', '$usedStudents / $maxStudents Siswa', valueColor: const Color(0xFF10B981), isDark: isDark),
          Divider(color: dividerColor, height: 18),
          _buildInfoRow('Masa Berlaku Lisensi:', expiresAt, isDark: isDark),
          Divider(color: dividerColor, height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Serial Kunci Lisensi:',
                style: TextStyle(fontSize: 12, color: isDark ? AppTheme.textSecondary : const Color(0xFF475569)),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _showFullLicenseKey ? licenseKey : maskedKey,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _showFullLicenseKey = !_showFullLicenseKey),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        _showFullLicenseKey ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        size: 16,
                        color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                      ),
                    ),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: licenseKey));
                      AppNotification.showSuccess(
                        context,
                        'Serial Lisensi Disalin',
                        subtitle: 'Kunci lisensi disalin ke clipboard.',
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.copy_rounded,
                        size: 15,
                        color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 38),
              side: BorderSide(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: _isLoadingLicense
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFF59E0B)),
                  )
                : const Icon(Icons.sync_rounded, size: 17, color: Color(0xFFF59E0B)),
            label: Text(
              _isLoadingLicense ? 'Menyinkronkan Lisensi...' : 'Segarkan Status & Kuota Lisensi',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
            onPressed: _isLoadingLicense ? null : () => _fetchLicenseStatus(showToast: true),
          ),
        ],
      ),
    );
  }

  Widget _buildActionInfoRow({
    required String label,
    required String value,
    required IconData icon,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Flexible(
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primaryGlow,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(icon, size: 13, color: AppTheme.primaryGlow),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmExternalLaunch({
    required IconData icon,
    required String title,
    required String body,
    required String confirmLabel,
    required String targetUrl,
    String? failureMessage,
  }) {
    final isDark = AppTheme.isDark(context);
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Batal',
      barrierColor: Colors.black.withValues(alpha: 0.6),
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (ctx, _, __) => AlertDialog(
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
            Icon(icon, color: AppTheme.primaryGlow, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          body,
          style: TextStyle(
            color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
            fontSize: 13,
            height: 1.45,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Batal',
              style: TextStyle(
                color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryShiei,
              foregroundColor: Colors.white,
              minimumSize: const Size(96, 38),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              final ok = await VolumeLockService.openBrowserUrl(targetUrl);
              if (!ok && mounted && failureMessage != null) {
                AppNotification.show(
                  context,
                  title: 'Tidak Dapat Membuka',
                  subtitle: failureMessage,
                  type: NotificationType.info,
                );
              }
            },
            child: Text(confirmLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      transitionBuilder: (ctx, anim1, _, child) {
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
