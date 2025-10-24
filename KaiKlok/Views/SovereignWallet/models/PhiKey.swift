//
//  PhiKey.swift
//  KaiKlok
//
//  Created by BJ Klock on 10/15/25.
//

import Foundation

struct PhiKey: Codable, Identifiable, Equatable {
    let id: String                 // UUID or hash of biometric signature
    let sigilHash: String          // Hash of the sigil SVG
    var balancePhi: Double         // Current Φ balance
    var balanceUSD: Double         // Cached live value in USD
    var createdAt: Date
    var lastPulse: Int             // Kai Pulse index when last updated

    // Static method to create a blank PhiKey before identity is registered
    static func empty() -> PhiKey {
        return PhiKey(
            id: UUID().uuidString,
            sigilHash: "",
            balancePhi: 0.0,
            balanceUSD: 0.0,
            createdAt: Date(),
            lastPulse: 0
        )
    }
}
