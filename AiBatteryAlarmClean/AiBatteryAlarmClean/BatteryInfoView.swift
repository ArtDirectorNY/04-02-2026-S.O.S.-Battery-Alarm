//  BatteryInfoView.swift
//  AiBatteryAlarmClean
//
//  Created by Jaime Ordonez on 11/7/25.
//

import SwiftUI
import UIKit

// Simple in-app Battery info view (App-Store-safe).
// Shows battery level, charging state, and an optional persisted override.
// Provides a button to open system Battery settings (DEBUG tries App-Prefs; Release uses public App Settings).
struct BatteryInfoView: View {
    @Environment(\.presentationMode) private var presentationMode

    @State private var batteryLevelPercent: Int = -1
    @State private var chargingState: String = "Unknown"
    @State private var batteryHealthString: String = "N/A"

    private func updateValues() {
        let device = UIDevice.current
        if device.batteryLevel >= 0 {
            batteryLevelPercent = Int(round(device.batteryLevel * 100))
        } else {
            batteryLevelPercent = -1
        }

        switch device.batteryState {
        case .charging: chargingState = "Charging"
        case .full:     chargingState = "Full"
        case .unplugged:chargingState = "Not Charging"
        case .unknown:  chargingState = "Unknown"
        @unknown default: chargingState = "Unknown"
        }

        #if targetEnvironment(simulator)
        batteryHealthString = "95" // simulator mock
        #else
        if let override = UserDefaults.standard.object(forKey: "batteryHealthOverride") as? Int,
           (1...100).contains(override) {
            batteryHealthString = "\(override)"
        } else if device.batteryLevel >= 0 {
            batteryHealthString = "\(max(50, min(100, Int(device.batteryLevel * 100))))"
        } else {
            batteryHealthString = "N/A"
        }
        #endif
    }

    private func openSystemBatterySettings() {
        let appSettings = URL(string: UIApplication.openSettingsURLString)!

        #if DEBUG
        // Try deep link first in DEBUG for local testing (unofficial)
        let candidates = [
            "App-Prefs:root=BATTERY&path=BATTERY_USAGE",
            "App-Prefs:root=BATTERY",
            "App-Prefs:root=Battery",
            "prefs:root=BATTERY"
        ]
        for s in candidates {
            if let url = URL(string: s), UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
                return
            }
        }
        // If none worked, fall back:
        UIApplication.shared.open(appSettings, options: [:], completionHandler: nil)
        #else
        // Release: only open public app settings
        UIApplication.shared.open(appSettings, options: [:], completionHandler: nil)
        #endif
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Battery Status")) {
                    HStack {
                        Text("Battery Level")
                        Spacer()
                        Text(batteryLevelPercent >= 0 ? "\(batteryLevelPercent)%" : "Unknown")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Charging State")
                        Spacer()
                        Text(chargingState).foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Battery Health (est.)")
                        Spacer()
                        Text(batteryHealthString + (batteryHealthString == "N/A" ? "" : "%"))
                            .foregroundColor(.secondary)
                    }
                }

                Section {
                    Button(action: openSystemBatterySettings) {
                        HStack {
                            Text("Open System Battery Settings")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                    }

                    // New: Clear any persisted batteryHealthOverride (useful for removing stale test values)
                    Button(action: {
                        UserDefaults.standard.removeObject(forKey: "batteryHealthOverride")
                        updateValues()
                        print("🔄 Cleared batteryHealthOverride from UserDefaults")
                    }) {
                        HStack {
                            Text("Clear Battery Health Override")
                                .foregroundColor(.red)
                            Spacer()
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                    }
                }

                Section(footer: Text("Note: system Battery settings cannot be embedded in-app. This view provides the same info and a shortcut to Settings.")) { EmptyView() }
            }
            .navigationBarTitle("Battery Info", displayMode: .inline)
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
            .onAppear {
                UIDevice.current.isBatteryMonitoringEnabled = true
                updateValues()
                NotificationCenter.default.addObserver(forName: UIDevice.batteryLevelDidChangeNotification, object: nil, queue: .main) { _ in
                    updateValues()
                }
                NotificationCenter.default.addObserver(forName: UIDevice.batteryStateDidChangeNotification, object: nil, queue: .main) { _ in
                    updateValues()
                }
            }
            .onDisappear {
                NotificationCenter.default.removeObserver(self)
            }
        }
    }
}
