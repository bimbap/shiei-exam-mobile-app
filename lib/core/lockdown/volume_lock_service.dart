import 'package:flutter/services.dart';

class VolumeLockService {
  static const MethodChannel _channel = MethodChannel('id.shiei/lockdown');

  /**
   * Activate hardware volume lock at 100% maximum volume.
   * Native Android listener will override any volume reduction back to 100%.
   */
  static Future<void> startVolumeLock() async {
    try {
      await _channel.invokeMethod('startVolumeLock');
    } catch (_) {
      // Non-Android platforms or fallback
    }
  }

  /**
   * Deactivate hardware volume lock.
   */
  static Future<void> stopVolumeLock() async {
    try {
      await _channel.invokeMethod('stopVolumeLock');
    } catch (_) {
      // Fallback
    }
  }

  /**
   * Immediately force system audio streams to 100%.
   */
  static Future<void> forceMaxVolume() async {
    try {
      await _channel.invokeMethod('forceMaxVolume');
    } catch (_) {
      // Fallback
    }
  }

  /**
   * Check whether device is currently in split-screen / multi-window mode.
   */
  static Future<bool> isMultiWindow() async {
    try {
      final bool inMulti = await _channel.invokeMethod('isMultiWindow') ?? false;
      return inMulti;
    } catch (_) {
      return false;
    }
  }

  /**
   * Pin the app in Kiosk mode (disables Home, Overview, and Notification shade on Android).
   */
  static Future<bool> startLockTask() async {
    try {
      final bool success = await _channel.invokeMethod('startLockTask') ?? false;
      return success;
    } catch (_) {
      return false;
    }
  }

  /**
   * Stop Kiosk mode pinning (only on valid exam completion or proctor PIN unlock).
   */
  static Future<bool> stopLockTask() async {
    try {
      final bool success = await _channel.invokeMethod('stopLockTask') ?? false;
      return success;
    } catch (_) {
      return false;
    }
  }

  /**
   * Check whether Kiosk lock task is currently active.
   */
  static Future<bool> isLockTaskActive() async {
    try {
      final bool active = await _channel.invokeMethod('isLockTaskActive') ?? false;
      return active;
    } catch (_) {
      return false;
    }
  }

  /**
   * Check whether Bluetooth is currently enabled on the device.
   * Anti-cheat requirement: Bluetooth must be OFF during exams.
   */
  static Future<bool> isBluetoothEnabled() async {
    try {
      final bool enabled = await _channel.invokeMethod('isBluetoothEnabled') ?? false;
      return enabled;
    } catch (_) {
      return false;
    }
  }

  /**
   * Enable or disable native FLAG_SECURE (anti-screenshot & screen record protection).
   */
  static Future<bool> setFlagSecure(bool enable) async {
    try {
      final bool success = await _channel.invokeMethod('setFlagSecure', {'enable': enable}) ?? false;
      return success;
    } catch (_) {
      return false;
    }
  }

  /**
   * Get current network connection type: 'wifi', 'cellular', 'ethernet', or 'none'.
   */
  static Future<String> getNetworkType() async {
    try {
      final String? type = await _channel.invokeMethod('getNetworkType');
      return type ?? 'none';
    } catch (_) {
      return 'none';
    }
  }

  /**
   * Hide and block floating apps and non-system overlay windows.
   */
  static Future<bool> setOverlayProtection(bool enable) async {
    try {
      final bool success = await _channel.invokeMethod('setOverlayProtection', {'enable': enable}) ?? false;
      return success;
    } catch (_) {
      return false;
    }
  }

  /**
   * Check whether an incoming or active phone call is currently in progress.
   * Exam Policy: Phone calls are permitted and will NOT eject student from exam.
   */
  static Future<bool> isPhoneCallActive() async {
    try {
      final bool active = await _channel.invokeMethod('isPhoneCallActive') ?? false;
      return active;
    } catch (_) {
      return false;
    }
  }

  /**
   * Get current device battery percentage level (0 to 100).
   */
  static Future<int> getBatteryLevel() async {
    try {
      final int level = await _channel.invokeMethod('getBatteryLevel') ?? -1;
      return level;
    } catch (_) {
      return -1;
    }
  }

  /**
   * Check whether device is currently plugged into charger / charging.
   * Exam Policy: Students are fully permitted to charge their device during exams.
   */
  static Future<bool> isDeviceCharging() async {
    try {
      final bool charging = await _channel.invokeMethod('isDeviceCharging') ?? false;
      return charging;
    } catch (_) {
      return false;
    }
  }

  /**
   * Check whether an external display, HDMI, or screen cast is connected.
   * Anti-cheat requirement: External displays are strictly forbidden during exams.
   */
  static Future<bool> isExternalDisplayConnected() async {
    try {
      final bool connected = await _channel.invokeMethod('isExternalDisplayConnected') ?? false;
      return connected;
    } catch (_) {
      return false;
    }
  }

  /**
   * Get current system screen brightness percentage (0 to 100).
   */
  static Future<int> getScreenBrightness() async {
    try {
      final int brightness = await _channel.invokeMethod('getScreenBrightness') ?? 50;
      return brightness;
    } catch (_) {
      return 50;
    }
  }

  /**
   * Set window brightness level (clamped to at least 40% minimum to prevent dimming).
   */
  static Future<bool> setWindowBrightness(int brightnessPercent) async {
    try {
      final bool success = await _channel.invokeMethod('setWindowBrightness', {
        'brightness': brightnessPercent,
      }) ?? false;
      return success;
    } catch (_) {
      return false;
    }
  }

  /**
   * Get human-readable device marketing name (e.g. "Xperia 1 III", "Galaxy S23").
   */
  static Future<String> getDeviceName() async {
    try {
      final String name = await _channel.invokeMethod('getDeviceName') ?? '';
      if (name.isNotEmpty) return name;
    } catch (_) {}
    return 'Android Device';
  }

  /**
   * Get hardware device ID / model code (e.g. "SOG03", "SM-S918B").
   */
  static Future<String> getDeviceId() async {
    try {
      final String id = await _channel.invokeMethod('getDeviceId') ?? '';
      if (id.isNotEmpty) return id;
    } catch (_) {}
    return 'UNKNOWN';
  }

  /**
   * Block or unblock native Android system status bar and gesture navigation bar.
   * When blocked, pull-downs and swipe-up gesture bars are immediately suppressed/collapsed.
   */
  static Future<bool> setKioskSystemBarsBlocked(bool blocked) async {
    try {
      final bool success = await _channel.invokeMethod('setKioskSystemBarsBlocked', {
        'blocked': blocked,
      }) ?? false;
      return success;
    } catch (_) {
      return false;
    }
  }

  /**
   * Lock or unlock device orientation strictly to portrait upright mode.
   */
  static Future<bool> lockOrientationPortrait(bool lock) async {
    try {
      final bool success = await _channel.invokeMethod('lockOrientationPortrait', {
        'lock': lock,
      }) ?? false;
      return success;
    } catch (_) {
      return false;
    }
  }

  /**
   * Check whether the device is rooted (SU binary, Magisk, test-keys).
   */
  static Future<bool> isDeviceRooted() async {
    try {
      final bool rooted = await _channel.invokeMethod('isDeviceRooted') ?? false;
      return rooted;
    } catch (_) {
      return false;
    }
  }

  /**
   * Check whether Frida dynamic instrumentation server/gadget is detected.
   */
  static Future<bool> isFridaDetected() async {
    try {
      final bool detected = await _channel.invokeMethod('isFridaDetected') ?? false;
      return detected;
    } catch (_) {
      return false;
    }
  }

  /**
   * Check whether USB Debugging / Developer Options ADB is active.
   */
  static Future<bool> isUsbDebuggingEnabled() async {
    try {
      final bool enabled = await _channel.invokeMethod('isUsbDebuggingEnabled') ?? false;
      return enabled;
    } catch (_) {
      return false;
    }
  }

  /**
   * Get app signing certificate fingerprint hash.
   */
  static Future<String> getAppSignatureHash() async {
    try {
      final String hash = await _channel.invokeMethod('verifyAppSignature') ?? '';
      return hash;
    } catch (_) {
      return '';
    }
  }

  /**
   * Perform comprehensive security integrity audit.
   * Returns a map containing root, frida, usb debugging, and signature validity states.
   */
  static Future<Map<String, dynamic>> checkSecurityIntegrity() async {
    try {
      final Map<dynamic, dynamic>? res = await _channel.invokeMethod('checkSecurityIntegrity');
      if (res != null) {
        return Map<String, dynamic>.from(res);
      }
    } catch (_) {}
    return {
      'isRooted': false,
      'isFrida': false,
      'isUsbDebugging': false,
      'isSignatureValid': true,
      'signatureHash': '',
      'isDebug': true,
    };
  }
}
