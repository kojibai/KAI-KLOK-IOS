//
//  SigilLineage.swift
//  KaiKlok
//
//  Created by BJ Klock on 10/16/25.
//

import Foundation

// Sender-side leaf (no receiver fields)
public func hashTransferSenderSide(_ t: WVSigilTransfer) -> String {
    let obj: [String: Any] = [
        "senderSignature": t.senderSignature,
        "senderStamp": t.senderStamp,
        "senderKaiPulse": t.senderKaiPulse,
        "payload": t.payload != nil ? [
            "name": t.payload!.name, "mime": t.payload!.mime, "size": t.payload!.size, "encoded": t.payload!.encoded
        ] : NSNull()
    ]
    return WVHash.sha256Hex(WVCodec.stableStringify(obj))
}

// Full leaf (sender+receiver)
public func hashTransferFull(_ t: WVSigilTransfer) -> String {
    let obj: [String: Any] = [
        "senderSignature": t.senderSignature,
        "senderStamp": t.senderStamp,
        "senderKaiPulse": t.senderKaiPulse,
        "receiverSignature": t.receiverSignature as Any,
        "receiverStamp": t.receiverStamp as Any,
        "receiverKaiPulse": t.receiverKaiPulse as Any,
        "payload": t.payload != nil ? [
            "name": t.payload!.name, "mime": t.payload!.mime, "size": t.payload!.size, "encoded": t.payload!.encoded
        ] : NSNull()
    ]
    return WVHash.sha256Hex(WVCodec.stableStringify(obj))
}

// v14: what the previous head root *should* be for an insertion at index
public func expectedPrevHeadRootV14(_ m: WVSigilMetadata, _ index: Int) -> String {
    let v14 = m.hardenedTransfers ?? []
    if index == 0 { return m.transfersWindowRootV14 ?? (m.transfersWindowRoot ?? "") }
    let slice = Array(v14.prefix(index))
    let leaves = slice.map { ht -> String in
        var mini: [String: Any] = [
            "previousHeadRoot": ht.previousHeadRoot,
            "senderPubKey": ht.senderPubKey,
            "senderSig": ht.senderSig,
            "senderKaiPulse": ht.senderKaiPulse,
            "nonce": ht.nonce,
            "transferLeafHashSend": ht.transferLeafHashSend,
            "receiverPubKey": ht.receiverPubKey as Any? ?? NSNull(),
            "receiverSig": ht.receiverSig as Any? ?? NSNull(),
            "receiverKaiPulse": ht.receiverKaiPulse as Any? ?? NSNull(),
            "transferLeafHashReceive": ht.transferLeafHashReceive as Any? ?? NSNull()
        ]
        if let zk = ht.zkSend {
            mini["zkSend"] = [
                "scheme": zk.scheme, "curve": zk.curve,
                "publicHash": zk.publicHash as Any? ?? NSNull(),
                "proofHash": zk.proofHash as Any? ?? NSNull(),
                "vkeyHash": zk.vkeyHash as Any? ?? NSNull()
            ]
        } else { mini["zkSend"] = NSNull() }
        if let zk = ht.zkReceive {
            mini["zkReceive"] = [
                "scheme": zk.scheme, "curve": zk.curve,
                "publicHash": zk.publicHash as Any? ?? NSNull(),
                "proofHash": zk.proofHash as Any? ?? NSNull(),
                "vkeyHash": zk.vkeyHash as Any? ?? NSNull()
            ]
        } else { mini["zkReceive"] = NSNull() }
        return WVHash.sha256Hex(WVCodec.stableStringify(mini))
    }
    return buildMerkleRoot(leaves)
}
