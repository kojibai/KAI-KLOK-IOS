//  KaiDialView.swift
//  SwiftUI Atlantean dial (neon + responsive)
//  - Day/Month colors auto-map from dayIndex/monthIndex (names + numbers match)
//  - Outer rim + day-progress sweep glow with the current Ark color (live)

import SwiftUI

struct KaiDialView: View {
    let moment: KairosMoment

    // Live measurements to manage spacing precisely
    @State private var monthNameWidth: CGFloat = 0
    @State private var centerDayWidth: CGFloat = 0
    @State private var percentWidth: CGFloat = 0
    @State private var monthIndexWidth: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            // ---- Responsive geometry ----
            let S  = min(geo.size.width, geo.size.height)
            let Cx = geo.size.width  / 2
            let Cy = geo.size.height / 2

            // Radii
            let R_outer     = S * 0.49
            let R_progress  = S * 0.46
            let R_numbers   = S * 0.405
            let R_arcLabels = S * 0.360
            let R_halo      = S * 0.22
            let haloStroke  = S * 0.06

            // Strokes & sizes
            let rimLine       = max(1, S * 0.006)
            let progressW     = S * 0.032
            let beatFont      = S * 0.045

            // ↓ Arc label font reduced by 30%
            let arcFont       = S * 0.054 * 0.70

            // Bigger day pulse at the very top
            let dayPulseFont  = S * 0.074

            let bbssFont      = S * 0.168
            let dowFont       = S * 0.092
            let monthFont     = S * 0.098
            let epFont        = S * 0.042

            // More visual weight/room to step % and center day-of-month
            let percentFont   = S * 0.040
            let centerDayFont = S * 0.094
            let monthNumFont  = S * 0.056

            let handThick     = max(2, S * 0.009)
            let handTip       = max(4, S * 0.018)

            // ---- Time math (keep exact) ----
            let dayPercent  = moment.dayPulse / KairosConstants.pulsesPerDay
            let clampedDay  = max(0.0, min(1.0, dayPercent))
            let eternalDeg  = (Double(moment.beat) + 0.5)
                            / Double(KairosConstants.beatsPerDay) * 360.0
            let stepPercent = max(0.0, min(1.0, moment.stepFraction)) * 100.0
            // Display only: rounded to nearest whole, math above remains exact
            let displayStepPercent = Int(stepPercent.rounded())

            // Arc anchors (beats) in order of arcNames:
            // Ignition 0 • Integration 7.5 • Harmony 11.5 • Reflection 18 • Purification 24.5 • Dream 28.5
            let arcCenters: [Double] = [0.0, 7.5, 11.5, 18.0, 24.5, 28.5]

            // === Dynamic Palette (LIVE) ======================================
            // Current Ark color (drives rim + progress + halo glow)
            let arkColor   = arkColorForArcIndex(moment.arcIndex)
            // Day + Month colors from indices (names AND numbers follow these)
            let dayColor   = dayColorForIndex(moment.dayIndex)
            let monthColor = monthColorForIndex(moment.monthIndex)
            // Utility
            let neonCyan   = kaiColor("#00faff")
            let etherFillTop  = kaiColor("#ebfdff")
            let etherFillBot  = etherFillTop.opacity(0.15)
            let etherStroke   = kaiColor("#bff7ff")
            let etherGlow     = kaiColor("#eaffff")

            // Eternal Pulse position — ABOVE Reflection (toward center)
            let reflectBeat = 18.0
            let reflectDeg  = (reflectBeat / 36.0) * 360.0 - 90.0
            let reflectAng  = Angle.degrees(reflectDeg)

            // Move EP further inward after lifting the trio
            let epExtraInward = S * 0.022
            let EP_r        = R_arcLabels - (S * 0.038 + epExtraInward)
            let EP_x        = Cx + EP_r * cos(CGFloat(reflectAng.radians))
            let EP_y        = Cy + EP_r * sin(CGFloat(reflectAng.radians))

            // ---- Spacing math for trio (symmetric gaps) ----
            let centerGap    = S * 0.040
            let extraGap     = S * 0.012
            let desiredGapBase = centerGap + extraGap

            // Month-name constraint (don’t spread wider than the month label).
            let halfMonth    = max(0, monthNameWidth / 2)

            // Each side’s maximum achievable gap under clamp:
            let maxLeftGap  = max(0, (halfMonth - percentWidth    / 2) - (centerDayWidth / 2))
            let maxRightGap = max(0, (halfMonth - monthIndexWidth / 2) - (centerDayWidth / 2))

            // Largest gap both sides can realize → symmetric spacing:
            let targetGap = min(desiredGapBase, maxLeftGap, maxRightGap)

            // Centers relative to middle:
            let leftCenterX  = -(centerDayWidth / 2 + targetGap + percentWidth     / 2)
            let rightCenterX =  +(centerDayWidth / 2 + targetGap + monthIndexWidth / 2)

            // ---- Vertical compaction & lifts ----
            let stackSpacing     = S * 0.006
            let dayMonthSpacing  = S * 0.002      // tighter Day↔Month
            let afterBeatTighten = -S * 0.010     // pull Day/Month closer to beat:step
            let trioLift         = -S * 0.022     // lift trio toward Month

            ZStack {
                // ---- OUTER RIM (Ark color + glow) ----
                Circle()
                    .strokeBorder(lineWidth: rimLine)
                    .foregroundStyle(arkColor.opacity(0.9))
                    .shadow(color: arkColor.opacity(0.75), radius: 12)
                    .frame(width: R_outer * 2, height: R_outer * 2)
                    .position(x: Cx, y: Cy)

                // ---- DAY PROGRESS SWEEP (Ark color + glow) ----
                Circle()
                    .trim(from: 0, to: clampedDay)
                    .stroke(style: StrokeStyle(lineWidth: progressW, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .foregroundStyle(arkColor)
                    .shadow(color: arkColor.opacity(0.9), radius: progressW)
                    .frame(width: R_progress * 2, height: R_progress * 2)
                    .position(x: Cx, y: Cy)

                // ---- BEAT NUMBERS 0..35 (spectrum) ----
                ForEach(0..<36, id: \.self) { i in
                    let ang = Angle.degrees(Double(i) * (360.0 / 36.0) - 90)
                    let x   = Cx + R_numbers * cos(CGFloat(ang.radians))
                    let y   = Cy + R_numbers * sin(CGFloat(ang.radians))
                    let hue = Double((i + 33) % 36) / 36.0

                    Text("\(i)")
                        .font(.system(size: beatFont, weight: .heavy, design: .rounded))
                        .foregroundColor(Color(hue: hue, saturation: 1, brightness: 1))
                        .shadow(color: .white.opacity(0.25), radius: 2)
                        .position(x: x, y: y)
                        .allowsHitTesting(false)
                }

                // ---- ARC LABELS ----
                ForEach(0..<6, id: \.self) { i in
                    let centerBeat = arcCenters[i]
                    let centerDeg  = (centerBeat / 36.0) * 360.0 - 90.0
                    let ang        = Angle.degrees(centerDeg)
                    let x          = Cx + R_arcLabels * cos(CGFloat(ang.radians))
                    let y          = Cy + R_arcLabels * sin(CGFloat(ang.radians))

                    let name   = KairosLabelEngine.arcNames[i]
                    let short  = KairosLabelEngine.short(name)
                    let color  = arkColorForArcIndex(i)               // palette matches Ark
                    let active = (i == moment.arcIndex)

                    Text(short)
                        .font(.system(size: arcFont, weight: .heavy, design: .rounded))
                        .foregroundStyle(color.opacity(active ? 1 : 0.60))
                        .shadow(color: color.opacity(0.75), radius: 10)
                        .minimumScaleFactor(0.75)
                        .lineLimit(1)
                        .position(x: x, y: y)
                        .allowsHitTesting(false)
                }

                // ---- INNER HALO RING ----
                Circle()
                    .strokeBorder(lineWidth: haloStroke)
                    .foregroundStyle(.white.opacity(0.22))
                    .frame(width: (R_halo * 2) + haloStroke,
                           height: (R_halo * 2) + haloStroke)
                    .shadow(color: arkColor.opacity(0.6), radius: 10) // subtle Ark tint
                    .position(x: Cx, y: Cy)

                // ---- MICRO ORB (Ark-tinted) ----
                MicroOrb(radius: R_halo + haloStroke / 2,
                         color: arkColor,
                         cycleSec: KairosConstants.breathSec)
                    .frame(width: S, height: S)
                    .position(x: Cx, y: Cy)

                // ---- ETERNAL HAND ----
                EternalHand(
                    center: CGPoint(x: Cx, y: Cy),
                    handThickness: handThick,
                    haloR: R_halo,
                    haloStroke: haloStroke,
                    outerR: R_progress,
                    fillFraction: moment.pulsesIntoBeat / KairosConstants.pulsesPerBeat,
                    rotationDeg: eternalDeg,
                    fillTop: etherFillTop,
                    fillBot: etherFillBot,
                    stroke: etherStroke,
                    glow: etherGlow,
                    tipRadius: handTip
                )

                // ---- STEP DIGITS (upright) ----
                HandStepLabel(
                    center: CGPoint(x: Cx, y: Cy),
                    haloR: R_halo,
                    haloStroke: haloStroke,
                    outerR: R_progress,
                    rotationDeg: eternalDeg,
                    text: moment.stepString,
                    color: .white,
                    size: S
                )

                // ---- CENTER STACK ----
                VStack(spacing: stackSpacing) {
                    // Day pulse — under Ignition (bigger)
                    Text("\(Int(floor(moment.dayPulse)))")
                        .font(.system(size: dayPulseFont, weight: .heavy, design: .rounded))
                        .foregroundStyle(neonCyan)
                        .shadow(color: neonCyan.opacity(0.8), radius: 6)
                        .minimumScaleFactor(0.75)
                        .lineLimit(1)

                    // Big beat:step
                    Text("\(moment.beatString):\(moment.stepString)")
                        .font(.system(size: bbssFont, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: arkColor.opacity(0.9), radius: 18) // match Ark glow
                        .minimumScaleFactor(0.75)
                        .lineLimit(1)

                    // Day & Month — tighter to beat:step and tighter between themselves
                    VStack(spacing: dayMonthSpacing) {
                        Text(KairosLabelEngine.dayName(forDayIndex: moment.dayIndex))
                            .font(.system(size: dowFont, weight: .heavy, design: .rounded))
                            .foregroundStyle(dayColor)
                            .shadow(color: dayColor.opacity(0.75), radius: 10)
                            .minimumScaleFactor(0.75)
                            .lineLimit(1)

                        Text(KairosLabelEngine.monthName(forMonthIndex: moment.monthIndex))
                            .font(.system(size: monthFont, weight: .heavy, design: .rounded))
                            .foregroundStyle(monthColor)
                            .shadow(color: monthColor.opacity(0.9), radius: 10)
                            .minimumScaleFactor(0.75)
                            .lineLimit(1)
                            .background(
                                GeometryReader { pr in
                                    Color.clear
                                        .preference(key: MonthNameWidthKey.self, value: pr.size.width)
                                }
                            )
                            .onPreferenceChange(MonthNameWidthKey.self) { monthNameWidth = $0 }
                    }
                    .padding(.top, afterBeatTighten) // pull Day/Month closer to beat:step

                    // Trio row — lifted upward; more space & size for % and center day
                    ZStack {
                        // CENTER: day-of-month (measure) — color-match Day color
                        Text("\(moment.monthDay1)")
                            .font(.system(size: centerDayFont, weight: .black, design: .rounded))
                            .foregroundStyle(dayColor)
                            .shadow(color: dayColor.opacity(0.9), radius: 6)
                            .minimumScaleFactor(0.8)
                            .lineLimit(1)
                            .background(
                                GeometryReader { pr in
                                    Color.clear
                                        .preference(key: CenterDayWidthKey.self, value: pr.size.width)
                                }
                            )
                            .onPreferenceChange(CenterDayWidthKey.self) { centerDayWidth = $0 }

                        // LEFT: % into step (measure) — display rounded whole
                        Text("\(displayStepPercent)%")
                            .font(.system(size: percentFont, weight: .black, design: .rounded))
                            .foregroundStyle(neonCyan)
                            .shadow(color: neonCyan.opacity(0.9), radius: 5)
                            .minimumScaleFactor(0.85)
                            .lineLimit(1)
                            .background(
                                GeometryReader { pr in
                                    Color.clear
                                        .preference(key: PercentWidthKey.self, value: pr.size.width)
                                }
                            )
                            .onPreferenceChange(PercentWidthKey.self) { percentWidth = $0 }
                            .offset(x: leftCenterX)

                        // RIGHT: month index (measure) — color-match Month color
                        Text("\(moment.monthIndex + 1)")
                            .font(.system(size: monthNumFont, weight: .black, design: .rounded))
                            .foregroundStyle(monthColor)
                            .shadow(color: monthColor.opacity(0.9), radius: 5)
                            .minimumScaleFactor(0.85)
                            .lineLimit(1)
                            .background(
                                GeometryReader { pr in
                                    Color.clear
                                        .preference(key: MonthIndexWidthKey.self, value: pr.size.width)
                                }
                            )
                            .onPreferenceChange(MonthIndexWidthKey.self) { monthIndexWidth = $0 }
                            .offset(x: rightCenterX)
                    }
                    .offset(y: trioLift) // move trio up toward month block
                }
                .frame(width: S)
                .position(x: Cx, y: Cy)

                // ---- ETERNAL PULSE — above Reflection (moved up/inward) ----
                Text("\(moment.pulse)")
                    .font(.system(size: epFont, weight: .heavy, design: .rounded))
                    .foregroundStyle(kaiColor("#d6ffff"))
                    .shadow(color: etherGlow.opacity(0.9), radius: 7)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .position(x: EP_x, y: EP_y)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("Kai-Klok dial, beat \(moment.beat), step \(moment.step)")
    }
}

// MARK: - Dynamic Palette Helpers (Day/Month/Ark)

/// Day colors by index (0..5): Solhara, Aquaris, Flamora, Verdari, Sonari, Kaelith
private func dayColorForIndex(_ i: Int) -> Color {
    switch (i % 6 + 6) % 6 {
    case 0: return kaiColor("#ff1559") // Solhara
    case 1: return kaiColor("#ff6d00") // Aquaris
    case 2: return kaiColor("#ffd900") // Flamora
    case 3: return kaiColor("#00ff66") // Verdari
    case 4: return kaiColor("#05e6ff") // Sonari
    default: return kaiColor("#c300ff") // Kaelith
    }
}

/// Month colors by index (0..7): Aethon, Virelai, Solari, Amarin, Kaelus, Umbriel, Noctura, Liora
private func monthColorForIndex(_ i: Int) -> Color {
    switch (i % 8 + 8) % 8 {
    case 0: return kaiColor("#ff1559") // Aethon
    case 1: return kaiColor("#ff6d00") // Virelai
    case 2: return kaiColor("#ffd900") // Solari
    case 3: return kaiColor("#00ff66") // Amarin
    case 4: return kaiColor("#05e6ff") // Kaelus
    case 5: return kaiColor("#0096ff") // Umbriel
    case 6: return kaiColor("#7000ff") // Noctura
    default: return kaiColor("#c300ff") // Liora
    }
}

/// Ark colors by arc index (0..5): Ignition, Integration, Harmonization, Reflection, Purification, Dream
private func arkColorForArcIndex(_ i: Int) -> Color {
    switch (i % 6 + 6) % 6 {
    case 0: return kaiColor("#ff1559") // Ignition Ark
    case 1: return kaiColor("#ff6d00") // Integration Ark
    case 2: return kaiColor("#ffd900") // Harmonization Ark
    case 3: return kaiColor("#00ff66") // Reflection Ark
    case 4: return kaiColor("#05e6ff") // Purification Ark
    default: return kaiColor("#c300ff") // Dream Ark
    }
}

// MARK: - Preference Keys
private struct MonthNameWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
private struct CenterDayWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
private struct PercentWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
private struct MonthIndexWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - Pieces

private struct MicroOrb: View {
    let radius: CGFloat
    let color: Color
    let cycleSec: Double
    @State private var anim = false

    var body: some View {
        GeometryReader { geo in
            let C = min(geo.size.width, geo.size.height) / 2
            Circle()
                .fill(color)
                .frame(width: max(8, C * 0.12), height: max(8, C * 0.12))
                .shadow(color: color, radius: 6)
                .offset(y: -radius)
                .rotationEffect(.degrees(anim ? 360 : 0))
                .animation(.linear(duration: cycleSec).repeatForever(autoreverses: false), value: anim)
                .position(x: C, y: C)
                .onAppear { anim = true }
        }
    }
}

private struct EternalHand: View {
    let center: CGPoint
    let handThickness: CGFloat
    let haloR: CGFloat
    let haloStroke: CGFloat
    let outerR: CGFloat
    let fillFraction: Double
    let rotationDeg: Double
    let fillTop: Color
    let fillBot: Color
    let stroke: Color
    let glow: Color
    let tipRadius: CGFloat

    var body: some View {
        let handLen  = outerR - (haloR + haloStroke)
        let baseY    = -(haloR + haloStroke)
        let f        = max(0, min(1, fillFraction))
        let fillH    = handLen * f

        let grad = LinearGradient(gradient: Gradient(colors: [fillBot, fillTop]),
                                  startPoint: .bottom, endPoint: .top)

        ZStack {
            // outline
            RoundedRectangle(cornerRadius: handThickness / 1.5)
                .strokeBorder(stroke, lineWidth: max(1, handThickness * 0.45))
                .frame(width: handThickness, height: handLen)
                .offset(y: baseY)

            // fill
            RoundedRectangle(cornerRadius: handThickness / 2)
                .fill(grad)
                .frame(width: handThickness, height: fillH)
                .offset(y: baseY - fillH)

            // tip jewel
            Circle()
                .fill(.white)
                .frame(width: tipRadius, height: tipRadius)
                .offset(y: baseY - handLen - tipRadius * 0.12)
                .shadow(color: glow, radius: tipRadius)
        }
        .rotationEffect(.degrees(rotationDeg))
        .position(x: center.x, y: center.y)
        .shadow(color: glow, radius: 6)
        .blendMode(.screen)
    }
}

private struct HandStepLabel: View {
    let center: CGPoint
    let haloR: CGFloat
    let haloStroke: CGFloat
    let outerR: CGFloat
    let rotationDeg: Double
    let text: String
    let color: Color
    let size: CGFloat

    var body: some View {
        let handLen   = outerR - (haloR + haloStroke)
        let y         = -(haloR + haloStroke) - handLen * 0.82
        let digitSize = max(12, size * 0.044)

        ZStack {
            Text(text)
                .font(.system(size: digitSize, weight: .black, design: .rounded))
                .foregroundColor(color)
                .shadow(color: .white.opacity(0.7), radius: 4)
                .rotationEffect(.degrees(-rotationDeg)) // keep upright
                .offset(y: y)
                .minimumScaleFactor(0.75)
                .lineLimit(1)
        }
        .rotationEffect(.degrees(rotationDeg)) // rotate with hand
        .position(x: center.x, y: center.y)
    }
}

// MARK: - Helpers

/// Create a Color from hex strings like "#RRGGBB" or "#RRGGBBAA".
private func kaiColor(_ hex: String, alpha: Double = 1.0) -> Color {
    var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    if hexString.hasPrefix("#") { hexString.removeFirst() }

    var n: UInt64 = 0
    guard Scanner(string: hexString).scanHexInt64(&n) else { return Color.white.opacity(alpha) }

    let r, g, b, a: UInt64
    switch hexString.count {
    case 6:
        r = (n >> 16) & 0xFF
        g = (n >> 8)  & 0xFF
        b =  n        & 0xFF
        a = 0xFF
    case 8:
        r = (n >> 24) & 0xFF
        g = (n >> 16) & 0xFF
        b = (n >> 8)  & 0xFF
        a =  n        & 0xFF
    default:
        return Color.white.opacity(alpha)
    }

    let fa = min(1.0, max(0.0, alpha * Double(a) / 255.0))
    return Color(red: Double(r) / 255.0,
                 green: Double(g) / 255.0,
                 blue: Double(b) / 255.0,
                 opacity: fa)
}
