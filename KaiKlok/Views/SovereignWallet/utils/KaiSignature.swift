//
//  KaiSignature.swift
//  KaiKlok
//
//  Created by BJ Klock on 10/15/25.
//

import Foundation
import CryptoKit

struct KaiSignature {
    
    /// Hashes a string input into a Poseidon-style signature (using SHA256 as placeholder)
    static func hash(_ input: String) -> String {
        let data = Data(input.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Hashes structured fields like sender, receiver, amount, pulse
    static func hashTransfer(
        from: String,
        to: String,
        amount: Double,
        pulse: Int
    ) -> String {
        let base = "\(from)-\(to)-\(amount)-\(pulse)"
        return hash(base)
    }

    /// Hashes inhale data like key, amount, pulse, chakra
    static func hashInhale(
        keyID: String,
        amount: Double,
        pulse: Int,
        chakraDay: String
    ) -> String {
        let base = "\(keyID)-\(amount)-\(pulse)-\(chakraDay)"
        return hash(base)
    }

    /// Hashes note data like key, amount, pulse, sigilHash
    static func hashNote(
        keyID: String,
        amount: Double,
        pulse: Int,
        sigilHash: String
    ) -> String {
        let base = "\(keyID)-\(amount)-\(pulse)-\(sigilHash)"
        return hash(base)
    }
}
