//
//  KairosLabelEngine.swift
//  KaiKlok
//

import SwiftUI

// Canon arc names used in UI
enum ArcName: String, CaseIterable {
    case ignition      = "Ignition Ark"
    case integration   = "Integration Ark"
    case harmonization = "Harmonization Ark"
    case reflektion    = "Reflektion Ark"
    case purifikation  = "Purifikation Ark"
    case dream         = "Dream Ark"
}

struct KairosLabelEngine {
    // Expose as strings for the dial’s ForEach
    static let arcNames: [String] = ArcName.allCases.map { $0.rawValue }

    // Eternal weekday names (0..5)
    private static let dayNames = [
        "Solhara", "Aquaris", "Flamora",
        "Verdari", "Sonari", "Kaelith"
    ]

    // Harmonic month names (0..7)
    private static let monthNames = [
        "Aethon", "Virelai", "Solari", "Amarin",
        "Kaelus", "Umbriel", "Noctura", "Liora"
    ]

    // MARK: - Arc helpers used by the dial

    /// Map 0..5 → ArcName (safe wrapped)
    static func arc(for index: Int) -> ArcName {
        let i = ((index % 6) + 6) % 6
        return ArcName.allCases[i]
    }

    /// Convenience: color by ArcName
    static func color(for arc: ArcName) -> Color {
        switch arc {
        case .ignition:      return kaiColor("#ff1559")
        case .integration:   return kaiColor("#ff6d00")
        case .harmonization: return kaiColor("#ffd900")
        case .reflektion:    return kaiColor("#00ff66")
        case .purifikation:  return kaiColor("#05e6ff")
        case .dream:         return kaiColor("#c300ff")
        }
    }

    /// Convenience: color by arc string
    static func color(for arcName: String) -> Color {
        ArcName(rawValue: arcName).map { color(for: $0) } ?? .white
    }

    /// Short, UI-friendly caption
    static func short(_ arc: ArcName) -> String {
        switch arc {
        case .ignition:      return "Ignite"
        case .integration:   return "Integrate"
        case .harmonization: return "Harmony"
        case .reflektion:    return "Reflekt"
        case .purifikation:  return "Purify"
        case .dream:         return "Dream"
        }
    }

    /// Overload for string input (dial uses strings from arcNames)
    static func short(_ arcName: String) -> String {
        ArcName(rawValue: arcName).map { short($0) } ?? arcName
    }

    // MARK: - Day / Month labels

    static func dayName(forDayIndex index: Int) -> String {
        let i = ((index % 6) + 6) % 6
        return dayNames[i]
    }

    static func monthName(forMonthIndex index: Int) -> String {
        let i = ((index % 8) + 8) % 8
        return monthNames[i]
    }

    // MARK: - Optional semantic label

    static func semanticLabel(pulse: Int) -> String {
        let pps  = KairosConstants.pulsesPerStep
        let spb  = KairosConstants.stepsPerBeat
        let bpd  = KairosConstants.beatsPerDay

        let step = (pulse / Int(pps)) % spb
        let beat = (pulse / (Int(pps) * spb)) % bpd
        let arc  = arc(for: beat / 6)
        let dayIndex = (pulse / (Int(pps) * spb * bpd)) % 6

        return "\(dayName(forDayIndex: dayIndex)) • \(arc.rawValue) • b\(beat) • s\(step)"
    }
}
