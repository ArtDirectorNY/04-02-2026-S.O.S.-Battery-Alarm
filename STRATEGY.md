# STRATEGY — S.O.S. Battery Alarm
### Running Project Strategy & Chat History
_Last updated: 2026-04-02_

---

## Prime Directive

> Work on **one tiny step at a time**. Do not skip ahead. Confirm each step before moving to the next. Keep this document updated as a living record so context is never lost between sessions.

---

## Session Log

### Session 1 — 2026-04-02 (Repository Bootstrap)

**Goal:** Create the GitHub repository, set up the file structure, perform a full code scan, and produce a prioritised issue report.

**Steps Completed:**
- [x] Created new GitHub repository: `04-02-2026-S.O.S.-Battery-Alarm`
- [x] Initial commit with `README.md`
- [x] Added `.gitignore` for Xcode / iOS project
- [x] Expanded `README.md` with full project overview, feature list, and App Store checklist
- [x] Created `STRATEGY.md` (this file) — running project log
- [x] Created `ASSESSMENT.md` — full scan report with prioritised issue list

**Steps Pending (awaiting source-file upload):**
- [ ] User uploads Xcode project source files to repository
- [ ] Re-run assessment against actual source code
- [ ] Fix P1 issues (battery monitoring in background, notification permission)
- [ ] Fix P2 issues (AVAudioSession, Info.plist)
- [ ] Fix P3 issues (UserDefaults persistence, Privacy Manifest)
- [ ] Fix P4 issues (deprecation warnings)
- [ ] Submit to TestFlight for testing
- [ ] Final App Store submission

**Questions for User (to be answered before proceeding):**
1. What is the exact **Bundle ID** for the app?
2. What is the **minimum iOS version** you are targeting?
3. Is the alarm sound a **custom audio file** or a system sound?
4. Does the app use **Background Audio** or **Background App Refresh** (or both)?
5. Have you already created the app record in **App Store Connect**?
6. Do you want to support **iPad**, or iPhone-only?
7. Is there a **Privacy Manifest** (`PrivacyInfo.xcprivacy`) already in the project?
8. What **Xcode version** are you building with? (paste the full build log when ready)

---

## Architecture Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Language | Swift 5 / SwiftUI | Modern, App Store preferred |
| Battery Monitoring | `UIDevice.batteryLevelDidChangeNotification` | Official API, no private API risk |
| Background Execution | `UIBackgroundModes: audio` + `BGTaskScheduler` | Required for alarm while backgrounded |
| Notifications | `UNUserNotificationCenter` | Only App-Store-compliant local notification API |
| Persistence | `UserDefaults` + optional `CoreData` for history | Lightweight, no entitlement needed |

---

## Issue Tracker

| ID | Priority | Status | Description |
|---|---|---|---|
| ISS-001 | 🔴 P1 | Open | Battery monitoring stops when app is backgrounded |
| ISS-002 | 🔴 P1 | Open | Notification permission request missing / not handled |
| ISS-003 | 🟠 P2 | Open | `AVAudioSession` category not set — alarm silent on mute |
| ISS-004 | 🟠 P2 | Open | `UIBackgroundModes` missing from `Info.plist` |
| ISS-005 | 🟡 P3 | Open | Threshold not persisted between launches |
| ISS-006 | 🟡 P3 | Open | Privacy Manifest (`PrivacyInfo.xcprivacy`) not included |
| ISS-007 | 🟢 P4 | Open | Deprecation warnings in Xcode 15 build log |

---

## Reference Links

- [Apple — Energy Efficiency Guide for iOS Apps](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/EnergyGuide-iOS/)
- [UIDevice Battery Notifications](https://developer.apple.com/documentation/uikit/uidevice#1655199)
- [Background Execution — Apple Docs](https://developer.apple.com/documentation/backgroundtasks)
- [UNUserNotificationCenter](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter)
- [AVAudioSession — playback category](https://developer.apple.com/documentation/avfaudio/avaudiosession/category/1616467-playback)
- [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Privacy Manifest Files](https://developer.apple.com/documentation/bundleresources/privacy_manifest_files)
