//
//  PulseFormatter.swift
//  KaiKlok
//
//  Created by BJ Klock on 10/15/25.
//

import Foundation

struct PulseFormatter {
    
    static func formatKaiTimestamp(
        pulse: Int,
        beat: Int,
        step: Int,
        chakraDay: String
    ) -> String {
        return "Pulse \(pulse) · Beat \(beat) · Step \(step) · \(chakraDay)"
    }

    static func formatKaiShort(
        beat: Int,
        step: Int
    ) -> String {
        return "B\(beat)·S\(step)"
    }

    static func formatKaiMeta(
        timestamp: Date,
        pulse: Int,
        chakraDay: String
    ) -> String {
        let chrono = Self.formatChrono(timestamp)
        return "🕰 \(chrono)\n🔮 Pulse \(pulse)\n🌿 \(chakraDay)"
    }

    static func formatChrono(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy · HH:mm:ss"
        return formatter.string(from: date)
    }
}
