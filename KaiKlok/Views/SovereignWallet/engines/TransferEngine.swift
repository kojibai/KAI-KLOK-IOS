//  TransferEngine.swift
//  KaiKlok
//
//  Created by BJ Klock on 10/15/25.
//

import Foundation

// MARK: - Local Kai canon (file-scoped; avoids cross-file private deps)

fileprivate let GENESIS_TS: Date = {
    var comps = DateComponents()
    comps.calendar = Calendar(identifier: .gregorian)
    comps.timeZone = TimeZone(secondsFromGMT: 0)
    comps.year = 2024; comps.month = 5; comps.day = 10
    comps.hour = 6; comps.minute = 45; comps.second = 41; comps.nanosecond = 888_000_000
    return comps.date ?? Date(timeIntervalSince1970: 0)
}()

/// φ-exact breath ≈ 5.236067977 s (KKS v1.0)
fileprivate let KAI_PULSE_SEC: Double = 3.0 + sqrt(5.0)

/// μ-pulse fixed-point
fileprivate let ONE_PULSE_MICRO: Int64 = 1_000_000
fileprivate let N_DAY_MICRO: Int64 = 17_491_270_421
fileprivate let PULSES_PER_STEP_MICRO: Int64 = 11_000_000
/// EXACT μpulses-per-beat with ties-to-even: (N_DAY_MICRO + 18)/36
fileprivate let MU_PER_BEAT_EXACT: Int64 = (N_DAY_MICRO + 18) / 36
fileprivate let DAYS_PER_WEEK = 6

@inline(__always) fileprivate func imod(_ n: Int64, _ m: Int64) -> Int64 {
    let r = n % m; return (r + m) % m
}
@inline(__always) fileprivate func floorDiv(_ n: Int64, _ d: Int64) -> Int64 {
    precondition(d != 0)
    let q = n / d
    let r = n % d
    return (r != 0 && ((r > 0) != (d > 0))) ? (q - 1) : q
}
fileprivate func roundTiesToEvenInt64(_ x: Double) -> Int64 {
    if !x.isFinite { return 0 }
    let sgn: Double = x < 0 ? -1 : 1
    let ax = abs(x)
    let i = floor(ax)
    let frac = ax - i
    if frac < 0.5 { return Int64(sgn * i) }
    if frac > 0.5 { return Int64(sgn * (i + 1)) }
    let even = (Int(i) % 2 == 0) ? i : (i + 1)
    return Int64(sgn * even)
}
fileprivate func microPulsesSinceGenesis(_ date: Date) -> Int64 {
    let delta = date.timeIntervalSince(GENESIS_TS) // seconds
    let pulses = delta / KAI_PULSE_SEC
    let micro = pulses * 1_000_000.0
    return roundTiesToEvenInt64(micro)
}

/// Minimal Kai snapshot for engines
fileprivate struct KaiNow {
    let pulse: Int
    let beat: Int
    let step: Int          // 0..43
    let chakraDay: String  // label parity with UI
}

fileprivate func kaiNow(at date: Date) -> KaiNow {
    let pμ_total = microPulsesSinceGenesis(date)
    let pμ_in_day = imod(pμ_total, N_DAY_MICRO)
    let dayIndex = floorDiv(pμ_total, N_DAY_MICRO)

    // beat/step using μ-pulses
    let beatI64 = floorDiv(pμ_in_day, MU_PER_BEAT_EXACT)
    let pμ_in_beat = pμ_in_day - beatI64 * MU_PER_BEAT_EXACT
    let rawStep = Int(pμ_in_beat / PULSES_PER_STEP_MICRO)
    let step = max(0, min(rawStep, 44 - 1))

    // whole pulses
    let pulse = Int(floorDiv(pμ_total, ONE_PULSE_MICRO))
    let beat = Int(beatI64)

    // chakra day from harmonic weekday (0..5)
    let harmonicDayIndex = Int(imod(dayIndex, Int64(DAYS_PER_WEEK)))
    let chakra: String
    switch harmonicDayIndex {
    case 0: chakra = "Root"         // Solhara
    case 1: chakra = "Sacral"       // Aquaris
    case 2: chakra = "Solar Plexus" // Flamora
    case 3: chakra = "Heart"        // Verdari
    case 4: chakra = "Throat"       // Sonari
    default: chakra = "Crown"       // Kaelith
    }

    return .init(pulse: pulse, beat: beat, step: step, chakraDay: chakra)
}

// MARK: - Transfer Engine

/// Drafts and commits transfer notes (send flow). Does **not** mutate `currentPhiKey`
/// directly (its setter is private). Let your UI or a dedicated balance engine
/// apply balance changes after a successful transfer.
@MainActor
final class TransferEngine {
    static let shared = TransferEngine()
    private init() {}

    struct TransferDraft {
        let note: PhiNote
        /// Optional: JSON you might encode into a QR for the recipient.
        let payloadJSON: String
    }

    /// Create a draft `PhiNote` representing a send from the current key.
    /// This does **not** change balances; call `commitSend(_:)` to persist the note,
    /// and then adjust balances via your identity manager’s public mutator.
    func draftSend(amountPhi: Double) -> TransferDraft? {
        guard let key = SigilIdentityManager.shared.currentPhiKey else { return nil }
        guard amountPhi > 0.0, amountPhi <= key.balancePhi else { return nil }

        let now = Date()
        let k = kaiNow(at: now)

        // Use a public/non-private quote (mirror InhaleEngine's policy if desired)
        let usdValue = usdQuote(for: amountPhi)

        // Deterministic signature (include sender, amount, pulse, and sigil hash)
        let signatureInput = "\(key.id)-\(amountPhi)-\(k.pulse)-\(key.sigilHash)"
        let kaiSignature = KaiSignature.hash(signatureInput)

        let note = PhiNote(
            id: UUID().uuidString,
            phiAmount: amountPhi,
            usdValue: usdValue,
            pulse: k.pulse,
            beat: k.beat,
            stepIndex: k.step,
            chakraDay: k.chakraDay,
            sigilHash: key.sigilHash,
            fromPhiKey: key.id,
            kaiSignature: kaiSignature,
            timestamp: now,
            isSpent: false
        )

        // Minimal JSON payload for QR / sharing (matches your existing fields)
        let payload: [String: Any] = [
            "id": note.id,
            "phiAmount": note.phiAmount,
            "usdValue": note.usdValue,
            "pulse": note.pulse,
            "beat": note.beat,
            "stepIndex": note.stepIndex,
            "chakraDay": note.chakraDay,
            "sigilHash": note.sigilHash,
            "fromPhiKey": note.fromPhiKey,
            "kaiSignature": note.kaiSignature
        ]

        let json: String
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
           let s = String(data: data, encoding: .utf8) {
            json = s
        } else {
            json = "{}"
        }

        return TransferDraft(note: note, payloadJSON: json)
    }

    /// Persist the note locally (e.g., outbox/history). Does **not** touch balances.
    func commitSend(_ draft: TransferDraft) {
        WalletStorage.shared.addNote(draft.note)
        // Balance changes should be applied by a dedicated method on SigilIdentityManager,
        // e.g. `SigilIdentityManager.shared.applyBalanceChange(phiDelta:usdDelta:lastPulse:)`
        // to avoid accessing a private setter.
    }

    // MARK: - Quote

    /// Public USD quote helper for transfers (kept here to avoid depending on any private APIs).
    func usdQuote(for phi: Double) -> Double {
        let fixedRate = 33.33 // Example: 1 Φ = $33.33 (align with your InhaleEngine policy)
        return phi * fixedRate
    }
}
