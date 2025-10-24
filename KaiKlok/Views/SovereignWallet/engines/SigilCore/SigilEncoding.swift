//
//  SigilEncoding.swift
//  KaiKlok
//
//  Created by BJ Klock on 10/16/25.
//

import Foundation
import CryptoKit

// MARK: - Time

@inline(__always)
public func kaiPulseNow() -> Int {
    Int(Date().timeIntervalSince1970.rounded())
}

// MARK: - Namespaced codecs & hashing (no global functions → no collisions)

public enum WVHash {
    @inline(__always)
    public static func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    @inline(__always)
    public static func sha256Hex(_ s: String) -> String {
        sha256Hex(Data(s.utf8))
    }
}

public enum WVCodec {
    /// Deterministic JSON (sorted keys; mirrors TS stableStringify)
    public static func stableStringify(_ any: Any) -> String {
        func norm(_ v: Any) -> Any {
            if let d = v as? [String: Any] {
                let keys = d.keys.sorted()
                var out: [String: Any] = [:]
                for k in keys { out[k] = norm(d[k] as Any) }
                return out
            } else if let a = v as? [Any] {
                return a.map(norm)
            }
            return v
        }
        func encode(_ v: Any) -> String {
            if JSONSerialization.isValidJSONObject(v),
               let d = try? JSONSerialization.data(withJSONObject: v, options: []),
               let s = String(data: d, encoding: .utf8) { return s }
            return "\"\""
        }
        return encode(norm(any))
    }

    public static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func base64urlJson<T: Encodable>(_ val: T) -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = []
        let data = (try? enc.encode(val)) ?? Data()
        return base64url(data)
    }

    public static func hashAny(_ any: Any) -> String {
        WVHash.sha256Hex(Data(stableStringify(any).utf8))
    }
}

// MARK: - Hex helpers

public extension Data {
    init?(hex: String) {
        let s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count % 2 == 0 else { return nil }
        var data = Data(capacity: s.count/2)
        var idx = s.startIndex
        while idx < s.endIndex {
            let next = s.index(idx, offsetBy: 2)
            guard next <= s.endIndex else { return nil }
            let b = s[idx..<next]
            guard let v = UInt8(b, radix: 16) else { return nil }
            data.append(v); idx = next
        }
        self = data
    }

    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}
