import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shiei_kiosk/core/auth/token_storage.dart';
import 'package:shiei_kiosk/core/notifications/exam_reminder_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel('id.shiei/lockdown');
  final List<MethodCall> log = <MethodCall>[];

  setUp(() {
    log.clear();
    FlutterSecureStorage.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      log.add(methodCall);
      switch (methodCall.method) {
        case 'scheduleExamReminder':
        case 'cancelExamReminder':
        case 'cancelAllExamReminders':
        case 'requestNotificationPermission':
          return true;
        default:
          return null;
      }
    });
  });

  group('Session Expiration Tests', () {
    test('Fresh session (< 3 days) is not expired', () async {
      await TokenStorage.saveSession(
        token: 'test_student_token_123',
        role: 'student',
        user: {'id': 1, 'name': 'Siswa Ujian'},
      );

      final isExpired = await TokenStorage.isSessionExpired(maxDays: 3);
      expect(isExpired, isFalse);
    });

    test('Old session (> 3 days) is marked as expired', () async {
      const storage = FlutterSecureStorage();
      final fourDaysAgo = DateTime.now().subtract(const Duration(days: 4));

      await storage.write(key: 'auth_token', value: 'expired_token_abc');
      await storage.write(
        key: 'session_timestamp',
        value: fourDaysAgo.millisecondsSinceEpoch.toString(),
      );

      final isExpired = await TokenStorage.isSessionExpired(maxDays: 3);
      expect(isExpired, isTrue);
    });

    test('Session without token returns false for isSessionExpired', () async {
      await TokenStorage.clear();
      final isExpired = await TokenStorage.isSessionExpired(maxDays: 3);
      expect(isExpired, isFalse);
    });
  });

  group('Exam Reminder & Imminent Detection Tests', () {
    test('getImminentExam detects exam starting within 2 hours today', () {
      final now = DateTime.now();
      final in30Minutes = now.add(const Duration(minutes: 30));

      final exams = [
        {
          'id': 101,
          'subject': 'Matematika Wajib',
          'start_time': in30Minutes.toIso8601String(),
          'duration': 60,
          'is_locked': false,
        },
        {
          'id': 102,
          'subject': 'Biologi',
          'start_time': now.add(const Duration(days: 5)).toIso8601String(),
          'duration': 90,
          'is_locked': false,
        },
      ];

      final imminent = ExamReminderService.getImminentExam(exams);
      expect(imminent, isNotNull);
      expect(imminent?['id'], equals(101));
      expect(imminent?['subject'], equals('Matematika Wajib'));
    });

    test('getImminentExam ignores locked or finished exams', () {
      final now = DateTime.now();
      final in15Minutes = now.add(const Duration(minutes: 15));

      final exams = [
        {
          'id': 201,
          'subject': 'Kimia',
          'start_time': in15Minutes.toIso8601String(),
          'duration': 60,
          'is_locked': true,
        },
      ];

      final imminent = ExamReminderService.getImminentExam(exams);
      expect(imminent, isNull);
    });

    test('syncReminders schedules reminder alarms via native MethodChannel', () async {
      final now = DateTime.now();
      final tomorrow = now.add(const Duration(days: 2));

      final exams = [
        {
          'id': 301,
          'subject': 'Fisika',
          'start_time': tomorrow.toIso8601String(),
          'duration': 90,
          'is_locked': false,
        },
      ];

      await ExamReminderService.syncReminders(exams);

      final scheduledCalls = log.where((c) => c.method == 'scheduleExamReminder').toList();
      expect(scheduledCalls.isNotEmpty, isTrue);

      final firstCall = scheduledCalls.first;
      expect(firstCall.arguments['examId'], equals(301));
      expect(firstCall.arguments['title'], contains('Fisika'));
    });

    test('cancelExamReminders sends cancel calls for both H-1 and H-30m reminders', () async {
      await ExamReminderService.cancelExamReminders(555);

      final cancelCalls = log.where((c) => c.method == 'cancelExamReminder').toList();
      expect(cancelCalls.length, equals(2));
      expect(cancelCalls[0].arguments['reminderId'], equals(555 * 10 + 1));
      expect(cancelCalls[1].arguments['reminderId'], equals(555 * 10 + 2));
    });
  });
}
