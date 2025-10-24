//
//  SigilShare.swift
//  KaiKlok
//
//  Created by BJ Klock on 9/18/25.
//

import Foundation
import CryptoKit

// MARK: - Models

/// Matches the web payload shape; keep fields compact (no timestamps).
public struct SigilSharePayload: Codable {
    public let pulse: Int
    public let beat: Int
    public let stepIndex: Int
    public let chakraDay: String
    public let stepsPerBeat: Int
    public let canonicalHash: String
    public let expiresAtPulse: Int
}

// MARK: - Constants

/// Base for the Explorer/Sigil page (set to your real origin).
private let SIGIL_BASE_URL = URL(string: "https://kaiklok.com")! // ← update to your origin if needed

// MARK: - URL Building

/// Base64URL (RFC 4648 §5) without padding — mirrors the web's compact param encoding.
@inline(__always)
private func base64URLEncode(_ data: Data) -> String {
    data.base64EncodedString(options: [])
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

/// URL builder that mirrors TSX’s `makeSigilUrl(hash, payload)`.
/// Produces: `{SIGIL_BASE_URL}/s/{canonicalHash}?p={base64url(payload)}`
/// Falls back to the base path if encoding or components fail (never crashes).
public func makeSigilUrl(canonicalHash: String, payload: SigilSharePayload) -> URL {
    // Normalize the hash to lowercase to keep canonical paths consistent
    let hash = canonicalHash.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let base = SIGIL_BASE_URL.appendingPathComponent("s").appendingPathComponent(hash)

    guard let data = try? JSONEncoder().encode(payload) else {
        // JSON encoding should not fail for a simple Codable payload; return base path on anomaly
        return base
    }

    let b64 = base64URLEncode(data)

    guard var comps = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
        return base
    }
    comps.queryItems = [URLQueryItem(name: "p", value: b64)]
    return comps.url ?? base
}

// MARK: - Hashing

/// SHA-256 (lowercase hex) — canonical hash of the visible SVG or fallback basis.
@inline(__always)
public func sha256Hex(_ data: Data) -> String {
    let digest = SHA256.hash(data: data)
    return digest.map { String(format: "%02x", $0) }.joined()
}

@inline(__always)
public func sha256Hex(_ text: String) -> String {
    sha256Hex(Data(text.utf8))
}

// MARK: - Local Registry (mirrors TSX `registerSigilUrl`)

/// Simple local registry for created Sigil URLs so the rest of the app can react.
public func registerSigilUrlLocally(_ url: URL) {
    let key = "sigil:urls"
    var arr = (UserDefaults.standard.array(forKey: key) as? [String]) ?? []
    let s = url.absoluteString
    if !arr.contains(s) { arr.append(s) }
    UserDefaults.standard.set(arr, forKey: key)
    NotificationCenter.default.post(name: .sigilUrlRegistered, object: s)
}

public extension Notification.Name {
    static let sigilUrlRegistered = Notification.Name("sigil:url-registered")
}
