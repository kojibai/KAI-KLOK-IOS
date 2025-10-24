//
//  WithdrawToSigilView.swift
//  KaiKlok
//
//  Created by BJ Klock on 10/15/25.
//

import SwiftUI

struct WithdrawToSigilView: View {
    @ObservedObject var identity = SigilIdentityManager.shared
    @State private var withdrawnNote: PhiNote? = nil
    @State private var isWithdrawing = false

    var balance: Double {
        identity.currentPhiKey?.balancePhi ?? 0.0
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                if let note = withdrawnNote {
                    Text("Sealed Note Created")
                        .font(.title2.bold())
                    
                    Text("Φ \(String(format: "%.4f", note.phiAmount))")
                        .font(.title)

                    if let qr = QRGenerator.generateQR(note) {
                        Image(uiImage: qr)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                            .frame(width: 220, height: 220)
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
                        withdrawnNote = nil
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top)
                } else {
                    VStack(spacing: 16) {
                        Text("Withdraw All to Note")
                            .font(.headline)

                        Text("Current Balance: Φ \(String(format: "%.4f", balance))")
                            .foregroundColor(.secondary)

                        Button("Seal Balance") {
                            Task {
                                isWithdrawing = true
                                if balance > 0 {
                                    if let note = await ExhaleEngine.shared.exhale(amountPhi: balance) {
                                        withdrawnNote = note
                                    }
                                }
                                isWithdrawing = false
                            }
                        }
                        .disabled(balance <= 0 || isWithdrawing)
                        .buttonStyle(.borderedProminent)
                    }
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Withdraw")
        }
    }
}
