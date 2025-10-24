//  KaiSigilSwiftUI.swift
//  KaiKlok
//
//  Eternal-Klok parity update (NO CHRONOS):
//  • Memory block now shows *eternal* data (exactly the same fields/values as the live panel)
//  • All values computed from the same KKS-1.0 μpulse canon used for rendering
//  • SVG export embeds a full EternalKlock JSON snapshot (CDATA); NO ISO timestamps anywhere
//  • Sigil visuals aligned to TSX app (polygon, Lissajous, halo, vertex dots, neon stack, center node)
//  • Seal Moment panel parity (hash + URL + share)
//  • FIXED: Pulse countdown now uses a single monotonic timebase with wall-clock calibration.
//           When the countdown reaches 0, the pulse flips exactly at that instant (no drift).
//  • NEW: Real Verifier wired to the checkmark button (full-screen `VerifierModal`)

import SwiftUI
import Combine
import QuartzCore
import UIKit
import Foundation
import CryptoKit

// MARK: - Config / Share URL base ---------------------------------------------

/// Set to your production web app origin (e.g., https://kaiklok.app)
private let SIGIL_BASE_URL = URL(string: "https://kaiklok.com")!

// MARK: - Canon / Constants ----------------------------------------------------

/// Genesis timestamp (UTC): 2024-05-10 06:45:41.888
private let GENESIS_TS: Date = {
    var comps = DateComponents()
    comps.calendar = Calendar(identifier: .gregorian)
    comps.timeZone = TimeZone(secondsFromGMT: 0)
    comps.year = 2024; comps.month = 5; comps.day = 10
    comps.hour = 6; comps.minute = 45; comps.second = 41; comps.nanosecond = 888_000_000
    return comps.date ?? Date(timeIntervalSince1970: 0)
}()

/// φ-exact breath ≈ 5.236067977 s (KKS v1.0)
private let KAI_PULSE_SEC: Double = 3.0 + sqrt(5.0)
private let PULSE_MS: Double = KAI_PULSE_SEC * 1000.0

/// Day canon
private let DAY_PULSES: Double = 17_491.270_421
private let STEPS_BEAT = 44
private let BEATS_DAY = 36

private let DAYS_PER_WEEK = 6
private let DAYS_PER_MONTH = 42
private let MONTHS_PER_YEAR = 8
private let DAYS_PER_YEAR = DAYS_PER_MONTH * MONTHS_PER_YEAR // 336

/// Micro-pulse fixed-point constants (KKS-1.0)
private let ONE_PULSE_MICRO: Int64 = 1_000_000
private let N_DAY_MICRO: Int64 = 17_491_270_421
private let PULSES_PER_STEP_MICRO: Int64 = 11_000_000

/// EXACT μpulses-per-beat (ties-to-even)
private let MU_PER_BEAT_EXACT: Int64 = {
    let num = Int128(N_DAY_MICRO) + 18 // (N_DAY_MICRO + 18)/36 — ties-to-even
    return Int64(num / 36)
}()
private let BEAT_PULSES_ROUNDED: Int = Int((MU_PER_BEAT_EXACT + (ONE_PULSE_MICRO / 2)) / ONE_PULSE_MICRO)

// MARK: - Types ----------------------------------------------------------------

private enum HarmonicDay: String, CaseIterable, Codable, Hashable {
    case Solhara, Aquaris, Flamora, Verdari, Sonari, Kaelith
}

private enum KaiChakra: String, CaseIterable, Codable, Hashable {
    case Root, Sacral, SolarPlexus = "Solar Plexus", Heart, Throat, ThirdEye = "Third Eye", Crown
}

private let ETERNAL_MONTH_NAMES: [String] = [
    "Aethon","Virelai","Solari","Amarin","Kaelus","Umbriel","Noctura","Liora"
]

private let ARC_NAMES: [String] = ["Ignite","Integrate","Harmonize","Reflekt","Purifikation","Dream"]
private func arcLabel(_ name: String) -> String { "\(name) Ark" }

private let DAY_TO_CHAKRA: [HarmonicDay: KaiChakra] = [
    .Solhara: .Root, .Aquaris: .Sacral, .Flamora: .SolarPlexus,
    .Verdari: .Heart, .Sonari: .Throat, .Kaelith: .Crown,
]

// Chakra visuals (polygon + hue)
private struct ChakraSpec { let sides: Int; let hue: Double }
private let CHAKRAS: [KaiChakra: ChakraSpec] = [
    .Root: .init(sides: 4,  hue:   0),   .Sacral: .init(sides: 6,  hue:  30),
    .SolarPlexus: .init(sides: 5, hue: 53), .Heart: .init(sides: 8, hue: 122),
    .Throat: .init(sides: 12, hue: 180), .ThirdEye: .init(sides: 14, hue: 222),
    .Crown: .init(sides: 16, hue: 258),
]

// Ark color map (for Eternal bar) — kept for reference/legacy use
private let ARK_COLORS: [String: Color] = [
    "Ignition Ark": Color(hex: 0xff0024),
    "Integration Ark": Color(hex: 0xff6f00),
    "Harmonization Ark": Color(hex: 0xffd600),
    "Reflection Ark": Color(hex: 0x00c853),
    "Purification Ark": Color(hex: 0x00b0ff),
    "Dream Ark": Color(hex: 0xc186ff),

    // tolerate “ArK”
    "Ignition ArK": Color(hex: 0xff0024),
    "Integration ArK": Color(hex: 0xff6f00),
    "Harmonization ArK": Color(hex: 0xffd600),
    "Reflection ArK": Color(hex: 0x00c853),
    "Purification ArK": Color(hex: 0x00b0ff),
    "Dream ArK": Color(hex: 0xc186ff),
]

// === Chakra → Eternal color (exact, to drive the top progress bar) ============
private let CHAKRA_ETERNAL_COLORS: [KaiChakra: Color] = [
    .Root:        Color(hex: 0xff0024), // red
    .Sacral:      Color(hex: 0xff6f00), // orange
    .SolarPlexus: Color(hex: 0xffd600), // yellow
    .Heart:       Color(hex: 0x00c853), // green
    .Throat:      Color(hex: 0x00b0ff), // blue
    .ThirdEye:    Color(hue: 222/360.0, saturation: 1.0, brightness: 0.92), // indigo (derived)
    .Crown:       Color(hex: 0xc186ff), // violet
]

// Normalize Ark labels (handles “Reflekt/Purifikation/Ignite/ArK”, etc.)
private func normalizedArkName(_ raw: String) -> String {
    let s = raw.replacingOccurrences(of: "ArK", with: "Ark")
    let lower = s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    switch lower {
    case "ignition ark", "ignite ark", "ignite":                 return "Ignition Ark"
    case "integration ark", "integrate ark", "integrate":        return "Integration Ark"
    case "harmonization ark", "harmonize ark", "harmonize":      return "Harmonization Ark"
    case "reflection ark", "reflekt ark", "reflekt":             return "Reflection Ark"
    case "purification ark", "purifikation ark", "purifikation": return "Purification Ark"
    case "dream ark", "dream":                                   return "Dream Ark"
    default:
        // If it already contains 'Ark' with some name, keep it; else append.
        return raw.contains("Ark") ? raw : "\(raw) Ark"
    }
}

// Map Ark → Chakra (for bar color to be the eternal chakra color)
private func chakraForArk(_ arkName: String) -> KaiChakra {
    switch normalizedArkName(arkName) {
    case "Ignition Ark":       return .Root
    case "Integration Ark":    return .Sacral
    case "Harmonization Ark":  return .SolarPlexus
    case "Reflection Ark":     return .Heart
    case "Purification Ark":   return .Throat
    case "Dream Ark":          return .Crown
    default:                   return .Root
    }
}

// MARK: - EternalKlock model (added locally to satisfy references) -------------

struct EternalKlock: Codable, Hashable {
    struct ChakraStep: Codable, Hashable {
        let stepIndex: Int
        let percentIntoStep: Double
        let stepsPerBeat: Int
    }
    struct ChakraBeat: Codable, Hashable {
        let beatIndex: Int
        let pulsesIntoBeat: Int
        let beatPulseCount: Int
        let totalBeats: Int
    }
    struct EternalChakraBeat: Codable, Hashable {
        let beatIndex: Int
        let pulsesIntoBeat: Int
        let beatPulseCount: Int
        let totalBeats: Int
        let percentToNext: Double
    }
    struct HarmonicWeekProgress: Codable, Hashable {
        let weekDay: String
        let weekDayIndex: Int
        let pulsesIntoWeek: Int
        let percent: Double
    }
    struct EternalMonthProgress: Codable, Hashable {
        let daysElapsed: Int
        let daysRemaining: Int
        let percent: Double
    }
    struct HarmonicYearProgress: Codable, Hashable {
        let daysElapsed: Int
        let daysRemaining: Int
        let percent: Double
    }

    let kaiPulseEternal: Int
    let kaiPulseToday: Int
    let eternalKaiPulseToday: Int

    let kairos_seal_day_month: String
    let kairos_seal_day_month_percent: String
    let kairos_seal: String
    let eternalSeal: String

    let harmonicDay: String
    let weekIndex: Int
    let weekName: String
    let dayOfMonth: Int

    let eternalMonth: String
    let eternalMonthIndex: Int

    let eternalYearName: String
    let eternalChakraArc: String

    let chakraStepString: String
    let chakraStep: ChakraStep
    let chakraBeat: ChakraBeat
    let eternalChakraBeat: EternalChakraBeat

    let harmonicWeekProgress: HarmonicWeekProgress
    let eternalMonthProgress: EternalMonthProgress
    let harmonicYearProgress: HarmonicYearProgress

    let kaiMomentSummary: String
    let compressed_summary: String
    let phiSpiralLevel: Int
}

// MARK: - Fixed-point helpers --------------------------------------------------

@inline(__always) private func imod(_ n: Int64, _ m: Int64) -> Int64 { let r = n % m; return (r + m) % m }

@inline(__always) private func floorDiv(_ n: Int64, _ d: Int64) -> Int64 {
    precondition(d != 0)
    let q = n / d
    let r = n % d
    return (r != 0 && ((r > 0) != (d > 0))) ? (q - 1) : q
}

/// ties-to-even rounding
private func roundTiesToEvenInt64(_ x: Double) -> Int64 {
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

/// μpulses since Genesis (KKS-1.0; single source of truth)
private func microPulsesSinceGenesis(_ date: Date) -> Int64 {
    let delta = date.timeIntervalSince(GENESIS_TS) // seconds
    let pulses = delta / KAI_PULSE_SEC
    let micro = pulses * 1_000_000.0
    return roundTiesToEvenInt64(micro)
}

// MARK: - Local Kai compute ----------------------------------------------------

private struct LocalKai {
    let pulse: Int
    let beat: Int
    let step: Int        // 0..43
    let stepPct: Double
    let pulsesIntoBeat: Int
    let pulsesIntoDay: Int
    let harmonicDay: HarmonicDay
    let chakraDay: KaiChakra
    let chakraStepString: String // "beat:SS"
    let dayOfMonth: Int // 1..42
    let monthIndex0: Int
    let monthIndex1: Int
    let monthName: String
    let yearIndex: Int
    let yearName: String
    let arcIndex: Int
    let arcName: String
    let weekIndex: Int
    let weekName: String

    // μpulse internals (for precise %s)
    let _pμ_in_day: Int64
    let _pμ_in_beat: Int64
}

private func computeLocalKai(_ date: Date) -> LocalKai {
    let pμ_total = microPulsesSinceGenesis(date)

    // Position within exact eternal day (μpulses)
    let pμ_in_day = imod(pμ_total, N_DAY_MICRO)
    let dayIndex = floorDiv(pμ_total, N_DAY_MICRO)

    // Beat/step from exact μpulse math
    let beatI64 = floorDiv(pμ_in_day, MU_PER_BEAT_EXACT)
    let beat = Int(beatI64)
    let pμ_in_beat = pμ_in_day - Int64(beat) * MU_PER_BEAT_EXACT

    let rawStep = Int(pμ_in_beat / PULSES_PER_STEP_MICRO)
    let step = max(0, min(rawStep, STEPS_BEAT - 1))
    let pμ_in_step = pμ_in_beat - Int64(step) * PULSES_PER_STEP_MICRO
    let stepPct = Double(pμ_in_step) / Double(PULSES_PER_STEP_MICRO)

    // Pulses (whole) derived from μpulses
    let pulse = Int(floorDiv(pμ_total, ONE_PULSE_MICRO))
    let pulsesIntoBeat = Int(pμ_in_beat / ONE_PULSE_MICRO)
    let pulsesIntoDay = Int(pμ_in_day / ONE_PULSE_MICRO)

    // Calendar mappings
    let harmonicDayIndex = Int(imod(dayIndex, Int64(DAYS_PER_WEEK)))
    let harmonicDay = HarmonicDay.allCases[harmonicDayIndex]
    let chakraDay = DAY_TO_CHAKRA[harmonicDay] ?? .Root

    let dayIndexNum = Int(dayIndex)
    let dayOfMonth = ((dayIndexNum % DAYS_PER_MONTH) + DAYS_PER_MONTH) % DAYS_PER_MONTH + 1

    let monthsSinceGenesis = dayIndexNum / DAYS_PER_MONTH
    let monthIndex0 = ((monthsSinceGenesis % MONTHS_PER_YEAR) + MONTHS_PER_YEAR) % MONTHS_PER_YEAR
    let monthIndex1 = monthIndex0 + 1
    let monthName = ETERNAL_MONTH_NAMES[monthIndex0]

    let yearIndex = dayIndexNum / DAYS_PER_YEAR
    let yearName: String = {
        if yearIndex < 1 { return "Year of Harmonik Restoration" }
        if yearIndex == 1 { return "Year of Harmonik Embodiment" }
        return "Year \(yearIndex)"
    }()

    let arcIndex = Int((pμ_in_day * 6) / N_DAY_MICRO)
    let arcName = arcLabel(ARC_NAMES[max(0, min(5, arcIndex))])

    let weekIndex = (dayOfMonth - 1) / DAYS_PER_WEEK
    let weekName = [
        "Awakening Flame","Flowing Heart","Radiant Will",
        "Harmonic Voice","Inner Mirror","Dreamfire Memory","Krowned Light",
    ][weekIndex]

    let chakraStepString = "\(beat):\(String(format: "%02d", step))"

    return .init(
        pulse: pulse, beat: beat, step: step, stepPct: stepPct,
        pulsesIntoBeat: pulsesIntoBeat, pulsesIntoDay: pulsesIntoDay,
        harmonicDay: harmonicDay, chakraDay: chakraDay, chakraStepString: chakraStepString,
        dayOfMonth: dayOfMonth, monthIndex0: monthIndex0, monthIndex1: monthIndex1,
        monthName: monthName, yearIndex: yearIndex, yearName: yearName,
        arcIndex: arcIndex, arcName: arcName, weekIndex: weekIndex, weekName: weekName,
        _pμ_in_day: pμ_in_day, _pμ_in_beat: pμ_in_beat
    )
}

// MARK: - EternalKlock snapshot -----------------------------------------------

/// Build eternal snapshot from computed LocalKai (single source of truth).
private func buildEternalKlock(_ kai: LocalKai) -> EternalKlock {
    // % of eternal day (μpulse-exact → float)
    let dayPercent = min(100.0, max(0.0, (Double(kai.pulsesIntoDay) / DAY_PULSES) * 100.0))

    // month & year progress (by days; Eternal-Klok uses fixed spans)
    let monthDaysElapsed = kai.dayOfMonth - 1
    let monthDaysRemain  = DAYS_PER_MONTH - kai.dayOfMonth
    let monthPercent = (Double(monthDaysElapsed) / Double(DAYS_PER_MONTH)) * 100.0

    let yearDayIndexInYear = (kai.monthIndex0 * DAYS_PER_MONTH) + (kai.dayOfMonth - 1)
    let yearDaysRemain = DAYS_PER_YEAR - 1 - yearDayIndexInYear
    let yearPercent = (Double(yearDayIndexInYear) / Double(DAYS_PER_YEAR)) * 100.0

    // week progress (by day position inside 6-day week)
    let weekDayIndex = (kai.dayOfMonth - 1) % DAYS_PER_WEEK
    let weekPercent = (Double(weekDayIndex) / Double(DAYS_PER_WEEK)) * 100.0
    let pulsesPrevDaysInWeek = Int(Double(weekDayIndex) * DAY_PULSES)
    let pulsesIntoWeek = pulsesPrevDaysInWeek + kai.pulsesIntoDay

    // percent to next beat (μpulse-exact)
    let percentToNextBeat = Double(kai._pμ_in_beat) / Double(MU_PER_BEAT_EXACT) * 100.0

    // seals & summaries (NO timestamp)
    let sealDM = "\(kai.chakraStepString) — D\(kai.dayOfMonth)/M\(kai.monthIndex1)"
    let sealDMPercent = "\(sealDM) • \(String(format: "%.2f", dayPercent))%"
    let momentSummary = "Eternal Seal • \(kai.harmonicDay.rawValue) — D\(kai.dayOfMonth) \(kai.monthName) — \(kai.yearName) — \(kai.arcName)"

    return EternalKlock(
        kaiPulseEternal: kai.pulse,
        kaiPulseToday: kai.pulsesIntoDay,
        eternalKaiPulseToday: kai.pulsesIntoDay,
        kairos_seal_day_month: sealDM,
        kairos_seal_day_month_percent: sealDMPercent,
        kairos_seal: sealDM,
        eternalSeal: sealDM,
        harmonicDay: kai.harmonicDay.rawValue,
        weekIndex: kai.weekIndex,
        weekName: kai.weekName,
        dayOfMonth: kai.dayOfMonth,
        eternalMonth: kai.monthName,
        eternalMonthIndex: kai.monthIndex1,
        eternalYearName: kai.yearName,
        eternalChakraArc: kai.arcName,
        chakraStepString: kai.chakraStepString,
        chakraStep: .init(stepIndex: kai.step, percentIntoStep: kai.stepPct, stepsPerBeat: STEPS_BEAT),
        chakraBeat: .init(beatIndex: kai.beat, pulsesIntoBeat: kai.pulsesIntoBeat, beatPulseCount: BEAT_PULSES_ROUNDED, totalBeats: BEATS_DAY),
        eternalChakraBeat: .init(beatIndex: kai.beat, pulsesIntoBeat: kai.pulsesIntoBeat, beatPulseCount: BEAT_PULSES_ROUNDED, totalBeats: BEATS_DAY, percentToNext: percentToNextBeat),
        harmonicWeekProgress: .init(weekDay: kai.harmonicDay.rawValue, weekDayIndex: weekDayIndex, pulsesIntoWeek: pulsesIntoWeek, percent: weekPercent),
        eternalMonthProgress: .init(daysElapsed: monthDaysElapsed, daysRemaining: monthDaysRemain, percent: monthPercent),
        harmonicYearProgress: .init(daysElapsed: yearDayIndexInYear, daysRemaining: yearDaysRemain, percent: yearPercent),
        kaiMomentSummary: momentSummary,
        compressed_summary: momentSummary,
        phiSpiralLevel: 1
    )
}

// MARK: - φ Boundary Scheduler + Countdown (FIXED SYNC) -----------------------

final class KaiPulseEngine: ObservableObject {
    @Published var now: Date = Date()
    @Published var nextBoundary: Date = Date()
    @Published var secondsLeft: Double = KAI_PULSE_SEC

    private var displayLink: CADisplayLink?
    private var timer: Timer?

    // Monotonic → wall calibration
    private var wallOffsetMs: Double = 0 // wallMs ≈ bootMs + wallOffsetMs
    private let genesisMs: Double = GENESIS_TS.timeIntervalSince1970 * 1000.0

    init() { alignAndStart() }
    deinit { stop() }

    private func bootMs() -> Double { CACurrentMediaTime() * 1000.0 }
    private func wallMs() -> Double { bootMs() + wallOffsetMs }

    private func pulseNow() -> Double { (wallMs() - genesisMs) / PULSE_MS }

    private func computeNextBoundaryMs(from nowWallMs: Double) -> Double {
        let p = (nowWallMs - genesisMs) / PULSE_MS
        let nextIndex = ceil(p) // next integer pulse
        return genesisMs + nextIndex * PULSE_MS
    }

    func alignAndStart() {
        stop()

        // Calibrate once per start/foreground: wall - boot
        let boot = bootMs()
        let wall = Date().timeIntervalSince1970 * 1000.0
        wallOffsetMs = wall - boot

        // Compute first boundary from calibrated wall
        let nowW = wallMs()
        let target = computeNextBoundaryMs(from: nowW)
        nextBoundary = Date(timeIntervalSince1970: target / 1000.0)

        // High-accuracy one-shot timer to boundary
        let delay = max(0, (target - nowW) / 1000.0)
        let t = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            self?.handleBoundaryFire(expectedTargetMs: target)
        }
        t.tolerance = 0 // exact flip
        RunLoop.main.add(t, forMode: .common)
        timer = t

        // Display link for smooth countdown (60fps)
        let dl = CADisplayLink(target: self, selector: #selector(tick))
        dl.preferredFrameRateRange = .init(minimum: 30, maximum: 120, preferred: 60)
        dl.add(to: .main, forMode: .common)
        displayLink = dl
    }

    func stop() {
        timer?.invalidate(); timer = nil
        displayLink?.invalidate(); displayLink = nil
    }

    private func rescheduleNext(from firedWallMs: Double) {
        // Recompute off of *actual* current wall time to avoid drift
        let nowW = wallMs()
        let base = max(firedWallMs, nowW)
        let target = computeNextBoundaryMs(from: base)
        nextBoundary = Date(timeIntervalSince1970: target / 1000.0)

        let delay = max(0, (target - nowW) / 1000.0)
        let t = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            self?.handleBoundaryFire(expectedTargetMs: target)
        }
        t.tolerance = 0
        RunLoop.main.add(t, forMode: .common)
        timer?.invalidate()
        timer = t
    }

    private func handleBoundaryFire(expectedTargetMs: Double) {
        // Snap the logical "now" to the *exact* boundary moment for μpulse math.
        now = Date(timeIntervalSince1970: expectedTargetMs / 1000.0)
        rescheduleNext(from: expectedTargetMs)
    }

    @objc private func tick() {
        let nowW = wallMs()
        let targetMs = nextBoundary.timeIntervalSince1970 * 1000.0
        let diff = targetMs - nowW

        // Smooth countdown
        secondsLeft = max(0, diff / 1000.0)

        // Clamp UI "now" so it never crosses the boundary early.
        let clampedMs = diff > 0 ? min(nowW, targetMs - 0.25) : targetMs // 0.25ms guard
        now = Date(timeIntervalSince1970: clampedMs / 1000.0)
    }
}

// MARK: - Sigil Geometry + Renderer (visual parity with TSX) -------------------

private struct KaiSigilRenderParams: Hashable {
    var pulse: Int
    var beat: Int
    var stepPct: Double // 0..1
    var chakra: KaiChakra

    // derived visuals
    var a: Double
    var b: Double
    var delta: Double // phase
    var rotation: Double // polygon rotation
    var sides: Int
    var hue: Double

    init(pulse: Int, beat: Int, stepPct: Double, chakra: KaiChakra) {
        self.pulse = pulse
        self.beat = beat
        self.stepPct = max(0, min(1, stepPct))
        self.chakra = chakra
        let spec = CHAKRAS[chakra] ?? .init(sides: 8, hue: 122)
        self.sides = spec.sides
        self.hue = spec.hue
        self.a = Double((pulse % 7) + 1)
        self.b = Double((beat % 5) + 2)
        self.delta = self.stepPct * 2 * .pi
        self.rotation = (pow((1+sqrt(5.0))/2.0, 2) * .pi * Double(pulse % 97))
            .truncatingRemainder(dividingBy: 2 * .pi)
    }
}

private func polygonPoints(in rect: CGRect, sides: Int, rotation: Double, radiusScale: CGFloat = 0.38) -> [CGPoint] {
    let r = min(rect.width, rect.height) * radiusScale
    let cx = rect.midX, cy = rect.midY
    return (0..<sides).map { i in
        let t = (Double(i) / Double(sides)) * 2 * .pi + rotation
        return CGPoint(x: cx + CGFloat(cos(t)) * r, y: cy + CGFloat(sin(t)) * r)
    }
}

private func polygonPath(in rect: CGRect, sides: Int, rotation: Double, radiusScale: CGFloat = 0.38) -> Path {
    let pts = polygonPoints(in: rect, sides: sides, rotation: rotation, radiusScale: radiusScale)
    var p = Path()
    for (i, pt) in pts.enumerated() { i == 0 ? p.move(to: pt) : p.addLine(to: pt) }
    p.closeSubpath()
    return p
}

private func lissajousPath(in rect: CGRect, a: Double, b: Double, delta: Double) -> Path {
    let w = rect.width, h = rect.height
    var p = Path()
    let N = 360
    for i in 0..<N {
        let t = (Double(i) / Double(N - 1)) * 2 * .pi
        let x = ((sin(a * t + delta) + 1) / 2) * w
        let y = ((sin(b * t) + 1) / 2) * h
        if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
    }
    p.closeSubpath()
    return p
}

private struct KaiSigilView: View {
    var params: KaiSigilRenderParams
    var size: CGFloat = 240

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            GeometryReader { _ in
                Canvas { ctx, sz in
                    let rect = CGRect(origin: .zero, size: sz)
                    let core = polygonPath(in: rect, sides: params.sides, rotation: params.rotation)
                    let aura = lissajousPath(in: rect, a: params.a, b: params.b, delta: params.delta)

                    // background
                    let rectPath = Path(rect)
                    ctx.fill(rectPath, with: .color(Color(hex: 0x060A10)))

                    // halo vignette (radial, animated by phase via brightness oscillation)
                    let light = 0.50 + 0.15 * sin(params.stepPct * 2 * .pi)
                    let phaseHue = (params.hue + 360.0 * 0.03 * params.stepPct).truncatingRemainder(dividingBy: 360.0)
                    let halo = Gradient(colors: [
                        Color(hue: phaseHue/360.0, saturation: 1, brightness: light, opacity: 0.55),
                        Color.clear
                    ])
                    ctx.fill(rectPath,
                             with: .radialGradient(halo,
                                                   center: .init(x: sz.width/2, y: sz.height/2),
                                                   startRadius: 0,
                                                   endRadius: min(sz.width, sz.height)*0.5))

                    // Neon aura stack (cyan → blue → white)
                    let w1 = max(1.6, size * 0.009)
                    let w2 = max(1.2, size * 0.008)
                    let w3 = max(0.6, size * 0.0035)

                    ctx.addFilter(.shadow(color: .cyan.opacity(0.55), radius: 22, x: 0, y: 0))
                    ctx.stroke(aura, with: .color(.cyan), lineWidth: w1)
                    ctx.addFilter(.blur(radius: 6))
                    ctx.stroke(aura, with: .color(Color.blue.opacity(0.85)), lineWidth: w2)
                    ctx.addFilter(.shadow(color: .white.opacity(0.9), radius: 1, x: 0, y: 0))
                    ctx.stroke(aura, with: .color(.white), lineWidth: w3)

                    // Core polygon (phase hue)
                    let coreColor = Color(hue: phaseHue/360.0, saturation: 1, brightness: 0.95)
                    ctx.addFilter(.shadow(color: .white.opacity(0.25), radius: 3, x: 0, y: 0))
                    ctx.stroke(core, with: .color(coreColor), lineWidth: max(1.2, size * 0.0048))

                    // Vertex dots
                    let pts = polygonPoints(in: rect, sides: params.sides, rotation: params.rotation)
                    let dotR = max(2.5, size * 0.016)
                    for pt in pts {
                        let circleRect = CGRect(x: pt.x - dotR, y: pt.y - dotR, width: dotR*2, height: dotR*2)
                        ctx.fill(Path(ellipseIn: circleRect), with: .color(coreColor.opacity(0.95)))
                    }

                    // Center node
                    let cDot = max(3.0, dotR * 0.9)
                    let cRect = CGRect(x: sz.width/2 - cDot, y: sz.height/2 - cDot, width: cDot*2, height: cDot*2)
                    ctx.fill(Path(ellipseIn: cRect), with: .color(Color.cyan))
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.cyan.opacity(0.25), lineWidth: 1)
                    .shadow(color: Color.cyan.opacity(0.18), radius: 12, x: 0, y: 0)
            )

            // Pulse tag (bottom-right)
            Text(params.pulse.formatted())
                .font(.system(size: 17, weight: .heavy, design: .monospaced))
                .foregroundColor(Color.white.opacity(0.9))
                .shadow(color: .cyan.opacity(0.9), radius: 6, x: 0, y: 0)
                .padding(.trailing, 16).padding(.bottom, 12)
        }
        .accessibilityLabel("Kairos sigil · pulse \(params.pulse)")
    }
}

// MARK: - SVG Export (NO timestamp; embeds EternalKlock JSON) ------------------

private func svgPathStringPolygon(size: CGFloat, sides: Int, rotation: Double, radiusScale: CGFloat = 0.38) -> String {
    let r = size * radiusScale
    let cx = size / 2.0, cy = size / 2.0
    var d = ""
    for i in 0..<sides {
        let t = (Double(i) / Double(sides)) * 2 * .pi + rotation
        let x = cx + CGFloat(cos(t)) * r
        let y = cy + CGFloat(sin(t)) * r
        let cmd = (i == 0) ? "M" : "L"
        d += "\(cmd)\(Int(x.rounded())),\(Int(y.rounded()))"
    }
    d += "Z"
    return d
}

private func svgPathStringLissajous(size: CGFloat, a: Double, b: Double, delta: Double, steps: Int = 360) -> String {
    var d = ""
    for i in 0..<steps {
        let t = (Double(i) / Double(steps - 1)) * 2 * .pi
        let x = ((sin(a * t + delta) + 1) / 2) * size
        let y = ((sin(b * t) + 1) / 2) * size
        let cmd = (i == 0) ? "M" : "L"
        d += "\(cmd)\(Int(x.rounded())),\(Int(y.rounded()))"
    }
    d += "Z"
    return d
}

private func jsonString<T: Encodable>(_ value: T) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    if #available(iOS 15.0, *) { encoder.outputFormatting.insert(.prettyPrinted) }
    if let data = try? encoder.encode(value), let s = String(data: data, encoding: .utf8) { return s }
    return "{}"
}

private func buildSVG(size: CGFloat, params: KaiSigilRenderParams, klock: EternalKlock) -> String {
    let coreD = svgPathStringPolygon(size: size, sides: params.sides, rotation: params.rotation)
    let auraD = svgPathStringLissajous(size: size, a: params.a, b: params.b, delta: params.delta)

    let klockJSON = jsonString(klock)
    let hue = params.hue
    let w = Int(size)

    // NO QR, NO ISO timestamps; Eternal payload embedded verbatim (CDATA)
    return """
    <?xml version="1.0" encoding="UTF-8"?>
    <svg xmlns="http://www.w3.org/2000/svg" width="\(w)" height="\(w)" viewBox="0 0 \(w) \(w)" version="1.1" aria-label="Kairos HarmoniK Sigil · Pulse \(params.pulse)">
      <title>Kairos HarmoniK Sigil • Pulse \(params.pulse)</title>
      <desc>Eternal Seal • \(klock.eternalSeal)</desc>
      <metadata><![CDATA[\(klockJSON)]]></metadata>
      <rect x="0" y="0" width="100%" height="100%" fill="#060A10"/>
      <g>
        <path d="\(auraD)" fill="none" stroke="#00ffff" stroke-width="\(max(1.6, size * 0.009))" opacity="0.9"/>
        <path d="\(auraD)" fill="none" stroke="rgba(30,80,255,0.85)" stroke-width="\(max(1.2, size * 0.008))"/>
        <path d="\(auraD)" fill="none" stroke="white" stroke-width="\(max(0.6, size * 0.0035))" opacity="0.9"/>
        <path d="\(coreD)" fill="none" stroke="hsl(\(hue) 100% 95%)" stroke-width="\(max(1.2, size * 0.0048))" opacity="0.95"/>
      </g>
    </svg>
    """
}

// MARK: - Holographic Close Button (FIXED: stateless, phase-driven) ------------

private struct HoloCloseButton: View {
    var pulseDuration: Double
    var action: () -> Void

    private func ringScale(_ phase: Double) -> CGFloat {
        let eased = 1.0 - pow(1.0 - phase, 3.0)
        return CGFloat(0.22 + 1.68 * eased) // ≈ 0.22 → 1.90
    }
    private func ringOpacity(_ phase: Double) -> Double {
        0.90 * (1.0 - phase)
    }

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate

            // continuous spin: 360° every 3.8s
            let spinPeriod = 3.8
            let spinAngle = Angle(degrees: (t.truncatingRemainder(dividingBy: spinPeriod) / spinPeriod) * 360.0)

            // ring phase tied to Kai pulse (0→1 each pulse)
            let ringPhase = t.truncatingRemainder(dividingBy: pulseDuration) / pulseDuration
            let s = ringScale(ringPhase)
            let o = ringOpacity(ringPhase)

            Button(action: action) {
                ZStack {
                    Circle()
                        .inset(by: 6)
                        .fill(
                            AngularGradient(gradient: Gradient(stops: [
                                .init(color: .clear,                    location: 0.00),
                                .init(color: Color.cyan.opacity(0.92),  location: 0.28),
                                .init(color: .clear,                    location: 0.42),
                                .init(color: .clear,                    location: 1.00),
                            ]), center: .center)
                        )
                        .blur(radius: 1.2)
                        .shadow(color: Color.cyan.opacity(0.6), radius: 6, x: 0, y: 0)
                        .rotationEffect(spinAngle)

                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Color.white.opacity(0.9))
                        .shadow(color: .cyan.opacity(0.6), radius: 3, x: 0, y: 0)

                    Circle()
                        .strokeBorder(Color.cyan.opacity(0.6), lineWidth: 2)
                        .shadow(color: Color.cyan.opacity(0.8), radius: 8, x: 0, y: 0)
                        .scaleEffect(s)
                        .opacity(o)
                }
                .frame(width: 48, height: 48)
                .background(Color.clear)
                .overlay(
                    Circle().stroke(Color.cyan.opacity(0.33), lineWidth: 1)
                        .shadow(color: Color.cyan.opacity(0.33), radius: 6, x: 0, y: 0)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }
}

// MARK: - Moment Row (countdown + Eternal day bar) -----------------------------

private struct SigilMomentRow: View {
    var secondsLeft: Double?
    var eternalPercent: Double
    var eternalColor: Color
    var eternalArkLabel: String

    var body: some View {
        VStack(spacing: 10) {
            if let secs = secondsLeft {
                Text("Kairos · next pulse in \(secs, specifier: "%.6f")s")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(Color.cyan.opacity(0.9))
                    .shadow(color: .white.opacity(0.15), radius: 1, x: 0, y: 0)
            }

            VStack(alignment: .leading, spacing: 6) {
                LabeledBar(label: eternalArkLabel, percent: eternalPercent, color: eternalColor)
            }
        }
        .padding(.horizontal, 8)
    }

    private struct LabeledBar: View {
        var label: String
        var percent: Double
        var color: Color
        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(label).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(percent, specifier: "%.2f")%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: min(1, max(0, percent/100)))
                    .tint(color)
                    .shadow(color: color.opacity(0.35), radius: 6, x: 0, y: 0)
            }
        }
    }
}

// MARK: - Backdrop & Card Background ------------------------------------------

private struct BackdropView: View {
    var body: some View {
        LinearGradient(stops: [
            .init(color: Color.black, location: 0),
            .init(color: Color(hex: 0x031019), location: 0.6),
            .init(color: Color.black, location: 1)
        ], startPoint: .top, endPoint: .bottom)
        .ignoresSafeArea()
        .overlay(
            RadialGradient(colors: [Color.cyan.opacity(0.07), Color.cyan.opacity(0.05), .clear],
                           center: UnitPoint.top, startRadius: 80, endRadius: 800)
                .ignoresSafeArea()
                .blur(radius: 2)
        )
    }
}

private struct CardBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(
                LinearGradient(colors: [Color(hex: 0x10171e), Color(hex: 0x05080c)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.cyan.opacity(0.15), lineWidth: 1)
                    .shadow(color: Color.cyan.opacity(0.18), radius: 12, x: 0, y: 0)
            )
    }
}

// MARK: - Main Modal -----------------------------------------------------------

struct KaiSigilModalView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var engine = KaiPulseEngine()

    // static controls
    @State private var useStaticDate = false
    @State private var staticDate: Date = Date()
    @State private var breathIndex: Int = 1

    // share (legacy)
    @State private var showShareSheet = false
    @State private var shareItem: ShareItem? = nil

    // stargate
    @State private var showStargate = false

    // RICH DATA expansion
    @State private var showRich = false

    // Seal panel
    @State private var showSealPanel = false
    @State private var sealUrl: URL? = nil
    @State private var sealHash: String = ""

    // Verifier
    @State private var showVerifier = false

    // derived Kai (single source)
    private var kai: LocalKai { computeLocalKai(effectiveDate) }
    private var effectiveDate: Date {
        if !useStaticDate { return engine.now }
        let local = Calendar.current
        let comps = local.dateComponents(in: .current, from: staticDate)
        var baseMin = comps
        baseMin.second = 0; baseMin.nanosecond = 0
        let minuteStart = local.date(from: baseMin) ?? staticDate
        let offset = Double(breathIndex - 1) * KAI_PULSE_SEC
        return minuteStart.addingTimeInterval(offset)
    }

    // Eternal snapshot & color/percent
    private var klock: EternalKlock { buildEternalKlock(kai) }

    // === Top bar color now derives from the eternal CHAKRA color (Ark → Chakra) ===
    private var eternalColor: Color {
        let chakra = chakraForArk(kai.arcName)
        return CHAKRA_ETERNAL_COLORS[chakra] ?? Color(hex: 0xffd600)
    }

    private var beatStepDisplay: String { "\(kai.beat):\(String(format: "%02d", kai.step))" }
    private var kairosSealDayMonth: String {
        "\(beatStepDisplay) — D\(kai.dayOfMonth)/M\(kai.monthIndex1)/Y\(kai.yearIndex)/P\(kai.pulse)"
    }

    var body: some View {
        // Ark bar percent (exact eternal-day %)
        let arkPercent: Double = min(100, max(0, (Double(kai.pulsesIntoDay) / DAY_PULSES) * 100.0))
        let stepPct: Double = useStaticDate ? computeLocalKai(effectiveDate).stepPct : kai.stepPct
        let sigilParams = KaiSigilRenderParams(pulse: kai.pulse, beat: kai.beat, stepPct: stepPct, chakra: kai.chakraDay)

        ZStack {
            BackdropView()

            VStack(spacing: 12) {
                ZStack {
                    // Card shell
                    ScrollView {
                        VStack(spacing: 14) {
                            // Title
                            Text("Sigil-Glyph Inhaler")
                                .font(.system(size: 36, weight: .heavy, design: .rounded))
                                .foregroundStyle(LinearGradient(colors: [Color.cyan, Color.white.opacity(0.95), Color.cyan, Color(hex: 0xff1559)], startPoint: .leading, endPoint: .trailing))
                                .shadow(color: Color.cyan.opacity(0.14), radius: 12, x: 0, y: 2)
                                .padding(.top, 6)

                            // Moment Row (countdown + Eternal day bar)
                            SigilMomentRow(
                                secondsLeft: engine.secondsLeft,
                                eternalPercent: arkPercent,
                                eternalColor: eternalColor,
                                eternalArkLabel: kai.arcName
                            )

                            // Static controls
                            StaticControls(
                                useStaticDate: $useStaticDate,
                                staticDate: $staticDate,
                                breathIndex: $breathIndex,
                                onNow: { useStaticDate = false; breathIndex = 1; engine.alignAndStart() }
                            )
                            .padding(.horizontal)

                            // Sigil
                            SigilSection(sigilParams: sigilParams, kai: kai)

                            // Metadata block (copy buttons)
                            SigilMetaBlock(kai: kai, kairosSealDayMonth: kairosSealDayMonth)

                            // RICH DATA — Eternal-Klok parity (NO timestamp)
                            DisclosureGroup(isExpanded: $showRich) {
                                RichGrid(klock: klock).padding(.top, 8)
                            } label: {
                                Text("Memory")
                                    .font(.headline)
                                    .foregroundStyle(LinearGradient(colors: [Color.cyan, Color.white, Color.cyan], startPoint: .leading, endPoint: .trailing))
                            }
                            .padding(.horizontal)
                            .padding(.bottom, 6)

                            Spacer(minLength: 100) // space above dock
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 56)
                        .padding(.bottom, 90)
                    }
                }
                .frame(maxWidth: 600)
                .background(CardBackground())
                .padding(.horizontal)
            }

            // ===== Sticky FAB Dock (bottom) =====
            VStack {
                Spacer()
                HStack(spacing: 14) {
                    Fab(icon: .checkmarkShield, title: "Verify") { openVerifier() } // <- wired to VerifierModal()
                    Fab(icon: .seal, title: "Seal") { openSealMoment(params: sigilParams) }
                    Fab(icon: .sparkles, title: "Stargate") { showStargate = true }
                }
                .padding(.bottom, max(10, safeBot()))
            }
            .padding(.horizontal, 12)
        }
        // Close button as stable overlay
        .overlay(alignment: .topTrailing) {
            HoloCloseButton(pulseDuration: KAI_PULSE_SEC) { dismiss() }
                .padding(.top, 10)
                .padding(.trailing, 10)
        }
        .sheet(isPresented: $showShareSheet) {
            if let item = shareItem {
                ActivityView(activityItems: [item.payload], applicationActivities: nil)
            }
        }
        .sheet(isPresented: $showStargate) {
            StargateView(params: sigilParams)
                .background(Color.black.ignoresSafeArea())
        }
        .fullScreenCover(isPresented: $showSealPanel) {
            if let url = sealUrl {
                SealMomentPanel(
                    hash: sealHash,
                    url: url,
                    onClose: { showSealPanel = false }
                )
                .background(Color.clear.ignoresSafeArea())
                .onAppear { registerSigilUrlLocally(url) }
            }
        }
        // Real Verifier (full-screen)
        .sheet(isPresented: $showVerifier) {
            VerifierModal()
        }
    }

    // MARK: - Export helpers (legacy)
    private func exportPNG(params: KaiSigilRenderParams) {
        let renderer = ImageRenderer(content: KaiSigilView(params: params, size: 1024))
        renderer.isOpaque = true
        if let ui = renderer.uiImage {
            shareItem = .init(payload: ui)
            showShareSheet = true
        }
    }

    private func exportSVG(params: KaiSigilRenderParams) {
        // Eternal parity bundle (embedded) — NO timestamps
        let klockPayload = buildEternalKlock(computeLocalKai(engine.now))
        let svg = buildSVG(size: 1024, params: params, klock: klockPayload)
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("sigil_\(params.pulse).svg")
        try? svg.data(using: String.Encoding.utf8)?.write(to: tmp)
        shareItem = .init(payload: tmp)
        showShareSheet = true
    }

    // MARK: - Seal helper (hash + URL + panel)
    private func openSealMoment(params: KaiSigilRenderParams) {
        // Build deterministic SVG → canonical hash
        let klockPayload = buildEternalKlock(computeLocalKai(engine.now))
        let svg = buildSVG(size: 1024, params: params, klock: klockPayload)
        let canonical = sha256Hex(svg)

        // Use discrete step index visible in UI
        let stepIndex = computeLocalKai(engine.now).step
        let payload = SigilSharePayload(
            pulse: params.pulse,
            beat: params.beat,
            stepIndex: stepIndex,
            chakraDay: params.chakra.rawValue,
            stepsPerBeat: STEPS_BEAT,
            canonicalHash: canonical,
            expiresAtPulse: params.pulse + 11
        )
        let url = makeSigilUrl(canonicalHash: canonical, payload: payload)

        self.sealHash = canonical
        self.sealUrl = url
        self.showSealPanel = true
    }

    private func openVerifier() {
        showVerifier = true
    }

    private func safeBot() -> CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.safeAreaInsets.bottom }
            .first ?? 0
    }
}

// MARK: - Subsections ----------------------------------------------------------

private struct StaticControls: View {
    @Binding var useStaticDate: Bool
    @Binding var staticDate: Date
    @Binding var breathIndex: Int
    var onNow: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Toggle(isOn: $useStaticDate) { Text("Static moment") }
                .tint(.cyan)

            if useStaticDate {
                DatePicker("Pick date & time", selection: $staticDate, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.compact)

                HStack {
                    Text("Breath within minute:")
                    Spacer()
                    Picker("", selection: $breathIndex) {
                        ForEach(1...11, id: \.self) { i in
                            Text("Breath \(i) — \(Double(i-1)*KAI_PULSE_SEC, specifier: "%.3f")s").tag(i)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Button("Now") { onNow() }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
            }
        }
    }
}

private struct SigilSection: View {
    let sigilParams: KaiSigilRenderParams
    let kai: LocalKai

    var body: some View {
        VStack(spacing: 8) {
            KaiSigilView(params: sigilParams, size: 240)
                .id(sigilParams)
                .padding(.top, 6)
        }
    }
}

private struct Fab: View {
    var icon: SFSymbol
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(colors: [Color.white.opacity(0.15), Color.white.opacity(0.05)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .background(
                        Circle().fill(
                            RadialGradient(colors: [Color.white.opacity(0.14), Color.white.opacity(0.06)],
                                           center: UnitPoint.top, startRadius: 0, endRadius: 120)
                        )
                    )
                    .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
                    .overlay(Circle().stroke(Color.cyan.opacity(0.25), lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.35), radius: 28, x: 0, y: 8)
                    .shadow(color: Color(hex: 0xFFD778).opacity(0.08), radius: 40, x: 0, y: 0)

                Image(systemName: icon.systemName)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 0)
            }
            .frame(width: 64, height: 64)
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .accessibilityLabel(Text(title))
    }
}

private enum SFSymbol: String {
    case sparkles = "sparkles"
    case seal = "seal"
    case checkmarkShield = "checkmark.shield"
    var systemName: String { rawValue }
}

// Metadata block with copy buttons
private struct SigilMetaBlock: View {
    let kai: LocalKai
    let kairosSealDayMonth: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Eternal Time:").bold()
                Text("\(kai.chakraStepString)")
                CopyBtn(text: kai.chakraStepString)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Kairos Seal:").bold()
                Text(kairosSealDayMonth)
                CopyBtn(text: kairosSealDayMonth)
            }
            Group {
                Labeled(k: "Day", v: "\(kai.harmonicDay.rawValue)")
                Labeled(k: "Month", v: "\(kai.monthName)")
                Labeled(k: "Arc", v: "\(kai.arcName)")
                Labeled(k: "Year", v: "\(kai.yearName)")
            }
            .padding(.top, 4)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [Color.white.opacity(0.06), Color.white.opacity(0.02)],
                                     startPoint: .top, endPoint: .bottom))
                .background(
                    ZStack {
                        RadialGradient(colors: [Color.cyan.opacity(0.10), .clear], center: UnitPoint.topLeading, startRadius: 0, endRadius: 300)
                        RadialGradient(colors: [Color.purple.opacity(0.10), .clear], center: UnitPoint.bottomTrailing, startRadius: 0, endRadius: 300)
                    }
                )
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.cyan.opacity(0.35), lineWidth: 1))
        )
        .accessibilityElement(children: .combine)
    }

    private struct Labeled: View {
        var k: String; var v: String
        var body: some View {
            HStack(alignment: .firstTextBaseline) {
                Text("\(k):").bold()
                Text(v)
            }
        }
    }

    private struct CopyBtn: View {
        var text: String
        @State private var copied = false
        var body: some View {
            Button(copied ? "Copied" : "Kopy") {
                UIPasteboard.general.string = text
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { copied = false }
            }
            .font(.system(size: 12, weight: .semibold))
            .padding(.vertical, 6).padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(colors: [Color.white.opacity(0.06), Color.white.opacity(0.02)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.cyan.opacity(0.35), lineWidth: 1))
            )
        }
    }
}

// MARK: - RICH DATA grid (Eternal-Klok parity; NO timestamp)

private struct RichGrid: View {
    let klock: EternalKlock

    private func row(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key).font(.caption.monospaced()).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.monospaced()).foregroundStyle(.primary)
        }
        .padding(.vertical, 2)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            row("kaiPulseEternal", "\(klock.kaiPulseEternal)")
            row("kaiPulseToday", "\(klock.kaiPulseToday)")
            row("eternalKaiPulseToday", "\(klock.eternalKaiPulseToday)")
            row("kairos_seal_day_month", klock.kairos_seal_day_month)
            row("kairos_seal_day_month_percent", klock.kairos_seal_day_month_percent)
            row("chakraStepString", klock.chakraStepString)
            row("harmonicDay", klock.harmonicDay)
            row("weekIndex", "\(klock.weekIndex)")
            row("weekName", klock.weekName)
            row("dayOfMonth", "\(klock.dayOfMonth)")
            row("eternalMonthIndex", "\(klock.eternalMonthIndex)")
            row("eternalMonth", klock.eternalMonth)
            row("eternalChakraArc", klock.eternalChakraArc)
            row("eternalYearName", klock.eternalYearName)
            row("chakraStep", "stepIndex=\(klock.chakraStep.stepIndex) • percentIntoStep=\(String(format: "%.5f", klock.chakraStep.percentIntoStep)) • stepsPerBeat=\(klock.chakraStep.stepsPerBeat)")
            row("chakraBeat", "beatIndex=\(klock.chakraBeat.beatIndex) • pulsesIntoBeat=\(klock.chakraBeat.pulsesIntoBeat) • beatPulseCount=\(klock.chakraBeat.beatPulseCount) • totalBeats=\(klock.chakraBeat.totalBeats)")
            row("eternalChakraBeat", "beatIndex=\(klock.eternalChakraBeat.beatIndex) • pulsesIntoBeat=\(klock.eternalChakraBeat.pulsesIntoBeat) • percentToNext=\(String(format: "%.4f", klock.eternalChakraBeat.percentToNext))%")
            row("harmonicWeekProgress", "dayIndex=\(klock.harmonicWeekProgress.weekDayIndex) • pulsesIntoWeek=\(klock.harmonicWeekProgress.pulsesIntoWeek) • percent=\(String(format: "%.4f", klock.harmonicWeekProgress.percent))%")
            row("eternalMonthProgress", "daysElapsed=\(klock.eternalMonthProgress.daysElapsed) • daysRemaining=\(klock.eternalMonthProgress.daysRemaining) • percent=\(String(format: "%.4f", klock.eternalMonthProgress.percent))%")
            row("harmonicYearProgress", "daysElapsed=\(klock.harmonicYearProgress.daysElapsed) • daysRemaining=\(klock.harmonicYearProgress.daysRemaining) • percent=\(String(format: "%.4f", klock.harmonicYearProgress.percent))%")
            row("eternalSeal", klock.eternalSeal)
            row("kaiMomentSummary", klock.kaiMomentSummary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: [Color.white.opacity(0.05), Color.white.opacity(0.02)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.cyan.opacity(0.25), lineWidth: 1))
        )
    }
}

// MARK: - Stargate (Fullscreen Viewer)

private struct StargateView: View {
    var params: KaiSigilRenderParams
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 0.92

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            KaiSigilView(params: params, size: min(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * 0.9)
                .scaleEffect(scale)
                .onAppear { withAnimation(.easeInOut(duration: 0.8)) { scale = 1.0 } }
            VStack {
                HStack { Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 28, weight: .semibold))
                    }
                    .tint(.white).padding()
                }
                Spacer()
            }
        }
    }
}

// MARK: - Helpers / Extensions --------------------------------------------------

private extension Comparable { func clamped(_ a: Self, _ b: Self) -> Self { min(max(self, a), b) } }

private extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xff) / 255.0
        let g = Double((hex >> 8) & 0xff) / 255.0
        let b = Double(hex & 0xff) / 255.0
        self = Color(red: r, green: g, blue: b)
    }
}

// Share bridge
private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]?
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct ShareItem { let payload: Any }

// MARK: - Demo Entry ------------------------------------------------------------

struct KaiSigilDemo: View {
    var body: some View {
        NavigationStack {
            KaiSigilModalView()
                .navigationTitle("Kairos Sigil Viewer")
                .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

#Preview {
    KaiSigilDemo()
}

// MARK: - Int128 (tiny helper for a single rounded division) -------------------

fileprivate struct Int128: ExpressibleByIntegerLiteral {
    private var hi: Int64
    private var lo: UInt64

    init(integerLiteral value: IntegerLiteralType) { self.init(Int64(value)) }
    init(_ v: Int64) { self.hi = v < 0 ? -1 : 0; self.lo = UInt64(bitPattern: v) }
    init(_ v: Int) { self.init(Int64(v)) }

    static func + (lhs: Int128, rhs: Int) -> Int128 {
        var res = lhs
        let sum = res.lo &+ UInt64(rhs)
        if sum < res.lo { res.hi &+= 1 }
        res.lo = sum
        return res
    }

    static func / (lhs: Int128, rhs: Int) -> Int64 {
        precondition(rhs > 0)
        let dividendHi = UInt64(bitPattern: lhs.hi)
        let dividendLo = lhs.lo
        let divisor = UInt64(rhs)
        var rem: UInt64 = 0
        let parts = [dividendHi, dividendLo]
        var qHi: UInt64 = 0, qLo: UInt64 = 0
        for (i, part) in parts.enumerated() {
            let acc = (rem << 64) | part
            let q = acc / divisor
            rem = acc % divisor
            if i == 0 { qHi = q } else { qLo = q }
        }
        let combined = (qHi << 64) | qLo
        return Int64(bitPattern: combined)
    }
}
