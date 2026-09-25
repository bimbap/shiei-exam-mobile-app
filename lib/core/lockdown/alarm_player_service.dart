import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import '../auth/token_storage.dart';
import 'volume_lock_service.dart';

class AlarmPlayerService {
  static final AudioPlayer _player = AudioPlayer();
  static bool _isPlaying = false;

  static bool get isPlaying => _isPlaying;

  /**
   * Start looping the loud security siren alarm.
   * [lockHardwareVolume]: When false (default), the alarm blasts at 100% volume
   * initially, but the user is free to lower or mute the volume using their
   * physical hardware volume buttons.
   * [force]: When true, ignores debug anti-alarm bypass (for manual user testing).
   */
  static Future<void> playSiren({
    bool lockHardwareVolume = false,
    bool force = false,
  }) async {
    // Debug Mode Anti-Alarm / Volume Bypass Check
    if (!force && kDebugMode && await TokenStorage.isAntiAlarmBypassEnabled()) {
      debugPrint('[AlarmPlayerService] Debug Anti-Alarm / Volume bypass active. Siren suppressed.');
      return;
    }

    // 1. Force native hardware volume to 100%
    try {
      if (lockHardwareVolume) {
        await VolumeLockService.startVolumeLock();
      } else {
        await VolumeLockService.forceMaxVolume();
        // Ensure volume observer does not trap or revert physical volume keys
        await VolumeLockService.stopVolumeLock();
      }
    } catch (_) {}

    if (_isPlaying && _player.state == PlayerState.playing) return;
    _isPlaying = true;

    try {
      await _player.stop();
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(1.0);
      await _player.play(AssetSource('audio/siren_alarm.mp3'));
    } catch (_) {
      // If MP3 asset fails, attempt WAV fallback
      try {
        await _player.play(AssetSource('audio/siren_alarm.wav'));
      } catch (_) {}
    }
  }

  /**
   * Stop the siren and lift hardware volume lock.
   */
  static Future<void> stopSiren() async {
    _isPlaying = false;
    try {
      await _player.stop();
    } catch (_) {}
    await VolumeLockService.stopVolumeLock();
  }
}
