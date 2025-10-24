//
//  Segments.swift
//  KaiKlok
//
//  Created by BJ Klock on 10/16/25.
//

import Foundation

// Local, file-private stringify to avoid cross-file symbol issues.
// Produces deterministic JSON with sorted keys (similar to TS stableStringify).
@inline(__always)
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

/// Rolls the current transfers window into a segment and returns updated metadata
/// plus a portable JSON blob describing the new segment.
///
/// - Returns: `(meta: updated metadata with head rolled, segmentFileData: optional JSON Data)`
public func sealCurrentWindowIntoSegment(_ m: WVSigilMetadata) -> (meta: WVSigilMetadata, segmentFileData: Data?) {
    var m = m
    let txs = m.transfers ?? []
    guard !txs.isEmpty else { return (m, nil) }

    // Compute window root from full leaves (sender+receiver)
    let leaves = txs.map { hashTransferFull($0) }
    let root = buildMerkleRoot(leaves)

    // Append segment
    var segs = m.segments ?? []
    segs.append(WVSegmentHead(root: root, count: leaves.count))
    m.segments = segs

    // Roll head window
    m.transfers = []
    m.cumulativeTransfers = (m.cumulativeTransfers ?? 0) + leaves.count
    m.segmentsMerkleRoot = buildMerkleRoot(segs.map { $0.root })

    // Emit a compact segment descriptor JSON (portable for disk/export)
    let payload: [String: Any] = [
        "pulse": m.pulse ?? 0,
        "segmentIndex": segs.count - 1,
        "root": root,
        "count": leaves.count
    ]
    let jsonStr: String = wvStableStringify(payload)
    let data = jsonStr.data(using: String.Encoding.utf8)

    return (m, data)
}
