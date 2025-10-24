//
//  NeonStyle.swift
//  KaiKlok
//
//  Created by BJ Klock on 9/11/25.
//

import SwiftUI

struct BackgroundView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    .black,
                    Color.cyan.opacity(0.28),
                    Color.blue.opacity(0.22),
                    .black
                ],
                startPoint: .top, endPoint: .bottom
            )
            RadialGradient(
                colors: [Color.cyan.opacity(0.18), .clear],
                center: .center, startRadius: 10, endRadius: 420
            )
            .blendMode(.screen)
        }
        .ignoresSafeArea()
    }
}
