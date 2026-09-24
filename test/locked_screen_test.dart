import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shiei_kiosk/features/lockout/locked_screen.dart';
import 'package:shiei_kiosk/shared/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('LockedScreen renders without crashing in dark theme', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: const LockedScreen(
          arguments: {
            'exam_id': 1,
            'event_type': 'app_minimize',
            'details': 'Siswa meminimalkan aplikasi.',
          },
        ),
      ),
    );

    expect(find.text('UJIAN TERKUNCI!'), findsOneWidget);
    expect(find.text('Cek Status Buka Kunci dari Pengawas'), findsOneWidget);
    expect(find.text('Kembali ke Beranda Ujian'), findsOneWidget);
  });

  testWidgets('LockedScreen renders without crashing in light theme', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const LockedScreen(
          arguments: {
            'exam_id': 1,
            'event_type': 'tab_switch',
            'details': 'Aplikasi kehilangan fokus.',
          },
        ),
      ),
    );

    expect(find.text('UJIAN TERKUNCI!'), findsOneWidget);
    expect(find.text('Cek Status Buka Kunci dari Pengawas'), findsOneWidget);
    expect(find.text('Kembali ke Beranda Ujian'), findsOneWidget);
  });

  testWidgets('LockedScreen renders proctor_kick correctly', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: const LockedScreen(
          arguments: {
            'exam_id': 1,
            'event_type': 'proctor_kick',
            'details': 'Dikeluarkan oleh Pengawas Ujian karena membawa catatan.',
          },
        ),
      ),
    );

    expect(find.text('SESI UJIAN DIHENTIKAN'), findsOneWidget);
    expect(find.text('Dikeluarkan oleh Pengawas Ujian'), findsOneWidget);
    expect(find.text('Dikeluarkan oleh Pengawas Ujian karena membawa catatan.'), findsOneWidget);
  });
}

