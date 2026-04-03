// BatteryMonitor.swift
import Foundation
import UIKit
import Combine
import SwiftUI
import UserNotifications

class BatteryMonitor: ObservableObject {
    // diagnostic instance counter to detect duplicate initializations
    static var instanceCounter: Int = 0

    // MARK: - Default Constants
    static let defaultLow: Float = 0.20
    static let defaultHigh: Float = 0.80
    static let defaultOverride: Float = 0.50

    // MARK: - Persistent Storage
    @AppStorage("lowThreshold") private var lowThresholdRaw: Double = Double(defaultLow)
    @AppStorage("highThreshold") private var highThresholdRaw: Double = Double(defaultHigh)
    @AppStorage("useOverride") var useOverride: Bool = false
    @AppStorage("overrideLevel") private var overrideLevelRaw: Double = Double(defaultOverride)

    // MARK: - Runtime State
    @Published var batteryLevel: Float = UIDevice.current.batteryLevel
    @Published var alarmActive: Bool = false

    private var batteryObserver: AnyCancellable?

    // High-threshold notification re-triggering
    private var lastHighNotificationTs: Date?
    private let highNotificationMinInterval: TimeInterval = 120.0

    // MARK: - Computed Properties
    var lowThreshold: Float {
        get { Float(lowThresholdRaw) }
        set { lowThresholdRaw = Double(newValue) }
    }

    var highThreshold: Float {
        get { Float(highThresholdRaw) }
        set { highThresholdRaw = Double(newValue) }
    }

    var overrideLevel: Float {
        get { Float(overrideLevelRaw) }
        set { overrideLevelRaw = Double(newValue) }
    }

    // MARK: - Initialization
    init() {
        // Diagnostic: count inits so we can detect duplicates
        BatteryMonitor.instanceCounter += 1
        print("🟢 BatteryMonitor initialized #\(BatteryMonitor.instanceCounter)")

        UIDevice.current.isBatteryMonitoringEnabled = true
        batteryObserver = Timer.publish(every: 5.0, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                let actual = UIDevice.current.batteryLevel
                let activeLevel = self.useOverride ? self.overrideLevel : actual
                self.batteryLevel = activeLevel

                print("🔍 Actual battery level: \(Int(actual * 100))%")
                if self.useOverride {
                    print("🧪 Using override level: \(Int(self.overrideLevel * 100))%")
                }

                self.evaluateThresholds()
            }
    }

    // MARK: - Threshold Evaluation
    func evaluateThresholds() {
        // Read raw device battery level and state
        let raw = UIDevice.current.batteryLevel
        guard raw >= 0 else {
            print("⚠️ Battery level unknown (raw = \(raw))")
            return
        }

        // Respect override if enabled, otherwise use actual
        let levelFloat = useOverride ? overrideLevel : raw
        let levelPercent = Int(round(levelFloat * 100))

        let deviceState = UIDevice.current.batteryState
        let isCharging = (deviceState == .charging || deviceState == .full)

        let low = lowThreshold
        let high = highThreshold

        print("🔧 evaluateThresholds: level=\(levelPercent)% (charging=\(isCharging)), low=\(Int(low*100))%, high=\(Int(high*100))%")

        // Safe-zone guard: if not charging and above low, clear any pending or delivered stale notifications
        if !isCharging && levelFloat > low {
            let center = UNUserNotificationCenter.current()
            center.removeAllPendingNotificationRequests()
            center.removeAllDeliveredNotifications()
            lastHighNotificationTs = nil
        }

        // Defensive safeguard:
        // If the device is charging and the measured level is at-or-below the low threshold,
        // always stop the alarm and do not allow any alarm to be started in this tick.
        if isCharging && levelFloat <= low {
            if alarmActive {
                alarmActive = false
                print("✅ Charging and level <= low — stopping alarm (defensive safeguard)")
                AlarmManager.shared.stopAlarm()
            } else {
                print("ℹ️ Charging and level <= low — alarm already not active")
            }
            // Update UI level and return early — do not process further conditions this tick.
            DispatchQueue.main.async {
                self.batteryLevel = levelFloat
            }
            // Reset high notification timer when below low while charging
            lastHighNotificationTs = nil
            return
        }

        // Decide whether alarm should be active under the desired logic:
        // - High (while charging) -> alarm + banner
        // - Low (while not charging) -> banner only (no alarm/haptics)
        var shouldAlarm = false
        var shouldLowBanner = false

        if isCharging {
            if levelFloat >= high {
                shouldAlarm = true  // alarm + banner handled below
            }
        } else {
            if levelFloat <= low {
                shouldLowBanner = true // banner only, no alarm/haptics
            }
        }

        // Update published batteryLevel for UI
        DispatchQueue.main.async {
            self.batteryLevel = levelFloat
        }

        // Transition logic
                if shouldLowBanner {
                    // Banner only (no alarm/haptics)
                    NotificationManager.default.scheduleBackgroundNotification(
                        title: "🔋 Battery Low!",
                        body: "Battery is at \(levelPercent)% - needs charging!",
                        batteryLevel: levelPercent,
                        origin: "BatteryMonitor"
                    )
                    print("✅ Low battery banner (no sound) requested: \(levelPercent)%")

                    // Ensure alarm is off for low condition
                    if alarmActive {
                        alarmActive = false
                        AlarmManager.shared.stopAlarm()
                    }
                    // Clear high notification stamp when not charging
                    if !isCharging { lastHighNotificationTs = nil }

                } else if shouldAlarm && !alarmActive {
                    alarmActive = true
                    print("🚨 Alarm condition met (high while charging) — starting alarm")
                    AlarmManager.shared.startAlarm()

                    NotificationManager.default.scheduleBackgroundNotification(
                        title: "🔋 Battery High!",
                        body: "Battery is at \(levelPercent)% - high level reached (as per your settings)",
                        batteryLevel: levelPercent,
                        origin: "BatteryMonitor"
                    )
                    print("✅ Background notification requested: 🔋 Battery High! (battery: \(levelPercent)%)")

                    // Stamp high-notification time for retrigger window
                    lastHighNotificationTs = Date()

                } else if shouldAlarm && alarmActive && isCharging && levelFloat >= high {
                    // Already alarming for high while charging — re-trigger banner if interval passed
                    let now = Date()
                    if lastHighNotificationTs == nil || now.timeIntervalSince(lastHighNotificationTs!) >= highNotificationMinInterval {
                        NotificationManager.default.scheduleBackgroundNotification(
                            title: "🔋 Battery High!",
                            body: "Battery is at \(levelPercent)% - high level reached (as per your settings)",
                            batteryLevel: levelPercent,
                            origin: "BatteryMonitor"
                        )
                        lastHighNotificationTs = now
                        print("🔁 High battery notification re-triggered (battery: \(levelPercent)%)")
                    }

                } else if !shouldAlarm && alarmActive {
                    alarmActive = false
                    print("✅ Alarm condition cleared — stopping alarm")
                    AlarmManager.shared.stopAlarm()
                    lastHighNotificationTs = nil

                } else {
                    // Safe zone: clear stamps and any pending notifications to avoid stale banners
                    if !isCharging { lastHighNotificationTs = nil }
                    UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
                }
    }

    // MARK: - Manual Stop
    func stopMonitoring() {
        batteryObserver?.cancel()
        AlarmManager.shared.stopAlarm()
        print("🛑 BatteryMonitor stopped")
    }

    // MARK: - Reset Functionality
    func resetSettings() {
        lowThreshold = Self.defaultLow
        highThreshold = Self.defaultHigh
        overrideLevel = Self.defaultOverride
        useOverride = false
        print("🔄 BatteryMonitor settings reset to default")
    }
}
