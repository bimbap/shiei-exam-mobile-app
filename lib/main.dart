import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'config/app_config.dart';
import 'config/routes.dart';
import 'core/api/api_client.dart';
import 'core/auth/token_storage.dart';
import 'core/lockdown/lockdown_service.dart';
import 'core/lockdown/volume_lock_service.dart';
import 'core/theme/theme_controller.dart';
import 'core/update/app_update_service.dart';
import 'features/auth/login_screen.dart';
import 'features/exam_list/exam_list_screen.dart';
import 'features/exam_player/exam_player_screen.dart';
import 'features/lockout/locked_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/teacher_monitor/monitor_screen.dart';
import 'features/update/changelog_screen.dart';
import 'shared/theme/app_theme.dart';
import 'shared/widgets/app_exit_dialog.dart';

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await initializeDateFormatting('id_ID', null);
  Intl.defaultLocale = 'id_ID';
  await AppConfig.init();
  await ThemeController.instance.init();

  // Handle single active session revocation globally
  ApiClient.onSessionTerminated = () {
    LockdownService().stopExamMonitoring();
    appNavigatorKey.currentState?.pushNamedAndRemoveUntil(
      AppRoutes.login,
      (route) => false,
    );
  };

  runApp(const ShieiExamApp());
}

class ShieiExamApp extends StatelessWidget {
  const ShieiExamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController.instance,
      builder: (context, _) {
        return MaterialApp(
          navigatorKey: appNavigatorKey,
          title: 'Shiei Exam',
          debugShowCheckedModeBanner: false,
          locale: const Locale('id', 'ID'),
          supportedLocales: const [
            Locale('id', 'ID'),
            Locale('en', 'US'),
          ],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeController.instance.themeMode,
          themeAnimationDuration: Duration.zero,
          initialRoute: AppRoutes.splash,
          builder: (context, child) {
            final isDark = ThemeController.instance.isDarkMode(context);
            AppTheme.applySystemOverlayStyle(isDark: isDark);
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: AppTheme.systemOverlayStyleFor(isDark),
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
                child: child ?? const SizedBox.shrink(),
              ),
            );
          },
          onGenerateRoute: (settings) {
            switch (settings.name) {
              case AppRoutes.splash:
                return MaterialPageRoute(builder: (_) => const SplashScreen());
              case AppRoutes.login:
                return MaterialPageRoute(builder: (_) => const LoginScreen());
              case AppRoutes.examList:
                return MaterialPageRoute(builder: (_) => const ExamListScreen());
              case AppRoutes.examPlayer:
                final args = settings.arguments as Map<String, dynamic>? ?? {};
                return MaterialPageRoute(
                  builder: (_) => ExamPlayerScreen(exam: args),
                );
              case AppRoutes.lockout:
                final args = settings.arguments as Map<String, dynamic>?;
                return MaterialPageRoute(
                  builder: (_) => LockedScreen(arguments: args),
                );
              case AppRoutes.teacherMonitor:
                return MaterialPageRoute(builder: (_) => const MonitorScreen());
              case AppRoutes.onboarding:
                return MaterialPageRoute(builder: (_) => const OnboardingScreen());
              case AppRoutes.settings:
                return MaterialPageRoute(builder: (_) => const SettingsScreen());
              case AppRoutes.changelog:
                return MaterialPageRoute(builder: (_) => const ChangelogScreen());
              default:
                return MaterialPageRoute(builder: (_) => const LoginScreen());
            }
          },
        );
      },
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    AppExitDialog.resetLock();
    _checkInitialAuth();
  }

  Future<void> _checkInitialAuth() async {
    // By default, allow screenshots across general screens (Home, Settings, History).
    // FLAG_SECURE is strictly toggled on when actively taking an exam.
    await VolumeLockService.setFlagSecure(false);

    await Future.delayed(const Duration(milliseconds: 600));

    // Detect if this launch is an app update
    final lastVersion = await TokenStorage.getLastAppVersion();
    const currentVersion = AppUpdateService.currentAppVersion;
    final isOnboarded = await TokenStorage.isOnboardingCompleted();
    final token = await TokenStorage.getToken();

    // App is considered an update if explicit version difference OR migration from older build
    final bool isAppUpdate = (lastVersion != null && lastVersion != currentVersion) ||
        (lastVersion == null && (isOnboarded || token != null));

    if (isAppUpdate) {
      await TokenStorage.setOnboardingCompleted(true);
      await TokenStorage.setFirstOpenDone();
      await TokenStorage.setLastAppVersion(currentVersion);
    }

    final bool shouldShowOnboarding = !isAppUpdate && !isOnboarded;
    if (shouldShowOnboarding) {
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(AppRoutes.onboarding);
      return;
    }

    final role = await TokenStorage.getRole();

    if (!mounted) return;

    final isExpired = await TokenStorage.isSessionExpired(maxDays: 3);
    if (isExpired) {
      await TokenStorage.clearToken();
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(AppRoutes.login);
      return;
    }

    if (!mounted) return;

    if (token != null && token.isNotEmpty) {
      if (role == 'teacher' || role == 'school_admin' || role == 'super_admin') {
        Navigator.of(context).pushReplacementNamed(AppRoutes.teacherMonitor);
      } else {
        Navigator.of(context).pushReplacementNamed(AppRoutes.examList);
      }
    } else {
      Navigator.of(context).pushReplacementNamed(AppRoutes.login);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await AppExitDialog.show(context);
      },
      child: Scaffold(
        backgroundColor: AppTheme.background(context),
        body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppTheme.primaryGlow.withValues(alpha: 0.28),
                    AppTheme.primaryDark.withValues(alpha: 0.12),
                  ],
                ),
                border: Border.all(
                  color: AppTheme.primaryShiei.withValues(alpha: 0.6),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryShiei.withValues(alpha: 0.25),
                    blurRadius: 32,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: ClipOval(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Image.asset(
                    'assets/images/shiei_logo.png',
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.shield_rounded,
                      size: 46,
                      color: AppTheme.primaryGlow,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              'SHIEI EXAM',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: AppTheme.text(context),
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Menjaga Integritas, Mengawal Kejujuran Ujian',
              style: TextStyle(fontSize: 12, color: AppTheme.primaryGlow),
            ),
            const SizedBox(height: 26),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.2, color: AppTheme.primaryGlow),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
