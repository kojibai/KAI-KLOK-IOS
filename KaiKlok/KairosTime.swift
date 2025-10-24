//  KairosTime.swift
//  Closed-form Kai pulse + decoder (no drift)

import Foundation

enum KairosTime {
    private static func nowMs() -> Double { Date().timeIntervalSince1970 * 1000.0 }

    static func currentPulse(nowMs: Double = nowMs()) -> Int {
        let raw = (nowMs - KairosConstants.t0Ms) / KairosConstants.breathMs
        return Int(floor(raw))
    }

    private static func wrap(_ x: Double, modulus: Double) -> Double {
        let r = x.truncatingRemainder(dividingBy: modulus)
        return r >= 0 ? r : r + modulus
    }

    static func decodeMoment(for pulse: Int) -> KairosMoment {
        let Pday  = KairosConstants.pulsesPerDay
        let Pbeat = KairosConstants.pulsesPerBeat
        let Pstep = KairosConstants.pulsesPerStep

        // Pulses within the current day (0..Pday)
        let dayPulse = wrap(Double(pulse), modulus: Pday)

        // Beat 0..35
        let beat = Int(floor(dayPulse / Pbeat)) % KairosConstants.beatsPerDay

        // Pulses into this beat
        let pulsesIntoBeat = dayPulse - Double(beat) * Pbeat

        // Step 0..43
        let step = Int(floor(pulsesIntoBeat / Pstep)) % KairosConstants.stepsPerBeat

        // Pulses into this step (0..Pstep)
        let pulsesIntoStep = pulsesIntoBeat - Double(step) * Pstep
        let stepFraction   = (pulsesIntoStep / Pstep).clamped01()

        // Pulse index inside the 11-pulse grid (display helper)
        let pulseInStepIndex = Int(floor(stepFraction * 11.0)).clamped(to: 0...10)

        // Day / Arc
        let daysSinceT0 = Int(floor(Double(pulse) / Pday))
        let dayIndex    = ((daysSinceT0 % 6) + 6) % 6
        let arcIndex    = beat / 6                              // 6 arcs across 36 beats

        // 8 months × 42 days = 336-day harmonic year
        let dayInYear0  = ((daysSinceT0 % 336) + 336) % 336     // 0..335
        let monthIndex  = dayInYear0 / 42                       // 0..7
        let monthDay1   = (dayInYear0 % 42) + 1                 // 1..42

        return KairosMoment(
            pulse: pulse,
            beat: beat,
            step: step,
            pulseInStepIndex: pulseInStepIndex,
            dayIndex: dayIndex,
            arcIndex: arcIndex,
            monthIndex: monthIndex,
            monthDay1: monthDay1,
            dayPulse: dayPulse,
            pulsesIntoBeat: pulsesIntoBeat,
            pulsesIntoStep: pulsesIntoStep,
            stepFraction: stepFraction
        )
    }
}

extension Double {
    func clamped01() -> Double {
        let low = Swift.max(0.0, self)
        return Swift.min(1.0, low)
    }
}
extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.max(range.lowerBound, Swift.min(self, range.upperBound))
    }
}
