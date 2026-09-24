import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import '../../core/theme/theme_controller.dart';

/**
 * Project SHIEI (市衛) Mobile Design System.
 * Ultra-refined security kiosk aesthetic: Shiei Vermilion & Sunset Flame,
 * Deep OLED Obsidian canvas, machined double-bezel surfaces, and buttery-smooth 60fps transitions.
 */
class AppTheme {
  // Official Project SHIEI Brand Color Palette
  static const Color primaryShiei = Color(0xFFEA580C);   // Shiei Vermilion
  static const Color primaryGlow = Color(0xFFF97316);    // Sunset Flame Accent
  static const Color primaryDark = Color(0xFFC2410C);    // Deep Torii Crimson
  
  // Backward compatibility alias: Points to Shiei Vermilion
  static const Color primaryBlue = primaryShiei;
  static const Color primary = primaryShiei;

  // Obsidian & Slate Surface Tones (Zero Eye Strain & High Contrast)
  static const Color backgroundDark = Color(0xFF090D16); // OLED Obsidian Black Canvas
  static const Color surfaceDark = Color(0xFF111827);    // Machined Midnight Layer
  static const Color surfaceCard = Color(0xFF1E293B);    // Concentric Bezel Card
  static const Color surfaceElevated = Color(0xFF26354D);// Floating Focus Pill
  static const Color borderSubtle = Color(0xFF334155);   // 1px Hairline Border
  static const Color borderDark = borderSubtle;          // Backward compatibility alias
  static const Color borderFocused = Color(0xFFEA580C);  // Shiei Focus Halo

  // Light / White Mode Surface Tones
  static const Color backgroundLight = Color(0xFFF8FAFC); // Clean Slate-50 Canvas
  static const Color surfaceLight = Color(0xFFFFFFFF);    // Pure White Machined Card
  static const Color surfaceCardLight = Color(0xFFF1F5F9);// Slate-100 Inner Bezel
  static const Color surfaceElevatedLight = Color(0xFFE2E8F0); // Slate-200 Pill
  static const Color borderSubtleLight = Color(0xFFE2E8F0); // 1px Hairline Slate Border

  // Functional Status Colors
  static const Color accentGreen = Color(0xFF10B981);    // Secure / Normal
  static const Color accentYellow = Color(0xFFF59E0B);   // Attention / Battery Warning
  static const Color accentAmber = Color(0xFFD97706);    // Active Charging
  static const Color dangerRed = Color(0xFFEF4444);      // Violation / Lockdown
  static const Color dangerDark = Color(0xFF991B1B);     // Alert Background

  // Typography Tones - Dark Mode
  static const Color textPrimary = Color(0xFFF8FAFC);    // Pure High Contrast
  static const Color textSecondary = Color(0xFF94A3B8);  // Balanced Muted Gray
  static const Color textMuted = Color(0xFF64748B);      // Micro Footnotes

  // Typography Tones - Light Mode
  static const Color textPrimaryLight = Color(0xFF0F172A); // High Contrast Slate-900
  static const Color textSecondaryLight = Color(0xFF475569); // Slate-600 Muted
  static const Color textMutedLight = Color(0xFF94A3B8); // Slate-400 Footnotes

  // Context-aware dynamic color helpers
  static bool isDark(BuildContext context) => Theme.of(context).brightness == Brightness.dark;
  static Color background(BuildContext context) => isDark(context) ? backgroundDark : backgroundLight;
  static Color surface(BuildContext context) => isDark(context) ? surfaceDark : surfaceLight;
  static Color surfaceCardOf(BuildContext context) => isDark(context) ? surfaceCard : surfaceCardLight;
  static Color border(BuildContext context) => isDark(context) ? borderSubtle : borderSubtleLight;
  static Color text(BuildContext context) => isDark(context) ? textPrimary : textPrimaryLight;
  static Color textSecondaryOf(BuildContext context) => isDark(context) ? textSecondary : textSecondaryLight;

  /// Edge-to-edge transparent system UI overlay style matching modern Android & Google Files.
  /// Eliminates top & bottom black letterbox bars in Recent Apps / App Switcher.
  static SystemUiOverlayStyle systemOverlayStyleFor(bool isDark) {
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
      systemStatusBarContrastEnforced: false,
    );
  }

  static SystemUiOverlayStyle get systemOverlayStyle =>
      systemOverlayStyleFor(ThemeController.instance.themeMode == ThemeMode.dark ||
          (ThemeController.instance.themeMode == ThemeMode.system &&
              WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark));

  static void applySystemOverlayStyle({bool? isDark}) {
    final dark = isDark ?? (ThemeController.instance.themeMode == ThemeMode.dark ||
        (ThemeController.instance.themeMode == ThemeMode.system &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark));
    SystemChrome.setSystemUIOverlayStyle(systemOverlayStyleFor(dark));
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      primaryColor: primaryShiei,
      scaffoldBackgroundColor: backgroundDark,
      cardColor: surfaceDark,
      dividerColor: borderSubtle,
      dividerTheme: const DividerThemeData(
        color: Color(0xFF1E293B),
        thickness: 1,
        space: 1,
      ),
      tabBarTheme: const TabBarThemeData(
        dividerColor: Colors.transparent,
      ),
      focusColor: Colors.transparent,
      dialogTheme: const DialogThemeData(surfaceTintColor: Colors.transparent),
      bottomSheetTheme: const BottomSheetThemeData(surfaceTintColor: Colors.transparent),
      cardTheme: const CardThemeData(surfaceTintColor: Colors.transparent),
      popupMenuTheme: PopupMenuThemeData(
        color: surfaceDark,
        surfaceTintColor: Colors.transparent,
        position: PopupMenuPosition.under,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFF334155), width: 1),
        ),
      ),
      
      // Buttery-smooth page transitions across all platforms
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),

      colorScheme: const ColorScheme.dark(
        primary: primaryShiei,
        secondary: primaryGlow,
        surface: surfaceDark,
        error: dangerRed,
        onPrimary: Colors.white,
        onSurface: textPrimary,
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        systemOverlayStyle: systemOverlayStyleFor(true),
        titleTextStyle: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: textPrimary,
          letterSpacing: 0.3,
        ),
        iconTheme: const IconThemeData(color: textPrimary),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceDark,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: borderSubtle, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: borderSubtle, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: primaryShiei, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: dangerRed, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: dangerRed, width: 2),
        ),
        labelStyle: const TextStyle(color: textSecondary, fontSize: 13.5),
        hintStyle: const TextStyle(color: textMuted, fontSize: 13.5),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryShiei,
          foregroundColor: Colors.white,
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
          shadowColor: primaryShiei.withOpacity(0.35),
          textStyle: const TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF0F172A),
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF334155), width: 1.2),
        ),
        elevation: 8,
      ),
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: primaryShiei,
      scaffoldBackgroundColor: backgroundLight,
      cardColor: surfaceLight,
      dividerColor: borderSubtleLight,
      dividerTheme: const DividerThemeData(
        color: Color(0xFFE2E8F0),
        thickness: 1,
        space: 1,
      ),
      tabBarTheme: const TabBarThemeData(
        dividerColor: Colors.transparent,
      ),
      focusColor: Colors.transparent,
      dialogTheme: const DialogThemeData(surfaceTintColor: Colors.transparent),
      bottomSheetTheme: const BottomSheetThemeData(surfaceTintColor: Colors.transparent),
      cardTheme: const CardThemeData(surfaceTintColor: Colors.transparent),
      popupMenuTheme: PopupMenuThemeData(
        color: surfaceLight,
        surfaceTintColor: Colors.transparent,
        position: PopupMenuPosition.under,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
        ),
      ),

      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),

      colorScheme: const ColorScheme.light(
        primary: primaryShiei,
        secondary: primaryGlow,
        surface: surfaceLight,
        error: dangerRed,
        onPrimary: Colors.white,
        onSurface: textPrimaryLight,
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        systemOverlayStyle: systemOverlayStyleFor(false),
        titleTextStyle: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: textPrimaryLight,
          letterSpacing: 0.3,
        ),
        iconTheme: const IconThemeData(color: textPrimaryLight),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceLight,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: borderSubtleLight, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: borderSubtleLight, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: primaryShiei, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: dangerRed, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: dangerRed, width: 2),
        ),
        labelStyle: const TextStyle(color: textSecondaryLight, fontSize: 13.5),
        hintStyle: const TextStyle(color: textMutedLight, fontSize: 13.5),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryShiei,
          foregroundColor: Colors.white,
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
          shadowColor: primaryShiei.withOpacity(0.25),
          textStyle: const TextStyle(
            fontSize: 15.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF0F172A),
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF334155), width: 1.2),
        ),
        elevation: 8,
      ),
    );
  }
}
