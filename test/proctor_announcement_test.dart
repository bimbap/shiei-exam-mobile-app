import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiei_kiosk/features/exam_player/url_exam_player.dart';
import 'package:shiei_kiosk/features/exam_player/widgets/exam_announcement_banner.dart';
import 'package:shiei_kiosk/shared/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ExamAnnouncementBanner & Sheet Tests', () {
    testWidgets('renders announcement banner with warning type and triggers callbacks', (WidgetTester tester) async {
      bool dismissed = false;

      final announcement = {
        'id': 101,
        'message': 'Ralat Soal No. 14: Pilihan C diganti menjadi 42 cm',
        'type': 'warning',
        'proctor': 'Bapak Joko (Pengawas Ruang 02)',
        'created_at': '2026-09-13T10:00:00Z',
      };

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: ExamAnnouncementBanner(
            announcement: announcement,
            onDismiss: () => dismissed = true,
            onViewAll: () {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('PENGUMUMAN'), findsOneWidget);
      expect(find.text('Bapak Joko (Pengawas Ruang 02)'), findsOneWidget);
      expect(find.text('Ralat Soal No. 14: Pilihan C diganti menjadi 42 cm'), findsOneWidget);

      // Tap "Saya Mengerti"
      await tester.tap(find.text('Saya Mengerti'));
      await tester.pumpAndSettle();
      expect(dismissed, isTrue);
    });

    testWidgets('triggers onViewAll callback when Semua Ralat is tapped', (WidgetTester tester) async {
      bool viewedAll = false;
      final announcement = {
        'id': 101,
        'message': 'Ralat Soal No. 14: Pilihan C diganti menjadi 42 cm',
        'type': 'warning',
        'proctor': 'Bapak Joko (Pengawas Ruang 02)',
      };

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: ExamAnnouncementBanner(
            announcement: announcement,
            onDismiss: () {},
            onViewAll: () => viewedAll = true,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Tap "Semua Ralat"
      await tester.tap(find.text('Semua Ralat'));
      await tester.pumpAndSettle();
      expect(viewedAll, isTrue);
    });

    testWidgets('renders urgent and info type badges accurately', (WidgetTester tester) async {
      final urgentAnnouncement = {
        'id': 102,
        'message': 'Harap tenang, waktu tersisa 5 menit',
        'type': 'urgent',
        'proctor': 'Pengawas Utama',
      };

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: ExamAnnouncementBanner(
            announcement: urgentAnnouncement,
            onDismiss: () {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('PERINGATAN MENDESAK'), findsOneWidget);
      expect(find.text('KHUSUS ANDA'), findsNothing);
    });

    testWidgets('renders KHUSUS ANDA badge when target_scope is selected', (WidgetTester tester) async {
      final personalAnnouncement = {
        'id': 103,
        'message': 'Harap periksa kembali biodata NISN Anda.',
        'type': 'info',
        'target_scope': 'selected',
        'proctor': 'Pengawas Ruang 01',
      };

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: ExamAnnouncementBanner(
            announcement: personalAnnouncement,
            onDismiss: () {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('INFO PENGAWAS'), findsOneWidget);
      expect(find.text('KHUSUS ANDA'), findsOneWidget);
    });

    test('UrlExamPlayer exposes clean non-wv user agent and trusts accounts.google.com', () {
      expect(UrlExamPlayer.browserCompatibleUserAgent.contains('; wv)'), isFalse);
      expect(
        UrlExamPlayer.isUrlAllowed('https://accounts.google.com/ServiceLogin', 'https://docs.google.com/forms/d/1'),
        isTrue,
      );
    });
  });
}
