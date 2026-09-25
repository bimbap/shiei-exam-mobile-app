import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/api/api_client.dart';
import '../../core/api/endpoints.dart';
import '../../core/auth/auth_service.dart';
import '../../core/auth/token_storage.dart';

class TeacherPortalController extends ChangeNotifier {
  final ApiClient _api = ApiClient();
  final AuthService _auth = AuthService();

  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _isDashboardLoading = false;
  bool _isMonitoringLoading = false;
  bool _isExamsLoading = false;
  bool _isStudentsLoading = false;
  bool _isTeachersLoading = false;
  bool _isUsersLoading = false;
  bool _isClassesLoading = false;
  bool _isProfileLoading = false;
  String? _errorMessage;

  Map<String, dynamic>? _currentUser;
  Map<String, dynamic>? _school;
  String? _userRole;

  // Monitoring data
  List<Map<String, dynamic>> _monitoringRecords = [];
  String? _monitorStatusFilter;
  String _monitorSearchQuery = '';
  int? _selectedExamId;

  // Exams data
  List<Map<String, dynamic>> _exams = [];

  // Classes, Students, Teachers & All Users data
  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _students = [];
  List<Map<String, dynamic>> _teachers = [];
  List<Map<String, dynamic>> _allUsers = [];

  int? _selectedClassId;
  String _studentSearchQuery = '';
  String _dataCategory = 'students'; // 'students', 'teachers', 'users', 'classes'
  String _teacherSubRoleFilter = 'all'; // 'all', 'kepala_sekolah', 'wakil_kepala_sekolah', 'guru', 'karyawan'
  String _userRoleFilter = 'all'; // 'all', 'school_admin', 'teacher', 'student'
  String _studentDeviceFilter = 'all'; // 'all', 'bound', 'unbound'
  String _dataSearchQuery = '';

  // Auto-refresh timer (default 5s for live exam monitoring)
  bool _autoRefresh = true;
  Timer? _pollingTimer;
  final ValueNotifier<int> syncCountdown = ValueNotifier<int>(5);
  bool _isBackgroundSyncing = false;

  // Polling, App Lifecycle & Connectivity state
  bool _isAppBackgrounded = false;
  DateTime? _lastSyncTime;
  bool _isConnectionLost = false;
  int _consecutivePollingErrors = 0;

  // Fraud Alert Audio & Haptics state
  bool _fraudAlertEnabled = true;
  bool _hasCompletedInitialLoad = false;
  Set<int> _knownBlockedStudentIds = {};
  Map<String, dynamic>? _latestFraudAlert;
  final List<Map<String, dynamic>> _activeFraudAlerts = [];
  AudioPlayer? _fraudAlertPlayer;
  Timer? _fraudSoundTimer;
  bool _isTourActive = false;

  // Getters
  bool get isTourActive => _isTourActive;
  bool get isLoading => _isLoading;
  bool get isRefreshing => _isRefreshing;
  bool get isDashboardLoading => _isDashboardLoading;
  bool get isMonitoringLoading => _isMonitoringLoading;
  bool get isExamsLoading => _isExamsLoading;
  bool get isStudentsLoading => _isStudentsLoading;
  bool get isTeachersLoading => _isTeachersLoading;
  bool get isUsersLoading => _isUsersLoading;
  bool get isClassesLoading => _isClassesLoading;
  bool get isProfileLoading => _isProfileLoading;
  bool get isAppBackgrounded => _isAppBackgrounded;
  DateTime? get lastSyncTime => _lastSyncTime;
  bool get isConnectionLost => _isConnectionLost;
  int get consecutivePollingErrors => _consecutivePollingErrors;

  String get lastSyncFormatted {
    if (_lastSyncTime == null) return '';
    final hour = _lastSyncTime!.hour.toString().padLeft(2, '0');
    final minute = _lastSyncTime!.minute.toString().padLeft(2, '0');
    final second = _lastSyncTime!.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second WIB';
  }

  String? get monitorFilter => _monitorStatusFilter;
  bool get fraudAlertEnabled => _fraudAlertEnabled;
  List<Map<String, dynamic>> get activeFraudAlerts => List.unmodifiable(_activeFraudAlerts);
  Map<String, dynamic>? get latestFraudAlert =>
      _activeFraudAlerts.isNotEmpty ? _activeFraudAlerts.first : _latestFraudAlert;
  String? get errorMessage => _errorMessage;
  Map<String, dynamic>? get currentUser => _currentUser;
  Map<String, dynamic>? get school => _school;
  String? get userRole => _userRole;
  bool get isTeacher => _userRole?.toLowerCase() == 'teacher';
  bool get isAdmin =>
      (_userRole?.toLowerCase() == 'school_admin' ||
       _userRole?.toLowerCase() == 'super_admin') &&
      !isTeacher;

  /// Checks if the current authenticated user has administrative or authorship rights
  /// to manage (edit, delete, toggle status, assign/remove proctors) the given exam.
  bool canManageExam(Map<String, dynamic>? exam) {
    if (exam == null) return false;
    if (isAdmin) return true;
    final currentId = _currentUser?['id']?.toString();
    final creatorId = (exam['created_by'] ?? exam['creator']?['id'] ?? exam['creator_id'])?.toString();
    if (currentId != null && creatorId != null && currentId == creatorId) {
      return true;
    }
    return false;
  }

  /// Checks if the current authenticated user can proctor or rotate token for this exam
  /// (School Admin, Super Admin, exam creator, or assigned proctor).
  bool canProctorExam(Map<String, dynamic>? exam, {List<Map<String, dynamic>>? proctors}) {
    if (exam == null) return false;
    if (canManageExam(exam)) return true;
    final currentId = _currentUser?['id']?.toString();
    if (currentId == null) return false;

    // Check provided proctors list
    if (proctors != null) {
      final isAssigned = proctors.any((p) {
        final uid = (p['user_id'] ?? p['id'] ?? p['user']?['id'])?.toString();
        return uid == currentId;
      });
      if (isAssigned) return true;
    }

    // Check embedded proctors inside exam map
    final rawProctors = exam['proctors'];
    if (rawProctors is List) {
      final isAssigned = rawProctors.any((p) {
        if (p is Map) {
          final uid = (p['user_id'] ?? p['id'] ?? p['user']?['id'])?.toString();
          return uid == currentId;
        }
        return p?.toString() == currentId;
      });
      if (isAssigned) return true;
    }

    return false;
  }

  /// Checks whether current authenticated user can unlock a student session for this exam
  /// (School Admin, Super Admin, exam creator, or assigned proctor).
  bool canUnlockStudentForExam(dynamic examId, {Map<String, dynamic>? exam}) {
    if (isAdmin) return true;
    final currentId = _currentUser?['id']?.toString();
    if (currentId == null) return false;

    final targetExam = (exam != null && exam.isNotEmpty)
        ? exam
        : _exams.firstWhere(
            (e) => e['id']?.toString() == examId?.toString(),
            orElse: () => <String, dynamic>{},
          );

    if (targetExam.isNotEmpty) {
      return canProctorExam(targetExam);
    }
    return false;
  }

  /// Checks whether the current user is assigned as a Wali Kelas (homeroom teacher)
  bool get isWaliKelas {
    if (!isTeacher) return false;
    final cmId = currentUser?['class_major_id'] ??
        currentUser?['class_id'] ??
        currentUser?['class_major']?['id'];
    return cmId != null;
  }

  /// Returns the class ID assigned to this Wali Kelas, if any
  int? get waliKelasId {
    final id = currentUser?['class_major_id'] ??
        currentUser?['class_id'] ??
        currentUser?['class_major']?['id'];
    return id != null ? int.tryParse(id.toString()) : null;
  }

  /// Returns the class name assigned to this Wali Kelas, if any
  String? get waliKelasName {
    final cm = currentUser?['class_major'];
    if (cm is Map && cm['name'] != null) return cm['name'].toString();
    final match = classes.firstWhere(
      (c) => c['id']?.toString() == waliKelasId?.toString(),
      orElse: () => <String, dynamic>{},
    );
    if (match.isNotEmpty && match['name'] != null) {
      return match['name'].toString();
    }
    return null;
  }

  /// Can the current user add a student (Admin can add to any class, Wali Kelas can add to their own class)
  bool get canAddStudent => isAdmin || isWaliKelas;

  /// Checks if the current authenticated user has permission to edit/delete a student.
  /// Admin can manage any student. Wali Kelas can manage students enrolled in their assigned class.
  bool canManageStudent(Map<String, dynamic>? student) {
    if (student == null) return false;
    if (isAdmin) return true;
    if (!isTeacher || !isWaliKelas) return false;

    final tClassId = waliKelasId?.toString();
    if (tClassId == null) return false;

    final sClassId = (student['class_major_id'] ??
            student['class_id'] ??
            student['class_major']?['id'] ??
            student['classes']?['id'])
        ?.toString();

    return tClassId == sClassId;
  }

  List<Map<String, dynamic>> get monitoringRecords => _monitoringRecords;
  String? get monitorStatusFilter => _monitorStatusFilter;
  String get monitorSearchQuery => _monitorSearchQuery;
  int? get selectedExamId => _selectedExamId;

  void setTourActive(bool active) {
    if (_isTourActive != active) {
      _isTourActive = active;
      if (!active) {
        stopFraudAlertSound();
      }
      notifyListeners();
    }
  }

  List<Map<String, dynamic>> get exams => _exams;
  List<Map<String, dynamic>> get activeExams {
    return _exams.where((e) {
      final status = e['status']?.toString().toLowerCase() ?? 'active';
      final isActive = e['is_active'] ?? (status == 'active');
      if (isActive == false || status == 'inactive') return false;

      final endTimeStr = e['end_time']?.toString();
      if (endTimeStr != null && endTimeStr.isNotEmpty) {
        final end = DateTime.tryParse(endTimeStr);
        if (end != null && DateTime.now().isAfter(end)) {
          return false;
        }
      }
      return true;
    }).toList();
  }
  List<Map<String, dynamic>> get classes => _classes;
  List<Map<String, dynamic>> get students => _students;
  List<Map<String, dynamic>> get teachers => _teachers;
  List<Map<String, dynamic>> get allUsers => _allUsers;

  int? get selectedClassId => _selectedClassId;
  String get studentSearchQuery => _studentSearchQuery;
  String get dataCategory => _dataCategory;
  String get teacherSubRoleFilter => _teacherSubRoleFilter;
  String get userRoleFilter => _userRoleFilter;
  String get studentDeviceFilter => _studentDeviceFilter;
  String get dataSearchQuery => _dataSearchQuery;
  bool get autoRefresh => _autoRefresh;

  // Multi-tier sorting: 1. start_time descending (terbaru), 2. created_at / id descending
  void _sortExamsList(List<Map<String, dynamic>> list) {
    list.sort((a, b) {
      final startA = DateTime.tryParse(a['start_time']?.toString() ?? '');
      final startB = DateTime.tryParse(b['start_time']?.toString() ?? '');
      if (startA != null && startB != null) {
        final comp = startB.compareTo(startA);
        if (comp != 0) return comp;
      } else if (startA != null) {
        return -1;
      } else if (startB != null) {
        return 1;
      }

      final createA = DateTime.tryParse(a['created_at']?.toString() ?? '');
      final createB = DateTime.tryParse(b['created_at']?.toString() ?? '');
      if (createA != null && createB != null) {
        final comp = createB.compareTo(createA);
        if (comp != 0) return comp;
      }

      final idA = int.tryParse(a['id']?.toString() ?? '') ?? 0;
      final idB = int.tryParse(b['id']?.toString() ?? '') ?? 0;
      return idB.compareTo(idA);
    });
  }

  // Safe data extraction helper handling raw arrays and Laravel pagination
  List<Map<String, dynamic>> _extractList(dynamic payload) {
    if (payload == null) return [];
    if (payload is List) {
      return payload
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    if (payload is Map) {
      if (payload['data'] != null) {
        return _extractList(payload['data']);
      }
    }
    return [];
  }

  // Computed KPI stats
  int get activeExamSessionsCount => _exams.where((e) {
        final status = e['status']?.toString();
        return status == 'active' || status == 'ongoing' || status == 'started';
      }).length;

  int get inProgressCount => _monitoringRecords.where((r) {
        final status = r['status']?.toString();
        return status == 'in_progress';
      }).length;

  int get lockedCount {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    final count = _monitoringRecords.where((r) {
      final status = r['status']?.toString();
      final isLocked = r['is_locked'] == true || status == 'locked';
      if (!isLocked) return false;
      if (status == 'terminated' || r['lock_reason'] == 'proctor_kick') return false;

      // Filter strictly to lockouts occurring within the last 7 days (matching school-panel)
      final dateStr = r['locked_at'] ?? r['updated_at'] ?? r['created_at'];
      if (dateStr != null) {
        final dt = DateTime.tryParse(dateStr.toString());
        if (dt != null && dt.isBefore(cutoff)) return false;
      }
      return true;
    }).length;

    // When onboarding tour is active, keep 1 as an educational example badge
    // so teachers/admins can clearly see how violation alerts look, rather than dropping to 0.
    if (_isTourActive && count == 0) {
      return 1;
    }
    return count;
  }

  /// Returns exams that currently have active ongoing sessions or are scheduled right now
  List<Map<String, dynamic>> get activeLiveExams {
    final activeExamIds = _monitoringRecords
        .where((r) {
          final status = r['status']?.toString();
          return status == 'in_progress' || r['is_locked'] == true;
        })
        .map((r) => r['link_id'] ?? r['link']?['id'])
        .whereType<dynamic>()
        .map((id) => id.toString())
        .toSet();

    final now = DateTime.now();

    return _exams.where((e) {
      final id = e['id']?.toString();
      final hasActiveStudents = id != null && activeExamIds.contains(id);

      final status = e['status']?.toString() ?? 'active';
      final isActive = e['is_active'] ?? (status == 'active');
      bool isScheduleOngoing = false;

      if (isActive && e['start_time'] != null && e['end_time'] != null) {
        try {
          final start = DateTime.parse(e['start_time'].toString()).toLocal();
          final end = DateTime.parse(e['end_time'].toString()).toLocal();
          if (now.isAfter(start) && now.isBefore(end)) {
            isScheduleOngoing = true;
          }
        } catch (_) {}
      }

      return hasActiveStudents || isScheduleOngoing;
    }).toList();
  }

  int get completedCount => _monitoringRecords.where((r) {
        final status = r['status']?.toString();
        return status == 'completed';
      }).length;

  int get totalMonitoringStudents => _monitoringRecords.length;

  // Filtered monitoring list
  List<Map<String, dynamic>> get filteredMonitoringRecords {
    return _monitoringRecords.where((r) {
      final user = r['user'] as Map<String, dynamic>? ?? {};
      final link = r['link'] as Map<String, dynamic>? ?? {};
      final status = r['status']?.toString() ?? 'pending';
      final isLocked = r['is_locked'] == true || status == 'locked';

      // Status filter
      if (_monitorStatusFilter != null) {
        if (_monitorStatusFilter == 'locked') {
          if (!isLocked && status != 'split_screen' && status != 'exited') return false;
        } else if (status != _monitorStatusFilter) {
          return false;
        }
      }

      // Exam filter
      if (_selectedExamId != null) {
        final linkId = r['link_id'] ?? link['id'];
        if (linkId?.toString() != _selectedExamId?.toString()) return false;
      }

      // Search query filter
      if (_monitorSearchQuery.isNotEmpty) {
        final name = (user['name'] ?? '').toString().toLowerCase();
        final username = (user['username'] ?? '').toString().toLowerCase();
        final nisn = (user['nisn'] ?? '').toString().toLowerCase();
        final title = (link['title'] ?? '').toString().toLowerCase();
        final q = _monitorSearchQuery.toLowerCase();
        if (!name.contains(q) && !username.contains(q) && !nisn.contains(q) && !title.contains(q)) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  // Filtered students list
  List<Map<String, dynamic>> get filteredStudents {
    final effectiveQuery = _dataSearchQuery.isNotEmpty ? _dataSearchQuery : _studentSearchQuery;
    return _students.where((s) {
      if (_selectedClassId != null) {
        final classId = s['class_major_id'] ?? s['class_id'] ?? s['class_major']?['id'] ?? s['classes']?['id'];
        if (classId?.toString() != _selectedClassId?.toString()) return false;
      }

      if (_studentDeviceFilter != 'all') {
        final deviceName = s['device_name']?.toString();
        final serial = s['serial_number']?.toString();
        final bool isBound = (deviceName != null && deviceName.isNotEmpty) || (serial != null && serial.isNotEmpty);
        if (_studentDeviceFilter == 'bound' && !isBound) return false;
        if (_studentDeviceFilter == 'unbound' && isBound) return false;
      }

      if (effectiveQuery.isNotEmpty) {
        final name = (s['name'] ?? '').toString().toLowerCase();
        final username = (s['username'] ?? '').toString().toLowerCase();
        final nisn = (s['nisn'] ?? '').toString().toLowerCase();
        final q = effectiveQuery.toLowerCase();
        if (!name.contains(q) && !username.contains(q) && !nisn.contains(q)) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  // Filtered teachers list
  List<Map<String, dynamic>> get filteredTeachers {
    final effectiveQuery = _dataSearchQuery.isNotEmpty ? _dataSearchQuery : _studentSearchQuery;
    return _teachers.where((t) {
      if (_teacherSubRoleFilter != 'all') {
        final subRole = (t['sub_role'] ?? 'none').toString().toLowerCase();
        if (_teacherSubRoleFilter == 'guru') {
          if (subRole != 'none' && subRole.isNotEmpty && subRole != 'guru') return false;
        } else if (subRole != _teacherSubRoleFilter.toLowerCase()) {
          return false;
        }
      }

      if (effectiveQuery.isNotEmpty) {
        final name = (t['name'] ?? '').toString().toLowerCase();
        final nip = (t['nip'] ?? '').toString().toLowerCase();
        final email = (t['email'] ?? '').toString().toLowerCase();
        final subRole = (t['sub_role'] ?? '').toString().toLowerCase();
        final q = effectiveQuery.toLowerCase();
        if (!name.contains(q) && !nip.contains(q) && !email.contains(q) && !subRole.contains(q)) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  // Filtered all users list
  List<Map<String, dynamic>> get filteredUsers {
    final effectiveQuery = _dataSearchQuery.isNotEmpty ? _dataSearchQuery : _studentSearchQuery;
    return _allUsers.where((u) {
      if (_userRoleFilter != 'all') {
        final role = u['role']?.toString().toLowerCase();
        if (role != _userRoleFilter.toLowerCase()) return false;
      }

      if (effectiveQuery.isNotEmpty) {
        final name = (u['name'] ?? '').toString().toLowerCase();
        final email = (u['email'] ?? '').toString().toLowerCase();
        final nip = (u['nip'] ?? '').toString().toLowerCase();
        final nisn = (u['nisn'] ?? '').toString().toLowerCase();
        final username = (u['username'] ?? '').toString().toLowerCase();
        final role = (u['role'] ?? '').toString().toLowerCase();
        final q = effectiveQuery.toLowerCase();
        if (!name.contains(q) && !email.contains(q) && !nip.contains(q) && !nisn.contains(q) && !username.contains(q) && !role.contains(q)) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  Future<void> init({bool clearPrevious = false}) async {
    _isLoading = true;
    _errorMessage = null;
    if (clearPrevious) {
      _monitoringRecords = [];
      _exams = [];
      _classes = [];
      _students = [];
      _teachers = [];
      _allUsers = [];
    }
    notifyListeners();

    try {
      _userRole = await TokenStorage.getRole();
      _currentUser = await TokenStorage.getUser();
      if ((_userRole == null || _userRole!.isEmpty) && _currentUser?['role'] != null) {
        _userRole = _currentUser!['role'].toString();
      }
      _fraudAlertEnabled = await TokenStorage.isFraudAlarmEnabled();

      final initialTasks = <Future>[
        _loadSchoolProfile(),
        _loadCurrentUserProfile(),
        loadMonitoringData(silent: true),
        loadExams(),
        loadClasses(),
        loadStudents(),
        loadTeachers(),
      ];
      if (isAdmin) {
        initialTasks.add(loadAllUsers());
      }
      await Future.wait(initialTasks);

      _isLoading = false;
      _startAutoRefreshTimer();
      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Refreshes dashboard statistics, school profile, and live session data.
  /// Shows DashboardSkeleton when clearPrevious is true.
  Future<void> refreshDashboard({bool clearPrevious = true}) async {
    if (clearPrevious) {
      _isDashboardLoading = true;
      notifyListeners();
    }
    try {
      await Future.wait([
        _loadSchoolProfile(),
        _loadCurrentUserProfile(),
        loadMonitoringData(silent: true),
        loadExams(),
        loadClasses(),
        loadStudents(),
      ]);
    } finally {
      if (clearPrevious) {
        _isDashboardLoading = false;
      }
      notifyListeners();
    }
  }

  Future<void> _loadSchoolProfile() async {
    try {
      final res = await _api.get(ApiEndpoints.schoolProfile);
      if (res.data != null && (res.data['status'] == 'success' || res.data['data'] != null)) {
        final raw = res.data['data'] ?? res.data['school'];
        if (raw is Map) {
          _school = Map<String, dynamic>.from(raw);
        }
      }
    } catch (_) {
      // Fallback to user's embedded school if available
      if (_currentUser?['school'] != null && _currentUser!['school'] is Map) {
        _school = Map<String, dynamic>.from(_currentUser!['school']);
      }
    }
  }

  Future<void> _loadCurrentUserProfile() async {
    try {
      final res = await _api.get(ApiEndpoints.me);
      if (res.data != null && (res.data['status'] == 'success' || res.data['data'] != null)) {
        final raw = res.data['data'];
        if (raw is Map) {
          _currentUser = Map<String, dynamic>.from(raw);
          if (_currentUser?['role'] != null) {
            final role = _currentUser!['role'].toString();
            if (role.isNotEmpty) _userRole = role;
          }
        }
      }
    } catch (_) {}
  }

  /// Reloads current user and school profiles (e.g. via pull-to-refresh on ProctorProfileTab)
  Future<void> refreshProfile({bool clearPrevious = false}) async {
    _isRefreshing = true;
    if (clearPrevious) {
      _isProfileLoading = true;
    }
    notifyListeners();
    try {
      await Future.wait([
        _loadSchoolProfile(),
        _loadCurrentUserProfile(),
      ]);
      if (_currentUser != null) {
        await TokenStorage.saveUser(_currentUser!);
      }
    } finally {
      _isRefreshing = false;
      _isProfileLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadMonitoringData({bool silent = false, bool clearPrevious = false}) async {
    if (!silent) {
      _isRefreshing = true;
      if (clearPrevious) {
        _isMonitoringLoading = true;
      }
      notifyListeners();
    }

    try {
      final query = <String, dynamic>{'per_page': 100};
      if (_monitorStatusFilter != null && _monitorStatusFilter != 'locked') {
        query['status'] = _monitorStatusFilter;
      }
      if (_selectedExamId != null) {
        query['link_id'] = _selectedExamId;
      }

      final res = await _api.get(ApiEndpoints.schoolMonitoring, queryParameters: query);
      if (res.data != null && (res.data['status'] == 'success' || res.data['data'] != null)) {
        final newRecords = _extractList(res.data['data']);
        _monitoringRecords = newRecords;
        _lastSyncTime = DateTime.now();
        _isConnectionLost = false;
        _consecutivePollingErrors = 0;
        try {
          _checkFraudViolations(newRecords);
        } catch (_) {}
      }
    } catch (_) {
      // Track consecutive polling errors to flag network disconnection
      _consecutivePollingErrors++;
      if (_consecutivePollingErrors >= 2) {
        _isConnectionLost = true;
      }
    } finally {
      _isRefreshing = false;
      _isMonitoringLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadExams({bool clearPrevious = false}) async {
    if (clearPrevious) {
      _isExamsLoading = true;
      notifyListeners();
    }
    try {
      final res = await _api.get(ApiEndpoints.schoolExams, queryParameters: {'per_page': 100});
      if (res.data != null && (res.data['status'] == 'success' || res.data['data'] != null)) {
        final list = _extractList(res.data['data']);
        _sortExamsList(list);
        _exams = list;
      }
    } catch (_) {} finally {
      _isExamsLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadClasses({bool clearPrevious = false}) async {
    if (clearPrevious) {
      _isClassesLoading = true;
      notifyListeners();
    }
    try {
      final res = await _api.get(ApiEndpoints.schoolClasses);
      if (res.data != null && (res.data['status'] == 'success' || res.data['data'] != null)) {
        _classes = _extractList(res.data['data']);
      }
    } catch (_) {} finally {
      _isClassesLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadStudents({bool clearPrevious = false}) async {
    if (clearPrevious) {
      _isStudentsLoading = true;
      notifyListeners();
    }
    try {
      final query = <String, dynamic>{
        'role': 'student',
        'all': true,
        'per_page': 200,
      };
      if (_selectedClassId != null) {
        query['class_major_id'] = _selectedClassId;
      }
      final res = await _api.get(ApiEndpoints.schoolStudents, queryParameters: query);
      if (res.data != null && (res.data['status'] == 'success' || res.data['data'] != null)) {
        _students = _extractList(res.data['data']);
      }
    } catch (_) {} finally {
      _isStudentsLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadTeachers({bool clearPrevious = false}) async {
    if (clearPrevious) {
      _isTeachersLoading = true;
      notifyListeners();
    }
    try {
      final res = await _api.get(
        ApiEndpoints.schoolTeachers,
        queryParameters: {'all': true, 'per_page': 200},
      );
      if (res.data != null && (res.data['status'] == 'success' || res.data['data'] != null)) {
        _teachers = _extractList(res.data['data']);
      }
    } catch (_) {} finally {
      _isTeachersLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadAllUsers({bool clearPrevious = false}) async {
    if (clearPrevious) {
      _isUsersLoading = true;
      notifyListeners();
    }
    try {
      final res = await _api.get(
        ApiEndpoints.schoolUsers,
        queryParameters: {'all': true, 'per_page': 200},
      );
      if (res.data != null && (res.data['status'] == 'success' || res.data['data'] != null)) {
        _allUsers = _extractList(res.data['data']);
      }
    } catch (_) {} finally {
      _isUsersLoading = false;
      notifyListeners();
    }
  }

  // --- ACTIONS ---

  /// Fetch all participant sessions for a specific exam (matches school-panel getLiveSessions)
  Future<List<Map<String, dynamic>>> loadExamParticipants(dynamic examId) async {
    if (examId == null) return [];
    try {
      final res = await _api.get(
        ApiEndpoints.schoolMonitoring,
        queryParameters: {'link_id': examId, 'per_page': 200},
      );
      if (res.data != null && (res.data['status'] == 'success' || res.data['data'] != null)) {
        final records = _extractList(res.data['data']);
        return records;
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Fetch all assigned proctors for a specific exam
  Future<List<Map<String, dynamic>>> loadExamProctors(dynamic examId) async {
    if (examId == null) return [];
    try {
      final res = await _api.get(ApiEndpoints.examProctors(examId));
      if (res.data != null && (res.data['status'] == 'success' || res.data['data'] != null)) {
        return _extractList(res.data['data']);
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Assign a teacher as proctor for a specific exam
  Future<bool> assignExamProctor(dynamic examId, int teacherId) async {
    if (examId == null) return false;
    try {
      final res = await _api.post(
        ApiEndpoints.examProctors(examId),
        data: {'user_id': teacherId},
      );
      if (res.data != null && (res.data['status'] == 'success' || res.statusCode == 200 || res.statusCode == 201)) {
        await loadExams();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Remove/unassign a teacher from proctoring an exam
  Future<bool> removeExamProctor(dynamic examId, int teacherId) async {
    if (examId == null) return false;
    try {
      final res = await _api.delete(ApiEndpoints.removeExamProctor(examId, teacherId));
      if (res.data != null && res.data['status'] == 'success') {
        await loadExams();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> unlockStudent(int linkId, int studentId) async {
    try {
      final res = await _api.post(ApiEndpoints.unlockExam(linkId, studentId));
      if (res.data != null && res.data['status'] == 'success') {
        await loadMonitoringData(silent: true);
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> addExtraTime(int linkId, int studentId, {int minutes = 15}) async {
    try {
      final res = await _api.post(
        ApiEndpoints.addExtraTime(linkId, studentId),
        data: {'minutes': minutes},
      );
      if (res.data != null && res.data['status'] == 'success') {
        await loadMonitoringData(silent: true);
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> kickStudent(int linkId, int studentId) async {
    try {
      final res = await _api.post(ApiEndpoints.kickStudent(linkId, studentId));
      if (res.data != null && res.data['status'] == 'success') {
        await loadMonitoringData(silent: true);
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> resetStudentDevice(int studentId) async {
    try {
      final res = await _api.put(
        ApiEndpoints.updateStudent(studentId),
        data: {
          'reset_device': true,
        },
      );
      if (res.data != null && res.data['status'] == 'success') {
        await loadStudents();
        await loadMonitoringData(silent: true);
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<String?> rotateToken(int examId) async {
    try {
      final res = await _api.post(ApiEndpoints.rotateExamToken(examId));
      if (res.data != null && res.data['status'] == 'success') {
        final data = res.data['data'];
        final newToken = (data is Map && data['token'] != null)
            ? data['token'].toString()
            : (res.data['token']?.toString());
        await loadExams();
        return newToken;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // --- ERROR LOCALIZATION HELPERS ---

  String _localizeError(dynamic error, String fallback) {
    if (error == null) return fallback;

    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map) {
        // Check errors map first (validation errors)
        final errorsMap = data['errors'];
        if (errorsMap is Map && errorsMap.isNotEmpty) {
          final firstKey = errorsMap.keys.first;
          final firstVal = errorsMap[firstKey];
          if (firstVal is List && firstVal.isNotEmpty) {
            return _translateServerMessage(firstVal.first.toString(), fallback: fallback);
          } else if (firstVal is String && firstVal.isNotEmpty) {
            return _translateServerMessage(firstVal, fallback: fallback);
          }
        }

        // Check message or error field
        final msg = data['message']?.toString() ?? data['error']?.toString();
        if (msg != null && msg.trim().isNotEmpty) {
          return _translateServerMessage(msg.trim(), fallback: fallback);
        }
      }

      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return 'Batas waktu koneksi habis (timeout). Periksa jaringan Anda.';
        case DioExceptionType.connectionError:
          return 'Gagal terhubung ke server ujian. Pastikan Wi-Fi atau jaringan aktif.';
        case DioExceptionType.badResponse:
          final code = error.response?.statusCode;
          if (code == 401) {
            return 'Sesi login telah berakhir. Silakan masuk kembali.';
          } else if (code == 403) {
            return 'Anda tidak memiliki hak akses untuk tindakan ini.';
          } else if (code == 404) {
            return 'Data target tidak ditemukan di server.';
          } else if (code == 422) {
            return 'Data formulir tidak valid atau belum lengkap.';
          } else if (code != null && code >= 500) {
            return 'Terjadi kendala pada server (Error $code). Silakan coba lagi.';
          }
          break;
        case DioExceptionType.cancel:
          return 'Permintaan dibatalkan.';
        default:
          break;
      }
    }

    return _translateServerMessage(error.toString(), fallback: fallback);
  }

  String _translateServerMessage(String msg, {required String fallback}) {
    final lower = msg.toLowerCase();
    if (lower.contains('unauthenticated') || lower.contains('unauthorized')) {
      return 'Sesi login telah berakhir. Silakan login ulang.';
    }
    if (lower.contains('forbidden') || lower.contains('not allowed') || lower.contains('this action is unauthorized')) {
      return 'Akses ditolak. Anda tidak memiliki wewenang untuk tindakan ini.';
    }
    if (lower.contains('not found') || lower.contains('modelnotfound')) {
      return 'Data target tidak ditemukan di sistem.';
    }
    if (lower.contains('token expired') || lower.contains('token has expired')) {
      return 'Sesi token kedaluwarsa. Silakan muat ulang data.';
    }
    if (lower.contains('connection refused') || lower.contains('failed host lookup')) {
      return 'Tidak dapat terhubung ke server. Periksa koneksi jaringan Anda.';
    }
    if (lower.contains('network is unreachable')) {
      return 'Jaringan tidak dapat dijangkau. Pastikan terhubung ke jaringan sekolah.';
    }
    if (lower.contains('timeout') || lower.contains('timed out')) {
      return 'Batas waktu koneksi habis. Silakan coba lagi.';
    }
    if (lower.contains('the given data was invalid') || lower.contains('validation failed')) {
      return 'Data yang dimasukkan tidak valid. Periksa isian formulir.';
    }
    if (lower.contains('already taken') || lower.contains('has already been taken')) {
      return 'Data tersebut sudah digunakan / terdaftar di sistem.';
    }
    if (lower.contains('student is not locked')) {
      return 'Siswa saat ini tidak dalam status terkunci.';
    }
    if (lower.contains('exam has ended') || lower.contains('exam is inactive')) {
      return 'Jadwal ujian sudah ditutup atau tidak aktif.';
    }
    if (lower.contains('proctor already assigned')) {
      return 'Guru pengawas sudah ditugaskan pada ujian ini.';
    }

    // If already clean text without Exception stack trace, return as is
    if (!lower.contains('exception') && !lower.contains('error:') && !lower.contains('dioexception') && !lower.contains('stack trace')) {
      return msg;
    }

    return fallback;
  }

  // --- EXAM CRUD ---

  Future<String?> createExam(Map<String, dynamic> payload) async {
    try {
      final res = await _api.post(ApiEndpoints.schoolExams, data: payload);
      if (res.data != null && (res.data['status'] == 'success' || res.statusCode == 201 || res.statusCode == 200)) {
        await loadExams();
        return null;
      }
      return _localizeError(res.data?['message'], 'Gagal membuat jadwal ujian.');
    } catch (e) {
      return _localizeError(e, 'Gagal membuat jadwal ujian.');
    }
  }

  Future<String?> updateExam(int id, Map<String, dynamic> payload) async {
    try {
      final res = await _api.put(ApiEndpoints.schoolExamDetail(id), data: payload);
      if (res.data != null && (res.data['status'] == 'success' || res.statusCode == 200)) {
        await loadExams();
        return null;
      }
      return _localizeError(res.data?['message'], 'Gagal memperbarui jadwal ujian.');
    } catch (e) {
      return _localizeError(e, 'Gagal memperbarui jadwal ujian.');
    }
  }

  Future<String?> deleteExam(int id) async {
    try {
      final res = await _api.delete(ApiEndpoints.schoolExamDetail(id));
      if (res.data != null && (res.data['status'] == 'success' || res.statusCode == 200)) {
        await loadExams();
        await loadMonitoringData(silent: true);
        return null;
      }
      return _localizeError(res.data?['message'], 'Gagal menghapus jadwal ujian.');
    } catch (e) {
      return _localizeError(e, 'Gagal menghapus jadwal ujian.');
    }
  }

  Future<String?> bulkDeleteExams(List<int> ids) async {
    try {
      final results = await Future.wait(
        ids.map((id) => _api.delete(ApiEndpoints.schoolExamDetail(id))),
      );
      final hasFailures = results.any(
        (res) => !(res.data != null && (res.data['status'] == 'success' || res.statusCode == 200)),
      );
      await loadExams();
      await loadMonitoringData(silent: true);
      if (hasFailures) {
        return 'Beberapa jadwal ujian tidak dapat dihapus.';
      }
      return null;
    } catch (e) {
      return _localizeError(e, 'Gagal menghapus jadwal ujian terpilih.');
    }
  }

  // --- CLASS CRUD ---

  Future<String?> createClass(String name, {int? teacherId}) async {
    try {
      final payload = <String, dynamic>{'name': name.trim()};
      if (teacherId != null && teacherId > 0) {
        payload['teacher_id'] = teacherId;
      }
      final res = await _api.post(ApiEndpoints.schoolClasses, data: payload);
      if (res.data != null && (res.data['status'] == 'success' || res.statusCode == 201 || res.statusCode == 200)) {
        await loadClasses();
        await loadTeachers();
        return null;
      }
      return _localizeError(res.data?['message'], 'Gagal membuat kelas.');
    } catch (e) {
      return _localizeError(e, 'Gagal membuat kelas.');
    }
  }

  Future<String?> updateClass(int id, String name, {int? teacherId, bool updateTeacher = false}) async {
    try {
      final payload = <String, dynamic>{'name': name.trim()};
      if (updateTeacher) {
        payload['teacher_id'] = (teacherId != null && teacherId > 0) ? teacherId : null;
      }
      final res = await _api.put(ApiEndpoints.schoolClassDetail(id), data: payload);
      if (res.data != null && (res.data['status'] == 'success' || res.statusCode == 200)) {
        await loadClasses();
        await loadTeachers();
        return null;
      }
      return _localizeError(res.data?['message'], 'Gagal memperbarui data kelas.');
    } catch (e) {
      return _localizeError(e, 'Gagal memperbarui data kelas.');
    }
  }

  /// Assign or unassign a teacher to a class as class advisor (Wali Kelas)
  Future<String?> assignClassTeacher(int classId, int? teacherId) async {
    try {
      final payload = <String, dynamic>{
        'teacher_id': (teacherId != null && teacherId > 0) ? teacherId : null,
      };
      final res = await _api.put(ApiEndpoints.schoolClassDetail(classId), data: payload);
      if (res.data != null && (res.data['status'] == 'success' || res.statusCode == 200)) {
        await loadClasses();
        await loadTeachers();
        return null;
      }
      return _localizeError(res.data?['message'], 'Gagal menghubungkan guru ke kelas.');
    } catch (e) {
      return _localizeError(e, 'Gagal menghubungkan guru ke kelas.');
    }
  }

  Future<String?> deleteClass(int id) async {
    try {
      final res = await _api.delete(ApiEndpoints.schoolClassDetail(id));
      if (res.data != null && (res.data['status'] == 'success' || res.statusCode == 200)) {
        await loadClasses();
        await loadStudents();
        return null;
      }
      return _localizeError(res.data?['message'], 'Gagal menghapus kelas.');
    } catch (e) {
      return _localizeError(e, 'Gagal menghapus kelas.');
    }
  }

  // --- USER CRUD ---

  Future<String?> createUser(Map<String, dynamic> payload) async {
    try {
      final res = await _api.post(ApiEndpoints.schoolUsers, data: payload);
      if (res.data != null && (res.data['status'] == 'success' || res.statusCode == 201 || res.statusCode == 200)) {
        await loadStudents();
        await loadTeachers();
        await loadAllUsers();
        return null;
      }
      return _localizeError(res.data?['message'], 'Gagal membuat akun pengguna.');
    } catch (e) {
      return _localizeError(e, 'Gagal membuat akun pengguna.');
    }
  }

  Future<String?> updateUser(int id, Map<String, dynamic> payload) async {
    try {
      final res = await _api.put(ApiEndpoints.schoolUserDetail(id), data: payload);
      if (res.data != null && (res.data['status'] == 'success' || res.statusCode == 200)) {
        await loadStudents();
        await loadTeachers();
        await loadAllUsers();
        return null;
      }
      return _localizeError(res.data?['message'], 'Gagal memperbarui data pengguna.');
    } catch (e) {
      return _localizeError(e, 'Gagal memperbarui data pengguna.');
    }
  }

  Future<String?> deleteUser(int id) async {
    try {
      final res = await _api.delete(ApiEndpoints.schoolUserDetail(id));
      if (res.data != null && (res.data['status'] == 'success' || res.statusCode == 200)) {
        await loadStudents();
        await loadTeachers();
        await loadAllUsers();
        return null;
      }
      return _localizeError(res.data?['message'], 'Gagal menghapus akun pengguna.');
    } catch (e) {
      return _localizeError(e, 'Gagal menghapus akun pengguna.');
    }
  }

  // --- STUDENT & MUTASI KELAS (ADMIN & WALI KELAS) ---

  Future<String?> createStudent(Map<String, dynamic> payload) async {
    try {
      final res = await _api.post(ApiEndpoints.schoolStudents, data: payload);
      if (res.data != null && (res.data['status'] == 'success' || res.statusCode == 201 || res.statusCode == 200)) {
        await loadStudents();
        await loadClasses();
        return null;
      }
      return _localizeError(res.data?['message'], 'Gagal menambahkan akun siswa.');
    } catch (e) {
      return _localizeError(e, 'Gagal menambahkan akun siswa.');
    }
  }

  Future<String?> updateStudentData(int id, Map<String, dynamic> payload) async {
    try {
      final res = await _api.put(ApiEndpoints.updateStudent(id), data: payload);
      if (res.data != null && (res.data['status'] == 'success' || res.statusCode == 200)) {
        await loadStudents();
        await loadClasses();
        return null;
      }
      return _localizeError(res.data?['message'], 'Gagal memperbarui data siswa.');
    } catch (e) {
      return _localizeError(e, 'Gagal memperbarui data siswa.');
    }
  }

  Future<String?> deleteStudent(int id) async {
    try {
      final res = await _api.delete(ApiEndpoints.updateStudent(id));
      if (res.data != null && (res.data['status'] == 'success' || res.statusCode == 200)) {
        await loadStudents();
        await loadClasses();
        return null;
      }
      return _localizeError(res.data?['message'], 'Gagal menghapus siswa.');
    } catch (e) {
      return _localizeError(e, 'Gagal menghapus siswa.');
    }
  }

  // --- BULK OPERATIONS (STUDENTS, TEACHERS, USERS) ---

  Future<String?> bulkDeleteStudents(List<int> ids) async {
    try {
      final res = await _api.post(
        ApiEndpoints.schoolStudentsBulkDelete,
        data: {'ids': ids},
      );
      if (res.data != null && (res.data['status'] == 'success' || res.statusCode == 200)) {
        await loadStudents();
        await loadClasses();
        if (isAdmin) await loadAllUsers();
        return null;
      }
      return _localizeError(res.data?['message'], 'Gagal menghapus siswa terpilih.');
    } catch (e) {
      return _localizeError(e, 'Gagal menghapus siswa terpilih.');
    }
  }

  Future<String?> bulkDeleteTeachers(List<int> ids) async {
    try {
      final res = await _api.post(
        ApiEndpoints.schoolTeachersBulkDelete,
        data: {'ids': ids},
      );
      if (res.data != null && (res.data['status'] == 'success' || res.statusCode == 200)) {
        await loadTeachers();
        if (isAdmin) await loadAllUsers();
        return null;
      }
      return _localizeError(res.data?['message'], 'Gagal menghapus guru/staf terpilih.');
    } catch (e) {
      return _localizeError(e, 'Gagal menghapus guru/staf terpilih.');
    }
  }

  Future<String?> bulkDeleteUsers(List<int> ids) async {
    try {
      final res = await _api.post(
        ApiEndpoints.schoolUsersBulkDelete,
        data: {'ids': ids},
      );
      if (res.data != null && (res.data['status'] == 'success' || res.statusCode == 200)) {
        await loadStudents();
        await loadTeachers();
        await loadAllUsers();
        return null;
      }
      return _localizeError(res.data?['message'], 'Gagal menghapus akun pengguna terpilih.');
    } catch (e) {
      return _localizeError(e, 'Gagal menghapus akun pengguna terpilih.');
    }
  }

  Future<String?> bulkStoreStudents(List<Map<String, dynamic>> students, {int? defaultClassId}) async {
    try {
      final res = await _api.post(
        ApiEndpoints.schoolStudentsBulk,
        data: {
          'students': students,
          if (defaultClassId != null) 'default_class_id': defaultClassId,
        },
      );
      if (res.data != null && (res.data['status'] == 'success' || res.statusCode == 200 || res.statusCode == 201)) {
        await loadStudents();
        await loadClasses();
        if (isAdmin) await loadAllUsers();
        return null;
      }
      return _localizeError(res.data?['message'], 'Gagal menambahkan data siswa massal.');
    } catch (e) {
      return _localizeError(e, 'Gagal menambahkan data siswa massal.');
    }
  }

  Future<String?> bulkStoreTeachers(List<Map<String, dynamic>> teachers, {String? defaultSubRole}) async {
    try {
      final res = await _api.post(
        ApiEndpoints.schoolTeachersBulk,
        data: {
          'teachers': teachers,
          if (defaultSubRole != null && defaultSubRole.isNotEmpty) 'default_sub_role': defaultSubRole,
        },
      );
      if (res.data != null && (res.data['status'] == 'success' || res.statusCode == 200 || res.statusCode == 201)) {
        await loadTeachers();
        if (isAdmin) await loadAllUsers();
        return null;
      }
      return _localizeError(res.data?['message'], 'Gagal menambahkan guru/staf massal.');
    } catch (e) {
      return _localizeError(e, 'Gagal menambahkan guru/staf massal.');
    }
  }

  Future<String?> bulkStoreUsers(List<Map<String, dynamic>> users) async {
    try {
      final res = await _api.post(
        ApiEndpoints.schoolUsersBulk,
        data: {'users': users},
      );
      if (res.data != null && (res.data['status'] == 'success' || res.statusCode == 200 || res.statusCode == 201)) {
        await loadStudents();
        await loadTeachers();
        await loadAllUsers();
        return null;
      }
      return _localizeError(res.data?['message'], 'Gagal menambahkan pengguna massal.');
    } catch (e) {
      return _localizeError(e, 'Gagal menambahkan pengguna massal.');
    }
  }

  Future<String?> transferStudentClass(int studentId, int targetClassId, {String? reason}) async {
    try {
      final res = await _api.post(
        ApiEndpoints.transferStudentClass(studentId),
        data: {
          'class_major_id': targetClassId,
          if (reason != null && reason.isNotEmpty) 'reason': reason,
        },
      );
      if (res.data != null && (res.data['status'] == 'success' || res.statusCode == 200)) {
        await loadStudents();
        await loadClasses();
        if (isAdmin) {
          await loadAllUsers();
        }
        return null;
      }
      return _localizeError(res.data?['message'], 'Gagal memutasi kelas siswa.');
    } catch (e) {
      return _localizeError(e, 'Gagal memutasi kelas siswa.');
    }
  }

  // --- ANNOUNCEMENT BROADCAST ---

  Future<List<Map<String, dynamic>>> getAnnouncements(int examId) async {
    try {
      final res = await _api.get(ApiEndpoints.schoolExamAnnouncements(examId));
      if (res.data != null && res.data['data'] is List) {
        return List<Map<String, dynamic>>.from(
          (res.data['data'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)),
        );
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<String?> sendAnnouncement(int examId, String message, {String type = 'warning'}) async {
    try {
      final res = await _api.post(
        ApiEndpoints.schoolExamAnnouncements(examId),
        data: {
          'message': message.trim(),
          'type': type,
        },
      );
      if (res.data != null && (res.data['status'] == 'success' || res.statusCode == 200 || res.statusCode == 201)) {
        return null;
      }
      return _localizeError(res.data?['message'], 'Gagal mengirim pengumuman.');
    } catch (e) {
      return _localizeError(e, 'Gagal mengirim pengumuman.');
    }
  }

  Future<String?> deleteAnnouncement(int examId, int announcementId) async {
    try {
      final res = await _api.delete(ApiEndpoints.schoolDeleteAnnouncement(examId, announcementId));
      if (res.data != null && (res.data['status'] == 'success' || res.statusCode == 200)) {
        return null;
      }
      return _localizeError(res.data?['message'], 'Gagal menghapus pengumuman.');
    } catch (e) {
      return _localizeError(e, 'Gagal menghapus pengumuman.');
    }
  }

  // --- FRAUD DETECTION & ALERTS ---

  void _checkFraudViolations(List<Map<String, dynamic>> records) {
    if (_isTourActive) return; // Prevent live polling alerts during onboarding tour
    final currentBlocked = <int>{};
    Map<String, dynamic>? newlyBlockedStudent;

    for (final r in records) {
      final status = (r['status'] ?? '').toString().toLowerCase();
      final isLocked = r['is_locked'] == true;
      if (status == 'blocked' || status == 'locked' || isLocked) {
        final studentId = r['user_id'] ?? r['student_id'] ?? r['user']?['id'] ?? r['id'];
        final intId = studentId is int ? studentId : int.tryParse(studentId.toString()) ?? 0;
        if (intId > 0) {
          currentBlocked.add(intId);
          if (!_knownBlockedStudentIds.contains(intId)) {
            newlyBlockedStudent = r;
            // Add to active alerts list, ensuring no duplicate entries
            _activeFraudAlerts.removeWhere((a) {
              final aId = a['user_id'] ?? a['student_id'] ?? a['user']?['id'] ?? a['id'];
              return aId.toString() == intId.toString();
            });
            _activeFraudAlerts.insert(0, r);
          }
        }
      }
    }

    // Only alert after initial fetch has set the baseline
    if (_hasCompletedInitialLoad && newlyBlockedStudent != null && _fraudAlertEnabled) {
      _latestFraudAlert = _activeFraudAlerts.isNotEmpty ? _activeFraudAlerts.first : newlyBlockedStudent;
      _triggerFraudAlert();
    }

    _knownBlockedStudentIds = currentBlocked;
    _hasCompletedInitialLoad = true;
  }

  void _triggerFraudAlert() {
    // 1. Triple Heavy Haptic Pulse
    try {
      HapticFeedback.heavyImpact();
      Future.delayed(const Duration(milliseconds: 200), () => HapticFeedback.heavyImpact());
      Future.delayed(const Duration(milliseconds: 400), () => HapticFeedback.heavyImpact());
    } catch (_) {}

    // 2. Short Security Siren Audio Alert
    _playFraudAlertSound();
  }

  Future<void> _playFraudAlertSound() async {
    try {
      _fraudAlertPlayer ??= AudioPlayer();
      _fraudSoundTimer?.cancel();
      await _fraudAlertPlayer!.stop();
      await _fraudAlertPlayer!.setVolume(0.85);
      await _fraudAlertPlayer!.play(AssetSource('audio/siren_alarm.mp3'));
      // Auto-stop siren pulse after 1.5 seconds so it serves as a chime alert
      _fraudSoundTimer = Timer(const Duration(milliseconds: 1500), () {
        _fraudAlertPlayer?.stop();
      });
    } catch (_) {
      try {
        SystemSound.play(SystemSoundType.alert);
      } catch (_) {}
    }
  }

  /// Plays a short siren chime & haptic demonstration for the onboarding tour on Step 3 (Langkah 3).
  Future<void> playTourFraudAudioDemo() async {
    try {
      HapticFeedback.heavyImpact();
      Future.delayed(const Duration(milliseconds: 180), () => HapticFeedback.heavyImpact());
    } catch (_) {}
    await _playFraudAlertSound();
  }

  /// Stops any playing fraud alert or tour siren sound immediately.
  void stopFraudAlertSound() {
    _fraudSoundTimer?.cancel();
    try {
      _fraudAlertPlayer?.stop();
    } catch (_) {}
  }

  Future<void> setFraudAlertSound(bool val) async {
    _fraudAlertEnabled = val;
    await TokenStorage.setFraudAlarmEnabled(val);
    notifyListeners();
  }

  Future<void> toggleFraudAlertSound() async {
    await setFraudAlertSound(!_fraudAlertEnabled);
  }

  Future<void> testFraudSound() async {
    _triggerFraudAlert();
  }

  void dismissFraudAlert(int index) {
    if (index >= 0 && index < _activeFraudAlerts.length) {
      _activeFraudAlerts.removeAt(index);
      if (_activeFraudAlerts.isEmpty) {
        _latestFraudAlert = null;
        stopFraudAlertSound();
      } else {
        _latestFraudAlert = _activeFraudAlerts.first;
      }
      notifyListeners();
    }
  }

  void removeFraudAlertForStudent(dynamic studentId) {
    if (studentId == null) return;
    _activeFraudAlerts.removeWhere((a) {
      final aId = a['user_id'] ?? a['student_id'] ?? a['user']?['id'] ?? a['id'];
      return aId.toString() == studentId.toString();
    });
    if (_activeFraudAlerts.isEmpty) {
      _latestFraudAlert = null;
      stopFraudAlertSound();
    } else {
      _latestFraudAlert = _activeFraudAlerts.first;
    }
    notifyListeners();
  }

  void clearFraudAlert() {
    _activeFraudAlerts.clear();
    _latestFraudAlert = null;
    stopFraudAlertSound();
    notifyListeners();
  }

  // --- FILTER CONTROLS ---

  void setMonitorFilter(String? filter) {
    _monitorStatusFilter = filter;
    notifyListeners();
    loadMonitoringData(silent: false);
  }

  void setMonitorSearch(String query) {
    _monitorSearchQuery = query.trim();
    notifyListeners();
  }

  void setSelectedExam(int? examId) {
    _selectedExamId = examId;
    notifyListeners();
    loadMonitoringData(silent: false);
  }

  void setSelectedClass(int? classId) {
    _selectedClassId = classId;
    notifyListeners();
    loadStudents();
  }

  void setStudentSearch(String query) {
    _studentSearchQuery = query.trim();
    _dataSearchQuery = _studentSearchQuery;
    notifyListeners();
  }

  void setDataCategory(String category) {
    _dataCategory = category;
    notifyListeners();
  }

  void setDataSearchQuery(String query) {
    _dataSearchQuery = query.trim();
    _studentSearchQuery = _dataSearchQuery;
    notifyListeners();
  }

  void setTeacherSubRoleFilter(String subRole) {
    _teacherSubRoleFilter = subRole;
    notifyListeners();
  }

  void setUserRoleFilter(String role) {
    _userRoleFilter = role;
    notifyListeners();
  }

  void setStudentDeviceFilter(String filter) {
    _studentDeviceFilter = filter;
    notifyListeners();
  }

  void _startAutoRefreshTimer() {
    _pollingTimer?.cancel();
    if (_autoRefresh && !_isAppBackgrounded) {
      _pollingTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
        if (!_autoRefresh || _isAppBackgrounded) return;

        if (syncCountdown.value > 1) {
          syncCountdown.value--;
        } else {
          syncCountdown.value = 5;
          if (!_isBackgroundSyncing) {
            _isBackgroundSyncing = true;
            try {
              await loadMonitoringData(silent: true);
            } finally {
              _isBackgroundSyncing = false;
            }
          }
        }
      });
    }
  }

  /// Pauses polling and audio alarms when app is sent to background / screen is locked
  void pausePolling() {
    _isAppBackgrounded = true;
    _pollingTimer?.cancel();
    _pollingTimer = null;
    stopFraudAlertSound();
    notifyListeners();
  }

  /// Resumes polling and fetches latest live session data when app returns to foreground
  void resumePolling() {
    _isAppBackgrounded = false;
    if (_autoRefresh) {
      _startAutoRefreshTimer();
    }
    notifyListeners();
  }

  void toggleAutoRefresh(bool val) {
    _autoRefresh = val;
    if (!val) {
      _pollingTimer?.cancel();
      _pollingTimer = null;
    } else {
      syncCountdown.value = 5;
      _startAutoRefreshTimer();
    }
    notifyListeners();
  }

  Future<void> logout() async {
    _pollingTimer?.cancel();
    await _auth.logout();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    syncCountdown.dispose();
    _fraudSoundTimer?.cancel();
    _fraudAlertPlayer?.dispose();
    super.dispose();
  }
}
