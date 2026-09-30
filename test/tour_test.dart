import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shiei_kiosk/features/tour/app_tour_dialog.dart';
import 'package:shiei_kiosk/shared/theme/app_theme.dart';

void main() {
  testWidgets('AppTourDialog renders welcome phase and advances through coachmark spotlight', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    bool tourCompleted = false;
    final switchedTabs = <int>[];

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: AppTourDialog(
            onTourCompleted: () {
              tourCompleted = true;
            },
            onSwitchTab: (tabIndex) {
              switchedTabs.add(tabIndex);
            },
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    // Phase 1: Welcome Bottom Card
    expect(find.text('Selamat Datang di Shiei Exam'), findsOneWidget);
    expect(find.text('Lewatkan'), findsOneWidget);
    expect(find.text('Mulai Tur Siswa'), findsOneWidget);

    // Tap "Mulai Tur Siswa" -> Enters Phase 2 (Coachmark Step 1)
    await tester.tap(find.text('Mulai Tur Siswa'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Langkah 1 dari 5'), findsOneWidget);
    expect(find.text('Identitas & Status Siswa'), findsOneWidget);
    expect(find.text('Lanjut'), findsOneWidget);
    expect(find.text('Lewati'), findsOneWidget);
    expect(switchedTabs, contains(0));

    // Tap Lanjut -> Step 2
    await tester.tap(find.text('Lanjut'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Langkah 2 dari 5'), findsOneWidget);
    expect(find.text('Pencarian Jadwal Ujian'), findsOneWidget);

    // Tap Lanjut -> Step 3
    await tester.tap(find.text('Lanjut'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Langkah 3 dari 5'), findsOneWidget);
    expect(find.text('Daftar Ujian Terjadwal'), findsOneWidget);

    // Tap Lanjut -> Step 4 (Switches to Tab 1)
    await tester.tap(find.text('Lanjut'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Langkah 4 dari 5'), findsOneWidget);
    expect(find.text('Riwayat Ujian & Hasil'), findsOneWidget);
    expect(switchedTabs, contains(1));

    // Tap Lanjut -> Step 5 (Switches to Tab 2)
    await tester.tap(find.text('Lanjut'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Langkah 5 dari 5'), findsOneWidget);
    expect(find.text('Kartu Digital & Mode Kiosk'), findsOneWidget);
    expect(find.text('Selesai'), findsOneWidget);
    expect(switchedTabs, contains(2));

    // Tap Selesai
    await tester.tap(find.text('Selesai'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tourCompleted, isTrue);
  });

  testWidgets('AppTourDialog skip button completes tour immediately', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    bool tourCompleted = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: AppTourDialog(
            onTourCompleted: () {
              tourCompleted = true;
            },
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Lewatkan'), findsOneWidget);
    await tester.tap(find.text('Lewatkan'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 350));
    expect(tourCompleted, isTrue);
  });

  test('TourTargetKeys creates unique GlobalKey instances without collisions', () {
    final keys1 = TourTargetKeys();
    final keys2 = TourTargetKeys();

    expect(keys1.studentCardKey, isNot(equals(keys2.studentCardKey)));
    expect(keys1.examSearchKey, isNot(equals(keys2.examSearchKey)));
  });
}
