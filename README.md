# S.O.S. Battery Alarm 🔋

An iOS application that monitors battery level and fires a loud S.O.S. alarm when the battery drops below a user-configured threshold — keeping you safe and never caught off-guard by a dead phone.

---

## Table of Contents

1. [App Overview](#app-overview)
2. [Feature List](#feature-list)
3. [Repository Structure](#repository-structure)
4. [App Store Submission Checklist](#app-store-submission-checklist)
5. [Known Issues & Priority Fixes](#known-issues--priority-fixes)
6. [Development Setup](#development-setup)
7. [Contributing](#contributing)

---

## App Overview

| Item | Detail |
|---|---|
| **App Name** | S.O.S. Battery Alarm |
| **Platform** | iOS 16+ |
| **Language** | Swift 5 / SwiftUI |
| **Xcode Version** | 15+ |
| **Bundle ID** | TBD (set in `project.pbxproj`) |
| **Primary Category** | Utilities |
| **Status** | Pre-submission — finishing touches |

---

## Feature List

### Primary Feature — Battery Alarm
- Monitors device battery level continuously via `UIDevice.current.batteryLevel` / `UIDevice.batteryLevelDidChangeNotification`.
- User sets a low-battery threshold (e.g. 20 %).
- Alarm triggers (sound + vibration + on-screen alert) when battery falls at or below the threshold.
- Alarm can be silenced by the user from the alert dialog.
- Background monitoring via `BGTaskScheduler` / `UIBackgroundModes` (audio / processing).

### Secondary Features
- **Settings** — configure alarm threshold, sound selection, vibration toggle.
- **History Log** — timestamped log of every alarm event.
- **Notifications** — local `UNUserNotificationCenter` push when battery threshold is reached.
- **S.O.S. Signal** — optional Morse-code flashlight (torch) pattern in addition to audio.
- **Widget / Live Activity** — (planned) battery-level glanceable.

---

## Repository Structure

```
04-02-2026-S.O.S.-Battery-Alarm/
├── SOSBatteryAlarm/                  # Xcode project root
│   ├── SOSBatteryAlarm.xcodeproj/
│   ├── SOSBatteryAlarmApp.swift      # @main entry point
│   ├── ContentView.swift
│   ├── BatteryMonitor/
│   │   ├── BatteryMonitor.swift      # Core battery-level logic
│   │   └── AlarmController.swift     # Sound / vibration / notification trigger
│   ├── Views/
│   │   ├── HomeView.swift
│   │   ├── SettingsView.swift
│   │   └── HistoryView.swift
│   ├── Models/
│   │   └── AlarmEvent.swift
│   ├── Resources/
│   │   ├── Assets.xcassets/
│   │   └── Sounds/
│   └── Info.plist
├── SOSBatteryAlarmTests/
├── SOSBatteryAlarmUITests/
├── STRATEGY.md                       # Running project strategy & chat history
├── ASSESSMENT.md                     # Full code scan report & prioritised issue list
├── .gitignore
└── README.md
```

> **Note:** Source files are pending upload from the local Xcode project.

---

## App Store Submission Checklist

- [ ] Bundle ID registered in App Store Connect
- [ ] Privacy Manifest (`PrivacyInfo.xcprivacy`) included and complete
- [ ] All `NSUsageDescription` keys present in `Info.plist`
  - [ ] `NSMicrophoneUsageDescription` (if used)
  - [ ] `UIBackgroundModes` declared (`audio`, `processing`, or `fetch` as needed)
- [ ] App icon set (all required sizes) in `Assets.xcassets`
- [ ] Launch screen configured
- [ ] No use of private APIs
- [ ] Entitlements file correct and signed
- [ ] Background task identifiers registered (`BGTaskSchedulerPermittedIdentifiers`)
- [ ] `UIRequiredDeviceCapabilities` accurate
- [ ] Age rating correctly set (likely 4+)
- [ ] Screenshots prepared for all required device sizes
- [ ] App Review Notes written (explain battery-alarm use-case)
- [ ] TestFlight build submitted and tested
- [ ] Crash-free rate ≥ 99 % on TestFlight
- [ ] Accessibility (VoiceOver) passes basic review
- [ ] Localisation strings (English baseline) complete

---

## Known Issues & Priority Fixes

See [ASSESSMENT.md](./ASSESSMENT.md) for the full prioritised issue list.

| Priority | Area | Issue |
|---|---|---|
| 🔴 P1 | Battery Alarm — Background | Battery monitoring stops when app is backgrounded without proper `UIBackgroundModes` |
| 🔴 P1 | Battery Alarm — Notifications | `UNUserNotificationCenter` permission request missing or not handled |
| 🟠 P2 | Battery Alarm — Sound | `AVAudioSession` category not set to `.playback` — alarm silent on mute switch |
| 🟠 P2 | Info.plist | Missing `UIBackgroundModes` entry |
| 🟡 P3 | Settings | Threshold value not persisted between launches (`UserDefaults` key mismatch) |
| 🟡 P3 | App Store | Privacy Manifest not included |
| 🟢 P4 | General | Deprecation warnings in Xcode 15 build log |

---

## Development Setup

### Requirements
- macOS Ventura 13.5+ or Sonoma 14+
- Xcode 15.2+
- iOS 16+ device or simulator (battery monitoring requires real device for threshold testing)

### Clone & Open
```bash
git clone https://github.com/ArtDirectorNY/04-02-2026-S.O.S.-Battery-Alarm.git
cd 04-02-2026-S.O.S.-Battery-Alarm
open SOSBatteryAlarm/SOSBatteryAlarm.xcodeproj
```

### Build & Test
```bash
xcodebuild -project SOSBatteryAlarm/SOSBatteryAlarm.xcodeproj \
           -scheme SOSBatteryAlarm \
           -destination 'platform=iOS Simulator,name=iPhone 15' \
           build test
```

---

## Contributing

1. Create a branch: `git checkout -b fix/your-description`
2. Make changes following the Prime Directive (one small step at a time).
3. Open a Pull Request against `main`.
4. Reference the relevant STRATEGY.md section in your PR description.
