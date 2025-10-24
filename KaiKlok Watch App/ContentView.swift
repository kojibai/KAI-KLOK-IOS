//
//  ContentView.swift
//  KaiKlok Watch App — Divine Interface v1.1.1 “Kai-Fidelity+”
//  Ship-ready: μpulse-exact, genesis-resnap, breath-periodic rendering, canon arcs.
//  Notes for Info.plist:
//    • NSMotionUsageDescription (tilt sparkle)
//    • UIBackgroundModes = [ audio ] if keeping Resonant Lock tones
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
    static let kaiPulseSec: Double = 3 + sqrt(5)          // ≈ 5.236067977 (breath)
    static let pulseMsExact: Double = kaiPulseSec * 1000.0

    // μpulse constants (exact; integer-safe)
    static let onePulseMicro: Int64 = 1_000_000
    static let nDayMicro: Int64 = 17_491_270_421          // exact μpulses/day
    static var muPerBeatExact: Int64 { (nDayMicro + 18) / 36 } // ties-to-even
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

    // Integer floor-division with negatives handled
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

    static func pad2(_ n: Int) -> String { String(format: "%02d", n) }
}

// MARK: - Domain

private enum DayName: String, CaseIterable, Codable { case Solhara, Aquaris, Flamora, Verdari, Sonari, Kaelith }

private struct LocalKai: Codable {
    let beat: Int               // 0..35
    let step: Int               // 0..43
    let wholePulsesIntoDay: Int // integer pulses into day (display/reporting)
    let dayOfMonth: Int         // 1..42
    let monthIndex1: Int        // 1..8
    let weekday: DayName
    let monthDayIndex: Int      // 0..41
    let chakraStepString: String
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

    let wholePulsesIntoDay = Int(KKS.floorDiv(pμ_in_day, KKS.onePulseMicro))

    let weekdayIdx = Int(KKS.imod(dayIndex, 6))
    let weekday = DayName.allCases[weekdayIdx]

    let dayIndexNum = Int(dayIndex)
    let dayOfMonth = ((dayIndexNum % 42) + 42) % 42 + 1
    let monthIndex0 = (dayIndexNum / 42) % 8
    let monthIndex1 = ((monthIndex0 + 8) % 8) + 1

    let monthDayIndex = dayOfMonth - 1
    let chakra = "\(beat):\(KKS.pad2(step))"
    let seal = "\(chakra) — D\(dayOfMonth)/M\(monthIndex1)"
    return .init(
        beat: beat, step: step, wholePulsesIntoDay: wholePulsesIntoDay,
        dayOfMonth: dayOfMonth, monthIndex1: monthIndex1,
        weekday: weekday, monthDayIndex: monthDayIndex,
        chakraStepString: chakra, sealText: seal
    )
}

private struct KaiMoment: Equatable, Codable {
    let date: Date
    let kai: LocalKai
    var stepIndexInDay: Int { kai.beat * 44 + kai.step }  // 0..(36*44-1)
    var totalStepsInDay: Int { 36 * 44 }
    var progress: Double { Double(stepIndexInDay) / Double(totalStepsInDay) }
    static func == (l: KaiMoment, r: KaiMoment) -> Bool {
        l.kai.beat == r.kai.beat && l.kai.step == r.kai.step
    }
}

// MARK: - Engine (μpulse-aligned with per-tick re-snap)

@MainActor
private final class KairosEngine: ObservableObject {
    static let shared = KairosEngine()
    @Published var moment: KaiMoment
    private var timer: DispatchSourceTimer?

    private init() {
        let now = Date()
        moment = KaiMoment(date: now, kai: computeLocalKai(now))
        scheduleAligned()
    }

    deinit { timer?.cancel() }

    private func scheduleAligned() {
        timer?.cancel(); timer = nil

        func scheduleNext() {
            let nowMs = Date().timeIntervalSince1970 * 1000.0
            let genesisMs = KKS.genesisUTC.timeIntervalSince1970 * 1000.0
            let elapsed = nowMs - genesisMs
            let periods = ceil(elapsed / KKS.pulseMsExact)
            let targetBoundary = genesisMs + periods * KKS.pulseMsExact
            let initialDelay = max(0, targetBoundary - nowMs) / 1000.0

            let t = DispatchSource.makeTimerSource(queue: .global(qos: .userInteractive))
            t.schedule(deadline: .now() + initialDelay, repeating: .never)
            t.setEventHandler { [weak self] in
                let now = Date()
                let m = KaiMoment(date: now, kai: computeLocalKai(now))
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.moment = m
                    self.timer?.cancel()
                    self.timer = nil
                    scheduleNext() // Hard re-snap every pulse boundary (zero drift)
                }
            }
            self.timer = t
            t.resume()
        }

        scheduleNext()
    }
}

// MARK: - Colors / helpers

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

private func chakraColor(beat: Int, step: Int) -> Color {
    let palette = ["#ff6b6b","#ffa94d","#ffe066","#8ce99a","#74c0fc","#b197fc","#f783ac"]
    let idx = (beat + step) % palette.count
    return kaiHex(palette[idx], alpha: 0.85)
}

// Canon arc names (6 × 7 days = 42)
private func arcName(for dayOfMonth: Int) -> String {
    let arcs = ["Ignition","Integration","Harmonization","Reflection","Purification","Dream"]
    let d = max(1, min(42, dayOfMonth))
    return arcs[(d - 1) / 7]
}

// MARK: - Motion (tilt for orbital sparkle)

@MainActor
private final class MotionManager: ObservableObject {
    static let shared = MotionManager()
    private let mgr = CMMotionManager()
    @Published var roll: Double = 0
    @Published var pitch: Double = 0

    private init() {
        mgr.deviceMotionUpdateInterval = 1.0 / 30.0
    }

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

// MARK: - Harmonic Audio Pulse (breath AM, safe on watch)

private enum HarmonicMode: String, CaseIterable {
    case relax = "Relax"   // ~396 Hz
    case focus = "Focus"   // ~528 Hz
    case root  = "Root"    // 432 Hz
    case custom = "Custom" // user-set
}

@MainActor
private final class HarmonicAudioPulse: ObservableObject {
    static let shared = HarmonicAudioPulse()
    @Published var mode: HarmonicMode = .root
    @Published var isPlaying: Bool = false

    private var player: AVAudioPlayer?
    var isReady: Bool { player != nil }

    private func configureSession() {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? s.setActive(true)
    }

    // Synthesize gentle AM tone and cache to temp, then loop with AVAudioPlayer.
    private func ensureToneFileURL(frequency: Double, seconds: Double = 12.0) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("harmonic_\(Int(frequency))_AM.caf")
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
            let env = Float(0.6 + 0.35 * sin(2.0 * .pi * breathHz * t))
            ptr[n] = env * Float(car) * 0.4
        }
        do { try file.write(from: buffer); return url } catch { return nil }
    }

    private func freqForMode(_ mode: HarmonicMode, customHz: Double?) -> Double {
        switch mode {
        case .relax:  return 396
        case .focus:  return 528
        case .root:   return 432
        case .custom: return max(110, min(1760, customHz ?? 432))
        }
    }

    func prepare(mode: HarmonicMode, customHz: Double? = nil) {
        self.mode = mode
        configureSession()
        let f = freqForMode(mode, customHz: customHz)
        guard let url = ensureToneFileURL(frequency: f) else { return }
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.numberOfLoops = -1
            p.volume = 0.8
            p.prepareToPlay()
            self.player = p
        } catch {
            self.player = nil
        }
    }

    func play() {
        guard let p = player else { return }
        p.play()
        isPlaying = true
    }

    func stop() {
        guard let p = player else { return }
        p.stop()
        p.currentTime = 0
        isPlaying = false
        // Be a good platform citizen
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
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
        // Beat start only (step==0); simpler, clearer, canon-aligned.
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

// MARK: - ContentView

struct ContentView: View {
    @StateObject private var engine = KairosEngine.shared
    @StateObject private var motion = MotionManager.shared
    @StateObject private var audio  = HarmonicAudioPulse.shared
    @StateObject private var affirm = AffirmationCenter.shared

    // Environment empathy
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Persisted vibes
    @AppStorage("didShowKaiWatchTips") private var didShowTips: Bool = false
    @AppStorage("eternalLight") private var eternalLight: Bool = false
    @AppStorage("audioMode") private var storedAudioMode: String = HarmonicMode.root.rawValue
    @AppStorage("customHz") private var storedCustomHz: Double = 432
    @AppStorage("affirmWhisperEnabled") private var storedWhisperEnabled: Bool = false

    // First-run teaching tip
    @State private var showTips = false

    @State private var showWeekModal = false
    @State private var showEternalKlock = false
    @State private var isSigilOverlay = false

    @State private var showModeSheet = false
    @State private var customHz: Double = 432

    @State private var isScrubbing = false
    @State private var crown: Double = 0
    @State private var previewMoment: KaiMoment? = nil
    @State private var lastHapticBeatIndex: Int = -1   // FIX: track beat boundary, not step/44

    @State private var resonantLocked = false

    private let breath: Double = KKS.kaiPulseSec

    private var currentMoment: KaiMoment { previewMoment ?? engine.moment }
    private var chipText: String {
        isScrubbing ? "Scrub \(currentMoment.kai.chakraStepString)" : "Live \(engine.moment.kai.chakraStepString)"
    }

    var body: some View {
        ZStack {
            AtlanteanBackgroundWatch(breath: breath, lightMode: eternalLight, reduceMotion: reduceMotion)
                .accessibilityHidden(true)

            GeometryReader { geo in
                let side   = min(geo.size.width, geo.size.height)
                let dialSz = min(side * 0.92, 220)

                VStack(spacing: 6) {
                    Text(arcName(for: currentMoment.kai.dayOfMonth))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(kaiHex("#cfefff").opacity(0.9))
                        .padding(.top, 2)

                    ZStack {
                        KaiDialView(moment: currentMoment, breath: breath, glowSize: dialSz, lightMode: eternalLight)
                            .frame(width: dialSz, height: dialSz)
                            .accessibilityHidden(true)

                        ChakraPulseOverlay(moment: currentMoment, breath: breath, reduceMotion: reduceMotion)
                            .allowsHitTesting(false)

                        HarmonicSpark(moment: currentMoment, roll: motion.roll, pitch: motion.pitch, reduceMotion: reduceMotion)
                            .allowsHitTesting(false)

                        if isSigilOverlay {
                            SigilOverlay(moment: currentMoment)
                                .transition(.opacity)
                                .allowsHitTesting(false)
                        }

                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                withAnimation(.easeInOut(duration: 0.25)) { isSigilOverlay.toggle() }
                            }
                            .onLongPressGesture(minimumDuration: 0.6) { captureSeal() }
                    }

                    HStack(spacing: 8) {
                        Text(verbatim: currentMoment.kai.sealText)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(kaiHex("#e6faff"))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(kaiHex("#00eaff", alpha: 0.14))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(kaiHex("#00eaff", alpha: 0.36), lineWidth: 1))

                        Text("μ\(KKS.microPulsesSinceGenesis(currentMoment.date))")
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    HStack(spacing: 8) {
                        ModeChip(isScrubbing: isScrubbing, text: chipText)
                            .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { toggleScrub() } }

                        HarmonicButton(label: resonantLocked ? NSLocalizedString("Unlock", comment: "") : NSLocalizedString("Resonant Lock", comment: "")) {
                            resonantLocked.toggle()
                            if resonantLocked {
                                if !audio.isReady { audio.prepare(mode: audio.mode, customHz: customHz) }
                                audio.play()
                                WKInterfaceDevice.current().play(.directionUp)
                            } else {
                                audio.stop()
                            }
                        }

                        HarmonicButton(label: audio.mode.rawValue) { showModeSheet = true }
                    }

                    Spacer(minLength: 2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if let phrase = affirm.current {
                Text(phrase)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(kaiHex("#09131a").opacity(0.72), in: Capsule())
                    .overlay(Capsule().stroke(kaiHex("#7ff7ff").opacity(0.35), lineWidth: 1))
                    .transition(.opacity)
            }

            if showTips {
                TipsOverlay {
                    withAnimation(.easeInOut(duration: 0.3)) { showTips = false; didShowTips = true }
                }
            }
        }
        .onAppear {
            // Restore vibe prefs
            audio.mode = HarmonicMode(rawValue: storedAudioMode) ?? .root
            customHz = storedCustomHz
            affirm.whisperEnabled = storedWhisperEnabled

            // Teach briefly on first run
            if !didShowTips {
                showTips = true
                DispatchQueue.main.asyncAfter(deadline: .now() + breath * 2.0) {
                    withAnimation(.easeInOut(duration: 0.3)) { showTips = false; didShowTips = true }
                }
            }

            // Start motion updates when visible
            motion.start()
        }
        .onDisappear {
            motion.stop()
        }
        // Persist on-the-fly changes
        .onChange(of: audio.mode) { _, new in storedAudioMode = new.rawValue }
        .onChange(of: customHz) { _, new in storedCustomHz = new }
        .onChange(of: affirm.whisperEnabled) { _, new in storedWhisperEnabled = new }

        .focusable(true)
        .digitalCrownRotation(
            $crown,
            from: -1.0,
            through: 1.0,
            by: 0.001,
            sensitivity: .high,
            isContinuous: true,
            isHapticFeedbackEnabled: true
        )
        .onChange(of: crown) { _, _ in
            guard isScrubbing else { return }
            previewMoment = scrubbedMoment(deltaBeats: crown)

            // FIX: Haptic on beat boundaries (step==0) with dedup per-beat
            if let pm = previewMoment, pm.kai.step == 0 {
                let beatIndex = pm.kai.beat // 0..35
                if beatIndex != lastHapticBeatIndex {
                    lastHapticBeatIndex = beatIndex
                    WKInterfaceDevice.current().play(.click)
                }
            }
        }
        .onChange(of: engine.moment) { oldVal, newVal in
            if newVal.kai.step == 0, newVal != oldVal {
                WKInterfaceDevice.current().play(.directionUp)
            }
            // Beat-start micro-tone *only sometimes* when not locked (energy friendly)
            if newVal.kai.step == 0 && !audio.isPlaying && (newVal.kai.beat % 3 == 0) {
                if !audio.isReady { audio.prepare(mode: audio.mode, customHz: customHz) }
                audio.play()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { audio.stop() }
            }
            affirm.trigger(beat: newVal.kai.beat, step: newVal.kai.step)
            if !isScrubbing { previewMoment = nil }
        }
        .animation(.linear(duration: 0.22), value: engine.moment.kai.step)

        .safeAreaInset(edge: .bottom) {
            BottomToolbarWatch(
                breath: breath,
                leftView: AnyView(HarmonicToggle(title: eternalLight ? NSLocalizedString("Light", comment: "") : NSLocalizedString("Night", comment: ""), isOn: eternalLight) { eternalLight.toggle() }),
                rightView: AnyView(HarmonicButton(label: NSLocalizedString("Week", comment: "")) { showWeekModal = true })
            )
            .padding(.bottom, 4)
        }
        .sheet(isPresented: $showWeekModal) { WeekKalendarWatchSheet() }
        .sheet(isPresented: $showEternalKlock) { EternalKlockWatchView(moment: currentMoment, breath: breath) }
        .sheet(isPresented: $showModeSheet) {
            ModeSheet(mode: $audio.mode, customHz: $customHz) {
                audio.prepare(mode: audio.mode, customHz: customHz)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(currentMoment.kai.sealText), \(currentMoment.kai.weekday.rawValue)")
        .accessibilityHint(isScrubbing ? NSLocalizedString("Turn Digital Crown to preview; tap to return live.", comment: "") : NSLocalizedString("Tap to enable Digital Crown preview.", comment: ""))
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

    private func scrubbedMoment(deltaBeats: Double) -> KaiMoment {
        let live = engine.moment
        let pulsesPerBeat = Double(KKS.muPerBeatExact) / Double(KKS.onePulseMicro)
        let deltaPulses = deltaBeats * pulsesPerBeat
        let targetDate = Date(timeInterval: deltaPulses * KKS.kaiPulseSec, since: live.date)
        return KaiMoment(date: targetDate, kai: computeLocalKai(targetDate))
    }

    // MARK: - SigilVault Capture
    private func captureSeal() {
        let stamp = currentMoment
        struct SealCapture: Codable {
            let moment: KaiMoment
            let pulseMicro: Int64
            let mode: String
            let lightMode: Bool
        }
        let payload = SealCapture(
            moment: stamp,
            pulseMicro: KKS.microPulsesSinceGenesis(stamp.date),
            mode: audio.mode.rawValue,
            lightMode: eternalLight
        )
        do {
            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            var url = dir.appendingPathComponent("seal_\(payload.pulseMicro).session.φ.json") // ← PATCH: var (mutable)
            let data = try JSONEncoder().encode(payload)
            try data.write(to: url, options: .atomic)

            // Exclude from backups (ephemeral session capture)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? url.setResourceValues(values) // ok: mutating method on var

            WKInterfaceDevice.current().play(.success)
        } catch {
            WKInterfaceDevice.current().play(.failure)
        }
    }
}

#Preview("KaiKlok (watchOS)") { ContentView() }

// MARK: - Kai Dial (hero view)

private struct KaiDialView: View {
    let moment: KaiMoment
    let breath: Double
    let glowSize: CGFloat
    let lightMode: Bool
    @State private var breathe = false

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(colors: [kaiHex("#00ffff").opacity(breathe ? 0.26 : 0.14), .clear],
                                   center: .center, startRadius: 0, endRadius: glowSize)
                )
                .blur(radius: 18)
                .allowsHitTesting(false)

            Canvas { ctx, size in
                let W = size.width, H = size.height
                let C = CGPoint(x: W/2, y: H/2)
                let R = min(W, H) * 0.46

                drawTrack(ctx: &ctx, center: C, r: R, width: 10,
                          color1: lightMode ? kaiHex("#eaf7ff") : kaiHex("#082230"),
                          color2: lightMode ? kaiHex("#cfe9ff") : kaiHex("#060c12"))

                drawTicks(ctx: &ctx, center: C, r: R, count: 36,
                          majorLength: 12, minorLength: 0,
                          color: (lightMode ? Color.black.opacity(0.25) : Color.white.opacity(0.24)),
                          width: 2)

                drawStepRing(ctx: &ctx, center: C, r: R - 12,
                             totalSteps: moment.totalStepsInDay,
                             completedSteps: moment.stepIndexInDay,
                             colorOn: lightMode ? kaiHex("#0077aa") : kaiHex("#00eaff"),
                             colorOff: lightMode ? Color.black.opacity(0.10) : Color.white.opacity(0.10))

                let angle = -Double.pi/2 + moment.progress * 2 * Double.pi
                let tip = CGPoint(x: C.x + cos(angle) * (R - 4),
                                  y: C.y + sin(angle) * (R - 4))
                var needle = Path()
                needle.move(to: C); needle.addLine(to: tip)
                ctx.stroke(needle, with: .color(lightMode ? kaiHex("#005b7a") : kaiHex("#7ff7ff")), lineWidth: 3)

                let capR: CGFloat = 6
                let capRect = CGRect(x: C.x - capR, y: C.y - capR, width: capR*2, height: capR*2)
                ctx.fill(Path(ellipseIn: capRect), with: .color(lightMode ? kaiHex("#00445e") : kaiHex("#8beaff")))
            }
            .compositingGroup()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: breath).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
        .onDisappear {
            // Stop breathing when off-screen to avoid idle work
            breathe = false
        }
    }

    private func drawTrack(ctx: inout GraphicsContext, center: CGPoint, r: CGFloat, width: CGFloat, color1: Color, color2: Color) {
        var p = Path()
        p.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r*2, height: r*2))
        ctx.stroke(p, with: .linearGradient(Gradient(colors: [color1, color2]),
                                            startPoint: CGPoint(x: center.x - r, y: center.y - r),
                                            endPoint: CGPoint(x: center.x + r, y: center.y + r)),
                   lineWidth: width)
    }
    private func drawTicks(ctx: inout GraphicsContext, center: CGPoint, r: CGFloat, count: Int, majorLength: CGFloat, minorLength: CGFloat, color: Color, width: CGFloat) {
        let base = -Double.pi/2
        for i in 0..<count {
            let t = Double(i) / Double(count)
            let a = base + t * 2 * Double.pi
            let cosA = cos(a), sinA = sin(a)
            let p0 = CGPoint(x: center.x + cosA * (r - majorLength), y: center.y + sinA * (r - majorLength))
            let p1 = CGPoint(x: center.x + cosA * (r), y: center.y + sinA * (r))
            var tick = Path(); tick.move(to: p0); tick.addLine(to: p1)
            ctx.stroke(tick, with: .color(color), lineWidth: width)
        }
        if minorLength > 0 {
            for i in 0..<(count*2) {
                let t = (Double(i) + 0.5) / Double(count*2)
                let a = base + t * 2 * Double.pi
                let cosA = cos(a), sinA = sin(a)
                let p0 = CGPoint(x: center.x + cosA * (r - minorLength), y: center.y + sinA * (r - minorLength))
                let p1 = CGPoint(x: center.x + cosA * (r), y: center.y + sinA * (r))
                var tick = Path(); tick.move(to: p0); tick.addLine(to: p1)
                ctx.stroke(tick, with: .color(color.opacity(0.6)), lineWidth: width*0.6)
            }
        }
    }
    private func drawStepRing(ctx: inout GraphicsContext,
                              center: CGPoint,
                              r: CGFloat,
                              totalSteps: Int,
                              completedSteps: Int,
                              colorOn: Color,
                              colorOff: Color) {
        var bg = Path()
        bg.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r*2, height: r*2))
        ctx.stroke(bg, with: .color(colorOff), lineWidth: 4)

        let start = -Double.pi/2
        let end = start + Double(completedSteps) / Double(totalSteps) * 2 * Double.pi
        var arc = Path()
        arc.addArc(center: center, radius: r, startAngle: .radians(start), endAngle: .radians(end), clockwise: false)
        ctx.stroke(arc, with: .color(colorOn), lineWidth: 5)
    }
}

// MARK: - Chakra Pulse Overlay

private struct ChakraPulseOverlay: View {
    let moment: KaiMoment
    let breath: Double
    let reduceMotion: Bool
    @State private var scale: CGFloat = 0.96

    var body: some View {
        Circle()
            .stroke(chakraColor(beat: moment.kai.beat, step: moment.kai.step).opacity(reduceMotion ? 0.20 : 0.35), lineWidth: 6)
            .blur(radius: reduceMotion ? 3 : 6)
            .scaleEffect(scale)
            .onChange(of: moment.kai.step) { _, _ in
                withAnimation(.spring(response: 0.45, dampingFraction: 0.88, blendDuration: 0.0)) {
                    scale = reduceMotion ? 0.99 : 1.02
                }
                withAnimation(.easeInOut(duration: breath * (1.0/11.0))) {
                    scale = 0.96
                }
            }
    }
}

// MARK: - Tilt-Based Orbital Sparkle (breath-periodic timeline)

private struct HarmonicSpark: View {
    let moment: KaiMoment
    let roll: Double
    let pitch: Double
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: max(0.08, KKS.kaiPulseSec / 44.0))) { _ in
            Canvas { ctx, size in
                let W = size.width, H = size.height
                let C = CGPoint(x: W/2, y: H/2)
                let baseR = min(W, H) * 0.36
                let baseAng = moment.progress * 2 * Double.pi
                let tiltA = baseAng + (reduceMotion ? 0.25 : 0.6) * roll + (reduceMotion ? 0.18 : 0.45) * pitch
                let count = reduceMotion ? 3 : 5
                for k in 0..<count {
                    let phase = Double(k) * (2 * Double.pi / Double(count))
                    let ang = tiltA + phase
                    let r  = baseR * CGFloat(0.86 + 0.08 * sin(ang * 0.5))
                    let pt = CGPoint(x: C.x + r * cos(ang), y: C.y + r * sin(ang))
                    let dotR: CGFloat = 1.0 + CGFloat(k) * 0.6
                    ctx.fill(
                        Path(ellipseIn: CGRect(x: pt.x - dotR, y: pt.y - dotR, width: dotR*2, height: dotR*2)),
                        with: .color(chakraColor(beat: moment.kai.beat, step: moment.kai.step).opacity(reduceMotion ? 0.16 : 0.22))
                    )
                }
            }
        }
    }
}

// MARK: - Sigil Seal View

private struct SigilOverlay: View {
    let moment: KaiMoment

    var body: some View {
        GeometryReader { geo in
            let S = min(geo.size.width, geo.size.height)
            let C = CGPoint(x: geo.size.width/2, y: geo.size.height/2)
            let a = 3 + (moment.stepIndexInDay % 5)
            let b = 2 + ((moment.stepIndexInDay / 5) % 5)
            let δ = Double((moment.kai.beat % 8)) * (Double.pi/8)

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
            .overlay(
                VStack(spacing: 4) {
                    Text("Seal").font(.system(size: 11, weight: .semibold))
                    Text("pulse μ\(KKS.microPulsesSinceGenesis(moment.date)) • \(moment.kai.chakraStepString)")
                        .font(.system(.caption2, design: .monospaced)).opacity(0.85)
                }
                .padding(6)
                .background(kaiHex("#041019").opacity(0.76), in: Capsule())
                .overlay(Capsule().stroke(kaiHex("#7ff7ff").opacity(0.35), lineWidth: 1))
                .padding(.top, 6)
                , alignment: .top
            )
        }
    }
}

// MARK: - Live/Scrub chip

private struct ModeChip: View {
    let isScrubbing: Bool
    let text: String
    var body: some View {
        HStack(spacing: 6) {
            HarmonicGlyph(size: 12, thick: 1.5).frame(width: 14, height: 14)
            Text(text).font(.footnote.weight(.semibold))
        }
        .padding(.vertical, 6).padding(.horizontal, 10)
        .background(kaiHex("#06121a").opacity(0.75), in: Capsule())
        .overlay(Capsule().stroke(kaiHex("#7fdfff").opacity(0.28), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
        .accessibilityLabel(isScrubbing ? "Scrubbing with Digital Crown" : "Live mode")
    }
}

private struct HarmonicGlyph: View {
    let size: CGFloat
    let thick: CGFloat
    var body: some View {
        ZStack {
            Circle().stroke(lineWidth: thick)
            Path { p in
                p.addArc(center: CGPoint(x: size/2, y: size/2), radius: size*0.28, startAngle: .degrees(0), endAngle: .degrees(300), clockwise: false)
            }.stroke(style: StrokeStyle(lineWidth: thick, lineCap: .round))
        }
        .foregroundStyle(kaiHex("#7ff7ff"))
        .frame(width: size, height: size)
    }
}

// MARK: - Buttons / Toolbar

private struct HarmonicButton: View {
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .padding(.vertical, 6).padding(.horizontal, 10)
                .background(kaiHex("#0a1b24"), in: Capsule())
                .overlay(Capsule().stroke(kaiHex("#7fdfff").opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct HarmonicToggle: View {
    let title: String
    let isOn: Bool
    let toggle: () -> Void
    var body: some View {
        Button(action: toggle) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .padding(.vertical, 6).padding(.horizontal, 10)
                .background(isOn ? kaiHex("#002b38") : kaiHex("#0a1b24"), in: Capsule())
                .overlay(Capsule().stroke(kaiHex("#7fdfff").opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct BottomToolbarWatch: View {
    let breath: Double
    let leftView: AnyView
    let rightView: AnyView
    @State private var on = false
    var body: some View {
        HStack(spacing: 10) {
            ZStack { breathingHalo(on: on, breath: breath); leftView }
            ZStack { breathingHalo(on: on, breath: breath); rightView }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(kaiHex("#06121a").opacity(0.7), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
        .frame(maxWidth: .infinity)
        .onAppear {
            withAnimation(.easeInOut(duration: breath).repeatForever(autoreverses: true)) { on = true }
        }
    }
    private func breathingHalo(on: Bool, breath: Double) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(
                RadialGradient(colors: [.cyan.opacity(on ? 0.18 : 0.08),
                                        .blue.opacity(on ? 0.08 : 0.04),
                                        .clear],
                               center: .center, startRadius: 0, endRadius: 90)
            )
            .blur(radius: 8)
            .frame(width: 52, height: 52)
            .allowsHitTesting(false)
    }
}

// MARK: - Background (breath-periodic, GPU-friendly)

private struct AtlanteanBackgroundWatch: View {
    let breath: Double
    let lightMode: Bool
    let reduceMotion: Bool
    var body: some View {
        ZStack {
            LinearGradient(
                colors: lightMode
                ? [kaiHex("#eaf7ff"), kaiHex("#d8eefc"), kaiHex("#cde7fb")]
                : [kaiHex("#05090f"), kaiHex("#0e1b22"), kaiHex("#0c2231")],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            TimelineView(.periodic(from: .now, by: max(0.12, breath / 11.0))) { t in
                AtlanteanCanvasWatch(
                    time: t.date.timeIntervalSinceReferenceDate,
                    breath: breath,
                    lightMode: lightMode,
                    reduceMotion: reduceMotion
                )
            }
            .ignoresSafeArea()
        }
    }
}

private struct AtlanteanCanvasWatch: View {
    let time: TimeInterval
    let breath: Double
    let lightMode: Bool
    let reduceMotion: Bool
    var body: some View {
        Canvas { ctx, size in
            let W = size.width, H = size.height
            let C = CGPoint(x: W/2, y: H/2)

            let phi = max(0.001, breath)
            let t1 = time.truncatingRemainder(dividingBy: phi) / phi
            let t2 = time.truncatingRemainder(dividingBy: phi * 2) / (phi * 2)
            let wave  = (reduceMotion ? 0.25 : 0.5) * sin(t1 * 2 * .pi) + 0.5
            let wave2 = (reduceMotion ? 0.25 : 0.5) * sin(t2 * 2 * .pi + .pi/3) + 0.5

            blob(&ctx, center: CGPoint(x: C.x, y: H * 0.22),
                 baseR: max(W, H) * 0.52, color: lightMode ? kaiHex("#6ec3ff") : kaiHex("#00ffff"),
                 blur: 20, alpha: lightMode ? 0.58 : 0.85, phase: wave)
            blob(&ctx, center: CGPoint(x: W * 0.22, y: H * 0.38),
                 baseR: max(W, H) * 0.40, color: lightMode ? kaiHex("#a9b8ff") : kaiHex("#7000ff"),
                 blur: 16, alpha: lightMode ? 0.50 : 0.75, phase: wave)
            blob(&ctx, center: CGPoint(x: W * 0.78, y: H * 0.36),
                 baseR: max(W, H) * 0.40, color: lightMode ? kaiHex("#77c7ff") : kaiHex("#00a0ff"),
                 blur: 16, alpha: lightMode ? 0.50 : 0.75, phase: wave)

            let rr = max(W, H) * CGFloat(0.40 + 0.04 * wave)
            var ring = Path()
            ring.addEllipse(in: CGRect(x: C.x - rr, y: C.y - rr, width: rr*2, height: rr*2))
            ctx.addFilter(.blur(radius: 8))
            ctx.stroke(ring, with: .color((lightMode ? Color.black : Color.cyan).opacity(0.12)), lineWidth: 1.5)

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
                    with: .color((lightMode ? Color.black : Color.white).opacity(0.10 + 0.28 * (1 - k)))
                )
            }
        }
    }
    private func blob(_ ctx: inout GraphicsContext,
                      center: CGPoint, baseR: CGFloat,
                      color: Color, blur: CGFloat, alpha: Double, phase: Double) {
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

// MARK: - Simple sheets

private struct WeekKalendarWatchSheet: View {
    var body: some View {
        VStack(spacing: 8) {
            HarmonicGlyph(size: 20, thick: 2)
            Text("Week Kalendar").font(.headline)
            Text("Watch-optimized week view coming here.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding()
    }
}

private struct EternalKlockWatchView: View {
    let moment: KaiMoment
    let breath: Double
    var body: some View {
        ZStack {
            LinearGradient(colors: [.black, kaiHex("#02040a")], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 10) {
                KaiDialView(moment: moment, breath: breath, glowSize: 220, lightMode: false)
                    .frame(width: 190, height: 190)
                Text(moment.kai.sealText)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(kaiHex("#07131a").opacity(0.8), in: Capsule())
                Text("Day \(moment.kai.dayOfMonth) of Month \(moment.kai.monthIndex1) — \(moment.kai.weekday.rawValue)")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding()
        }
    }
}

private struct ModeSheet: View {
    @Binding var mode: HarmonicMode
    @Binding var customHz: Double
    var onApply: () -> Void
    var body: some View {
        VStack(spacing: 10) {
            Text("Harmonic Mode").font(.headline)
            ForEach(HarmonicMode.allCases, id: \.self) { m in
                Button {
                    mode = m
                } label: {
                    HStack {
                        Text(m.rawValue).font(.system(size: 14, weight: .semibold))
                        Spacer()
                        if mode == m { HarmonicGlyph(size: 14, thick: 2).foregroundStyle(kaiHex("#7ff7ff")) }
                    }
                    .padding(8)
                    .background(kaiHex("#08141b"), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }.buttonStyle(.plain)
            }
            if mode == .custom {
                HStack {
                    Text("Hz").font(.system(size: 13, weight: .semibold))
                    Slider(value: $customHz, in: 110...1760, step: 1)
                    Text("\(Int(customHz))").font(.system(.footnote, design: .monospaced))
                }.padding(.horizontal, 8)
            }
            HarmonicButton(label: "Apply") { onApply() }
        }
        .padding()
    }
}

// MARK: - First-run Tips Overlay

private struct TipsOverlay: View {
    var onDismiss: () -> Void
    var body: some View {
        VStack(spacing: 8) {
            Text("Welcome to KaiKlok")
                .font(.headline)
            Text("• Double-tap the dial to show the Seal overlay.\n• Long-press the dial to capture a sealed moment.\n• Tap “Live/Scrub” chip to preview with the Digital Crown.")
                .font(.system(.footnote))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button(action: onDismiss) {
                Text("Got it").font(.system(size: 13, weight: .semibold))
                    .padding(.vertical, 6).padding(.horizontal, 14)
                    .background(kaiHex("#0a1b24"), in: Capsule())
            }.buttonStyle(.plain)
        }
        .padding(12)
        .background(kaiHex("#06121a").opacity(0.9), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(kaiHex("#7fdfff").opacity(0.3), lineWidth: 1))
        .padding()
        .transition(.opacity)
    }
}
