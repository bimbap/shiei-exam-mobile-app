import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class ExamReminderService {
  static const MethodChannel _channel = MethodChannel('id.shiei/lockdown');

  /**
   * Request notification runtime permission on Android 13+ (POST_NOTIFICATIONS).
   */
  static Future<void> requestPermission() async {
    try {
      await _channel.invokeMethod('requestNotificationPermission');
    } catch (_) {}
  }

  /**
   * Check if POST_NOTIFICATIONS permission is currently granted.
   */
  static Future<bool> isPermissionGranted() async {
    try {
      final res = await _channel.invokeMethod<bool>('isNotificationPermissionGranted');
      return res ?? false;
    } catch (_) {
      return true;
    }
  }

  /**
   * Synchronize scheduled reminders for all upcoming exams:
   * 1. H-1 at 19:00 WIB the day before the exam.
   * 2. H-30 minutes before exam start time.
   */
  static Future<void> syncReminders(List<Map<String, dynamic>> exams) async {
    final now = DateTime.now();

    for (final exam in exams) {
      final id = exam['id'];
      if (id is! int) continue;

      // Skip already finished / locked exams
      if (exam['is_locked'] == true) continue;

      final startTimeStr = exam['start_time'];
      if (startTimeStr == null) continue;

      DateTime? startDt;
      try {
        startDt = DateTime.parse(startTimeStr.toString()).toLocal();
      } catch (_) {
        continue;
      }

      final subject = (exam['subject'] ?? 'Ujian Sekolah').toString();
      final timeFormatted = DateFormat('HH:mm').format(startDt);

      // 1. H-1 Malam (19:00 WIB the day before exam date)
      final examDateOnly = DateTime(startDt.year, startDt.month, startDt.day);
      final dayBeforeAt19 = examDateOnly.subtract(const Duration(days: 1)).add(const Duration(hours: 19));

      if (dayBeforeAt19.isAfter(now)) {
        await _scheduleReminder(
          examId: id,
          reminderId: id * 10 + 1,
          title: '📅 Besok: Ujian $subject',
          message: 'Ujian dimulai besok pukul $timeFormatted WIB. Pastikan baterai HP Anda penuh.',
          triggerTimeMillis: dayBeforeAt19.millisecondsSinceEpoch,
        );
      }

      // 2. H-30 Menit sebelum ujian dimulai
      final hMinus30m = startDt.subtract(const Duration(minutes: 30));
      if (hMinus30m.isAfter(now)) {
        await _scheduleReminder(
          examId: id,
          reminderId: id * 10 + 2,
          title: '⏰ 30 Menit Lagi: Ujian $subject',
          message: 'Ujian akan dimulai pukul $timeFormatted WIB. Silakan bersiap di ruang ujian.',
          triggerTimeMillis: hMinus30m.millisecondsSinceEpoch,
        );
      }
    }
  }

  static Future<bool> _scheduleReminder({
    required int examId,
    required int reminderId,
    required String title,
    required String message,
    required int triggerTimeMillis,
  }) async {
    try {
      final bool? success = await _channel.invokeMethod('scheduleExamReminder', {
        'examId': examId,
        'reminderId': reminderId,
        'title': title,
        'message': message,
        'triggerTimeMillis': triggerTimeMillis,
      });
      return success ?? false;
    } catch (_) {
      return false;
    }
  }

  /**
   * Cancel reminders for a specific exam (e.g. when exam starts or is submitted).
   */
  static Future<void> cancelExamReminders(int examId) async {
    try {
      await _channel.invokeMethod('cancelExamReminder', {'reminderId': examId * 10 + 1});
      await _channel.invokeMethod('cancelExamReminder', {'reminderId': examId * 10 + 2});
    } catch (_) {}
  }

  /**
   * Find an imminent upcoming exam scheduled for today within the next 2 hours.
   */
  static Map<String, dynamic>? getImminentExam(List<Map<String, dynamic>> exams) {
    final now = DateTime.now();

    for (final exam in exams) {
      if (exam['is_locked'] == true) continue;
      final startTimeStr = exam['start_time'];
      if (startTimeStr == null) continue;

      try {
        final startDt = DateTime.parse(startTimeStr.toString()).toLocal();
        final diff = startDt.difference(now);

        // Within 2 hours before start, or started less than duration ago
        final durationMinutes = exam['duration'] ?? exam['duration_minutes'] ?? 60;
        if (diff.inMinutes >= -durationMinutes && diff.inMinutes <= 120) {
          return exam;
        }
      } catch (_) {}
    }
    return null;
  }
}
