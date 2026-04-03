// NotificationManager.swift

import Foundation
import UserNotifications
import UIKit

class NotificationManager: NSObject {
    static let `default` = NotificationManager()

    // Throttle state
    private var lastScheduledDate: Date?
    private var lastScheduledBatteryLevel: Int?
    // Configurable thresholds
    private let minInterval: TimeInterval = 60        // seconds between background notifications
    private let minPercentDelta = 1                   // percent change required to bypass rate limit

    // MARK: - Authorization
    func requestAuthorization() {
        let center = UNUserNotificationCenter.current()
        // Set delegate so we can show banners in foreground
        center.delegate = NotificationManager.default
        print("🔔 NotificationManager: UNUserNotificationCenter.delegate = NotificationManager")

        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            DispatchQueue.main.async {
                if granted {
                    print("Permission granted")
                } else if let error = error {
                    print("Authorization error: \(error.localizedDescription)")
                } else {
                    print("Permission denied")
                }
            }
        }
    }

    // Simple helpers retained for compatibility
    func addNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Battery Alarm"
        content.body = "Battery level is below 20%."
        content.sound = UNNotificationSound.default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "BatteryLowAlert", content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Notification error: \(error.localizedDescription)")
            }
        }
    }

    func removeNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["BatteryLowAlert"])
    }

    // Updated scheduled background notification with throttling and battery-level awareness
    // Adds an optional 'origin' string for diagnostic tracing (default keeps backward compatibility).
    func scheduleBackgroundNotification(title: String, body: String, batteryLevel: Int, origin: String = "unknown") {
        let now = Date()

        // If we've fired recently, suppress new notification unless battery changed enough
        if let lastDate = lastScheduledDate {
            let elapsed = now.timeIntervalSince(lastDate)
            if elapsed < minInterval {
                // If battery level did not change enough, suppress
                if let lastLevel = lastScheduledBatteryLevel {
                    if abs(batteryLevel - lastLevel) < minPercentDelta {
                        print("⏱️ Suppressed background notification — only \(Int(elapsed))s since last (min \(Int(minInterval))s) and battery delta < \(minPercentDelta)% (last:\(lastLevel) now:\(batteryLevel)) [from: \(origin)]")
                        return
                    }
                } else {
                    // No last level recorded, but still within interval -> suppress
                    print("⏱️ Suppressed background notification — fired recently (\(Int(elapsed))s < \(Int(minInterval))s) [from: \(origin)]")
                    return
                }
            }
        }

        // Update last fired state
        lastScheduledDate = now
        lastScheduledBatteryLevel = batteryLevel

        let content = UNMutableNotificationContent()
        content.title = title

        // Append the requested suffix to body so user sees "(per your settings)"
        let bodyWithSuffix = body + " (per your settings)."
        content.body = bodyWithSuffix
        content.sound = .default

        // Use a stable identifier so pending identical notifications will be replaced, avoiding queue bloat
        let identifier = "BackgroundBatteryAlert"

        // Trigger immediately (short delay to let system show banner even when app backgrounds)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Background notification error: \(error.localizedDescription) [from: \(origin)]")
            } else {
                print("✅ Background notification scheduled: \(title) (battery: \(batteryLevel)%) [from: \(origin)]")
            }
        }
    }

    // Keep the old signature for compatibility if some code calls it without battery level.
    // It simply forwards with batteryLevel = -1 (will still be throttled by time).
    func scheduleBackgroundNotification(title: String, body: String) {
        scheduleBackgroundNotification(title: title, body: body, batteryLevel: -1, origin: "unknown")
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension NotificationManager: UNUserNotificationCenterDelegate {
    // When a notification arrives while the app is in the foreground, tell the system to show a banner and play sound.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler:
                                @escaping (UNNotificationPresentationOptions) -> Void) {
        // Ask system to present banner and play sound even when app is foregrounded
        print("🔔 NotificationManager: willPresent called — asking system to show banner/sound")
        completionHandler([.banner, .sound, .list])
    }

    // (Optional) handle user response if you want to react when the user taps the banner.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        print("🔔 NotificationManager: didReceive response — id: \(response.notification.request.identifier)")
        completionHandler()
    }
}
