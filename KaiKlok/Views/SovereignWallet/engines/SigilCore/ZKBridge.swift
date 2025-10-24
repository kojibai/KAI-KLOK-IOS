//
//  ZKBridge.swift
//  KaiKlok
//
//  Created by BJ Klock on 10/16/25.
//

import Foundation

// Local, file-private stable stringify to avoid cross-file symbol coupling.
@inline(__always)
private func _stableStringify(_ any: Any) -> String {
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
           let s = String(data: d, encoding: .utf8) {
            return s
        }
        return "\"\""
    }
    return encode(norm(any))
}

/// Local helper so this file doesn't depend on external symbol names.
/// Uses your global `sha256Hex` + the local `_stableStringify`.
@inline(__always)
private func zkHashAny(_ any: Any) -> String {
    sha256Hex(Data(_stableStringify(any).utf8))
}

// Best-effort offline verify: check hashes match their bundles
@discardableResult
public func verifyZkOnHead(_ m: inout WVSigilMetadata) -> Bool {
    var touched = false
    guard var hs = m.hardenedTransfers, !hs.isEmpty else { return false }

    for i in hs.indices {
        var h = hs[i]

        // SEND side bundle
        if let b = h.zkSendBundle {
            let pHash = zkHashAny(b.proof?.value ?? NSNull())
            let sHash = zkHashAny(b.publicSignals?.value ?? NSNull())
            var ok = true
            if let expectP = h.zkSend?.proofHash { ok = ok && (expectP == pHash) }
            if let expectS = h.zkSend?.publicHash { ok = ok && (expectS == sHash) }
            if let v = b.vkey?.value, let exp = h.zkSend?.vkeyHash {
                ok = ok && (exp == zkHashAny(v))
            }
            if ok {
                if var z = h.zkSend { z.verified = true; h.zkSend = z } // mutate copy then reassign
                touched = true
            }
        }

        // RECEIVE side bundle
        if let b = h.zkReceiveBundle {
            let pHash = zkHashAny(b.proof?.value ?? NSNull())
            let sHash = zkHashAny(b.publicSignals?.value ?? NSNull())
            var ok = true
            if let expectP = h.zkReceive?.proofHash { ok = ok && (expectP == pHash) }
            if let expectS = h.zkReceive?.publicHash { ok = ok && (expectS == sHash) }
            if let v = b.vkey?.value, let exp = h.zkReceive?.vkeyHash {
                ok = ok && (exp == zkHashAny(v))
            }
            if ok {
                if var z = h.zkReceive { z.verified = true; h.zkReceive = z }
                touched = true
            }
        }

        hs[i] = h
    }

    m.hardenedTransfers = hs
    return touched
}
