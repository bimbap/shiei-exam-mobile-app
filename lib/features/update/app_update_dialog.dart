import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/update/app_update_service.dart';
import '../../shared/theme/app_theme.dart';

class AppUpdateDialog extends StatefulWidget {
  final AppUpdateInfo updateInfo;

  const AppUpdateDialog({
    super.key,
    required this.updateInfo,
  });

  static const _storage = FlutterSecureStorage();
  static String _dismissKey(String version) => 'update_dismissed_v$version';

  /// Show the dialog only if the user hasn't dismissed this version before.
  /// Force updates always show regardless.
  static Future<void> show(BuildContext context, AppUpdateInfo updateInfo) async {
    if (!updateInfo.forceUpdate) {
      final dismissed = await _storage.read(key: _dismissKey(updateInfo.latestVersion));
      if (dismissed == 'true') return;
    }
    if (!context.mounted) return;
    return showDialog(
      context: context,
      barrierDismissible: !updateInfo.forceUpdate,
      builder: (ctx) => AppUpdateDialog(updateInfo: updateInfo),
    );
  }

  static Future<void> clearDismissed(String version) async {
    await _storage.delete(key: _dismissKey(version));
  }

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog> {
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  int _totalBytes = 0;
  String? _errorMessage;
  String _statusText = 'Siap mengunduh pembaruan';
  String? _cachedApkPath;
  bool _doNotShowAgain = false;

  @override
  void initState() {
    super.initState();
    AppUpdateService.instance
        .getCachedApkPath(
          targetVersion: widget.updateInfo.latestVersion,
          targetBuild: widget.updateInfo.latestBuild,
        )
        .then((path) {
      if (mounted && path != null) {
        setState(() {
          _cachedApkPath = path;
          _downloadProgress = 1.0;
          _statusText = 'Berkas pembaruan v${widget.updateInfo.latestVersion} siap dipasang.';
        });
      }
    });
  }

  Future<void> _startDirectDownloadAndInstall() async {
    // Check if target version APK is already cached on disk
    _cachedApkPath ??= await AppUpdateService.instance.getCachedApkPath(
      targetVersion: widget.updateInfo.latestVersion,
      targetBuild: widget.updateInfo.latestBuild,
    );

    // If APK is already downloaded, try to install directly without re-downloading
    if (_cachedApkPath != null && File(_cachedApkPath!).existsSync()) {
      final canInstall = await AppUpdateService.instance.canRequestPackageInstalls();
      if (!canInstall && mounted) {
        await AppUpdateService.instance.openInstallPermissionSettings();
        setState(() {
          _isDownloading = false;
          _errorMessage = 'Silakan aktifkan toggle "Izinkan dari sumber ini" di setelan Android yang terbuka, lalu tekan tombol Pasang kembali.';
        });
        return;
      }
      setState(() {
        _isDownloading = false;
        _errorMessage = null;
        _statusText = 'Membuka installer Android...';
      });
      final success = await AppUpdateService.instance.installApk(_cachedApkPath!);
      if (!success && mounted) {
        final stillCanInstall = await AppUpdateService.instance.canRequestPackageInstalls();
        setState(() {
          if (!stillCanInstall) {
            _errorMessage = 'Izin pemasangan belum aktif. Aktifkan "Izinkan dari sumber ini" di setelan Android.';
          } else {
            _errorMessage = 'Gagal membuka installer. Pastikan berkas APK valid atau coba unduh ulang.';
          }
        });
      }
      return;
    }

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _totalBytes = 0;
      _errorMessage = null;
      _statusText = 'Menghubungi server sekolah...';
    });

    // Check permission to install unknown apps on Android 8+
    final canInstall = await AppUpdateService.instance.canRequestPackageInstalls();
    if (!canInstall && mounted) {
      final isDark = AppTheme.isDark(context);
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            ),
          ),
          title: Row(
            children: [
              Icon(
                Icons.security_rounded,
                color: isDark ? const Color(0xFFFB923C) : const Color(0xFFEA580C),
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Izin Pemasangan APK',
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
            'Untuk memasang pembaruan secara langsung, sistem Android memerlukan izin "Install aplikasi dari sumber tidak dikenal" untuk aplikasi Shiei Kiosk.\n\nBuka setelan sekarang untuk mengaktifkannya?',
            style: TextStyle(
              color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
              fontSize: 13,
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(
                'Batal',
                style: TextStyle(color: isDark ? AppTheme.textMuted : const Color(0xFF64748B)),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryShiei,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                Navigator.of(ctx).pop(true);
                await AppUpdateService.instance.openInstallPermissionSettings();
              },
              child: const Text('Buka Pengaturan', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );

      if (proceed != true) {
        setState(() {
          _isDownloading = false;
          _statusText = 'Pemasangan dibatalkan (izin belum diberikan).';
        });
        return;
      }
    }

    setState(() {
      _statusText = 'Mengunduh berkas APK v${widget.updateInfo.latestVersion}...';
    });

    final apkPath = await AppUpdateService.instance.downloadApk(
      widget.updateInfo.downloadUrl,
      targetVersion: widget.updateInfo.latestVersion,
      targetBuild: widget.updateInfo.latestBuild,
      onProgress: (received, total) {
        if (!mounted) return;
        setState(() {
          _totalBytes = total;
          if (total > 0) {
            _downloadProgress = (received / total).clamp(0.0, 1.0);
            final percent = (_downloadProgress * 100).toInt();
            final recMB = (received / (1024 * 1024)).toStringAsFixed(1);
            final totMB = (total / (1024 * 1024)).toStringAsFixed(1);
            _statusText = 'Mengunduh... $percent% ($recMB MB / $totMB MB)';
          } else {
            final recMB = (received / (1024 * 1024)).toStringAsFixed(1);
            _statusText = 'Mengunduh... $recMB MB';
          }
        });
      },
    );

    if (!mounted) return;

    if (apkPath != null && apkPath.isNotEmpty) {
      _cachedApkPath = apkPath;
      setState(() {
        _isDownloading = false;
        _downloadProgress = 1.0;
        _statusText = 'Unduhan selesai! Membuka installer Android...';
      });

      // Trigger native package installer
      final installTriggered = await AppUpdateService.instance.installApk(apkPath);
      if (!installTriggered && mounted) {
        setState(() {
          _errorMessage = 'Gagal membuka installer. Silakan aktifkan izin "Izinkan dari sumber ini" di setelan Android, lalu tekan tombol Pasang Pembaruan.';
        });
      }
    } else {
      await AppUpdateService.instance.cleanupCachedApks();
      setState(() {
        _isDownloading = false;
        _errorMessage = 'Gagal mengunduh berkas APK. Tautan unduhan mungkin tidak dapat diakses secara publik (404/Private) atau koneksi internet terputus.';
        _statusText = 'Unduhan gagal.';
      });
    }
  }

  Future<void> _showEmergencyBypassDialog() async {
    final isDark = AppTheme.isDark(context);
    final bypass = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
        ),
        title: Row(
          children: [
            const Icon(Icons.shield_outlined, color: AppTheme.dangerRed, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Akses Darurat Pengawas',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
            ),
          ],
        ),
        content: Text(
          'Pembaruan wajib gagal diunduh karena kendala jaringan atau tautan unduhan tidak dapat diakses.\n\nApakah pengawas mengizinkan siswa melewati pembaruan ini sementara waktu agar dapat mengikuti ujian?',
          style: TextStyle(
            fontSize: 12.5,
            height: 1.4,
            color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Batal',
              style: TextStyle(color: isDark ? AppTheme.textMuted : const Color(0xFF64748B)),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.dangerRed,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Izinkan Lewati (Darurat)', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (bypass == true && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final updateInfo = widget.updateInfo;
    final isDark = AppTheme.isDark(context);

    return PopScope(
      canPop: !updateInfo.forceUpdate && !_isDownloading,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: updateInfo.forceUpdate
                  ? AppTheme.dangerRed.withOpacity(isDark ? 0.7 : 0.5)
                  : (isDark ? AppTheme.primaryShiei.withOpacity(0.6) : const Color(0xFFFED7AA)),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: updateInfo.forceUpdate
                    ? AppTheme.dangerRed.withOpacity(isDark ? 0.25 : 0.15)
                    : (isDark ? AppTheme.primaryGlow.withOpacity(0.2) : const Color(0xFF0F172A).withOpacity(0.12)),
                blurRadius: 28,
                spreadRadius: 2,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Banner
              Container(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: updateInfo.forceUpdate
                        ? (isDark
                            ? [AppTheme.dangerRed.withOpacity(0.35), const Color(0xFF0F172A)]
                            : [const Color(0xFFFEF2F2), Colors.white])
                        : (isDark
                            ? [AppTheme.primaryShiei.withOpacity(0.35), const Color(0xFF0F172A)]
                            : [const Color(0xFFFFF7ED), Colors.white]),
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(19)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: updateInfo.forceUpdate
                            ? (isDark ? AppTheme.dangerRed.withOpacity(0.25) : const Color(0xFFFEE2E2))
                            : (isDark ? AppTheme.primaryShiei.withOpacity(0.25) : const Color(0xFFFFEDD5)),
                        border: Border.all(
                          color: updateInfo.forceUpdate
                              ? AppTheme.dangerRed
                              : (isDark ? AppTheme.primaryGlow : const Color(0xFFF97316)),
                          width: 1.5,
                        ),
                      ),
                      child: Icon(
                        updateInfo.forceUpdate ? Icons.security_rounded : Icons.system_update_alt_rounded,
                        color: updateInfo.forceUpdate
                            ? (isDark ? const Color(0xFFFCA5A5) : AppTheme.dangerRed)
                            : (isDark ? AppTheme.primaryGlow : const Color(0xFFEA580C)),
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            updateInfo.forceUpdate ? 'Pembaruan Keamanan Wajib' : 'Pembaruan Tersedia',
                            style: TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: updateInfo.forceUpdate
                                      ? (isDark ? AppTheme.dangerRed.withOpacity(0.3) : const Color(0xFFFEE2E2))
                                      : (isDark ? AppTheme.primaryShiei.withOpacity(0.3) : const Color(0xFFFFEDD5)),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: updateInfo.forceUpdate
                                        ? (isDark ? AppTheme.dangerRed.withOpacity(0.6) : const Color(0xFFFCA5A5))
                                        : (isDark ? AppTheme.primaryGlow.withOpacity(0.5) : const Color(0xFFFDBA74)),
                                  ),
                                ),
                                child: Text(
                                  updateInfo.forceUpdate ? 'WAJIB v${updateInfo.latestVersion}' : 'v${updateInfo.latestVersion}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: updateInfo.forceUpdate
                                        ? (isDark ? const Color(0xFFFCA5A5) : const Color(0xFF991B1B))
                                        : (isDark ? AppTheme.primaryGlow : const Color(0xFFC2410C)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                                  ),
                                ),
                                child: Text(
                                  updateInfo.fileSize,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark ? Colors.white70 : const Color(0xFF475569),
                                    fontWeight: FontWeight.w500,
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

              // Content Body
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      updateInfo.releaseTitle,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Dirilis pada ${updateInfo.releaseDate}',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Mandatory Warning Box
                    if (updateInfo.forceUpdate) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: isDark ? AppTheme.dangerRed.withOpacity(0.18) : const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isDark ? AppTheme.dangerRed.withOpacity(0.4) : const Color(0xFFFECACA),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: AppTheme.dangerRed, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Pembaruan ini diwajibkan oleh server sekolah untuk menjaga integritas anti-contek. Anda tidak dapat memasuki ruang ujian sebelum memasang pembaruan ini.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark ? const Color(0xFFFCA5A5) : const Color(0xFF991B1B),
                                  fontWeight: FontWeight.w600,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Highlights List
                    Text(
                      'Sorotan Pembaruan:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white70 : const Color(0xFF334155),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF1E293B).withOpacity(0.6)
                            : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Column(
                        children: updateInfo.highlights.take(4).map((item) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '• ',
                                  style: TextStyle(
                                    color: isDark ? AppTheme.primaryGlow : const Color(0xFFEA580C),
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    item,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark ? Colors.white : const Color(0xFF334155),
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // In-App Download Progress / Status Bar
                    if (_isDownloading || _downloadProgress > 0) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark
                                ? AppTheme.primaryShiei.withOpacity(0.5)
                                : const Color(0xFFFED7AA),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _isDownloading ? 'Mengunduh APK...' : 'Unduhan Siap',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                                  ),
                                ),
                                Text(
                                  '${(_downloadProgress * 100).toInt()}%',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: isDark ? AppTheme.primaryGlow : const Color(0xFFEA580C),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: _totalBytes > 0 ? _downloadProgress : null,
                                minHeight: 8,
                                backgroundColor: isDark
                                    ? const Color(0xFF0F172A)
                                    : const Color(0xFFE2E8F0),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  isDark ? AppTheme.primaryGlow : const Color(0xFFEA580C),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _statusText,
                              style: TextStyle(
                                fontSize: 10.5,
                                color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],

                    // Error Box
                    if (_errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppTheme.dangerRed.withOpacity(0.18)
                              : const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isDark
                                ? AppTheme.dangerRed.withOpacity(0.4)
                                : const Color(0xFFFECACA),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.error_outline_rounded, size: 16, color: AppTheme.dangerRed),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark ? Colors.white : const Color(0xFF991B1B),
                                      height: 1.3,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (_errorMessage!.contains('Izin') || _errorMessage!.contains('setelan') || _errorMessage!.contains('toggle')) ...[
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerRight,
                                child: InkWell(
                                  onTap: () => AppUpdateService.instance.openInstallPermissionSettings(),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? AppTheme.primaryShiei.withOpacity(0.3)
                                          : const Color(0xFFFFEDD5),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: isDark
                                            ? AppTheme.primaryGlow.withOpacity(0.5)
                                            : const Color(0xFFFDBA74),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.settings_rounded,
                                          size: 13,
                                          color: isDark ? AppTheme.primaryGlow : const Color(0xFFEA580C),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Buka Setelan Sekarang',
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.bold,
                                            color: isDark ? AppTheme.primaryGlow : const Color(0xFFC2410C),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ] else ...[
                              const SizedBox(height: 10),
                              Wrap(
                                alignment: WrapAlignment.end,
                                spacing: 8,
                                runSpacing: 6,
                                children: [
                                  if (widget.updateInfo.downloadUrl.isNotEmpty)
                                    InkWell(
                                      onTap: () => AppUpdateService.instance.openDownloadUrl(widget.updateInfo.downloadUrl),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(
                                            color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.open_in_browser_rounded,
                                              size: 13,
                                              color: isDark ? Colors.white70 : const Color(0xFF475569),
                                            ),
                                            const SizedBox(width: 5),
                                            Text(
                                              'Buka di Browser',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: isDark ? Colors.white : const Color(0xFF334155),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  if (widget.updateInfo.forceUpdate)
                                    InkWell(
                                      onTap: _showEmergencyBypassDialog,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: isDark
                                              ? AppTheme.dangerRed.withOpacity(0.25)
                                              : const Color(0xFFFEE2E2),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(
                                            color: isDark
                                                ? AppTheme.dangerRed.withOpacity(0.6)
                                                : const Color(0xFFFCA5A5),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.shield_outlined,
                                              size: 13,
                                              color: AppTheme.dangerRed,
                                            ),
                                            const SizedBox(width: 5),
                                            const Text(
                                              'Akses Darurat Pengawas',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: AppTheme.dangerRed,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],

                    // Notice about Direct Install Permission
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 14,
                            color: isDark ? AppTheme.primaryGlow : const Color(0xFFEA580C),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Pemasangan dilakukan langsung di aplikasi. Jika Android meminta konfirmasi izin, aktifkan "Izinkan dari sumber ini".',
                              style: TextStyle(
                                fontSize: 10.5,
                                color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
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

              // Action Buttons
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                child: Column(
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryShiei,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 44),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 4,
                      ),
                      onPressed: _isDownloading ? null : _startDirectDownloadAndInstall,
                      icon: _isDownloading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.download_rounded, size: 18),
                      label: Text(
                        _isDownloading
                            ? 'Sedang Mengunduh...'
                            : (_downloadProgress == 1.0 ? 'Pasang Pembaruan Ulang' : 'Unduh & Pasang Sekarang'),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (!updateInfo.forceUpdate && !_isDownloading) ...[
                      const SizedBox(height: 8),
                      // "Jangan tampilkan lagi" checkbox
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => setState(() => _doNotShowAgain = !_doNotShowAgain),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 18,
                                height: 18,
                                child: Checkbox(
                                  value: _doNotShowAgain,
                                  onChanged: (val) => setState(() => _doNotShowAgain = val ?? false),
                                  activeColor: isDark ? AppTheme.primaryShiei : const Color(0xFFF97316),
                                  side: BorderSide(
                                    color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
                                  ),
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Jangan ingatkan lagi untuk versi ini',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      TextButton(
                        onPressed: () async {
                          if (_doNotShowAgain) {
                            await AppUpdateDialog._storage.write(
                              key: AppUpdateDialog._dismissKey(updateInfo.latestVersion),
                              value: 'true',
                            );
                          }
                          if (context.mounted) Navigator.of(context).pop();
                        },
                        child: Text(
                          'Nanti Saja',
                          style: TextStyle(
                            color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B),
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    ],
                  ],
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
