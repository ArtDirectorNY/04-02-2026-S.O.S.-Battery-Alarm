// AlarmModalView.swift

import SwiftUI

struct AlarmModalView: View {
    @EnvironmentObject var monitor: BatteryMonitor

    // Helper to create readable percent text
    private var batteryPercentText: String {
        let pct = Int(round(monitor.batteryLevel * 100))
        return "\(pct)%"
    }

    // Determine if this is a HIGH alarm (device charging) — best-effort
    private var isHighAlarm: Bool {
        let state = UIDevice.current.batteryState
        return state == .charging || state == .full
    }

    private var titleText: String {
        isHighAlarm ? "🔋 Battery High!" : "🔋 Battery Low"
    }

    private var bodyText: String {
        if isHighAlarm {
            return "Sufficiently charged (per your settings). Unplug the device. (Battery: \(batteryPercentText))"
        } else {
            return "Battery is at \(batteryPercentText), consider charging. See settings."
        }
    }

    var body: some View {
        // Full-screen dimmed background with centered card
        GeometryReader { geom in
            VStack {
                Spacer()
                VStack(spacing: 16) {
                    Text(titleText)
                        .font(.headline)
                        .multilineTextAlignment(.center)

                    Text(bodyText)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 12) {
                        Button(action: dismissAction) {
                            Text("Dismiss")
                                .bold()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color(UIColor.systemGray5))
                                .cornerRadius(8)
                        }

                        Button(action: openSettings) {
                            Text("Open Settings")
                                .bold()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.accentColor)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: min(420, geom.size.width - 40))
                .background(VisualEffectBlur(blurStyle: .systemMaterial))
                .cornerRadius(14)
                .shadow(radius: 20)
                .padding(.bottom, 36)
            }
            .frame(width: geom.size.width, height: geom.size.height)
            .background(
                Color.black.opacity(0.35)
                    .edgesIgnoringSafeArea(.all)
                    .onTapGesture {
                        // Tapping outside dismisses (but leaves notifications intact)
                        dismissAction()
                    }
            )
        }
    }

    private func dismissAction() {
        // Stop native audio/haptics but keep scheduled notifications (so background banners persist)
        AlarmManager.shared.stopAlarm()
        DispatchQueue.main.async {
            monitor.alarmActive = false
        }
    }

    private func openSettings() {
        // Open app Settings so user can adjust notification/behavior
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }
}

// Minimal UIBlur/VisualEffect for cross-version compatibility
// (keeps the modal consistent with iOS materials)
struct VisualEffectBlur: UIViewRepresentable {
    var blurStyle: UIBlurEffect.Style

    func makeUIView(context: Context) -> UIVisualEffectView {
        return UIVisualEffectView(effect: UIBlurEffect(style: blurStyle))
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: blurStyle)
    }
}
