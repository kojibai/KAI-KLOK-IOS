//  ExhaleEngine.swift
//  KaiKlok
//
//  Created by BJ Klock on 10/15/25.
//

import Foundation

// MARK: - Canon (local bridge; mirrors KaiSigilSwiftUI canon)

fileprivate let GENESIS_TS: Date = {
    var comps = DateComponents()
    comps.calendar = Calendar(identifier: .gregorian)
    comps.timeZone = TimeZone(secondsFromGMT: 0)
    comps.year = 2024; comps.month = 5; comps.day = 10
    comps.hour = 6; comps.minute = 45; comps.second = 41; comps.nanosecond = 888_000_000
    return comps.date ?? Date(timeIntervalSince1970: 0)
}()

fileprivate let KAI_PULSE_SEC: Double = 3.0 + sqrt(5.0)
fileprivate let ONE_PULSE_MICRO: Int64 = 1_000_000
fileprivate let N_DAY_MICRO: Int64 = 17_491_270_421
fileprivate let PULSES_PER_STEP_MICRO: Int64 = 11_000_000
/// EXACT μpulses-per-beat (ties-to-even): (N_DAY_MICRO + 18)/36
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

/// Minimal Kai bridge for engines: pulse/beat/step/chakraDay (string)
fileprivate struct KaiNow {
    let pulse: Int
    let beat: Int
    let step: Int
    let chakraDay: String
}

fileprivate func kaiNow(at date: Date) -> KaiNow {
    let pμ_total = microPulsesSinceGenesis(date)
    let pμ_in_day = imod(pμ_total, N_DAY_MICRO)
    let dayIndex = floorDiv(pμ_total, N_DAY_MICRO)

    // beat/step using μpulses
    let beatI64 = floorDiv(pμ_in_day, MU_PER_BEAT_EXACT)
    let pμ_in_beat = pμ_in_day - beatI64 * MU_PER_BEAT_EXACT
    let rawStep = Int(pμ_in_beat / PULSES_PER_STEP_MICRO)
    let step = max(0, min(rawStep, 44 - 1))

    // whole pulses
    let pulse = Int(floorDiv(pμ_total, ONE_PULSE_MICRO))
    let beat = Int(beatI64)

    // chakra day from harmonic weekday (0..5)
    let harmonicDayIndex = Int(imod(dayIndex, Int64(DAYS_PER_WEEK)))
    // Map → Chakra label
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

// Simple public USD quote used in engines/UI (decoupled from private InhaleEngine API)
fileprivate func quotedUSD(for phiAmount: Double) -> Double {
    // Placeholder parity: 1 Φ = 1 USD. Replace with live valuation when available.
    return phiAmount * 1.0
}

// MARK: - ExhaleEngine

@MainActor
final class ExhaleEngine {
    static let shared = ExhaleEngine()
    private init() {}

    /// Creates a PhiNote “exhale” from the current Kai moment and persists it.
    /// - Returns: The created note, or `nil` if validation fails.
    func exhale(amountPhi: Double) async -> PhiNote? {
        guard var key = SigilIdentityManager.shared.currentPhiKey else { return nil }
        guard amountPhi > 0.0, amountPhi <= key.balancePhi else { return nil }

        // 1) Current Kai time (μpulse canon)
        let now = Date()
        let k = kaiNow(at: now)

        // 2) Valuation + references
        let usdValue = quotedUSD(for: amountPhi)
        let sigilHash = key.sigilHash

        // 3) Deterministic signature (adjust as needed)
        let signatureInput = "\(key.id)-\(amountPhi)-\(k.pulse)-\(sigilHash)"
        let kaiSignature = KaiSignature.hash(signatureInput)

        // 4) Build note
        let note = PhiNote(
            id: UUID().uuidString,
            phiAmount: amountPhi,
            usdValue: usdValue,
            pulse: k.pulse,
            beat: k.beat,
            stepIndex: k.step,
            chakraDay: k.chakraDay,
            sigilHash: sigilHash,
            fromPhiKey: key.id,
            kaiSignature: kaiSignature,
            timestamp: now,
            isSpent: false
        )

        // 5) Persist note and adjust local balances
        WalletStorage.shared.addNote(note)
        key.balancePhi -= amountPhi
        key.balanceUSD -= usdValue
        key.lastPulse = k.pulse

        // IMPORTANT:
        // currentPhiKey has a private setter, so we cannot assign it here.
        // If you expose a public mutator (e.g., SigilIdentityManager.shared.updateCurrentPhiKey(key)),
        // you can write it back by uncommenting the next line:
        // SigilIdentityManager.shared.updateCurrentPhiKey(key)

        // Optionally rotate/register a new key lineage if desired:
        SigilIdentityManager.shared.registerNewPhiKey(from: key.sigilHash)

        return note
    }
}
