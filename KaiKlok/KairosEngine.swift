//
//  KairosEngine.swift
//  KaiKlok
//
//  Created by BJ Klock on 9/20/25.
//  Closed-form φ‑exact ticker. No drift. No guesswork.
//

import Foundation
import Combine

/// A singleton pulse engine that emits the current Kairos state in real time.
///
/// This class drives all UI updates, animation ticks, and Live Activity synchronization
/// by publishing the current `pulse` and decoded `KairosMoment`, in perfect φ-sync.
///
final class KairosEngine: ObservableObject {
    
    // MARK: - Singleton Instance

    static let shared = KairosEngine()

    // MARK: - Published Kairos State

    /// Current Kairos Pulse (φ‑aligned index)
    @Published private(set) var pulse: Int = 0

    /// Fully decoded moment snapshot (pulse, beat, step, chakraDay, etc.)
    @Published private(set) var moment: KairosMoment = KairosTime.decodeMoment(for: 0)

    // MARK: - Internal Timer

    private var timer: AnyCancellable?

    // MARK: - Initialization

    private init() {
        start()
    }

    // MARK: - Lifecycle

    /// Starts the harmonic pulse engine (main thread, φ rhythm)
    func start() {
        timer?.cancel()
        timer = Timer
            .publish(every: KairosConstants.uiTickSec, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }

                let p = KairosTime.currentPulse()
                if p != self.pulse {
                    self.pulse = p
                }

                self.moment = KairosTime.decodeMoment(for: p)
            }
    }

    /// Stops the harmonic pulse engine (optional for background mode)
    func stop() {
        timer?.cancel()
        timer = nil
    }
}

// MARK: - Static Helpers for Live Activity + Widgets

extension KairosEngine {
    
    /// Returns the current Pulse index (φ-based)
    static func currentPulse() -> Int {
        KairosTime.currentPulse()
    }

    /// Returns the current Step index (0–43)
    static func currentStep() -> Int {
        KairosTime.decodeMoment(for: KairosTime.currentPulse()).step
    }

    /// Returns the current Beat index (0–35)
    static func currentBeat() -> Int {
        KairosTime.decodeMoment(for: KairosTime.currentPulse()).beat
    }
}
