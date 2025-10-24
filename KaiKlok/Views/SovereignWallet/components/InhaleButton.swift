//
//  InhaleButton.swift
//  KaiKlok
//
//  Created by BJ Klock on 10/15/25.
//

import SwiftUI

struct InhaleButton: View {
    var action: () -> Void
    @State private var isPressed = false

    var body: some View {
        Button(action: {
            withAnimation(.easeIn(duration: 0.2)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeOut(duration: 0.3)) {
                    isPressed = false
                }
                action()
            }
        }) {
            ZStack {
                Circle()
                    .fill(isPressed ? Color.green.opacity(0.3) : Color.green)
                    .frame(width: isPressed ? 72 : 64, height: isPressed ? 72 : 64)
                    .shadow(radius: isPressed ? 4 : 8)

                Image(systemName: "wind") // You may replace with custom glyph
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(.white)
                    .rotationEffect(.degrees(isPressed ? 15 : 0))
            }
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel("Inhale Φ")
    }
}
