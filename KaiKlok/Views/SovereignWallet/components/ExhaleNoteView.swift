//
//  ExhaleNoteView.swift
//  KaiKlok
//
//  Created by BJ Klock on 10/15/25.
//

import SwiftUI

struct ExhaleNoteView: View {
    @ObservedObject var identity = SigilIdentityManager.shared
    @State private var amountPhi: Double = 0.1
    @State private var mintedNote: PhiNote? = nil
    @State private var isExhaling = false

    var max: Double {
        identity.currentPhiKey?.balancePhi ?? 0.0
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if let note = mintedNote {
                    Text("✅ Note Minted")
                        .font(.title2.bold())
                    Text("Φ \(String(format: "%.4f", note.phiAmount))")
                        .font(.title)

                    if let image = QRGenerator.generateQR(note) {
                        Image(uiImage: image)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                            .frame(width: 200, height: 200)
                            .padding(.top)
                    }

                    Text(PulseFormatter.formatKaiTimestamp(
                        pulse: note.pulse,
                        beat: note.beat,
                        step: note.stepIndex,
                        chakraDay: note.chakraDay
                    ))
                        .font(.caption)
                        .multilineTextAlignment(.center)

                    Button("Done") {
                        mintedNote = nil
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top)
                } else {
                    VStack(spacing: 16) {
                        Text("Exhale Value")
                            .font(.headline)

                        Slider(value: $amountPhi, in: 0.01...max, step: 0.01)
                        Text("Φ \(String(format: "%.4f", amountPhi)) / \(String(format: "%.4f", max))")

                        Button(action: {
                            Task {
                                isExhaling = true
                                if let note = await ExhaleEngine.shared.exhale(amountPhi: amountPhi) {
                                    mintedNote = note
                                }
                                isExhaling = false
                            }
                        }) {
                            Text("Exhale Now")
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(amountPhi <= 0 || amountPhi > max || isExhaling)
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding()
            .navigationTitle("Exhale Note")
        }
    }
}
