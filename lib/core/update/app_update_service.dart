import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../api/api_client.dart';

class AppUpdateInfo {
  final String clientVersion;
  final String latestVersion;
  final int latestBuild;
  final bool hasUpdate;
  final bool forceUpdate;
  final bool isMandatory;
  final String minSupportedVersion;
  final String releaseDate;
  final String releaseTitle;
  final String fileSize;
  final String downloadUrl;
  final List<String> highlights;

  AppUpdateInfo({
    required this.clientVersion,
    required this.latestVersion,
    required this.latestBuild,
    required this.hasUpdate,
    required this.forceUpdate,
    this.isMandatory = false,
    this.minSupportedVersion = '1.0.0',
    required this.releaseDate,
    required this.releaseTitle,
    required this.fileSize,
    required this.downloadUrl,
    required this.highlights,
  });

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) {
    return AppUpdateInfo(
      clientVersion: json['client_version'] as String? ?? '1.0.0',
      latestVersion: json['latest_version'] as String? ?? '2.4.0',
      latestBuild: (json['latest_build'] as num?)?.toInt() ?? 4,
      hasUpdate: json['has_update'] as bool? ?? false,
      forceUpdate: json['force_update'] as bool? ?? false,
      isMandatory: json['is_mandatory'] as bool? ?? false,
      minSupportedVersion: json['min_supported_version'] as String? ?? '1.0.0',
      releaseDate: json['release_date'] as String? ?? 'Terbaru',
      releaseTitle: json['release_title'] as String? ?? 'Pembaruan Kiosk',
      fileSize: json['file_size'] as String? ?? '25.4 MB',
      downloadUrl: json['download_url'] as String? ?? '',
      highlights: (json['highlights'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
    );
  }
}

class ChangelogCategory {
  final String name;
  final List<String> items;

  ChangelogCategory({required this.name, required this.items});

  factory ChangelogCategory.fromJson(Map<String, dynamic> json) {
    return ChangelogCategory(
      name: json['name'] as String? ?? '',
      items: (json['items'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
    );
  }
}

class VersionChangelog {
  final String version;
  final String buildNumber;
  final String releaseDate;
  final bool isLatest;
  final String title;
  final String headline;
  final List<ChangelogCategory> categories;

  VersionChangelog({
    required this.version,
    required this.buildNumber,
    required this.releaseDate,
    required this.isLatest,
    required this.title,
    required this.headline,
    required this.categories,
  });

  factory VersionChangelog.fromJson(Map<String, dynamic> json) {
    return VersionChangelog(
      version: json['version'] as String? ?? '1.0.0',
      buildNumber: json['build_number']?.toString() ?? '2026.1',
      releaseDate: json['release_date'] as String? ?? '',
      isLatest: json['is_latest'] as bool? ?? false,
      title: json['title'] as String? ?? '',
      headline: json['headline'] as String? ?? '',
      categories: (json['categories'] as List<dynamic>?)
              ?.map((e) => ChangelogCategory.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class AppUpdateService {
  static final AppUpdateService instance = AppUpdateService._internal();
  factory AppUpdateService() => instance;
  AppUpdateService._internal();

  static const MethodChannel _platformChannel = MethodChannel('id.shiei/lockdown');
  final ApiClient _api = ApiClient();

  static const String currentAppVersion = '2.5.0';
  static const int currentAppBuild = 5;
  static const String currentBuildNumber = '2026.5';

  /// True if running in debug mode (development / debug build)
  static bool get isDebugBuild => kDebugMode;

  /// Dynamic display version string differentiating debug builds from production releases.
  /// E.g. '2.5.0-debug' vs '2.5.0'
  static String get displayAppVersion => kDebugMode ? '$currentAppVersion-debug' : currentAppVersion;

  /// Dynamic build number string.
  /// E.g. '2026.5-dev' vs '2026.5'
  static String get displayBuildNumber => kDebugMode ? '$currentBuildNumber-dev' : currentBuildNumber;

  /// Formatted full version label for settings, changelogs, and headers.
  static String get fullVersionString => 'v$displayAppVersion (Build $displayBuildNumber)';

  // Local fallback changelogs to ensure offline availability
  static final List<VersionChangelog> fallbackChangelogs = [
    VersionChangelog(
      version: '2.5.0',
      buildNumber: '2026.5',
      releaseDate: '30 September 2026',
      isLatest: true,
      title: 'Pembaruan Aplikasi v2.5.0',
      headline: 'Pembaruan v2.5.0 hadir dengan sistem pembaruan otomatis yang lebih praktis serta peningkatan keamanan agar ujian berjalan lancar dan tenang.',
      categories: [
        ChangelogCategory(
          name: 'Fitur Baru',
          items: [
            'Pembaruan Otomatis Lebih Praktis: Aplikasi kini dapat mendeteksi dan mengunduh versi terbaru secara langsung tanpa perlu repot unduh manual.',
            'Catatan Rilis Lebih Jelas: Informasi seputar fitur baru dan perbaikan kini tampil rapi dan mudah dibaca di menu Pengaturan.',
            'Pilihan "Jangan Ingatkan Lagi": Kamu bisa memilih untuk menunda pembaruan sementara waktu agar tidak terganggu saat ingin langsung masuk ujian.',
          ],
        ),
        ChangelogCategory(
          name: 'Keamanan & Kenyamanan Ujian',
          items: [
            'Pengisian Baterai Lebih Nyaman: Tetap bisa mengisi daya baterai lewat colokan listrik tembok selama ujian tanpa takut alarm menyala.',
            'Penguncian Tombol Kembali: Mencegah aplikasi tertutup secara tidak sengaja saat kamu sedang asyik mengerjakan soal.',
            'Bantuan Cepat untuk Pengawas: Memudahkan guru atau pengawas membantu siswa jika sewaktu-waktu terjadi kendala teknis di ruang ujian.',
          ],
        ),
        ChangelogCategory(
          name: 'Peningkatan & Perbaikan',
          items: [
            'Aplikasi Lebih Gesit & Hemat Baterai: Perpindahan layar terasa jauh lebih mulus dan tidak membuat perangkat cepat panas.',
            'Perbaikan Tulisan & Huruf: Teks di layar ponsel berukuran kompak kini lebih nyaman dibaca tanpa terpotong.',
            'Tetap Stabil Saat Sinyal Lemah: Aplikasi tetap berjalan lancar dan data tetap aman meski koneksi internet sekolah sempat tersendat.',
          ],
        ),
      ],
    ),
    VersionChangelog(
      version: '2.4.0',
      buildNumber: '2026.4',
      releaseDate: '24 September 2026',
      isLatest: false,
      title: 'Pembaruan Akbar Ekosistem SHIEI v2.4.0 (Golden Release)',
      headline: 'Integrasi arsitektur multi-platform terpadu, Guided Tour interaktif, Live Proctoring Guru, dan dual-engine cloud sync.',
      categories: [
        ChangelogCategory(
          name: 'Fitur Baru',
          items: [
            'Sistem Auto-Update Cerdas & Dual-Patch Policy (pembaruan opsional dengan penundaan vs wajib dengan lockdown ketat).',
            'Universal Multi-Platform Hub terintegrasi dengan distribusi berkecepatan tinggi via GitHub Releases CDN.',
            'Pusat Pembaruan Sistem (OTA System Updater) 1-Click pada School Panel dengan pencadangan dan rollback otomatis.',
            'Interactive 5-Step Guided Tour per-akun dengan dynamic spotlight cutout 60 FPS dan breathing pulse glow.',
            'Dashboard Pemantauan Guru (Teacher Live Proctoring) dengan radar integritas siswa dan modal detail komprehensif.',
            'Penyempurnaan kartu sesi ujian siswa dengan indikator penanggalan, jam mulai-selesai, dan nama pembuat ujian.',
          ],
        ),
        ChangelogCategory(
          name: 'Keamanan & Kiosk',
          items: [
            'Enforcement lockdown hardware back gesture (PopScope) saat mode pembaruan keamanan wajib aktif.',
            'Integrasi arsitektur database hybrid Dual-Engine (MySQL lokal + AWS RDS / Supabase PostgreSQL Cloud Sync).',
            'Sistem otentikasi token rotatif Single Active Session dan pengikatan serial hardware anti-duplikasi.',
            'Proteksi anti-contek berlapis: deteksi split-screen, floating apps, dan blokir tangkapan layar (FLAG_SECURE).',
          ],
        ),
        ChangelogCategory(
          name: 'Peningkatan & Perbaikan',
          items: [
            'Optimalisasi performa antarmuka 60 FPS pada transisi tab, modal lembar aksi, dan rendering lembar ujian.',
            'Penyempurnaan tata letak dan palet warna adaptif tema gelap dan terang (Dark/Light Mode) di seluruh layar.',
            'Pemberian kendali volume fisik perangkat saat sirine peringatan pelanggaran berbunyi.',
            'Peningkatan efisiensi transfer data dan polling cerdas berbasis ValueNotifier 1-detik.',
          ],
        ),
      ],
    ),
    VersionChangelog(
      version: '2.3.0',
      buildNumber: '2026.3',
      releaseDate: '22 September 2026',
      isLatest: false,
      title: 'Mesin Tur Panduan Interaktif & Penyempurnaan Animasi 60 FPS',
      headline: 'Panduan onboarding visual interaktif 5 langkah untuk pengenalan fitur kiosk dan pengawasan.',
      categories: [
        ChangelogCategory(
          name: 'Fitur Baru',
          items: [
            'Interactive 5-Step Guided Tour per-akun (strictly 1x per account) untuk orientasi siswa dan pengawas.',
            'Spotlight cutout dinamis 60 FPS (TweenAnimationBuilder) yang bertransformasi mulus antar elemen antarmuka.',
            'Breathing glow pulse border neon pada area fokus tur untuk meningkatkan kejelasan visual.',
          ],
        ),
        ChangelogCategory(
          name: 'Keamanan & Kiosk',
          items: [
            'Konsolidasi peringatan integritas kiosk dan anti-cheat ke dalam dialog profil siswa.',
            'Pencegahan duplikasi tur saat pergantian akun dan persistensi token storage yang aman.',
          ],
        ),
        ChangelogCategory(
          name: 'Peningkatan & Perbaikan',
          items: [
            'Penghapusan ghost step tur pada tombol tersembunyi dan transisi crossfade instan.',
            'Penyelarasan palet warna overlay tur pada mode gelap (Dark Mode) dan terang (Light Mode).',
          ],
        ),
      ],
    ),
    VersionChangelog(
      version: '2.2.0',
      buildNumber: '2026.22',
      releaseDate: '20 September 2026',
      isLatest: false,
      title: 'Modernisasi Kartu Sesi Ujian & Tata Letak Pengaturan',
      headline: 'Penyegaran tampilan kartu sesi ujian aktif dengan informasi waktu riil dan hierarki profil modern.',
      categories: [
        ChangelogCategory(
          name: 'Fitur Baru',
          items: [
            'Penanggalan lengkap dan jam mulai-selesai (bukan durasi total) pada kartu sesi ujian aktif.',
            'Pencantuman nama guru/admin pembuat ujian pada setiap kartu jadwal ujian.',
            'Label status kartu ujian yang lebih kontekstual dan komunikatif menggantikan teks kaku.',
          ],
        ),
        ChangelogCategory(
          name: 'Keamanan & Kiosk',
          items: [
            'Penguncian interaksi kartu ujian kadaluarsa atau sesi ujian yang telah dikunci pengawas.',
            'Sinkronisasi real-time status ujian aktif dengan timer countdown berbasis detik.',
          ],
        ),
        ChangelogCategory(
          name: 'Peningkatan & Perbaikan',
          items: [
            'Tata letak kartu pengaturan gaya Apple Settings/Material 3 dengan pembatas halus (hairline dividers).',
            'Perbaikan overflow teks pada layar ponsel beresolusi kompak.',
          ],
        ),
      ],
    ),
    VersionChangelog(
      version: '2.1.0',
      buildNumber: '2026.21',
      releaseDate: '18 September 2026',
      isLatest: false,
      title: 'Dashboard Pemantauan Guru & Radar Integritas Siswa',
      headline: 'Sistem live proctoring komprehensif bagi guru dan pengawas ruang ujian.',
      categories: [
        ChangelogCategory(
          name: 'Fitur Baru',
          items: [
            'Dashboard Teacher Live Proctoring dengan visualisasi radar chart integritas kepatuhan siswa.',
            'Modal detail siswa interaktif lengkap dengan riwayat log kejadian, durasi pengerjaan, dan status perangkat.',
            'Lembar aksi pengawas (Student Action Sheet) untuk buka kunci darurat, peringatan, dan reset sesi.',
          ],
        ),
        ChangelogCategory(
          name: 'Keamanan & Kiosk',
          items: [
            'Live sync status ujian siswa dengan indikator mekanis rolling counter detik (ShieiAnimatedCounter).',
            'Peringatan otomatis saat koneksi pengawas terputus dan pemulihan data instan.',
          ],
        ),
        ChangelogCategory(
          name: 'Peningkatan & Perbaikan',
          items: [
            'Dukungan gesture geser horizontal (swipeable PageView) pada tab pemantauan dan data sekolah.',
            'Optimasi performa re-render menggunakan ValueNotifier agar tidak membebani baterai perangkat.',
          ],
        ),
      ],
    ),
    VersionChangelog(
      version: '2.0.0',
      buildNumber: '2026.20',
      releaseDate: '15 September 2026',
      isLatest: false,
      title: 'Fondasi Arsitektur Dual-Engine Hybrid & Cloud Synchronization',
      headline: 'Lompatan besar arsitektur sinkronisasi lokal MySQL dengan AWS RDS / Supabase PostgreSQL Cloud.',
      categories: [
        ChangelogCategory(
          name: 'Fitur Utama',
          items: [
            'Arsitektur Dual-Engine Hybrid: MySQL untuk performa lokal sekolah + PostgreSQL untuk cadangan cloud terpusat.',
            'Sistem lisensi cloud real-time terintegrasi dengan License Manager Portal.',
            'Dev Security Vault & Kill-Switch darurat untuk manajemen lisensi sekolah bermasalah.',
          ],
        ),
        ChangelogCategory(
          name: 'Sistem Proteksi',
          items: [
            'Otentikasi Single Active Session berbasis rotasi token kriptografis anti-hijack.',
            'Pengikatan unik hardware serial perangkat untuk mencegah pertukaran ponsel antar siswa.',
            'Sistem otorisasi PIN pengawas darurat dan pemblokiran panggilan suara latar belakang.',
          ],
        ),
      ],
    ),
    VersionChangelog(
      version: '1.0.1',
      buildNumber: '2026.2',
      releaseDate: '11 September 2026',
      isLatest: false,
      title: 'Pembaruan Keamanan & Auto-Update Pengembang',
      headline: 'Rilis pemeliharaan dan peningkatan stabilitas Kiosk dengan sistem pembaruan mandiri.',
      categories: [
        ChangelogCategory(
          name: 'Fitur Baru',
          items: [
            'Sistem auto-update aplikasi langsung dari server developer tanpa perlu Play Store/App Store.',
            'Panel Catatan Rilis & Pengumuman interaktif dengan pemilihan versi di menu Pengaturan.',
            'Desain modern Kiosk Control Bar pada tampilan pengerjaan ujian siswa.',
          ],
        ),
        ChangelogCategory(
          name: 'Keamanan & Kiosk',
          items: [
            'Penyempurnaan proteksi sesi tunggal dan pemblokiran panggilan suara (Single Active Device Session).',
            'Sistem otorisasi PIN pengawas untuk keluar darurat dari mode terkunci.',
            'Proteksi tangkapan layar (FLAG_SECURE) dan blokir overlay melayang yang diperkuat.',
          ],
        ),
        ChangelogCategory(
          name: 'Peningkatan & Perbaikan',
          items: [
            'Kendali volume suara fisik diberikan kembali kepada siswa saat sirine peringatan berbunyi.',
            'Inisialisasi WebView pengerjaan ujian lebih gegas dan bebas lag (60 FPS).',
            'Penyelarasan tagline resmi menjadi Bahasa Indonesia: "Menjaga Integritas, Mengawal Kejujuran Ujian".',
          ],
        ),
      ],
    ),
    VersionChangelog(
      version: '1.0.0',
      buildNumber: '2026.1',
      releaseDate: '01 September 2026',
      isLatest: false,
      title: 'Rilis Perdana Kiosk Pelajar Project SHIEI',
      headline: 'Fondasi awal platform ujian sekolah terintegrasi anti-contek tingkat tinggi.',
      categories: [
        ChangelogCategory(
          name: 'Fitur Utama',
          items: [
            'Lockdown Kiosk Mode penuh untuk Android (blokir tombol Home, Recent Apps, dan Notifikasi).',
            'Tampilan antarmuka ujian terproteksi dengan browser terisolasi.',
            'Integrasi QR Code Scanner untuk masuk ke sesi ujian secara instan.',
          ],
        ),
        ChangelogCategory(
          name: 'Sistem Proteksi',
          items: [
            'Deteksi split-screen, floating window, dan multi-display otomatis.',
            'Pengikatan perangkat ujian berbasis serial unik hardware.',
            'Alarm sirine peringatan otomatis saat mendeteksi indikasi kecurangan.',
          ],
        ),
      ],
    ),
  ];

  AppUpdateInfo? latestUpdateInfo;

  /// Check for a newer version from the dev/backend server.
  Future<AppUpdateInfo?> checkForUpdate({
    String currentVersion = currentAppVersion,
    int currentBuild = currentAppBuild,
    String? platform,
  }) async {
    final activePlatform = platform ?? (Platform.isIOS ? 'ios' : (Platform.isWindows ? 'windows' : 'android'));
    try {
      final res = await _api.get(
        '/app/version-check',
        queryParameters: {
          'platform': activePlatform,
          'version': currentVersion,
          'build': currentBuild,
        },
      );

      if (res.statusCode == 200 && res.data != null && res.data['success'] == true) {
        final info = AppUpdateInfo.fromJson(Map<String, dynamic>.from(res.data));
        latestUpdateInfo = info;
        return info;
      }
    } catch (e) {
      debugPrint('[AppUpdateService] Error checking version: $e');
    }
    return null;
  }

  /// Fetch changelogs from server with fallback to bundled history.
  Future<List<VersionChangelog>> fetchChangelogs() async {
    try {
      final res = await _api.get('/app/changelogs');
      if (res.statusCode == 200 && res.data != null && res.data['changelogs'] is List) {
        final list = (res.data['changelogs'] as List)
            .map((e) => VersionChangelog.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        if (list.isNotEmpty) return list;
      }
    } catch (e) {
      debugPrint('[AppUpdateService] Failed to fetch changelogs from server, using fallback: $e');
    }
    return fallbackChangelogs;
  }

  /// Get the cached downloaded APK file path if it exists on disk and matches target version/build.
  Future<String?> getCachedApkPath({
    String targetVersion = '',
    int targetBuild = 0,
  }) async {
    try {
      String? dirPath;
      try {
        dirPath = await _platformChannel.invokeMethod<String>('getAppCacheDir');
      } catch (_) {}
      final baseDir = (dirPath != null && dirPath.isNotEmpty) ? Directory(dirPath) : Directory.systemTemp;
      
      final filename = (targetVersion.isNotEmpty && targetBuild > 0)
          ? 'shiei-kiosk-v$targetVersion-b$targetBuild.apk'
          : 'shiei-kiosk-update.apk';
      final savePath = '${baseDir.path}/$filename';
      final file = File(savePath);
      if (file.existsSync() && file.lengthSync() > 1024 * 1024) {
        return savePath;
      }
    } catch (_) {}
    return null;
  }

  /// Download APK directly inside the app with real-time byte progress.
  Future<String?> downloadApk(
    String url, {
    String targetVersion = '',
    int targetBuild = 0,
    required void Function(int received, int total) onProgress,
  }) async {
    if (url.isEmpty) return null;
    try {
      String? dirPath;
      try {
        dirPath = await _platformChannel.invokeMethod<String>('getAppCacheDir');
      } catch (_) {}
      final baseDir = (dirPath != null && dirPath.isNotEmpty) ? Directory(dirPath) : Directory.systemTemp;
      
      // Clean up any stale or previous APKs to avoid storage bloat and version confusion
      try {
        if (baseDir.existsSync()) {
          for (final entity in baseDir.listSync()) {
            if (entity is File && entity.path.toLowerCase().endsWith('.apk')) {
              try {
                entity.deleteSync();
              } catch (_) {}
            }
          }
        }
      } catch (_) {}

      final filename = (targetVersion.isNotEmpty && targetBuild > 0)
          ? 'shiei-kiosk-v$targetVersion-b$targetBuild.apk'
          : 'shiei-kiosk-update.apk';
      final savePath = '${baseDir.path}/$filename';

      final dio = Dio();
      await dio.download(
        url,
        savePath,
        onReceiveProgress: onProgress,
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: true,
          validateStatus: (status) => status != null && status >= 200 && status < 400,
        ),
      );

      if (File(savePath).existsSync()) {
        return savePath;
      }
    } catch (e) {
      debugPrint('[AppUpdateService] Direct APK download failed: $e');
    }
    return null;
  }

  /// Trigger native package installer via FileProvider.
  Future<bool> installApk(String filePath) async {
    if (filePath.isEmpty) return false;
    try {
      final success = await _platformChannel.invokeMethod<bool>('installApk', {'filePath': filePath});
      return success ?? false;
    } catch (e) {
      debugPrint('[AppUpdateService] Platform error installing APK: $e');
      return false;
    }
  }

  /// Check if the app has permission to install unknown apps (Android 8+).
  Future<bool> canRequestPackageInstalls() async {
    try {
      final canInstall = await _platformChannel.invokeMethod<bool>('canRequestPackageInstalls');
      return canInstall ?? true;
    } catch (e) {
      return true;
    }
  }

  /// Open Android OS settings for "Install unknown apps" permission.
  Future<bool> openInstallPermissionSettings() async {
    try {
      final success = await _platformChannel.invokeMethod<bool>('openInstallPermissionSettings');
      return success ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Launch APK download URL in browser (fallback).
  Future<bool> openDownloadUrl(String url) async {
    if (url.isEmpty) return false;
    try {
      final success = await _platformChannel.invokeMethod<bool>('openBrowserUrl', {'url': url});
      return success ?? false;
    } catch (e) {
      debugPrint('[AppUpdateService] Platform error launching download URL: $e');
      return false;
    }
  }
}
