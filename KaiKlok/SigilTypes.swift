//
//  SigilTypes.swift
//  KaiKlok
//
//  Created by BJ Klock on 9/15/25.
//

//
//  SigilTypes.swift
//  KaiKlok
//
//  Canonical Sigil types used across the app.
//  IMPORTANT: Ensure this is the ONLY file that declares `SigilParams`.
//

import Foundation

/// Canonical parameter bag for generating/exporting a sigil.
/// Keep this type stable; other files (SigilView, SVGBuilder, SigilMath, etc.)
/// rely on these exact field names.
public struct SigilParams: Sendable, Codable, Equatable {
    /// Eternal pulse number (whole pulses since Genesis)
    public var pulse: Int64

    /// Beat within the Eternal day (0..35)
    public var beat: Int

    /// Step index within a beat (0..43)
    public var stepIndex: Int

    /// Chakra/day mapping as a simple index (use your own enum elsewhere if desired)
    /// 0: Root, 1: Sacral, 2: Solar Plexus, 3: Heart, 4: Throat, 5: Third Eye, 6: Crown
    public var chakraDay: Int

    /// Optional deterministic seed for visual jitter / styling
    public var seed: UInt64

    /// Optional user key for φ-related personalization
    public var userPhiKey: String?

    /// Optional signature blob (string/hex/etc.)
    public var kaiSignature: String?

    /// Timestamp you want to attach (often equals `pulse`, but kept separate)
    public var timestamp: Int64

    public init(
        pulse: Int64,
        beat: Int,
        stepIndex: Int,
        chakraDay: Int,
        seed: UInt64,
        userPhiKey: String? = nil,
        kaiSignature: String? = nil,
        timestamp: Int64
    ) {
        self.pulse = pulse
        self.beat = beat
        self.stepIndex = stepIndex
        self.chakraDay = chakraDay
        self.seed = seed
        self.userPhiKey = userPhiKey
        self.kaiSignature = kaiSignature
        self.timestamp = timestamp
    }

    // Explicit Equatable to silence any synthesis issues if your project
    // compiles with special flags or has conditional members later.
    public static func == (lhs: SigilParams, rhs: SigilParams) -> Bool {
        lhs.pulse == rhs.pulse &&
        lhs.beat == rhs.beat &&
        lhs.stepIndex == rhs.stepIndex &&
        lhs.chakraDay == rhs.chakraDay &&
        lhs.seed == rhs.seed &&
        lhs.userPhiKey == rhs.userPhiKey &&
        lhs.kaiSignature == rhs.kaiSignature &&
        lhs.timestamp == rhs.timestamp
    }
}
