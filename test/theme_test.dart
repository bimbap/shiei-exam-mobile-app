import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shiei_kiosk/core/auth/token_storage.dart';
import 'package:shiei_kiosk/core/theme/theme_controller.dart';
import 'package:shiei_kiosk/shared/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('ThemeController & TokenStorage Tests', () {
    test('Defaults to ThemeMode.system when no saved preference exists', () async {
      await ThemeController.instance.init();
      expect(ThemeController.instance.themeMode, equals(ThemeMode.system));
    });

    test('Loads saved ThemeMode.light correctly', () async {
      await TokenStorage.saveThemeMode('light');
      await ThemeController.instance.init();
      expect(ThemeController.instance.themeMode, equals(ThemeMode.light));
    });

    test('Loads saved ThemeMode.dark correctly', () async {
      await TokenStorage.saveThemeMode('dark');
      await ThemeController.instance.init();
      expect(ThemeController.instance.themeMode, equals(ThemeMode.dark));
    });

    test('setThemeMode updates controller and persists to storage', () async {
      await ThemeController.instance.init();
      
      await ThemeController.instance.setThemeMode(ThemeMode.light);
      expect(ThemeController.instance.themeMode, equals(ThemeMode.light));
      var saved = await TokenStorage.getThemeMode();
      expect(saved, equals('light'));

      await ThemeController.instance.setThemeMode(ThemeMode.dark);
      expect(ThemeController.instance.themeMode, equals(ThemeMode.dark));
      saved = await TokenStorage.getThemeMode();
      expect(saved, equals('dark'));

      await ThemeController.instance.setThemeMode(ThemeMode.system);
      expect(ThemeController.instance.themeMode, equals(ThemeMode.system));
      saved = await TokenStorage.getThemeMode();
      expect(saved, equals('system'));
    });
  });

  group('AppTheme Palette & ThemeData Tests', () {
    test('lightTheme has Brightness.light and correct base colors', () {
      final lightTheme = AppTheme.lightTheme;
      expect(lightTheme.brightness, equals(Brightness.light));
      expect(lightTheme.scaffoldBackgroundColor, equals(AppTheme.backgroundLight));
    });

    test('darkTheme has Brightness.dark and correct base colors', () {
      final darkTheme = AppTheme.darkTheme;
      expect(darkTheme.brightness, equals(Brightness.dark));
      expect(darkTheme.scaffoldBackgroundColor, equals(AppTheme.backgroundDark));
    });

    testWidgets('AppTheme context helpers react properly to widget brightness', (tester) async {
      late bool isDarkLightMode;
      late Color bgLightMode;
      late Color textLightMode;

      await tester.pumpWidget(
        Theme(
          data: AppTheme.lightTheme,
          child: Builder(
            builder: (context) {
              isDarkLightMode = AppTheme.isDark(context);
              bgLightMode = AppTheme.background(context);
              textLightMode = AppTheme.text(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(isDarkLightMode, isFalse);
      expect(bgLightMode, equals(AppTheme.backgroundLight));
      expect(textLightMode, equals(AppTheme.textPrimaryLight));

      late bool isDarkDarkMode;
      late Color bgDarkMode;
      late Color textDarkMode;

      await tester.pumpWidget(
        Theme(
          data: AppTheme.darkTheme,
          child: Builder(
            builder: (context) {
              isDarkDarkMode = AppTheme.isDark(context);
              bgDarkMode = AppTheme.background(context);
              textDarkMode = AppTheme.text(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(isDarkDarkMode, isTrue);
      expect(bgDarkMode, equals(AppTheme.backgroundDark));
      expect(textDarkMode, equals(AppTheme.textPrimary));
    });
  });
}
