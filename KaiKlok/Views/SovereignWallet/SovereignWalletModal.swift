//  SovereignWalletModal.swift
//  KaiKlok
//
//  Created by BJ Klock on 10/15/25.
//

import SwiftUI

// Make the inhale result usable with `.sheet(item:)`
extension InhaleEngine.InhaleResult: Identifiable {
    // Use the Kai signature (already unique/deterministic for the inhale) as the stable identity.
    var id: String { kaiSignature }
}

struct SovereignWalletModal: View {
    @ObservedObject var identity = SigilIdentityManager.shared
    @ObservedObject var storage = WalletStorage.shared

    @State private var showInhaleResult: InhaleEngine.InhaleResult? = nil
    @State private var showSendModal = false
    @State private var showExhale = false
    @State private var showWithdraw = false
    @State private var showVault = false

    var body: some View {
        VStack(spacing: 24) {
            // 🧿 Identity
            if let key = identity.currentPhiKey {
                BalanceCard(phi: key.balancePhi, usd: key.balanceUSD)

                HStack(spacing: 16) {
                    InhaleButton {
                        Task {
                            if let result = await InhaleEngine.shared.inhale() {
                                showInhaleResult = result
                            }
                        }
                    }

                    Button("Exhale") {
                        showExhale = true
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Send Φ") {
                        showSendModal = true
                    }
                    .buttonStyle(.bordered)
                }

                HStack(spacing: 16) {
                    Button("Withdraw") {
                        showWithdraw = true
                    }
                    .buttonStyle(.bordered)

                    Button("Vault") {
                        showVault = true
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Text("No ΦKey Registered")
                    .foregroundColor(.red)
            }

            Spacer()
        }
        .padding()
        .sheet(item: $showInhaleResult) { result in
            VStack(spacing: 20) {
                Text("Inhaled:")
                    .font(.headline)
                Text("Φ \(String(format: "%.4f", result.phiAmount))")
                    .font(.largeTitle.bold())
                Text("≈ $\(String(format: "%.2f", result.usdValue))")
                    .foregroundColor(.secondary)
                Text(
                    PulseFormatter.formatKaiTimestamp(
                        pulse: result.pulse,
                        beat: result.beat,
                        step: result.stepIndex,
                        chakraDay: result.chakraDay
                    )
                )
                .font(.footnote)
                .multilineTextAlignment(.center)
            }
            .padding()
        }
        .sheet(isPresented: $showSendModal) {
            SendPhiModal()
        }
        .sheet(isPresented: $showExhale) {
            ExhaleNoteView()
        }
        .sheet(isPresented: $showWithdraw) {
            WithdrawToSigilView()
        }
        .sheet(isPresented: $showVault) {
            NoteHistoryView()
        }
    }
}
