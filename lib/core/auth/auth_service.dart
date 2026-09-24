import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import '../api/api_client.dart';
import '../api/endpoints.dart';
import 'token_storage.dart';

import '../lockdown/volume_lock_service.dart';

class AuthService {
  final ApiClient _api = ApiClient();
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  /**
   * Extract unique hardware fingerprint, device name (e.g. Xperia 1 III),
   * and device ID (e.g. SOG03) for 1-device lock and friendly identification.
   */
  Future<Map<String, String>> getDeviceDetails() async {
    String deviceName = '';
    String deviceId = '';
    String serialNumber = '';

    try {
      deviceName = await VolumeLockService.getDeviceName();
      deviceId = await VolumeLockService.getDeviceId();
    } catch (_) {}

    try {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        if (deviceId.isEmpty || deviceId == 'UNKNOWN') {
          deviceId = androidInfo.model.isNotEmpty ? androidInfo.model : androidInfo.device;
        }
        if (deviceName.isEmpty || deviceName == 'Android Device') {
          final brand = androidInfo.brand.isNotEmpty ? androidInfo.brand : androidInfo.manufacturer;
          deviceName = '$brand ${androidInfo.model}'.trim();
        }
        serialNumber = androidInfo.id.isNotEmpty ? androidInfo.id : androidInfo.fingerprint;
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfo.iosInfo;
        if (deviceName.isEmpty) deviceName = iosInfo.name.isNotEmpty ? iosInfo.name : 'iPhone / iPad';
        if (deviceId.isEmpty) deviceId = iosInfo.utsname.machine.isNotEmpty ? iosInfo.utsname.machine : 'iOS';
        serialNumber = iosInfo.identifierForVendor ?? 'IOS-UNKNOWN-DEVICE';
      }
    } catch (_) {}

    if (serialNumber.isEmpty) {
      final cached = await TokenStorage.getSerialNumber();
      if (cached != null && cached.isNotEmpty) {
        serialNumber = cached;
      } else {
        serialNumber = '$deviceId-${DateTime.now().millisecondsSinceEpoch}';
      }
    }

    return {
      'device_name': deviceName.isNotEmpty ? deviceName : 'Android Device',
      'device_id': deviceId.isNotEmpty ? deviceId : 'UNKNOWN',
      'serial_number': serialNumber,
    };
  }

  /**
   * Extract unique hardware fingerprint or serial number for 1-device lock.
   */
  Future<String> getDeviceUniqueIdentifier() async {
    final details = await getDeviceDetails();
    return details['serial_number']!;
  }

  /**
   * Unified Login for any role (Student, Teacher, Admin).
   * Automatically passes hardware device details and handles role-tailored session saving.
   */
  Future<Map<String, dynamic>> login({
    required String name,
    required String password,
    String? examToken,
  }) async {
    final details = await getDeviceDetails();
    final serialNumber = details['serial_number']!;
    final deviceName = details['device_name']!;
    final deviceId = details['device_id']!;

    final response = await _api.post(
      ApiEndpoints.login,
      data: {
        'name': name.trim(),
        'password': password,
        'token': examToken?.trim(),
        'serial_number': serialNumber,
        'device_name': deviceName,
        'device_id': deviceId,
      },
    );

    final data = response.data;
    if (data['status'] == 'success') {
      await TokenStorage.saveSession(
        token: data['token'],
        role: data['role'],
        user: data['user'],
        serialNumber: serialNumber,
      );
    }
    return data;
  }

  /**
   * Student Login with Username, Password, Exam Token, Serial Number, Device Name, and Device ID.
   */
  Future<Map<String, dynamic>> studentLogin({
    required String name,
    required String password,
    String? examToken,
  }) async {
    final details = await getDeviceDetails();
    final serialNumber = details['serial_number']!;
    final deviceName = details['device_name']!;
    final deviceId = details['device_id']!;

    final response = await _api.post(
      ApiEndpoints.studentLogin,
      data: {
        'name': name.trim(),
        'password': password,
        'token': examToken?.trim(),
        'serial_number': serialNumber,
        'device_name': deviceName,
        'device_id': deviceId,
      },
    );

    final data = response.data;
    if (data['status'] == 'success') {
      await TokenStorage.saveSession(
        token: data['token'],
        role: data['role'],
        user: data['user'],
        serialNumber: serialNumber,
      );
    }
    return data;
  }

  /**
   * Staff/Teacher Login.
   */
  Future<Map<String, dynamic>> teacherLogin({
    required String name,
    required String password,
  }) async {
    final response = await _api.post(
      ApiEndpoints.adminLogin,
      data: {
        'name': name.trim(),
        'password': password,
      },
    );

    final data = response.data;
    if (data['status'] == 'success') {
      await TokenStorage.saveSession(
        token: data['token'],
        role: data['role'],
        user: data['user'],
      );
    }
    return data;
  }

  /**
   * Logout and clear encrypted session.
   */
  Future<void> logout() async {
    try {
      await _api.post(ApiEndpoints.logout);
    } catch (_) {
      // Ignore network errors during logout
    }
    await TokenStorage.clear();
  }

  /**
   * Check if user is currently authenticated.
   */
  Future<bool> isLoggedIn() async {
    final token = await TokenStorage.getToken();
    return token != null && token.isNotEmpty;
  }
}
