import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiei_kiosk/features/exam_player/exam_timer_widget.dart';
import 'package:shiei_kiosk/shared/theme/app_theme.dart';

void main() {
  group('ExamTimerWidget Tests', () {
    testWidgets('renders remaining time accurately in MM:SS and HH:MM:SS format', (WidgetTester tester) async {
      // 1. Under 1 hour (45 minutes = 2700s) -> 45:00
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: ExamTimerWidget(
              durationMinutes: 45,
              onTimeout: () {},
              enableMilestones: false,
            ),
          ),
        ),
      );
      expect(find.text('45:00'), findsOneWidget);

      // 2. 1 hour or more (90 minutes) -> 01:30:00
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: ExamTimerWidget(
              durationMinutes: 90,
              onTimeout: () {},
              enableMilestones: false,
            ),
          ),
        ),
      );
      expect(find.text('01:30:00'), findsOneWidget);
    });

    testWidgets('triggers milestone notification and callback when crossing milestone threshold', (WidgetTester tester) async {
      final triggeredMilestones = <int>[];

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: ExamTimerWidget(
              durationMinutes: 10,
              initialRemainingSeconds: 302, // 2 seconds before 5-minute milestone (300s)
              onTimeout: () {},
              onMilestone: (sec) {
                triggeredMilestones.add(sec);
              },
              enableMilestones: true,
            ),
          ),
        ),
      );

      // Initially at 302s, milestone 300 hasn't fired yet
      expect(triggeredMilestones.isEmpty, isTrue);

      // Tick 1 second -> remaining 301s
      await tester.pump(const Duration(seconds: 1));
      expect(triggeredMilestones.isEmpty, isTrue);

      // Tick 1 more second -> remaining 300s (crosses 5m milestone!)
      await tester.pump(const Duration(seconds: 1));
      expect(triggeredMilestones.contains(300), isTrue);

      // Verify notification overlay entry was injected
      expect(find.text('Perhatian: 5 Menit Terakhir!'), findsOneWidget);

      // Tick another second -> should NOT re-trigger milestone 300
      await tester.pump(const Duration(seconds: 1));
      expect(triggeredMilestones.where((m) => m == 300).length, equals(1));
    });

    testWidgets('does not immediately fire milestone >= initial remaining time on startup', (WidgetTester tester) async {
      final triggeredMilestones = <int>[];

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: ExamTimerWidget(
              durationMinutes: 60, // Exactly 3600 seconds
              onTimeout: () {},
              onMilestone: (sec) {
                triggeredMilestones.add(sec);
              },
              enableMilestones: true,
            ),
          ),
        ),
      );

      // 60-minute milestone (3600s) should NOT fire on 0 seconds elapsed
      expect(triggeredMilestones.contains(3600), isFalse);

      // Tick 2 seconds
      await tester.pump(const Duration(seconds: 2));
      expect(triggeredMilestones.isEmpty, isTrue);
    });

    testWidgets('invokes onTimeout when remaining seconds reaches zero', (WidgetTester tester) async {
      bool timeoutCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: ExamTimerWidget(
              durationMinutes: 1,
              initialRemainingSeconds: 2,
              onTimeout: () {
                timeoutCalled = true;
              },
              enableMilestones: false,
            ),
          ),
        ),
      );

      expect(timeoutCalled, isFalse);

      // Tick 1s -> 1s left
      await tester.pump(const Duration(seconds: 1));
      expect(timeoutCalled, isFalse);

      // Tick 1s -> 0s left -> onTimeout fired!
      await tester.pump(const Duration(seconds: 1));
      expect(timeoutCalled, isTrue);
    });

    testWidgets('synchronizes countdown to endTime when student enters late', (WidgetTester tester) async {
      // Allocated duration is 60 minutes, but endTime is exactly 10 minutes (600s) from now
      final now = DateTime.now();
      final targetEndTime = now.add(const Duration(minutes: 10));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: ExamTimerWidget(
              durationMinutes: 60,
              endTime: targetEndTime,
              onTimeout: () {},
              enableMilestones: false,
            ),
          ),
        ),
      );

      // Student gets strictly 10 minutes (or 09:59/10:00), never 60:00
      expect(find.text('10:00'), findsOneWidget);
    });

    testWidgets('didUpdateWidget updates remaining time when endTime is extended by teacher', (WidgetTester tester) async {
      final now = DateTime.now();
      DateTime currentEndTime = now.add(const Duration(minutes: 5));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: StatefulBuilder(
            builder: (context, setState) {
              return Scaffold(
                body: Column(
                  children: [
                    ExamTimerWidget(
                      durationMinutes: 60,
                      endTime: currentEndTime,
                      onTimeout: () {},
                      enableMilestones: false,
                    ),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          currentEndTime = now.add(const Duration(minutes: 20));
                        });
                      },
                      child: const Text('Extend'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );

      expect(find.text('05:00'), findsOneWidget);

      // Tap extend button to simulate teacher extending time on panel + refresh sync
      await tester.tap(find.text('Extend'));
      await tester.pump();

      expect(find.text('20:00'), findsOneWidget);
    });
  });
}
