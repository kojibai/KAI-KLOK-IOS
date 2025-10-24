//  MonthKalendarModal.swift
//  KaiKlok
//
//  Atlantean Lumitech • “Kairos Kalendar” — Month Modal (spiral v6.4 parity)
//  Camera math fixed: screen-space camera with correct pixel offsets,
//  pinch + double-tap anchoring, follow mode centering, and cancellable ticks.
//
import SwiftUI
import Foundation
import QuartzCore
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Shared Kai Constants (KKS v1.0)

private enum WK {
    static let kaiPulseSec: Double = 3 + sqrt(5)                  // ≈ 5.236067977
    static let pulseMsExact: Double = kaiPulseSec * 1000.0

    static let genesisUTC: Date = {
        var comps = DateComponents()
        comps.calendar = Calendar(identifier: .gregorian)
        comps.timeZone = TimeZone(secondsFromGMT: 0)
        comps.year = 2024; comps.month = 5; comps.day = 10
        comps.hour = 6; comps.minute = 45; comps.second = 41; comps.nanosecond = 888_000_000
        return comps.date!
    }()

    static let dayPulses: Double = 17_491.270_421                 // HARMONIC_DAY_PULSES
    static let pulsesPerStepMicro: Int64 = 11_000_000             // 11 pulses / step
    static let onePulseMicro: Int64 = 1_000_000
    static let nDayMicro: Int64 = 17_491_270_421                  // exact μpulses/day

    // μpulses per beat = (μpulses per day)/36, ties-to-even
    static var muPerBeatExact: Int64 { (nDayMicro + 18) / 36 }

    static let phi: Double = (1 + sqrt(5)) / 2
}

// MARK: - Domain (parity with TSX)

enum DayName: String, CaseIterable, Codable {
    case Solhara, Aquaris, Flamora, Verdari, Sonari, Kaelith
}

struct KaiKlockSnapshot: Equatable {
    let harmonicDay: DayName
    let kairos_seal_day_month: String
    let eternalKaiPulseToday: Double?
    let SpiralArc: String?
}

struct MonthNote: Identifiable, Equatable { let pulse: Double; let id: String; let text: String }

struct MonthHarmonicDayInfo: Equatable {
    let name: DayName
    let kaiTimestamp: String
    let startPulse: Double
}

// MARK: - Colors

private extension Color {
    static func kai(_ hex: String) -> Color {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var n: UInt64 = 0; Scanner(string: s).scanHexInt64(&n)
        return Color(.sRGB,
                     red:   Double((n >> 16) & 255) / 255,
                     green: Double((n >>  8) & 255) / 255,
                     blue:  Double( n        & 255) / 255,
                     opacity: 1)
    }

    static let nebulaBase = Color.kai("#04060c")
    static let nebulaDeep = Color.kai("#01050e")
    static let aquaCore   = Color.kai("#00eaff")
    static func aquaSoft(_ a: Double) -> Color { Color(.sRGB, red: 0, green: 234/255, blue: 1, opacity: a) }
    static func sealGlow(_ a: Double) -> Color { Color(.sRGB, red: 0, green: 234/255, blue: 1, opacity: a) }
    static let noteDot       = Color.kai("#ff1559")
    static let etherik0      = Color.kai("#8beaff")
    static let etherik1      = Color.kai("#c7f4ff")
}

private let MONTH_DAY_COLOR: [DayName: Color] = [
    .Solhara: Color.kai("#ff0024"),
    .Aquaris: Color.kai("#ff6f00"),
    .Flamora: Color.kai("#ffd600"),
    .Verdari: Color.kai("#00c853"),
    .Sonari:  Color.kai("#00b0ff"),
    .Kaelith: Color.kai("#c186ff"),
]

// MARK: - μpulse math

private struct LocalKai {
    let beat: Int
    let step: Int
    let pulsesIntoDay: Double
    let dayOfMonth: Int      // 1..42
    let monthIndex1: Int     // 1..8
    let weekday: DayName
    let monthDayIndex: Int   // 0..41
    let chakraStepString: String
    let sealText: String
}

private func roundTiesToEven(_ x: Double) -> Int64 {
    guard x.isFinite else { return 0 }
    let s = x < 0 ? -1.0 : 1.0
    let ax = abs(x)
    let i = floor(ax)
    let f = ax - i
    if f < 0.5 { return Int64(s * i) }
    if f > 0.5 { return Int64(s * (i + 1)) }
    let ii = Int(i)
    return Int64(s * (ii.isMultiple(of: 2) ? i : (i + 1)))
}
private func floorDiv(_ n: Int64, _ d: Int64) -> Int64 {
    let q = n / d, r = n % d
    return (r != 0 && ((r > 0) != (d > 0))) ? (q - 1) : q
}
private func imod(_ n: Int64, _ m: Int64) -> Int64 {
    let r = n % m; return r >= 0 ? r : r + m
}
private func microPulsesSinceGenesis(_ now: Date) -> Int64 {
    let deltaSec = now.timeIntervalSince(WK.genesisUTC)
    let pulses = deltaSec / WK.kaiPulseSec
    let micro = pulses * 1_000_000.0
    return roundTiesToEven(micro)
}
private func pad2(_ n: Int) -> String { String(format: "%02d", n) }

private func computeLocalKai(_ now: Date) -> LocalKai {
    let pμ_total  = microPulsesSinceGenesis(now)
    let pμ_in_day = imod(pμ_total, WK.nDayMicro)
    let dayIndex  = floorDiv(pμ_total, WK.nDayMicro)

    let beat = Int(floorDiv(pμ_in_day, WK.muPerBeatExact))         // 0..35
    let pμ_in_beat = pμ_in_day - Int64(beat) * WK.muPerBeatExact
    var step = Int(floorDiv(pμ_in_beat, WK.pulsesPerStepMicro))    // 0..43
    step = min(max(step, 0), 43)

    let pulsesIntoDay = Double(floorDiv(pμ_in_day, WK.onePulseMicro))

    let weekdayIdx = Int(imod(dayIndex, 6))
    let weekday = DayName.allCases[weekdayIdx]

    let dayIndexNum = Int(dayIndex)
    let dayOfMonth = ((dayIndexNum % 42) + 42) % 42 + 1
    let monthIndex0 = (dayIndexNum / 42) % 8
    let monthIndex1 = ((monthIndex0 + 8) % 8) + 1

    let monthDayIndex = dayOfMonth - 1
    let chakra = "\(beat):\(pad2(step))"
    let seal = "\(chakra) — D\(dayOfMonth)/M\(monthIndex1)"
    return .init(beat: beat, step: step, pulsesIntoDay: pulsesIntoDay,
                 dayOfMonth: dayOfMonth, monthIndex1: monthIndex1, weekday: weekday,
                 monthDayIndex: monthDayIndex, chakraStepString: chakra, sealText: seal)
}

// MARK: - Spiral geometry (7 turns × 6 days/turn)

private struct SpiralPoint {
    let x: CGFloat
    let y: CGFloat
    let thetaDeg: CGFloat
    let r: CGFloat
}

private func spiralPoints() -> [SpiralPoint] {
    let daysPerTurn = 6.0
    let turns = 7.0
    let total = Int(daysPerTurn * turns) // 42 nodes
    let thetaStep = 360.0 / daysPerTurn  // 60°
    let theta0 = -90.0                   // start at top
    let a = 9.5
    let growth = WK.phi                  // φ per revolution
    let k = log(growth) / (2 * .pi)
    var out: [SpiralPoint] = []
    out.reserveCapacity(total)
    for i in 0..<total {
        let θdegD = theta0 + Double(i) * thetaStep
        let θD = θdegD * .pi / 180.0
        let rev = Double(i) / daysPerTurn
        let rD = a * exp(k * 2 * .pi * rev)
        let xD = rD * cos(θD), yD = rD * sin(θD)
        out.append(.init(x: CGFloat(xD),
                         y: CGFloat(yD),
                         thetaDeg: CGFloat(θdegD),
                         r: CGFloat(rD)))
    }
    return out
}

// MARK: - Main Modal (Spiral)

struct MonthKalendarModal: View {
    // Props parity with TSX
    let DAYS: [DayName]                        // TSX uses DAYS[i % 6] directly — no D1 rotation
    let initialData: KaiKlockSnapshot?
    let notes: [MonthNote]
    let onSelectDay: (DayName, Int) -> Void
    let onAddNote: (Int) -> Void
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Live Kai + comet progress
    @State private var localKai: LocalKai? = nil
    @State private var monthProg: Double = 0        // index + fraction across today

    // Day detail
    @State private var dayDetail: MonthHarmonicDayInfo? = nil
    @State private var suppressBackdropUntil: CFTimeInterval = 0

    // Camera modes/state
    enum CamMode { case fit, follow, free }
    struct Cam { var x: CGFloat; var y: CGFloat; var z: CGFloat }
    @State private var camMode: CamMode = .fit
    @State private var cam: Cam = .init(x: 0, y: 0, z: 1)

    // Auto-fit bounds (“viewBox”)
    @State private var vbX: CGFloat = -60
    @State private var vbY: CGFloat = -60
    @State private var vbW: CGFloat = 120
    @State private var vbH: CGFloat = 120

    // Gesture/tap-guard
    @State private var movedPx: CGFloat = 0

    // RAF-like batching
    @State private var dl: CADisplayLinkWrapper? = nil
    @State private var pendingCam: Cam? = nil

    // Ark hue (for comet twinkle & seal glow)
    @State private var arkColor: Color = Color.kai("#8beaff")

    // Spiral cache
    private let points = spiralPoints()

    // µpulse scheduler cancellation
    @State private var _tickGen: Int = 0

    // Initial parse
    private var initIdx: Int {
        let seal = initialData?.kairos_seal_day_month ?? "D?/M?"
        if let m = seal.firstMatch(regex: #"D\s*(\d+)"#), let n = Int(m) { return max(0, min(41, n-1)) }
        return 0
    }
    private var initSeal: String {
        (initialData?.kairos_seal_day_month ?? "D?/M?")
            .replacingOccurrences(of: #"D\s+(\d+)"#, with: "D$1", options: .regularExpression)
            .replacingOccurrences(of: #"/\s*M(\d+)"#, with: "/M$1", options: .regularExpression)
    }

    // Notes → day index set
    private var noteSet: Set<Int> {
        var s = Set<Int>(); s.reserveCapacity(notes.count)
        for n in notes { s.insert(Int(floor(n.pulse / WK.dayPulses))) }
        return s
    }

    // Pulse animation phase (for spiral neon breathing, like TSX)
    @State private var pulseBreath: Bool = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // BACKDROP — opaque cosmic portal (clickable to close)
                NebulaBackdrop()
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if CACurrentMediaTime() >= suppressBackdropUntil { onClose() }
                    }

                // PANEL (non-closing; events are stopped like TSX panel)
                ZStack {
                    // Atlantean Close glyph (safe-area aware)
                    GlyphClose()
                        .frame(width: 42, height: 42)
                        .accessibilityLabel("Close month view")
                        .position(x: geo.size.width - (geo.safeAreaInsets.trailing + 28),
                                  y: geo.safeAreaInsets.top + 28)
                        .onTapGesture { onClose() }

                    // STAGE (centered, no push-down): draw in WORLD coords,
                    // map to SCREEN via toScreen(...), then apply SCREEN-space camera.
                    ZStack {
                        spiralRibbon(geo: geo)

                        // Day chips EXACTLY at spiral nodes
                        ForEach(0..<points.count, id: \.self) { i in
                            dayNode(i, geo: geo)
                        }

                        cometLayer(geo: geo)
                    }
                    // SCREEN-space camera (corrected pixel math)
                    .scaleEffect(cam.z)
                    .offset(x: cam.x, y: cam.y)
                    .contentShape(Rectangle())
                    .background(Color.clear)
                    .overlay(
                        // Gestures: pan + pinch (centroid anchored) + double-tap
                        GestureSurface(
                            cam: $cam,
                            camMode: $camMode,
                            movedPx: $movedPx,
                            onDoubleTapAt: { screenPt in
                                autoFreeMode()
                                toggleDoubleTapZoom(at: screenPt) // screen anchor
                                movedPx = 9999
                            },
                            onPan: { delta in
                                autoFreeMode()
                                // pan operates in SCREEN space
                                cam.x += delta.width
                                cam.y += delta.height
                            },
                            onPinch: { state in
                                autoFreeMode()
                                // SCREEN-space, centroid-anchored scaling:
                                // T_new = T_old + (1 - z_new/z_old) * (centroid - T_old)
                                let old = cam
                                var newZ = old.z * state.scale
                                newZ = clampZ(newZ)
                                let k = (old.z == 0) ? 0 : (1 - (newZ / old.z))
                                var newT = CGPoint(x: old.x + k * (state.location.x - old.x),
                                                   y: old.y + k * (state.location.y - old.y))
                                // add two-finger pan drift (centroid moved)
                                if let prev = state.previousLocation {
                                    newT.x += (state.location.x - prev.x)
                                    newT.y += (state.location.y - prev.y)
                                }
                                cam = .init(x: newT.x, y: newT.y, z: newZ)
                                movedPx = 9999
                            }
                        )
                    )

                    // Camera controls (safe-area aware)
                    HStack(spacing: 6) {
                        CamButton(title: "Fit", active: camMode == .fit) { mod in
                            if mod.shift || mod.meta {
                                focusDay(0, targetZ: 8, geo: geo)
                                camMode = .free
                            } else {
                                camMode = .fit; cam = .init(x: 0, y: 0, z: 1)
                            }
                        }
                        CamButton(title: "Follow", active: camMode == .follow) { _ in
                            camMode = .follow; followCometSnap(geo: geo)
                        }
                        CamButton(title: "Free", active: camMode == .free) { _ in
                            camMode = .free
                        }
                    }
                    .position(x: 72, y: geo.size.height - (geo.safeAreaInsets.bottom + 44))

                    // Seal chip — μpulse accurate (safe-area aware)
                    SealChip(text: (squashSeal(localKai?.sealText ?? initSeal)), ark: arkColor)
                        .position(x: geo.size.width/2,
                                  y: geo.size.height - (geo.safeAreaInsets.bottom + 84))
                        .accessibilityHidden(true)
                }
                .ignoresSafeArea()

                // Day detail
                if let dd = dayDetail {
                    DayDetailModalView(info: dd) { dayDetail = nil }
                        .transition(.opacity .combined(with: .scale))
                        .zIndex(10)
                }
            }
            .onAppear {
                syncArkHue()
                computeViewBox()
                _tickGen &+= 1
                scheduleAlignedTicks(generation: _tickGen, geo: geo)
                attachDisplayLink()
                monthProg = Double(initIdx)
                pulseBreath.toggle() // start neon breathing
            }
            .onDisappear {
                // cancel tick loop + display link
                _tickGen &+= 1
                dl?.invalidate(); dl = nil
            }
            // iOS 17+ onChange API: two-parameter closure
            .onChange(of: camMode) { _, newValue in
                if newValue == .fit { cam = .init(x: 0, y: 0, z: 1) }
                if newValue == .follow { followCometSnap(geo: geo) }
            }
        }
    }

    // MARK: - Helpers (split heavy expressions)

    // Spiral ribbon split out
    @ViewBuilder
    private func spiralRibbon(geo: GeometryProxy) -> some View {
        Path { path in
            guard let first = points.first else { return }
            path.move(to: toScreen(CGPoint(x: first.x, y: first.y), geo: geo))
            for p in points.dropFirst() {
                path.addLine(to: toScreen(CGPoint(x: p.x, y: p.y), geo: geo))
            }
        }
        .stroke(
            LinearGradient(colors: [.aquaCore, Color.kai("#ff1559")],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)
        )
        .opacity(pulseBreath ? 0.85 : 0.55)
        .animation(reduceMotion ? nil : .easeInOut(duration: WK.kaiPulseSec).repeatForever(autoreverses: true),
                   value: pulseBreath)
        .shadow(color: .aquaCore.opacity(0.85), radius: 6)
    }

    // Day chip node split out (this was the type-checker hot spot)
    @ViewBuilder
    private func dayNode(_ i: Int, geo: GeometryProxy) -> some View {
        let p = points[i]
        let day: DayName = DAYS.isEmpty ? DayName.allCases[i % 6] : DAYS[i % DAYS.count]
        let isToday = i == (localKai?.monthDayIndex ?? initIdx)
        let hasNote = noteSet.contains(i)
        let angle = p.thetaDeg + 90
        let base = toScreen(CGPoint(x: p.x, y: p.y), geo: geo)
        let label = "\(day.rawValue.prefix(3)) • \(i+1)"
        let color = MONTH_DAY_COLOR[day] ?? .white

        DayChip(center: base,
                chipAngle: isToday ? 0 : angle,
                isToday: isToday,
                hasNote: hasNote,
                color: color,
                label: label)
        .accessibilityLabel("\(day.rawValue) day \(i + 1)")
        .contentShape(Rectangle())
        // Double-tap to add note (SwiftUI uses onTapGesture(count:))
        .onTapGesture(count: 2) {
            onAddNote(i)
        }
        // Single tap to open
        .onTapGesture {
            if movedPx < 8 {
                suppressBackdropUntil = CACurrentMediaTime() + 0.35
                openDay(day: day, idx: i)
            }
        }
    }

    // Comet split out
    @ViewBuilder
    private func cometLayer(geo: GeometryProxy) -> some View {
        let comet = interpolatedComet()
        Comet(core: .etherik0, twinkle: arkColor)
            .position(toScreen(comet.point, geo: geo))
            .rotationEffect(.degrees(Double(comet.angle + CGFloat(90))))
            .animation(reduceMotion ? nil : .interpolatingSpring(stiffness: 120, damping: 18),
                       value: comet.point)
    }

    private func squashSeal(_ s: String) -> String {
        s.replacingOccurrences(of: #"D\s+(\d+)"#, with: "D$1", options: .regularExpression)
         .replacingOccurrences(of: #"/\s*M(\d+)"#, with: "/M$1", options: .regularExpression)
    }

    // Base fit scale to emulate SVG viewBox "xMidYMid meet"
    private func fitScale(_ geo: GeometryProxy) -> CGFloat {
        let sx = geo.size.width / vbW
        let sy = geo.size.height / vbH
        return min(sx, sy)
    }

    // World → Screen: SVG viewBox-style centering (NO push-down)
    private func toScreen(_ world: CGPoint, geo: GeometryProxy) -> CGPoint {
        let s = fitScale(geo)
        let cx = geo.size.width / 2
        let cy = geo.size.height / 2
        let wx = world.x - (vbX + vbW/2)
        let wy = world.y - (vbY + vbH/2)
        return CGPoint(x: cx + wx * s, y: cy + wy * s)
    }

    // Ark hue mapping (sets comet twinkle + seal hues)
    private func syncArkHue() {
        let map: [String: Color] = [
            "Ignition ArK":"#ff0024",
            "Integration ArK":"#ff6f00",
            "Harmonization ArK":"#ffd600",
            "Reflection ArK":"#00c853",
            "Purification ArK":"#00b0ff",
            "Dream ArK":"#c186ff",
        ].mapValues { Color.kai($0) }
        if let arc = initialData?.SpiralArc, let c = map[arc] {
            arkColor = c
        } else {
            arkColor = Color.kai("#8beaff")
        }
    }

    // μpulse scheduler (no drift) — boundary-aligned to genesis (cancellable)
    private func scheduleAlignedTicks(generation gen: Int, geo: GeometryProxy) {
        // initial compute
        let k0 = computeLocalKai(Date()); localKai = k0
        monthProg = Double(k0.monthDayIndex) + min(1, max(0, k0.pulsesIntoDay / WK.dayPulses))

        var targetBoundary: CFTimeInterval = {
            let nowMs = CFAbsoluteTimeGetCurrent() * 1000.0
            let genesisMs = WK.genesisUTC.timeIntervalSince1970 * 1000.0
            let elapsed = nowMs - genesisMs
            let periods = ceil(elapsed / WK.pulseMsExact)
            return genesisMs + periods * WK.pulseMsExact
        }()

        func fire() {
            // cancel if view disappeared / generation advanced
            guard gen == _tickGen else { return }

            let now = CFAbsoluteTimeGetCurrent() * 1000.0
            if now >= targetBoundary {
                let missed = Int(floor((now - targetBoundary) / WK.pulseMsExact))
                for _ in 0...missed {
                    let k = computeLocalKai(Date()); localKai = k
                    monthProg = Double(k.monthDayIndex) + min(1, max(0, k.pulsesIntoDay / WK.dayPulses))
                    if camMode == .follow { followCometSnap(geo: geo) }
                    targetBoundary += WK.pulseMsExact
                }
            }
            let delay = max(0, targetBoundary - CFAbsoluteTimeGetCurrent() * 1000.0)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay/1000.0) { fire() }
        }
        let initialDelay = max(0, targetBoundary - CFAbsoluteTimeGetCurrent() * 1000.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + initialDelay/1000.0) { fire() }
    }

    // MARK: - Camera & viewBox

    private func computeViewBox() {
        guard let minX = points.map(\.x).min(),
              let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(),
              let maxY = points.map(\.y).max() else { return }
        let pad: CGFloat = 14
        vbX = minX - pad; vbY = minY - pad; vbW = (maxX - minX) + pad*2; vbH = (maxY - minY) + pad*2
        if camMode == .fit { cam = .init(x: 0, y: 0, z: 1) }
    }

    private func followCometSnap(geo: GeometryProxy) {
        let target = interpolatedComet().point
        // base screen position without camera
        let s0 = toScreen(target, geo: geo)
        let center = CGPoint(x: geo.size.width/2, y: geo.size.height/2)
        let z = cam.z
        // camera is screen-space: T = center - z * s0
        setCamBatched(.init(x: center.x - z * s0.x, y: center.y - z * s0.y, z: z))
    }

    private func focusDay(_ idx: Int, targetZ: CGFloat = 6, geo: GeometryProxy) {
        guard idx >= 0 && idx < points.count else { return }
        let p = points[idx]
        let s0 = toScreen(CGPoint(x: p.x, y: p.y), geo: geo) // base screen pos without camera
        let center = CGPoint(x: geo.size.width/2, y: geo.size.height/2)
        let z = clampZ(targetZ)
        setCamBatched(.init(x: center.x - z * s0.x, y: center.y - z * s0.y, z: z))
    }

    private func clampZ(_ z: CGFloat) -> CGFloat { max(0.5, min(14, z)) }
    private func autoFreeMode() { if camMode != .free { camMode = .free } }

    // RAF-batched camera updates for smoothness
    private func attachDisplayLink() {
        dl = CADisplayLinkWrapper { _ in
            if let next = pendingCam {
                pendingCam = nil
                withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.82)) { cam = next }
            }
        }
        dl?.add(to: .main)
    }
    private func setCamBatched(_ next: Cam) { pendingCam = next }

    // MARK: - Double-tap zoom (anchor SCREEN point)

    private func toggleDoubleTapZoom(at screenPt: CGPoint) {
        let from = cam.z
        let to: CGFloat = from < 3.2 * 0.9 ? 3.2 : 1.0
        // keep the tapped screen point fixed after zoom:
        // T_new = T_old + (1 - to/from) * (anchor - T_old)
        let k = (from == 0) ? 0 : (1 - (to / from))
        let x = cam.x + k * (screenPt.x - cam.x)
        let y = cam.y + k * (screenPt.y - cam.y)
        setCamBatched(.init(x: x, y: y, z: to))
    }

    // MARK: - Comet interpolation

    private func interpolatedComet() -> (point: CGPoint, angle: CGFloat) {
        let clamped = max(0.0, min(Double(points.count - 1), monthProg))
        let i0 = Int(floor(clamped))
        let i1 = min(points.count - 1, i0 + 1)
        let t = CGFloat(clamped - Double(i0))
        let p0 = points[i0], p1 = points[i1]
        let x = p0.x + (p1.x - p0.x) * t
        let y = p0.y + (p1.y - p0.y) * t
        let a = p0.thetaDeg + (p1.thetaDeg - p0.thetaDeg) * t
        return (CGPoint(x: x, y: y), a)
    }

    // MARK: - Day open

    private func monthDayStartPulse(targetIdx: Int) -> Double {
        let curIdx = localKai?.monthDayIndex ?? initIdx
        let pulsesIntoDay: Double = {
            if let v = initialData?.eternalKaiPulseToday { return v }
            return localKai?.pulsesIntoDay ?? 0
        }()
        let todayZero = floor(pulsesIntoDay / WK.dayPulses) * WK.dayPulses
        return todayZero + Double(targetIdx - curIdx) * WK.dayPulses
    }

    private func openDay(day: DayName, idx: Int) {
        onSelectDay(day, idx)
        let monthIndex = localKai?.monthIndex1 ?? 1
        let beatStep = localKai?.chakraStepString ?? "0:00"
        let kaiTimestamp = squashSeal("\(beatStep) — D\(idx + 1)/M\(monthIndex)")
        dayDetail = MonthHarmonicDayInfo(
            name: day,
            kaiTimestamp: kaiTimestamp,
            startPulse: monthDayStartPulse(targetIdx: idx)
        )
    }
}

// MARK: - UI Pieces (unchanged except small tap improvements)

private struct GlyphClose: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hover = false
    @State private var tapDown = false

    var body: some View {
        let base = ZStack {
            Polygon(sides: 6)
                .stroke(LinearGradient(colors: [.aquaCore, Color.kai("#ff1559")],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 4)
                .blur(radius: 1.2)
                .shadow(color: .aquaCore.opacity(0.75), radius: 8)
                .shadow(color: Color.kai("#ff1559").opacity(0.75), radius: 12)
            Path { p in
                p.move(to: CGPoint(x: 12, y: 12)); p.addLine(to: CGPoint(x: 52, y: 52))
                p.move(to: CGPoint(x: 52, y: 12)); p.addLine(to: CGPoint(x: 12, y: 52))
                p.move(to: CGPoint(x: 32, y: 8));  p.addLine(to: CGPoint(x: 32, y: 56))
                p.move(to: CGPoint(x: 8,  y: 32)); p.addLine(to: CGPoint(x: 56, y: 32))
            }
            .stroke(LinearGradient(colors: [.aquaCore, Color.kai("#ff1559")],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 4)
            .blur(radius: 1.0)
        }
        .frame(width: 42, height: 42)

        base
            .rotationEffect(.degrees(reduceMotion ? 0 : (hover ? 135 : tapDown ? 45 : 0)))
            .scaleEffect(reduceMotion ? 1 : (hover ? 1.18 : tapDown ? 0.92 : 1))
            .animation(.spring(response: 0.24, dampingFraction: 0.82), value: hover)
            .animation(.spring(response: 0.24, dampingFraction: 0.82), value: tapDown)
            .contentShape(Rectangle())
            #if os(macOS)
            .onHover { hover = $0 }
            #endif
            .gesture(DragGesture(minimumDistance: 0).onChanged { _ in tapDown = true }.onEnded { _ in tapDown = false })
    }
}

private struct DayChip: View {
    let center: CGPoint
    let chipAngle: CGFloat
    let isToday: Bool
    let hasNote: Bool
    let color: Color
    let label: String

    var body: some View {
        let w: CGFloat = 8.5, h: CGFloat = 4.6, r: CGFloat = 1.6

        let strokeStyle: AnyShapeStyle = isToday
        ? AnyShapeStyle(LinearGradient(colors:[.etherik0,.etherik1],
                                       startPoint:.topLeading, endPoint:.bottomTrailing))
        : AnyShapeStyle(Color.white.opacity(0.2))

        ZStack {
            RoundedRectangle(cornerRadius: r, style: .continuous)
                .fill(color)
                .frame(width: w, height: h)
                .overlay(
                    RoundedRectangle(cornerRadius: r, style: .continuous)
                        .stroke(strokeStyle, lineWidth: isToday ? 1.2 : 0.6)
                )
                .shadow(color: isToday ? .aquaCore : .white.opacity(0.2), radius: isToday ? 8 : 3)

            if isToday {
                RoundedRectangle(cornerRadius: r, style: .continuous)
                    .stroke(LinearGradient(colors:[.etherik0,.etherik1],
                                           startPoint:.topLeading, endPoint:.bottomTrailing),
                            lineWidth: 1.4)
                    .frame(width: w, height: h)
                    .shadow(color: .etherik0.opacity(0.9), radius: 6)
            }

            if hasNote {
                Circle().fill(Color.noteDot)
                    .frame(width: 1.8, height: 1.8)
                    .offset(x: w/2 - 1.2, y: -h/2 + 1.2)
                    .shadow(color: .noteDot, radius: 4)
                    .shadow(color: .noteDot, radius: 8)
            }

            // Label always upright (flip when tangent is upside-down)
            let a = (chipAngle.truncatingRemainder(dividingBy: 360) + 360)
                .truncatingRemainder(dividingBy: 360)
            let needsFlip = a > 90 && a < 270
            Text(label)
                .font(.system(size: 2.8, weight: .semibold))
                .foregroundColor(color)
                .shadow(color: .black.opacity(0.65), radius: 2)
                .offset(y: -(h + 0.6))
                .rotationEffect(.degrees(needsFlip ? 180 : 0))
                .accessibilityHidden(true)
        }
        .position(center)
        .rotationEffect(.degrees(Double(chipAngle)))
    }
}

private struct Comet: View {
    let core: Color
    let twinkle: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tw: Bool = false

    var body: some View {
        ZStack {
            // baby-blue breath
            ZStack {
                Circle().fill(LinearGradient(colors: [.etherik0,.etherik1], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 4.4, height: 4.4)
                    .opacity(0.95)
                Circle().fill(LinearGradient(colors: [.etherik0,.etherik1], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .opacity(0.55).frame(width: 8.8, height: 8.8)
                Circle().fill(LinearGradient(colors: [.etherik0,.etherik1], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .opacity(0.26).frame(width: 13.2, height: 13.2)
                Circle().stroke(LinearGradient(colors: [.etherik0,.etherik1], startPoint: .topLeading, endPoint: .bottomTrailing),
                                lineWidth: 1.1)
                    .frame(width: 15.2, height: 15.2)
                    .opacity(0.9)
            }
            .scaleEffect(reduceMotion ? 1 : (tw ? 1.06 : 0.98))
            .opacity(reduceMotion ? 1 : (tw ? 1.0 : 0.9))
            .animation(reduceMotion ? nil : .easeInOut(duration: WK.kaiPulseSec).repeatForever(autoreverses: true), value: tw)

            // Ark twinkle
            ZStack {
                Rectangle().fill(LinearGradient(colors:[twinkle, twinkle.opacity(0.2)], startPoint:.leading, endPoint:.trailing)).frame(width: 6.4, height: 0.9)
                Rectangle().fill(LinearGradient(colors:[twinkle, twinkle.opacity(0.2)], startPoint:.top, endPoint:.bottom)).frame(width: 0.9, height: 6.4)
                Rectangle().fill(LinearGradient(colors:[twinkle, twinkle.opacity(0.6)], startPoint:.leading, endPoint:.trailing)).frame(width: 4.4, height: 0.7).rotationEffect(.degrees(45))
                Rectangle().fill(LinearGradient(colors:[twinkle, twinkle.opacity(0.6)], startPoint:.leading, endPoint:.trailing)).frame(width: 4.4, height: 0.7).rotationEffect(.degrees(-45))
                Circle().fill(twinkle).frame(width: 1.8, height: 1.8).opacity(0.9)
            }
            .rotationEffect(.degrees(reduceMotion ? 45 : (tw ? 405 : 45)))
            .scaleEffect(reduceMotion ? 1 : (tw ? 1.18 : 0.92))
            .opacity(reduceMotion ? 0.85 : (tw ? 1.0 : 0.6))
            .animation(reduceMotion ? nil : .easeInOut(duration: WK.kaiPulseSec).repeatForever(autoreverses: true), value: tw)
        }
        .shadow(color: core, radius: 6)
        .shadow(color: core, radius: 10)
        .onAppear { tw.toggle() }
        .accessibilityHidden(true)
    }
}

private struct SealChip: View {
    let text: String
    let ark: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var up = false
    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 13, weight: .medium, design: .monospaced))
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Color.aquaSoft(0.14))
            .foregroundColor(Color.kai("#e6faff"))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.sealGlow(0.36), lineWidth: 1))
            .shadow(color: Color.sealGlow(0.42), radius: 12)
            .overlay(
                RoundedRectangle(cornerRadius: 16).stroke(ark.opacity(0.28), lineWidth: 0.8)
            )
            .offset(y: up ? -8 : 0)
            .shadow(color: Color.sealGlow(0.42), radius: up ? 16 : 12)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: WK.kaiPulseSec).repeatForever(autoreverses: true)) { up = true }
            }
            .allowsHitTesting(false)
    }
}

private struct CamButton: View {
    let title: String
    let active: Bool
    let action: (ModifierKeyEvent) -> Void
    var body: some View {
        Button {
            #if os(macOS)
            action(.init(shift: NSEvent.modifierFlags.contains(.shift),
                         meta: NSEvent.modifierFlags.contains(.command)))
            #else
            action(.init(shift: false, meta: false))
            #endif
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(active ? Color.aquaCore.opacity(0.18) : Color.white.opacity(0.08))
                .foregroundColor(.white.opacity(0.9))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(active ? Color.aquaCore.opacity(0.36) : Color.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) camera")
        .accessibilityAddTraits(active ? .isSelected : [])
    }
    struct ModifierKeyEvent { let shift: Bool; let meta: Bool }
}

// MARK: - Gestures (pan + pinch + double-tap)

#if canImport(UIKit)
private struct GestureSurface: UIViewRepresentable {
    @Binding var cam: MonthKalendarModal.Cam
    @Binding var camMode: MonthKalendarModal.CamMode
    @Binding var movedPx: CGFloat

    let onDoubleTapAt: (CGPoint) -> Void
    let onPan: (CGSize) -> Void
    struct PinchState {
        enum Phase { case began, changed, ended }
        let phase: Phase
        let scale: CGFloat            // incremental ratio
        let location: CGPoint         // current centroid (screen)
        let previousLocation: CGPoint?// previous centroid (screen)
    }
    let onPinch: (PinchState) -> Void

    func makeUIView(context: Context) -> UIView {
        let v = UIView(frame: .zero)
        v.isMultipleTouchEnabled = true
        v.backgroundColor = .clear

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.onPan(_:)))
        pan.minimumNumberOfTouches = 1; pan.maximumNumberOfTouches = 2
        pan.cancelsTouchesInView = false
        pan.delegate = context.coordinator

        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.onPinch(_:)))
        pinch.cancelsTouchesInView = false
        pinch.delegate = context.coordinator

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.onDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.cancelsTouchesInView = true

        v.addGestureRecognizer(pan); v.addGestureRecognizer(pinch); v.addGestureRecognizer(doubleTap)
        context.coordinator.host = self
        return v
    }
    func updateUIView(_ uiView: UIView, context: Context) { }
    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var host: GestureSurface!
        var lastT: CGPoint = .zero
        var lastScale: CGFloat = 1
        var lastCentroid: CGPoint? = nil // screen-space

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        @objc func onPan(_ g: UIPanGestureRecognizer) {
            if host.camMode != .free { host.camMode = .free }
            switch g.state {
            case .began:
                host.movedPx = 0; lastT = .zero
            case .changed:
                let t = g.translation(in: g.view)
                let dt = CGPoint(x: t.x - lastT.x, y: t.y - lastT.y)
                lastT = t
                host.movedPx = max(host.movedPx, hypot(t.x, t.y))
                host.onPan(CGSize(width: dt.x, height: dt.y))  // screen delta
            default:
                break
            }
        }
        @objc func onPinch(_ g: UIPinchGestureRecognizer) {
            if host.camMode != .free { host.camMode = .free }
            let loc = g.location(in: g.view)
            switch g.state {
            case .began:
                lastScale = 1
                lastCentroid = loc
                host.onPinch(.init(phase: .began, scale: 1, location: loc, previousLocation: loc))
            case .changed:
                let ratio = g.scale / max(0.0001, lastScale) // incremental
                let prev = lastCentroid
                lastScale = g.scale
                lastCentroid = loc
                host.onPinch(.init(phase: .changed, scale: ratio, location: loc, previousLocation: prev))
                host.movedPx = 9999
            default:
                host.onPinch(.init(phase: .ended, scale: 1, location: loc, previousLocation: lastCentroid))
                lastCentroid = nil
            }
        }
        @objc func onDoubleTap(_ g: UITapGestureRecognizer) {
            host.onDoubleTapAt(g.location(in: g.view))
        }
    }
}
#else
private struct GestureSurface: View {
    @Binding var cam: MonthKalendarModal.Cam
    @Binding var camMode: MonthKalendarModal.CamMode
    @Binding var movedPx: CGFloat
    let onDoubleTapAt: (CGPoint) -> Void
    let onPan: (CGSize) -> Void
    struct PinchState { enum Phase { case began, changed, ended }; let phase: Phase; let scale: CGFloat; let location: CGPoint; let previousLocation: CGPoint? }
    let onPinch: (PinchState) -> Void
    var body: some View { Color.clear.contentShape(Rectangle()) }
}
#endif

// MARK: - Day detail

private struct DayDetailModalView: View {
    let info: MonthHarmonicDayInfo
    let onClose: () -> Void
    var body: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
                .onTapGesture { onClose() }
            VStack(spacing: 12) {
                HStack {
                    Text(info.name.rawValue).font(.headline).foregroundColor(.white)
                    Spacer()
                    Button(action: onClose) { Image(systemName: "xmark").font(.headline.bold()) }.tint(.white)
                }
                .padding(.horizontal, 14).padding(.top, 12)
                Text(info.kaiTimestamp)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
                Text("Start pulse: \(Int(info.startPulse))")
                    .font(.footnote).foregroundColor(.white.opacity(0.7))
                Spacer(minLength: 6)
            }
            .frame(maxWidth: 420)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(18)
        }
    }
}

// MARK: - Backdrop & utilities

private struct NebulaBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [.nebulaBase, .nebulaDeep], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color.black.opacity(0.1), .clear], center: .center, startRadius: 0, endRadius: 600)
                .blendMode(.screen)
            Canvas { ctx, size in
                let count = 350
                for _ in 0..<count {
                    let x = CGFloat.random(in: 0...size.width)
                    let y = CGFloat.random(in: 0...size.height)
                    let r = CGFloat.random(in: 0.4...1.0)
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)), with: .color(.white.opacity(0.06)))
                }
            }
            .blendMode(.screen)
            .opacity(0.9)
        }
    }
}

private struct Polygon: Shape {
    let sides: Int
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height)/2
        for i in 0..<sides {
            let aD = (Double(i) * (360.0/Double(sides)) - 90) * .pi / 180
            let cosA = CGFloat(cos(aD)), sinA = CGFloat(sin(aD))
            let pt = CGPoint(x: c.x + cosA * r, y: c.y + sinA * r)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath(); return p
    }
}

private final class CADisplayLinkWrapper {
    private let link: CADisplayLink
    private let tick: (CADisplayLink) -> Void
    init(_ tick: @escaping (CADisplayLink) -> Void) {
        self.tick = tick
        self.link = CADisplayLink(target: DisplayLinkProxy.shared, selector: #selector(DisplayLinkProxy.shared.onTick(_:)))
        DisplayLinkProxy.shared.tick = tick
    }
    func add(to runloop: RunLoop) { link.add(to: runloop, forMode: .common) }
    func invalidate() { link.invalidate() }
    private final class DisplayLinkProxy: NSObject {
        static let shared = DisplayLinkProxy()
        var tick: ((CADisplayLink) -> Void)?
        @objc func onTick(_ dl: CADisplayLink) { tick?(dl) }
    }
}

private extension String {
    func firstMatch(regex: String) -> String? {
        guard let r = try? NSRegularExpression(pattern: regex) else { return nil }
        guard let m = r.firstMatch(in: self, options: [], range: NSRange(location: 0, length: (self as NSString).length)) else { return nil }
        guard m.numberOfRanges >= 2 else { return nil }
        let range = m.range(at: 1)
        if let swiftRange = Range(range, in: self) { return String(self[swiftRange]) }
        return nil
    }
}

// MARK: - Preview

#Preview("Kairos Month Spiral") {
    MonthKalendarModal(
        DAYS: [.Solhara,.Aquaris,.Flamora,.Verdari,.Sonari,.Kaelith],
        initialData: .init(
            harmonicDay: .Solhara,
            kairos_seal_day_month: "0:00 — D1/M1",
            eternalKaiPulseToday: nil,
            SpiralArc: "Reflection ArK"
        ),
        notes: [ .init(pulse: 0, id: "n0", text: "Hello") ],
        onSelectDay: {_,_ in}, onAddNote: {_ in}, onClose: {}
    )
}
