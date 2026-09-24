import 'package:flutter/material.dart';
import '../auth/token_storage.dart';

class ThemeController extends ChangeNotifier {
  static final ThemeController instance = ThemeController._internal();
  ThemeController._internal();

  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;

  /**
   * Initialize theme mode from persisted preferences.
   * Defaults to ThemeMode.system (auto-detect system brightness on first launch).
   */
  Future<void> init() async {
    final savedMode = await TokenStorage.getThemeMode();
    if (savedMode == 'light') {
      _themeMode = ThemeMode.light;
    } else if (savedMode == 'dark') {
      _themeMode = ThemeMode.dark;
    } else {
      _themeMode = ThemeMode.system;
    }
    notifyListeners();
  }

  /**
   * Update theme mode across the application and persist preference.
   * notifyListeners() is dispatched immediately before awaiting storage to eliminate UI lag.
   */
  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();

    // Persist to secure storage
    final modeStr = mode == ThemeMode.light
        ? 'light'
        : (mode == ThemeMode.dark ? 'dark' : 'system');
    await TokenStorage.saveThemeMode(modeStr);
  }

  /**
   * Determine whether dark mode is currently active given the current context.
   * Uses safe brightness resolution to avoid assertion crashes.
   */
  bool isDarkMode(BuildContext context) {
    if (_themeMode == ThemeMode.dark) return true;
    if (_themeMode == ThemeMode.light) return false;
    final brightness = MediaQuery.maybePlatformBrightnessOf(context) ??
        View.of(context).platformDispatcher.platformBrightness;
    return brightness == Brightness.dark;
  }
}
