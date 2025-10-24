//  KaiValuation.swift
//  KaiKlok
//
//  Created by BJ Klock on 10/13/25.
//
//  Swift port of valuation.ts (vφ-5 “Harmonia”) — deterministic, φ-anchored.
//  Produces a reproducible premium/valueΦ and exposes a compact USD/Φ index
//  for UI (we map price ≈ baseUSDPerPhi * premium).
//
//  Notes
//  - This is a literal, side-effect-free engine (no network, no RNG).
//  - We keep exact Fibonacci/Lucas checks in UInt64 space (safe for Kai pulses).
//  - Pulses per day constant mirrors TS policy (17491.270421).
//

import Foundation

// MARK: - Public surface

public enum KaiValuation {
    // Golden ratio
    internal static let PHI: Double = (1 + sqrt(5)) / 2

    // Canon rhythm
    public static let defaultStepsPerBeat: Int = 44         // 44 steps/beat
    public static let pulsesPerStep: Int = 11               // 11 pulses/step
    public static let pulsesPerBeatCanon: Int = 44 * 11     // 484
    public static let pulsesPerDayExact: Double = 17_491.270421

    // Small “index” scaler for UI (maps dimensionless premium → USD/Φ)
    public static var indexBaseUSDPerPhi: Double = 1.000

    // MARK: Types (Swift mirrors of TS)

    public struct Transfer {
        public var senderKaiPulse: Int
        public var receiverKaiPulse: Int? // nil if open
        public init(senderKaiPulse: Int, receiverKaiPulse: Int?) {
            self.senderKaiPulse = senderKaiPulse; self.receiverKaiPulse = receiverKaiPulse
        }
    }

    public struct IPFlow {
        public var atPulse: Int
        public var amountPhi: Double
        public init(atPulse: Int, amountPhi: Double) { self.atPulse = atPulse; self.amountPhi = amountPhi }
    }

    public struct Metadata {
        // Kai identity
        public var kaiPulse: Int?                 // claim pulse (preferred)
        public var pulse: Int?                    // legacy alias
        public var userPhiKey: String? = nil

        // geometry/rhythm
        public var beat: Int? = nil
        public var stepIndex: Int? = nil          // 0..(stepsPerBeat-1)
        public var stepsPerBeat: Int? = nil       // default 44

        // craft signals
        public var seriesSize: Int? = 1
        public enum Quality: String { case low, med, high }
        public var quality: Quality = .med
        public var creatorVerified: Bool = false
        public var creatorRep: Double = 0         // 0..1

        // resonance
        public var frequencyHz: Double? = nil

        // lineage
        public var transfers: [Transfer] = []
        public var cumulativeTransfers: Int? = nil

        // optional intrinsic IP cashflows (in Φ at future Kai pulses)
        public var ipCashflows: [IPFlow] = []

        // policy id hook
        public var valuationPolicyId: String? = nil

        public init() {}

        public static func defaultIndexMeta() -> Metadata {
            var m = Metadata()
            m.seriesSize = 1
            m.quality = .med
            m.creatorVerified = false
            m.creatorRep = 0.5
            return m
        }
    }

    public struct Inputs: Sendable {
        // diagnostics we export (subset)
        public let pulsesPerBeat: Int
        public let agePulses: Int
        public let adoptionAtClaim: Double
        public let adoptionNow: Double
        public let adoptionDelta: Double
        public let rarityScore01: Double
        public let fibAccrualLevels: Int
        public let lucasAccrualLevels: Int
        public let indexScarcity: Double
        public let adoptionLift: Double
        public let fibAccrualLift: Double
        public let lucasAccrualLift: Double
        public let breathWave: Double
        public let dayWave: Double
        public let strobeWave: Double
        public let momentAffinityOsc: Double
        public let combinedOsc: Double
        public let dynamicGrowth: Double
        public let rarityFloor: Double
        public let premiumBandBase: Double
    }

    public struct Seal: Sendable {
        public let version: Int
        public let unit: String                 // "Φ"
        public let algorithm: String            // "phi/kosmos-vφ-5"
        public let policyChecksum: String
        public let policyId: String?
        public let valuePhi: Double
        public let premium: Double
        public let inputs: Inputs
        public let computedAtPulse: Int
        public let cumulativeTransfers: Int
    }

    // MARK: Public API

    /// Compute the intrinsic premium/valueΦ at a specific `nowPulse`.
    public static func compute(meta rawMeta: Metadata, nowPulse: Int) -> Seal {
        let PHI = KaiValuation.PHI

        // -------- Tunables (policy excerpt; mirrors TS constants) --------
        let RARITY_ONE_OF_ONE = PHI
        let RARITY_EXP = 1 / PHI

        let QUALITY_LOW  = 1 - pow(PHI, -6)
        let QUALITY_MED  = 1.0
        let QUALITY_HIGH = 1 + pow(PHI, -6)
        let CREATOR_VERIFIED_LIFT = pow(PHI, -6)
        let CREATOR_REP_MAX       = pow(PHI, -5)

        let PROV_LOG_SLOPE = pow(PHI, -3)      // ≈0.236
        let HOLD_SLOPE     = pow(PHI, -4)      // ≈0.146
        let HOLD_CAP       = 1 + pow(PHI, -4)

        let CLOSURE_CENTER = 0.7
        let CLOSURE_RANGE  = 0.3
        let CLOSURE_GAIN   = pow(PHI, -6)
        let CADENCE_GAIN   = pow(PHI, -6)

        let CHURN_KAPPA = 0.15
        let AGE_EPS     = pow(PHI, -5)
        let AGE_CAP     = 1 + pow(PHI, -3)

        let RESONANCE_GAIN = pow(PHI, -5)

        let GEOM_EDGE_GAIN  = pow(PHI, -7)
        let GEOM_PHI_GAIN   = pow(PHI, -7)
        let GEOM_PRIME_GAIN = pow(PHI, -8)

        let MOMENT_FIB_EXACT_GAIN        = 1 / PHI
        let MOMENT_LUCAS_EXACT_GAIN      = 1 / pow(PHI, 2)
        let MOMENT_PHI_TRANSITION_GAIN   = 1 / pow(PHI, 2)
        let MOMENT_UNIFORM_GAIN          = 1 / pow(PHI, 3)
        let MOMENT_PAL_GAIN              = 1 / pow(PHI, 4)
        let MOMENT_RUN_GAIN              = 1 / pow(PHI, 4)
        let MOMENT_SEQ_GAIN              = 1 / pow(PHI, 5)
        let MOMENT_LOW_ENTROPY_GAIN      = 1 / pow(PHI, 6)

        let GENESIS_BIAS_GAIN = 1 / pow(PHI, 5)

        let ADOPTION_TAU_PULSES = pulsesPerDayExact * 365
        let ADOPTION_GAIN_BASE  = 1 / pow(PHI, 3)
        let ADOPTION_GAIN_RARE  = 1 / pow(PHI, 2)
        let INDEX_SCARCITY_GAIN = 1 / pow(PHI, 4)
        let FIB_STEP_GAIN       = 1 / pow(PHI, 6)
        let LUCAS_STEP_GAIN     = 1 / pow(PHI, 7)

        let BREATH_WAVE_GAIN = 1 / pow(PHI, 8)
        let DAY_WAVE_GAIN    = 1 / pow(PHI, 8)
        let STROBE_WAVE_GAIN = 1 / pow(PHI, 9)

        let MOMENT_AFFINITY_GAIN_BASE = 1 / pow(PHI, 4)
        let MOMENT_AFFINITY_DIGIT_WEIGHT = 1 / PHI

        // -------- Normalize meta / rhythm --------
        var meta = rawMeta
        let STEPS = coerceStepsPerBeat(meta.stepsPerBeat)
        let pulsesPerBeat = STEPS * pulsesPerStep

        let claimPulse = resolveClaimPulse(meta: meta, nowPulse: nowPulse)
        let transfers = meta.transfers
        let closed = transfers.filter { $0.receiverKaiPulse != nil }

        let beatsSinceClaim = max(1.0, Double(nowPulse - claimPulse) / Double(pulsesPerBeat))
        let velocityPerBeat = Double(transfers.count) / beatsSinceClaim
        // Explicit Set element type to satisfy the compiler
        let uniqueHolders = max(1, Set<Int>(transfers.compactMap { $0.receiverKaiPulse }).count)
        let closedFraction = transfers.isEmpty ? 1.0 : Double(closed.count) / Double(transfers.count)

        let cadReg = cadenceRegularity01(deltas: interSendDeltas(transfers))
        let medHoldBeats: Double = {
            // Explicitly type the array so compactMap inference is unambiguous
            let xs: [Double] = closed
                .compactMap { t in
                    guard let r = t.receiverKaiPulse else { return nil }
                    let v = Double(r - t.senderKaiPulse) / Double(pulsesPerBeat)
                    return v >= 0 ? v : nil
                }
            return median(xs)
        }()

        let resonancePhi = phiResonance01(meta.frequencyHz)

        // Step/Beat resolution (single source of truth)
        let claimStepResolved = resolveStepIndex(meta: meta, stepsPerBeat: STEPS, claimPulse: claimPulse)
        let claimBeatResolved = resolveBeat(meta: meta, pulsesPerBeat: pulsesPerBeat, claimPulse: claimPulse)
        meta.stepIndex = claimStepResolved
        meta.beat = claimBeatResolved

        // Optional geometry lift
        let geomLift = geometryLift(meta: meta, stepsPerBeat: STEPS, resonancePhi: resonancePhi,
                                    GEOM_EDGE_GAIN, GEOM_PHI_GAIN, GEOM_PRIME_GAIN)

        // Age & PV(IP)
        let agePulses = max(0, nowPulse - claimPulse)
        let pv_phi = presentValueIP(ip: meta.ipCashflows, nowPulse: nowPulse)

        // -------- Baseline premium --------
        let size = max(1, meta.seriesSize ?? 1)
        let rarity = size <= 1 ? RARITY_ONE_OF_ONE : pow(Double(size), -RARITY_EXP)

        let qf: Double = {
            switch meta.quality {
            case .low:  return QUALITY_LOW
            case .med:  return QUALITY_MED
            case .high: return QUALITY_HIGH
            }
        }()

        let creator = (meta.creatorVerified ? (1 + CREATOR_VERIFIED_LIFT) : 1)
                    + (meta.creatorRep * CREATOR_REP_MAX)

        let prov = 1 + PROV_LOG_SLOPE * log1p(Double(uniqueHolders - 1))

        let closureCentered = clamp((closedFraction - CLOSURE_CENTER) / CLOSURE_RANGE, -1, 1)
        let closureLift = 1 + CLOSURE_GAIN * closureCentered

        let cadenceLift = 1 + CADENCE_GAIN * (2 * cadReg - 1)

        let holdLift = min(HOLD_CAP, max(1, 1 + HOLD_SLOPE * log1p(medHoldBeats)))

        let resonanceLift = 1 + RESONANCE_GAIN * (2 * resonancePhi - 1)

        let ageBeats = Double(agePulses) / Double(pulsesPerBeat)
        let ageLift = min(AGE_CAP, 1 + AGE_EPS * log1p(ageBeats))

        let churnPenalty = 1 / (1 + CHURN_KAPPA * max(0, velocityPerBeat))

        let claimMoment = momentRarityLiftFromPulse(pulse: claimPulse,
                                                    MOMENT_FIB_EXACT_GAIN, MOMENT_LUCAS_EXACT_GAIN,
                                                    MOMENT_PHI_TRANSITION_GAIN, MOMENT_UNIFORM_GAIN,
                                                    MOMENT_PAL_GAIN, MOMENT_RUN_GAIN,
                                                    MOMENT_SEQ_GAIN, MOMENT_LOW_ENTROPY_GAIN)

        let lineageMoments: [Double] = closed.compactMap { t in
            guard let r = t.receiverKaiPulse else { return nil }
            return momentRarityLiftFromPulse(pulse: r,
                                             MOMENT_FIB_EXACT_GAIN, MOMENT_LUCAS_EXACT_GAIN,
                                             MOMENT_PHI_TRANSITION_GAIN, MOMENT_UNIFORM_GAIN,
                                             MOMENT_PAL_GAIN, MOMENT_RUN_GAIN,
                                             MOMENT_SEQ_GAIN, MOMENT_LOW_ENTROPY_GAIN)
        }
        let lineageGM = geometricMean(lineageMoments)
        let genesisBias = genesisProximityLift(claimPulse: claimPulse, GENESIS_BIAS_GAIN: GENESIS_BIAS_GAIN)

        let momentLift = claimMoment * max(1, lineageGM) * genesisBias

        let baselinePremium =
            rarity * qf * creator * prov * closureLift * cadenceLift *
            holdLift * resonanceLift * ageLift * churnPenalty * geomLift * momentLift

        // -------- Dynamic φ-compounding / floor --------
        let adoptionAtClaim = adoptionIndex01(pulse: claimPulse, tau: ADOPTION_TAU_PULSES)
        let adoptionNow = adoptionIndex01(pulse: nowPulse,   tau: ADOPTION_TAU_PULSES)
        let adoptionDelta = max(0, adoptionNow - adoptionAtClaim)

        let rarityScore01 = momentRarityScore01FromPulse(pulse: claimPulse)
        let k = ADOPTION_GAIN_BASE + ADOPTION_GAIN_RARE * rarityScore01

        let adoptionLift = round9(exp(k * adoptionDelta))
        let indexScarcity = round9(1 + INDEX_SCARCITY_GAIN * (1 - adoptionAtClaim))

        let fibLevels   = countFibLevelsSince(agePulses: agePulses)
        let lucasLevels = countLucasLevelsSince(agePulses: agePulses)
        let fibAccrualLift   = round9(exp(FIB_STEP_GAIN   * Double(fibLevels)))
        let lucasAccrualLift = round9(exp(LUCAS_STEP_GAIN * Double(lucasLevels)))

        let dynamicGrowth = round9(indexScarcity * adoptionLift * fibAccrualLift * lucasAccrualLift)

        // Strict monotone rarity floor
        let rarityFloor = round9(1 * claimMoment * indexScarcity * adoptionLift * fibAccrualLift * lucasAccrualLift * max(1, genesisBias))

        // -------- Live oscillations (φ) --------
        // breath
        let breathPhase01 = pulsesPerBeat > 0 ? frac(Double(nowPulse % pulsesPerBeat) / Double(pulsesPerBeat)) : 0
        let breathAmp = BREATH_WAVE_GAIN * (0.5 + 0.5 * cadReg)
        let breathWave = round9(1 + breathAmp * sin(2 * .pi * breathPhase01))

        // day
        let dayPhase01 = frac(Double(nowPulse) / pulsesPerDayExact)
        let claimDayPhase01 = frac(Double(claimPulse) / pulsesPerDayExact)
        let daySim = 1 - abs(((dayPhase01 - claimDayPhase01 + 1).truncatingRemainder(dividingBy: 1)) - 0.5) * 2
        let dayAmp = DAY_WAVE_GAIN * (0.5 + 0.5 * resonancePhi) * (0.5 + 0.5 * cadReg)
        let dayWave = round9(1 + dayAmp * (2 * daySim - 1))

        // strobe (Beatty)
        let (_, strobeWaveVal) = strobeWave(claimPulse: claimPulse, nowPulse: nowPulse, STROBE_WAVE_GAIN)

        // moment affinity
        let nowStep = stepIndexFromPulse(pulse: nowPulse, stepsPerBeat: STEPS)
        let claimResid = breathResidFromPulse(pulse: claimPulse)
        let nowResid = breathResidFromPulse(pulse: nowPulse)
        let stepSim = circularSim01(a: nowStep, b: claimStepResolved, period: STEPS)
        let breathSim = circularSim01(a: nowResid, b: claimResid, period: pulsesPerStep)
        let phiFracSim = 1 - abs(((logPhiFrac01(Double(nowPulse) + 1) - logPhiFrac01(Double(claimPulse) + 1) + 1).truncatingRemainder(dividingBy: 1)) - 0.5) * 2
        let claimRareScore = rarityScore01
        let nowRareScore = momentRarityScore01FromPulse(pulse: nowPulse)
        let rareSim = 1 - abs(claimRareScore - nowRareScore)

        let claimMotifs = motifFeatureSet(pulse: claimPulse)
        let nowMotifs = motifFeatureSet(pulse: nowPulse)
        let motifSim = jaccard01(a: claimMotifs, b: nowMotifs)

        let w_step = 0.30, w_breath = 0.30, w_phi = 0.20, w_digit = 0.20
        let digitBlend = MOMENT_AFFINITY_DIGIT_WEIGHT * motifSim + (1 - MOMENT_AFFINITY_DIGIT_WEIGHT) * rareSim
        let momentAffinitySim01 = round6(w_step * stepSim + w_breath * breathSim + w_phi * phiFracSim + w_digit * digitBlend)

        let momentAffinityAmp = round6(MOMENT_AFFINITY_GAIN_BASE * (0.5 + 0.5 * claimRareScore) * (0.5 + 0.5 * resonancePhi))
        let momentAffinityOsc = round6(1 + momentAffinityAmp * (2 * momentAffinitySim01 - 1))

        // combine — strictly positive
        let combinedOsc = round6(breathWave * dayWave * strobeWaveVal * momentAffinityOsc)

        // -------- Compose premium --------
        let premiumPreWave = baselinePremium * dynamicGrowth
        let premiumBandBase = max(0, premiumPreWave - rarityFloor)
        let premium = round6(rarityFloor + premiumBandBase * combinedOsc)

        // Final value in Φ (1 Φ × premium + PV(IP))
        let valuePhi = round6(1 * premium + pv_phi)

        // inputs surface
        let inputs = Inputs(
            pulsesPerBeat: pulsesPerBeat,
            agePulses: agePulses,
            adoptionAtClaim: round9(adoptionAtClaim),
            adoptionNow: round9(adoptionNow),
            adoptionDelta: round9(adoptionDelta),
            rarityScore01: round6(rarityScore01),
            fibAccrualLevels: fibLevels,
            lucasAccrualLevels: lucasLevels,
            indexScarcity: round6(indexScarcity),
            adoptionLift: round6(adoptionLift),
            fibAccrualLift: round6(fibAccrualLift),
            lucasAccrualLift: round6(lucasAccrualLift),
            breathWave: round6(breathWave),
            dayWave: round6(dayWave),
            strobeWave: round6(strobeWaveVal),
            momentAffinityOsc: round6(momentAffinityOsc),
            combinedOsc: round6(combinedOsc),
            dynamicGrowth: round6(dynamicGrowth),
            rarityFloor: round6(rarityFloor),
            premiumBandBase: round6(premiumBandBase)
        )

        return Seal(
            version: 1,
            unit: "Φ",
            algorithm: "phi/kosmos-vφ-5",
            policyChecksum: policyChecksum(),   // domain-separated stable hash
            policyId: meta.valuationPolicyId,
            valuePhi: valuePhi,
            premium: premium,
            inputs: inputs,
            computedAtPulse: nowPulse,
            cumulativeTransfers: meta.cumulativeTransfers ?? transfers.count
        )
    }

    /// Convenience for the UI: USD/Φ “Value Index” at a pulse (base * premium).
    public static func indexUSDPerPhi(meta: Metadata, nowPulse: Int, baseUSDPerPhi: Double? = nil) -> Double {
        let seal = compute(meta: meta, nowPulse: nowPulse)
        return (baseUSDPerPhi ?? indexBaseUSDPerPhi) * seal.premium
    }
}

// MARK: - Internals (helpers)

private func clamp(_ x: Double, _ a: Double, _ b: Double) -> Double { max(a, min(b, x)) }
private func frac(_ x: Double) -> Double { x - floor(x) }
private func log1p(_ x: Double) -> Double { Foundation.log(1 + max(0, x)) }
private func round6(_ x: Double) -> Double { (x * 1_000_000).rounded() / 1_000_000 }
private func round9(_ x: Double) -> Double { (x * 1_000_000_000).rounded() / 1_000_000_000 }
private func median(_ xs: [Double]) -> Double {
    guard !xs.isEmpty else { return 0 }
    let a = xs.sorted()
    let m = a.count / 2
    return a.count % 2 == 1 ? a[m] : (a[m-1] + a[m]) / 2
}
private func geometricMean(_ xs: [Double]) -> Double {
    guard !xs.isEmpty else { return 1 }
    let sumLog = xs.reduce(0.0) { $0 + Foundation.log(max($1, 1e-12)) }
    return exp(sumLog / Double(xs.count))
}

// cadence
private func interSendDeltas(_ ts: [KaiValuation.Transfer]) -> [Double] {
    guard ts.count >= 2 else { return [] }
    var out: [Double] = []
    for i in 1..<ts.count {
        let a = ts[i-1].senderKaiPulse, b = ts[i].senderKaiPulse
        if b >= a { out.append(Double(b - a)) }
    }
    return out
}
private func cadenceRegularity01(deltas: [Double]) -> Double {
    guard !deltas.isEmpty else { return 1.0 }
    let m = median(deltas)
    guard m > 0 else { return 1.0 }
    let madNorm = deltas.reduce(0.0) { $0 + abs($1 - m) / m } / Double(deltas.count)
    return 1 / (1 + madNorm)
}

// adoption & accrual
private func adoptionIndex01(pulse: Int, tau: Double) -> Double {
    guard pulse > 0 else { return 0 }
    return 1 - pow(KaiValuation.PHI, -Double(pulse) / tau)
}
private func countFibLevelsSince(agePulses: Int) -> Int {
    guard agePulses > 0 else { return 0 }
    var a: UInt64 = 1, b: UInt64 = 1
    var levels = 0
    let A = UInt64(agePulses)
    while b <= A {
        levels += 1
        (a, b) = (b, a &+ b)
        if b < a { break } // overflow guard
    }
    return levels
}
private func countLucasLevelsSince(agePulses: Int) -> Int {
    guard agePulses > 0 else { return 0 }
    var a: UInt64 = 2, b: UInt64 = 1
    var levels = 0
    let A = UInt64(agePulses)
    while b <= A {
        levels += 1
        (a, b) = (b, a &+ b)
        if b < a { break }
    }
    return levels
}

// geometry & resonance
private func phiResonance01(_ f: Double?) -> Double {
    guard let f, f > 0, f.isFinite else { return 0.5 }
    let x = log(f) / log(KaiValuation.PHI)
    let dist = abs(x - round(x))
    return 0.5 + 0.5 * clamp(1 - 2 * dist, 0, 1)
}
private func isPrime(_ n: Int?) -> Bool {
    guard let n, n >= 2 else { return false }
    if n % 2 == 0 { return n == 2 }
    var i = 3
    while i * i <= n { if n % i == 0 { return false }; i += 2 }
    return true
}
private func geometryLift(meta: KaiValuation.Metadata,
                          stepsPerBeat: Int,
                          resonancePhi: Double,
                          _ EDGE_GAIN: Double, _ PHI_GAIN: Double, _ PRIME_GAIN: Double) -> Double
{
    var lift = 1.0
    if let step = meta.stepIndex, step == 0 || step == max(stepsPerBeat - 1, 0) { lift *= 1 + EDGE_GAIN }
    if isPrime(meta.beat) { lift *= 1 + PRIME_GAIN }
    if resonancePhi > 0.9 {
        let t = clamp((resonancePhi - 0.9) / 0.1, 0, 1)
        lift *= 1 + PHI_GAIN * t
    }
    return lift
}

// IP PV
private func presentValueIP(ip: [KaiValuation.IPFlow], nowPulse: Int) -> Double {
    ip.reduce(0.0) { s, c in
        let dp = c.atPulse - nowPulse
        let disc = 1 / (1 + max(0.0, Double(dp)) / KaiValuation.pulsesPerDayExact)
        return s + c.amountPhi * disc
    }
}

// numeric-moment rarity helpers
private func isPerfectSquare(_ n: UInt64) -> Bool {
    let r = UInt64(Double(n).squareRoot())
    return r &* r == n || (r &+ 1) &* (r &+ 1) == n
}
private func isFibonacciExact(_ pulse: Int) -> Bool {
    guard pulse >= 0 else { return false }
    let n = UInt64(pulse)
    // 5n^2 ± 4
    let n2 = n &* n
    let a = 5 &* n2 &+ 4
    let b = 5 &* n2 &- 4
    return isPerfectSquare(a) || isPerfectSquare(b)
}
private func isLucasExact(_ pulse: Int) -> Bool {
    guard pulse >= 0 else { return false }
    let N = UInt64(pulse)
    var a: UInt64 = 2, b: UInt64 = 1
    while b < N {
        let t = a &+ b
        a = b; b = t
        if b < a { break }
    }
    return b == N
}
private func absDigits(_ pulse: Int) -> String { String(abs(pulse)) }
private func allSameDigit(_ s: String) -> Bool {
    guard s.count > 1, let f = s.first else { return false }
    return s.allSatisfy { $0 == f }
}
private func isPalindromeDigits(_ s: String) -> Bool {
    guard s.count > 1 else { return false }
    return s == String(s.reversed())
}
private func longestRunSameDigit(_ s: String) -> Int {
    guard !s.isEmpty else { return 0 }
    var maxLen = 1, cur = 1, prev = s.first!
    for ch in s.dropFirst() {
        if ch == prev { cur += 1; maxLen = max(maxLen, cur) } else { cur = 1; prev = ch }
    }
    return maxLen
}
private func longestRunDigitInfo(_ s: String) -> (len: Int, digit: Character) {
    guard let first = s.first else { return (0, "0") }
    var maxLen = 1, curLen = 1, digit = first, prev = first
    for ch in s.dropFirst() {
        if ch == prev { curLen += 1; if curLen > maxLen { maxLen = curLen; digit = ch } }
        else { curLen = 1; prev = ch }
    }
    return (maxLen, digit)
}
private func longestConsecutiveSequenceLen(_ s: String) -> Int {
    guard s.count > 1 else { return 1 }
    let nums = s.compactMap { $0.wholeNumberValue }
    var maxLen = 1, cur = 1, dir = 0
    for i in 1..<nums.count {
        let step = nums[i] - nums[i-1]
        if step == dir, (step == 1 || step == -1) { cur += 1 }
        else if step == 1 || step == -1 { dir = step; cur = 2 }
        else { dir = 0; cur = 1 }
        maxLen = max(maxLen, cur)
    }
    return maxLen
}
private func digitEntropy01(_ s: String) -> Double {
    guard !s.isEmpty else { return 1 }
    var cnt = Array(repeating: 0, count: 10)
    for ch in s { if let v = ch.wholeNumberValue { cnt[v] += 1 } }
    var H = 0.0
    for c in cnt where c > 0 {
        let p = Double(c) / Double(s.count)
        H -= p * log(p)
    }
    let Hmax = log(Double(min(10, s.count)))
    return clamp(H / (Hmax == 0 ? 1 : Hmax), 0, 1)
}

// φ-spiral transitions s_n = ceil(φ^n)
private func phiTransitionIndexFromPulse(_ pulse: Int) -> Int? {
    guard pulse >= 1 else { return nil }
    let PHI = KaiValuation.PHI
    let N = pulse
    let nApprox = Int(floor(log(Double(N)) / log(PHI)))
    for n in max(1, nApprox - 2)...(nApprox + 6) {
        let s = Int(ceil(pow(PHI, Double(n))))
        if s == N { return n }
    }
    return nil
}

private func momentRarityLiftFromPulse(pulse: Int,
                                       _ FIB: Double, _ LUC: Double, _ PHI_T: Double,
                                       _ UNI: Double, _ PAL: Double, _ RUN: Double,
                                       _ SEQ: Double, _ ENT: Double) -> Double
{
    let s = absDigits(pulse); let len = s.count
    var lift = 1.0
    if isFibonacciExact(pulse) { lift *= 1 + FIB }
    if isLucasExact(pulse)     { lift *= 1 + LUC }
    if phiTransitionIndexFromPulse(pulse) != nil { lift *= 1 + PHI_T }
    if allSameDigit(s)         { lift *= 1 + UNI }
    if isPalindromeDigits(s)   { lift *= 1 + PAL }
    let run = longestRunSameDigit(s)
    if run >= 3 {
        let norm = clamp(Double(run - 2) / Double(max(3, len - 2)), 0, 1)
        lift *= 1 + RUN * norm
    }
    let seq = longestConsecutiveSequenceLen(s)
    if seq >= 4 {
        let norm = clamp(Double(seq - 3) / Double(max(4, len - 3)), 0, 1)
        lift *= 1 + SEQ * norm
    }
    let ent = digitEntropy01(s)
    lift *= 1 + ENT * (1 - ent)
    return lift
}

private func momentRarityScore01FromPulse(pulse: Int) -> Double {
    let PHI = KaiValuation.PHI
    let s = absDigits(pulse); let len = s.count
    var score = 0.0, wsum = 0.0

    let fib = isFibonacciExact(pulse) ? 1.0 : 0.0
    score += 1.0 * fib;  wsum += 1.0

    let luc = isLucasExact(pulse) ? 1.0 : 0.0
    score += (1/PHI) * luc; wsum += 1/PHI

    let uniform = allSameDigit(s) ? 1.0 : 0.0
    score += (1/PHI) * uniform; wsum += 1/PHI

    let pal = isPalindromeDigits(s) ? 1.0 : 0.0
    score += pow(PHI, -2) * pal; wsum += pow(PHI, -2)

    let run = longestRunSameDigit(s)
    let runNorm = clamp(Double(run - 2) / Double(max(3, len - 2)), 0, 1)
    score += pow(PHI, -2) * runNorm; wsum += pow(PHI, -2)

    let seq = longestConsecutiveSequenceLen(s)
    let seqNorm = clamp(Double(seq - 3) / Double(max(4, len - 3)), 0, 1)
    score += pow(PHI, -3) * seqNorm; wsum += pow(PHI, -3)

    let ent = digitEntropy01(s)
    score += pow(PHI, -3) * (1 - ent); wsum += pow(PHI, -3)

    guard wsum > 0 else { return 0 }
    return clamp(score / wsum, 0, 1)
}

// moment affinity helpers
private func stepIndexFromPulse(pulse: Int, stepsPerBeat: Int) -> Int {
    let n = max(0, pulse)
    return (n / KaiValuation.pulsesPerStep) % max(1, stepsPerBeat)
}
private func breathResidFromPulse(pulse: Int) -> Int {
    return max(0, pulse) % KaiValuation.pulsesPerStep // 0..10
}
private func circularSim01(a: Int, b: Int, period: Int) -> Double {
    let da = ((a - b) % period + period) % period
    let theta = (2 * Double.pi * Double(da)) / Double(period)
    return 0.5 * (1 + cos(theta))
}
private func logPhiFrac01(_ n: Double) -> Double {
    guard n > 0, n.isFinite else { return 0 }
    let x = log(n) / log(KaiValuation.PHI)
    return frac(x)
}
private func motifFeatureSet(pulse: Int) -> Set<String> {
    var s: Set<String> = []
    if isFibonacciExact(pulse) { s.insert("fib") }
    if isLucasExact(pulse)     { s.insert("lucas") }
    let ds = absDigits(pulse)
    if allSameDigit(ds)        { s.insert("uniform") }
    if isPalindromeDigits(ds)  { s.insert("pal") }
    if longestRunSameDigit(ds) >= 4 { s.insert("longrun") }
    if longestConsecutiveSequenceLen(ds) >= 5 { s.insert("longseq") }
    return s
}
private func jaccard01(a: Set<String>, b: Set<String>) -> Double {
    if a.isEmpty && b.isEmpty { return 0.0 }
    let uCount = a.union(b).count
    let interCount = a.intersection(b).count
    return Double(interCount) / Double(uCount)
}

// normalization helpers
private func coerceStepsPerBeat(_ steps: Int?) -> Int {
    guard let s = steps, s > 0 else { return KaiValuation.defaultStepsPerBeat }
    return s
}
private func resolveClaimPulse(meta: KaiValuation.Metadata, nowPulse: Int) -> Int {
    if let k = meta.kaiPulse { return k }
    if let p = meta.pulse { return p }
    return nowPulse
}
private func resolveStepIndex(meta: KaiValuation.Metadata, stepsPerBeat: Int, claimPulse: Int) -> Int {
    if let s = meta.stepIndex { return Swift.max(0, Swift.min(stepsPerBeat - 1, s)) }
    return stepIndexFromPulse(pulse: claimPulse, stepsPerBeat: stepsPerBeat)
}
private func resolveBeat(meta: KaiValuation.Metadata, pulsesPerBeat: Int, claimPulse: Int) -> Int {
    if let b = meta.beat { return b }
    return claimPulse / pulsesPerBeat
}

// Genesis proximity (gentle early lift/discount)
private func genesisProximityLift(claimPulse: Int, GENESIS_BIAS_GAIN: Double) -> Double {
    guard claimPulse >= 0 else { return 1.0 }
    let yearPulsesApprox = KaiValuation.pulsesPerDayExact * 365
    let t = Double(claimPulse) / (Double(claimPulse) + yearPulsesApprox)
    return 1 + GENESIS_BIAS_GAIN * (1 - 2 * t)
}

// Beatty strobe
private func strobeWave(claimPulse: Int, nowPulse: Int, _ gain: Double) -> (phase01: Double, wave: Double) {
    let PHI = KaiValuation.PHI
    let u = frac((Double(claimPulse) + Double(nowPulse)) * PHI)
    let wave = round9(1 + gain * (2 * u - 1))
    return (round9(u), wave)
}

// Policy checksum (stable FNV-ish hash of embedded constants)
private func policyChecksum() -> String {
    // Keep minimal + deterministic: the integers/doubles we embed above
    let s = "val-policy:" + [
        KaiValuation.defaultStepsPerBeat,
        KaiValuation.pulsesPerStep,
        KaiValuation.pulsesPerBeatCanon
    ].map { "\($0)" }.joined(separator: "|") + "|pulsesPerDay=\(KaiValuation.pulsesPerDayExact)"
    var h: UInt32 = 2166136261
    for c in s.utf8 {
        h ^= UInt32(c)
        h = h &+ ((h << 1) &+ (h << 4) &+ (h << 7) &+ (h << 8) &+ (h << 24))
    }
    return String(format: "%08x", h)
}

// =============================================================================
// Public Issuance API (moved into a non-public extension so explicit `public`
// on members is not “redundant in a public extension”).
// =============================================================================

extension KaiValuation {

    // MARK: Issuance policy (Swift port of phi-issuance.ts)

    public struct IssuancePolicy {
        public struct WhaleTaper { public var k: Double; public init(k: Double) { self.k = k } }
        public struct LifetimeTier {
            public var thresholdUsd: Double
            public var boost: Double
            public init(thresholdUsd: Double, boost: Double) { self.thresholdUsd = thresholdUsd; self.boost = boost }
        }
        public struct HoldBonus {
            public var eta: Double; public var rho: Double; public var capMultiple: Double
            public init(eta: Double, rho: Double, capMultiple: Double) { self.eta = eta; self.rho = rho; self.capMultiple = capMultiple }
        }
        public struct Choir {
            public var windowPulses: Int; public var maxBoost: Double; public var wStep: Double; public var wBreath: Double
            public init(windowPulses: Int, maxBoost: Double, wStep: Double, wBreath: Double) {
                self.windowPulses = windowPulses; self.maxBoost = maxBoost; self.wStep = wStep; self.wBreath = wBreath
            }
        }
        public struct Breath { public var maxBoost: Double; public init(maxBoost: Double) { self.maxBoost = maxBoost } }
        public enum FestivalMode { case beatEvery, phiTransition }
        public struct Festival {
            public var mode: FestivalMode; public var interval: Int; public var widthBeats: Int; public var bonus: Double
            public init(mode: FestivalMode, interval: Int, widthBeats: Int, bonus: Double) {
                self.mode = mode; self.interval = interval; self.widthBeats = widthBeats; self.bonus = bonus
            }
        }
        public enum Combine: String { case min, product, max }
        public enum Interp: String { case step, linear }
        public struct Milestones {
            public var adoption: [(atAdoption: Double, multiplier: Double)]?
            public var pulse:    [(atPulse: Int,    multiplier: Double)]?
            public var beat:     [(atBeat: Int,     multiplier: Double)]?
            public var phiTransition: [(atN: Int,   multiplier: Double)]?
            public var combine: Combine
            public var interpolation: Interp
            public init(
                adoption: [(atAdoption: Double, multiplier: Double)]?,
                pulse: [(atPulse: Int, multiplier: Double)]?,
                beat: [(atBeat: Int, multiplier: Double)]?,
                phiTransition: [(atN: Int, multiplier: Double)]?,
                combine: Combine,
                interpolation: Interp
            ) {
                self.adoption = adoption; self.pulse = pulse; self.beat = beat; self.phiTransition = phiTransition
                self.combine = combine; self.interpolation = interpolation
            }
        }
        public struct Vow {
            public var earlyUnlockPenalty: Double; public var stewardEpochBeats: Int; public var stewardSpreadBeats: Int
            public init(earlyUnlockPenalty: Double, stewardEpochBeats: Int, stewardSpreadBeats: Int) {
                self.earlyUnlockPenalty = earlyUnlockPenalty; self.stewardEpochBeats = stewardEpochBeats; self.stewardSpreadBeats = stewardSpreadBeats
            }
        }

        // Scalars
        public var basePhiPerUsd: Double
        public var adoptionLambda: Double
        public var premiumGamma: Double
        public var momentBoostMax: Double

        // Size
        public var sizeScaleUsd: Double
        public var sizeMu: Double
        public var sizeCap: Double
        public var whaleTaper: WhaleTaper?

        // Streak / tiers
        public var streakMaxBoost: Double
        public var lifetimeTiers: [LifetimeTier]?

        // Optional features
        public var holdBonus: HoldBonus?
        public var choir: Choir?
        public var breath: Breath?
        public var festival: Festival?
        public var milestones: Milestones?
        public var vow: Vow?

        // Memberwise init (public) so callers can customize if needed
        public init(
            basePhiPerUsd: Double,
            adoptionLambda: Double,
            premiumGamma: Double,
            momentBoostMax: Double,
            sizeScaleUsd: Double,
            sizeMu: Double,
            sizeCap: Double,
            whaleTaper: WhaleTaper?,
            streakMaxBoost: Double,
            lifetimeTiers: [LifetimeTier]?,
            holdBonus: HoldBonus?,
            choir: Choir?,
            breath: Breath?,
            festival: Festival?,
            milestones: Milestones?,
            vow: Vow?
        ) {
            self.basePhiPerUsd = basePhiPerUsd
            self.adoptionLambda = adoptionLambda
            self.premiumGamma = premiumGamma
            self.momentBoostMax = momentBoostMax
            self.sizeScaleUsd = sizeScaleUsd
            self.sizeMu = sizeMu
            self.sizeCap = sizeCap
            self.whaleTaper = whaleTaper
            self.streakMaxBoost = streakMaxBoost
            self.lifetimeTiers = lifetimeTiers
            self.holdBonus = holdBonus
            self.choir = choir
            self.breath = breath
            self.festival = festival
            self.milestones = milestones
            self.vow = vow
        }

        public static let `default` = IssuancePolicy(
            basePhiPerUsd: 0.10,
            adoptionLambda: 1 / PHI,
            premiumGamma: 1 / pow(PHI, 2),
            momentBoostMax: 1 / pow(PHI, 2),
            sizeScaleUsd: 100,
            sizeMu: 1 / pow(PHI, 3),
            sizeCap: 1 + 1 / pow(PHI, 2),
            whaleTaper: WhaleTaper(k: 1 / pow(PHI, 4)),
            streakMaxBoost: 1 / pow(PHI, 3),
            lifetimeTiers: [
                LifetimeTier(thresholdUsd: 200,  boost: 0.05),
                LifetimeTier(thresholdUsd: 1000, boost: 0.10),
                LifetimeTier(thresholdUsd: 3000, boost: 0.16),
            ],
            holdBonus: HoldBonus(eta: 1 / pow(PHI, 2), rho: 1 / pow(PHI, 3), capMultiple: 1 / PHI),
            choir: Choir(windowPulses: 242, maxBoost: 1 / pow(PHI, 3), wStep: 0.6, wBreath: 0.4),
            breath: Breath(maxBoost: 1 / pow(PHI, 4)),
            festival: Festival(mode: .beatEvery, interval: 13, widthBeats: 1, bonus: 1 / pow(PHI, 4)),
            milestones: Milestones(
                adoption: [
                    (0.10, 0.95),
                    (0.25, 0.90),
                    (0.50, 1 / PHI),
                    (0.75, pow(PHI, -1.25))
                ],
                pulse: nil,
                beat: nil,
                phiTransition: [
                    (18, 0.92),
                    (21, 0.88),
                    (25, 0.82)
                ],
                combine: .min,
                interpolation: .step
            ),
            vow: Vow(earlyUnlockPenalty: 0.5, stewardEpochBeats: 55, stewardSpreadBeats: 21)
        )
    }

    public struct IssuanceContext {
        public var nowPulse: Int
        public var usd: Double
        public var currentStreakDays: Int? = nil
        public var lifetimeUsdSoFar: Double? = nil
        public var plannedHoldBeats: Int? = nil
        public var choirNearby: [Int]? = nil          // pulses of neighbors within window
        public var breathPhase01: Double? = nil       // 0..1 (optional)
        public init(
            nowPulse: Int,
            usd: Double,
            currentStreakDays: Int? = nil,
            lifetimeUsdSoFar: Double? = nil,
            plannedHoldBeats: Int? = nil,
            choirNearby: [Int]? = nil,
            breathPhase01: Double? = nil
        ) {
            self.nowPulse = nowPulse
            self.usd = usd
            self.currentStreakDays = currentStreakDays
            self.lifetimeUsdSoFar = lifetimeUsdSoFar
            self.plannedHoldBeats = plannedHoldBeats
            self.choirNearby = choirNearby
            self.breathPhase01 = breathPhase01
        }
    }

    public struct IssuanceMultipliers {
        public let adoption: Double, premium: Double, moment: Double, size: Double,
            streak: Double, tier: Double, choir: Double, breath: Double, festival: Double, milestone: Double, taper: Double
        public init(
            adoption: Double, premium: Double, moment: Double, size: Double,
            streak: Double, tier: Double, choir: Double, breath: Double, festival: Double, milestone: Double, taper: Double
        ) {
            self.adoption = adoption; self.premium = premium; self.moment = moment; self.size = size
            self.streak = streak; self.tier = tier; self.choir = choir; self.breath = breath
            self.festival = festival; self.milestone = milestone; self.taper = taper
        }
    }

    public struct IssuanceQuote {
        public let phiPerUsd: Double
        public let usdPerPhi: Double
        public let addPhiNow: Double
        public let issuanceMultiplier: Double
        public let multipliers: IssuanceMultipliers
        public let hold: (vestAtPulse: Int, bonusPhiAtVest: Double, bonusNowPV: Double)?
        public let nextMilestone: (kind: String, at: Double, multiplier: Double)?
        public let premium: Double
        public let adoption: Double
        public let rarityScore: Double
        public let pulsesPerBeat: Int
        public let valuePhiBefore: Double
        public let valuePhiAfterPV: Double
        public init(
            phiPerUsd: Double,
            usdPerPhi: Double,
            addPhiNow: Double,
            issuanceMultiplier: Double,
            multipliers: IssuanceMultipliers,
            hold: (vestAtPulse: Int, bonusPhiAtVest: Double, bonusNowPV: Double)?,
            nextMilestone: (kind: String, at: Double, multiplier: Double)?,
            premium: Double,
            adoption: Double,
            rarityScore: Double,
            pulsesPerBeat: Int,
            valuePhiBefore: Double,
            valuePhiAfterPV: Double
        ) {
            self.phiPerUsd = phiPerUsd; self.usdPerPhi = usdPerPhi; self.addPhiNow = addPhiNow
            self.issuanceMultiplier = issuanceMultiplier; self.multipliers = multipliers
            self.hold = hold; self.nextMilestone = nextMilestone
            self.premium = premium; self.adoption = adoption; self.rarityScore = rarityScore
            self.pulsesPerBeat = pulsesPerBeat; self.valuePhiBefore = valuePhiBefore; self.valuePhiAfterPV = valuePhiAfterPV
        }
    }

    // MARK: Public: parity price (USD per Φ) — mirror of TS quotePhiForUsd

    public static func usdPerPhi(meta: Metadata, nowPulse: Int, usd: Double, policy: IssuancePolicy? = nil) -> Double {
        let q = quotePhiForUsd(meta: meta, ctx: IssuanceContext(nowPulse: nowPulse, usd: usd), policy: policy)
        return q.usdPerPhi
    }

    public static func quotePhiForUsd(meta: Metadata, ctx: IssuanceContext, policy: IssuancePolicy? = nil) -> IssuanceQuote {
        // coalesce optional policy to default to avoid default-arg access issues
        let policy = policy ?? IssuancePolicy.default

        // 1) Intrinsic (premium, adoption, rarity, pulsesPerBeat)
        let seal = compute(meta: meta, nowPulse: ctx.nowPulse)
        let adoption = seal.inputs.adoptionNow
        let rarityScore = seal.inputs.rarityScore01
        let pulsesPerBeat = seal.inputs.pulsesPerBeat
        let stepsPerBeat = max(1, pulsesPerBeat / pulsesPerStep)
        let premium = max(1e-12, seal.premium)
        let usd = max(0, ctx.usd)

        // 2) Multipliers (exact TS math)
        let M_adoption = round9(exp(-policy.adoptionLambda * adoption))
        let M_premium  = round9(pow(1 / max(premium, 1e-9), policy.premiumGamma))
        let M_moment   = round9(1 + policy.momentBoostMax * rarityScore)

        let rawSize = 1 + policy.sizeMu * log1p(usd / max(policy.sizeScaleUsd, 1))
        let M_size  = min(rawSize, policy.sizeCap)
        let M_taper = policy.whaleTaper != nil ? 1 / sqrt(1 + (policy.whaleTaper!.k * usd)) : 1
        let sizeMultiplier = round9(M_size * M_taper)

        let N = max(0, ctx.currentStreakDays ?? 0)
        let M_streak = round9(1 + policy.streakMaxBoost * (1 - pow(PHI, -Double(N))))

        let L = max(0, (ctx.lifetimeUsdSoFar ?? 0) + usd)
        let tierBoost = (policy.lifetimeTiers ?? []).reduce(0.0) { acc, t in L >= t.thresholdUsd ? max(acc, t.boost) : acc }
        let M_tier = round9(1 + tierBoost)

        let M_choir = round9(choirMultiplier(nowPulse: ctx.nowPulse, stepsPerBeat: stepsPerBeat, neighbors: ctx.choirNearby ?? [], cfg: policy.choir))
        let M_breath = round9(breathAlignmentMultiplier(nowPulse: ctx.nowPulse, breathPhase01: ctx.breathPhase01, cfg: policy.breath))
        let M_festival = round9(festivalMultiplier(nowPulse: ctx.nowPulse, pulsesPerBeat: pulsesPerBeat, cfg: policy.festival))
        let (M_milestone, nextMilestone) = milestoneMultiplier(policy: policy, nowPulse: ctx.nowPulse, adoption: adoption, pulsesPerBeat: pulsesPerBeat)

        let issuanceMultiplier = round9(M_adoption * M_premium * M_moment * sizeMultiplier * M_streak * M_tier * M_choir * M_breath * M_festival * M_milestone)

        // 3) Φ/$, add Φ now
        let phiPerUsd = round9(policy.basePhiPerUsd * issuanceMultiplier)
        let usdPerPhi = phiPerUsd > 0 ? round9(1 / phiPerUsd) : .infinity
        let addPhiNow = round9(usd * phiPerUsd)

        // 4) Optional hold bonus (PV like TS)
        var holdInfo: (Int, Double, Double)? = nil
        if let hb = policy.holdBonus, let beats = ctx.plannedHoldBeats, beats > 0 {
            let vestPulse = ctx.nowPulse + beats * pulsesPerBeat
            let rawBonus = addPhiNow * hb.eta * (1 - exp(-hb.rho * Double(beats)))
            let bonusPhiAtVest = min(rawBonus, addPhiNow * hb.capMultiple)
            let disc = 1 / (1 + max(0.0, Double(vestPulse - ctx.nowPulse)) / KaiValuation.pulsesPerDayExact)
            let bonusNowPV = round9(bonusPhiAtVest * disc)
            holdInfo = (vestPulse, round9(bonusPhiAtVest), bonusNowPV)
        }

        // 5) Value snapshots (purely informational)
        let pv_phi = presentValueIP(ip: meta.ipCashflows, nowPulse: ctx.nowPulse)
        let valuePhiBefore = round9(1 * premium + pv_phi)
        let valuePhiAfterPV = round9(valuePhiBefore + addPhiNow + (holdInfo?.2 ?? 0))

        return IssuanceQuote(
            phiPerUsd: phiPerUsd,
            usdPerPhi: usdPerPhi,
            addPhiNow: addPhiNow,
            issuanceMultiplier: issuanceMultiplier,
            multipliers: IssuanceMultipliers(
                adoption: M_adoption, premium: M_premium, moment: M_moment, size: sizeMultiplier,
                streak: M_streak, tier: M_tier, choir: M_choir, breath: M_breath, festival: M_festival, milestone: M_milestone, taper: M_taper
            ),
            hold: holdInfo.map { (vest, bonus, pv) in (vestAtPulse: vest, bonusPhiAtVest: bonus, bonusNowPV: pv) },
            nextMilestone: nextMilestone,
            premium: premium,
            adoption: adoption,
            rarityScore: rarityScore,
            pulsesPerBeat: pulsesPerBeat,
            valuePhiBefore: valuePhiBefore,
            valuePhiAfterPV: valuePhiAfterPV
        )
    }

    // MARK: — helpers (ports of TS helpers) —

    private static func choirMultiplier(nowPulse: Int, stepsPerBeat: Int, neighbors: [Int], cfg: IssuancePolicy.Choir?) -> Double {
        guard let cfg, !neighbors.isEmpty else { return 1 }
        let window = max(1, cfg.windowPulses)
        let left = nowPulse - window, right = nowPulse + window
        let choir = neighbors.filter { $0 >= left && $0 <= right }
        if choir.isEmpty { return 1 }
        let meStep = stepIndexFromPulse(pulse: nowPulse, stepsPerBeat: stepsPerBeat)
        let meResid = breathResidFromPulse(pulse: nowPulse)
        var sum = 0.0
        for p in choir {
            let s = stepIndexFromPulse(pulse: p, stepsPerBeat: stepsPerBeat)
            let r = breathResidFromPulse(pulse: p)
            let stepSim = circularSim01(a: meStep, b: s, period: stepsPerBeat)
            let breathSim = circularSim01(a: meResid, b: r, period: pulsesPerStep)
            let pair = (cfg.wStep * stepSim) + (cfg.wBreath * breathSim)
            sum += pair
        }
        let avg = sum / Double(choir.count) // 0..1
        return 1 + cfg.maxBoost * (2 * avg - 1)
    }

    private static func breathAlignmentMultiplier(nowPulse: Int, breathPhase01: Double?, cfg: IssuancePolicy.Breath?) -> Double {
        guard let cfg, let phase = breathPhase01 else { return 1 }
        let resid = Double(breathResidFromPulse(pulse: nowPulse)) / Double(pulsesPerStep) // 0..1
        let sim = 1 - abs(((phase - resid + 1).truncatingRemainder(dividingBy: 1)) - 0.5) * 2
        return 1 + cfg.maxBoost * (2 * sim - 1)
    }

    private static func festivalMultiplier(nowPulse: Int, pulsesPerBeat: Int, cfg: IssuancePolicy.Festival?) -> Double {
        guard let cfg else { return 1 }
        let beat = nowPulse / max(1, pulsesPerBeat)
        switch cfg.mode {
        case .beatEvery:
            let k = max(1, cfg.interval)
            let half = max(0, cfg.widthBeats)
            let near = (beat % k == 0) || abs(beat % k) <= half || abs((beat % k) - k) <= half
            return near ? 1 + cfg.bonus : 1
        case .phiTransition:
            let nApprox = Int(floor(log(Double(max(1, nowPulse))) / log(PHI)))
            let sN = Int(ceil(pow(PHI, Double(nApprox))))
            let k = max(1, cfg.interval)
            let isEvent = (nApprox % k) == 0
            let half = max(0, cfg.widthBeats)
            let eventBeat = sN / max(1, pulsesPerBeat)
            let near = abs(beat - eventBeat) <= half
            return (isEvent && near) ? 1 + cfg.bonus : 1
        }
    }

    private static func milestoneMultiplier(policy: IssuancePolicy, nowPulse: Int, adoption: Double, pulsesPerBeat: Int)
      -> (Double, (kind: String, at: Double, multiplier: Double)?) {

        guard let ms = policy.milestones else { return (1, nil) }
        func step(_ x: Double, _ arr: [(Double, Double)]) -> Double {
            var m = 1.0; for e in arr { if x >= e.0 { m = e.1 } }; return m
        }
        func linear(_ x: Double, _ arr: [(Double, Double)]) -> Double {
            guard let first = arr.first else { return 1 }
            if x <= first.0 { return first.1 }
            for i in 1..<arr.count {
                let a = arr[i-1], b = arr[i]
                if x <= b.0 {
                    let t = (x - a.0) / max(1e-12, b.0 - a.0)
                    return a.1 + t * (b.1 - a.1)
                }
            }
            return arr.last!.1
        }
        func interp(_ x: Double, arr: [(Double, Double)]) -> Double {
            ms.interpolation == .linear ? linear(x, arr) : step(x, arr)
        }
        var parts: [Double] = []
        var next: (String, Double, Double)? = nil

        if let a = ms.adoption, !a.isEmpty {
            let arr = a.sorted { $0.atAdoption < $1.atAdoption }.map { (max(0,min(1,$0.atAdoption)), $0.multiplier) }
            parts.append(interp(adoption, arr: arr))
            if let nxt = arr.first(where: { adoption < $0.0 }), next == nil { next = ("adoption", nxt.0, nxt.1) }
        }
        if let p = ms.pulse, !p.isEmpty {
            let arr = p.sorted { $0.atPulse < $1.atPulse }.map { (Double(max(0,$0.atPulse)), $0.multiplier) }
            parts.append(interp(Double(nowPulse), arr: arr))
            if let nxt = arr.first(where: { Double(nowPulse) < $0.0 }), next == nil { next = ("pulse", nxt.0, nxt.1) }
        }
        if let b = ms.beat, !b.isEmpty {
            let beat = nowPulse / max(1, pulsesPerBeat)
            let arr = b.sorted { $0.atBeat < $1.atBeat }.map { (Double(max(0,$0.atBeat)), $0.multiplier) }
            parts.append(interp(Double(beat), arr: arr))
            if let nxt = arr.first(where: { Double(beat) < $0.0 }), next == nil { next = ("beat", nxt.0, nxt.1) }
        }
        if let ph = ms.phiTransition, !ph.isEmpty {
            let nApprox = Int(floor(log(Double(max(1, nowPulse))) / log(PHI)))
            let arr = ph.sorted { $0.atN < $1.atN }.map { (Double(max(1,$0.atN)), $0.multiplier) }
            parts.append(interp(Double(nApprox), arr: arr))
            if let nxt = arr.first(where: { Double(nApprox) < $0.0 }), next == nil { next = ("phiTransition", nxt.0, nxt.1) }
        }

        let M: Double
        switch ms.combine {
        case .min:     M = parts.min() ?? 1
        case .max:     M = parts.max() ?? 1
        case .product: M = parts.reduce(1, *)
        }
        return (round9(M), next.map { (kind: $0.0, at: $0.1, multiplier: $0.2) })
    }
}
