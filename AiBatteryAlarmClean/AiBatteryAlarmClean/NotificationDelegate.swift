//
//  NotificationDelegate.swift
//  AiBatteryAlarmClean
//
//  Created by Jaime Ordonez on 12/26/25.
//


import Foundation
import UserNotifications

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    private override init() {
        super.init()
    }

    // When a notification arrives while the app is in the foreground, present it as a banner+sound+badge.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        #if swift(>=5.3)
        if #available(iOS 14.0, *) {
            completionHandler([.banner, .sound, .badge])
        } else {
            completionHandler([.alert, .sound, .badge])
        }
        #else
        completionHandler([.alert, .sound, .badge])
        #endif
    }

    // Optional: handle responses (taps) if you need later
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        // Add handling if you want to route taps into the app
        completionHandler()
    }
}
