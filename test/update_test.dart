import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:shiei_kiosk/core/update/app_update_service.dart';
import 'package:shiei_kiosk/features/update/changelog_screen.dart';
import 'package:shiei_kiosk/shared/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel('id.shiei/lockdown');
  final List<MethodCall> log = <MethodCall>[];

  setUp(() {
    log.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      log.add(methodCall);
      if (methodCall.method == 'openBrowserUrl') {
        return true;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('AppUpdateInfo parses JSON correctly', () {
    final json = {
      'client_version': '1.0.0',
      'latest_version': '1.0.1',
      'latest_build': 2,
      'has_update': true,
      'force_update': false,
      'release_date': '11 September 2026',
      'release_title': 'Pembaruan Kiosk & Auto-Update Dev',
      'file_size': '24.8 MB',
      'download_url': 'http://127.0.0.1:8000/api/v1/app/download-latest',
      'highlights': [
        'Sistem pembaruan mandiri',
        'Panel catatan rilis',
      ],
    };

    final info = AppUpdateInfo.fromJson(json);
    expect(info.latestVersion, equals('1.0.1'));
    expect(info.latestBuild, equals(2));
    expect(info.hasUpdate, isTrue);
    expect(info.forceUpdate, isFalse);
    expect(info.highlights.length, equals(2));
    expect(info.downloadUrl, equals('http://127.0.0.1:8000/api/v1/app/download-latest'));
  });

  test('VersionChangelog parses categories correctly', () {
    final changelogs = AppUpdateService.fallbackChangelogs;
    expect(changelogs.isNotEmpty, isTrue);
    expect(changelogs.first.version, equals('2.7.0'));
    expect(changelogs.first.isLatest, isTrue);
    expect(changelogs.first.categories.length, equals(3));
    expect(changelogs.first.categories.first.name, equals('Fitur Baru'));
  });

  test('openDownloadUrl dispatches HTTPS calls and rejects untrusted HTTP URLs', () async {
    final rejected = await AppUpdateService.instance.openDownloadUrl('http://example.com/app.apk');
    expect(rejected, isFalse);
    expect(log.any((call) => call.method == 'openBrowserUrl'), isFalse);

    final success = await AppUpdateService.instance.openDownloadUrl('https://example.com/app.apk');
    expect(success, isTrue);
    expect(log.any((call) => call.method == 'openBrowserUrl'), isTrue);
    expect(log.firstWhere((call) => call.method == 'openBrowserUrl').arguments['url'], equals('https://example.com/app.apk'));
  });

  test('compareVersions and isForceUpdateRequired enforce minSupportedVersion and checksum parsing', () {
    expect(AppUpdateService.compareVersions('2.5.0', '2.5.1'), lessThan(0));
    expect(AppUpdateService.compareVersions('2.5.0', '2.5.0'), equals(0));
    expect(AppUpdateService.compareVersions('2.6.0', '2.5.9'), greaterThan(0));

    final enforcedByMinVersion = AppUpdateInfo.fromJson({
      'client_version': '2.7.0',
      'latest_version': '2.8.0',
      'latest_build': 12,
      'has_update': false,
      'force_update': false,
      'is_mandatory': false,
      'min_supported_version': '2.8.0',
      'checksum_sha256': 'A' * 64,
      'download_url': 'https://example.com/shiei.apk',
    });

    expect(enforcedByMinVersion.checksumSha256, equals('a' * 64));
    expect(AppUpdateService.instance.isForceUpdateRequired(enforcedByMinVersion), isTrue);

    final sameVersionForced = AppUpdateInfo.fromJson({
      'client_version': '2.7.0',
      'latest_version': '2.7.0',
      'latest_build': 9,
      'has_update': true,
      'force_update': true,
      'is_mandatory': true,
      'min_supported_version': '2.4.0',
      'download_url': 'https://example.com/shiei.apk',
    });
    expect(AppUpdateService.instance.isForceUpdateRequired(sameVersionForced), isFalse);
    final normalizedSame = AppUpdateService.instance.normalizeUpdatePolicy(sameVersionForced);
    expect(normalizedSame.hasUpdate, isFalse);
    expect(normalizedSame.forceUpdate, isFalse);

    final optionalUpdate = AppUpdateInfo(
      clientVersion: '2.7.0',
      latestVersion: '2.7.1',
      latestBuild: 10,
      hasUpdate: true,
      forceUpdate: false,
      isMandatory: false,
      minSupportedVersion: '2.4.0',
      releaseDate: '17 November 2026',
      releaseTitle: 'Optional Patch',
      fileSize: '86.7 MB',
      downloadUrl: 'https://example.com/shiei.apk',
      highlights: const [],
    );

    expect(AppUpdateService.instance.isForceUpdateRequired(optionalUpdate), isFalse);
  });

  testWidgets('ChangelogScreen renders in dark theme', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: ChangelogScreen(
          initialChangelogs: AppUpdateService.fallbackChangelogs,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Catatan Rilis & Pembaruan'), findsOneWidget);
    expect(find.text('Versi Aplikasi Terpasang'), findsOneWidget);
    expect(find.text('Daftar Riwayat Rilis'), findsOneWidget);
  });

  testWidgets('ChangelogScreen renders in light theme', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: ChangelogScreen(
          initialChangelogs: AppUpdateService.fallbackChangelogs,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Catatan Rilis & Pembaruan'), findsOneWidget);
    expect(find.text('Versi Aplikasi Terpasang'), findsOneWidget);
    expect(find.text('Daftar Riwayat Rilis'), findsOneWidget);
  });

  test('parseExpectedSizeBytes and isDiskFullError handle size labels and ENOSPC', () {
    expect(AppUpdateService.parseExpectedSizeBytes('85.7 MB'), (85.7 * 1024 * 1024).round());
    expect(AppUpdateService.parseExpectedSizeBytes('1,5 GB'), (1.5 * 1024 * 1024 * 1024).round());
    expect(AppUpdateService.parseExpectedSizeBytes('512 KB'), 512 * 1024);
    expect(AppUpdateService.parseExpectedSizeBytes('invalid'), isNull);

    expect(
      AppUpdateService.isDiskFullError(
        const FileSystemException('Write failed', '/tmp/a.apk', OSError('No space left on device', 28)),
      ),
      isTrue,
    );
    expect(AppUpdateService.isDiskFullError(Exception('Network timeout')), isFalse);
  });

  test('downloadApk aborts cleanly with clear message when available storage is insufficient', () async {
    final tmpDir = Directory.systemTemp.createTempSync('shiei_storage_test_');
    addTearDown(() {
      if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
    });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      log.add(methodCall);
      if (methodCall.method == 'getAppCacheDir') return tmpDir.path;
      if (methodCall.method == 'getAvailableStorageBytes') return 50 * 1024 * 1024; // 50 MB free
      return null;
    });

    final result = await AppUpdateService.instance.downloadApk(
      'https://github.com/bimbap/shiei-exam-mobile-app/releases/download/v2.6.2/test.apk',
      expectedSha256: 'a' * 64,
      expectedSizeHint: '85.7 MB',
      onProgress: (_, __) {},
    );

    expect(result, isNull);
    expect(AppUpdateService.instance.lastDownloadError, contains('Memori HP tidak cukup'));
    expect(AppUpdateService.instance.lastDownloadError, contains('Tersedia 50 MB'));
  });

  test('checkStorageForInstall blocks install when free headroom is below 1.25x APK size', () async {
    final tmpDir = Directory.systemTemp.createTempSync('shiei_install_space_');
    addTearDown(() {
      if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
    });
    final fakeApk = File('${tmpDir.path}/sample.apk')
      ..writeAsBytesSync(List<int>.filled(4 * 1024 * 1024, 0));

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      if (methodCall.method == 'getAvailableStorageBytes') return 4 * 1024 * 1024; // Only 4 MB free for 4 MB APK
      return null;
    });
    expect(await AppUpdateService.instance.checkStorageForInstall(fakeApk.path), contains('Memori HP terlalu penuh'));

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      if (methodCall.method == 'getAvailableStorageBytes') return 10 * 1024 * 1024; // 10 MB free (>= 5 MB needed)
      return null;
    });
    expect(await AppUpdateService.instance.checkStorageForInstall(fakeApk.path), isNull);
  });
}
