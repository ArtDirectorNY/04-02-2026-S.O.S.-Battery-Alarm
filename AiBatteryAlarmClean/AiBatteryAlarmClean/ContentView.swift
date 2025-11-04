import SwiftUI

struct ContentView: View {
    @StateObject private var monitor = BatteryMonitor()
    
    var body: some View {
        PromoWebView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .edgesIgnoringSafeArea(.all)
    }
}
/*import SwiftUI
import StoreKit

struct ContentView: View {
    
    @StateObject private var monitor = BatteryMonitor()
    @FocusState private var focusedField: Field?

    @State private var lowInput: String = "\(Int(BatteryMonitor.defaultLow * 100))"
    @State private var highInput: String = "\(Int(BatteryMonitor.defaultHigh * 100))"
    @State private var lowError: String?
    @State private var highError: String?
    @State private var purchaseConfirmed: Bool = false

    enum Field {
        case low, high
    }

    var batteryColor: Color {
        let level = monitor.batteryLevel
        if level <= monitor.lowThreshold { return .red }
        if level >= monitor.highThreshold { return .orange }
        return .green
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("🔋 Battery Level")
                .font(.title2)

            ProgressView(value: monitor.batteryLevel)
                .progressViewStyle(.linear)
                .tint(batteryColor)
                .frame(height: 20)

            Text("\(Int(monitor.batteryLevel * 100))%")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("Low Battery Alarm (%)")
                TextField("0–100", text: $lowInput)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                    .focused($focusedField, equals: .low)
                    .onChange(of: lowInput) { validateLow() }
                if let error = lowError {
                    Text(error).foregroundColor(.red).font(.caption)
                }
                Text("\(Int(monitor.lowThreshold * 100))%")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("High Battery Alarm (%)")
                TextField("0–100", text: $highInput)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                    .focused($focusedField, equals: .high)
                    .onChange(of: highInput) { validateHigh() }
                if let error = highError {
                    Text(error).foregroundColor(.red).font(.caption)
                }
                Text("\(Int(monitor.highThreshold * 100))%")
            }

            // BUTTONS SECTION - FIXED
            VStack(spacing: 12) {
                Button("Stop Alarm") {
                    monitor.stopMonitoring()
                    focusedField = nil
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)

                Button("Reset Settings") {
                    monitor.resetSettings()
                    lowInput = "\(Int(BatteryMonitor.defaultLow * 100))"
                    highInput = "\(Int(BatteryMonitor.defaultHigh * 100))"
                    lowError = nil
                    highError = nil
                    focusedField = nil
                    print("🔄 Settings reset to default")
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.red)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .padding(.horizontal)

            PromoWebView()
                .frame(height: 240)
                .cornerRadius(10)
        }
        .padding()
    }

    func validateLow() {
        if let value = Int(lowInput), value >= 0, value <= 100 {
            monitor.lowThreshold = Float(value) / 100
            lowError = nil
        } else {
            lowError = "Enter a number between 0 and 100"
        }
    }

    func validateHigh() {
        if let value = Int(highInput), value >= 0, value <= 100 {
            monitor.highThreshold = Float(value) / 100
            highError = nil
        } else {
            highError = "Enter a number between 0 and 100"
        }
    }

    func simulatePurchase() {
        print("🛒 Simulated purchase triggered")
        purchaseConfirmed = true
    }
}
*/
