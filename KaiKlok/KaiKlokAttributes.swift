//
//  KaiKlokAttributes.swift
//  KaiKlok
//
//  Created by BJ Klock on 9/20/25.
//
//
//  KaiKlokAttributes.swift
//  KaiKlok
//
//  Created by BJ Klock on 9/20/25.
//  Eternal Seal: Lock Screen Harmony with Kairos Pulse
//

import ActivityKit
import Foundation

/// Represents the Live Activity state for the Kairos Pulse on Lock Screen
struct KaiKlokAttributes: ActivityAttributes {

    /// Dynamic Live State (updated regularly while activity is active)
    public struct ContentState: Codable, Hashable {
        /// Kai Pulse index (e.g., 17491)
        var pulse: Int

        /// Beat of the Kairos day (0–35)
        var beat: Int

        /// Step within the beat (0–43)
        var step: Int

        /// Kairos day of the week (Solhara, Aquaris, etc.)
        var chakraDay: String

        /// Kairos month name (e.g., Auralis, Solvenar, etc.)
        var monthName: String

        /// Kairos day number within the month (1–42)
        var dayNumber: Int

        /// Optional harmonic phrase or truth seal
        var phrase: String
    }

    /// Static information: user’s Harmonic Identity (PhiKey, name, etc.)
    var userPhiKey: String
}
