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

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _serverUrlController = TextEditingController(text: AppConfig.baseUrl);
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
  Map<String, dynamic>? _schoolData;
  bool _isLoadingLicense = false;
  bool _showFullLicenseKey = false;

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    final serial = await _authService.getDeviceUniqueIdentifier();
    final name = await VolumeLockService.getDeviceName();
    final model = await VolumeLockService.getDeviceId();
    final isSec = await TokenStorage.isScreenshotProtectionEnabled();
    final isExitBypass = await TokenStorage.isAppExitBypassEnabled();
    final isAlarmBypass = await TokenStorage.isAntiAlarmBypassEnabled();

    // Determine admin role status and school context
    final role = await TokenStorage.getRole();
    final user = await TokenStorage.getUser();
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
        _isAdmin = isAdmin;
        _schoolData = school;
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

    String formattedUrl = rawUrl;
    if (!formattedUrl.startsWith('http://') && !formattedUrl.startsWith('https://')) {
      formattedUrl = 'http://$formattedUrl';
    }

    final uri = Uri.tryParse(formattedUrl);
    if (uri == null || !uri.hasAuthority) {
      AppNotification.show(
        context,
        title: 'Pengaturan Database Gagal Tersimpan',
        subtitle: 'Format URL server database tidak valid.',
        type: NotificationType.error,
        duration: const Duration(milliseconds: 3200),
      );
      return;
    }

    setState(() => _isSavingServer = true);

    try {
      AppConfig.setCustomBaseUrl(formattedUrl);
      _serverUrlController.text = AppConfig.baseUrl;

      // 1. Notifikasi pertama: Pengaturan database berhasil tersimpan
      AppNotification.show(
        context,
        title: 'Pengaturan Database Berhasil Disimpan',
        subtitle: AppConfig.baseUrl,
        type: NotificationType.success,
        duration: const Duration(milliseconds: 2500),
      );
    } catch (_) {
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
                  onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                  decoration: const InputDecoration(
                    hintText: 'http://192.168.1.100:8000/api/v1',
                    prefixIcon: Icon(Icons.link_rounded, color: AppTheme.primaryGlow),
                  ),
                ),
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
            ),
          ),
          const SizedBox(height: 20),

          // Section 1.5: Status & Pengaturan Lisensi Sekolah (Khusus Administrator)
          if (_isAdmin) ...[
            _buildSectionHeader('STATUS & PENGATURAN LISENSI SEKOLAH', Icons.workspace_premium_rounded),
            _buildAdminLicenseCard(isDark, cardBg, cardBorder, titleColor, textColor, dividerColor),
            const SizedBox(height: 20),
          ],

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
                            Row(
                              children: [
                                Text(
                                  'Anti-Screenshot Lembar Ujian',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: titleColor),
                                ),
                                const SizedBox(width: 8),
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
                            Row(
                              children: [
                                Text(
                                  'Bypass Keluar Aplikasi (Testing)',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: titleColor),
                                ),
                                const SizedBox(width: 8),
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
                            Row(
                              children: [
                                Text(
                                  'Bypass Suara Alarm (Anti-Berisik)',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: titleColor),
                                ),
                                const SizedBox(width: 8),
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

          // Section 3: Tentang Aplikasi
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
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Versi ${AppUpdateService.displayAppVersion} (Build ${AppUpdateService.displayBuildNumber})',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: titleColor),
                            ),
                            if (AppUpdateService.isDebugBuild) ...[
                              const SizedBox(width: 8),
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
                          ],
                        ),
                        const Text(
                          'Menjaga Integritas, Mengawal Kejujuran Ujian',
                          style: TextStyle(fontSize: 10.5, color: AppTheme.primaryGlow),
                        ),
                      ],
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
                _buildInfoRow('Pengembang:', 'bapp Production', isDark: isDark),
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
          Text(
            title,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: AppTheme.primaryGlow,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? valueColor, bool isDark = true}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, color: isDark ? AppTheme.textSecondary : const Color(0xFF475569)),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: valueColor ?? (isDark ? Colors.white : const Color(0xFF0F172A)),
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
}
