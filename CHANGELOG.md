# Changelog

All notable changes to **Shiei Exam Mobile (`shiei_kiosk`)** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.6.0] - 2026-11-15

### Added
- **Guided Voice Call Privacy Shield**: Added an on-demand 10-second call control window (limited to 2 uses per exam session) with exam content privacy blur during active voice calls on Android and iOS.
- **Mobile Proctor Live Call Telemetry**: Added real-time active call duration counters and a dedicated **Log Telpon** audit tab inside student detail views on the mobile proctor dashboard.
- **Per-Incident Violation History**: Upgraded the student exam violation history panel with scrollable incident cards and per-incident unlocker attribution.

### Changed
- **Cross-Platform Kiosk Stability**: Refined Android screen-pinning recovery and iOS Guided Access / screen capture monitoring for smoother transitions and fewer false triggers.
- **Navigation & Clipboard Hygiene**: Strengthened host navigation restrictions and automatic clipboard sanitization at exam start.
- **Empty State & UI Polish**: Updated empty state visuals and responsive layouts on the student exam dashboard.

### Fixed
- Fixed controller lifecycle race conditions during rapid tab switching and screen disposal.
- Fixed proctor student detail modal state synchronization for active call timers.

## [2.5.0] - 2026-11-14

### Added
- **iOS (iPhone & iPad) Kiosk Support**: Initial cross-platform iOS support with native lock-task integration, Dynamic Island and Home Indicator safe-area calibration, and App Switcher privacy protection.
- **In-App Update Routing**: Platform-aware update flow supporting Android APK downloads and iOS Safari release links.

### Changed
- **Teacher Monitor Sync Controls**: Improved manual pause handling and silent refresh throttling to prevent unintended auto-refresh overrides.

## [2.4.0] - 2026-11-12

### Added
- **Unified Mobile Proctor Command Center**: Live student telemetry, room QR code sharing, class management, and instant proctor announcements.
- **Guided Interactive Tour**: Step-by-step spotlight walkthrough for first-time students and proctors.
