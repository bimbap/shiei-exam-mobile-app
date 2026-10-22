import Flutter
import UIKit
import Network
import CallKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterStreamHandler {
  private let lockdownChannelName = "id.shiei/lockdown"
  private let lockdownEventsChannelName = "id.shiei/lockdown_events"

  private var eventSink: FlutterEventSink?
  private var isFlagSecure: Bool = false
  private var isVolumeLockActive: Bool = false
  private var privacyShieldView: UIView?

  private let networkMonitor = NWPathMonitor()
  private var currentNetworkType: String = "wifi"
  private let callObserver = CXCallObserver()

  private var orientationLock = UIInterfaceOrientationMask.portrait

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    setupNetworkMonitoring()
    setupPlatformChannels(controller: controller)
    setupSecurityObservers()

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // MARK: - Platform Channels Setup
  private func setupPlatformChannels(controller: FlutterViewController) {
    let methodChannel = FlutterMethodChannel(name: lockdownChannelName, binaryMessenger: controller.binaryMessenger)
    let eventChannel = FlutterEventChannel(name: lockdownEventsChannelName, binaryMessenger: controller.binaryMessenger)

    eventChannel.setStreamHandler(self)

    methodChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      guard let self = self else { return }

      switch call.method {
      case "exitApp":
        exit(0)

      case "setFlagSecure":
        let enable = (call.arguments as? [String: Any])?["enable"] as? Bool ?? true
        self.isFlagSecure = enable
        result(true)

      case "getNetworkType":
        result(self.currentNetworkType)

      case "isPhoneCallActive":
        let isActive = self.checkIfCallActive()
        result(isActive)

      case "isDeviceRooted":
        result(self.checkJailbreak())

      case "isMultiWindow":
        // iPhones do not support split-screen multitasking; return false
        result(false)

      case "setKioskSystemBarsBlocked", "enterLockTask":
        if #available(iOS 12.2, *) {
          UIAccessibility.requestGuidedAccessSession(enabled: true) { success in
            result(success)
          }
        } else {
          result(UIAccessibility.isGuidedAccessEnabled)
        }

      case "exitLockTask":
        if #available(iOS 12.2, *) {
          UIAccessibility.requestGuidedAccessSession(enabled: false) { success in
            result(success)
          }
        } else {
          result(true)
        }

      case "isLockTaskActive":
        result(UIAccessibility.isGuidedAccessEnabled)

      case "lockOrientationPortrait":
        self.orientationLock = .portrait
        UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
        result(true)

      case "unlockOrientation":
        self.orientationLock = .allButUpsideDown
        result(true)

      case "forceMaxVolume":
        self.setVolumeHigh()
        result(true)

      case "startVolumeLock":
        self.isVolumeLockActive = true
        self.setVolumeHigh()
        result(true)

      case "stopVolumeLock":
        self.isVolumeLockActive = false
        result(true)

      case "setOverlayProtection":
        result(true)

      case "syncReminders":
        result(true)

      case "installApkUpdate":
        // Android-specific APK installation; no-op on iOS
        result(false)

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // MARK: - FlutterStreamHandler (Events)
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    self.eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    self.eventSink = nil
    return nil
  }

  // MARK: - Security & Anti-Cheat Notifications
  private func setupSecurityObservers() {
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(didTakeScreenshot),
      name: UIApplication.userDidTakeScreenshotNotification,
      object: nil
    )

    if #available(iOS 11.0, *) {
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(screenCaptureChanged),
        name: UIScreen.capturedDidChangeNotification,
        object: nil
      )
    }
  }

  @objc private func didTakeScreenshot() {
    eventSink?("screenshot_attempt")
  }

  @objc private func screenCaptureChanged() {
    if #available(iOS 11.0, *) {
      if UIScreen.main.isCaptured {
        eventSink?("screenshot_attempt")
      }
    }
  }

  // MARK: - App Lifecycle & Privacy Shield
  override func applicationWillResignActive(_ application: UIApplication) {
    super.applicationWillResignActive(application)
    if isFlagSecure {
      showPrivacyShield()
      eventSink?("app_resigned_active")
    }
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    hidePrivacyShield()
  }

  private func showPrivacyShield() {
    guard privacyShieldView == nil, let window = self.window else { return }

    let shield = UIView(frame: window.bounds)
    shield.backgroundColor = UIColor(red: 15/255, green: 23/255, blue: 42/255, alpha: 1.0) // Dark slate
    shield.autoresizingMask = [.flexibleWidth, .flexibleHeight]

    let label = UILabel()
    label.text = "市衛 • Sesi Ujian Sedang Berlangsung"
    label.textColor = .white
    label.font = UIFont.systemFont(ofSize: 14, weight: .bold)
    label.textAlignment = .center
    label.translatesAutoresizingMaskIntoConstraints = false

    shield.addSubview(label)
    NSLayoutConstraint.activate([
      label.centerXAnchor.constraint(equalTo: shield.centerXAnchor),
      label.centerYAnchor.constraint(equalTo: shield.centerYAnchor)
    ])

    window.addSubview(shield)
    self.privacyShieldView = shield
  }

  private func hidePrivacyShield() {
    privacyShieldView?.removeFromSuperview()
    privacyShieldView = nil
  }

  // MARK: - Network Monitoring
  private func setupNetworkMonitoring() {
    networkMonitor.pathUpdateHandler = { [weak self] path in
      if path.usesInterfaceType(.wifi) {
        self?.currentNetworkType = "wifi"
      } else if path.usesInterfaceType(.cellular) {
        self?.currentNetworkType = "cellular"
      } else if path.usesInterfaceType(.wiredEthernet) {
        self?.currentNetworkType = "ethernet"
      } else {
        self?.currentNetworkType = "none"
      }
    }
    let queue = DispatchQueue(label: "id.shiei.network_monitor")
    networkMonitor.start(queue: queue)
  }

  // MARK: - Phone Call Detection
  private func checkIfCallActive() -> Bool {
    for call in callObserver.calls {
      if !call.hasEnded {
        return true
      }
    }
    return false
  }

  // MARK: - Jailbreak Detection
  private func checkJailbreak() -> Bool {
    #if targetEnvironment(simulator)
    return false
    #else
    let suspiciousPaths = [
      "/Applications/Cydia.app",
      "/Library/MobileSubstrate/MobileSubstrate.dylib",
      "/bin/bash",
      "/usr/sbin/sshd",
      "/etc/apt",
      "/private/var/lib/apt/",
      "/Applications/Sileo.app",
      "/var/binpack"
    ]

    for path in suspiciousPaths {
      if FileManager.default.fileExists(atPath: path) {
        return true
      }
    }

    // Attempt to write outside sandbox
    let testPath = "/private/shiei_jailbreak_probe.txt"
    do {
      try "probe".write(toFile: testPath, atomically: true, encoding: .utf8)
      try FileManager.default.removeItem(atPath: testPath)
      return true
    } catch {
      // Normal sandbox restriction
    }

    if let url = URL(string: "cydia://package/com.example.package") {
      if UIApplication.shared.canOpenURL(url) {
        return true
      }
    }

    return false
    #endif
  }

  // MARK: - Volume Management
  private func setVolumeHigh() {
    do {
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      // Audio session activation error handling
    }
  }

  override func application(
    _ application: UIApplication,
    supportedInterfaceOrientationsFor window: UIWindow?
  ) -> UIInterfaceOrientationMask {
    return orientationLock
  }
}
