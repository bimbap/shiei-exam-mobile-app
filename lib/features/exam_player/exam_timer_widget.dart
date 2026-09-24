import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/app_notification.dart';

class ExamMilestone {
  final int seconds;
  final String title;
  final String subtitle;
  final NotificationType type;
  final IconData icon;

  const ExamMilestone({
    required this.seconds,
    required this.title,
    required this.subtitle,
    required this.type,
    required this.icon,
  });
}

class ExamTimerWidget extends StatefulWidget {
  final int durationMinutes;
  final int extraMinutes;
  final VoidCallback onTimeout;
  final void Function(int remainingSeconds)? onMilestone;
  final bool enableMilestones;
  final int? initialRemainingSeconds;
  final DateTime? endTime;
  final DateTime? startTime;
  final Duration serverClockOffset;

  static const List<ExamMilestone> defaultMilestones = [
    ExamMilestone(
      seconds: 3600, // 60 minutes / 1 hour
      title: 'Waktu Tersisa: 1 Jam',
      subtitle: 'Masih ada 60 menit tersisa. Periksa ritme dan pembagian waktu pengerjaan soal Anda.',
      type: NotificationType.info,
      icon: Icons.access_time_rounded,
    ),
    ExamMilestone(
      seconds: 1800, // 30 minutes
      title: 'Waktu Tersisa: 30 Menit',
      subtitle: 'Sisa waktu pengerjaan 30 menit lagi. Pastikan seluruh soal utama telah terisi.',
      type: NotificationType.info,
      icon: Icons.timer_outlined,
    ),
    ExamMilestone(
      seconds: 900, // 15 minutes
      title: 'Pengingat: 15 Menit Lagi',
      subtitle: 'Waktu ujian segera berakhir dalam 15 menit. Mulai periksa dan selesaikan soal yang belum terjawab.',
      type: NotificationType.warning,
      icon: Icons.hourglass_bottom_rounded,
    ),
    ExamMilestone(
      seconds: 600, // 10 minutes
      title: 'Pengingat: 10 Menit Lagi',
      subtitle: 'Waktu pengerjaan tinggal 10 menit. Pastikan tidak ada nomor soal yang terlewat.',
      type: NotificationType.warning,
      icon: Icons.timelapse_rounded,
    ),
    ExamMilestone(
      seconds: 300, // 5 minutes
      title: 'Perhatian: 5 Menit Terakhir!',
      subtitle: 'Waktu tinggal 5 menit! Segera tuntaskan jawaban dan bersiap untuk mengirim ujian.',
      type: NotificationType.warning,
      icon: Icons.alarm_on_rounded,
    ),
    ExamMilestone(
      seconds: 60, // 1 minute
      title: 'Peringatan: 1 Menit Terakhir!',
      subtitle: 'Sisa waktu 1 menit! Sistem akan otomatis mengunci dan mengirim jawaban ujian.',
      type: NotificationType.error,
      icon: Icons.warning_amber_rounded,
    ),
  ];

  const ExamTimerWidget({
    super.key,
    required this.durationMinutes,
    this.extraMinutes = 0,
    required this.onTimeout,
    this.onMilestone,
    this.enableMilestones = true,
    this.initialRemainingSeconds,
    this.endTime,
    this.startTime,
    this.serverClockOffset = Duration.zero,
  });

  @override
  State<ExamTimerWidget> createState() => _ExamTimerWidgetState();
}

class _ExamTimerWidgetState extends State<ExamTimerWidget> with SingleTickerProviderStateMixin {
  late int _remainingSeconds;
  Timer? _timer;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  final Set<int> _notifiedMilestones = <int>{};

  int _computeRemainingSeconds() {
    final effectiveNow = DateTime.now().add(widget.serverClockOffset);
    final allocatedSeconds = (widget.durationMinutes + widget.extraMinutes) * 60;

    if (widget.endTime != null) {
      final effectiveEndTime = widget.endTime!.add(Duration(minutes: widget.extraMinutes));
      final diffMs = effectiveEndTime.difference(effectiveNow).inMilliseconds;
      if (diffMs <= 0) return 0;
      final diffToEnd = (diffMs / 1000).ceil();

      // If startTime is specified and exam has already started, remaining time is bounded
      // by either (1) time left until endTime, or (2) remaining allocated duration since startTime
      if (widget.startTime != null && effectiveNow.isAfter(widget.startTime!)) {
        final elapsedSinceStart = effectiveNow.difference(widget.startTime!).inSeconds;
        final remainingFromDuration = allocatedSeconds - elapsedSinceStart;
        final target = remainingFromDuration < diffToEnd ? remainingFromDuration : diffToEnd;
        return target.clamp(0, allocatedSeconds);
      }

      return diffToEnd < allocatedSeconds ? diffToEnd : allocatedSeconds;
    }

    return allocatedSeconds;
  }

  @override
  void initState() {
    super.initState();
    if (widget.endTime != null) {
      _remainingSeconds = _computeRemainingSeconds();
    } else {
      _remainingSeconds = widget.initialRemainingSeconds ?? ((widget.durationMinutes + widget.extraMinutes) * 60);
    }

    // Suppress any milestone that is >= initial duration
    // so starting an exam doesn't immediately fire redundant notifications
    for (final milestone in ExamTimerWidget.defaultMilestones) {
      if (milestone.seconds >= _remainingSeconds) {
        _notifiedMilestones.add(milestone.seconds);
      }
    }

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _pulseAnimation = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    if (_remainingSeconds < 300) {
      _pulseController.repeat(reverse: true);
    }

    _startTimer();
  }

  @override
  void didUpdateWidget(covariant ExamTimerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final hasEndTimeChanged = oldWidget.endTime != widget.endTime;
    final hasStartTimeChanged = oldWidget.startTime != widget.startTime;
    final hasDurationChanged = oldWidget.durationMinutes != widget.durationMinutes;
    final hasExtraMinutesChanged = oldWidget.extraMinutes != widget.extraMinutes;

    if (hasEndTimeChanged || hasStartTimeChanged || hasDurationChanged || hasExtraMinutesChanged) {
      setState(() {
        if (widget.endTime != null) {
          _remainingSeconds = _computeRemainingSeconds();
        } else {
          final oldTotal = (oldWidget.durationMinutes + oldWidget.extraMinutes) * 60;
          final newTotal = (widget.durationMinutes + widget.extraMinutes) * 60;
          final diff = newTotal - oldTotal;
          _remainingSeconds = (_remainingSeconds + diff).clamp(0, newTotal);
        }

        if (_remainingSeconds < 300 && !_pulseController.isAnimating) {
          _pulseController.repeat(reverse: true);
        } else if (_remainingSeconds >= 300 && _pulseController.isAnimating) {
          _pulseController.stop();
          _pulseController.reset();
        }
      });

      // If duration or endTime was extended, re-enable future milestones that haven't been crossed yet
      _notifiedMilestones.removeWhere((sec) => sec < _remainingSeconds);
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;

      int nextRemaining;
      if (widget.endTime != null) {
        // Keep strictly synchronized with target end_time wall clock
        nextRemaining = _computeRemainingSeconds();
      } else {
        nextRemaining = _remainingSeconds - 1;
      }

      if (nextRemaining < 0) nextRemaining = 0;

      setState(() {
        _remainingSeconds = nextRemaining;
        if (_remainingSeconds < 300 && !_pulseController.isAnimating) {
          _pulseController.repeat(reverse: true);
        } else if (_remainingSeconds >= 300 && _pulseController.isAnimating) {
          _pulseController.stop();
          _pulseController.reset();
        }
      });

      if (_remainingSeconds == 0) {
        _timer?.cancel();
        _pulseController.stop();
        widget.onTimeout();
      } else {
        _checkMilestones(_remainingSeconds);
      }
    });
  }

  void _checkMilestones(int remaining) {
    if (!widget.enableMilestones || !mounted) return;

    for (final milestone in ExamTimerWidget.defaultMilestones) {
      if (remaining <= milestone.seconds && !_notifiedMilestones.contains(milestone.seconds)) {
        _notifiedMilestones.add(milestone.seconds);
        widget.onMilestone?.call(milestone.seconds);

        // Gentle haptic feedback
        try {
          if (milestone.seconds <= 300) {
            HapticFeedback.heavyImpact();
          } else {
            HapticFeedback.mediumImpact();
          }
        } catch (_) {}

        AppNotification.show(
          context,
          title: milestone.title,
          subtitle: milestone.subtitle,
          type: milestone.type,
          customIcon: milestone.icon,
          duration: const Duration(seconds: 4),
        );
        break; // Trigger at most one milestone notification per second tick
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    AppNotification.hide();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hours = _remainingSeconds ~/ 3600;
    final minutes = ((_remainingSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final seconds = (_remainingSeconds % 60).toString().padLeft(2, '0');
    final timeDisplay = hours > 0
        ? '${hours.toString().padLeft(2, '0')}:$minutes:$seconds'
        : '$minutes:$seconds';

    Color timerColor = AppTheme.accentGreen;
    bool isCritical = false;

    if (_remainingSeconds < 300) {
      timerColor = AppTheme.dangerRed;
      isCritical = true;
    } else if (_remainingSeconds < 600) {
      timerColor = const Color(0xFFF59E0B);
    }

    final widgetContent = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: timerColor.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: timerColor.withValues(alpha: isCritical ? 0.7 : 0.4),
          width: isCritical ? 1.4 : 1,
        ),
        boxShadow: isCritical
            ? [
                BoxShadow(
                  color: timerColor.withValues(alpha: 0.25),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isCritical ? Icons.alarm_on_rounded : Icons.timer_outlined,
            size: 15,
            color: timerColor,
          ),
          const SizedBox(width: 5),
          Text(
            timeDisplay,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: timerColor,
              fontFamily: 'monospace',
              letterSpacing: 0.5,
            ),
          ),
          if (widget.extraMinutes > 0) ...[
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.6), width: 0.8),
              ),
              child: Text(
                '+${widget.extraMinutes}m',
                style: const TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFFF59E0B),
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ],
      ),
    );

    if (isCritical) {
      return AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return Opacity(
            opacity: _pulseAnimation.value,
            child: child,
          );
        },
        child: widgetContent,
      );
    }

    return widgetContent;
  }
}
