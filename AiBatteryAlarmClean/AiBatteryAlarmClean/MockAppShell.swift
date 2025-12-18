//
//  MockAppShell.swift
//  AiBatteryAlarmClean
//
//  Created by Jaime Ordonez on 11/23/25.
//

import SwiftUI

struct MockAppShellView: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("Free Battery Alarm")
                .font(.largeTitle)
                .bold()
            ZStack {
                Capsule().fill(Color.gray.opacity(0.25)).frame(height: 40)
                Capsule().fill(Color.green).frame(width: 220, height: 40)
                Text("78% - 82%").bold()
            }
            .padding()

            HStack {
                VStack {
                    Text("Brightness")
                    Slider(value: .constant(0.5))
                    Text("50%")
                }
                VStack {
                    Text("Volume")
                    Slider(value: .constant(0.5))
                    Text("50%")
                }
            }
            .padding()

            Spacer()
        }
        .padding()
        .background(Color(white: 0.06))
    }
}

#if DEBUG
struct MockAppShellView_Previews: PreviewProvider {
    static var previews: some View {
        MockAppShellView()
            .previewDevice(PreviewDevice(rawValue: "iPhone 17 Pro"))
            .previewDisplayName("Mock App Shell - iPhone 17 Pro")
    }
}
#endif
