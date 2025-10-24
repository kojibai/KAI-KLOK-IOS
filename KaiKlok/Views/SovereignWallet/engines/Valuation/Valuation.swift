//
//  Valuation.swift
//  KaiKlok
//
//  Created by BJ Klock on 10/16/25.
//

import Foundation

public struct ValueSeal: Codable {
    public var valuePhi: Double
    public var atPulse: Int
    public var headHash: String?

    // Public memberwise init so it can be called from @inlinable funcs.
    public init(valuePhi: Double, atPulse: Int, headHash: String?) {
        self.valuePhi = valuePhi
        self.atPulse = atPulse
        self.headHash = headHash
    }
}

public struct InitialGlyph: Codable {
    public var hash: String
    public var value: Double
    public var pulseCreated: Int
    public var meta: WVSigilMetadata

    public init(hash: String, value: Double, pulseCreated: Int, meta: WVSigilMetadata) {
        self.hash = hash
        self.value = value
        self.pulseCreated = pulseCreated
        self.meta = meta
    }
}

/// Builds a reproducible (toy) valuation from current pulse and head root.
@inlinable
public func buildValueSeal(
    _ meta: WVSigilMetadata,
    nowPulse: Int,
    headHash: String?
) -> ValueSeal {
    // toy heuristic: mix pulse + head root to a reproducible 0..1 → scale
    let seed = "\(meta.pulse ?? 0)|\(headHash ?? "")|\(nowPulse)"
    let h = sha256Hex(seed)
    let first16 = String(h.prefix(16))
    let v = Double(UInt64(first16, radix: 16) ?? 0) / Double(UInt64.max)
    let scaled = (v * 0.6180339887 + 0.382) * 1000.0
    return ValueSeal(valuePhi: scaled, atPulse: nowPulse, headHash: headHash)
}
