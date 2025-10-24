//
//  SigilCrypto.swift
//  KaiKlok
//
//  Created by BJ Klock on 10/16/25.
//

import Foundation
import CryptoKit

// MARK: - Local, namespaced SHA-256 helpers (avoid collisions with other files)

@inline(__always)
private func wv_sha256Hex(_ data: Data) -> String {
    let digest = SHA256.hash(data: data)
    return digest.map { String(format: "%02x", $0) }.joined()
}

@inline(__always)
private func wv_sha256Hex(_ s: String) -> String {
    wv_sha256Hex(Data(s.utf8))
}

// MARK: - Public API

/// Σ from core fields (parity with TSX)
public func computeKaiSignature(_ m: WVSigilMetadata) -> String? {
    guard let p = m.pulse, let b = m.beat, let s = m.stepIndex, let day = m.chakraDay else { return nil }
    return wv_sha256Hex("\(p)|\(b)|\(s)|\(day)")
}

/// Φ derived from Σ (stub: plug your real mapping later)
public func derivePhiKeyFromSig(_ sig: String) -> String {
    "phi_" + String(wv_sha256Hex(sig).prefix(40))
}

/// Optional: map public key → Φ (stub for parity)
public func phiFromPublicKey(_ spki: String) -> String {
    "phi_pub_" + String(wv_sha256Hex(spki).prefix(24))
}
