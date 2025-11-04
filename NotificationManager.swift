import Foundation
import UserNotifications

class NotificationManager {
    static let `default` = NotificationManager()

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("Permission granted")
            } else if let error = error {
                print("Authorization error: \(error.localizedDescription)")
            }
        }
    }

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
    func scheduleBackgroundNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        // Trigger immediately
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "BackgroundBatteryAlert", content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ Background notification error: \(error.localizedDescription)")
            } else {
                print("✅ Background notification scheduled: \(title)")
            }
        }
    }
}
