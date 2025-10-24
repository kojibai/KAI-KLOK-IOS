//
//  KeypairStore.swift
//  KaiKlok
//
//  Created by BJ Klock on 10/16/25.
//

import Foundation
import CryptoKit
import Security

public struct WVKeypair {
    /// Exported public key (ANSI X9.63 / uncompressed) encoded as base64url.
    public let spkiB64u: String
    /// Private signing key (P-256)
    public let priv: P256.Signing.PrivateKey
}

private let kService = "com.kaiklok.sovereign"
private let kAccount = "v14-p256"

// Local base64url helper (kept file-private to avoid symbol clashes)
@inline(__always)
private func base64url(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

// Persist raw private key in Keychain; export pubkey as x963 base64url
public func loadOrCreateKeypair() throws -> WVKeypair {
    if let raw = try? keychainRead(service: kService, account: kAccount) {
        if let priv = try? P256.Signing.PrivateKey(rawRepresentation: raw) {
            let pub = priv.publicKey
            let x963 = pub.x963Representation
            return WVKeypair(spkiB64u: base64url(x963), priv: priv)
        }
    }
    // Create new
    let priv = P256.Signing.PrivateKey()
    let raw = priv.rawRepresentation
    try keychainWrite(service: kService, account: kAccount, data: raw)
    let x963 = priv.publicKey.x963Representation
    return WVKeypair(spkiB64u: base64url(x963), priv: priv)
}

// ECDSA P-256 signature (DER) → base64url
public func signB64u(_ priv: P256.Signing.PrivateKey, _ message: String) throws -> String {
    let sig = try priv.signature(for: Data(message.utf8))
    return base64url(sig.derRepresentation)
}

// MARK: - Tiny Keychain helpers

private func keychainWrite(service: String, account: String, data: Data) throws {
    let q: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
        kSecValueData as String: data
    ]
    // Replace any existing item
    SecItemDelete(q as CFDictionary)
    let status = SecItemAdd(q as CFDictionary, nil)
    guard status == errSecSuccess else {
        throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
    }
}

private func keychainRead(service: String, account: String) throws -> Data {
    let q: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(q as CFDictionary, &item)
    guard status == errSecSuccess, let data = item as? Data else {
        throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
    }
    return data
}
