//
//  BalanceCard.swift
//  KaiKlok
//
//  Created by BJ Klock on 10/15/25.
//

import SwiftUI

struct BalanceCard: View {
    let phi: Double
    let usd: Double
    var pulse: Int? = nil
    var chakraDay: String? = nil

    var body: some View {
        VStack(spacing: 8) {
            Text("Current Balance")
                .font(.title3)
                .foregroundColor(.secondary)

            Text("Φ \(String(format: "%.6f", phi))")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            Text("≈ $\(String(format: "%.2f", usd))")
                .foregroundColor(.gray)

            if let pulse = pulse, let chakra = chakraDay {
                Text("Last Pulse: \(pulse) · \(chakra)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.secondarySystemBackground))
                .shadow(radius: 2)
        )
    }
}
