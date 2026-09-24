import 'package:flutter/material.dart';
import '../../core/api/api_client.dart';
import '../../core/api/endpoints.dart';
import '../../core/auth/auth_service.dart';
import '../../core/auth/token_storage.dart';
import '../../core/notifications/exam_reminder_service.dart';

class ExamListController extends ChangeNotifier {
  final ApiClient _api = ApiClient();
  final AuthService _auth = AuthService();

  bool _isLoading = true;
  bool _isHistoryLoading = false;
  bool _isProfileLoading = false;
  bool _isHistoryManualRefreshing = false;
  bool _isProfileManualRefreshing = false;
  bool _hasLoadedHistory = false;
  bool _hasLoadedProfile = false;
  String? _errorMessage;
  List<Map<String, dynamic>> _exams = [];
  List<Map<String, dynamic>> _history = [];
  Map<String, dynamic>? _currentUser;

  bool get isLoading => _isLoading;
  bool get isHistoryLoading => _isHistoryLoading;
  bool get isProfileLoading => _isProfileLoading;
  bool get isHistoryManualRefreshing => _isHistoryManualRefreshing;
  bool get isProfileManualRefreshing => _isProfileManualRefreshing;
  bool get hasLoadedHistory => _hasLoadedHistory;
  bool get hasLoadedProfile => _hasLoadedProfile;
  String? get errorMessage => _errorMessage;
  List<Map<String, dynamic>> get exams => _exams;
  List<Map<String, dynamic>> get history => _history;
  Map<String, dynamic>? get currentUser => _currentUser;

  Future<void> loadExams({bool clearPrevious = false}) async {
    _isLoading = true;
    _errorMessage = null;
    if (clearPrevious) {
      _exams = [];
    }
    notifyListeners();

    _currentUser = await TokenStorage.getUser();
    if (_currentUser != null) {
      _hasLoadedProfile = true;
    }

    try {
      final response = await _api.get(ApiEndpoints.studentExams);
      if (response.data['status'] == 'success') {
        final rawList = response.data['data'] as List? ?? [];
        _exams = rawList.map((e) => Map<String, dynamic>.from(e)).toList();
        ExamReminderService.syncReminders(_exams);
      }
      await loadHistory(isManualRefresh: false);
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'Gagal memuat jadwal ujian. Periksa koneksi ke server.';
      notifyListeners();
    }
  }

  Future<void> refreshProfile({bool isManualRefresh = false, bool clearPrevious = false}) async {
    _isProfileLoading = true;
    if (isManualRefresh) {
      _isProfileManualRefreshing = true;
    }
    if (clearPrevious) {
      _currentUser = null;
      _hasLoadedProfile = false;
    }
    notifyListeners();
    try {
      final response = await _api.get(ApiEndpoints.userProfile);
      if (response.data != null && response.data['status'] == 'success') {
        final userData = response.data['data'] as Map<String, dynamic>?;
        if (userData != null) {
          _currentUser = userData;
          _hasLoadedProfile = true;
          await TokenStorage.saveUser(userData);
        }
      }
    } catch (_) {}
    _isProfileLoading = false;
    _isProfileManualRefreshing = false;
    notifyListeners();
  }

  Future<void> loadHistory({bool isManualRefresh = false, bool clearPrevious = false}) async {
    _isHistoryLoading = true;
    if (isManualRefresh) {
      _isHistoryManualRefreshing = true;
    }
    if (clearPrevious) {
      _history = [];
      _hasLoadedHistory = false;
    }
    notifyListeners();
    try {
      final response = await _api.get(ApiEndpoints.studentHistory);
      if (response.data['status'] == 'success') {
        final rawList = response.data['data'] as List? ?? [];
        _history = rawList.map((e) => Map<String, dynamic>.from(e)).toList();
        _hasLoadedHistory = true;
      }
    } catch (_) {
      _hasLoadedHistory = true;
    }
    _isHistoryLoading = false;
    _isHistoryManualRefreshing = false;
    notifyListeners();
  }

  Future<void> logout() async {
    await _auth.logout();
  }
}
