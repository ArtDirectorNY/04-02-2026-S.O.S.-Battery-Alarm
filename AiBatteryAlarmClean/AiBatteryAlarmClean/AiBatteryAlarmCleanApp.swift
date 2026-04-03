//  AiBatteryAlarmCleanApp.swift
//  AiBatteryAlarmClean
//
// AiBatteryAlarmCleanApp.swift
//  Created by Jaime Ordonez on 10/6/25.
/*
 Previous history retained in comments in original file.
*/

import SwiftUI
import UserNotifications

@main
struct AiBatteryAlarmCleanApp: App {
    // Single shared BatteryMonitor for the app lifecycle
    @StateObject private var monitor = BatteryMonitor()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(monitor)
                .onAppear {
                    // Wire the UNUserNotificationCenter delegate so foreground banners are presented.
                    UNUserNotificationCenter.current().delegate = NotificationDelegate.shared

                    // Request notification permission early so background/foreground banners can be shown.
                    NotificationManager.default.requestAuthorization()
                }
        }
    }
}
