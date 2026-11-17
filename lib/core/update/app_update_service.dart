import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../config/app_config.dart';
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
  final String? checksumSha256;
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
    this.checksumSha256,
    required this.highlights,
  });

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) {
    final rawSha = json['checksum_sha256']?.toString().trim().toLowerCase();
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
      checksumSha256: (rawSha != null && rawSha.isNotEmpty) ? rawSha : null,
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

  static String _runtimeAppVersion = '2.6.2';
  static int _runtimeAppBuild = 8;

  static String get currentAppVersion => _runtimeAppVersion;
  static int get currentAppBuild => _runtimeAppBuild;
  static String get currentBuildNumber => '2026.$_runtimeAppBuild';

  /// Loads actual installed app version and build number from native bundle metadata (pubspec.yaml).
  static Future<void> initPackageInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final pkgVer = info.version.trim();
      final pkgBuild = int.tryParse(info.buildNumber.trim());
      if (pkgVer.isNotEmpty) {
        _runtimeAppVersion = pkgVer.split('-').first.split('+').first.trim();
      }
      if (pkgBuild != null && pkgBuild > 0) {
        _runtimeAppBuild = pkgBuild;
      }
    } catch (_) {
      // Headless unit tests or unsupported embedders retain compiled fallback defaults
    }
  }

  @visibleForTesting
  static void setRuntimeVersionForTest({
    required String version,
    required int build,
  }) {
    _runtimeAppVersion = version;
    _runtimeAppBuild = build;
  }

  /// True if running in debug mode (development / debug build)
  static bool get isDebugBuild => kDebugMode;

  /// Dynamic display version string differentiating debug builds from production releases.
  static String get displayAppVersion => kDebugMode ? '$currentAppVersion-debug' : currentAppVersion;

  /// Dynamic build number string.
  static String get displayBuildNumber => kDebugMode ? '$currentBuildNumber-dev' : currentBuildNumber;

  /// Formatted full version label for settings, changelogs, and headers.
  static String get fullVersionString => 'v$displayAppVersion (Build $displayBuildNumber)';

  // Local fallback changelogs to ensure offline availability
  static final List<VersionChangelog> fallbackChangelogs = [
    VersionChangelog(
      version: '2.6.2',
      buildNumber: '2026.8',
      releaseDate: '17 November 2026',
      isLatest: true,
      title: 'Pembaruan Aplikasi v2.6.2',
      headline: 'Pembaruan v2.6.2 menghadirkan mode browser Incognito sebagai default, pengelola akun Google khusus di dalam aplikasi, grafik kedisiplinan interaktif, dan sinkronisasi versi otomatis.',
      categories: [
        ChangelogCategory(
          name: 'Fitur Baru',
          items: [
            'Mode Guest (Incognito) Default: Peramban ujian kini otomatis berjalan tanpa menyimpan riwayat atau cookie.',
            'Account Picker Google Khusus SHIEI: Pemilihan, tambah akun baru, serta konfirmasi putus/hapus akun permanen langsung di antarmuka SHIEI.',
            'Grafik Kedisiplinan Interaktif: Grafik garis di tab Profil lengkap dengan tooltip judul ujian dan format durasi jam-menit.',
          ],
        ),
        ChangelogCategory(
          name: 'Keamanan & Kenyamanan Ujian',
          items: [
            'Izin Akses Akun Terpisah: Slide khusus izin akun/kontak sebelum memilih mode login browser.',
            'Pembersihan Clipboard Senyap: Sanitasi clipboard di awal sesi ujian tanpa notifikasi pop-up OS.',
            'Sinkronisasi Versi Otomatis: Mencegah stuck pembaruan berulang ketika versi aplikasi terbaru sudah terpasang.',
          ],
        ),
        ChangelogCategory(
          name: 'Peningkatan & Perbaikan',
          items: [
            'Pengumuman Pengawas Tertarget: Dukungan target kelas atau siswa aktif serta penekanan dialog pada ujian selesai.',
            'Perbaikan Layout & Responsivitas: Tombol dialog sejajar simetris serta tata letak optimal di layar 320px.',
            'Tour Installer & Maskot Terbaru: Ilustrasi chibi baru dan SHIEI Quad Banner.',
          ],
        ),
      ],
    ),
    VersionChangelog(
      version: '2.5.0',
      buildNumber: '2026.5',
      releaseDate: '30 September 2026',
      isLatest: false,
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
      title: 'Pembaruan Aplikasi v2.4.0',
      headline: 'Rilis pemeliharaan dan peningkatan kestabilan aplikasi ujian dengan sistem proteksi cerdas dan performa lebih ringan.',
      categories: [
        ChangelogCategory(
          name: 'Fitur Baru',
          items: [
            'Pengisian Baterai Lewat Colokan Listrik: Siswa tetap dapat mengisi daya HP menggunakan adaptor colokan dinding selama ujian tanpa memicu alarm keamanan.',
            'Tombol Pintas Pengaturan: Memudahkan siswa membuka pengaturan perangkat secara instan saat dibutuhkan panduan teknis pengawas.',
          ],
        ),
        ChangelogCategory(
          name: 'Keamanan & Kiosk',
          items: [
            'Sistem Pengaman USB Cerdas: Keamanan ujian akan aktif secara otomatis hanya jika HP terdeteksi terhubung kabel data ke komputer atau laptop.',
            'Sistem Proteksi Lebih Akurat: Menjaga aplikasi tetap terkunci aman selama sesi ujian berlangsung agar siswa dapat mengerjakan soal dengan tenang.',
          ],
        ),
        ChangelogCategory(
          name: 'Peningkatan & Perbaikan',
          items: [
            'Ukuran Aplikasi Lebih Ringkas: Aplikasi kini lebih hemat memori penyimpanan dan jauh lebih cepat saat pertama kali dibuka.',
            'Tampilan Kartu Lebih Rapi: Teks dan status pengawas kini tampil pas di layar HP berukuran ringkas tanpa terpotong.',
            'Performa Lebih Gesit: Optimalisasi animasi dan transisi agar penggunaan baterai tetap hemat selama ujian.',
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
  String? lastDownloadError;

  static final RegExp _sha256HexPattern = RegExp(r'^[a-f0-9]{64}$');

  /// Compare dotted semantic versions (e.g. "2.5.0" vs "2.4.9").
  static int compareVersions(String a, String b) {
    List<int> parseParts(String raw) {
      final cleaned = raw.split('-').first.split('+').first.trim();
      return cleaned.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    }

    final pa = parseParts(a);
    final pb = parseParts(b);
    final maxLen = pa.length > pb.length ? pa.length : pb.length;
    for (int i = 0; i < maxLen; i++) {
      final va = i < pa.length ? pa[i] : 0;
      final vb = i < pb.length ? pb[i] : 0;
      if (va != vb) return va.compareTo(vb);
    }
    return 0;
  }

  /// True when update policy requires blocking lobby access until updated.
  bool isForceUpdateRequired(AppUpdateInfo info) {
    final belowMinSupported = compareVersions(currentAppVersion, info.minSupportedVersion) < 0;
    final cmp = compareVersions(currentAppVersion, info.latestVersion);
    final isAlreadyUpToDate = cmp > 0 || (cmp == 0 && currentAppBuild >= info.latestBuild);
    // Allow builds equal to or newer than the server's latest release without trapping users in update loops.
    if (!belowMinSupported && isAlreadyUpToDate) {
      return false;
    }
    return info.forceUpdate || belowMinSupported || (info.hasUpdate && info.isMandatory);
  }

  /// Normalizes server update response against locally installed version & build number.
  AppUpdateInfo normalizeUpdatePolicy(AppUpdateInfo info) {
    final belowMinSupported = compareVersions(currentAppVersion, info.minSupportedVersion) < 0;
    final cmp = compareVersions(currentAppVersion, info.latestVersion);
    final isAlreadyUpToDate = !belowMinSupported &&
        (cmp > 0 || (cmp == 0 && currentAppBuild >= info.latestBuild));
    if (!isAlreadyUpToDate) {
      return info;
    }
    return AppUpdateInfo(
      clientVersion: currentAppVersion,
      latestVersion: info.latestVersion,
      latestBuild: info.latestBuild,
      hasUpdate: false,
      forceUpdate: false,
      isMandatory: false,
      minSupportedVersion: info.minSupportedVersion,
      releaseDate: info.releaseDate,
      releaseTitle: info.releaseTitle,
      fileSize: info.fileSize,
      downloadUrl: info.downloadUrl,
      checksumSha256: info.checksumSha256,
      highlights: info.highlights,
    );
  }

  bool _isValidDownloadUri(String rawUrl) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || !uri.hasAuthority || uri.host.trim().isEmpty) return false;
    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'https') return true;
    if (scheme == 'http' && AppConfig.isLocalOrPrivateHost(uri.host)) {
      return true;
    }
    return false;
  }

  bool _hasApkMagicHeader(File file) {
    RandomAccessFile? raf;
    try {
      if (!file.existsSync() || file.lengthSync() < 5 * 1024 * 1024) return false;
      raf = file.openSync(mode: FileMode.read);
      final bytes = raf.readSync(4);
      return bytes.length == 4 && bytes[0] == 0x50 && bytes[1] == 0x4B && bytes[2] == 0x03 && bytes[3] == 0x04;
    } catch (_) {
      return false;
    } finally {
      try {
        raf?.closeSync();
      } catch (_) {}
    }
  }

  /// Compute lowercase SHA-256 hex digest of a local file via native streaming implementation.
  Future<String?> computeFileSha256(String filePath) async {
    try {
      final hash = await _platformChannel.invokeMethod<String>('verifyFileSha256', {'filePath': filePath});
      return hash?.trim().toLowerCase();
    } catch (e) {
      debugPrint('[AppUpdateService] Native SHA-256 check error: $e');
      return null;
    }
  }

  /// Verify downloaded/cached APK integrity against expected SHA-256 checksum.
  Future<bool> verifyApkIntegrity(String filePath, String? expectedSha256) async {
    final file = File(filePath);
    if (!_hasApkMagicHeader(file)) {
      lastDownloadError = 'Berkas APK tidak valid atau korup (header arsip tidak sesuai).';
      return false;
    }

    final normalizedExpected = expectedSha256?.trim().toLowerCase() ?? '';
    if (!_sha256HexPattern.hasMatch(normalizedExpected)) {
      lastDownloadError = 'Checksum SHA-256 rilis belum tersedia dari server/Exam Manager. Instalasi otomatis dibatalkan demi keamanan.';
      return false;
    }

    final actualHash = await computeFileSha256(filePath);
    if (actualHash == null || actualHash != normalizedExpected) {
      lastDownloadError = 'Verifikasi integritas SHA-256 gagal! Berkas APK tidak cocok dengan rilis resmi dan telah dihapus.';
      return false;
    }

    return true;
  }

  /// Check for a newer version from the dev/backend server.
  Future<AppUpdateInfo?> checkForUpdate({
    String? currentVersion,
    int? currentBuild,
    String? platform,
  }) async {
    final effectiveVersion = currentVersion ?? currentAppVersion;
    final effectiveBuild = currentBuild ?? currentAppBuild;
    final activePlatform = platform ?? (Platform.isIOS ? 'ios' : (Platform.isWindows ? 'windows' : 'android'));
    try {
      final res = await _api.get(
        '/app/version-check',
        queryParameters: {
          'platform': activePlatform,
          'version': effectiveVersion,
          'build': effectiveBuild,
        },
      );

      if (res.statusCode == 200 && res.data != null && res.data['success'] == true) {
        final rawInfo = AppUpdateInfo.fromJson(Map<String, dynamic>.from(res.data));
        final normalized = normalizeUpdatePolicy(rawInfo);
        latestUpdateInfo = normalized;
        return normalized;
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

  /// Get the cached downloaded APK file path if it exists on disk, matches target version/build,
  /// and passes ZIP + SHA-256 integrity checks.
  Future<String?> getCachedApkPath({
    String targetVersion = '',
    int targetBuild = 0,
    String? expectedSha256,
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
      if (file.existsSync()) {
        final isIntact = await verifyApkIntegrity(savePath, expectedSha256);
        if (isIntact) {
          return savePath;
        }
        try {
          file.deleteSync();
        } catch (_) {}
      }
    } catch (_) {}
    return null;
  }

  /// Clean up stale or leftover downloaded APKs from storage to prevent storage bloat.
  Future<void> cleanupCachedApks({String? preserveVersion}) async {
    try {
      String? dirPath;
      try {
        dirPath = await _platformChannel.invokeMethod<String>('getAppCacheDir');
      } catch (_) {}
      final baseDir = (dirPath != null && dirPath.isNotEmpty) ? Directory(dirPath) : Directory.systemTemp;
      if (baseDir.existsSync()) {
        for (final entity in baseDir.listSync()) {
          if (entity is File && entity.path.toLowerCase().endsWith('.apk')) {
            if (preserveVersion != null && entity.path.contains('v$preserveVersion')) {
              continue;
            }
            try {
              entity.deleteSync();
              debugPrint('[AppUpdateService] Cleaned up cached APK: ${entity.path}');
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      debugPrint('[AppUpdateService] Error cleaning cached APKs: $e');
    }
  }

  /// Download APK directly inside the app with real-time byte progress and SHA-256 verification.
  Future<String?> downloadApk(
    String url, {
    String targetVersion = '',
    int targetBuild = 0,
    String? expectedSha256,
    required void Function(int received, int total) onProgress,
  }) async {
    lastDownloadError = null;
    if (url.isEmpty) {
      lastDownloadError = 'Tautan unduhan pembaruan kosong.';
      return null;
    }
    if (!_isValidDownloadUri(url)) {
      lastDownloadError = 'Tautan unduhan harus menggunakan HTTPS (kecuali server sekolah lokal yang terkonfigurasi).';
      return null;
    }

    final normalizedExpected = expectedSha256?.trim().toLowerCase() ?? '';
    if (!_sha256HexPattern.hasMatch(normalizedExpected)) {
      lastDownloadError = 'Checksum SHA-256 rilis belum tersedia dari server/Exam Manager. Instalasi otomatis dibatalkan demi keamanan.';
      return null;
    }

    try {
      String? dirPath;
      try {
        dirPath = await _platformChannel.invokeMethod<String>('getAppCacheDir');
      } catch (_) {}
      final baseDir = (dirPath != null && dirPath.isNotEmpty) ? Directory(dirPath) : Directory.systemTemp;

      // Clean up previous APKs to avoid storage bloat
      await cleanupCachedApks();

      final filename = (targetVersion.isNotEmpty && targetBuild > 0)
          ? 'shiei-kiosk-v$targetVersion-b$targetBuild.apk'
          : 'shiei-kiosk-update.apk';
      final savePath = '${baseDir.path}/$filename';

      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(minutes: 3),
        ),
      );
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

      final downloaded = File(savePath);
      if (downloaded.existsSync() && await verifyApkIntegrity(savePath, normalizedExpected)) {
        return savePath;
      }
      if (downloaded.existsSync()) {
        // Corrupt, incomplete, or checksum mismatch — delete immediately
        try { downloaded.deleteSync(); } catch (_) {}
      }
    } catch (e) {
      debugPrint('[AppUpdateService] Direct APK download failed: $e');
      lastDownloadError = 'Gagal mengunduh berkas APK. Periksa tautan rilis atau koneksi internet.';
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
    if (url.isEmpty || !_isValidDownloadUri(url)) return false;
    try {
      final success = await _platformChannel.invokeMethod<bool>('openBrowserUrl', {'url': url});
      return success ?? false;
    } catch (e) {
      debugPrint('[AppUpdateService] Platform error launching download URL: $e');
      return false;
    }
  }
}
