//
//  SigilIdentityManager.swift
//  KaiKlok
//
//  Created by BJ Klock on 10/15/25.
//

import Foundation
import CryptoKit

@MainActor
final class SigilIdentityManager: ObservableObject {
    static let shared = SigilIdentityManager()
    
    @Published private(set) var currentPhiKey: PhiKey? = nil
    private let keyFileName = "phikey.json"
    
    private init() {
        loadPhiKey()
    }
    
    // MARK: - Registration
    
    func registerNewPhiKey(from sigilSVG: String) {
        let hash = Self.hashSigil(sigilSVG)
        
        let newKey = PhiKey(
            id: UUID().uuidString,
            sigilHash: hash,
            balancePhi: 0.0,
            balanceUSD: 0.0,
            createdAt: Date(),
            lastPulse: 0
        )
        
        currentPhiKey = newKey
        savePhiKey(newKey)
    }
    
    func isRegistered() -> Bool {
        return currentPhiKey != nil
    }
    
    // MARK: - Local Persistence
    
    private func savePhiKey(_ key: PhiKey) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(key) {
            let url = Self.getPhiKeyURL(fileName: keyFileName)
            try? data.write(to: url, options: .atomic)
        }
    }
    
    private func loadPhiKey() {
        let url = Self.getPhiKeyURL(fileName: keyFileName)
        guard let data = try? Data(contentsOf: url) else { return }
        if let key = try? JSONDecoder().decode(PhiKey.self, from: data) {
            currentPhiKey = key
        }
    }
    
    // MARK: - Utilities
    
    static func hashSigil(_ sigilSVG: String) -> String {
        let data = Data(sigilSVG.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    static func getPhiKeyURL(fileName: String) -> URL {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return directory.appendingPathComponent(fileName)
    }
}
