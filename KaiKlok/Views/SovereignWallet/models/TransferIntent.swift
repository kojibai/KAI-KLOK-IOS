//
//  TransferIntent.swift
//  KaiKlok
//
//  Created by BJ Klock on 10/15/25.
//

import Foundation

struct TransferIntent: Codable, Identifiable, Equatable {
    let id: String                 // UUID or derived hash of the transfer
    let fromPhiKey: String         // Sender’s ΦKey id
    let toPhiKey: String           // Receiver’s ΦKey id
    let amountPhi: Double          // Amount in Φ being transferred
    let kaiSignature: String       // Poseidon hash proof (ZK)
    let pulse: Int                 // Kai pulse when initiated
    let noteHash: String?          // Optional: hash of attached note
    let timestamp: Date            // Time created (Kai time equivalent)
    var isConfirmed: Bool          // True once applied to local ledger
    var isBroadcasted: Bool        // True if synced to PhiNet (optional)

    init(
        fromPhiKey: String,
        toPhiKey: String,
        amountPhi: Double,
        kaiSignature: String,
        pulse: Int,
        noteHash: String? = nil
    ) {
        self.id = UUID().uuidString
        self.fromPhiKey = fromPhiKey
        self.toPhiKey = toPhiKey
        self.amountPhi = amountPhi
        self.kaiSignature = kaiSignature
        self.pulse = pulse
        self.noteHash = noteHash
        self.timestamp = Date()
        self.isConfirmed = false
        self.isBroadcasted = false
    }

    // Helper for marking as confirmed
    func confirmedVersion() -> TransferIntent {
        var copy = self
        copy.isConfirmed = true
        return copy
    }

    // Helper for marking as broadcasted
    func broadcastedVersion() -> TransferIntent {
        var copy = self
        copy.isBroadcasted = true
        return copy
    }
}
