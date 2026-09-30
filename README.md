# Shiei Exam Mobile • High-Security Kiosk & Proctor Client

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?style=for-the-badge&logo=dart&logoColor=white)](https://dart.dev)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS-green?style=for-the-badge)](https://flutter.dev)
[![License](https://img.shields.io/badge/License-Proprietary-blue?style=for-the-badge)](LICENSE)

> **市衛 • 誠実を守り、規律ある試験へ。**  
> *Project SHIEI • Menjaga Integritas, Mengawal Kejujuran Ujian.*  

---

## 📌 Overview

**Shiei Exam Mobile** is the dedicated student examination and on-the-go teacher proctoring application for **Project SHIEI**. Built with Flutter, it operates as a hardened **Kiosk Application** that prevents academic fraud by actively enforcing device integrity, blocking multitasking, and providing proctors with immediate mobile control.

---

## 🛡️ Core Capabilities & Architecture

- **Dedicated Kiosk Examination Shell**: Full-screen containment and session locking designed to prevent unintended disruptions and maintain a focused testing environment.
- **Hardware & Environment Verification**: Comprehensive pre-flight system diagnostics to verify device readiness before exam authorization.
- **Real-Time Proctor Coordination**: Instant mobile supervision tools for teachers, including QR-based verification, live schedule adjustments, and student progress monitoring.
- **Offline Session Resilience**: Intelligent local answer caching ensuring exam continuity even in intermittent or disrupted school connectivity conditions.
- **Universal Cross-Platform Experience**: Responsive layouts tailored for smartphones, compact foldables, and educational tablet workstations.

---

## 🛠️ System Requirements

- **Flutter SDK**: `^3.24.0`
- **Dart SDK**: `^3.5.0`
- **Target Platforms**: Android 7.0+ (API 24+) / iOS 14.0+

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

## 👨‍💻 Author

**Ibrahim Muliatama** ([@bimbap](https://github.com/bimbap))
