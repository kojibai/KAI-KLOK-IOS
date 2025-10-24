//
//  SigilURL.swift
//  KaiKlok
//
//  Created by BJ Klock on 10/16/25.
//

import Foundation

// MARK: - Local helpers (file-private to avoid cross-file symbol collisions)

@inline(__always)
private func wvBase64url(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

@inline(__always)
private func wvBase64urlJson<T: Encodable>(_ value: T) -> String {
    let enc = JSONEncoder()
    enc.outputFormatting = [] // compact
    let data = (try? enc.encode(value)) ?? Data()
    return wvBase64url(data)
}

// MARK: - Share payload

public struct SigilSharePayloadLoose: Codable {
    public var pulse: Int
    public var beat: Int
    public var stepIndex: Int
    public var chakraDay: String
    public var kaiSignature: String?
    public var userPhiKey: String?

    public init(
        pulse: Int,
        beat: Int,
        stepIndex: Int,
        chakraDay: String,
        kaiSignature: String? = nil,
        userPhiKey: String? = nil
    ) {
        self.pulse = pulse
        self.beat = beat
        self.stepIndex = stepIndex
        self.chakraDay = chakraDay
        self.kaiSignature = kaiSignature
        self.userPhiKey = userPhiKey
    }
}

/// Builds the canonical Sigil URL. If you want to embed the payload,
/// you can append `?p=<base64url(json)>` using `wvBase64urlJson(payload)`.
public func makeSigilUrl(_ canonical: String, _ payload: SigilSharePayloadLoose) -> String {
    // Keep this aligned with your web route. Minimal base path for now.
    // Example (uncomment to include payload in query):
    // let p = wvBase64urlJson(payload)
    // return "https://app.kaiklok.com/s/\(canonical)?p=\(p)"
    "https://app.kaiklok.com/s/\(canonical)"
}

// MARK: - Compact history

public struct SigilTransferLite: Codable {
    public var s: String   // signature (sender or receiver)
    public var p: Int      // pulse
    public var r: String?  // optional receiver signature

    public init(s: String, p: Int, r: String? = nil) {
        self.s = s
        self.p = p
        self.r = r
    }
}

/// Encodes a compact transfer history as a base64url string with a lightweight prefix.
public func encodeSigilHistory(_ lite: [SigilTransferLite]) -> String {
    "h:" + wvBase64urlJson(lite)
}
