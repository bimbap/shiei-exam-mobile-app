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
    expect(changelogs.first.version, equals('2.5.0'));
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
      'client_version': '2.5.0',
      'latest_version': '2.5.1',
      'latest_build': 12,
      'has_update': false,
      'force_update': false,
      'is_mandatory': false,
      'min_supported_version': '2.5.1',
      'checksum_sha256': 'A' * 64,
      'download_url': 'https://example.com/shiei.apk',
    });

    expect(enforcedByMinVersion.checksumSha256, equals('a' * 64));
    expect(AppUpdateService.instance.isForceUpdateRequired(enforcedByMinVersion), isTrue);

    final optionalUpdate = AppUpdateInfo(
      clientVersion: '2.5.0',
      latestVersion: '2.5.1',
      latestBuild: 12,
      hasUpdate: true,
      forceUpdate: false,
      isMandatory: false,
      minSupportedVersion: '2.4.0',
      releaseDate: '12 November 2026',
      releaseTitle: 'Optional Patch',
      fileSize: '25 MB',
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
}
