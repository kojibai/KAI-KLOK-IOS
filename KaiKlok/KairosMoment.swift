//  KairosMoment.swift

import Foundation

struct KairosMoment: Equatable {
    let pulse: Int                // global pulse since T0
    let beat: Int                 // 0..35
    let step: Int                 // 0..43
    let pulseInStepIndex: Int     // 0..10

    // Day / Arc within 6-day cycle
    let dayIndex: Int             // 0..5  -> Solhara..Kaelith
    let arcIndex: Int             // 0..5  -> Ignition..Dream

    // Calendar (8 months of 42 days = 336)
    let monthIndex: Int           // 0..7  -> Aethon..Liora
    let monthDay1: Int            // 1..42

    // Derived continuous values for rendering
    let dayPulse: Double
    let pulsesIntoBeat: Double
    let pulsesIntoStep: Double
    let stepFraction: Double

    // Helpers for UI
    var beatString: String { String(format: "%02d", beat) }
    var stepString: String { String(format: "%02d", step) }
}
