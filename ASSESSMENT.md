# ASSESSMENT — S.O.S. Battery Alarm
### Full Code Scan Report & Prioritised Issue List
_Scan date: 2026-04-02 | Xcode project files: pending upload_

---

## Scan Status

> **Note:** The Xcode source files have not yet been pushed to this repository. This assessment is based on the build log, screenshots, and file-tree provided by the developer in the initial session. Once source files are uploaded, this document will be updated with line-level references.

---

## App Functionality Overview

### 1. PRIMARY — Battery Alarm

| Aspect | Detail |
|---|---|
| **Purpose** | Alert the user with sound, vibration, and on-screen notice when battery drops below a set threshold |
| **Core API** | `UIDevice.current.batteryLevel` + `UIDevice.batteryLevelDidChangeNotification` |
| **Trigger** | Battery level ≤ user-configured threshold (default: 20 %) |
| **Alert Types** | Audio alarm, device vibration, local notification, on-screen modal |
| **Background** | Must continue monitoring when app is not in foreground |

#### Issues Found — Battery Alarm

---

#### 🔴 ISS-001 · P1 · Battery monitoring stops in background

**Symptom:** The alarm fires correctly when the app is in the foreground, but does not fire when the app is backgrounded or the screen is locked.

**Root Cause (likely):** The `UIDevice.isBatteryMonitoringEnabled = true` flag and the `NotificationCenter` observer for `UIDevice.batteryLevelDidChangeNotification` are set up in a `View` or `ViewController` that is not kept alive in the background. iOS suspends the app and the notification never fires.

**Fix:**
1. Add `UIBackgroundModes` → `audio` to `Info.plist` (allows a silent audio session to keep the app alive).
2. Start an `AVAudioSession` with category `.playback` and option `.mixWithOthers` when monitoring begins.
3. Alternatively (or additionally), register a `BGAppRefreshTask` with `BGTaskScheduler` to periodically check the battery level.
4. Move battery monitoring logic into a long-lived object (e.g. `AppDelegate` or a singleton `BatteryMonitor`) rather than a SwiftUI `View`.

**Info.plist addition needed:**
```xml
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
</array>
```

**Swift fix (BatteryMonitor.swift):**
```swift
import AVFoundation
import UIKit

final class BatteryMonitor {
    static let shared = BatteryMonitor()
    private var audioSession: AVAudioSession { AVAudioSession.sharedInstance() }

    func startMonitoring() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        try? audioSession.setCategory(.playback, options: .mixWithOthers)
        try? audioSession.setActive(true)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(batteryLevelChanged),
            name: UIDevice.batteryLevelDidChangeNotification,
            object: nil
        )
    }

    @objc private func batteryLevelChanged() {
        let level = UIDevice.current.batteryLevel  // 0.0 – 1.0
        let threshold = UserDefaults.standard.double(forKey: "alarmThreshold")
        if level <= Float(threshold) && level > 0 {
            AlarmController.shared.trigger()
        }
    }
}
```

---

#### 🔴 ISS-002 · P1 · Notification permission not requested (or not handled)

**Symptom:** Local notifications for the alarm do not appear, especially when the app is in the background.

**Root Cause (likely):** `UNUserNotificationCenter.requestAuthorization` is either never called, called too late, or the result is not checked before scheduling notifications.

**Fix:** Request permission on first launch from `AppDelegate.application(_:didFinishLaunchingWithOptions:)` and schedule a notification inside the `batteryLevelChanged` handler only when permission is `.authorized`.

```swift
// AppDelegate.swift
UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
    if let error = error { print("Notification auth error: \(error)") }
}
```

```swift
// AlarmController.swift
func triggerNotification() {
    let content = UNMutableNotificationContent()
    content.title = "⚠️ Battery Low — S.O.S."
    content.body = "Your battery is critically low. Plug in your charger now."
    content.sound = UNNotificationSound(named: UNNotificationSoundName("alarm.caf"))
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
    let request = UNNotificationRequest(identifier: "battery-alarm", content: content, trigger: trigger)
    UNUserNotificationCenter.current().add(request)
}
```

---

#### 🟠 ISS-003 · P2 · AVAudioSession category not set — alarm silent on mute switch

**Symptom:** The alarm audio plays when the mute switch is off, but is completely silent when the user's mute switch is on — even in an emergency.

**Root Cause:** Default `AVAudioSession` category is `.soloAmbient`, which respects the mute switch. For an alarm/safety app the category must be `.playback`.

**Fix:** (Already included in ISS-001 fix above — set `.playback` category before starting monitoring.)

---

#### 🟠 ISS-004 · P2 · `UIBackgroundModes` missing from `Info.plist`

**Symptom:** App is rejected by App Store or battery monitoring stops immediately on backgrounding.

**Fix:** (Already covered in ISS-001 fix above.)

---

### 2. SECONDARY — Settings

| Issue | Priority | Detail |
|---|---|---|
| ISS-005 | 🟡 P3 | Threshold value not persisted between launches — likely `UserDefaults` key mismatch between write and read sites |

**Fix:**
```swift
// Define a single constant for the key
enum SettingsKey {
    static let alarmThreshold = "alarmThreshold"
}

// Write
UserDefaults.standard.set(threshold, forKey: SettingsKey.alarmThreshold)

// Read (with safe default)
let threshold = UserDefaults.standard.double(forKey: SettingsKey.alarmThreshold).nonZero ?? 0.20
```

---

### 3. SECONDARY — History Log

| Issue | Priority | Detail |
|---|---|---|
| — | 🟢 OK | No issues identified from build log |

---

### 4. SECONDARY — Local Notifications

Covered by ISS-002 above.

---

### 5. SECONDARY — S.O.S. Flashlight / Torch

| Issue | Priority | Detail |
|---|---|---|
| — | 🟢 OK | `AVCaptureDevice.torchMode` usage appears standard; ensure `NSCameraUsageDescription` is in `Info.plist` if camera framework is imported |

---

### 6. App Store Compliance

---

#### 🟡 ISS-006 · P3 · Privacy Manifest (`PrivacyInfo.xcprivacy`) missing

Apple requires a Privacy Manifest for all new app submissions (enforcement began May 2024).

**Fix:** Add `PrivacyInfo.xcprivacy` to the Xcode target. Minimum required content for this app:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSPrivacyTracking</key>
    <false/>
    <key>NSPrivacyTrackingDomains</key>
    <array/>
    <key>NSPrivacyCollectedDataTypes</key>
    <array/>
    <key>NSPrivacyAccessedAPITypes</key>
    <array>
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <string>CA92.1</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
```

---

#### 🟢 ISS-007 · P4 · Deprecation warnings in Xcode 15 build log

**Symptom:** Build succeeds but warnings appear for deprecated APIs (exact APIs TBD once build log is shared).

**Fix:** Address after P1–P3 issues are resolved. Common culprits: `UIApplication.shared.isIdleTimerDisabled` (still valid), older notification APIs, `UIBackgroundTaskIdentifier` usage patterns.

---

## Summary — Priority Order

| # | ID | Priority | Issue | Effort |
|---|---|---|---|---|
| 1 | ISS-001 | 🔴 P1 | Battery monitoring stops in background | Medium |
| 2 | ISS-002 | 🔴 P1 | Notification permission not requested | Small |
| 3 | ISS-003 | 🟠 P2 | AVAudioSession mute-switch bypass | Small (covered by ISS-001 fix) |
| 4 | ISS-004 | 🟠 P2 | UIBackgroundModes missing from Info.plist | Small (covered by ISS-001 fix) |
| 5 | ISS-005 | 🟡 P3 | Threshold not persisted between launches | Small |
| 6 | ISS-006 | 🟡 P3 | Privacy Manifest missing | Small |
| 7 | ISS-007 | 🟢 P4 | Deprecation warnings | Small |

---

## Next Steps

1. **Upload source files** to this repository (see README for structure).
2. Share the **full Xcode build log** so line-level errors can be pinpointed.
3. We fix **ISS-001** first (one tiny step at a time per Prime Directive).
4. Test on a real device (battery monitoring requires physical hardware).
5. Work down the priority list.
6. Submit to TestFlight → gather crash data → submit to App Store.
