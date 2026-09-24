import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../api/api_client.dart';
import '../api/endpoints.dart';

class CheatReporter {
  static final ApiClient _api = ApiClient();
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _pendingViolationsKey = 'pending_cheat_violations';

  /**
   * Report anti-cheat incident to backend server.
   * If network fails or is disconnected, the incident is securely buffered in
   * offline persistence so it cannot be escaped or lost.
   */
  static Future<Map<String, dynamic>?> reportViolation({
    required int linkId,
    required String eventType,
    Map<String, dynamic>? metadata,
  }) async {
    final payload = {
      'link_id': linkId,
      'event_type': eventType,
      'metadata': {
        ...?metadata,
        'client_timestamp': DateTime.now().toIso8601String(),
      },
    };

    try {
      final response = await _api.post(
        ApiEndpoints.cheatEvent,
        data: payload,
      );

      // Successfully sent — attempt to flush any previous buffered violations
      _flushPendingViolationsAsync();

      return response.data as Map<String, dynamic>?;
    } catch (_) {
      // Network failed or device offline: buffer securely
      await _queueViolation(payload);
      return null;
    }
  }

  static Future<void> _queueViolation(Map<String, dynamic> payload) async {
    try {
      final raw = await _storage.read(key: _pendingViolationsKey);
      List<dynamic> list = [];
      if (raw != null) {
        try {
          list = jsonDecode(raw) as List<dynamic>;
        } catch (_) {}
      }
      list.add(payload);
      await _storage.write(key: _pendingViolationsKey, value: jsonEncode(list));
    } catch (_) {}
  }

  static void _flushPendingViolationsAsync() {
    flushPendingViolations();
  }

  /**
   * Flush all buffered offline violations to backend when connectivity is restored.
   */
  static Future<void> flushPendingViolations() async {
    try {
      final raw = await _storage.read(key: _pendingViolationsKey);
      if (raw == null || raw.isEmpty) return;

      List<dynamic> list = [];
      try {
        list = jsonDecode(raw) as List<dynamic>;
      } catch (_) {
        return;
      }
      if (list.isEmpty) return;

      final remaining = <dynamic>[];
      for (final item in list) {
        try {
          if (item is Map<String, dynamic>) {
            await _api.post(ApiEndpoints.cheatEvent, data: item);
          } else if (item is Map) {
            await _api.post(ApiEndpoints.cheatEvent, data: Map<String, dynamic>.from(item));
          }
        } catch (_) {
          remaining.add(item);
        }
      }

      if (remaining.isEmpty) {
        await _storage.delete(key: _pendingViolationsKey);
      } else {
        await _storage.write(key: _pendingViolationsKey, value: jsonEncode(remaining));
      }
    } catch (_) {}
  }
}
