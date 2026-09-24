import 'package:flutter/material.dart';
import '../../config/routes.dart';
import '../../core/auth/token_storage.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/app_exit_dialog.dart';
import '../../shared/widgets/fluid_curved_bottom_bar.dart';
import '../../shared/widgets/shiei_brand_logo.dart';
import '../tour/proctor_tour_dialog.dart';
import 'tabs/dashboard_tab.dart';
import 'tabs/exams_monitor_tab.dart';
import 'tabs/proctor_profile_tab.dart';
import 'tabs/school_data_tab.dart';
import 'teacher_portal_controller.dart';

class MonitorScreen extends StatefulWidget {
  const MonitorScreen({super.key});

  @override
  State<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends State<MonitorScreen> with WidgetsBindingObserver {
  final TeacherPortalController _controller = TeacherPortalController();
  late final ProctorTourTargetKeys _tourKeys = ProctorTourTargetKeys();
  final GlobalKey<ExamsMonitorTabState> _examsMonitorKey = GlobalKey<ExamsMonitorTabState>();
  final GlobalKey<SchoolDataTabState> _schoolDataKey = GlobalKey<SchoolDataTabState>();
  int _currentTabIndex = 0;
  String? _pendingStatusFilter;
  int _navigationTrigger = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppExitDialog.resetLock();
    _controller.init();
    _controller.addListener(_onControllerUpdate);

    // Auto-launch proctor tour on first entrance after initial render
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final completed = await TokenStorage.isProctorTourCompleted(isAdmin: _controller.isAdmin);
      if (!completed && mounted) {
        _openTour(forceShow: false);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _controller.pausePolling();
    } else if (state == AppLifecycleState.resumed) {
      _controller.resumePolling();
    }
  }

  @override
  void reassemble() {
    super.reassemble();
    _controller.resumePolling();
  }

  void _onControllerUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onControllerUpdate);
    _controller.dispose();
    super.dispose();
  }

  void _handleNavigateTab(int targetTab, {String? statusFilter, String? dataCategory}) {
    setState(() {
      _currentTabIndex = targetTab;
      _pendingStatusFilter = statusFilter;
      _navigationTrigger++;
    });
    if (targetTab == 1 && statusFilter != null) {
      _controller.setMonitorFilter(statusFilter == 'all' ? null : statusFilter);
    }
    if (targetTab == 2 && dataCategory != null) {
      _controller.setDataCategory(dataCategory);
    }
  }

  void _openTour({bool forceShow = true}) {
    _controller.setTourActive(true);
    ProctorTourDialog.show(
      context,
      targetKeys: _tourKeys,
      controller: _controller,
      forceShow: forceShow,
      isAdmin: _controller.isAdmin,
      onComplete: () {
        _controller.setTourActive(false);
      },
      onSwitchTab: (index, {statusFilter, dataCategory}) {
        if (mounted) {
          _handleNavigateTab(index, statusFilter: statusFilter, dataCategory: dataCategory);
        }
      },
    );
  }

  Widget _buildAppBarTitle(bool isDark) {
    switch (_currentTabIndex) {
      case 0:
        return const ShieiBrandLogo(logoSize: 26, fontSize: 17);
      case 1:
        return const Text(
          'Ujian & Live Monitor',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        );
      case 2:
        return const Text(
          'Data Sekolah',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        );
      case 3:
      default:
        return const Text(
          'Profil Pengawas',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        );
    }
  }

  void _confirmLogout() {
    final isDark = AppTheme.isDark(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppTheme.surfaceDark : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
        ),
        title: const Text(
          'Keluar dari Portal?',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: Text(
          'Apakah Anda yakin ingin keluar dari sesi pengawas ujian sekolah?',
          style: TextStyle(
            fontSize: 12.5,
            color: isDark ? AppTheme.textSecondary : const Color(0xFF475569),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Batal',
              style: TextStyle(color: isDark ? AppTheme.textSecondary : const Color(0xFF64748B)),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await _controller.logout();
              if (mounted) {
                Navigator.of(context).pushReplacementNamed(AppRoutes.login);
              }
            },
            child: const Text('Keluar Akun'),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildAppBarActions() {
    return [
      IconButton(
        icon: const Icon(Icons.refresh_rounded),
        tooltip: 'Muat Ulang',
        onPressed: () {
          if (_currentTabIndex == 0) {
            _controller.refreshDashboard(clearPrevious: true);
          } else if (_currentTabIndex == 1) {
            _controller.loadMonitoringData(clearPrevious: true);
            _controller.loadExams(clearPrevious: true);
          } else if (_currentTabIndex == 2) {
            _controller.loadStudents(clearPrevious: true);
            _controller.loadTeachers(clearPrevious: true);
            if (_controller.isAdmin) {
              _controller.loadAllUsers(clearPrevious: true);
            }
            _controller.loadClasses(clearPrevious: true);
          } else if (_currentTabIndex == 3) {
            _controller.refreshProfile(clearPrevious: true);
          }
        },
      ),
      // Settings button at top-right (matching student layout)
      IconButton(
        icon: const Icon(Icons.settings_outlined),
        tooltip: 'Pengaturan Kiosk',
        onPressed: () => Navigator.of(context).pushNamed(AppRoutes.settings),
      ),
      // Alternative logout button at top-right navbar when on profile tab (matching student layout)
      if (_currentTabIndex == 3)
        IconButton(
          icon: const Icon(Icons.logout_rounded, color: AppTheme.dangerRed),
          tooltip: 'Keluar Akun',
          onPressed: _confirmLogout,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);


    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;

        // Layer 1: Check if Navigator has any open modal sheets, dialogs, or pushed screens
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
          return;
        }

        // Layer 2: In-Tab state revert (Search, Filters, Selection, SpeedDial)
        if (_currentTabIndex == 2) {
          final handled = _schoolDataKey.currentState?.handleBackNavigation() ?? false;
          if (handled) return;
        } else if (_currentTabIndex == 1) {
          final handled = _examsMonitorKey.currentState?.handleBackNavigation() ?? false;
          if (handled) return;
        }

        // Layer 3: Bottom Navigation Bar Root (Any tab: Dashboard, Ujian, Data, Profil)
        // Prompt exit confirmation dialog directly without forcing return to Dashboard
        await AppExitDialog.show(context);
      },
      child: Scaffold(
        backgroundColor: AppTheme.background(context),
        appBar: AppBar(
          title: _buildAppBarTitle(isDark),
          actions: _buildAppBarActions(),
        ),
        body: IndexedStack(
          index: _currentTabIndex,
          children: [
            DashboardTab(
              controller: _controller,
              onNavigateTab: _handleNavigateTab,
              tourKeys: _tourKeys,
            ),
            ExamsMonitorTab(
              key: _examsMonitorKey,
              controller: _controller,
              initialStatusFilter: _pendingStatusFilter,
              navigationTrigger: _navigationTrigger,
              tourKeys: _tourKeys,
            ),
            SchoolDataTab(
              key: _schoolDataKey,
              controller: _controller,
              tourKeys: _tourKeys,
            ),
            ProctorProfileTab(
              controller: _controller,
              onLogout: _confirmLogout,
              tourKeys: _tourKeys,
              onOpenTour: () => _openTour(forceShow: true),
            ),
          ],
        ),
        bottomNavigationBar: FluidCurvedBottomBar(
          currentIndex: _currentTabIndex,
          backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
          activeColor: AppTheme.primaryGlow,
          inactiveColor: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
          borderColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
          items: const [
            FluidNavItem(
              icon: Icons.dashboard_rounded,
              activeIcon: Icons.dashboard_rounded,
              label: 'Dashboard',
            ),
            FluidNavItem(
              icon: Icons.assignment_rounded,
              activeIcon: Icons.assignment_rounded,
              label: 'Ujian',
            ),
            FluidNavItem(
              icon: Icons.school_rounded,
              activeIcon: Icons.school_rounded,
              label: 'Data',
            ),
            FluidNavItem(
              icon: Icons.person_rounded,
              activeIcon: Icons.person_rounded,
              label: 'Profil',
            ),
          ],
          onTap: (index) {
            setState(() {
              _currentTabIndex = index;
            });
            if (index == 0) {
              _controller.refreshDashboard(clearPrevious: false);
            } else if (index == 1) {
              _controller.loadExams();
              _controller.loadMonitoringData(silent: true);
            } else if (index == 2) {
              _controller.loadClasses();
              _controller.loadStudents();
              if (_controller.isAdmin) {
                _controller.loadAllUsers();
              } else {
                _controller.loadTeachers();
              }
            } else if (index == 3) {
              _controller.refreshProfile(clearPrevious: false);
            }
          },
        ),
      ),
    );
  }
}
