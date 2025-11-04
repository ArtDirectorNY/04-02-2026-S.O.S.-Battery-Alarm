import Foundation
import UIKit
import Combine
import SwiftUI

class BatteryMonitor: ObservableObject {
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
        UIDevice.current.isBatteryMonitoringEnabled = true
        batteryObserver = Timer.publish(every: 5.0, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                let actual = UIDevice.current.batteryLevel
                let activeLevel = self.useOverride ? self.overrideLevel : actual
                self.batteryLevel = activeLevel

                print("🟢 BatteryMonitor initialized")
                print("🔍 Actual battery level: \(Int(actual * 100))%")
                if self.useOverride {
                    print("🧪 Using override level: \(Int(self.overrideLevel * 100))%")
                }

                self.evaluateThresholds()
            }
    }

    // MARK: - Threshold Evaluation
    func evaluateThresholds() {
        // Alarm handling moved to webview - this function does nothing now
    }
   /* func evaluateThresholds() {
        let level = batteryLevel
        let low = lowThreshold
        let high = highThreshold

        print("🔧 Low threshold: \(Int(low * 100))%, High threshold: \(Int(high * 100))%")

        if level <= low {
            print("⚠️ Battery is below low threshold")
            if !alarmActive {
                alarmActive = true
                AlarmManager.shared.startAlarm()
                print("🚨 Low alarm triggered")
            }
        } else if level >= high {
            print("⚠️ Battery is above high threshold")
            if !alarmActive {
                alarmActive = true
                AlarmManager.shared.startAlarm()
                print("🚨 High alarm triggered")
            }
        } else {
            if alarmActive {
                alarmActive = false
                AlarmManager.shared.stopAlarm()
                print("✅ Alarm cleared")
            }
        }
    }*/

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
