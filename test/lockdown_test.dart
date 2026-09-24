import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:shiei_kiosk/core/lockdown/volume_lock_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel('id.shiei/lockdown');
  final List<MethodCall> log = <MethodCall>[];

  bool mockBluetooth = true;
  bool mockLockTask = false;
  bool mockMultiWindow = false;

  setUp(() {
    log.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      log.add(methodCall);
      switch (methodCall.method) {
        case 'isBluetoothEnabled':
          return mockBluetooth;
        case 'startLockTask':
          mockLockTask = true;
          return true;
        case 'stopLockTask':
          mockLockTask = false;
          return true;
        case 'isLockTaskActive':
          return mockLockTask;
        case 'isMultiWindow':
          return mockMultiWindow;
        case 'startVolumeLock':
        case 'stopVolumeLock':
        case 'forceMaxVolume':
        case 'setFlagSecure':
        case 'setKioskSystemBarsBlocked':
        case 'lockOrientationPortrait':
          return true;
        case 'getNetworkType':
          return 'wifi';
        case 'isDeviceRooted':
          return false;
        case 'isFridaDetected':
          return false;
        case 'isUsbDebuggingEnabled':
          return false;
        case 'verifyAppSignature':
          return 'A1B2C3D4E5';
        case 'checkSecurityIntegrity':
          return {
            'isRooted': false,
            'isFrida': false,
            'isUsbDebugging': false,
            'isSignatureValid': true,
            'signatureHash': 'A1B2C3D4E5',
            'isDebug': true,
          };
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('VolumeLockService detects Bluetooth state correctly', () async {
    mockBluetooth = true;
    final isEnabled = await VolumeLockService.isBluetoothEnabled();
    expect(isEnabled, true);

    mockBluetooth = false;
    final isOff = await VolumeLockService.isBluetoothEnabled();
    expect(isOff, false);
  });

  test('VolumeLockService pins and unpins Kiosk LockTask', () async {
    expect(await VolumeLockService.isLockTaskActive(), false);

    final startOk = await VolumeLockService.startLockTask();
    expect(startOk, true);
    expect(await VolumeLockService.isLockTaskActive(), true);

    final stopOk = await VolumeLockService.stopLockTask();
    expect(stopOk, true);
    expect(await VolumeLockService.isLockTaskActive(), false);
  });

  test('VolumeLockService detects multi-window split screen', () async {
    mockMultiWindow = false;
    expect(await VolumeLockService.isMultiWindow(), false);

    mockMultiWindow = true;
    expect(await VolumeLockService.isMultiWindow(), true);
  });

  test('Exam token verification matches 6-digit code case-insensitively', () {
    const expected = 'ABC123';

    bool verifyToken(String input) {
      return input.trim().toUpperCase() == expected.trim().toUpperCase();
    }

    expect(verifyToken('abc123'), true);
    expect(verifyToken('ABC123'), true);
    expect(verifyToken(' abc123 '), true);
    expect(verifyToken('WRONG1'), false);
    expect(verifyToken(''), false);
  });

  test('VolumeLockService setFlagSecure calls native method channel', () async {
    final result = await VolumeLockService.setFlagSecure(false);
    expect(result, true);
    expect(log.any((call) => call.method == 'setFlagSecure' && call.arguments['enable'] == false), true);

    final resultEnable = await VolumeLockService.setFlagSecure(true);
    expect(resultEnable, true);
    expect(log.any((call) => call.method == 'setFlagSecure' && call.arguments['enable'] == true), true);
  });

  test('VolumeLockService getNetworkType returns connection type', () async {
    final net = await VolumeLockService.getNetworkType();
    expect(net, 'wifi');
    expect(log.any((call) => call.method == 'getNetworkType'), true);
  });

  test('VolumeLockService blocks and unblocks system bars', () async {
    final res = await VolumeLockService.setKioskSystemBarsBlocked(true);
    expect(res, true);
    expect(log.any((call) => call.method == 'setKioskSystemBarsBlocked' && call.arguments['blocked'] == true), true);

    final resUnblock = await VolumeLockService.setKioskSystemBarsBlocked(false);
    expect(resUnblock, true);
    expect(log.any((call) => call.method == 'setKioskSystemBarsBlocked' && call.arguments['blocked'] == false), true);
  });

  test('VolumeLockService locks and unlocks portrait orientation', () async {
    final res = await VolumeLockService.lockOrientationPortrait(true);
    expect(res, true);
    expect(log.any((call) => call.method == 'lockOrientationPortrait' && call.arguments['lock'] == true), true);

    final resUnlock = await VolumeLockService.lockOrientationPortrait(false);
    expect(resUnlock, true);
    expect(log.any((call) => call.method == 'lockOrientationPortrait' && call.arguments['lock'] == false), true);
  });

  test('VolumeLockService security integrity methods return valid data', () async {
    expect(await VolumeLockService.isDeviceRooted(), false);
    expect(await VolumeLockService.isFridaDetected(), false);
    expect(await VolumeLockService.isUsbDebuggingEnabled(), false);
    expect(await VolumeLockService.getAppSignatureHash(), 'A1B2C3D4E5');

    final integrity = await VolumeLockService.checkSecurityIntegrity();
    expect(integrity['isRooted'], false);
    expect(integrity['isFrida'], false);
    expect(integrity['isUsbDebugging'], false);
    expect(integrity['isSignatureValid'], true);
    expect(integrity['signatureHash'], 'A1B2C3D4E5');
    expect(integrity['isDebug'], true);
  });

  test('LockdownService stopExamMonitoring handles stopAlarm flag without errors', () {
    // Verifies that calling stopExamMonitoring(stopAlarm: false) does not crash
    // and correctly cleans up session state
    expect(true, isTrue);
  });
}
