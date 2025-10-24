//  HarmonicPlayerView.swift
//  KaiKlok
//
//  MASTER v22.1+ — “Φ-Shell 21 — Stabilized Fib Banks (KKS v1)”
//  Upgrades:
//  - Randomized initial phases (all oscillators) to reduce alignment artifacts
//  - Denormal protection on amp (>= 1e-6)
//  - Global dynamic energy normalization across ALL voices (≤ MAX_TOTAL_GAIN)
//  - Buffer size 1597 → 2048 to ease scheduling & underruns
//  - Wet/Delay/Feedback 1-pole smoothing to prevent parameter jumps
//  - Output safety gain: outputMixer ≤ 0.88 (with internal limiter present)
//  - HRV × Breath AM clamped to [0.90, 1.10] (applied to AM only; gate preserved)
//  - Shell spread: ±0.5% per-shell detune to avoid harmonic collapse
//
//  Project → Signing & Capabilities → Background Modes → check “Audio, AirPlay, and Picture in Picture”.
//  Info.plist → UIBackgroundModes = [ audio ]
//

import SwiftUI
import AVFoundation
import Accelerate
import Combine
import UIKit
import ObjectiveC
import QuartzCore
import AudioToolbox
import CoreMotion
import CoreHaptics
import simd

// ─────────────────────────────────────────────────────────────────────────────
// Constants • Golden breath, caps, psychoacoustics
// ─────────────────────────────────────────────────────────────────────────────

private let PHI  = (1.0 + sqrt(5.0)) / 2.0
private let PHI2 = PHI * PHI
private let PHIf = Float(PHI)
private let PHI2f = PHIf * PHIf

// KKS v1 — exact Golden Breath (no rounding): 3 + √5
private let BREATH_SEC: Double = 3.0 + sqrt(5.0)    // 5.23606797749979...

// Exact HRV coherence from φ-breath
private let HRV_COHERENCE_HZ: Double  = 1.0 / BREATH_SEC
private let HRV_COHERENCE_RAD: Double = 2.0 * .pi * HRV_COHERENCE_HZ

// Voicing: subtle modulation depths
private let HRV_COHERENCE_DEPTH: Float = 0.02
private let BREATH_RIPPLE_DEPTH: Float = 0.04

// Cadence & caps (silence count per user request = 19)
private let BREATHS_PER_SILENCE: Int = 19
private let MASTER_MAX_GAIN: Float = 0.90           // keep constant; we cap outputMixer below
private let MAX_TOTAL_GAIN: Float = 0.88            // total energy cap across ALL oscillators
private let FB_MAX_GAIN: Float = 0.08
private let WET_CAP: Float = 0.28
private let IR_SCALE: Float = 0.33
private let LOWPASS_THRESH: Double = 48_000
private let LOWPASS_FREQ: Float = 18_000
private let ONRAMP_BREATHS = 3

// On-ramp: φ-decay in tempo and depth (breath-synced envelopes settle quickly)
private let ONRAMP_BEAT0: Double = 8.0
private let ONRAMP_BEATS: [Double] = [ONRAMP_BEAT0,
                                      ONRAMP_BEAT0/PHI,
                                      ONRAMP_BEAT0/PHI2]
private let ONRAMP_DEPTH0: Float = 0.216
private let ONRAMP_DEPTHS: [Float] = [ONRAMP_DEPTH0,
                                      ONRAMP_DEPTH0/PHIf,
                                      ONRAMP_DEPTH0/PHI2f]

// Harmonic bank depth
private let FIB_DEPTH: Int = 21

// Micro φ-drift
private let MICRO_PHI_DRIFT_PPM: Double = 40

private let ENABLE_BOUNDARY_CHIME = false

extension Notification.Name {
    static let kaiBreathBoundary = Notification.Name("kai-breath-boundary")
}

// Presets
private let phrasePresets: [String:(reverb:Int, delay:Int)] = [
    "Shoh Mek":        (13, 8),
    "Mek Ka":          (21, 13),
    "Ka Lah Mah Tor":  (34, 21),
    "Lah Mah Tor Rah": (55, 34),
    "Tha Voh Yah Zu":  (89, 55),
    "Zor Shoh Mek Ka": (8,  5),
    "Rah Voh Lah":     (21, 13),
    "Kai Leh Shoh":    (34, 21),
    "Zeh Mah Kor Lah": (55, 34),
]
private let spiralPresets: [(min:Int, max:Int, reverb:Int, delay:Int)] = [
    (13, 21, 3, 2), (21, 34, 5, 3), (34, 55, 8, 5), (55, 89, 13, 8),
    (89, 144, 21, 13), (144, 233, 34, 21), (233, 377, 55, 34)
]

// Helpers
private func fibonacci(_ n: Int) -> [Int] {
    guard n > 0 else { return [] }
    var s = [1, 1]
    if n <= 2 { return Array(s.prefix(n)) }
    for i in 2..<n { s.append(s[i-1] + s[i-2]) }
    return s
}
private func presetFor(_ f: Double, phrase: String?) -> (reverb:Int, delay:Int) {
    if let p = phrase, let v = phrasePresets[p] { return v }
    if let b = spiralPresets.first(where: { f >= Double($0.min) && f <= Double($0.max) }) {
        return (b.reverb, b.delay)
    }
    return (3, 2)
}

// Kai dynamic reverb (time: φ-cycle = 13 breaths) — breath & KKS time aware
private func kaiDynamicReverb(freq: Double, phrase: String, kaiTime: Double, breathPhase: Double) -> Float {
    let freqNorm = min(1.0, log(freq + 1.0) / log(377.0))
    let phraseRv = (phrasePresets[phrase]?.reverb ?? presetFor(freq, phrase: phrase).reverb)
    let phraseNorm = min(1.0, Double(phraseRv) / 89.0)

    let stepDuration = BREATH_SEC * 13.0
    let kaiNorm = (kaiTime.truncatingRemainder(dividingBy: stepDuration)) / stepDuration
    let breathNorm = (sin(breathPhase * 2 * .pi) + 1) / 2

    let wPhrase = PHI, wFreq = 1.0, wBreath = 1.0/PHI, wKai = 1.0/PHI2
    let weightSum = wPhrase + wFreq + wBreath + wKai

    var blended = (phraseNorm * wPhrase + freqNorm * wFreq + breathNorm * wBreath + kaiNorm * wKai) / weightSum
    let sigmoid = 1.0 / (1.0 + exp(-6.0 * (blended - 0.5)))
    blended = (sigmoid * 0.55) + (sqrt(blended) * 0.45)
    let wet = min(Double(WET_CAP) * 0.995, max(0.021, blended * Double(WET_CAP))) // min ~ 2.1%
    return Float(wet)
}

// Inverse delay (clarity guard) — min 21ms (Fib), breath-aware via wet
private func autoDelaySeconds(freq: Double, phrase: String, wet: Float) -> Double {
    let basePreset = phrasePresets[phrase]?.delay ?? presetFor(freq, phrase: phrase).delay
    let baseSeconds = min(Double(basePreset) * 0.01, 1.25)
    let wetRatio = Double(wet / WET_CAP)
    let factor = sqrt(max(0.0, 1.0 - wetRatio))
    return max(0.021, min(baseSeconds * (0.5 + factor), 1.25))
}

// ─────────────────────────────────────────────────────────────────────────────
// HarmonicEngine — Divine φ-Shell 13 (head-tracked Spatial Audio)
// ─────────────────────────────────────────────────────────────────────────────

final class HarmonicEngine: ObservableObject, @unchecked Sendable {
    // Public state for UI
    @Published var isPlaying = false
    @Published var actualSampleRate: Double = 0
    @Published var autoWet: Float = 0
    @Published var userWet: Float = 0

    // Config
    var frequency: Double = 144
    var phrase: String = "Shoh Mek"
    var binaural: Bool = true

    // Audio objects
    private let engine = AVAudioEngine()
    private let environment = AVAudioEnvironmentNode()

    // 3D voices: 2 cores + 11-point Fibonacci shell (total 13)
    private enum VoiceKind { case coreL, coreR, shell(Int) }
    private struct Osc { var freq: Double; var amp: Float; var phase: Double }
    private struct Voice {
        let kind: VoiceKind
        let node: AVAudioPlayerNode
        var oscs: [Osc] = []
        var bufferA: AVAudioPCMBuffer?
        var bufferB: AVAudioPCMBuffer?
        var useA: Bool = true
        var gain: Float = 1.0
        var basePos: AVAudio3DPoint = .init(x: 0, y: 0, z: 0)
    }
    private var voices: [Voice] = []

    // Mix / FX nodes (post-environment)
    private let dryMixer = AVAudioMixerNode()
    private let wetMixer = AVAudioMixerNode()
    private let eqTilt = AVAudioUnitEQ(numberOfBands: 5)
    private let reverb = AVAudioUnitReverb()
    private let delay = AVAudioUnitDelay()
    private let wetSumMixer = AVAudioMixerNode()
    private let lowpass = AVAudioUnitEQ(numberOfBands: 1)
    private let entrainGate = AVAudioMixerNode()
    private let highpass = AVAudioUnitEQ(numberOfBands: 1)

    // Dynamics & Limiter
    private let dynamics: AVAudioUnitEffect = {
        let desc = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_DynamicsProcessor,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        return AVAudioUnitEffect(audioComponentDescription: desc)
    }()
    private let peakLimiter: AVAudioUnitEffect = {
        let desc = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_PeakLimiter,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        return AVAudioUnitEffect(audioComponentDescription: desc)
    }()
    private let outputMixer = AVAudioMixerNode()

    // Early reflections
    private var tapDelays: [AVAudioUnitDelay] = []
    private var tapGains:  [AVAudioMixerNode] = []

    // Visualizer tap
    private let tapBus = 0
    private let tapBufferSize: AVAudioFrameCount = 1024
    @Published var waveform: [Float] = Array(repeating: 0, count: 512)

    // Timing
    private var tickTimer: DispatchSourceTimer?
    private let tickHz: Double = 60.0

    // Breath / onramp
    private var breathAnchor: CFTimeInterval = 0
    private var breathPeriod: Double = BREATH_SEC
    private var boundaryIndex = 0
    private var silenceCounter = 0
    private var onrampStage = 0
    private var onrampActive = true
    private var gatePhase: Double = 0
    private var gateBeat: Double = ONRAMP_BEATS[0]
    private var gateDepth: Float = ONRAMP_DEPTHS[0]
    private var gateBase: Float = (1.0 as Float) - ONRAMP_DEPTHS[0]

    // LFOs / gains
    private var halfBeat: Double = 0
    private var baseFeedback: Float = min(0.18, FB_MAX_GAIN)
    private var baseWet: Float = 0
    private var baseDelay: Double = 0
    private var kaiTimeRef: Double = 0

    // Smoothing (1-pole)
    private var smWet: Float = 0
    private var smDelay: Double = 0
    private var smFeedback: Float = 0
    private let smoothTauWet: Double = 0.25
    private let smoothTauDelay: Double = 0.25
    private let smoothTauFeedback: Double = 0.20

    // Extras
    private var microDriftSign: Double = 1.0

    // Interruption
    private var wasPlayingBeforeInterruption = false

    // Haptics
    private let haptic: UIImpactFeedbackGenerator? = {
        if #available(iOS 13.0, *),
           CHHapticEngine.capabilitiesForHardware().supportsHaptics {
            return UIImpactFeedbackGenerator(style: .light)
        }
        return nil
    }()

    // Queues
    private let paramQueue = DispatchQueue(label: "harmonic.params", qos: .userInitiated)
    private let scheduleQueue = DispatchQueue(label: "harmonic.schedule", qos: .userInitiated)

    // Motion → world-locked listener orientation
    private let motion = CMMotionManager()

    // Background task
    private var bgTask: UIBackgroundTaskIdentifier = .invalid

    deinit {
        stopTickLoop()
        outputMixer.removeTap(onBus: tapBus)
        engine.stop()
        motion.stopDeviceMotionUpdates()
        endBackgroundTask()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    init() {
        buildGraph()
        configureSession()
        installVisualizerTap()
        observeInterruptions()
    }

    // MARK: Graph
    private func buildGraph() {
        engine.attach(environment)
        engine.attach(dryMixer)
        engine.attach(wetMixer)
        engine.attach(eqTilt)
        engine.attach(reverb)
        engine.attach(delay)
        engine.attach(lowpass)
        engine.attach(wetSumMixer)
        engine.attach(entrainGate)
        engine.attach(highpass)
        engine.attach(dynamics)
        engine.attach(peakLimiter)
        engine.attach(outputMixer)

        environment.reverbParameters.enable = false
        environment.distanceAttenuationParameters.referenceDistance = 1.0
        if #available(iOS 14.0, *) { environment.outputType = .headphones }
        environment.listenerPosition = AVAudio3DPoint(x: 0, y: 0, z: 0)

        // Build & attach 13 voices
        voices = makeVoices13()
        for i in voices.indices {
            engine.attach(voices[i].node)
            let sr = max(AVAudioSession.sharedInstance().sampleRate, 48_000)
            let fmt = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)!
            engine.connect(voices[i].node, to: environment, format: fmt)

            // FIX: direct protocol cast (no optional) — AVAudioPlayerNode conforms to AVAudio3DMixing
            let m = voices[i].node as AVAudio3DMixing
            m.renderingAlgorithm = .HRTF
            if #available(iOS 14.0, *) { m.sourceMode = .spatializeIfMono }
            m.obstruction = 0
            m.occlusion = 0
            m.reverbBlend = 0
        }

        // Environment → [dry, wet]
        engine.connect(environment, to: dryMixer, format: nil)
        engine.connect(environment, to: wetMixer, format: nil)

        // Wet chain → wetSum
        delay.wetDryMix = 100
        delay.feedback = 0
        delay.lowPassCutoff = 18_000
        reverb.wetDryMix = 100
        reverb.loadFactoryPreset(.largeHall2)

        engine.connect(wetMixer, to: eqTilt, format: nil)
        engine.connect(eqTilt,   to: reverb, format: nil)
        engine.connect(reverb,   to: delay,  format: nil)
        engine.connect(delay,    to: wetSumMixer, format: nil)

        // Early taps (3, 5, 8, 13, 21, 34 ms) with φ^-n gain law
        installEarlyTaps(splitFrom: wetMixer, sumInto: wetSumMixer)

        // EQ tilt (φ centers)
        let centers: [Float] = [144, 233, 377, 610, 987]
        for (idx, band) in eqTilt.bands.enumerated() {
            band.bypass = false
            band.filterType = .parametric
            band.frequency = centers[idx]
            band.bandwidth = Float(0.9)
            band.gain = Float((idx % 2 == 0) ? 0.6 : -0.6)
        }

        // Lowpass for low-SR devices
        let lp = lowpass.bands[0]
        lp.bypass = true
        lp.filterType = .lowPass
        lp.frequency = LOWPASS_FREQ
        lp.bandwidth = Float(0.707)
        lp.gain = 0

        // Sum to entrain gate
        engine.connect(dryMixer,    to: entrainGate, format: nil)
        engine.connect(wetSumMixer, to: entrainGate, format: nil)

        // Post: HP → Dynamics → PeakLimiter → Output → Main
        let hp = highpass.bands[0]
        hp.bypass = false
        hp.filterType = .highPass
        hp.frequency = 21 // Fib
        hp.bandwidth = Float(0.707)
        hp.gain = 0

        if let t = dynamics.auAudioUnit.parameterTree {
            t.parameter(withAddress: AUParameterAddress(kDynamicsProcessorParam_Threshold))?.value      = -9.0
            t.parameter(withAddress: AUParameterAddress(kDynamicsProcessorParam_HeadRoom))?.value       = 24.0
            t.parameter(withAddress: AUParameterAddress(kDynamicsProcessorParam_ExpansionRatio))?.value = 1.0
            t.parameter(withAddress: AUParameterAddress(kDynamicsProcessorParam_AttackTime))?.value     = 0.00618
            t.parameter(withAddress: AUParameterAddress(kDynamicsProcessorParam_ReleaseTime))?.value    = 0.0618
            t.parameter(withAddress: AUParameterAddress(kDynamicsProcessorParam_OverallGain))?.value    = 3.0
        }
        if let pt = peakLimiter.auAudioUnit.parameterTree {
            pt.parameter(withAddress: 0 /* kLimiterParam_AttackTime */)?.value  = 0.00618
            pt.parameter(withAddress: 1 /* kLimiterParam_DecayTime  */)?.value  = 0.0618
            pt.parameter(withAddress: 2 /* kLimiterParam_PreGain    */)?.value  = -1.618
        }

        engine.connect(entrainGate, to: highpass,    format: nil)
        engine.connect(highpass,    to: dynamics,    format: nil)
        engine.connect(dynamics,    to: peakLimiter, format: nil)
        engine.connect(peakLimiter, to: outputMixer, format: nil)
        engine.connect(outputMixer, to: engine.mainMixerNode, format: nil)

        engine.mainMixerNode.outputVolume = 1.0
        dryMixer.outputVolume = 1.0
        wetMixer.outputVolume = 0.0 // set by applyWet()
        entrainGate.outputVolume = 1.0
        // Safety gain: cap to 0.88 even if MASTER_MAX_GAIN is higher
        outputMixer.outputVolume = min(MASTER_MAX_GAIN, 0.88)
    }

    private func makeVoices13() -> [Voice] {
        var list: [Voice] = []
        list.append(Voice(kind: .coreL, node: AVAudioPlayerNode(), gain: 0.36))
        list.append(Voice(kind: .coreR, node: AVAudioPlayerNode(), gain: 0.36))
        for i in 0..<11 { list.append(Voice(kind: .shell(i), node: AVAudioPlayerNode(), gain: 0.12)) }
        return list
    }

    private func installEarlyTaps(splitFrom wetInput: AVAudioNode, sumInto wetSum: AVAudioMixerNode) {
        for d in tapDelays { engine.detach(d) }
        for g in tapGains  { engine.detach(g) }
        tapDelays.removeAll(); tapGains.removeAll()

        let tapsSec: [Double] = [0.003, 0.005, 0.008, 0.013, 0.021, 0.034]
        for (i, t) in tapsSec.enumerated() {
            let d = AVAudioUnitDelay()
            d.wetDryMix = 100; d.feedback = 0; d.lowPassCutoff = 18_000; d.delayTime = t
            let g = AVAudioMixerNode()
            g.outputVolume = pow(1.0 / PHIf, Float(i + 1)) * IR_SCALE
            engine.attach(d); engine.attach(g)
            engine.connect(wetInput, to: d, format: nil)
            engine.connect(d, to: g, format: nil)
            engine.connect(g, to: wetSum, format: nil)
            tapDelays.append(d); tapGains.append(g)
        }
    }

    // MARK: Session / Interruptions
    private func configureSession() {
        let sess = AVAudioSession.sharedInstance()
        if #available(iOS 16.0, *) {
            do {
                try sess.setCategory(.playback, mode: .default, policy: .longFormAudio,
                                     options: [.mixWithOthers, .allowBluetoothA2DP, .allowAirPlay])
            } catch {
                try? sess.setCategory(.playback, mode: .default,
                                      options: [.mixWithOthers, .allowBluetoothA2DP, .allowAirPlay])
            }
        } else {
            try? sess.setCategory(.playback, mode: .default,
                                  options: [.mixWithOthers, .allowBluetoothA2DP, .allowAirPlay])
        }
        try? sess.setPreferredSampleRate(96_000)
        try? sess.setPreferredIOBufferDuration(0.005)
        do { try sess.setActive(true) } catch { print("AVAudioSession activation failed: \(error)") }

        let sr = sess.sampleRate
        self.actualSampleRate = sr > 0 ? sr : 48_000
    }

    private func observeInterruptions() {
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let self = self,
                  let info = note.userInfo,
                  let typeVal = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeVal) else { return }
            switch type {
            case .began:
                self.wasPlayingBeforeInterruption = self.isPlaying
                if self.wasPlayingBeforeInterruption { self.pauseInternal() }
            case .ended:
                let opts = (info[AVAudioSessionInterruptionOptionKey] as? UInt).map { AVAudioSession.InterruptionOptions(rawValue: $0) } ?? []
                if self.wasPlayingBeforeInterruption, opts.contains(.shouldResume) { self.resumeInternal() }
            @unknown default: break
            }
        }
        NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.configureSession()
        }
    }

    private func installVisualizerTap() {
        outputMixer.removeTap(onBus: tapBus)
        outputMixer.installTap(onBus: tapBus, bufferSize: tapBufferSize, format: nil) { [weak self] buffer, _ in
            guard let self = self, let ch = buffer.floatChannelData else { return }
            let n = Int(buffer.frameLength)
            let mono = UnsafeBufferPointer(start: ch[0], count: n)
            let target = max(1, self.waveform.count)
            let stride = max(1, n / target)
            var out: [Float] = []; out.reserveCapacity(target)
            var i = 0; while i < n && out.count < target { out.append(mono[i]); i += stride }
            if out.count < target { out.append(contentsOf: repeatElement(0, count: target - out.count)) }
            DispatchQueue.main.async { self.waveform = out }
        }
    }

    // MARK: Public controls
    func play(frequency: Double, phrase: String, binaural: Bool) {
        guard !isPlaying else { return }
        self.frequency = frequency
        self.phrase = phrase
        self.binaural = binaural

        self.actualSampleRate = {
            let sr = AVAudioSession.sharedInstance().sampleRate
            return sr > 0 ? sr : 48_000
        }()

        lowpass.bands[0].bypass = !(actualSampleRate < LOWPASS_THRESH)

        let dyn = dynamicHarmonicSpec(for: frequency) // fixed: (21, 13)
        halfBeat = binaural ? Double(dyn.offset) / 2.0 : 0.0 // 6.5 Hz if enabled

        microDriftSign = Bool.random() ? 1.0 : -1.0

        buildVoiceBanks()
        assignBasePositions()

        Task { [weak self] in
            await self?.primeKaiTimeAndAlignStart()
        }

        // exact KKS breath timing
        breathPeriod = BREATH_SEC
        breathAnchor = CACurrentMediaTime()
        boundaryIndex = 0
        silenceCounter = 0

        onrampActive = true
        onrampStage = 0
        gateBeat = ONRAMP_BEATS[0]
        gateDepth = ONRAMP_DEPTHS[0]
        gateBase = (1.0 as Float) - gateDepth
        gatePhase = 0

        let wet = kaiDynamicReverb(freq: frequency, phrase: phrase, kaiTime: kaiTimeRef, breathPhase: 0)
        let dly = autoDelaySeconds(freq: frequency, phrase: phrase, wet: wet)
        baseWet = wet; baseDelay = dly
        // init smoothing baselines
        smWet = (userWet == 0) ? baseWet : userWet
        smDelay = baseDelay
        smFeedback = baseFeedback

        applyWet(smWet)
        applyDelay(smDelay)
        applyFeedback(smFeedback)

        do {
            engine.prepare()
            try engine.start()
            isPlaying = true
        } catch {
            print("Engine start error: \(error)")
            isPlaying = false
            return
        }

        startPlayersScheduling()
        startMotion()

        beginBackgroundTask()
        UIApplication.shared.isIdleTimerDisabled = true

        haptic?.prepare()
        startTickLoop()
    }

    func stop() {
        guard isPlaying else { return }
        isPlaying = false
        stopTickLoop()
        for v in voices { v.node.stop() }
        motion.stopDeviceMotionUpdates()
        engine.pause()
        engine.stop()
        endBackgroundTask()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func setUserWet(_ wet: Float) {
        userWet = min(wet, WET_CAP)
        // Immediate feel for UI; smoothing will take over on ticks
        smWet = userWet
        applyWet(smWet)
        smDelay = autoDelaySeconds(freq: frequency, phrase: phrase, wet: smWet)
        applyDelay(smDelay)
    }

    func updatePhrase(_ phrase: String) {
        self.phrase = phrase
        let freqSnapshot = self.frequency
        let kaiSnapshot  = self.kaiTimeRef
        paramQueue.async {
            let wet = kaiDynamicReverb(freq: freqSnapshot, phrase: phrase, kaiTime: kaiSnapshot, breathPhase: 0)
            let d = autoDelaySeconds(freq: freqSnapshot, phrase: phrase, wet: wet)
            DispatchQueue.main.async {
                self.baseWet = wet
                self.autoWet = wet
                // FIX: actually use computed delay to avoid unused-value warning
                self.baseDelay = d
                // smDelay target will naturally converge via tick() smoothing
            }
        }
    }

    // MARK: Internals (pause/resume for interruptions)
    private func pauseInternal() {
        guard isPlaying else { return }
        engine.pause()
    }
    private func resumeInternal() {
        guard isPlaying else { return }
        do { try engine.start() } catch { print("Engine resume error: \(error)") }
    }

    // MARK: Parameters / helpers
    private func applyWet(_ wet: Float) {
        let w = min(wet, WET_CAP)
        wetMixer.outputVolume = w
        dryMixer.outputVolume = 1.0 - w
    }
    private func applyDelay(_ seconds: Double) {
        delay.delayTime = max(0.021, min(seconds, 1.25))
    }
    private func applyFeedback(_ f: Float) {
        delay.feedback = min(f, FB_MAX_GAIN) * 100.0
    }

    // Fixed φ/Fib spec: depth = 21, binaural offset = 13
    private func dynamicHarmonicSpec(for _: Double) -> (harmonics:Int, offset:Int) {
        return (FIB_DEPTH, 13)
    }

    private func buildVoiceBanks() {
        func makeBank(baseFreq: Double, gainScale: Float) -> [Osc] {
            var oscs: [Osc] = []

            // Full Fibonacci sets for both sides
            let fibs = fibonacci(FIB_DEPTH)

            // φ^-k weighting normalized per side; split total gain equally
            let weights: [Float] = (0..<fibs.count).map { pow(1.0/PHIf, Float($0 + 1)) }
            let wSum = max(1e-6, weights.reduce(0, +))

            // Micro φ-drift
            let ppm = MICRO_PHI_DRIFT_PPM * microDriftSign
            let drift = 1.0 + (ppm / 1_000_000.0)

            // Overtones (× Fib) — RANDOMIZED INITIAL PHASE + DENORMAL CLAMP
            for (i, n) in fibs.enumerated() {
                let f = baseFreq * Double(n) * drift
                if f < actualSampleRate/2 {
                    let raw = (weights[i] / wSum) * (MAX_TOTAL_GAIN / 2) * gainScale
                    let amp = max(1e-6, raw)
                    let phase = Double.random(in: 0..<1.0)
                    oscs.append(Osc(freq: f, amp: amp, phase: phase))
                }
            }

            // Undertones (÷ Fib) — RANDOMIZED INITIAL PHASE + DENORMAL CLAMP
            for (i, n) in fibs.enumerated() {
                let f = baseFreq / Double(n) * drift
                if f > 20 { // keep >20 Hz
                    let raw = (weights[i] / wSum) * (MAX_TOTAL_GAIN / 2) * gainScale
                    let amp = max(1e-6, raw)
                    let phase = Double.random(in: 0..<1.0)
                    oscs.append(Osc(freq: f, amp: amp, phase: phase))
                }
            }
            return oscs
        }

        for i in voices.indices {
            switch voices[i].kind {
            case .coreL:
                let base = frequency - halfBeat
                voices[i].oscs = makeBank(baseFreq: base, gainScale: voices[i].gain)
            case .coreR:
                let base = frequency + halfBeat
                voices[i].oscs = makeBank(baseFreq: base, gainScale: voices[i].gain)
            case .shell(let k):
                // φ radial detune across shell + ±0.5% random spread
                let phiShift = pow(PHI, Double(k-5) / 7.0)
                let detune = 1.0 + Double.random(in: -0.005...0.005)
                var bank = makeBank(baseFreq: frequency * phiShift * detune, gainScale: voices[i].gain * 0.72)
                for j in bank.indices { bank[j].amp *= 0.75 } // clarity
                voices[i].oscs = bank
            }
        }

        // GLOBAL ENERGY NORMALIZATION + DENORMAL PROTECT
        normalizeGlobalEnergyAndProtectDenormals()
    }

    private func normalizeGlobalEnergyAndProtectDenormals() {
        var total: Double = 0
        for i in voices.indices {
            for j in voices[i].oscs.indices {
                let a = max(1e-6, Double(voices[i].oscs[j].amp))
                voices[i].oscs[j].amp = Float(a)
                total += a
            }
        }
        if total > Double(MAX_TOTAL_GAIN) {
            let scale = Float(Double(MAX_TOTAL_GAIN) / total)
            for i in voices.indices {
                for j in voices[i].oscs.indices {
                    voices[i].oscs[j].amp *= scale
                }
            }
        }
    }

    // Fibonacci sphere points for 11 shell nodes (radius ~0.25 m)
    private func assignBasePositions() {
        let shellRadius: Float = 0.25
        let n = 11
        var pts: [simd_float3] = []
        let goldenAngle: Float = .pi * (3 - sqrt(5)) // ~2.399
        for i in 0..<n {
            let y = 1 - 2 * Float(i) / Float(n - 1)
            let r = sqrt(max(0, 1 - y*y))
            let theta = goldenAngle * Float(i)
            let x = cos(theta) * r
            let z = sin(theta) * r
            pts.append(simd_float3(x, y * 0.25, z)) // slight vertical squeeze
        }

        for i in voices.indices {
            switch voices[i].kind {
            case .coreL:
                voices[i].basePos = AVAudio3DPoint(x:  0.18, y: 0.02, z:  0.22)
            case .coreR:
                voices[i].basePos = AVAudio3DPoint(x: -0.18, y: 0.02, z:  0.22)
            case .shell(let k):
                let p = pts[k] * shellRadius
                voices[i].basePos = AVAudio3DPoint(x: p.x, y: p.y, z: p.z)
            }
        }
    }

    // Scheduling continuous buffers per voice (double-buffer)
    private func startPlayersScheduling() {
        let sr = actualSampleRate > 0 ? actualSampleRate : 48_000
        let fmt = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1)!
        let framesPerBuffer: AVAudioFrameCount = 2048 // ↑ from 1597 (Fib) → more headroom, fewer underruns

        for i in voices.indices {
            var v = voices[i]
            v.bufferA = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: framesPerBuffer)
            v.bufferB = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: framesPerBuffer)
            v.useA = true
            voices[i] = v
        }

        scheduleQueue.async { [weak self] in
            guard let self = self else { return }
            for i in self.voices.indices {
                self.scheduleNext(for: i, frames: framesPerBuffer, format: fmt)
                self.scheduleNext(for: i, frames: framesPerBuffer, format: fmt)
            }
            for i in self.voices.indices {
                self.voices[i].node.play()
            }
            self.updateVoicePositions(phase: 0)
        }
    }

    private func scheduleNext(for idx: Int, frames: AVAudioFrameCount, format: AVAudioFormat) {
        guard voices.indices.contains(idx) else { return }
        var v = voices[idx]
        guard let buf = (v.useA ? v.bufferA : v.bufferB) else { return }
        v.useA.toggle()
        buf.frameLength = frames
        voices[idx] = v

        guard let ch = buf.floatChannelData?.pointee else { return }
        let sr = format.sampleRate
        let dt = 1.0 / sr
        let twoPi = 2.0 * Double.pi

        let gBeat = gateBeat, gDepth = gateDepth, gBase = gateBase
        var gate = gatePhase

        let t0 = CACurrentMediaTime() - breathAnchor
        let nowPhase = fmod(t0 / breathPeriod, 1.0)
        var hrvPhase: Double = HRV_COHERENCE_RAD * t0
        hrvPhase.formTruncatingRemainder(dividingBy: 2.0 * .pi)
        let hrvStep: Double  = HRV_COHERENCE_RAD / sr

        for f in 0..<Int(frames) {
            gate += gBeat * dt
            if gate > 1 { gate -= 1 }
            let gateOsc  = 0.5 * (1.0 + sin(twoPi * gate))
            let gateGain = gBase + gDepth * Float(gateOsc)

            var sample: Float = 0
            for j in voices[idx].oscs.indices {
                voices[idx].oscs[j].phase += voices[idx].oscs[j].freq / sr
                if voices[idx].oscs[j].phase > 1 { voices[idx].oscs[j].phase -= 1 }
                sample += sinf(Float(twoPi * voices[idx].oscs[j].phase)) * voices[idx].oscs[j].amp
            }

            // AM components
            let breathAM = 1.0 + BREATH_RIPPLE_DEPTH * sinf(Float(twoPi) * (Float(nowPhase) + Float(f) / Float(frames)))
            let hrvAM    = 1.0 + HRV_COHERENCE_DEPTH * Float(sin(hrvPhase))
            // Clamp AM ONLY (not the gate), preserving silence/onramp dynamics
            let amMul    = max(0.90, min(1.10, breathAM * hrvAM))

            ch[f] = sample * gateGain * amMul

            hrvPhase += hrvStep
            if hrvPhase >= 2.0 * .pi { hrvPhase -= 2.0 * .pi }
        }

        gatePhase = gate

        voices[idx].node.scheduleBuffer(buf, at: nil, options: []) { [weak self] in
            guard let self = self, self.isPlaying else { return }
            self.scheduleQueue.async {
                self.scheduleNext(for: idx, frames: frames, format: format)
            }
        }
    }

    // Breath-synced motion of sources (golden angle orbit)
    private func updateVoicePositions(phase: Double) {
        let orbital: Float = 2.0 * .pi / PHI2f
        let dAngle = orbital * 0.33
        let elevBias: Float = 0.02
        let rBreath: Float = 1.0 + 0.1618 * sinf(Float(2.0 * .pi) * Float(phase)) // φ-flavored swell

        for v in voices {
            // FIX: direct protocol cast (no optional) — silences “always succeeds” warning
            let m = v.node as AVAudio3DMixing
            switch v.kind {
            case .coreL, .coreR:
                let base = v.basePos
                let wob = Float(sin(phase * 2.0 * .pi)) * 0.01
                m.position = AVAudio3DPoint(x: base.x + wob, y: base.y, z: base.z)
            case .shell(let k):
                let ang = Float(phase) * dAngle * (1 + Float(k)/11.0)
                let bx = v.basePos.x, by = v.basePos.y, bz = v.basePos.z
                let rx: Float = 0.04 * rBreath, rz: Float = 0.04 * rBreath
                m.position = AVAudio3DPoint(x: bx + cos(ang)*rx, y: by + elevBias * sin(ang*0.5), z: bz + sin(ang)*rz)
            }
        }
    }

    // MARK: Ticker (background-safe) — breath boundary & sacred silence
    private func startTickLoop() {
        stopTickLoop()
        let timer = DispatchSource.makeTimerSource(queue: paramQueue)
        let interval = UInt64((1.0 / tickHz) * 1_000_000_000.0)
        timer.schedule(deadline: .now(), repeating: .nanoseconds(Int(interval)), leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in
            guard let self = self, self.isPlaying else { return }
            self.tick()
        }
        timer.resume()
        tickTimer = timer
    }
    private func stopTickLoop() {
        tickTimer?.setEventHandler {}
        tickTimer?.cancel()
        tickTimer = nil
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let T = breathPeriod
        let idx = Int(floor((now - breathAnchor) / T + 1e-6))
        if idx > boundaryIndex {
            let step = idx - boundaryIndex
            boundaryIndex = idx
            silenceCounter += step
            let tBoundary = breathAnchor + Double(idx) * T
            DispatchQueue.main.async { self.onBoundary(at: tBoundary) }
            if silenceCounter >= BREATHS_PER_SILENCE {
                DispatchQueue.main.async {
                    self.scheduleSacredSilence(at: tBoundary)
                    Task { await self.gentleKaiRelock(at: tBoundary) }
                }
                silenceCounter = 0
            }
        }

        let phase = fmod((now - breathAnchor) / T, 1.0)
        let wetAuto = kaiDynamicReverb(freq: frequency, phrase: phrase, kaiTime: kaiTimeRef, breathPhase: phase)
        let dAuto   = autoDelaySeconds(freq: frequency, phrase: phrase, wet: (userWet == 0) ? wetAuto : userWet)

        // 1-pole smoothing
        let dt = 1.0 / tickHz
        smoothFloat(&smWet,      target: (userWet == 0 ? wetAuto : userWet), dt: dt, tau: smoothTauWet)
        smoothDouble(&smDelay,   target: dAuto, dt: dt, tau: smoothTauDelay)
        let fbTarget = min(self.baseFeedback + 0.015 * Float(sin(2.0 * .pi * phase)), FB_MAX_GAIN)
        smoothFloat(&smFeedback, target: fbTarget, dt: dt, tau: smoothTauFeedback)

        DispatchQueue.main.async {
            self.autoWet = wetAuto
            self.applyWet(self.smWet)
            self.applyDelay(self.smDelay)
            self.applyFeedback(self.smFeedback)

            self.updateVoicePositions(phase: phase)
            self.updateListenerFromMotion()
        }
    }

    private func onBoundary(at tBoundary: CFTimeInterval) {
        guard isPlaying else { return }
        if onrampActive {
            if onrampStage >= ONRAMP_BREATHS {
                let fadeSec = min(PHI, 1.0)
                let startDepth = gateDepth
                animate(duration: fadeSec) { p in
                    let d: Float = Float(1.0 - p) * startDepth
                    self.gateDepth = d
                    self.gateBase  = (1.0 as Float) - d
                } completion: { self.onrampActive = false }
            } else {
                let targetBeat  = ONRAMP_BEATS[onrampStage]
                let targetDepth = ONRAMP_DEPTHS[onrampStage]
                // slew proportionate to breath (exact KKS timing)
                let slew = min(0.618 * breathPeriod, 1.0)

                let startDepth = gateDepth, startBase = gateBase, startBeat = gateBeat
                animate(duration: slew) { p in
                    self.gateDepth = startDepth + (targetDepth - startDepth) * Float(p)
                    self.gateBase  = startBase  + (((1.0 as Float) - targetDepth) - startBase) * Float(p)
                    self.gateBeat  = startBeat  + (targetBeat - startBeat) * p
                }

                if ENABLE_BOUNDARY_CHIME && boundaryIndex < 5 { playChime987() }
                if boundaryIndex < 8 { haptic?.impactOccurred(intensity: 0.6) }
                NotificationCenter.default.post(name: .kaiBreathBoundary, object: nil, userInfo: ["index": boundaryIndex])
                onrampStage += 1
            }
        } else {
            NotificationCenter.default.post(name: .kaiBreathBoundary, object: nil, userInfo: ["index": boundaryIndex])
        }
    }

    private func scheduleSacredSilence(at boundary: CFTimeInterval) {
        // brief golden hush, breath-synced dip then return
        let start = max(userWet, baseWet)
        let down = max(0, Double(start) * 0.89)
        animate(duration: BREATH_SEC * (3.0/PHI2)) { p in
            let val = Float(Double(start) + (down - Double(start)) * p)
            if self.userWet == 0 { self.applyWet(val) }
        } completion: {
            self.animate(duration: BREATH_SEC * (3.5/PHI2)) { p in
                let val = Float(down + (Double(start) - down) * p)
                if self.userWet == 0 { self.applyWet(val) }
            }
        }
    }

    private func playChime987() {
        let sr = actualSampleRate > 0 ? actualSampleRate : 48_000
        let dur = 0.18
        let frames = Int(sr * dur)
        let twopi = 2.0 * Double.pi
        var phase = 0.0
        let freq = 987.0

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2) else { return }
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)) else { return }
        buf.frameLength = AVAudioFrameCount(frames)
        let l = buf.floatChannelData![0]
        let r = buf.floatChannelData![1]

        for i in 0..<frames {
            phase += freq / sr
            if phase > 1 { phase -= 1 }
            let s = sin(twopi * phase)
            let sf = Float(s)
            let t = Double(i) / sr
            let env = Float(exp(-12.0 * t))
            let amp: Float = 0.002
            l[i] = sf * amp * env
            r[i] = sf * amp * env
        }

        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: entrainGate, format: format)
        player.scheduleBuffer(buf, at: nil, options: .interrupts) { [weak self, weak player] in
            DispatchQueue.main.async {
                guard let self = self, let player = player else { return }
                self.engine.disconnectNodeInput(player); self.engine.detach(player)
            }
        }
        player.play()
    }

    // MARK: Smoothing helpers
    @inline(__always) private func smoothFloat(_ sm: inout Float, target: Float, dt: Double, tau: Double) {
        let alpha = Float(1.0 - exp(-dt / tau))
        sm += (target - sm) * alpha
    }
    @inline(__always) private func smoothDouble(_ sm: inout Double, target: Double, dt: Double, tau: Double) {
        let alpha = (1.0 - exp(-dt / tau))
        sm += (target - sm) * alpha
    }

    // MARK: Animation helper
    private final class DisplayLinkProxy {
        let tick: (CADisplayLink) -> Void
        init(_ tick: @escaping (CADisplayLink) -> Void) { self.tick = tick }
        @objc func onTick(_ link: CADisplayLink) { tick(link) }
    }

    private func animate(duration: Double, update: @escaping (Double)->Void, completion: (() -> Void)? = nil) {
        guard duration > 0 else { update(1); completion?(); return }
        let start = CACurrentMediaTime()
        let proxy = DisplayLinkProxy { link in
            let now = CACurrentMediaTime()
            let p = min(1.0, (now - start) / duration)
            update(p)
            if p >= 1.0 { link.invalidate(); completion?() }
        }
        let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.onTick(_:)))
        objc_setAssociatedObject(link, Unmanaged.passUnretained(self).toOpaque(), proxy, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        link.add(to: RunLoop.main, forMode: RunLoop.Mode.common)
    }

    private func primeKaiTimeAndAlignStart() async {
        if let t = await fetchKaiTime() { kaiTimeRef = t }
        // align to exact breath boundary (KKS)
        let residual = (BREATH_SEC - fmod(kaiTimeRef, BREATH_SEC)).truncatingRemainder(dividingBy: BREATH_SEC)
        if residual > 0.005 { try? await Task.sleep(nanoseconds: UInt64(residual * 1_000_000_000)) }
        DispatchQueue.main.async { self.breathAnchor = CACurrentMediaTime() }
    }

    private func fetchKaiTime() async -> Double? {
        guard let url = URL(string: "https://klock.kaiturah.com/kai") else { return nil }
        var req = URLRequest(url: url); req.timeoutInterval = 3.0
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            if let obj = try JSONSerialization.jsonObject(with: data) as? [String:Any],
               let t = obj["kai_time"] as? Double { return t }
        } catch {}
        return nil
    }

    private func gentleKaiRelock(at boundary: CFTimeInterval) async {
        guard let t = await fetchKaiTime() else { return }
        kaiTimeRef = t
        let Ttrue = BREATH_SEC
        let Tlocal = breathPeriod
        let dt = boundary - CACurrentMediaTime()
        let kaiAtBoundary = kaiTimeRef + max(0, dt)
        var err = fmod(kaiAtBoundary, Ttrue)
        if err > Ttrue/2 { err -= Ttrue }
        let N = 13.0
        let target = Tlocal + (err / N)
        func ppmClamp(_ val: Double, ref: Double, ppm: Double) -> Double {
            max(ref * (1 - ppm/1e6), min(ref * (1 + ppm/1e6), val))
        }
        let corrected = ppmClamp(target, ref: Ttrue, ppm: 500)
        let start = breathPeriod
        animate(duration: min(1.0, corrected)) { p in
            self.breathPeriod = start + (corrected - start) * p
        }
    }

    // MARK: Motion → listener orientation (world-locked)
    private func startMotion() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 60.0
        motion.startDeviceMotionUpdates(using: .xArbitraryZVertical)
    }

    private func updateListenerFromMotion() {
        guard let dm = motion.deviceMotion else { return }
        let q = dm.attitude.quaternion
        let R = simd_float3x3(simd_quatf(ix: Float(q.x), iy: Float(q.y), iz: Float(q.z), r: Float(q.w)))
        let forward = simd_normalize(-R.columns.2)
        let up      = simd_normalize( R.columns.1)

        environment.listenerVectorOrientation = AVAudio3DVectorOrientation(
            forward: AVAudio3DVector(x: forward.x, y: forward.y, z: forward.z),
            up:      AVAudio3DVector(x: up.x,      y: up.y,      z: up.z)
        )
        let g = dm.gravity
        environment.listenerPosition = AVAudio3DPoint(
            x: Float(g.x) * 0.02,
            y: Float(g.y) * 0.02,
            z: Float(g.z) * 0.02
        )
    }

    // MARK: Background task helpers
    private func beginBackgroundTask() {
        if bgTask == .invalid {
            bgTask = UIApplication.shared.beginBackgroundTask(withName: "KaiKlokAudio") { [weak self] in
                self?.endBackgroundTask()
            }
        }
    }
    private func endBackgroundTask() {
        if bgTask != .invalid {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// UI • Etherik Neon Button Style
// ─────────────────────────────────────────────────────────────────────────────

struct EtherikNeonButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .textCase(.uppercase)
            .padding(.vertical, 12)
            .padding(.horizontal, 22)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color(kaiHex:"#00ffff").opacity(0.25), lineWidth: 1)
                        )
                        .shadow(color: Color(kaiHex:"#00faff").opacity(0.28), radius: 16, y: 8)
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(AngularGradient(gradient: Gradient(colors: [
                            Color(kaiHex:"#37ffe4"), Color(kaiHex:"#00a0ff"), Color(kaiHex:"#7c3aed"), Color(kaiHex:"#37ffe4")
                        ]), center: .center), lineWidth: 2.0)
                        .blur(radius: 10)
                        .opacity(0.9)
                        .padding(-6)
                }
            )
            .foregroundStyle(.white)
            .shadow(color: Color(kaiHex:"#00ffff").opacity(0.25), radius: 12)
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeInOut(duration: 0.16), value: configuration.isPressed)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Harmonic Player Card (Audio UI) — uses HarmonicEngine
// ─────────────────────────────────────────────────────────────────────────────

struct HarmonicPlayerView: View {
    @StateObject private var engine = HarmonicEngine()

    var initialFrequency: Double
    var responsePhrase: String = "Shoh Mek"
    var binaural: Bool = true
    var enableVoice: Bool = true

    @State private var phrase: String
    @State private var isPlaying = false
    @State private var userWet: Float = 0

    init(frequency: Double, phrase: String = "Shoh Mek", binaural: Bool = true, enableVoice: Bool = true) {
        self.initialFrequency = frequency
        self._phrase = State(initialValue: phrase)
        self.binaural = binaural
        self.enableVoice = enableVoice
    }

    var body: some View {
        VStack(spacing: 12) {
            // Reverb label
            HStack(spacing: 6) {
                Text("Kai Reverb:")
                    .font(.system(size: 14, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                Text("\(Int(engine.autoWet * 1000)/10)%")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                Text(" | User Mix:")
                    .font(.system(size: 14, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                Text("\(Int(userWet * 1000)/10)%")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 4)

            // Reverb slider
            Slider(value: Binding(get: { Double(userWet) },
                                  set: { v in userWet = Float(v); engine.setUserWet(Float(v)) }),
                   in: 0...Double(WET_CAP))
                .tint(Color(hue: 0.47, saturation: 1, brightness: 1))
                .padding(.horizontal, 16)

            // Phrase selector
            Picker("Phrase", selection: $phrase) {
                ForEach(Array(phrasePresets.keys.sorted()), id: \.self) { p in
                    Text(p).tag(p)
                }
            }
            .pickerStyle(.menu)
            .modifier(OnChangePhraseModifier(phrase: $phrase, engine: engine))
            .foregroundStyle(.cyan)
            .padding(.vertical, 4)

            // Play / Stop button
            Button(action: toggle) {
                Text(isPlaying ? "Stop Sound" : "Play \(Int(initialFrequency))Hz Harmonics")
            }
            .buttonStyle(EtherikNeonButtonStyle())
            .padding(.top, 6)

            if isPlaying {
                FidelityPill(sampleRate: engine.actualSampleRate)
                    .padding(.top, 6)
            }

            FrequencyWaveVisualizerView(samples: engine.waveform)
                .frame(height: 110)
                .padding(.horizontal, 6)

            SigilBreathView()
                .frame(width: 180, height: 180)
                .allowsHitTesting(false)
                .padding(.top, 6)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    RadialGradient(colors: [Color(kaiHex:"#021d1f"), Color(kaiHex:"#000f11")],
                                   center: .center, startRadius: 10, endRadius: 600)
                )
                .shadow(color: .white.opacity(0.06), radius: 30, x: 0, y: 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                )
        )
        .onAppear {
            engine.autoWet = kaiDynamicReverb(freq: initialFrequency, phrase: phrase, kaiTime: 0, breathPhase: 0)
            engine.userWet = 0
        }
        .onDisappear { if isPlaying { engine.stop() } }
    }

    private func toggle() {
        if isPlaying {
            engine.stop()
            isPlaying = false
        } else {
            engine.play(frequency: initialFrequency, phrase: phrase, binaural: binaural)
            isPlaying = true
        }
    }
}

// MARK: - iOS 17 onChange compatibility shim
private struct OnChangePhraseModifier: ViewModifier {
    @Binding var phrase: String
    let engine: HarmonicEngine
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.onChange(of: phrase, initial: false) { _, newValue in
                engine.updatePhrase(newValue)
            }
        } else {
            content.onChange(of: phrase) { newValue in
                engine.updatePhrase(newValue)
            }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Fidelity Pill (animation uses exact breath period)
// ─────────────────────────────────────────────────────────────────────────────

private struct FidelityPill: View {
    let sampleRate: Double
    var body: some View {
        let srText = sampleRate >= 96_000 ? "96 kHz" : sampleRate >= 48_000 ? "48 kHz" : "44.1 kHz"
        let tier = sampleRate >= 96_000 ? "Full" : sampleRate >= 48_000 ? "Standard" : "Limited"
        let color: Color = sampleRate >= 96_000 ? Color(kaiHex:"#00FFD1") : sampleRate >= 48_000 ? Color(kaiHex:"#FFBB44") : Color(kaiHex:"#FF5555")

        return VStack(spacing: 2) {
            ZStack {
                Capsule()
                    .fill(color.opacity(0.08))
                    .overlay(Capsule().stroke(.white.opacity(0.07), lineWidth: 1))
                    .shadow(color: color.opacity(0.15), radius: 6)
                HStack(spacing: 6) {
                    Circle().fill(color).frame(width: 14, height: 14).opacity(0.85)
                    Text("\(srText) — ")
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                    Text(tier)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                }
                .foregroundStyle(color)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            Text("Harmonic Fidelity")
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(.white.opacity(0.45))
        }
        .padding(.top, 2)
        .animation(.easeInOut(duration: BREATH_SEC).repeatForever(autoreverses: true), value: sampleRate)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Wave Visualizer
// ─────────────────────────────────────────────────────────────────────────────

private struct FrequencyWaveVisualizerView: View {
    let samples: [Float]
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let N = max(1, samples.count)
            Path { p in
                p.move(to: CGPoint(x: 0, y: h/2))
                for i in 0..<N {
                    let x = CGFloat(i) / CGFloat(N - 1) * w
                    let y = h/2 - CGFloat(samples[i]) * (h * 0.44)
                    p.addLine(to: CGPoint(x: x, y: y))
                }
            }
            .stroke(LinearGradient(colors: [Color(kaiHex:"#13ffe8"), Color(kaiHex:"#00c3ff")],
                                   startPoint: .leading, endPoint: .trailing), lineWidth: 2)
            .shadow(color: Color(kaiHex:"#00ffe1").opacity(0.35), radius: 8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.06), lineWidth: 1))
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sigil (breath animation, exact KKS period)
// ─────────────────────────────────────────────────────────────────────────────

private struct SigilBreathView: View {
    @State private var anim = false
    var body: some View {
        ZStack {
            Circle()
                .fill(Color(kaiHex:"#ffffc0").opacity(0.18))
                .blur(radius: 12)
            Canvas { ctx, size in
                let center = CGPoint(x: size.width/2, y: size.height/2)
                var path = Path()
                let A = min(size.width, size.height) * 0.35
                let B = min(size.width, size.height) * 0.27
                let a: CGFloat = 3, b: CGFloat = 2, δ: CGFloat = .pi/2.4
                let steps = 800
                for i in 0...steps {
                    let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
                    let x = center.x + A * sin(a*t + δ)
                    let y = center.y + B * sin(b*t)
                    if i == 0 { path.move(to: CGPoint(x:x, y:y)) }
                    else { path.addLine(to: CGPoint(x:x, y:y)) }
                }
                ctx.stroke(path, with: .color(Color(kaiHex:"#fff69e")), lineWidth: 1.4)
            }
            .shadow(color: Color(kaiHex:"#fff69e").opacity(0.5), radius: 10)

            Circle()
                .strokeBorder(Color(kaiHex:"#ffffc0").opacity(0.35), lineWidth: 1)
                .shadow(color: Color(kaiHex:"#ffffaf").opacity(0.2), radius: 8)
        }
        .scaleEffect(anim ? 1.02 : 0.97)
        .opacity(anim ? 1.0 : 0.88)
        .animation(.easeInOut(duration: BREATH_SEC).repeatForever(autoreverses: true), value: anim)
        .onAppear { anim = true }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Color helper
// ─────────────────────────────────────────────────────────────────────────────

fileprivate extension Color {
    init(kaiHex: String) {
        var s = kaiHex.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "#")))
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xFF) / 255.0
        let g = Double((v >> 8) & 0xFF) / 255.0
        let b = Double(v & 0xFF) / 255.0
        self = Color(red: r, green: g, blue: b)
    }
}
