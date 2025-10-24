// KairosConstants.swift
// Canon constants for Eternal Time (KKS-1.0)

import Foundation

enum KairosConstants {
    // φ-exact breath unit
    static let breathSec: Double = 3.0 + sqrt(5.0)                 // ≈ 5.236067977…
    static let breathMs:  Double = breathSec * 1000.0

    // Genesis epoch (UTC) 2024-05-10 06:45:41.888
    static let t0Ms: Double = 1_715_323_541_888

    // Grid & continuous day pulse spec
    static let beatsPerDay   = 36
    static let stepsPerBeat  = 44
    static let pulsesPerDay: Double   = 17_491.270_421
    static let pulsesPerBeat: Double  = pulsesPerDay / Double(beatsPerDay)
    static let pulsesPerStep: Double  = pulsesPerBeat / Double(stepsPerBeat)

    // UI
    static let uiTickSec: Double = 0.25 // UI refresh cadence (does not “keep” time)
}
