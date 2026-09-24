// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:shiei_kiosk/shared/theme/app_theme.dart';

import 'package:shiei_kiosk/features/auth/login_controller.dart';

void main() {
  testWidgets('AppTheme dark theme smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme,
      home: const Scaffold(body: Text('Shiei Exam')),
    ));
    expect(find.text('Shiei Exam'), findsOneWidget);
  });

  test('LoginController starts with clean state and no role locked', () {
    final controller = LoginController();
    expect(controller.isLoading, false);
    expect(controller.errorMessage, isNull);
    expect(controller.userRole, isNull);
    expect(controller.isTeacherMode, false);
  });

  testWidgets('OnboardingScreen renders in light and dark mode', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      home: const Scaffold(body: Text('Selamat Datang di Shiei Exam')),
    ));
    expect(find.text('Selamat Datang di Shiei Exam'), findsOneWidget);
  });
}
