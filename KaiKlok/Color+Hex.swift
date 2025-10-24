//
//  Color+Hex.swift
//  KaiKlok
//
//  Created by BJ Klock on 9/11/25.
//

// Color+Hex.swift
import SwiftUI

extension Color {
    /// Lightweight hex initializer: "#RRGGBB" or "#RRGGBBAA"
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)

        switch s.count {
        case 6:
            self.init(
                .sRGB,
                red:   Double((value & 0xFF0000) >> 16) / 255.0,
                green: Double((value & 0x00FF00) >>  8) / 255.0,
                blue:  Double( value & 0x0000FF       ) / 255.0,
                opacity: 1.0
            )
        case 8:
            self.init(
                .sRGB,
                red:   Double((value & 0xFF000000) >> 24) / 255.0,
                green: Double((value & 0x00FF0000) >> 16) / 255.0,
                blue:  Double((value & 0x0000FF00) >>  8) / 255.0,
                opacity: Double(value & 0x000000FF) / 255.0
            )
        default:
            self = .white
        }
    }
}
// Color+Hex.swift
// Tiny helper used across the dial. Name is 'kaiColor' to avoid any init(hex:) clashes.


@inline(__always)
func kaiColor(_ hex: String) -> Color {
    var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.hasPrefix("#") { s.removeFirst() }

    var v: UInt64 = 0
    Scanner(string: s).scanHexInt64(&v)

    switch s.count {
    case 6:
        let r = Double((v & 0xFF0000) >> 16) / 255.0
        let g = Double((v & 0x00FF00) >>  8) / 255.0
        let b = Double( v & 0x0000FF       ) / 255.0
        return Color(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
    case 8:
        let r = Double((v & 0xFF000000) >> 24) / 255.0
        let g = Double((v & 0x00FF0000) >> 16) / 255.0
        let b = Double((v & 0x0000FF00) >>  8) / 255.0
        let a = Double( v & 0x000000FF       ) / 255.0
        return Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    default:
        return .white
    }
}
