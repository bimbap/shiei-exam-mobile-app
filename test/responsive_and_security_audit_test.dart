import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shiei_kiosk/config/app_config.dart';
import 'package:shiei_kiosk/core/auth/token_storage.dart';
import 'package:shiei_kiosk/features/auth/login_screen.dart';
import 'package:shiei_kiosk/features/exam_list/integrity_line_chart.dart';
import 'package:shiei_kiosk/features/exam_player/url_exam_player.dart';
import 'package:shiei_kiosk/features/exam_player/widgets/exam_announcement_banner.dart';
import 'package:shiei_kiosk/features/onboarding/onboarding_screen.dart';
import 'package:shiei_kiosk/features/settings/legal_document_screen.dart';
import 'package:shiei_kiosk/features/settings/settings_screen.dart';
import 'package:shiei_kiosk/features/settings/widgets/browser_account_picker_sheet.dart';
import 'package:shiei_kiosk/features/teacher_monitor/dialogs/class_form_dialog.dart';
import 'package:shiei_kiosk/features/teacher_monitor/dialogs/exam_form_dialog.dart';
import 'package:shiei_kiosk/features/teacher_monitor/dialogs/user_form_dialog.dart';
import 'package:shiei_kiosk/features/teacher_monitor/tabs/school_data_tab.dart';
import 'package:shiei_kiosk/features/teacher_monitor/teacher_portal_controller.dart';
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

  group('App-Wide Bug Fix Regressions', () {
    test(
      'TokenStorage clears stale browser email when switching/adding without email extraction',
      () async {
        await TokenStorage.saveBrowserLoginMeta(
          connected: true,
          email: 'old.account@gmail.com',
        );
        expect(
          (await TokenStorage.getBrowserLoginMeta())['email'],
          'old.account@gmail.com',
        );

        await TokenStorage.saveBrowserLoginMeta(
          connected: true,
          email: null,
          clearEmailIfMissing: true,
        );
        final updated = await TokenStorage.getBrowserLoginMeta();
        expect(updated['connected'], true);
        expect(updated['email'], isNull);
      },
    );

    testWidgets(
      'Non-admin teacher cannot multi-select Teacher cards in SchoolDataTab',
      (tester) async {
        final ctrl = _FakeTeacherPortalController(
          fakeRole: 'teacher',
          fakeCurrentUser: {
            'id': 99,
            'name': 'Pak Budi',
            'role': 'teacher',
            'class_major_id': 1,
          },
          fakeClasses: [
            {'id': 1, 'name': 'X RPL 1'},
            {'id': 2, 'name': 'X RPL 2'},
          ],
          fakeTeachers: [
            {
              'id': 50,
              'name': 'Bu Siti',
              'email': 'siti@sekolah.id',
              'role': 'teacher',
              'sub_role': 'guru',
            },
          ],
          fakeStudents: [
            {
              'id': 201,
              'name': 'Siswa Kelas Sendiri',
              'nisn': '11111',
              'role': 'student',
              'class_major_id': 1,
            },
            {
              'id': 202,
              'name': 'Siswa Kelas Lain',
              'nisn': '22222',
              'role': 'student',
              'class_major_id': 2,
            },
          ],
        );
        ctrl.setDataCategory('teachers');

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(body: SchoolDataTab(controller: ctrl)),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Bu Siti'), findsOneWidget);
        await tester.longPress(find.text('Bu Siti'));
        await tester.pumpAndSettle();
        expect(find.text('Pilih Semua'), findsNothing);

        await tester.tap(find.text('Siswa').first);
        await tester.pumpAndSettle();

        await tester.longPress(find.text('Siswa Kelas Lain'));
        await tester.pumpAndSettle();
        expect(find.text('Pilih Semua'), findsNothing);

        await tester.longPress(find.text('Siswa Kelas Sendiri'));
        await tester.pumpAndSettle();
        expect(find.text('Pilih Semua'), findsOneWidget);
        ctrl.dispose();
      },
    );

    testWidgets(
      'UserFormDialog disables Save in edit mode until fields actually change',
      (tester) async {
        final ctrl = _FakeTeacherPortalController(
          fakeRole: 'school_admin',
          fakeCurrentUser: {'id': 1, 'role': 'school_admin'},
          fakeClasses: const [
            {'id': 1, 'name': 'X RPL 1'},
          ],
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: UserFormDialog(
                controller: ctrl,
                userData: {
                  'id': 10,
                  'name': 'Ahmad Siswa',
                  'email': 'ahmad@sekolah.id',
                  'nisn': '0011223344',
                  'role': 'student',
                  'class_major_id': 1,
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final saveBtnFinder =
            find.widgetWithText(ElevatedButton, 'Simpan Perubahan');
        expect(saveBtnFinder, findsOneWidget);
        expect(tester.widget<ElevatedButton>(saveBtnFinder).onPressed, isNull);

        await tester.enterText(
          find.widgetWithText(TextFormField, 'Ahmad Siswa'),
          'Ahmad Updated',
        );
        await tester.pumpAndSettle();
        expect(
          tester.widget<ElevatedButton>(saveBtnFinder).onPressed,
          isNotNull,
        );

        await tester.enterText(
          find.widgetWithText(TextFormField, 'Ahmad Updated'),
          'Ahmad Siswa',
        );
        await tester.pumpAndSettle();
        expect(tester.widget<ElevatedButton>(saveBtnFinder).onPressed, isNull);
        ctrl.dispose();
      },
    );

    testWidgets(
      'ClassFormDialog disables Save in edit mode until fields change',
      (tester) async {
        final ctrl = _FakeTeacherPortalController(
          fakeRole: 'school_admin',
          fakeCurrentUser: {'id': 1, 'role': 'school_admin'},
          fakeClasses: const [
            {'id': 1, 'name': 'X RPL 1'},
          ],
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: ClassFormDialog(
                controller: ctrl,
                classData: {'id': 1, 'name': 'X RPL 1'},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final saveBtnFinder =
            find.widgetWithText(ElevatedButton, 'Simpan Perubahan');
        expect(saveBtnFinder, findsOneWidget);
        expect(tester.widget<ElevatedButton>(saveBtnFinder).onPressed, isNull);

        await tester.tap(find.text('XI'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<ElevatedButton>(saveBtnFinder).onPressed,
          isNotNull,
        );
        ctrl.dispose();
      },
    );

    testWidgets(
      'ExamFormDialog disables Save in edit mode until fields change',
      (tester) async {
        await initializeDateFormatting('id_ID');
        final ctrl = _FakeTeacherPortalController(
          fakeRole: 'school_admin',
          fakeCurrentUser: {'id': 1, 'role': 'school_admin'},
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: ExamFormDialog(
                controller: ctrl,
                exam: const {
                  'id': 77,
                  'title': 'UTS Matematika',
                  'subject': 'Matematika',
                  'url': 'https://docs.google.com/forms/d/test',
                  'token': 'ABC123',
                  'duration_minutes': 60,
                  'is_active': true,
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final saveBtnFinder =
            find.widgetWithText(ElevatedButton, 'Simpan Perubahan');
        expect(saveBtnFinder, findsOneWidget);
        expect(tester.widget<ElevatedButton>(saveBtnFinder).onPressed, isNull);

        await tester.enterText(
          find.widgetWithText(TextFormField, 'UTS Matematika'),
          'UTS Matematika Revisi',
        );
        await tester.pumpAndSettle();
        expect(
          tester.widget<ElevatedButton>(saveBtnFinder).onPressed,
          isNotNull,
        );
        ctrl.dispose();
      },
    );

    testWidgets(
      'SettingsScreen & LoginScreen server URL edit buttons stay disabled until modified',
      (tester) async {
        AppConfig.setCustomBaseUrl('https://shiei.example.com');

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: const SettingsScreen(),
          ),
        );
        await tester.pump(const Duration(milliseconds: 200));

        final settingsSaveFinder =
            find.widgetWithText(ElevatedButton, 'Simpan Pengaturan Server');
        await tester.ensureVisible(settingsSaveFinder);
        await tester.pumpAndSettle();
        expect(
          tester.widget<ElevatedButton>(settingsSaveFinder).onPressed,
          isNull,
        );

        await tester.enterText(
          find.widgetWithText(TextField, AppConfig.inputBaseUrl),
          'https://shiei-new.example.com',
        );
        await tester.pumpAndSettle();
        expect(
          tester.widget<ElevatedButton>(settingsSaveFinder).onPressed,
          isNotNull,
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: const LoginScreen(),
          ),
        );
        await tester.pump(const Duration(milliseconds: 200));

        await tester.tap(find.byTooltip('Pengaturan Server'));
        await tester.pumpAndSettle();

        final dialogSaveFinder = find.widgetWithText(ElevatedButton, 'Simpan');
        expect(dialogSaveFinder, findsOneWidget);
        expect(
          tester.widget<ElevatedButton>(dialogSaveFinder).onPressed,
          isNull,
        );

        await tester.enterText(
          find.widgetWithText(TextField, AppConfig.inputBaseUrl),
          'https://shiei-updated.example.com',
        );
        await tester.pumpAndSettle();
        expect(
          tester.widget<ElevatedButton>(dialogSaveFinder).onPressed,
          isNotNull,
        );
      },
    );
  });
}

class _FakeTeacherPortalController extends TeacherPortalController {
  final String fakeRole;
  final Map<String, dynamic> fakeCurrentUser;
  final List<Map<String, dynamic>> fakeClasses;
  final List<Map<String, dynamic>> fakeTeachers;
  final List<Map<String, dynamic>> fakeStudents;
  String _fakeCategory = 'students';

  _FakeTeacherPortalController({
    required this.fakeRole,
    required this.fakeCurrentUser,
    this.fakeClasses = const [],
    this.fakeTeachers = const [],
    this.fakeStudents = const [],
  });

  @override
  bool get isLoading => false;

  @override
  bool get isStudentsLoading => false;

  @override
  bool get isTeachersLoading => false;

  @override
  bool get isUsersLoading => false;

  @override
  bool get isClassesLoading => false;

  @override
  String? get userRole => fakeRole;

  @override
  bool get isTeacher => fakeRole.toLowerCase() == 'teacher';

  @override
  bool get isAdmin =>
      (fakeRole.toLowerCase() == 'school_admin' ||
          fakeRole.toLowerCase() == 'super_admin') &&
      !isTeacher;

  @override
  Map<String, dynamic>? get currentUser => fakeCurrentUser;

  @override
  List<Map<String, dynamic>> get classes => fakeClasses;

  @override
  List<Map<String, dynamic>> get teachers => fakeTeachers;

  @override
  List<Map<String, dynamic>> get students => fakeStudents;

  @override
  List<Map<String, dynamic>> get filteredTeachers => fakeTeachers;

  @override
  List<Map<String, dynamic>> get filteredStudents => fakeStudents;

  @override
  String get dataCategory => _fakeCategory;

  @override
  void setDataCategory(String category) {
    _fakeCategory = category;
    notifyListeners();
  }

  @override
  Future<void> loadClasses({bool clearPrevious = false}) async {}

  @override
  Future<void> loadStudents({bool clearPrevious = false}) async {}

  @override
  Future<void> loadTeachers({bool clearPrevious = false}) async {}

  @override
  Future<void> loadAllUsers({bool clearPrevious = false}) async {}

  @override
  Future<void> loadExams({bool clearPrevious = false}) async {}
}
