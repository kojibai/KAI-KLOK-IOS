//  ContentView.swift
//  KaiKlok Watch App — Divine Interface v2.9.0
//  “Perpetual Pulse Orb (no stop at top) • Exact-Lock Sync via genesis+P
//   • Fibonacci-Locked Harmonic Chime (soft attack, natural fade)
//   • Pulse Haptics (20% • 50% → boundary BIG) • Beat-0 Accent (opt)
//   • Phase Cal • Chakra D/M/Y • Arc Numerals IN TICK ROW
//   • Center BB:SS • Max face fill • Filling Step Hand • Scrollable Mode Sheet
//   • Exact Boundary Scheduler (μ-jitter minimized; single source-of-truth)
//   • watchOS 10+ onChange deprecations resolved (two-parameter closures)”
//
//  2.9.0 (drop-in):
//  • Pulse Orb now uses continuous phase = fract((now - genesis)/P) — no boundary stick,
//    perfectly smooth perpetual motion while remaining boundary-locked.
//  • Replaced boundary “beep” with Fibonacci-tuned harmonic chime (soft attack + natural fade).
//    No forced stop; the chime rings out cleanly. Still scheduled EXACTLY at the boundary.
//  • No behavior change to lead-in haptics (20% / 50%) or BIG boundary haptic.
//
//  Notes:
//  • Requires: watchOS target with SwiftUI/Combine/AVFoundation/CoreMotion.
//  • Toolbar hidden on watchOS to avoid Chronos UI intrusion.
//

import SwiftUI
import Foundation
import WatchKit
import AVFoundation
import CoreMotion
import Combine

// MARK: - KKS (Kairos Klock Spec) — φ timing & math

private enum KKS {
    static let phi: Double = (1 + sqrt(5)) / 2
    static let kaiPulseSec: Double = 3 + sqrt(5)          // exact P ≈ 5.236067977…
    static let pulseMsExact: Double = kaiPulseSec * 1000.0

    // μpulse constants (exact; integer-safe)
    static let onePulseMicro: Int64 = 1_000_000
    static let nDayMicro: Int64 = 17_491_270_421          // exact μpulses/day
    static var muPerBeatExact: Int64 { (nDayMicro + 18) / 36 } // ties-to-even integral split
    static let pulsesPerStepMicro: Int64 = 11_000_000     // 11 pulses/step
    static let dayPulses: Double = 17_491.270_421

    // Genesis (UTC): 2024-05-10 06:45:41.888
    static let genesisUTC: Date = {
        var c = DateComponents()
        c.calendar = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)
        c.year = 2024; c.month = 5; c.day = 10
        c.hour = 6; c.minute = 45; c.second = 41; c.nanosecond = 888_000_000
        return c.date!
    }()

    // Safe rounding (banker's rounding)
    static func roundTiesToEven(_ x: Double) -> Int64 {
        guard x.isFinite else { return 0 }
        let s = x < 0 ? -1.0 : 1.0
        let ax = abs(x)
        let i = floor(ax)
        let f = ax - i
        if f < 0.5 { return Int64(s * i) }
        if f > 0.5 { return Int64(s * (i + 1)) }
        let ii = Int(i)
        return Int64(s * (ii.isMultiple(of: 2) ? i : (i + 1)))
    }

    static func floorDiv(_ n: Int64, _ d: Int64) -> Int64 {
        let q = n / d, r = n % d
        return (r != 0 && ((r > 0) != (d > 0))) ? (q - 1) : q
    }
    static func imod(_ n: Int64, _ m: Int64) -> Int64 {
        let r = n % m; return r >= 0 ? r : r + m
    }

    static func microPulsesSinceGenesis(_ now: Date) -> Int64 {
        let deltaSec = now.timeIntervalSince(genesisUTC)
        let pulses = deltaSec / kaiPulseSec
        let micro = pulses * 1_000_000.0
        return roundTiesToEven(micro)
    }

    static func wholePulsesSinceGenesis(_ now: Date) -> Int64 {
        let μ = Double(microPulsesSinceGenesis(now))
        return roundTiesToEven(μ / Double(onePulseMicro))
    }

    static func pad2(_ n: Int) -> String { String(format: "%02d", n) }
}

// MARK: - Fibonacci helpers (for harmonic custom Hz)

private func fibonacciNumbers(in range: ClosedRange<Int>) -> [Int] {
    var a = 1, b = 1
    var out: [Int] = []
    while b <= range.upperBound {
        if b >= range.lowerBound { out.append(b) }
        (a, b) = (b, a + b)
    }
    return Array(Set(out)).sorted()
}
private let FIB_HZ: [Int] = fibonacciNumbers(in: 110...1760) // e.g. [144, 233, 377, 610, 987, 1597]
private func nearestIndex(in arr: [Int], to value: Int) -> Int {
    guard !arr.isEmpty else { return 0 }
    var best = 0
    var bestDiff = abs(arr[0] - value)
    for i in arr.indices.dropFirst() {
        let d = abs(arr[i] - value)
        if d < bestDiff { best = i; bestDiff = d }
    }
    return best
}
private func nearestFib(to hz: Double) -> Int {
    let idx = nearestIndex(in: FIB_HZ, to: Int(hz.rounded()))
    return FIB_HZ[idx]
}

// MARK: - Domain

private enum DayName: String, CaseIterable, Codable { case Solhara, Aquaris, Flamora, Verdari, Sonari, Kaelith }

// Live arc (time-of-day)
private let ARC_NAMES_SHORT = ["Ignite","Integrate","Harmonize","Reflect","Purify","Dream"]
@inline(__always) private func arcIndex(forBeat beat: Int) -> Int { max(0, min(5, beat / 6)) }
@inline(__always) private func arcShortNameForBeat(_ beat: Int) -> String { ARC_NAMES_SHORT[arcIndex(forBeat: beat)] }

// Arc theming
private struct ArcTheme {
    let accent: Color
    let accentSoft: Color
    let track1: Color
    let track2: Color
    let bgTop: Color
    let bgMid: Color
    let bgBot: Color
}

private func kaiHex(_ hex: String, alpha: Double = 1.0) -> Color {
    var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.hasPrefix("#") { s.removeFirst() }
    var n: UInt64 = 0
    guard Scanner(string: s).scanHexInt64(&n) else { return .white.opacity(alpha) }
    let r, g, b: Double
    switch s.count {
    case 6:
        r = Double((n >> 16) & 0xff) / 255
        g = Double((n >>  8) & 0xff) / 255
        b = Double( n        & 0xff) / 255
        return Color(red: r, green: g, blue: b, opacity: alpha)
    case 8:
        let rr = Double((n >> 24) & 0xff) / 255
        let gg = Double((n >> 16) & 0xff) / 255
        let bb = Double((n >>  8) & 0xff) / 255
        let aa = Double( n        & 0xff) / 255
        return Color(red: rr, green: gg, blue: bb, opacity: min(1, max(0, alpha * aa)))
    default:
        return .white.opacity(alpha)
    }
}

private func themeForArc(_ idx: Int) -> ArcTheme {
    switch max(0, min(5, idx)) {
    case 0:
        return .init(
            accent: kaiHex("#FF4D4D"), accentSoft: kaiHex("#FF2626"),
            track1: kaiHex("#1A0C0C"), track2: kaiHex("#0C0606"),
            bgTop: kaiHex("#0B0305"), bgMid: kaiHex("#14070A"), bgBot: kaiHex("#1A0A0E")
        )
    case 1:
        return .init(
            accent: kaiHex("#FF964D"), accentSoft: kaiHex("#FF7A26"),
            track1: kaiHex("#1A120C"), track2: kaiHex("#0C0805"),
            bgTop: kaiHex("#0C0703"), bgMid: kaiHex("#160D07"), bgBot: kaiHex("#1B120C")
        )
    case 2:
        return .init(
            accent: kaiHex("#FFD84D"), accentSoft: kaiHex("#FFC226"),
            track1: kaiHex("#19190C"), track2: kaiHex("#0B0B05"),
            bgTop: kaiHex("#0A0903"), bgMid: kaiHex("#141306"), bgBot: kaiHex("#1A1A0C")
        )
    case 3:
        return .init(
            accent: kaiHex("#6BE28B"), accentSoft: kaiHex("#45D16D"),
            track1: kaiHex("#0C1A12"), track2: kaiHex("#06100A"),
            bgTop: kaiHex("#031008"), bgMid: kaiHex("#081A10"), bgBot: kaiHex("#0D2318")
        )
    case 4:
        return .init(
            accent: kaiHex("#4DA8FF"), accentSoft: kaiHex("#2C8EFF"),
            track1: kaiHex("#0C141A"), track2: kaiHex("#060B10"),
            bgTop: kaiHex("#05090F"), bgMid: kaiHex("#0E1B22"), bgBot: kaiHex("#0C2231")
        )
    default:
        return .init(
            accent: kaiHex("#B07CFF"), accentSoft: kaiHex("#9A5EFF"),
            track1: kaiHex("#150F1A"), track2: kaiHex("#0A0710"),
            bgTop: kaiHex("#0A0710"), bgMid: kaiHex("#130F1B"), bgBot: kaiHex("#1A1422")
        )
    }
}

// Chakra color mapping (6-color cycle)
@inline(__always) private func chakraColorIndex6(_ idx: Int) -> Color {
    switch idx {
    case 0: return kaiHex("#FF4D4D")
    case 1: return kaiHex("#FF964D")
    case 2: return kaiHex("#FFD84D")
    case 3: return kaiHex("#6BE28B")
    case 4: return kaiHex("#4DA8FF")
    default: return kaiHex("#B07CFF")
    }
}
@inline(__always) private func chakraColorForDay(_ dayOfMonth: Int) -> Color {
    let i = max(1, dayOfMonth); return chakraColorIndex6((i - 1) % 6)
}
@inline(__always) private func chakraColorForMonth(_ monthIndex1: Int) -> Color {
    let i = max(1, monthIndex1); return chakraColorIndex6((i - 1) % 6)
}

// Grouped integer formatting
private let groupedIntFormatter: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.groupingSeparator = ","
    f.locale = Locale(identifier: "en_US")
    return f
}()
private func formatGroupedInt(_ n: Int64) -> String {
    groupedIntFormatter.string(from: NSNumber(value: n)) ?? "\(n)"
}

// MARK: - Local Kai types

private struct LocalKai: Codable {
    let beat: Int               // 0..35
    let step: Int               // 0..43
    let stepFracInBeat: Double  // precise (step + fine)/44.0
    let wholePulsesIntoDay: Int
    let dayOfMonth: Int         // 1..42
    let monthIndex1: Int        // 1..8
    let yearIndex0: Int         // Y0-based
    let weekday: DayName
    let monthDayIndex: Int      // 0..41
    let sealText: String        // "beat:SS — D#/M#"
}

private func computeLocalKai(_ now: Date) -> LocalKai {
    let pμ_total  = KKS.microPulsesSinceGenesis(now)
    let pμ_in_day = KKS.imod(pμ_total, KKS.nDayMicro)
    let dayIndex  = KKS.floorDiv(pμ_total, KKS.nDayMicro)

    let beat = Int(KKS.floorDiv(pμ_in_day, KKS.muPerBeatExact))
    let pμ_in_beat = pμ_in_day - Int64(beat) * KKS.muPerBeatExact
    var step = Int(KKS.floorDiv(pμ_in_beat, KKS.pulsesPerStepMicro))
    step = min(max(step, 0), 43)

    let microIntoStep = max(0, pμ_in_beat - Int64(step) * KKS.pulsesPerStepMicro)
    let fineStep = Double(microIntoStep) / Double(KKS.pulsesPerStepMicro)
    let stepFracInBeat = (Double(step) + min(max(fineStep, 0.0), 1.0)) / 44.0

    let wholePulsesIntoDay = Int(KKS.floorDiv(pμ_in_day, KKS.onePulseMicro))

    let weekdayIdx = Int(KKS.imod(dayIndex, 6))
    let weekday = DayName.allCases[weekdayIdx]

    let dayIndexNum = Int(dayIndex)
    let dayOfMonth = ((dayIndexNum % 42) + 42) % 42 + 1
    let monthIndex0 = (dayIndexNum / 42) % 8
    let monthIndex1 = ((monthIndex0 + 8) % 8) + 1
    let yearIndex0 = (dayIndexNum / 336)
    let monthDayIndex = dayOfMonth - 1

    let seal = "\(beat):\(KKS.pad2(step)) — D\(dayOfMonth)/M\(monthIndex1)"
    return .init(
        beat: beat, step: step, stepFracInBeat: stepFracInBeat,
        wholePulsesIntoDay: wholePulsesIntoDay,
        dayOfMonth: dayOfMonth, monthIndex1: monthIndex1, yearIndex0: yearIndex0,
        weekday: weekday, monthDayIndex: monthDayIndex,
        sealText: seal
    )
}

private struct KaiMoment: Equatable, Codable {
    let date: Date
    let kai: LocalKai
    var stepIndexInDay: Int { kai.beat * 44 + kai.step }
    var totalStepsInDay: Int { 36 * 44 }
    var progressDay: Double { Double(stepIndexInDay) / Double(totalStepsInDay) }
    static func == (l: KaiMoment, r: KaiMoment) -> Bool {
        l.kai.beat == r.kai.beat && l.kai.step == r.kai.step &&
        l.kai.wholePulsesIntoDay == r.kai.wholePulsesIntoDay
    }
}

// MARK: - Exact Pulse Clock (single source-of-truth)

@MainActor
private final class PulseClock: ObservableObject {
    static let shared = PulseClock()
    @Published var moment: KaiMoment

    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "kai.pulse.clock", qos: .userInteractive)

    // Subscribers for boundary ticks (called immediately at boundary)
    private var subscribers: [(KaiMoment) -> Void] = []

    private init() {
        let now = Date()
        self.moment = KaiMoment(date: now, kai: computeLocalKai(now))
        scheduleAligned()
    }
    deinit { timer?.cancel() }

    func subscribe(_ fn: @escaping (KaiMoment) -> Void) {
        subscribers.append(fn)
    }

    private func scheduleAligned() {
        timer?.cancel(); timer = nil

        func scheduleNext() {
            let nowMs = Date().timeIntervalSince1970 * 1000.0
            let genesisMs = KKS.genesisUTC.timeIntervalSince1970 * 1000.0
            let elapsed = nowMs - genesisMs
            let periods = ceil(elapsed / KKS.pulseMsExact)
            let boundaryMs = genesisMs + periods * KKS.pulseMsExact
            let initialDelay = max(0, boundaryMs - nowMs) / 1000.0

            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now() + initialDelay, repeating: .never, leeway: .nanoseconds(0))
            t.setEventHandler { [weak self] in
                guard let self else { return }
                let now = Date()
                let newMoment = KaiMoment(date: now, kai: computeLocalKai(now))
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.moment = newMoment
                    for s in self.subscribers { s(newMoment) }
                    self.timer?.cancel()
                    self.timer = nil
                    scheduleNext() // schedule following boundary precisely
                }
            }
            self.timer = t
            t.resume()
        }
        scheduleNext()
    }
}

// MARK: - Motion (tilt for orbital sparkle)

@MainActor
private final class MotionManager: ObservableObject {
    static let shared = MotionManager()
    private let mgr = CMMotionManager()
    @Published var roll: Double = 0
    @Published var pitch: Double = 0

    private init() { mgr.deviceMotionUpdateInterval = 1.0 / 30.0 }

    func start() {
        guard mgr.isDeviceMotionAvailable, !mgr.isDeviceMotionActive else { return }
        mgr.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let d = data else { return }
            self?.roll  = max(-.pi/3, min(.pi/3, d.attitude.roll))
            self?.pitch = max(-.pi/3, min(.pi/3, d.attitude.pitch))
        }
    }
    func stop() {
        guard mgr.isDeviceMotionActive else { return }
        mgr.stopDeviceMotionUpdates()
    }
}

// MARK: - Harmonic Audio (device-time scheduled chime + optional continuous tone)

private enum HarmonicMode: String, CaseIterable {
    case relax = "Relax"   // ~396 Hz
    case focus = "Focus"   // ~528 Hz
    case root  = "Root"    // 432 Hz
    case custom = "Custom" // user-set (Fibonacci-locked)
}

@MainActor
private final class HarmonicAudioPulse: ObservableObject {
    static let shared = HarmonicAudioPulse()
    @Published var mode: HarmonicMode = .root
    @Published var isPlaying: Bool = false

    private var loopPlayer: AVAudioPlayer?   // continuous “Resonant Lock” tone
    private var chimeURL: URL?               // cached Fibonacci chime sample

    var isReady: Bool { loopPlayer != nil }
    var deviceTimeNow: TimeInterval { loopPlayer?.deviceCurrentTime ?? 0 }

    private func configureSession() {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? s.setActive(true, options: [])
    }

    // Base frequency per mode (then snapped for chime generation)
    private func baseFreqForMode(_ mode: HarmonicMode, customHz: Double?) -> Double {
        switch mode {
        case .relax:  return 396
        case .focus:  return 528
        case .root:   return 432
        case .custom: return Double(nearestFib(to: customHz ?? 432))
        }
    }

    // Build a soft-attack, natural-decay Fibonacci chime as CAF (mono 44.1k)
    private func ensureChimeFileURL(frequency f0: Double, seconds: Double = 1.35) -> URL? {
        let root = nearestFib(to: f0)
        let idx  = max(0, min(FIB_HZ.count - 1, nearestIndex(in: FIB_HZ, to: root)))
        let f1   = FIB_HZ[idx]
        let f2   = FIB_HZ[min(FIB_HZ.count - 1, idx + 1)]
        let f3   = FIB_HZ[max(0, idx - 1)]

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("kai_chime_\(f1)_\(f2)_\(f3).caf")
        if FileManager.default.fileExists(atPath: url.path) { return url }

        let sr: Double = 44_100
        let frames = Int(seconds * sr)
        let format = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)!
        guard let file = try? AVAudioFile(forWriting: url, settings: format.settings) else { return nil }
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        let x = buffer.floatChannelData![0]

        // Envelope: ~8ms attack, ~220ms fast decay, then smooth tail to 0 by end
        let att = 0.008, d1 = 0.22
        let tailTau = 0.60  // seconds for exp tail
        for n in 0..<frames {
            let t = Double(n) / sr
            // soft attack
            let aEnv = min(1.0, t / att)
            // two-stage decay: fast dip then long tail
            let dEnv = (t < d1) ? (1.0 - 0.25 * (t / d1)) : (0.75 * exp(-(t - d1)/tailTau))
            let env  = Float(aEnv * dEnv)

            // Harmonic partials locked to Fibonacci neighbors
            let s1 = sin(2.0 * .pi * Double(f1) * t)
            let s2 = sin(2.0 * .pi * Double(f2) * t)
            let s3 = sin(2.0 * .pi * Double(f3) * t)

            // Slight breath wobble (very low depth) to feel organic, not chorusy
            let wob = 0.02 * sin(2.0 * .pi * (1.0 / KKS.kaiPulseSec) * t)
            let mix = (1.00 * s1) + (0.55 * s2) + (0.42 * s3)
            x[n] = env * Float((1.0 + wob) * 0.45 * mix)
        }
        do { try file.write(from: buffer); return url } catch { return nil }
    }

    // Prepare continuous loop tone for Resonant Lock and provide a device timebase
    func prepare(mode: HarmonicMode, customHz: Double? = nil) {
        configureSession()
        let f = baseFreqForMode(mode, customHz: customHz)
        // Looping pad (gentle breath AM) for Resonant Lock
        let url = ensureLoopToneURL(frequency: f) // see helper below
        guard let url else { return }
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.numberOfLoops = -1
            p.volume = 0.0          // keep silent until play()
            p.prepareToPlay()
            self.loopPlayer = p
            // Prebuild a chime sample matching the current mode
            self.chimeURL = ensureChimeFileURL(frequency: f)
        } catch {
            self.loopPlayer = nil
            self.chimeURL = nil
        }
    }

    // Gentle loop tone with breath AM (used only when user enables Resonant Lock)
    private func ensureLoopToneURL(frequency: Double, seconds: Double = 12.0) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("kai_lock_\(Int(frequency)).caf")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let sr: Double = 44_100
        let frames = Int(seconds * sr)
        let format = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)!
        guard let file = try? AVAudioFile(forWriting: url, settings: format.settings) else { return nil }
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        let ptr = buffer.floatChannelData![0]
        let breathHz = 1.0 / KKS.kaiPulseSec
        for n in 0..<frames {
            let t = Double(n) / sr
            let car = sin(2.0 * .pi * frequency * t)
            let env = Float(0.65 + 0.30 * sin(2.0 * .pi * breathHz * t))
            ptr[n] = env * Float(car) * 0.25
        }
        do { try file.write(from: buffer); return url } catch { return nil }
    }

    func play() {
        guard let p = loopPlayer else { return }
        p.volume = 0.8
        p.play(); isPlaying = true
    }

    func stop() {
        guard let p = loopPlayer else { return }
        p.stop(); p.currentTime = 0; isPlaying = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Schedule a Fibonacci-tuned chime at a wall-clock Date using a stable device timebase.
    func scheduleHarmonicChime(atWallClock target: Date) {
        // Ensure we have a device timebase; prepare if needed (silent loop player is fine).
        if loopPlayer == nil { prepare(mode: mode) }
        guard let timebase = loopPlayer?.deviceCurrentTime else { return }

        // Ensure chime sample exists for the current mode
        if chimeURL == nil {
            let f = baseFreqForMode(mode, customHz: nil)
            chimeURL = ensureChimeFileURL(frequency: f)
        }
        guard let url = chimeURL else { return }

        // A transient player just for the chime (so loop tone isn’t interrupted)
        guard let chime = try? AVAudioPlayer(contentsOf: url) else { return }
        chime.numberOfLoops = 0
        chime.volume = 1.0
        chime.prepareToPlay()

        // Schedule precisely
        let now = Date()
        let delta = max(0.010, target.timeIntervalSince(now))
        let fireDeviceTime = timebase + delta
        chime.play(atTime: fireDeviceTime)
        // No forced stop; the chime file encodes the fade-out tail naturally.
    }
}

// MARK: - Haptic + Audio Coordinator (anchored to PulseClock)

@MainActor
private final class HapticAudioCoordinator {
    static let shared = HapticAudioCoordinator()

    var pulseHapticsEnabled: Bool = true
    var accentBeatEnabled: Bool = true
    var phaseOffset: Double = 0.0 // 0..1
    var audioMode: HarmonicMode = .root
    var customHz: Double = 432

    private let audio = HarmonicAudioPulse.shared

    private init() {
        audio.prepare(mode: audioMode, customHz: customHz)
    }

    private func shiftedFraction(_ frac: Double) -> Double {
        let f = frac + (phaseOffset - floor(phaseOffset))
        return f - floor(f) // wrap to [0,1)
    }

    /// Called by ContentView at each pulse boundary (EXACT).
    func handleBoundary(moment: KaiMoment) {
        guard pulseHapticsEnabled else { return }

        let P = KKS.kaiPulseSec

        // 🔔 BIG boundary hit: big haptic + *harmonic chime* EXACTLY on the boundary
        WKInterfaceDevice.current().play(.success)
        audio.scheduleHarmonicChime(atWallClock: moment.date)

        // 🌊 Inside-pulse “lead-in” haptics for NEXT boundary (light, breath-like)
        let d1 = shiftedFraction(0.20) * P
        let d2 = shiftedFraction(0.50) * P

        DispatchQueue.main.asyncAfter(deadline: .now() + d1) {
            if self.pulseHapticsEnabled { WKInterfaceDevice.current().play(.click) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + d2) {
            if self.pulseHapticsEnabled { WKInterfaceDevice.current().play(.directionUp) }
        }

        if accentBeatEnabled && moment.kai.step == 0 {
            // Optional light accent; visuals/affirmations handle the rest.
        }
    }
}

// MARK: - KaiTime Affirmations (watch-safe TTS + gentle fade)

@MainActor
private final class AffirmationCenter: ObservableObject {
    static let shared = AffirmationCenter()
    @Published var current: String? = nil
    @Published var whisperEnabled: Bool = false

    private let phrases = [
        NSLocalizedString("You are on time.", comment: "Affirmation"),
        NSLocalizedString("Let your seal guide you.", comment: "Affirmation"),
        NSLocalizedString("Breath aligns all.", comment: "Affirmation"),
        NSLocalizedString("Coherence returns.", comment: "Affirmation"),
        NSLocalizedString("Move with the Kai.", comment: "Affirmation")
    ]

    #if os(watchOS)
    private let synth: AVSpeechSynthesizer? = {
        if #available(watchOS 9.0, *) { return AVSpeechSynthesizer() }
        return nil
    }()
    #else
    private let synth = AVSpeechSynthesizer()
    #endif

    func trigger(beat: Int, step: Int) {
        guard step == 0 else { return }
        let idx = (beat % max(1, phrases.count))
        let text = phrases[idx]
        withAnimation(.easeInOut(duration: 2.6)) { current = text }
        if whisperEnabled {
            #if os(watchOS)
            if let s = synth {
                let utt = AVSpeechUtterance(string: text)
                utt.rate = 0.45; utt.pitchMultiplier = 0.9; utt.volume = 0.55
                s.speak(utt)
            } else {
                WKInterfaceDevice.current().play(.notification)
            }
            #else
            let utt = AVSpeechUtterance(string: text)
            utt.rate = 0.45; utt.pitchMultiplier = 0.9; utt.volume = 0.55
            synth.speak(utt)
            #endif
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { [weak self] in
            withAnimation(.easeInOut(duration: 2.6)) {
                if self?.current == text { self?.current = nil }
            }
        }
    }
}

// MARK: - Small reusable views (IconButton / DMY / Pills)

private struct IconButton: View {
    let systemName: String
    let action: () -> Void
    let size: CGFloat = 28
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .bold))
                .frame(width: size, height: size)
                .background(kaiHex("#06121a").opacity(0.75), in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
    }
}

private struct DMYText: View {
    let day: Int
    let month: Int
    let year: Int
    var body: some View {
        HStack(spacing: 0) {
            Text("D").foregroundStyle(.white)
            Text("\(day)").foregroundStyle(chakraColorForDay(day))
            Text("/M").foregroundStyle(.white)
            Text("\(month)").foregroundStyle(chakraColorForMonth(month))
            Text("/Y\(year)").foregroundStyle(.white)
        }
    }
}

private struct InfoPill: View {
    let text: String
    let accent: Color
    var size: CGFloat = 1.0
    var body: some View {
        let baseFont: CGFloat = 13, hPad: CGFloat = 10, vPad: CGFloat = 5
        Text(text)
            .font(.system(size: baseFont * size, weight: .regular, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, hPad * size)
            .padding(.vertical, vPad * size)
            .background(
                LinearGradient(colors: [accent.opacity(0.26), kaiHex("#0a1b24").opacity(0.66)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: Capsule()
            )
            .overlay(Capsule().stroke(accent.opacity(0.45), lineWidth: max(1 as CGFloat, 1 * size)))
    }
}

private struct InfoPillRich<Content: View>: View {
    let accent: Color
    var size: CGFloat = 1.0
    let content: Content
    init(accent: Color, size: CGFloat = 1.0, @ViewBuilder content: () -> Content) {
        self.accent = accent; self.size = size; self.content = content()
    }
    var body: some View {
        let baseFont: CGFloat = 13, hPad: CGFloat = 10, vPad: CGFloat = 5
        content
            .font(.system(size: baseFont * size, weight: .regular, design: .monospaced))
            .padding(.horizontal, hPad * size)
            .padding(.vertical, vPad * size)
            .background(
                LinearGradient(colors: [accent.opacity(0.26), kaiHex("#0a1b24").opacity(0.66)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: Capsule()
            )
            .overlay(Capsule().stroke(accent.opacity(0.45), lineWidth: max(1 as CGFloat, 1 * size)))
    }
}

// MARK: - ContentView

struct ContentView: View {
    @StateObject private var clock  = PulseClock.shared
    @StateObject private var motion = MotionManager.shared
    @StateObject private var audio  = HarmonicAudioPulse.shared
    @StateObject private var affirm = AffirmationCenter.shared

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage("didShowKaiWatchTips") private var didShowTips: Bool = false
    @AppStorage("audioMode") private var storedAudioMode: String = HarmonicMode.root.rawValue
    @AppStorage("customHz") private var storedCustomHz: Double = 432
    @AppStorage("pulseHapticsEnabled") private var pulseHapticsEnabled: Bool = true
    @AppStorage("accentBeatEnabled")   private var accentBeatEnabled: Bool = true
    @AppStorage("affirmWhisperEnabled") private var storedWhisperEnabled: Bool = false
    @AppStorage("phaseOffset") private var phaseOffset: Double = 0.0 // 0..1

    @State private var showTips = false
    @State private var showWeekModal = false
    @State private var showModeSheet = false

    @State private var isScrubbing = false
    @State private var crown: Double = 0
    @State private var previewMoment: KaiMoment? = nil
    @State private var lastHapticBeatIndex: Int = -1
    @State private var resonantLocked = false
    @State private var isSigilOverlay = false

    @State private var showBreathGuide = false
    @State private var guidePulse = 0

    private let breath: Double = KKS.kaiPulseSec

    private var currentMoment: KaiMoment { previewMoment ?? clock.moment }
    private var currentArcIndex: Int { arcIndex(forBeat: currentMoment.kai.beat) }
    private var theme: ArcTheme { themeForArc(currentArcIndex) }

    private var arcPillText: String { arcShortNameForBeat(currentMoment.kai.beat) }
    private var pulsePillText: String {
        let P = KKS.wholePulsesSinceGenesis(currentMoment.date)
        return "P\(formatGroupedInt(P))"
    }

    private var a11yLabel: String {
        "\(currentMoment.kai.sealText), \(currentMoment.kai.weekday.rawValue), \(arcShortNameForBeat(currentMoment.kai.beat)) arc, D\(currentMoment.kai.dayOfMonth)/M\(currentMoment.kai.monthIndex1)/Y\(currentMoment.kai.yearIndex0), \(pulsePillText)"
    }

    var body: some View {
        ZStack {
            AtlanteanBackgroundWatch(breath: breath, reduceMotion: reduceMotion, theme: theme)
                .accessibilityHidden(true)

            GeometryReader { geo in
                let side   = min(geo.size.width, geo.size.height)
                let dialSz = side * 0.995

                VStack(spacing: 4) {
                    DialAreaView(
                        moment: currentMoment,
                        breath: breath,
                        dialSize: dialSz,
                        theme: theme,
                        reduceMotion: reduceMotion,
                        roll: motion.roll,
                        pitch: motion.pitch,
                        isSigilOverlay: isSigilOverlay,
                        onDoubleTap: { withAnimation(.easeInOut(duration: 0.25)) { isSigilOverlay.toggle() } },
                        onLongPress: { captureSeal() }
                    )

                    PillsAreaView(
                        arcText: arcPillText,
                        d: currentMoment.kai.dayOfMonth,
                        m: currentMoment.kai.monthIndex1,
                        y: currentMoment.kai.yearIndex0,
                        pulseText: pulsePillText,
                        accent: theme.accent
                    )

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            CornerControlsView(
                topLeft: { showWeekModal = true },
                topRight: { showModeSheet = true },
                bottomLeft: { toggleScrub() },
                bottomRight: { toggleResonantLock() }
            )
            .zIndex(10)

            AffirmationOverlay(phrase: affirm.current, accent: theme.accent)

            if showTips {
                TipsOverlay(onDismiss: {
                    withAnimation(.easeInOut(duration: 0.3)) { showTips = false; didShowTips = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + breath * 2.0) {
                        withAnimation(.easeInOut(duration: 0.3)) { showTips = false; didShowTips = true }
                        self.startBreathGuide()
                    }
                })
                .zIndex(20)
            }

            if showBreathGuide {
                BreathGuideOverlay(pulseIndex: guidePulse, onDismiss: { showBreathGuide = false })
                    .zIndex(30)
            }
        }
        .setupLifecycle(
            onAppear: onAppearSetup,
            onDisappear: { motion.stop() }
        )
        .syncSettingsToCoordinator(
            audio: audio,
            affirm: affirm,
            pulseHapticsEnabled: $pulseHapticsEnabled,
            accentBeatEnabled: $accentBeatEnabled,
            storedWhisperEnabled: $storedWhisperEnabled,
            storedAudioMode: $storedAudioMode,
            storedCustomHz: $storedCustomHz,
            phaseOffset: $phaseOffset
        )
        .scrubSupport(
            isScrubbing: $isScrubbing,
            crown: $crown,
            momentProvider: { clock.moment },
            onPreview: { pm in previewMoment = pm },
            onBeatTick: { idx in
                if idx != lastHapticBeatIndex {
                    lastHapticBeatIndex = idx
                    WKInterfaceDevice.current().play(.click)
                }
            },
            onStop: {
                previewMoment = nil
                crown = 0
                lastHapticBeatIndex = -1
            }
        )
        .animation(.linear(duration: 0.20), value: clock.moment.kai.wholePulsesIntoDay)
        .sheet(isPresented: $showWeekModal) {
            WeekKalendarWatchSheet()
        }
        .sheet(isPresented: $showModeSheet) {
            ModeSheet(
                mode: $audio.mode,
                customHz: $storedCustomHz,
                pulseHapticsEnabled: $pulseHapticsEnabled,
                accentBeatEnabled: $accentBeatEnabled,
                whisperEnabled: $storedWhisperEnabled,
                phaseOffset: $phaseOffset
            ) {
                storedCustomHz = Double(nearestFib(to: storedCustomHz))
                HapticAudioCoordinator.shared.audioMode = audio.mode
                HapticAudioCoordinator.shared.customHz = storedCustomHz
                audio.prepare(mode: audio.mode, customHz: storedCustomHz)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11yLabel)
        .accessibilityHint(isScrubbing
                           ? NSLocalizedString("Turn Digital Crown to preview; double-tap toggles overlay; long-press saves a sealed moment.", comment: "")
                           : NSLocalizedString("Double-tap toggles overlay; long-press saves a sealed moment.", comment: ""))
        #if os(watchOS)
        .toolbar(.hidden)
        #endif
        .onReceiveBoundary { moment in
            HapticAudioCoordinator.shared.handleBoundary(moment: moment)
            handleMomentChange(moment)
        }
    }

    // MARK: - Lifecycle & moment handlers

    private func onAppearSetup() {
        // Wire coordinator to settings
        let coord = HapticAudioCoordinator.shared
        coord.pulseHapticsEnabled = pulseHapticsEnabled
        coord.accentBeatEnabled   = accentBeatEnabled
        coord.phaseOffset         = phaseOffset
        coord.audioMode           = HarmonicMode(rawValue: storedAudioMode) ?? .root
        coord.customHz            = storedCustomHz

        audio.mode = coord.audioMode
        if !audio.isReady { audio.prepare(mode: audio.mode, customHz: storedCustomHz) }

        affirm.whisperEnabled = storedWhisperEnabled
        motion.start()

        if !didShowTips {
            showTips = true
            DispatchQueue.main.asyncAfter(deadline: .now() + breath * 2.0) {
                withAnimation(.easeInOut(duration: 0.3)) { showTips = false; didShowTips = true }
                self.startBreathGuide()
            }
        }
    }

    private func handleMomentChange(_ newVal: KaiMoment) {
        affirm.trigger(beat: newVal.kai.beat, step: newVal.kai.step)
        if !isScrubbing { previewMoment = nil }
    }

    private func toggleScrub() {
        isScrubbing.toggle()
        if !isScrubbing {
            previewMoment = nil
            crown = 0
            lastHapticBeatIndex = -1
        }
        WKInterfaceDevice.current().play(isScrubbing ? .start : .stop)
    }

    private func toggleResonantLock() {
        resonantLocked.toggle()
        if resonantLocked {
            if !audio.isReady { audio.prepare(mode: audio.mode, customHz: storedCustomHz) }
            audio.play()
            WKInterfaceDevice.current().play(.directionUp)
        } else {
            audio.stop()
        }
    }

    private func scrubbedMoment(deltaBeats: Double, from live: KaiMoment) -> KaiMoment {
        let pulsesPerBeat = Double(KKS.muPerBeatExact) / Double(KKS.onePulseMicro)
        let targetDate = Date(timeInterval: (deltaBeats * pulsesPerBeat) * KKS.kaiPulseSec, since: live.date)
        return KaiMoment(date: targetDate, kai: computeLocalKai(targetDate))
    }

    // 3-pulse guide
    private func startBreathGuide() {
        showBreathGuide = true
        guidePulse = 0

        func tick(_ i: Int) {
            guard showBreathGuide else { return }
            guidePulse = i
            if i < 2 {
                DispatchQueue.main.asyncAfter(deadline: .now() + breath) {
                    tick(i + 1)
                }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + breath * 0.75) {
                    withAnimation(.easeInOut(duration: 0.25)) { showBreathGuide = false }
                }
            }
        }
        tick(0)
    }

    // Long-press capture to JSON
    private func captureSeal() {
        let stamp = clock.moment
        struct SealCapture: Codable {
            let moment: KaiMoment
            let pulseMicro: Int64
            let mode: String
        }
        let payload = SealCapture(moment: stamp, pulseMicro: KKS.microPulsesSinceGenesis(stamp.date), mode: audio.mode.rawValue)
        do {
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let url = dir.appendingPathComponent("seal_\(payload.pulseMicro).session.φ.json")
            let data = try JSONEncoder().encode(payload)
            try data.write(to: url, options: .atomic)
            WKInterfaceDevice.current().play(.success)
        } catch {
            WKInterfaceDevice.current().play(.failure)
        }
    }
}

#Preview("KaiKlok (watchOS)") { ContentView() }

// MARK: - Corner Controls Overlay

private struct CornerControlsView: View {
    let topLeft: () -> Void
    let topRight: () -> Void
    let bottomLeft: () -> Void
    let bottomRight: () -> Void

    var body: some View {
        GeometryReader { _ in
            ZStack {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        IconButton(systemName: "calendar", action: topLeft)
                            .padding(.top, -2).padding(.leading, -2)
                        Spacer(minLength: 0)
                        IconButton(systemName: "waveform", action: topRight)
                            .padding(.top, -2).padding(.trailing, -2)
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 0) {
                        IconButton(systemName: "viewfinder", action: bottomLeft)
                            .padding(.bottom, -2).padding(.leading, -2)
                        Spacer(minLength: 0)
                        IconButton(systemName: "lock", action: bottomRight)
                            .padding(.bottom, -2).padding(.trailing, -2)
                    }
                }
            }
        }
        .allowsHitTesting(true)
    }
}

// MARK: - Dial Area

private struct DialAreaView: View {
    let moment: KaiMoment
    let breath: Double
    let dialSize: CGFloat
    let theme: ArcTheme
    let reduceMotion: Bool
    let roll: Double
    let pitch: Double
    let isSigilOverlay: Bool
    let onDoubleTap: () -> Void
    let onLongPress: () -> Void

    var body: some View {
        ZStack {
            KaiDialView(moment: moment, breath: breath, glowSize: dialSize, theme: theme)
                .frame(width: dialSize, height: dialSize)
                .accessibilityHidden(true)

            // Background pulse/halo below the moving orb
            ChakraPulseOverlay(moment: moment, theme: theme, breath: breath, reduceMotion: reduceMotion)
                .allowsHitTesting(false)

            HarmonicSpark(moment: moment, roll: roll, pitch: pitch, reduceMotion: reduceMotion, theme: theme)
                .allowsHitTesting(false)

            // ⭐ Perpetual Pulse Orb (continuous phase from genesis)
            PulseOrbOverlay(
                moment: moment,
                dialSize: dialSize,
                theme: theme,
                reduceMotion: reduceMotion
            )
            .frame(width: dialSize, height: dialSize)
            .clipShape(Circle())
            .contentShape(Circle())
            .allowsHitTesting(false)
            .zIndex(5)

            if isSigilOverlay {
                SigilOverlay(moment: moment)
                    .id(moment.kai.wholePulsesIntoDay)
                    .transition(.scale.combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.18), value: moment.kai.wholePulsesIntoDay)
                    .allowsHitTesting(false)
            }

            CenterBeatStepLabel(beats: moment.kai.beat, step: moment.kai.step, accent: theme.accent)

            // Gesture target restricted to circle — NO single tap
            GestureRingPad(size: dialSize, onDoubleTap: onDoubleTap, onLongPress: onLongPress)
        }
    }
}

private struct CenterBeatStepLabel: View {
    let beats: Int
    let step: Int
    let accent: Color
    var body: some View {
        let bbss = "\(KKS.pad2(beats)):\(KKS.pad2(step))"
        Text(bbss)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(kaiHex("#0a1b24").opacity(0.65), in: Capsule())
            .overlay(Capsule().stroke(accent.opacity(0.35), lineWidth: 1))
            .allowsHitTesting(false)
    }
}

private struct GestureRingPad: View {
    let size: CGFloat
    let onDoubleTap: () -> Void
    let onLongPress: () -> Void
    var body: some View {
        Color.clear
            .frame(width: size, height: size)
            .clipShape(Circle())
            .contentShape(Circle())
            .highPriorityGesture(TapGesture(count: 2).onEnded { onDoubleTap() })
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.6).onEnded { _ in onLongPress() })
    }
}

// MARK: - Pills

private struct PillsAreaView: View {
    let arcText: String
    let d: Int
    let m: Int
    let y: Int
    let pulseText: String
    let accent: Color
    var body: some View {
        VStack(spacing: 6) {
            InfoPill(text: arcText, accent: accent, size: 0.8)
            HStack(spacing: 8) {
                InfoPillRich(accent: accent) {
                    DMYText(day: d, month: m, year: y).foregroundStyle(.white)
                }
                InfoPill(text: pulseText, accent: accent)
            }
        }
        .padding(.top, 0)
    }
}

// MARK: - Kai Dial (hero view)

private struct KaiDialView: View {
    let moment: KaiMoment
    let breath: Double
    let glowSize: CGFloat
    let theme: ArcTheme
    @State private var breathe = false

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(colors: [theme.accentSoft.opacity(breathe ? 0.26 : 0.14), .clear],
                                   center: .center, startRadius: 0, endRadius: glowSize)
                )
                .blur(radius: 18)
                .allowsHitTesting(false)

            Canvas { ctx, size in
                let W = size.width, H = size.height
                let C = CGPoint(x: W/2, y: H/2)
                let R = min(W, H) * 0.46

                drawTrack(ctx: &ctx, center: C, r: R, width: 10,
                          color1: theme.track1, color2: theme.track2)

                // Major ticks — skip where numerals render (0,6,12,18,24,30)
                let majorTickLength: CGFloat = 12
                let skip = Set([0, 6, 12, 18, 24, 30])
                drawTicks(ctx: &ctx, center: C, r: R, count: 36,
                          majorLength: majorTickLength, color: Color.white.opacity(0.24),
                          width: 2, skipIndices: skip)

                // Day step ring
                drawDayStepRing(ctx: &ctx, center: C, r: R - 12,
                                totalSteps: moment.totalStepsInDay,
                                completedSteps: moment.stepIndexInDay,
                                colorOn: theme.accent.opacity(0.75),
                                colorOff: Color.white.opacity(0.10))

                // Beat:step progress wedge
                drawBeatStepProgress(ctx: &ctx, center: C, r: R - 18,
                                     beatIndex: moment.kai.beat,
                                     stepFracInBeat: moment.kai.stepFracInBeat,
                                     color: theme.accent)

                // Filling Step Hand
                drawStepHand(ctx: &ctx, center: C, r: R - 4,
                             beatProgressDay: moment.progressDay,
                             stepFill: moment.kai.stepFracInBeat,
                             trackColor: Color.white.opacity(0.28),
                             fillColor: theme.accent)

                // Arc numerals on the tick row
                drawArcNumeralsOnTickRow(ctx: &ctx, center: C, baseRadius: R,
                                         fontSize: 11, majorTickLength: majorTickLength)
            }
            .compositingGroup()

            GeometryReader { geo in
                let W = geo.size.width
                let H = geo.size.height

                DMYText(day: moment.kai.dayOfMonth, month: moment.kai.monthIndex1, year: moment.kai.yearIndex0)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(kaiHex("#0a1b24").opacity(0.65), in: Capsule())
                    .overlay(Capsule().stroke(theme.accent.opacity(0.35), lineWidth: 1))
                    .position(x: W/2, y: H * 0.32)
                    .allowsHitTesting(false)

                let P = KKS.wholePulsesSinceGenesis(moment.date)
                let pulse = "P\(formatGroupedInt(P))"
                Text(pulse)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.95))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(kaiHex("#0a1b24").opacity(0.65), in: Capsule())
                    .overlay(Capsule().stroke(theme.accent.opacity(0.35), lineWidth: 1))
                    .position(x: W/2, y: H * 0.70)
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: breath).repeatForever(autoreverses: true)) { breathe = true }
        }
        .onDisappear { breathe = false }
    }

    private func drawTrack(ctx: inout GraphicsContext, center: CGPoint, r: CGFloat, width: CGFloat, color1: Color, color2: Color) {
        var p = Path()
        p.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r*2, height: r*2))
        ctx.stroke(p, with: .linearGradient(Gradient(colors: [color1, color2]),
                                            startPoint: CGPoint(x: center.x - r, y: center.y - r),
                                            endPoint: CGPoint(x: center.x + r, y: center.y + r)),
                   lineWidth: width)
    }

    private func drawTicks(ctx: inout GraphicsContext, center: CGPoint, r: CGFloat, count: Int, majorLength: CGFloat, color: Color, width: CGFloat, skipIndices: Set<Int> = []) {
        let base = -Double.pi/2
        for i in 0..<count where !skipIndices.contains(i) {
            let t = Double(i) / Double(count)
            let a = base + t * 2 * Double.pi
            let cosA = cos(a), sinA = sin(a)
            let p0 = CGPoint(x: center.x + cosA * (r - majorLength), y: center.y + sinA * (r - majorLength))
            let p1 = CGPoint(x: center.x + cosA * (r), y: center.y + sinA * (r))
            var tick = Path(); tick.move(to: p0); tick.addLine(to: p1)
            ctx.stroke(tick, with: .color(color), lineWidth: width)
        }
    }

    private func drawDayStepRing(ctx: inout GraphicsContext, center: CGPoint, r: CGFloat, totalSteps: Int, completedSteps: Int, colorOn: Color, colorOff: Color) {
        var bg = Path()
        bg.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r*2, height: r*2))
        ctx.stroke(bg, with: .color(colorOff), lineWidth: 4)

        let start = -Double.pi/2
        let end = start + Double(completedSteps) / Double(totalSteps) * 2 * Double.pi
        var arc = Path()
        arc.addArc(center: center, radius: r, startAngle: .radians(start), endAngle: .radians(end), clockwise: false)
        ctx.stroke(arc, with: .color(colorOn), lineWidth: 5)
    }

    private func drawBeatStepProgress(ctx: inout GraphicsContext, center: CGPoint, r: CGFloat, beatIndex: Int, stepFracInBeat: Double, color: Color) {
        let startBeat = -Double.pi/2 + (Double(beatIndex) / 36.0) * 2 * Double.pi
        let end = startBeat + stepFracInBeat * (2 * Double.pi / 36.0)
        var arc = Path()
        arc.addArc(center: center, radius: r, startAngle: .radians(startBeat), endAngle: .radians(end), clockwise: false)
        ctx.stroke(arc, with: .color(color), lineWidth: 6)
    }

    private func drawStepHand(ctx: inout GraphicsContext, center: CGPoint, r: CGFloat, beatProgressDay: Double, stepFill: Double, trackColor: Color, fillColor: Color) {
        let angle = -Double.pi/2 + beatProgressDay * 2 * Double.pi
        let rTrack = r
        let rFill  = rTrack * CGFloat(max(0.0, min(1.0, stepFill)))
        let lineW: CGFloat = 7.0

        let ux = CGFloat(cos(angle)), uy = CGFloat(sin(angle))

        // Track
        let tipTrack = CGPoint(x: center.x + ux * rTrack, y: center.y + uy * rTrack)
        var track = Path(); track.move(to: center); track.addLine(to: tipTrack)
        ctx.stroke(track, with: .color(trackColor), style: StrokeStyle(lineWidth: lineW, lineCap: .round))

        // Fill
        if rFill > 0 {
            let tipFill = CGPoint(x: center.x + ux * rFill, y: center.y + uy * rFill)
            var fill = Path(); fill.move(to: center); fill.addLine(to: tipFill)
            ctx.stroke(fill, with: .color(fillColor), style: StrokeStyle(lineWidth: lineW, lineCap: .round))
        }

        // Center cap
        let capR: CGFloat = 6
        ctx.fill(Path(ellipseIn: CGRect(x: center.x - capR, y: center.y - capR, width: capR*2, height: capR*2)),
                 with: .color(fillColor.opacity(0.9)))
    }

    private func drawArcNumeralsOnTickRow(ctx: inout GraphicsContext, center: CGPoint, baseRadius: CGFloat, fontSize: CGFloat, majorTickLength: CGFloat) {
        let labelR = baseRadius - (majorTickLength / 2.0)
        let baseAngle = -Double.pi / 2
        let starts = [0, 6, 12, 18, 24, 30]
        for startBeat in starts {
            let t = Double(startBeat) / 36.0
            let ang = baseAngle + t * 2 * Double.pi
            let x = center.x + CGFloat(cos(ang)) * labelR
            let y = center.y + CGFloat(sin(ang)) * labelR
            let arcIdx = max(0, min(5, startBeat / 6))
            let arcTheme = themeForArc(arcIdx)
            ctx.addFilter(.shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 0))
            let label = Text("\(startBeat)")
                .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                .foregroundColor(arcTheme.accent)
            ctx.draw(label, at: CGPoint(x: x, y: y), anchor: .center)
            ctx.addFilter(.shadow(color: .clear, radius: 0))
        }
    }
}

// MARK: - Perpetual Boundary-Locked Pulse Orb (no pause at top)

private struct PulseOrbOverlay: View {
    let moment: KaiMoment
    let dialSize: CGFloat
    let theme: ArcTheme
    let reduceMotion: Bool

    // No lastBoundary; compute continuous phase from exact genesis + P
    private func continuousPhase(at t: Date) -> Double {
        let elapsed = t.timeIntervalSince(KKS.genesisUTC) / KKS.kaiPulseSec
        return elapsed - floor(elapsed) // fract in [0,1)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0/60.0)) { ctx in
            let now = ctx.date
            let phase = continuousPhase(at: now)                     // 0..1 within pulse, continuous
            let R = dialSize * 0.46
            let ringR = max(0, R - 12.0 - 2.0)                       // slightly inset from day-step ring
            let breathe = reduceMotion ? 1.0 : (0.985 + 0.015 * sin(phase * 2 * .pi))
            let r = ringR * breathe
            let angle = -Double.pi / 2 + phase * 2 * Double.pi       // top at boundary; no stick

            Canvas { ctx, size in
                let W = size.width, H = size.height
                let C = CGPoint(x: W/2, y: H/2)

                // Orb position on ring
                let ux = CGFloat(cos(angle)), uy = CGFloat(sin(angle))
                let P = CGPoint(x: C.x + ux * r, y: C.y + uy * r)

                // Comet tail (~30°)
                let tail = Double.pi / 6.0
                var tailPath = Path()
                tailPath.addArc(center: C, radius: r,
                                startAngle: .radians(angle - tail),
                                endAngle: .radians(angle),
                                clockwise: false)
                ctx.addFilter(.blur(radius: reduceMotion ? 2 : 3))
                ctx.stroke(tailPath, with: .color(theme.accent.opacity(reduceMotion ? 0.16 : 0.26)), lineWidth: 4)
                ctx.addFilter(.blur(radius: 0))

                // Outer bloom
                let bloomR: CGFloat = 14
                ctx.addFilter(.blur(radius: reduceMotion ? 6 : 8))
                ctx.fill(
                    Path(ellipseIn: CGRect(x: P.x - bloomR, y: P.y - bloomR, width: bloomR*2, height: bloomR*2)),
                    with: .color(theme.accent.opacity(reduceMotion ? 0.28 : 0.42))
                )
                ctx.addFilter(.blur(radius: 0))

                // Halo ring
                let haloR: CGFloat = 7.5
                ctx.stroke(
                    Path(ellipseIn: CGRect(x: P.x - haloR, y: P.y - haloR, width: haloR*2, height: haloR*2)),
                    with: .color(Color.white.opacity(0.80)),
                    lineWidth: 1.25
                )

                // Core
                let coreR: CGFloat = 4.8
                ctx.fill(
                    Path(ellipseIn: CGRect(x: P.x - coreR, y: P.y - coreR, width: coreR*2, height: coreR*2)),
                    with: .color(.white)
                )
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Chakra Pulse Overlay (with step-0 bloom)

private struct ChakraPulseOverlay: View {
    let moment: KaiMoment
    let theme: ArcTheme
    let breath: Double
    let reduceMotion: Bool
    @State private var scale: CGFloat = 0.96

    var body: some View {
        Circle()
            .stroke(theme.accent.opacity(reduceMotion ? 0.20 : 0.35), lineWidth: 6)
            .blur(radius: reduceMotion ? 3 : 6)
            .scaleEffect(scale)
            .onChange(of: moment.kai.wholePulsesIntoDay) { _, _ in
                withAnimation(.spring(response: 0.42, dampingFraction: 0.9, blendDuration: 0.0)) {
                    scale = reduceMotion ? 0.99 : 1.02
                }
                withAnimation(.easeInOut(duration: breath * (1.0/11.0))) {
                    scale = 0.96
                }
            }
            .onChange(of: moment.kai.step) { _, newStep in
                guard newStep == 0 else { return }
                withAnimation(.spring(response: 0.20, dampingFraction: 0.65)) { scale = 1.05 }
                withAnimation(.easeOut(duration: 0.18).delay(0.12)) { scale = 0.96 }
            }
    }
}

// MARK: - Tilt-Based Orbital Sparkle

private struct HarmonicSpark: View {
    let moment: KaiMoment
    let roll: Double
    let pitch: Double
    let reduceMotion: Bool
    let theme: ArcTheme

    var body: some View {
        let period = max(0.08, KKS.kaiPulseSec / 44.0)
        TimelineView(.periodic(from: .now, by: period)) { _ in
            Canvas { ctx, size in
                let W = size.width, H = size.height
                let C = CGPoint(x: W/2, y: H/2)
                let baseR = min(W, H) * 0.36
                let baseAng = moment.progressDay * 2 * Double.pi
                let tiltA = baseAng + (reduceMotion ? 0.25 : 0.6) * roll + (reduceMotion ? 0.18 : 0.45) * pitch
                let count = reduceMotion ? 3 : 5
                for k in 0..<count {
                    let phase = Double(k) * (2 * Double.pi / Double(count))
                    let ang = tiltA + phase
                    let rScale = 0.86 + 0.08 * sin(ang * 0.5)
                    let r  = baseR * CGFloat(rScale)
                    let pt = CGPoint(x: C.x + r * cos(ang), y: C.y + r * sin(ang))
                    let dotR: CGFloat = 1.0 + CGFloat(k) * 0.6
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: pt.x - dotR, y: pt.y - dotR, width: dotR*2, height: dotR*2)),
                        with: .color(theme.accent.opacity(reduceMotion ? 0.16 : 0.22))
                    )
                }
            }
        }
    }
}

// MARK: - Sigil Overlay (lissajous)

private struct SigilOverlay: View {
    let moment: KaiMoment
    var body: some View {
        GeometryReader { geo in
            let S = min(geo.size.width, geo.size.height)
            let C = CGPoint(x: geo.size.width/2, y: geo.size.height/2)

            let pulse = moment.kai.wholePulsesIntoDay
            let a = 3 + Int(pulse % 5)                   // 3..7
            let b = 2 + Int((pulse / 5) % 5)             // 2..6
            let δ = Double((pulse % 64)) * (Double.pi/64)

            Canvas { ctx, _ in
                var p = Path()
                let R = S * 0.34
                let N = 640
                for i in 0...N {
                    let t = Double(i) / Double(N) * 2 * Double.pi
                    let x = C.x + CGFloat(R * cos(Double(a) * t + δ))
                    let y = C.y + CGFloat(R * sin(Double(b) * t))
                    if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                }
                ctx.stroke(p, with: .color(kaiHex("#cfffff").opacity(0.85)), lineWidth: 2.0)
                ctx.addFilter(.blur(radius: 5))
                ctx.stroke(p, with: .color(kaiHex("#7ff7ff").opacity(0.28)), lineWidth: 6.0)
            }
        }
    }
}

// MARK: - Background

private struct AtlanteanBackgroundWatch: View {
    let breath: Double
    let reduceMotion: Bool
    let theme: ArcTheme
    var body: some View {
        ZStack {
            LinearGradient(colors: [theme.bgTop, theme.bgMid, theme.bgBot], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            let tick = max(0.12, breath / 11.0)
            TimelineView(.periodic(from: .now, by: tick)) { t in
                AtlanteanCanvasWatch(time: t.date.timeIntervalSinceReferenceDate, breath: breath, reduceMotion: reduceMotion, theme: theme)
            }
            .ignoresSafeArea()
        }
    }
}

private struct AtlanteanCanvasWatch: View {
    let time: TimeInterval
    let breath: Double
    let reduceMotion: Bool
    let theme: ArcTheme
    var body: some View {
        Canvas { ctx, size in
            drawBackground(ctx: &ctx, size: size, time: time, breath: breath, reduceMotion: reduceMotion, theme: theme)
        }
    }

    private func drawBackground(ctx: inout GraphicsContext, size: CGSize, time: TimeInterval, breath: Double, reduceMotion: Bool, theme: ArcTheme) {
        let W = size.width, H = size.height
        let C = CGPoint(x: W/2, y: H/2)

        let phi = max(0.001, breath)
        let t1 = time.truncatingRemainder(dividingBy: phi) / phi
        let t2 = time.truncatingRemainder(dividingBy: phi * 2) / (phi * 2)
        let wave  = (reduceMotion ? 0.25 : 0.5) * sin(t1 * 2 * .pi) + 0.5
        let wave2 = (reduceMotion ? 0.25 : 0.5) * sin(t2 * 2 * .pi + .pi/3) + 0.5

        blob(&ctx, center: CGPoint(x: C.x, y: H * 0.22), baseR: max(W, H) * 0.52, color: theme.accentSoft, blur: 20, alpha: 0.20, phase: wave)
        blob(&ctx, center: CGPoint(x: W * 0.22, y: H * 0.38), baseR: max(W, H) * 0.40, color: theme.accent, blur: 16, alpha: 0.14, phase: wave)
        blob(&ctx, center: CGPoint(x: W * 0.78, y: H * 0.36), baseR: max(W, H) * 0.40, color: theme.accent, blur: 16, alpha: 0.14, phase: wave)

        let rr = max(W, H) * CGFloat(0.40 + 0.04 * wave)
        var ring = Path()
        ring.addEllipse(in: CGRect(x: C.x - rr, y: C.y - rr, width: rr*2, height: rr*2))
        ctx.addFilter(.blur(radius: 8))
        ctx.stroke(ring, with: .color(Color.white.opacity(0.10)), lineWidth: 1.5)

        let sparks = reduceMotion ? 36 : 64
        let spin = time / 18
        for i in 0..<sparks {
            let k = Double(i) / Double(sparks)
            let ang = k * 2 * Double.pi * 3 + spin
            let d  = CGFloat((0.18 + 0.58 * k) * Double(min(W, H))) * CGFloat(0.84 + 0.12 * wave2)
            let pt = CGPoint(x: C.x + d * cos(ang), y: C.y + d * sin(ang))
            let dotR: CGFloat = 0.9 + CGFloat(k) * 1.2
            ctx.fill(
                Path(ellipseIn: CGRect(x: pt.x - dotR, y: pt.y - dotR, width: dotR*2, height: dotR*2)),
                with: .color(theme.accent.opacity(0.10 + 0.12 * (1 - k)))
            )
        }
    }

    private func blob(_ ctx: inout GraphicsContext, center: CGPoint, baseR: CGFloat, color: Color, blur: CGFloat, alpha: Double, phase: Double) {
        let r = baseR * CGFloat(0.85 + 0.30 * phase)
        let rect = CGRect(x: center.x - r, y: center.y - r, width: r*2, height: r*2)
        ctx.addFilter(.blur(radius: blur))
        ctx.opacity = alpha
        let g = Gradient(stops: [
            .init(color: color.opacity(0.20), location: 0.0),
            .init(color: color.opacity(0.001), location: 1.0)
        ])
        ctx.fill(Path(ellipseIn: rect), with: .radialGradient(g, center: center, startRadius: 0, endRadius: r))
        ctx.opacity = 1
    }
}


// MARK: - Mode Sheet (watch-safe, Fibonacci-locked custom Hz, phase cal)

private struct ModeSheet: View {
    @Binding var mode: HarmonicMode
    @Binding var customHz: Double
    @Binding var pulseHapticsEnabled: Bool
    @Binding var accentBeatEnabled: Bool
    @Binding var whisperEnabled: Bool
    @Binding var phaseOffset: Double
    var onApply: () -> Void

    @State private var selectedFibIndex: Int = nearestIndex(in: FIB_HZ, to: 432)
    @State private var hzInput: String = "432"

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("Harmonic Modes & Haptics")
                    .font(.headline)
                    .padding(.top, 4)

                ForEach(HarmonicMode.allCases, id: \.self) { m in
                    Button {
                        mode = m
                    } label: {
                        HStack {
                            Text(m.rawValue).font(.system(size: 14, weight: .semibold))
                            Spacer()
                            if mode == m {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(kaiHex("#7ff7ff"))
                            }
                        }
                        .padding(8)
                        .background(kaiHex("#08141b"), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                Divider().overlay(Color.white.opacity(0.08))

                if mode == .custom {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Custom Frequency (Fibonacci-locked)")
                            .font(.system(size: 13, weight: .semibold))

                        Picker("Fibonacci Hz", selection: $selectedFibIndex) {
                            ForEach(0..<FIB_HZ.count, id: \.self) { i in Text("\(FIB_HZ[i]) Hz").tag(i) }
                        }
                        .labelsHidden()
                        .pickerStyle(.wheel)
                        .frame(maxWidth: .infinity)

                        HStack(spacing: 8) {
                            Text("Set Hz")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                            TextField("Hz", text: $hzInput)
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .multilineTextAlignment(.trailing)
                                .onSubmit { applyHzInput() }
                            Button {
                                applyHzInput()
                                WKInterfaceDevice.current().play(.click)
                            } label: { Image(systemName: "checkmark.circle") }
                            .buttonStyle(.plain)
                        }
                        .padding(8)
                        .background(kaiHex("#08141b"), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                        Text("Selected: \(FIB_HZ[selectedFibIndex]) Hz")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .onChange(of: selectedFibIndex) { _, idx in
                        let hz = FIB_HZ[max(0, min(FIB_HZ.count - 1, idx))]
                        customHz = Double(hz)
                        hzInput = "\(hz)"
                    }
                    .onAppear {
                        let snap = nearestFib(to: customHz)
                        selectedFibIndex = nearestIndex(in: FIB_HZ, to: snap)
                        hzInput = "\(snap)"
                        customHz = Double(snap)
                    }
                }

                Divider().overlay(Color.white.opacity(0.08))

                Toggle(isOn: $pulseHapticsEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pulse Haptics")
                        Text("Small cues at 20% & 50%; BIG harmonic chime at boundary (~5.236 s).")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .tint(kaiHex("#7ff7ff"))

                Toggle(isOn: $accentBeatEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Beat Accent")
                        Text("Optional visual/affirmation accent at each step start (11 pulses/step).")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .tint(kaiHex("#7ff7ff"))

                Toggle(isOn: $whisperEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Whisper Affirmations")
                        Text("Soft affirmation at beat boundaries.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .tint(kaiHex("#7ff7ff"))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Phase Calibration")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Align the 20%/50% cues to your inhale crest.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Slider(value: $phaseOffset, in: 0...1, step: 0.01)
                    Text(String(format: "Offset: %.0f%% of pulse", phaseOffset * 100))
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Button(action: onApply) {
                    HStack(spacing: 8) {
                        Image(systemName: "waveform").font(.system(size: 16, weight: .bold))
                        Text("Apply").font(.system(size: 14, weight: .semibold))
                    }
                    .padding(.vertical, 8).padding(.horizontal, 12)
                    .background(kaiHex("#0a1b24"), in: Capsule())
                    .overlay(Capsule().stroke(kaiHex("#7fdfff").opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Apply")
                .padding(.bottom, 8)
            }
            .padding(.horizontal)
        }
        .focusable(false)
    }

    private func applyHzInput() {
        let v = Double(hzInput) ?? customHz
        let snapped = nearestFib(to: v)
        selectedFibIndex = nearestIndex(in: FIB_HZ, to: snapped)
        hzInput = "\(snapped)"
        customHz = Double(snapped)
    }
}

// MARK: - Tips & Breath Guide overlays (unchanged)

private struct TipsOverlay: View {
    var onDismiss: () -> Void
    var body: some View {
        VStack(spacing: 8) {
            Text("Welcome to KaiKlok")
                .font(.headline)
            Text("• Double-tap the dial to show/hide the Seal overlay.\n• Long-press the dial to capture a sealed moment (JSON).\n• Use the corner icons: calendar, waveform, viewfinder, lock.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button(action: onDismiss) {
                Text("Join the Breath").font(.system(size: 13, weight: .semibold))
                    .padding(.vertical, 6).padding(.horizontal, 14)
                    .background(kaiHex("#0a1b24"), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(kaiHex("#06121a").opacity(0.9), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(kaiHex("#7fdfff").opacity(0.3), lineWidth: 1))
        .padding()
        .transition(.opacity)
    }
}

private struct BreathGuideOverlay: View {
    let pulseIndex: Int
    let onDismiss: () -> Void
    var body: some View {
        VStack(spacing: 10) {
            Text("Join the Breath").font(.headline)
            Text(pulseIndex < 2 ? "Inhale • Crest • Exhale" : "You are on time.")
                .font(.system(size: 14, weight: .semibold))
            Button("Dismiss", action: onDismiss)
                .font(.system(size: 13, weight: .semibold))
                .padding(.vertical, 6).padding(.horizontal, 14)
                .background(kaiHex("#0a1b24"), in: Capsule())
        }
        .padding(12)
        .background(kaiHex("#06121a").opacity(0.95), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(kaiHex("#7fdfff").opacity(0.3), lineWidth: 1))
        .padding()
        .transition(.opacity)
    }
}

private struct AffirmationOverlay: View {
    let phrase: String?
    let accent: Color
    var body: some View {
        Group {
            if let phrase {
                Text(phrase)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(kaiHex("#09131a").opacity(0.72), in: Capsule())
                    .overlay(Capsule().stroke(accent.opacity(0.35), lineWidth: 1))
                    .transition(.opacity)
            }
        }
    }
}

// MARK: - View modifiers (setup/sync/scrub/boundary)

private struct SetupLifecycleModifier: ViewModifier {
    let onAppear: () -> Void
    let onDisappear: () -> Void
    func body(content: Content) -> some View {
        content
            .onAppear(perform: onAppear)
            .onDisappear(perform: onDisappear)
    }
}
private extension View {
    func setupLifecycle(onAppear: @escaping () -> Void,
                        onDisappear: @escaping () -> Void) -> some View {
        modifier(SetupLifecycleModifier(onAppear: onAppear, onDisappear: onDisappear))
    }
}

private struct SyncSettingsModifier: ViewModifier {
    @ObservedObject var audio: HarmonicAudioPulse
    @ObservedObject var affirm: AffirmationCenter
    @Binding var pulseHapticsEnabled: Bool
    @Binding var accentBeatEnabled: Bool
    @Binding var storedWhisperEnabled: Bool
    @Binding var storedAudioMode: String
    @Binding var storedCustomHz: Double
    @Binding var phaseOffset: Double

    func body(content: Content) -> some View {
        content
            .onChange(of: audio.mode) { _, new in storedAudioMode = new.rawValue }
            .onChange(of: affirm.whisperEnabled) { _, new in storedWhisperEnabled = new }
            .onChange(of: pulseHapticsEnabled) { _, v in HapticAudioCoordinator.shared.pulseHapticsEnabled = v }
            .onChange(of: accentBeatEnabled)   { _, v in HapticAudioCoordinator.shared.accentBeatEnabled   = v }
            .onChange(of: phaseOffset)         { _, v in HapticAudioCoordinator.shared.phaseOffset         = v }
            .onChange(of: storedCustomHz)      { _, v in HapticAudioCoordinator.shared.customHz            = v }
    }
}
private extension View {
    func syncSettingsToCoordinator(
        audio: HarmonicAudioPulse,
        affirm: AffirmationCenter,
        pulseHapticsEnabled: Binding<Bool>,
        accentBeatEnabled: Binding<Bool>,
        storedWhisperEnabled: Binding<Bool>,
        storedAudioMode: Binding<String>,
        storedCustomHz: Binding<Double>,
        phaseOffset: Binding<Double>
    ) -> some View {
        modifier(SyncSettingsModifier(
            audio: audio, affirm: affirm,
            pulseHapticsEnabled: pulseHapticsEnabled.wrappedValueBinding,
            accentBeatEnabled: accentBeatEnabled.wrappedValueBinding,
            storedWhisperEnabled: storedWhisperEnabled.wrappedValueBinding,
            storedAudioMode: storedAudioMode.wrappedValueBinding,
            storedCustomHz: storedCustomHz.wrappedValueBinding,
            phaseOffset: phaseOffset.wrappedValueBinding
        ))
    }
}

// helper to convert Binding<T> to @Binding param of modifier init
private extension Binding {
    var wrappedValueBinding: Binding<Value> { self }
}

private struct ScrubSupportModifier: ViewModifier {
    @Binding var isScrubbing: Bool
    @Binding var crown: Double
    let momentProvider: () -> KaiMoment
    let onPreview: (KaiMoment) -> Void
    let onBeatTick: (Int) -> Void
    let onStop: () -> Void

    func body(content: Content) -> some View {
        #if os(watchOS)
        content
            .focusable(true)
            .digitalCrownRotation(
                $crown,
                from: -1.0, through: 1.0, by: 0.001,
                sensitivity: .high,
                isContinuous: true,
                isHapticFeedbackEnabled: true
            )
            .onChange(of: crown) { _, _ in
                guard isScrubbing else { return }
                let live = momentProvider()
                let pulsesPerBeat = Double(KKS.muPerBeatExact) / Double(KKS.onePulseMicro)
                let targetDate = Date(timeInterval: (crown * pulsesPerBeat) * KKS.kaiPulseSec, since: live.date)
                let pm = KaiMoment(date: targetDate, kai: computeLocalKai(targetDate))
                onPreview(pm)
                if pm.kai.step == 0 { onBeatTick(pm.kai.beat) }
            }
        #else
        content
        #endif
    }
}
private extension View {
    func scrubSupport(
        isScrubbing: Binding<Bool>,
        crown: Binding<Double>,
        momentProvider: @escaping () -> KaiMoment,
        onPreview: @escaping (KaiMoment) -> Void,
        onBeatTick: @escaping (Int) -> Void,
        onStop: @escaping () -> Void
    ) -> some View {
        modifier(ScrubSupportModifier(
            isScrubbing: isScrubbing.wrappedValueBinding,
            crown: crown.wrappedValueBinding,
            momentProvider: momentProvider,
            onPreview: onPreview,
            onBeatTick: onBeatTick,
            onStop: onStop
        ))
    }
}

private struct BoundaryReceiveModifier: ViewModifier {
    @State private var subscribed = false
    let handler: (KaiMoment) -> Void
    func body(content: Content) -> some View {
        content
            .onAppear {
                if !subscribed {
                    subscribed = true
                    PulseClock.shared.subscribe { moment in
                        handler(moment)
                    }
                }
            }
    }
}
private extension View {
    func onReceiveBoundary(_ handler: @escaping (KaiMoment) -> Void) -> some View {
        modifier(BoundaryReceiveModifier(handler: handler))
    }
}
