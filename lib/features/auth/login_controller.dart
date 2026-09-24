import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../../config/app_config.dart';
import '../../core/auth/auth_service.dart';

class LoginController extends ChangeNotifier {
  final AuthService _auth = AuthService();

  bool _isLoading = false;
  String? _errorMessage;
  String? _userRole;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String? get userRole => _userRole;
  bool get isTeacherMode => _userRole == 'teacher' || _userRole == 'school_admin' || _userRole == 'super_admin';

  void clearError() {
    if (_errorMessage != null) {
      _errorMessage = null;
      notifyListeners();
    }
  }

  void setError(String message) {
    _errorMessage = message;
    notifyListeners();
  }

  Future<bool> login({
    required String name,
    required String password,
    String? token,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final res = await _auth.login(name: name, password: password, examToken: token);
      _userRole = res['role'];
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _errorMessage = _parseError(e);
      notifyListeners();
      return false;
    }
  }

  String _parseError(dynamic error) {
    if (error is DioException) {
      final responseData = error.response?.data;
      if (responseData is Map) {
        // Handle validation errors map
        final errorsMap = responseData['errors'];
        if (errorsMap is Map && errorsMap.isNotEmpty) {
          final firstKey = errorsMap.keys.first;
          final firstVal = errorsMap[firstKey];
          if (firstVal is List && firstVal.isNotEmpty) {
            return _translateAuthMessage(firstVal.first.toString());
          } else if (firstVal is String && firstVal.isNotEmpty) {
            return _translateAuthMessage(firstVal);
          }
        }

        final msg = responseData['message']?.toString() ?? responseData['error']?.toString();
        if (msg != null && msg.trim().isNotEmpty) {
          return _translateAuthMessage(msg.trim());
        }
      }

      final statusCode = error.response?.statusCode;
      if (statusCode == 401) {
        return 'Nama pengguna atau kata sandi salah. Silakan periksa kembali.';
      }
      if (statusCode == 403) {
        return 'Akun Anda tidak memiliki izin akses atau dinonaktifkan.';
      }
      if (statusCode == 422) {
        return 'Format data tidak valid. Periksa isian nama pengguna dan kata sandi.';
      }
      if (statusCode == 429) {
        return 'Terlalu banyak percobaan login. Silakan tunggu beberapa saat.';
      }
      if (statusCode != null && statusCode >= 500) {
        return 'Terjadi kendala pada server (Error $statusCode). Hubungi admin sekolah.';
      }

      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.receiveTimeout) {
        return 'Gagal terhubung ke server ujian (${AppConfig.baseUrl}). Periksa Wi-Fi atau IP server.';
      }
    } else if (error is Exception) {
      return _translateAuthMessage(error.toString());
    }
    return 'Gagal masuk: Nama pengguna atau kata sandi salah.';
  }

  String _translateAuthMessage(String msg) {
    final lower = msg.toLowerCase();
    if (lower.contains('device mismatch') || lower.contains('terkunci ke hp lain') || lower.contains('device bound')) {
      return 'Perangkat Tidak Cocok: Akun ini sudah terkunci ke HP lain.';
    }
    if (lower.contains('invalid credentials') || lower.contains('tidak sesuai') || lower.contains('salah') || lower.contains('unauthenticated')) {
      return 'Nama pengguna atau kata sandi salah. Silakan periksa kembali.';
    }
    if (lower.contains('invalid exam access token') || lower.contains('token tidak valid') || lower.contains('token ujian')) {
      return 'Token ujian tidak valid atau sudah kedaluwarsa.';
    }
    if (lower.contains('inactive') || lower.contains('nonaktif') || lower.contains('disabled')) {
      return 'Akun Anda sedang dinonaktifkan. Hubungi admin sekolah.';
    }
    if (lower.contains('throttle') || lower.contains('too many requests') || lower.contains('terlalu banyak')) {
      return 'Terlalu banyak percobaan login. Silakan tunggu beberapa saat.';
    }
    if (lower.contains('connection') || lower.contains('socket') || lower.contains('host lookup') || lower.contains('unreachable')) {
      return 'Gagal terhubung ke server ujian. Periksa koneksi Wi-Fi atau IP server.';
    }
    if (lower.contains('timeout')) {
      return 'Batas waktu koneksi ke server habis. Silakan coba lagi.';
    }
    if (!lower.contains('exception') && !lower.contains('error:') && !lower.contains('dioexception') && !lower.contains('stack trace')) {
      return msg;
    }
    return 'Gagal masuk: Nama pengguna atau kata sandi salah.';
  }
}
