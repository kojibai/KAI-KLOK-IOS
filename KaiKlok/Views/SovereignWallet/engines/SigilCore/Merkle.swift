//
//  Merkle.swift
//  KaiKlok
//
//  Created by BJ Klock on 10/16/25.
//

import Foundation
import CryptoKit

/// Local, unambiguous SHA-256 helper for this file.
@inline(__always)
private func sc_sha256Hex(_ data: Data) -> String {
    let digest = SHA256.hash(data: data)
    return digest.map { String(format: "%02x", $0) }.joined()
}

// Pair-hash = sha256(L||R) over bytes (leaves are hex-strings)
public func buildMerkleRoot(_ leavesHex: [String]) -> String {
    if leavesHex.isEmpty { return "" }
    var layer = leavesHex.map { Data(hex: $0) ?? Data() }
    while layer.count > 1 {
        var next: [Data] = []
        var i = 0
        while i < layer.count {
            let L = layer[i]
            let R = (i + 1 < layer.count) ? layer[i+1] : layer[i]
            var cat = Data(); cat.append(L); cat.append(R)
            next.append(Data(hex: sc_sha256Hex(cat)) ?? Data())
            i += 2
        }
        layer = next
    }
    return layer.first?.hexString ?? ""
}

public func merkleProof(_ leavesHex: [String], index: Int) -> [String] {
    var idx = index
    var layer = leavesHex.map { Data(hex: $0) ?? Data() }
    var proof: [Data] = []
    while layer.count > 1 {
        var next: [Data] = []
        var i = 0
        while i < layer.count {
            let L = layer[i]
            let R = (i + 1 < layer.count) ? layer[i+1] : layer[i]
            if i == idx ^ 1 || (i == idx && i+1 >= layer.count) {
                proof.append(i == idx ? R : L)
            }
            var cat = Data(); cat.append(L); cat.append(R)
            next.append(Data(hex: sc_sha256Hex(cat)) ?? Data())
            i += 2
        }
        idx /= 2
        layer = next
    }
    return proof.map { $0.hexString }
}

public func verifyProof(rootHex: String, leafHex: String, index: Int, proofHex: [String]) -> Bool {
    var idx = index
    var hash = Data(hex: leafHex) ?? Data()
    for sibHex in proofHex {
        let sib = Data(hex: sibHex) ?? Data()
        var cat = Data()
        if idx % 2 == 0 { cat.append(hash); cat.append(sib) }
        else            { cat.append(sib);  cat.append(hash) }
        hash = Data(hex: sc_sha256Hex(cat)) ?? Data()
        idx /= 2
    }
    return hash.hexString.lowercased() == rootHex.lowercased()
}
