//
//  WalletStorage.swift
//  KaiKlok
//
//  Created by BJ Klock on 10/15/25.
//

import Foundation

@MainActor
final class WalletStorage: ObservableObject {
    static let shared = WalletStorage()
    
    // MARK: - Published State
    @Published var notes: [PhiNote] = []
    @Published var transfers: [TransferIntent] = []
    
    private let notesFile = "phi_notes.json"
    private let transfersFile = "phi_transfers.json"
    
    private init() {
        loadNotes()
        loadTransfers()
    }
    
    // MARK: - Notes
    
    func addNote(_ note: PhiNote) {
        notes.append(note)
        saveNotes()
    }
    
    func markNoteSpent(_ noteID: String) {
        if let index = notes.firstIndex(where: { $0.id == noteID }) {
            notes[index] = notes[index].spentVersion()
            saveNotes()
        }
    }
    
    private func saveNotes() {
        saveJSON(notes, to: notesFile)
    }
    
    private func loadNotes() {
        notes = loadJSON(from: notesFile) ?? []
    }
    
    // MARK: - Transfers
    
    func addTransfer(_ intent: TransferIntent) {
        transfers.append(intent)
        saveTransfers()
    }
    
    func confirmTransfer(_ intentID: String) {
        if let index = transfers.firstIndex(where: { $0.id == intentID }) {
            transfers[index] = transfers[index].confirmedVersion()
            saveTransfers()
        }
    }
    
    private func saveTransfers() {
        saveJSON(transfers, to: transfersFile)
    }
    
    private func loadTransfers() {
        transfers = loadJSON(from: transfersFile) ?? []
    }
    
    // MARK: - JSON Helpers
    
    private func saveJSON<T: Encodable>(_ obj: T, to file: String) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(obj) {
            let url = Self.getURL(for: file)
            try? data.write(to: url, options: .atomic)
        }
    }
    
    private func loadJSON<T: Decodable>(from file: String) -> T? {
        let url = Self.getURL(for: file)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
    
    private static func getURL(for fileName: String) -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent(fileName)
    }
}
