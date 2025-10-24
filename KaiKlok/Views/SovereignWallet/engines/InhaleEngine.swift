//  InhaleEngine.swift
//  KaiKlok
//
//  Created by BJ Klock on 10/15/25.
//

import Foundation

// MARK: - Canon bridge (kept local to avoid cross-module private deps)

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

// MARK: - Inhale Engine

@MainActor
final class InhaleEngine {
    static let shared = InhaleEngine()
    private init() {}

    struct InhaleResult {
        let phiAmount: Double
        let usdValue: Double
        let pulse: Int
        let beat: Int
        let stepIndex: Int
        let chakraDay: String
        let kaiSignature: String
    }

    /// Inhale to mint new value based on the current Kai Pulse.
    func inhale() async -> InhaleResult? {
        guard let key = SigilIdentityManager.shared.currentPhiKey else { return nil }

        // 1) Current Kai time (μ-pulse canon)
        let now = Date()
        let k = kaiNow(at: now)

        // 2) Calculate issuance + valuation
        let phiAmount = Self.issuedPhiAmount(at: k.pulse)
        let usdValue  = Self.quotedUSD(for: phiAmount)

        // 3) Deterministic KaiSignature (adjust as needed)
        let sealInput = "\(key.id)-\(phiAmount)-\(k.pulse)-\(k.chakraDay)"
        let kaiSignature = KaiSignature.hash(sealInput)

        // 4) Update balances — NOTE: currentPhiKey has a private setter, so we cannot assign.
        // If you expose a public mutator (e.g. SigilIdentityManager.shared.updateCurrentPhiKey(_:)),
        // apply the credited balances there.
        // Example (when available):
        // var updated = key
        // updated.balancePhi += phiAmount
        // updated.balanceUSD += usdValue
        // updated.lastPulse = k.pulse
        // SigilIdentityManager.shared.updateCurrentPhiKey(updated)

        // Optional lineage/rotation hook if desired:
        // SigilIdentityManager.shared.registerNewPhiKey(from: key.sigilHash)

        return InhaleResult(
            phiAmount: phiAmount,
            usdValue: usdValue,
            pulse: k.pulse,
            beat: k.beat,
            stepIndex: k.step,
            chakraDay: k.chakraDay,
            kaiSignature: kaiSignature
        )
    }

    // MARK: - Issuance & Quote

    /// Example issuance policy: 0.618 Φ per breath, lightly modulated by a 144-pulse sine.
    private static func issuedPhiAmount(at pulse: Int) -> Double {
        let base = 0.61803398875
        let modulator = 1.0 + sin(Double(pulse % 144) / 144.0 * 2.0 * .pi) * 0.08
        return base * modulator
    }

    /// Public engine quote (used by UI and tests as needed).
    /// Swap for a live oracle when available.
    static func quotedUSD(for phi: Double) -> Double {
        let fixedRate = 33.33 // Example: 1 Φ = $33.33
        return phi * fixedRate
    }
}
