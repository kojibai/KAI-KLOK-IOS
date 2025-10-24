//
//  SigilModels.swift
//  KaiKlok
//
//  Created by BJ Klock on 10/16/25.
//

//
//  SigilModels.swift
//  KaiKlok
//
//  Shared Codable models & small constants used by Verifier/Stamper.
//  Keep this logic-free; engines live under engines/SigilCore/*
//

import Foundation

// MARK: - Small constants that mirror TSX defaults

public let SEGMENT_SIZE: Int = 24
public let SIGIL_CTX: String = "https://kai.sigil/ctx"
public let SIGIL_TYPE: String = "KaiSigil"

// MARK: - UI State

public enum WVUiState: String {
    case idle, invalid, structMismatch, sigMismatch, notOwner, unsigned, readySend, readyReceive, complete, verified
}

// MARK: - Value wrappers

/// Lossless wrapper for “any JSON” (for ZK bundles, etc.)
public struct WVCodableValue: Codable {
    public let value: Any
    public init(_ v: Any) { value = v }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self)   { value = b; return }
        if let i = try? c.decode(Int.self)    { value = i; return }
        if let d = try? c.decode(Double.self) { value = d; return }
        if let s = try? c.decode(String.self) { value = s; return }
        if let a = try? c.decode([WVCodableValue].self) {
            value = a.map { $0.value }; return
        }
        if let o = try? c.decode([String: WVCodableValue].self) {
            value = o.mapValues { $0.value }; return
        }
        value = NSNull()
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case let b as Bool: try c.encode(b)
        case let i as Int: try c.encode(i)
        case let d as Double: try c.encode(d)
        case let s as String: try c.encode(s)
        case let a as [Any]: try c.encode(a.map(WVCodableValue.init))
        case let o as [String: Any]: try c.encode(o.mapValues(WVCodableValue.init))
        default: try c.encodeNil()
        }
    }
}

// MARK: - Core models

public struct WVSigilPayload: Codable {
    public let name: String
    public let mime: String
    public let size: Int
    public let encoded: String // base64 (not url)
}

public struct WVSigilTransfer: Codable {
    public var senderSignature: String
    public var senderStamp: String
    public var senderKaiPulse: Int
    public var payload: WVSigilPayload?

    // Receiver side (filled on inhale)
    public var receiverSignature: String?
    public var receiverStamp: String?
    public var receiverKaiPulse: Int?
}

public struct WVZkHashRef: Codable {
    public var scheme: String
    public var curve: String
    public var publicHash: String?
    public var proofHash: String?
    public var vkeyHash: String?
    public var verified: Bool?
}

public struct WVZkBundle: Codable {
    public var scheme: String
    public var curve: String
    public var proof: WVCodableValue?
    public var publicSignals: WVCodableValue?
    public var vkey: WVCodableValue?
}

/// Hardened lineage (v14)
public struct WVHardenedTransferV14: Codable {
    public var previousHeadRoot: String
    public var senderPubKey: String
    public var senderSig: String
    public var senderKaiPulse: Int
    public var nonce: String
    public var transferLeafHashSend: String

    // Receive half
    public var receiverPubKey: String?
    public var receiverSig: String?
    public var receiverKaiPulse: Int?
    public var transferLeafHashReceive: String?

    // Optional ZK
    public var zkSend: WVZkHashRef?
    public var zkReceive: WVZkHashRef?
    public var zkSendBundle: WVZkBundle?
    public var zkReceiveBundle: WVZkBundle?
}

public struct WVSegmentHead: Codable {
    public var root: String
    public var count: Int
}

public struct WVSigilMetadata: Codable {
    // core
    public var pulse: Int?
    public var beat: Int?
    public var stepIndex: Int?
    public var chakraDay: String?

    // signatures/keys
    public var kaiSignature: String?
    public var userPhiKey: String?
    public var creatorPublicKey: String?

    // lineage
    public var transferNonce: String?
    public var transfers: [WVSigilTransfer]?
    public var hardenedTransfers: [WVHardenedTransferV14]?

    // head window + segments
    public var segmentSize: Int?
    public var segments: [WVSegmentHead]?
    public var segmentsMerkleRoot: String?
    public var cumulativeTransfers: Int?
    public var transfersWindowRoot: String?
    public var transfersWindowRootV14: String?

    // extras used in UI
    public var frequencyHz: Double?
    public var chakraGate: String?

    // ctx/type like the TSX defaults
    public var context: String?
    public var type: String?

    // optional ZK verifying key blob (opaque)
    public var zkVerifyingKey: WVCodableValue?

    // canonical hash (optional)
    public var canonicalHash: String?

    public enum CodingKeys: String, CodingKey {
        case pulse, beat, stepIndex, chakraDay
        case kaiSignature, userPhiKey, creatorPublicKey
        case transferNonce, transfers, hardenedTransfers
        case segmentSize, segments, segmentsMerkleRoot, cumulativeTransfers
        case transfersWindowRoot, transfersWindowRootV14
        case frequencyHz, chakraGate
        case context = "@context"
        case type
        case zkVerifyingKey
        case canonicalHash
    }
}

// MARK: - Tiny helpers reused in UI/engines

@inline(__always)
public func normalizeChakraDay(_ s: String?) -> String {
    guard let s, !s.isEmpty else { return "—" }
    return s.prefix(1).uppercased() + s.dropFirst()
}
