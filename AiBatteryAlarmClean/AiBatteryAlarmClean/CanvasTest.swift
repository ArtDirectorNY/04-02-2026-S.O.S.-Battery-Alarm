//
//  CanvasTest.swift
//  AiBatteryAlarmClean
//
//  Created by Jaime Ordonez on 11/23/25.
//

import SwiftUI

struct CanvasTestView: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("Canvas Test")
                .font(.largeTitle)
                .padding()
            Text("If you see this in the Canvas, previews are working.")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.12))
    }
}

struct CanvasTestView_Previews: PreviewProvider {
    static var previews: some View {
        CanvasTestView()
            .previewDevice("iPhone 16e")
            .previewDisplayName("iPhone 16e")
    }
}
