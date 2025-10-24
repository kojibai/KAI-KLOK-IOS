//
//  PhiNote.swift
//  KaiKlok
//
//  Created by BJ Klock on 10/15/25.
//

import Foundation

struct PhiNote: Codable, Identifiable, Equatable {
    let id: String                     // Unique ID (UUID or derived hash)
    let phiAmount: Double              // Value in Φ
    let usdValue: Double               // Snapshot of USD at time of mint
    let pulse: Int                     // Kai Pulse index
    let beat: Int                      // Kai beat (0-35)
    let stepIndex: Int                 // Kai step (0-43)
    let chakraDay: String              // Day name (e.g. "Solhara")
    let sigilHash: String              // Hash of the sigil SVG
    let fromPhiKey: String             // Originating wallet id
    let kaiSignature: String           // Poseidon hash for ZK validation
    let timestamp: Date                // UTC minting timestamp
    var isSpent: Bool                  // Marks if note has been transferred

    // Helper to mark a note as spent (immutable logic)
    func spentVersion() -> PhiNote {
        var copy = self
        copy.isSpent = true
        return copy
    }
}
