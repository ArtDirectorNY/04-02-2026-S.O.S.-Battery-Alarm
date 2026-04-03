// ContentView.swift
import SwiftUI

struct ContentView: View {
    // Use the app-level BatteryMonitor provided via environmentObject
    @EnvironmentObject var monitor: BatteryMonitor

    var body: some View {
        PromoWebView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .edgesIgnoringSafeArea(.all)
    }
}

#if DEBUG
import SwiftUI
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(BatteryMonitor())
            .previewDevice(PreviewDevice(rawValue: "iPhone 17 Pro"))
            .previewDisplayName("iPhone 17 Pro")
    }
}
#endif
