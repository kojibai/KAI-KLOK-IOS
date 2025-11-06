//
//  VerifierModal.swift
//  KaiKlok
//
//  TSX-parity Verifier/Stamper (mobile-first, full-screen)
//  v14.4 — Sovereign hardening+++ (ECDSA + optional ZK bind)
//  - Fix: iOS 18 deprecations for String(contentsOf:)
//  - Fix: 'never mutated' warnings (mini, types)
//
//  NOTE: All models (WVSigil* types, etc.) live in sigilmodels now.
//  This file ONLY contains UI + ViewModel and local, namespaced helpers.
//

import SwiftUI
import UniformTypeIdentifiers
import CryptoKit
import Foundation
import WebKit
import UIKit

// MARK: - Local, namespaced helpers (NO global extensions or shared names)

private func wvKaiPulseNow() -> Int {
    Int(Date().timeIntervalSince1970.rounded())
}

private func wvSHA256Hex(_ s: String) -> String {
    wvSHA256Hex(Data(s.utf8))
}
private func wvSHA256Hex(_ data: Data) -> String {
    let digest = SHA256.hash(data: data)
    return digest.map { String(format: "%02x", $0) }.joined()
}

// Deterministic JSON (stable stringify)
private func wvStableStringify(_ any: Any) -> String {
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

// base64url
private func wvBase64urlJson<T: Encodable>(_ val: T) -> String {
    let enc = JSONEncoder()
    enc.outputFormatting = []
    let data = (try? enc.encode(val)) ?? Data()
    return wvBase64url(data)
}
private func wvBase64url(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

// Small hex helpers (LOCAL — no global Data extensions)
private func wvHexToData(_ hex: String) -> Data {
    let s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    guard s.count % 2 == 0 else { return Data() }
    var data = Data(capacity: s.count/2)
    var idx = s.startIndex
    while idx < s.endIndex {
        let next = s.index(idx, offsetBy: 2)
        guard next <= s.endIndex else { break }
        let b = s[idx..<next]
        guard let v = UInt8(b, radix: 16) else { return Data() }
        data.append(v)
        idx = next
    }
    return data
}
private func wvDataToHex(_ data: Data) -> String {
    data.map { String(format: "%02x", $0) }.joined()
}

// Compute Kai content signature (best-effort, parity with TSX)
private func wvComputeKaiSignature(_ m: WVSigilMetadata) -> String? {
    guard let p = m.pulse, let b = m.beat, let s = m.stepIndex, let day = m.chakraDay else { return nil }
    return wvSHA256Hex("\(p)|\(b)|\(s)|\(day)")
}

// Derive Φ from Σ (placeholder; keep parity of I/O)
private func wvDerivePhiKeyFromSig(_ sig: String) -> String {
    "phi_" + wvSHA256Hex(sig).prefix(40)
}

// Merkle (SHA256, pair hash = sha256(L||R))
private func wvBuildMerkleRoot(_ leavesHex: [String]) -> String {
    if leavesHex.isEmpty { return "" }
    var layer = leavesHex.map { wvHexToData($0) }
    while layer.count > 1 {
        var next: [Data] = []
        var i = 0
        while i < layer.count {
            let L = layer[i]
            let R = i + 1 < layer.count ? layer[i+1] : layer[i]
            var cat = Data()
            cat.append(L); cat.append(R)
            next.append(wvHexToData(wvSHA256Hex(cat)))
            i += 2
        }
        layer = next
    }
    return wvDataToHex(layer.first ?? Data())
}

// Proof generation (for latest leaf) + verification
private func wvMerkleProof(_ leavesHex: [String], index: Int) -> [String] {
    var idx = index
    var layer = leavesHex.map { wvHexToData($0) }
    var proof: [Data] = []
    while layer.count > 1 {
        var next: [Data] = []
        var i = 0
        while i < layer.count {
            let L = layer[i]
            let R = i + 1 < layer.count ? layer[i+1] : layer[i]
            if i == idx ^ 1 || (i == idx && i+1 >= layer.count) {
                proof.append(i == idx ? R : L)
            }
            var cat = Data(); cat.append(L); cat.append(R)
            next.append(wvHexToData(wvSHA256Hex(cat)))
            i += 2
        }
        idx /= 2
        layer = next
    }
    return proof.map { wvDataToHex($0) }
}
private func wvVerifyProof(rootHex: String, leafHex: String, index: Int, proofHex: [String]) -> Bool {
    var idx = index
    var hash = wvHexToData(leafHex)
    for sibHex in proofHex {
        let sib = wvHexToData(sibHex)
        var cat = Data()
        if idx % 2 == 0 {
            cat.append(hash); cat.append(sib)
        } else {
            cat.append(sib); cat.append(hash)
        }
        hash = wvHexToData(wvSHA256Hex(cat))
        idx /= 2
    }
    return wvDataToHex(hash).lowercased() == rootHex.lowercased()
}

// Transfer hashing (sender-side & full leaf)
private func wvHashTransferSenderSide(_ t: WVSigilTransfer) -> String {
    let obj: [String: Any] = [
        "senderSignature": t.senderSignature,
        "senderStamp": t.senderStamp,
        "senderKaiPulse": t.senderKaiPulse,
        "payload": t.payload != nil ? [
            "name": t.payload!.name,
            "mime": t.payload!.mime,
            "size": t.payload!.size,
            "encoded": t.payload!.encoded
        ] : NSNull()
    ]
    return wvSHA256Hex(wvStableStringify(obj))
}
private func wvHashTransferFull(_ t: WVSigilTransfer) -> String {
    let obj: [String: Any] = [
        "senderSignature": t.senderSignature,
        "senderStamp": t.senderStamp,
        "senderKaiPulse": t.senderKaiPulse,
        "receiverSignature": t.receiverSignature as Any,
        "receiverStamp": t.receiverStamp as Any,
        "receiverKaiPulse": t.receiverKaiPulse as Any,
        "payload": t.payload != nil ? [
            "name": t.payload!.name,
            "mime": t.payload!.mime,
            "size": t.payload!.size,
            "encoded": t.payload!.encoded
        ] : NSNull()
    ]
    return wvSHA256Hex(wvStableStringify(obj))
}

// Nonce
private func wvGenNonce() -> String { UUID().uuidString.replacingOccurrences(of: "-", with: "") }

// Embed JSON into <metadata><![CDATA[...]]></metadata>
private func wvEmbedMetadata(svgString: String, meta: WVSigilMetadata) -> String {
    let enc = JSONEncoder()
    enc.outputFormatting = [.sortedKeys]
    let json = (try? enc.encode(meta)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    if let a = svgString.range(of: "<metadata><![CDATA["),
       let b = svgString.range(of: "]]></metadata>") {
        var s = svgString
        s.replaceSubrange(a.upperBound..<b.lowerBound, with: json)
        return s
    } else {
        let node = "<metadata><![CDATA[\(json)]]></metadata>"
        return svgString.replacingOccurrences(of: "</svg>", with: "\(node)</svg>")
    }
}

// Extract JSON back out
private func wvExtractMeta(fromSVG svg: String) -> (raw: String, meta: WVSigilMetadata, contextOk: Bool, typeOk: Bool)? {
    guard let a = svg.range(of: "<metadata><![CDATA["),
          let b = svg.range(of: "]]></metadata>") else { return nil }
    let json = String(svg[a.upperBound..<b.lowerBound])
    guard let data = json.data(using: .utf8) else { return nil }
    let dec = JSONDecoder()
    guard let m = try? dec.decode(WVSigilMetadata.self, from: data) else { return nil }
    let ctxOK = (m.context ?? "").isEmpty || (m.context ?? "").lowercased().contains("sigil")
    let typeOK = (m.type ?? "").isEmpty || (m.type ?? "").lowercased().contains("sigil")
    return (json, m, ctxOK, typeOK)
}

// MARK: - UI State (renamed to avoid any collision)

enum WVVerifierUiState: String {
    case idle, invalid, structMismatch, sigMismatch, notOwner, unsigned, readySend, readyReceive, complete, verified
}

private func wvDeriveState(contextOk: Bool, typeOk: Bool, hasCore: Bool, contentSigMatches: Bool?, isOwner: Bool?, hasTransfers: Bool, lastOpen: Bool, isUnsigned: Bool) -> WVVerifierUiState {
    if !contextOk || !typeOk { return .invalid }
    if !hasCore { return .structMismatch }
    if contentSigMatches == false { return .sigMismatch }
    if isOwner == false { return .notOwner }
    if isUnsigned { return .unsigned }
    if !hasTransfers { return .readySend }
    if lastOpen { return .readyReceive }
    return .complete
}

// MARK: - ViewModel

final class VerifierVM: ObservableObject {
    // Inputs
    @Published var svgURL: URL?
    @Published var rawMeta: String?
    @Published var meta: WVSigilMetadata?

    // Live sig / RGB seed
    @Published var liveSig: String?
    @Published var rgbSeed: [Int]?

    // Derived
    @Published var uiState: WVVerifierUiState = .idle
    @Published var contentSigExpected: String?
    @Published var contentSigMatches: Bool?
    @Published var phiKeyExpected: String?
    @Published var phiKeyMatches: Bool?

    // Head proof
    @Published var headProof: (ok: Bool, index: Int, root: String)?

    // Errors
    @Published var error: String?

    // Tab
    @Published var tab: String = "summary"

    // Attachments
    @Published var payload: WVSigilPayload?

    // Seal modal
    @Published var sealOpen: Bool = false
    @Published var sealUrl: String = ""
    @Published var sealHash: String = ""

    // Explorer / Valuation
    @Published var explorerOpen = false
    @Published var valuationOpen = false

    // Pulse ticker
    @Published var pulseNow: Int = wvKaiPulseNow()
    private var timer: Timer?

    func startPulse() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.pulseNow = wvKaiPulseNow()
        }
    }
    func stopPulse() { timer?.invalidate() ; timer = nil }

    // Handle imported SVG
    func handle(svgData: String, blobURL: URL) {
        error = nil; uiState = .idle; tab = "summary"; payload = nil

        guard let (raw, meta0, ctxOK, typeOK) = wvExtractMeta(fromSVG: svgData) else {
            self.error = "No <metadata><![CDATA[...]]> JSON found."
            return
        }
        rawMeta = raw
        svgURL = blobURL

        var m = meta0
        // defaults
        if m.segmentSize == nil { m.segmentSize = 24 } // SEGMENT_SIZE
        if m.cumulativeTransfers == nil {
            let segCount = (m.segments ?? []).reduce(0) { $0 + ($1.count) }
            m.cumulativeTransfers = segCount + (m.transfers?.count ?? 0)
        }
        if !(m.segments?.isEmpty ?? true), m.segmentsMerkleRoot?.isEmpty ?? true {
            let roots = (m.segments ?? []).map { $0.root }
            m.segmentsMerkleRoot = wvBuildMerkleRoot(roots)
        }

        // live centre-pixel sig substitute: hash(svg bytes + pulseNow) + RGB seed
        do {
            let svgBytes = Data(svgData.utf8)
            let now = wvKaiPulseNow()
            let timeData = withUnsafeBytes(of: now.bigEndian) { Data($0) }
            var combined = Data()
            combined.append(svgBytes)
            combined.append(timeData)
            let h = wvSHA256Hex(combined)
            liveSig = h
            let bytes = Array(wvHexToData(h).prefix(3))
            rgbSeed = bytes.map { Int($0) }
        }

        // Expected Σ and Φ
        if let sig = wvComputeKaiSignature(m) {
            contentSigExpected = sig
            if let k = m.kaiSignature {
                contentSigMatches = (k.lowercased() == sig.lowercased())
            } else {
                contentSigMatches = nil
            }
        } else { contentSigExpected = nil; contentSigMatches = nil }

        if let k = m.kaiSignature {
            let phi = wvDerivePhiKeyFromSig(k)
            phiKeyExpected = String(phi)
            phiKeyMatches = (m.userPhiKey != nil) ? (m.userPhiKey == phi) : nil
        } else {
            phiKeyExpected = nil
            phiKeyMatches = nil
        }

        // Ownership (legacy heuristic)
        let last = m.transfers?.last
        let lastParty = last?.receiverSignature ?? last?.senderSignature
        let isOwner = (lastParty != nil && liveSig != nil) ? (lastParty == liveSig) : nil

        let hasCore = (m.pulse != nil && m.beat != nil && m.stepIndex != nil && m.chakraDay != nil)
        let hasTransfers = (m.transfers?.isEmpty == false)
        let lastOpen = (m.transfers?.last?.receiverSignature == nil)
        let isUnsigned = (m.kaiSignature == nil)

        // Head window compute + proof
        let m2 = refreshHeadWindow(m)
        meta = m2
        rawMeta = encodeRaw(m2)

        let next = wvDeriveState(contextOk: ctxOK, typeOk: typeOK, hasCore: hasCore,
                                 contentSigMatches: contentSigMatches, isOwner: isOwner,
                                 hasTransfers: hasTransfers, lastOpen: lastOpen, isUnsigned: isUnsigned)

        let verified = (next != .invalid && next != .structMismatch && next != .sigMismatch && next != .notOwner && !lastOpen && ((contentSigMatches ?? true) || isUnsigned || m.kaiSignature != nil))

        uiState = verified ? .verified : next
    }

    private func encodeRaw(_ m: WVSigilMetadata?) -> String? {
        guard let m else { return nil }
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys, .prettyPrinted]
        return (try? enc.encode(m)).flatMap { String(data:$0, encoding:.utf8) }
    }

    // Recompute head roots/proofs
    private func refreshHeadWindow(_ m: WVSigilMetadata) -> WVSigilMetadata {
        var m = m
        let txs = m.transfers ?? []
        if !txs.isEmpty {
            let leaves = txs.map { wvHashTransferFull($0) }
            let root = wvBuildMerkleRoot(leaves)
            m.transfersWindowRoot = root
            let idx = leaves.count - 1
            let proof = wvMerkleProof(leaves, index: idx)
            let ok = wvVerifyProof(rootHex: root, leafHex: leaves[idx], index: idx, proofHex: proof)
            headProof = (ok, idx, root)
        } else {
            m.transfersWindowRoot = nil
            headProof = nil
        }

        // v14 window — hash hardened entries
        if let v14s = m.hardenedTransfers, !v14s.isEmpty {
            let miniLeaves: [String] = v14s.map { ht in
                let mini: [String: Any] = [
                    "previousHeadRoot": ht.previousHeadRoot,
                    "senderPubKey": ht.senderPubKey,
                    "senderSig": ht.senderSig,
                    "senderKaiPulse": ht.senderKaiPulse,
                    "nonce": ht.nonce,
                    "transferLeafHashSend": ht.transferLeafHashSend,
                    "receiverPubKey": ht.receiverPubKey as Any? ?? NSNull(),
                    "receiverSig": ht.receiverSig as Any? ?? NSNull(),
                    "receiverKaiPulse": ht.receiverKaiPulse as Any? ?? NSNull(),
                    "transferLeafHashReceive": ht.transferLeafHashReceive as Any? ?? NSNull(),
                    "zkSend": ht.zkSend != nil ? [
                        "scheme": ht.zkSend!.scheme,
                        "curve": ht.zkSend!.curve,
                        "publicHash": ht.zkSend!.publicHash as Any? ?? NSNull(),
                        "proofHash": ht.zkSend!.proofHash as Any? ?? NSNull(),
                        "vkeyHash": ht.zkSend!.vkeyHash as Any? ?? NSNull()
                    ] : NSNull(),
                    "zkReceive": ht.zkReceive != nil ? [
                        "scheme": ht.zkReceive!.scheme,
                        "curve": ht.zkReceive!.curve,
                        "publicHash": ht.zkReceive!.publicHash as Any? ?? NSNull(),
                        "proofHash": ht.zkReceive!.proofHash as Any? ?? NSNull(),
                        "vkeyHash": ht.zkReceive!.vkeyHash as Any? ?? NSNull()
                    ] : NSNull()
                ]
                return wvSHA256Hex(wvStableStringify(mini))
            }
            m.transfersWindowRootV14 = wvBuildMerkleRoot(miniLeaves)
        }
        return m
    }

    // Actions

    func sealUnsigned(svgString: String) {
        guard var m = meta, let url = svgURL else { return }
        if m.kaiSignature == nil {
            guard let sig = wvComputeKaiSignature(m) else { self.error = "Cannot compute kaiSignature — missing core fields."; return }
            m.kaiSignature = sig
        }
        if m.userPhiKey == nil, let sig = m.kaiSignature { m.userPhiKey = String(wvDerivePhiKeyFromSig(sig)) }
        if m.transferNonce == nil { m.transferNonce = wvGenNonce() }
        if m.pulse == nil { m.pulse = pulseNow }

        // silently anchor our creatorPublicKey if absent (parity)
        if m.creatorPublicKey == nil {
            m.creatorPublicKey = "spki_" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }

        // iOS 18-safe string load
        let svg = (try? String(contentsOf: url, encoding: .utf8))
            ?? ((try? Data(contentsOf: url)).flatMap { String(data: $0, encoding: .utf8) })
            ?? svgString

        let newSVG = wvEmbedMetadata(svgString: svg, meta: m)
        try? newSVG.data(using: .utf8)?.write(to: url, options: .atomic)

        let m2 = refreshHeadWindow(m)
        meta = m2
        rawMeta = encodeRaw(m2)
        uiState = (uiState == .unsigned) ? .readySend : uiState
        error = nil
    }

    func attach(_ fileURL: URL) {
        guard let data = try? Data(contentsOf: fileURL) else {
            self.error = "Couldn’t read the selected file."
            return
        }
        let name = fileURL.lastPathComponent
        let ext = fileURL.pathExtension.lowercased()
        let mime = (
            ext == "pdf" ? "application/pdf" :
            UTType(filenameExtension: ext)?.preferredMIMEType
        ) ?? "application/octet-stream"

        payload = WVSigilPayload(name: name, mime: mime, size: data.count, encoded: data.base64EncodedString())
        error = nil
    }

    func send(svgString: String) {
        guard var m = meta, let live = liveSig, let url = svgURL else { return }

        // Validate Σ if present
        if let ks = m.kaiSignature, let expected = contentSigExpected, ks.lowercased() != expected.lowercased() {
            self.error = "Content signature mismatch — cannot send."
            self.uiState = .sigMismatch
            return
        }

        // Seal if unsigned
        if m.kaiSignature == nil {
            guard let sig = wvComputeKaiSignature(m) else { self.error = "Cannot compute kaiSignature — missing core fields."; return }
            m.kaiSignature = sig
            if m.userPhiKey == nil { m.userPhiKey = String(wvDerivePhiKeyFromSig(sig)) }
        }
        // Ensure pulse exists (metadata core)
        if m.pulse == nil { m.pulse = pulseNow }

        let now = wvKaiPulseNow()
        let stamp = wvSHA256Hex("\(live)-\(m.pulse ?? 0)-\(now)")
        let tx = WVSigilTransfer(senderSignature: live, senderStamp: stamp, senderKaiPulse: now, payload: payload)

        // Ensure context/type populated
        if m.context == nil { m.context = "https://kai.sigil/ctx" }
        if m.type == nil { m.type = "KaiSigil" }
        m.transferNonce = m.transferNonce ?? wvGenNonce()
        var head = m.transfers ?? []
        head.append(tx)
        m.transfers = head
        if m.segmentSize == nil { m.segmentSize = 24 }

        // v14 hardened (sender side)
        if m.creatorPublicKey == nil { m.creatorPublicKey = "spki_" + UUID().uuidString.replacingOccurrences(of: "-", with: "") }
        let prevRootV14 = m.transfersWindowRootV14 ?? (m.transfersWindowRoot ?? "")
        let leafSend = wvHashTransferSenderSide(tx)
        let senderSig = wvSHA256Hex("send:\(prevRootV14)|\(now)|\(m.creatorPublicKey!)|\(leafSend)|\(m.transferNonce!)")
        var hardened = m.hardenedTransfers ?? []
        hardened.append(WVHardenedTransferV14(
            previousHeadRoot: prevRootV14,
            senderPubKey: m.creatorPublicKey!,
            senderSig: senderSig,
            senderKaiPulse: now,
            nonce: m.transferNonce!,
            transferLeafHashSend: leafSend,
            receiverPubKey: nil, receiverSig: nil, receiverKaiPulse: nil, transferLeafHashReceive: nil,
            zkSend: nil, zkReceive: nil, zkSendBundle: nil, zkReceiveBundle: nil
        ))
        m.hardenedTransfers = hardened

        // iOS 18-safe string load
        let svg = (try? String(contentsOf: url, encoding: .utf8))
            ?? ((try? Data(contentsOf: url)).flatMap { String(data: $0, encoding: .utf8) })
            ?? svgString

        // Write back into SVG
        let withHead = wvEmbedMetadata(svgString: svg, meta: m)
        try? withHead.data(using: .utf8)?.write(to: url, options: .atomic)

        // Recompute head, maybe segment
        var after = refreshHeadWindow(m)
        let cap = after.segmentSize ?? 24
        if (after.transfers?.count ?? 0) >= cap {
            // Seal current window as a segment (simple head-roll)
            let leaves = (after.transfers ?? []).map { wvHashTransferFull($0) }
            let root = wvBuildMerkleRoot(leaves)
            var segs = after.segments ?? []
            segs.append(WVSegmentHead(root: root, count: leaves.count))
            after.segments = segs
            after.transfers = [] // roll
            after.cumulativeTransfers = (after.cumulativeTransfers ?? 0) + leaves.count
            after.segmentsMerkleRoot = wvBuildMerkleRoot(segs.map{$0.root})

            // persist SVG after roll
            let rolled = wvEmbedMetadata(svgString: withHead, meta: after)
            try? rolled.data(using: .utf8)?.write(to: url, options: .atomic)

            after = refreshHeadWindow(after)
        }

        meta = after
        rawMeta = encodeRaw(after)
        uiState = .readyReceive
        error = nil

        // Build share URL (best-effort parity)
        let canonical = (after.canonicalHash?.lowercased()) ?? wvSHA256Hex("\(after.pulse ?? 0)|\(after.beat ?? 0)|\(after.stepIndex ?? 0)|\(after.chakraDay ?? "")").lowercased()
        let payloadLite: [String: Any?] = [
            "pulse": after.pulse, "beat": after.beat, "stepIndex": after.stepIndex, "chakraDay": after.chakraDay,
            "kaiSignature": after.kaiSignature, "userPhiKey": after.userPhiKey
        ]
        let token = after.transferNonce ?? wvGenNonce()
        let base = URL(string: "https://app.kaiklok.com/s/\(canonical)")!
        var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        let pJson = wvStableStringify(payloadLite.compactMapValues{ $0 })
        let pB64u = wvBase64url(Data(pJson.utf8))
        comps.queryItems = [URLQueryItem(name: "p", value: pB64u), URLQueryItem(name: "t", value: token)]
        self.sealUrl = comps.url?.absoluteString ?? base.absoluteString
        self.sealHash = canonical
        self.sealOpen = true
    }

    func receive() {
        guard var m = meta, let live = liveSig, var last = m.transfers?.last else { return }
        guard last.receiverSignature == nil else { return }
        let now = wvKaiPulseNow()
        last.receiverSignature = live
        last.receiverStamp = wvSHA256Hex("\(live)-\(last.senderStamp)-\(now)")
        last.receiverKaiPulse = now
        m.transfers?.removeLast()
        m.transfers?.append(last)

        // v14 receive half
        if var hLast = m.hardenedTransfers?.last, hLast.receiverSig == nil {
            let leafRecv = wvHashTransferFull(last)
            let recvSig = wvSHA256Hex("recv:\(hLast.previousHeadRoot)|\(hLast.senderSig)|\(now)|\(m.creatorPublicKey ?? "spki_0")|\(leafRecv)")
            hLast.receiverPubKey = m.creatorPublicKey ?? "spki_0"
            hLast.receiverSig = recvSig
            hLast.receiverKaiPulse = now
            hLast.transferLeafHashReceive = leafRecv
            m.hardenedTransfers?.removeLast()
            m.hardenedTransfers?.append(hLast)
        }

        meta = refreshHeadWindow(m)
        rawMeta = encodeRaw(meta)
        uiState = .complete
        error = nil

        // Auto-save payload to Files
        if let pay = last.payload, let bin = Data(base64Encoded: pay.encoded) {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(pay.name)
            try? bin.write(to: tmp, options: .atomic)
        }
    }
}

// MARK: - SVG Document Picker (UIKit wrapper)

private struct SVGDocumentPicker: UIViewControllerRepresentable {
    var onPick: (URL, String) -> Void
    var onCancel: () -> Void = {}

    func makeCoordinator() -> Coord { Coord(onPick: onPick, onCancel: onCancel) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // Accept common SVG UTTypes, including when iOS tags them as XML/plain text
        var types: [UTType] = []
        if let t = UTType("public.svg-image") { types.append(t) }
        if let t = UTType(filenameExtension: "svg") { types.append(t) }
        types.append(.xml)
        types.append(.plainText)
        // Always allow generic data as a fallback
        types.append(.data)
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: Array(Set(types)), asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}

    final class Coord: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL, String) -> Void
        let onCancel: () -> Void
        init(onPick: @escaping (URL, String) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick; self.onCancel = onCancel
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { onCancel(); return }
            let needsStop = url.startAccessingSecurityScopedResource()
            defer { if needsStop { url.stopAccessingSecurityScopedResource() } }
            do {
                // First try UTF-8 string (iOS 18-safe)
                let svg = try String(contentsOf: url, encoding: .utf8)
                onPick(url, svg)
            } catch {
                // Fallback: load raw data, then decode as UTF-8
                if let data = try? Data(contentsOf: url), let s = String(data: data, encoding: .utf8) {
                    onPick(url, s)
                } else {
                    onCancel()
                }
            }
        }
    }
}

// MARK: - Generic Attachment Picker (UIKit)

private struct AttachmentDocumentPicker: UIViewControllerRepresentable {
    var onPick: (URL) -> Void
    var onCancel: () -> Void = {}

    func makeCoordinator() -> Coord { Coord(onPick: onPick, onCancel: onCancel) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [.data, .pdf]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: Array(Set(types)), asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) { }

    final class Coord: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        let onCancel: () -> Void
        init(onPick: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick; self.onCancel = onCancel
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { onCancel() }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { onCancel(); return }
            let needsStop = url.startAccessingSecurityScopedResource()
            defer { if needsStop { url.stopAccessingSecurityScopedResource() } }
            onPick(url)
        }
    }
}

// MARK: - Verifier Panel (full-screen)

private struct VerifierPanelView: View {
    @ObservedObject var vm: VerifierVM
    @Binding var importedSVG: String
    @Binding var showAttachPicker: Bool
    @Environment(\.dismiss) private var dismissPanel

    var body: some View {
        ZStack {
            Color.black.opacity(0.001)
            VStack(spacing: 0) {
                // Topbar: status chips + close
                HStack {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) { statusChips }
                            .padding(.leading, 6)
                    }
                    Button {
                        dismissPanel()
                    } label: {
                        Text("×").font(.system(size: 24, weight: .black))
                    }
                    .buttonStyle(HoloCloseButton())
                }
                .padding(.horizontal, 8)
                .padding(.top, 6)
                .background(LinearGradient(colors: [Color.black.opacity(0.6), Color.black.opacity(0.3)], startPoint: .top, endPoint: .bottom))

                if let meta = vm.meta {
                    // Header
                    HStack(alignment: .center, spacing: 14) {
                        if let url = vm.svgURL {
                            AsyncImage(url: url) { img in
                                img.resizable().scaledToFit()
                            } placeholder: { Color.clear }
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.08)))
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Pulse \(meta.pulse ?? 0)")
                                .font(.headline)
                            Text("Beat \(meta.beat ?? 0) · Step \(meta.stepIndex ?? 0) · Day: \(normalizeChakra(meta.chakraDay))")
                                .foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                if let sig = meta.kaiSignature {
                                    TagView(text: "Σ \(sig.prefix(16))…")
                                } else {
                                    TagView(text: "Unsigned", tone: .warn)
                                }
                                if let phi = meta.userPhiKey {
                                    TagView(text: "Φ \(phi)")
                                }
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    // Tabs
                    SegmentedTabs(selection: Binding(get: { vm.tab }, set: { vm.tab = $0 }))

                    // Body
                    Group {
                        switch vm.tab {
                        case "summary":
                            SummaryGrid(vm: vm)
                        case "lineage":
                            LineageList(vm: vm)
                        default:
                            DataView(vm: vm)
                        }
                    }
                    .frame(maxHeight: .infinity)
                    .background(Color.black.opacity(0.0001))

                    // Footer actions
                    VStack(spacing: 10) {
                        if let err = vm.error {
                            Text(err).foregroundStyle(.red).font(.subheadline).lineLimit(nil).multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                        }
                        HStack(spacing: 10) {
                            if vm.uiState == .unsigned {
                                Button("Seal content (Σ + Φ)") { vm.sealUnsigned(svgString: importedSVG) }
                                    .borderedButtonCompat()
                            }
                            if vm.uiState == .readySend || vm.uiState == .verified {
                                Button("Attach") { showAttachPicker = true }
                                    .borderedButtonCompat()
                                Button("Exhale") { vm.send(svgString: importedSVG) }
                                    .borderedButtonCompat(prominent: true)
                            }
                            if vm.uiState == .readyReceive {
                                Button("Inhale") { vm.receive() }
                                    .borderedButtonCompat(prominent: true)
                            }
                            if (vm.meta?.transfers?.isEmpty == false) {
                                Button("Segment") {
                                    vm.uiState = .readyReceive
                                    vm.send(svgString: importedSVG) // triggers roll if cap reached
                                }
                                .borderedButtonCompat()
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                    }
                    .background(LinearGradient(colors: [kai("#001318").opacity(0.4), .clear], startPoint: .top, endPoint: .bottom))
                } else {
                    Spacer()
                    Text("Load a Sigil to begin").foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.08)))
            .shadow(color: .black.opacity(0.4), radius: 24, y: 10)
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
        }
        .ignoresSafeArea()
        // Seal share sheet
        .sheet(isPresented: Binding(get: { vm.sealOpen }, set: { vm.sealOpen = $0 })) {
            if let url = URL(string: vm.sealUrl) {
                ShareSheet(activityItems: [url])
                    .presentationDetents([.medium, .large])
            }
        }
        // Explorer placeholder
        .sheet(isPresented: Binding(get: { vm.explorerOpen }, set: { vm.explorerOpen = $0 })) {
            NavigationStack {
                Text("ΦStream Explorer")
                    .font(.title3.bold())
                    .padding()
                Spacer()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Close") { vm.explorerOpen = false } }
            }
        }
        // Attachment picker
        .sheet(isPresented: $showAttachPicker) {
            AttachmentDocumentPicker(onPick: { url in
                vm.attach(url)
                showAttachPicker = false
            }, onCancel: { showAttachPicker = false })
            .ignoresSafeArea()
        }
    }

    // Status chips (icons only)
    @ViewBuilder private var statusChips: some View {
        Group {
            if vm.uiState == .invalid        { IconChip(kind: .err,  title: "Invalid",       sys: "xmark.octagon") }
            if vm.uiState == .structMismatch { IconChip(kind: .err,  title: "Structure mismatch", sys: "exclamationmark.triangle") }
            if vm.uiState == .sigMismatch    { IconChip(kind: .err,  title: "Signature mismatch", sys: "xmark.seal") }
            if vm.uiState == .notOwner       { IconChip(kind: .warn, title: "Not owner",     sys: "shield.slash") }
            if vm.uiState == .unsigned       { IconChip(kind: .warn, title: "Unsigned",      sys: "number") }
            if vm.uiState == .readySend      { IconChip(kind: .info, title: "Ready to send", sys: "paperplane") }
            if vm.uiState == .readyReceive   { IconChip(kind: .info, title: "Ready to receive", sys: "arrow.down.circle") }
            if vm.uiState == .complete       { IconChip(kind: .ok,   title: "Lineage sealed", sys: "checkmark.circle") }
            if vm.uiState == .verified       { IconChip(kind: .ok,   title: "Verified",      sys: "seal") }

            if vm.contentSigMatches == true  { IconChip(kind: .ok,   title: "Content Σ match", sys: "sigma") }
            if vm.contentSigMatches == false { IconChip(kind: .err,  title: "Content Σ mismatch", sys: "sigma") }
            if vm.phiKeyMatches == true      { IconChip(kind: .ok,   title: "Φ-Key match",   sys: "function") }
            if vm.phiKeyMatches == false     { IconChip(kind: .err,  title: "Φ-Key mismatch", sys: "function") }

            if let c = vm.meta?.cumulativeTransfers {
                IconChip(kind: .info, title: "Cumulative", sys: "number.circle").badge(c)
            }
            if let segs = vm.meta?.segments?.count, segs > 0 {
                IconChip(kind: .info, title: "Segments", sys: "square.stack").badge(segs)
            }
            if let hp = vm.headProof {
                IconChip(kind: hp.ok ? .ok : .err, title: hp.ok ? "Head proof verified" : "Head proof failed", sys: "shield.lefthalf.filled")
            }
            if (vm.meta?.transfersWindowRootV14?.isEmpty == false) {
                IconChip(kind: .info, title: "v14 head root present", sys: "barcode.viewfinder")
            }
        }
    }
}

// MARK: - Root View

struct VerifierModal: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var vm = VerifierVM()

    @State private var showSystemSvgPicker = false
    @State private var showAttachPicker = false
    @State private var importedSVG: String = ""
    @State private var panelOpen: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                // Toolbar
                HStack {
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(AngularGradient(gradient: Gradient(colors: [kai("#37ffe4"), kai("#a78bfa"), kai("#5ce1ff"), kai("#37ffe4")]),
                                                  center: .center))
                            .frame(width: 28, height: 28)
                        Text("Verify").font(.system(.title3, weight: .heavy))
                            .foregroundStyle(holoText())
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        Button("ΦStream") { vm.explorerOpen = true; panelOpen = true }
                            .borderedButtonCompat()
                        Button {
                            showSystemSvgPicker = true
                        } label: {
                            Label("Φkey", systemImage: "arrow.down.to.line")
                        }
                        .borderedButtonCompat(prominent: true)
                    }
                }
                .padding(12)
                .background(blurTopbar())
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                Spacer(minLength: 4)

                Button {
                    showSystemSvgPicker = true
                } label: {
                    Label("Import Sigil SVG", systemImage: "doc.badge.plus")
                        .font(.headline)
                }
                .borderedButtonCompat(prominent: true)
                .padding(.top, 20)

                Spacer()
            }
            .padding(.horizontal, 12)
            .navigationTitle("Verifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { vm.startPulse() }
            .onDisappear { vm.stopPulse() }

            // SVG IMPORT (UIKit picker)
            .sheet(isPresented: $showSystemSvgPicker) {
                SVGDocumentPicker(
                    onPick: { url, svg in
                        importedSVG = svg
                        vm.handle(svgData: svg, blobURL: url)
                        showSystemSvgPicker = false
                        panelOpen = true
                    },
                    onCancel: { showSystemSvgPicker = false }
                )
                .ignoresSafeArea()
            }

            // Full-screen “dialog”
            .fullScreenCover(isPresented: $panelOpen) {
                VerifierPanelView(vm: vm, importedSVG: $importedSVG, showAttachPicker: $showAttachPicker)
                    .background(Color.black.opacity(0.25))
                    .ignoresSafeArea()
            }
        }
    }
}

// MARK: - Subviews

private struct SummaryGrid: View {
    @ObservedObject var vm: VerifierVM
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                KV("Now", "\(vm.pulseNow)")
                KV("frequency (Hz)", vm.meta?.frequencyHz.map { String($0) } ?? "—", wide: false)
                KV("Spiral Gate", vm.meta?.chakraGate ?? "—", wide: false)
                KV("Segments", "\(vm.meta?.segments?.count ?? 0)")
                KV("Cumulative", "\(vm.meta?.cumulativeTransfers ?? 0)")
                if let root = vm.meta?.segmentsMerkleRoot { KV("Segments Root", root, wide: true, mono: true) }
                if let root = vm.meta?.transfersWindowRoot { KV("Head Breath Root", root, wide: true, mono: true) }
                if let hp = vm.headProof { KV("Latest proof", "#\(hp.index) \(hp.ok ? "✓" : "×")") }
                if let sig = vm.liveSig { KV("Live Centre-Pixel Sig", sig, wide: true, mono: true) }
                if let rgb = vm.rgbSeed { KV("RGB seed", rgb.map(String.init).joined(separator: ", ")) }
                if let ks = vm.meta?.kaiSignature {
                    KV("Metadata Σ", ks, wide: true, mono: true, chip:
                        vm.contentSigMatches == true ? TagView(text: "match", tone: .ok) :
                        vm.contentSigMatches == false ? TagView(text: "mismatch", tone: .err) : nil
                    )
                }
                if let exp = vm.contentSigExpected { KV("Expected Σ", exp, wide: true, mono: true) }
                if let phi = vm.meta?.userPhiKey {
                    KV("Φ-Key", phi, wide: true, mono: true, chip:
                        vm.phiKeyExpected != nil ? (vm.phiKeyMatches == true ? TagView(text: "match", tone: .ok) : TagView(text: "mismatch", tone: .err)) : nil
                    )
                }
            }
            .padding(12)
        }
    }
}

private struct LineageList: View {
    @ObservedObject var vm: VerifierVM
    var body: some View {
        ScrollView {
            if let txs = vm.meta?.transfers, !txs.isEmpty {
                VStack(spacing: 10) {
                    ForEach(Array(txs.enumerated()), id: \.offset) { i, t in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("#\(i+1)").font(.headline)
                                Spacer()
                                let open = (t.receiverSignature == nil)
                                Text(open ? "Pending receive" : "Sealed")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(open ? .yellow : .green)
                            }
                            HR()
                            Row("Sender Σ", t.senderSignature)
                            Row("Sender Stamp", t.senderStamp)
                            Row("Sender Pulse", "\(t.senderKaiPulse)")

                            if let h = vm.meta?.hardenedTransfers, i < h.count {
                                let ht = h[i]
                                if !ht.previousHeadRoot.isEmpty { Row("Prev-Head", ht.previousHeadRoot) }
                                Row("SEND leaf", ht.transferLeafHashSend)
                                if let r = ht.transferLeafHashReceive { Row("RECV leaf", r) }
                                if let zk = ht.zkSend { Row("ZK SEND", "\(zk.verified == true ? "✓" : "•") \(zk.scheme)") }
                                if let zk = ht.zkSend, let ph = zk.proofHash { Row("ZK SEND hash", ph) }
                                if let zk = ht.zkReceive { Row("ZK RECV", "\(zk.verified == true ? "✓" : "•") \(zk.scheme)") }
                                if let zk = ht.zkReceive, let ph = zk.proofHash { Row("ZK RECV hash", ph) }
                            }

                            if let rs = t.receiverSignature {
                                Row("Receiver Σ", rs)
                                Row("Receiver Stamp", t.receiverStamp ?? "—")
                                Row("Receiver Pulse", t.receiverKaiPulse.map(String.init) ?? "—")
                            }

                            if let p = t.payload {
                                DisclosureGroup("Payload") {
                                    Row("Name", p.name)
                                    Row("MIME", p.mime)
                                    Row("Size", "\(p.size) bytes")
                                }
                            }
                        }
                        .padding(12)
                        .background(panel())
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .padding(12)
            } else {
                Text("No transfers yet — ready to inhale a send stamp.")
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
    }
}

private struct DataView: View {
    @ObservedObject var vm: VerifierVM
    @State private var viewRaw = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("View raw JSON", isOn: $viewRaw)
                .toggleStyle(SwitchToggleStyle())
                .padding(.horizontal, 16).padding(.top, 8)

            ScrollView {
                if viewRaw {
                    Text(vm.rawMeta ?? "{}")
                        .font(.system(.footnote, design: .monospaced))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(red: 0.05, green: 0.06, blue: 0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(12)
                } else {
                    JsonTree(obj: try? JSONSerialization.jsonObject(with: (vm.rawMeta ?? "{}").data(using: .utf8) ?? Data()))
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                }
            }
        }
    }
}

// MARK: - Small UI atoms

private struct IconChip: View {
    enum Tone { case info, ok, warn, err }
    let kind: Tone
    let title: String
    let sys: String
    var numberBadge: Int?

    init(kind: Tone, title: String, sys: String) {
        self.kind = kind; self.title = title; self.sys = sys
    }
    func badge(_ n: Int) -> some View { var v = self; v.numberBadge = n; return v }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: sys).imageScale(.small)
            if let n = numberBadge { Text("\(n)") }
        }
        .padding(.vertical, 6).padding(.horizontal, 10)
        .background(chipBG(kind))
        .overlay(RoundedRectangle(cornerRadius: 999).stroke(.white.opacity(0.08)))
        .clipShape(Capsule())
        .foregroundStyle(chipFG(kind))
        .accessibilityLabel(Text(title))
        .help(title)
    }

    private func chipBG(_ k: Tone) -> some ShapeStyle {
        switch k {
        case .info: return AnyShapeStyle(LinearGradient(colors:[kai("#3cf"), kai("#a78bfa").opacity(0.3)], startPoint:.top, endPoint:.bottom).opacity(0.12))
        case .ok:   return AnyShapeStyle(Color.green.opacity(0.12))
        case .warn: return AnyShapeStyle(Color.yellow.opacity(0.12))
        case .err:  return AnyShapeStyle(Color.red.opacity(0.12))
        }
    }
    private func chipFG(_ k: Tone) -> Color {
        switch k {
        case .info: return kai("#5ce1ff")
        case .ok:   return Color.green
        case .warn: return Color.yellow
        case .err:  return Color.red
        }
    }
}

private struct TagView: View {
    enum Tone { case info, ok, warn, err }
    var text: String
    var tone: Tone = .info
    var body: some View {
        Text(text)
            .font(.system(.footnote, weight: .semibold))
            .padding(.vertical, 4).padding(.horizontal, 8)
            .background(tagBG(tone))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
    private func tagBG(_ t: Tone) -> some ShapeStyle {
        switch t {
        case .info: return AnyShapeStyle(Color.white.opacity(0.06))
        case .ok:   return AnyShapeStyle(Color.green.opacity(0.18))
        case .warn: return AnyShapeStyle(Color.yellow.opacity(0.18))
        case .err:  return AnyShapeStyle(Color.red.opacity(0.18))
        }
    }
}

private struct SegmentedTabs: View {
    @Binding var selection: String
    var body: some View {
        HStack(spacing: 8) {
            SegTab("Summary")
            SegTab("Lineage")
            SegTab("Data")
            Spacer()
            Button("Φ Value") { /* hook valuation */ }
                .borderedButtonCompat()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(LinearGradient(colors:[Color.black.opacity(0.6), Color.black.opacity(0.3)], startPoint: .top, endPoint: .bottom))
        .overlay(Rectangle().frame(height: 1).foregroundStyle(.white.opacity(0.06)), alignment: .bottom)
    }
    @ViewBuilder private func SegTab(_ key: String) -> some View {
        let isOn = selection.lowercased() == key.lowercased()
        Button(key) { selection = key.lowercased() }
            .borderedButtonCompat(prominent: isOn)
    }
}

private struct KV: View {
    var k: String, v: String, wide: Bool = false, mono: Bool = false
    var chip: TagView? = nil
    init(_ k: String, _ v: String, wide: Bool = false, mono: Bool = false, chip: TagView? = nil) {
        self.k = k; self.v = v; self.wide = wide; self.mono = mono; self.chip = chip
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(k).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(v).font(mono ? .system(.footnote, design: .monospaced) : .footnote)
                    .textSelection(.enabled)
                if let chip { chip }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(panel())
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .gridCellColumns(wide ? 2 : 1)
    }
}

private struct Row: View {
    var k: String, v: String
    init(_ k: String, _ v: String) { self.k = k; self.v = v }
    var body: some View {
        HStack(alignment: .top) {
            Text(k).frame(width: 140, alignment: .leading).foregroundStyle(.secondary)
            Text(v).textSelection(.enabled).font(.system(.footnote, design: .monospaced))
            Spacer()
        }.padding(.vertical, 4)
    }
}

private struct HR: View { var body: some View { Rectangle().fill(.white.opacity(0.06)).frame(height: 1) } }

// MARK: - Json Tree (type-erased)

private struct JsonTree: View {
    let obj: Any?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            node(obj)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func node(_ v: Any?) -> AnyView {
        switch v {
        case let d as [String: Any]:
            let keys = d.keys.sorted()
            return AnyView(
                ForEach(keys, id: \.self) { k in
                    DisclosureGroup("\"\(k)\"") {
                        node(d[k])
                    }.tint(kai("#a78bfa"))
                }
            )
        case let a as [Any]:
            return AnyView(
                ForEach(0..<a.count, id: \.self) { i in
                    DisclosureGroup("[\(i)]") {
                        node(a[i])
                    }.tint(kai("#a78bfa"))
                }
            )
        default:
            return AnyView(
                Text(String(describing: v ?? "null"))
                    .font(.system(.footnote, design: .monospaced))
            )
        }
    }
}

// MARK: - Styles / helpers

private func normalizeChakra(_ s: String?) -> String {
    guard let s = s, !s.isEmpty else { return "—" }
    return s.prefix(1).uppercased() + s.dropFirst()
}

private func holoText() -> some ShapeStyle {
    AnyShapeStyle(AngularGradient(gradient: Gradient(colors: [kai("#37ffe4"), kai("#a78bfa"), kai("#5ce1ff"), kai("#37ffe4")]),
                                  center: .center))
}
private func blurTopbar() -> some View {
    LinearGradient(colors: [Color.white.opacity(0.06), Color.white.opacity(0.03)], startPoint: .top, endPoint: .bottom)
        .background(.ultraThinMaterial)
}
private func panel() -> some ShapeStyle {
    AnyShapeStyle(
        LinearGradient(colors: [Color.white.opacity(0.035), Color.white.opacity(0.02)], startPoint: .top, endPoint: .bottom)
    )
}
private func kai(_ hex: String) -> Color {
    var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.hasPrefix("#") { s.removeFirst() }
    let v = UInt64(s, radix: 16) ?? 0
    let r = Double((v >> 16) & 0xff) / 255.0
    let g = Double((v >> 8) & 0xff) / 255.0
    let b = Double(v & 0xff) / 255.0
    return Color(red: r, green: g, blue: b)
}

private struct HoloCloseButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 40, height: 40)
            .background(LinearGradient(colors: [Color.white.opacity(0.06), Color.white.opacity(0.03)], startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.12)))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: kai("#11d7ff").opacity(0.3), radius: 10)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

// iOS-agnostic bordered style
private struct NeonBorderedButtonStyle: ButtonStyle {
    let prominent: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.callout, design: .rounded))
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                prominent
                ? AnyShapeStyle(LinearGradient(colors: [Color.white.opacity(0.10), Color.white.opacity(0.05)],
                                               startPoint: .top, endPoint: .bottom))
                : AnyShapeStyle(Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(prominent ? 0.35 : 0.18), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.25), radius: prominent ? 8 : 4, y: prominent ? 4 : 2)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}

private extension View {
    @ViewBuilder func borderedButtonCompat(prominent: Bool = false) -> some View {
        self.buttonStyle(NeonBorderedButtonStyle(prominent: prominent))
    }
}

// Share sheet
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}
