import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiei_kiosk/core/auth/token_storage.dart';
import 'package:shiei_kiosk/features/exam_list/integrity_line_chart.dart';
import 'package:shiei_kiosk/features/exam_player/url_exam_player.dart';
import 'package:shiei_kiosk/features/exam_player/widgets/exam_announcement_banner.dart';
import 'package:shiei_kiosk/features/onboarding/onboarding_screen.dart';
import 'package:shiei_kiosk/features/settings/legal_document_screen.dart';
import 'package:shiei_kiosk/features/settings/settings_screen.dart';
import 'package:shiei_kiosk/features/settings/widgets/browser_account_picker_sheet.dart';
import 'package:shiei_kiosk/shared/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const lockdownChannel = MethodChannel('id.shiei/lockdown');

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(lockdownChannel, (call) async {
      switch (call.method) {
        case 'getDeviceName':
          return 'Pixel 6a';
        case 'getDeviceId':
          return 'BLUEJAY';
        case 'getDeviceUniqueId':
          return 'TEST-HW-SERIAL-001';
        case 'setFlagSecure':
          return true;
        case 'hasGoogleAccountsPermission':
          return true;
        case 'requestGoogleAccountsPermission':
          return true;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(lockdownChannel, null);
  });

  group('Pentest & Privacy Verification', () {
    test('UrlExamPlayer blocks lookalikes, dangerous schemes, and public http', () {
      const examUrl = 'https://cbt.sekolah.sch.id/exam/1';
      expect(UrlExamPlayer.isUrlAllowed('javascript:alert(1)', examUrl), false);
      expect(UrlExamPlayer.isUrlAllowed('file:///etc/passwd', examUrl), false);
      expect(UrlExamPlayer.isUrlAllowed('intent://scan/#Intent;end', examUrl), false);
      expect(UrlExamPlayer.isUrlAllowed('https://docs.google.com.attacker.tld/form', examUrl), false);
      expect(UrlExamPlayer.isUrlAllowed('http://cbt.sekolah.sch.id/exam/1', examUrl), false);
      expect(UrlExamPlayer.isUrlAllowed('https://accounts.google.com/ServiceLogin', examUrl), true);
      expect(UrlExamPlayer.isUrlAllowed('http://192.168.1.50/exam', 'http://192.168.1.50/start'), true);
    });

    testWidgets('LegalDocumentScreen omits contact details cleanly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const LegalDocumentScreen(
            title: 'Kebijakan Privasi',
            subtitle: 'Test',
            effectiveLabel: '17 Nov 2026',
            sections: LegalDocumentScreen.privacySections,
            icon: Icons.privacy_tip_outlined,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('contact@hexadev.my.id'), findsNothing);
      expect(find.textContaining('Kontak Resmi'), findsNothing);
      expect(find.textContaining('Kontak Dukungan'), findsNothing);
    });
  });

  group('Responsiveness Audit (320px Narrow + 1.35x Scale & 840px Tablet)', () {
    testWidgets(
      'ExamAnnouncementBanner renders 2-line badges above sender cleanly at 320px & 1.35x text scale',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 568),
                textScaler: TextScaler.linear(1.35),
              ),
              child: Scaffold(
                body: ExamAnnouncementBanner(
                  announcement: const {
                    'id': 9,
                    'type': 'urgent',
                    'target_scope': 'selected',
                    'proctor': 'Drs. H. Ahmad Kurniawan Supardi, M.Pd.',
                    'message': 'Harap cek ulang nomor 12 sebelum waktu ujian habis.',
                  },
                  autoDismissDuration: Duration.zero,
                  onDismiss: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final badgeRect = tester.getRect(find.text('PERINGATAN MENDESAK'));
        final senderRect = tester.getRect(
          find.text('Drs. H. Ahmad Kurniawan Supardi, M.Pd.'),
        );
        expect(senderRect.top, greaterThanOrEqualTo(badgeRect.bottom));
      },
    );

    testWidgets(
      'IntegrityLineChart handles single point and 8 points with drag scrubbing without overflow',
      (tester) async {
        int picked = 0;
        final samplePoints = List.generate(
          8,
          (i) => IntegrityChartPoint(
            label: 'U${i + 1}',
            title: 'Ujian ${i + 1}',
            subject: 'MAT',
            statusText: i == 3 ? 'Selesai | 1 Peringatan' : 'Tertib | 0 Peringatan',
            durationSummary: i == 3 ? '1j 25m' : '48m',
            value: i == 3 ? 85.0 : 100.0,
            color: i == 3 ? const Color(0xFFF59E0B) : AppTheme.accentGreen,
            rawItem: const {},
          ),
        );

        for (final size in const [Size(320, 568), Size(840, 1100)]) {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1.0;

          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.darkTheme,
              home: Scaffold(
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: IntegrityLineChart(
                      points: samplePoints,
                      selectedIndex: picked,
                      isDark: true,
                      onSelectIndex: (idx) => picked = idx,
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.tapAt(tester.getCenter(find.byType(IntegrityLineChart)));
          await tester.pump();
          expect(picked, inInclusiveRange(0, samplePoints.length - 1));
        }

        // Single-point edge case
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: IntegrityLineChart(
                points: [samplePoints.first],
                selectedIndex: 0,
                isDark: false,
                onSelectIndex: (_) {},
              ),
            ),
          ),
        );
        await tester.pump();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      },
    );

    testWidgets(
      'SettingsScreen renders connected long portal domain cleanly at 320px & 1.3x text scale',
      (tester) async {
        await TokenStorage.setKeepBrowserLoginEnabled(true);
        await TokenStorage.saveBrowserLoginMeta(
          connected: true,
          label: 'portal-cbt-sman1kotabandung.sch.id',
          email: 'ibrahim.muliatama.panjang@student.sch.id',
          url: 'https://portal-cbt-sman1kotabandung.sch.id',
        );

        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: const MediaQuery(
              data: MediaQueryData(
                size: Size(320, 640),
                textScaler: TextScaler.linear(1.3),
              ),
              child: SettingsScreen(),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.textContaining('ibrahim.muliatama.panjang'), findsOneWidget);

        // Scroll through entire Settings list to verify lower sections (Hardware, Theme, About) never overflow
        await tester.scrollUntilVisible(
          find.text('Ketentuan Layanan (ToS)'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Ketentuan Layanan (ToS)'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('HexaDev'),
          250,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('HexaDev'), findsOneWidget);
      },
    );

    testWidgets(
      'SettingsScreen disconnect dialog stacks full-width aligned buttons and purges session cleanly',
      (tester) async {
        await TokenStorage.setKeepBrowserLoginEnabled(true);
        await TokenStorage.saveBrowserLoginMeta(
          connected: true,
          label: 'Akun Google',
          email: 'mi1122320@gmail.com',
          url: 'https://docs.google.com/forms',
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: const SettingsScreen(),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Putuskan'));
        await tester.pumpAndSettle();

        final purgeBtn = find.widgetWithText(ElevatedButton, 'Putuskan & Hapus Sesi');
        final softBtn = find.widgetWithText(OutlinedButton, 'Lepas Saja (Simpan Sesi)');
        final cancelBtn = find.widgetWithText(TextButton, 'Batal');
        expect(purgeBtn, findsOneWidget);
        expect(softBtn, findsOneWidget);
        expect(cancelBtn, findsOneWidget);

        final r1 = tester.getRect(purgeBtn);
        final r2 = tester.getRect(softBtn);
        final r3 = tester.getRect(cancelBtn);
        expect((r1.width - r2.width).abs(), lessThan(1.0));
        expect((r2.width - r3.width).abs(), lessThan(1.0));
        expect(r2.top, greaterThanOrEqualTo(r1.bottom));
        expect(r3.top, greaterThanOrEqualTo(r2.bottom));

        await tester.tap(purgeBtn);
        await tester.pumpAndSettle();

        expect(await TokenStorage.isKeepBrowserLoginEnabled(), false);
        expect((await TokenStorage.getBrowserLoginMeta())['connected'], false);
        expect(await TokenStorage.getSavedBrowserEmails(), isEmpty);
        expect(
          await TokenStorage.getHiddenDeviceGoogleEmails(),
          ['mi1122320@gmail.com'],
        );
      },
    );

    testWidgets(
      'OnboardingScreen renders cleanly without overflow on 320x568 short screen',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: const MediaQuery(
              data: MediaQueryData(
                size: Size(320, 568),
                textScaler: TextScaler.linear(1.25),
              ),
              child: OnboardingScreen(),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(PageView), findsOneWidget);
      },
    );

    test('TokenStorage manages saved and hidden browser emails consistently', () async {
      await TokenStorage.saveBrowserLoginMeta(
        connected: true,
        email: 'Budi@Gmail.com',
      );
      expect(await TokenStorage.getSavedBrowserEmails(), ['budi@gmail.com']);

      await TokenStorage.addSavedBrowserEmail('siti@gmail.com');
      expect(
        await TokenStorage.getSavedBrowserEmails(),
        ['siti@gmail.com', 'budi@gmail.com'],
      );

      await TokenStorage.removeSavedBrowserEmail('budi@gmail.com');
      await TokenStorage.hideDeviceGoogleEmail('budi@gmail.com');
      expect(await TokenStorage.getSavedBrowserEmails(), ['siti@gmail.com']);
      expect(await TokenStorage.getHiddenDeviceGoogleEmails(), ['budi@gmail.com']);

      // Re-connecting removes email from hidden list cleanly
      await TokenStorage.saveBrowserLoginMeta(
        connected: true,
        email: 'budi@gmail.com',
      );
      expect(await TokenStorage.getHiddenDeviceGoogleEmails(), isEmpty);
      expect(
        await TokenStorage.getSavedBrowserEmails(),
        ['budi@gmail.com', 'siti@gmail.com'],
      );
    });

    testWidgets(
      'BrowserAccountPickerSheet allows deleting saved accounts and returns add sentinel without OS dialog',
      (tester) async {
        await TokenStorage.addSavedBrowserEmail('siswa.one@gmail.com');
        await TokenStorage.saveBrowserLoginMeta(
          connected: true,
          email: 'siswa.two@gmail.com',
        );

        String? picked;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      picked = await BrowserAccountPickerSheet.pick(
                        context,
                        currentEmail: 'siswa.two@gmail.com',
                      );
                    },
                    child: const Text('Buka Picker'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Buka Picker'));
        await tester.pumpAndSettle();

        expect(find.text('siswa.one@gmail.com'), findsOneWidget);
        expect(find.text('siswa.two@gmail.com'), findsOneWidget);
        expect(find.text('Masuk dengan Akun Google Lain'), findsOneWidget);

        // Delete active/first account using delete button -> triggers confirmation alert
        await tester.tap(find.byIcon(Icons.delete_outline_rounded).first);
        await tester.pumpAndSettle();
        expect(find.text('Putuskan & Hapus Akun?'), findsOneWidget);
        await tester.tap(find.text('Ya, Putuskan'));
        await tester.pumpAndSettle();

        expect(find.text('siswa.two@gmail.com'), findsNothing);
        expect((await TokenStorage.getBrowserLoginMeta())['connected'], false);
        expect(
          await TokenStorage.getSavedBrowserEmails(),
          ['siswa.one@gmail.com'],
        );
        expect(
          await TokenStorage.getHiddenDeviceGoogleEmails(),
          ['siswa.two@gmail.com'],
        );

        // Tap "Masuk dengan Akun Google Lain"
        await tester.tap(find.text('Masuk dengan Akun Google Lain'));
        await tester.pumpAndSettle();
        expect(picked, BrowserAccountPickerSheet.addAccountSentinel);
      },
    );

    testWidgets(
      'OnboardingScreen forces Guest/Incognito default if keep=1 without connected account',
      (tester) async {
        await TokenStorage.setKeepBrowserLoginEnabled(true);
        expect(await TokenStorage.isKeepBrowserLoginEnabled(), true);

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: const OnboardingScreen(),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(await TokenStorage.isKeepBrowserLoginEnabled(), false);
      },
    );
  });
}
