//
//  NoteHistoryView.swift
//  KaiKlok
//
//  Created by BJ Klock on 10/15/25.
//

import SwiftUI

struct NoteHistoryView: View {
    @ObservedObject var storage = WalletStorage.shared

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    ForEach(storage.notes.sorted(by: { $0.timestamp > $1.timestamp })) { note in
                        VStack(spacing: 8) {
                            HStack {
                                Text("Φ \(String(format: "%.4f", note.phiAmount))")
                                    .font(.title2.bold())
                                Spacer()
                                Text(note.isSpent ? "Spent" : "Active")
                                    .foregroundColor(note.isSpent ? .red : .green)
                                    .font(.caption)
                            }

                            Text(PulseFormatter.formatKaiTimestamp(
                                pulse: note.pulse,
                                beat: note.beat,
                                step: note.stepIndex,
                                chakraDay: note.chakraDay
                            ))
                            .font(.caption)
                            .foregroundColor(.secondary)

                            if let qr = QRGenerator.generateQR(note) {
                                Image(uiImage: qr)
                                    .resizable()
                                    .interpolation(.none)
                                    .scaledToFit()
                                    .frame(width: 180, height: 180)
                            }
                        }
                        .padding()
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
                        .shadow(radius: 2)
                    }

                    if storage.notes.isEmpty {
                        Text("No exhaled notes yet.")
                            .foregroundColor(.secondary)
                            .padding(.top)
                    }
                }
                .padding()
            }
            .navigationTitle("Vault")
        }
    }
}
