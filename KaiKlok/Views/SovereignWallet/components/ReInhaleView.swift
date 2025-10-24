//  ReInhaleView.swift
//  KaiKlok
//
//  Created by BJ Klock on 10/15/25.
//

import SwiftUI

// MARK: - App-wide signal your model layer can observe (optional but useful)
extension Notification.Name {
    /// Payload:
    ///  - fromKeyId: String
    ///  - phiDelta: Double
    ///  - usdDelta: Double
    ///  - lastPulse: Int
    static let kaiReInhaleRequested = Notification.Name("kai.reInhale.requested")
}

struct ReInhaleView: View {
    @ObservedObject var identity = SigilIdentityManager.shared
    @State private var scannedNote: PhiNote? = nil
    @State private var accepted = false

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if let note = scannedNote {
                    Text("Scanned Note")
                        .font(.headline)

                    Text("Φ \(String(format: "%.4f", note.phiAmount))")
                        .font(.title)

                    Text(
                        PulseFormatter.formatKaiTimestamp(
                            pulse: note.pulse,
                            beat: note.beat,
                            step: note.stepIndex,
                            chakraDay: note.chakraDay
                        )
                    )
                    .font(.caption)
                    .multilineTextAlignment(.center)

                    if accepted {
                        Text("✅ Re-inhaled into balance")
                            .foregroundColor(.green)
                            .padding(.top)
                    } else {
                        Button("Re-Inhale Now") {
                            guard let key = identity.currentPhiKey,
                                  key.id == note.fromPhiKey else {
                                return
                            }

                            // Compute deltas locally
                            let phiDelta = note.phiAmount
                            let usdDelta = quotedUSD(for: note.phiAmount)

                            // Hand off to your model layer to actually mutate/persist balances.
                            // (Avoids touching currentPhiKey's private setter from here.)
                            NotificationCenter.default.post(
                                name: .kaiReInhaleRequested,
                                object: nil,
                                userInfo: [
                                    "fromKeyId": key.id,
                                    "phiDelta": phiDelta,
                                    "usdDelta": usdDelta,
                                    "lastPulse": note.pulse
                                ]
                            )

                            accepted = true
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(accepted)
                    }

                    Button("Scan Another") {
                        scannedNote = nil
                        accepted = false
                    }
                    .padding(.top)
                } else {
                    QRScannerView<PhiNote> { note in
                        if let note = note {
                            scannedNote = note
                        }
                    }
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Re-Inhale Note")
        }
    }

    /// Public helper to quote USD for a Φ amount without touching private engine APIs.
    /// Replace the conversion logic with your live valuation if desired.
    private func quotedUSD(for phiAmount: Double) -> Double {
        // Simple default: 1 Φ = 1 USD (placeholder)
        // If you have a public valuation source, swap it in here.
        return phiAmount * 1.0
    }
}
