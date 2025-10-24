//
//  VerifyHistorical.swift
//  KaiKlok
//
//  Created by BJ Klock on 10/16/25.
//

//
//  VerifyHistorical.swift
//  KaiKlok
//

import Foundation

public enum WVVerifyBundle {
    case head(windowMerkleRoot: String, transferProof: [String], leafHex: String, index: Int)
}

public func verifyHistorical(_ meta: WVSigilMetadata, _ bundle: WVVerifyBundle) -> Bool {
    switch bundle {
    case .head(let root, let proof, let leaf, let idx):
        // simple merkle check parity
        return verifyProof(rootHex: root, leafHex: leaf, index: idx, proofHex: proof)
    }
}
