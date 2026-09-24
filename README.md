# Shiei Exam Mobile • High-Security Kiosk & Proctor Client

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?style=for-the-badge&logo=dart&logoColor=white)](https://dart.dev)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS-green?style=for-the-badge)](https://flutter.dev)
[![License](https://img.shields.io/badge/License-Proprietary-blue?style=for-the-badge)](LICENSE)

> **市衛 • 誠実を守り、規律ある試験へ。**  
> *Project SHIEI • Menjaga Integritas, Mengawal Kejujuran Ujian.*  
> Official Mascot: **Shiei-kun (市衛くん)**

---

## 📌 Overview

**Shiei Exam Mobile** is the dedicated student examination and on-the-go teacher proctoring application for **Project SHIEI**. Built with Flutter, it operates as a hardened **Kiosk Application** that prevents academic fraud by actively enforcing device integrity, blocking multitasking, and providing proctors with immediate mobile control.

---

## 🛡️ Anti-Cheating & Kiosk Security Suite

- **Hardened Kiosk Mode**: Screen pinning and full-screen enforcement to prevent switching apps or accessing home navigation during exams.
- **Anti-Overlay & Floating Window Blocker**: Detects and neutralizes third-party floating assistance widgets, calculators, and screen recorders.
- **Hardware & Peripherals Integrity**:
  - Blocks active Bluetooth audio/headsets.
  - Detects active phone calls and suppresses background interruptions.
  - Restricts USB debugging and ADB developer bridge tampering.
  - Monitored battery status and screen brightness diagnostics before exam entry.
- **Emergency Sirens & Visual Flashers**: Immediate audio alarm and red strobe banner triggered if a violation or unauthorized app escape is attempted.
- **Dual-Role Experience**:
  - **Student Mode**: Distraction-free exam runner with automatic local state caching and offline answer resilience.
  - **Teacher / Proctor Mode**: Complete mobile proctoring hub featuring QR scanner unblock, class transfers, instant time adjustments, and live student progress tracking.
- **Universal Form Factor Support**: Optimized for standard smartphones, compact foldables/covers, and large tablets (`maxWidth: 600dp` sheets and adaptive grid layouts).

---

## 🛠️ Requirements & Tech Stack

- **Flutter SDK**: `^3.24.0`
- **Dart SDK**: `^3.5.0`
- **Target OS**: Android 7.0+ (API 24+) / iOS 14.0+
- **Key Packages**:
  - `http` & `dio` for secure REST communications
  - `qr_code_scanner` / `mobile_scanner` for rapid student unblocking
  - `screen_protector` for anti-screenshot & secure view rendering
  - `wakelock_plus` for continuous display preservation

---

## 📦 Getting Started

### 1. Prerequisites
Ensure you have Flutter installed and configured:
```bash
flutter doctor
```

### 2. Install Dependencies
```bash
cd mobile-app
flutter pub get
```

### 3. Run on Connected Device
```bash
# List available devices
flutter devices

# Run in debug mode
flutter run -d <DEVICE_ID>
```

### 4. Build Release Bundle
```bash
# Build Android APK (Fat APK)
flutter build apk --release

# Build Split Per-ABI APKs (Smaller downloads)
flutter build apk --split-per-abi --release

# Build Android App Bundle (for Google Play / MDM)
flutter build appbundle --release
```

---

## 📐 Project Structure

```
lib/
├── core/                 # Auth tokens, API client, security services & network layer
├── features/
│   ├── exam_list/        # Student exam dashboard & readiness diagnostics
│   ├── exam_player/      # Secure exam runner with question timer & auto-save
│   ├── lockout/          # Violation alarm screen & emergency unblock handler
│   ├── onboarding/       # Permission gating guide (Notification & Install gates)
│   ├── settings/         # App diagnostics, sound testing & server configurations
│   ├── teacher_monitor/  # Mobile proctor command center (live tracking, QR, classes)
│   └── tour/             # Guided spotlight walkthrough for new teachers & students
└── shared/
    ├── theme/            # Shiei Design System (dark & light tokens)
    └── widgets/          # Responsive bottom sheets, selectors & custom UI controls
```

---

## 👨‍💻 Author & Maintainer

**Ibrahim Muliatama** ([@bimbap](https://github.com/bimbap))  
*Junior Cloud Engineer & Modern Web Developer*
