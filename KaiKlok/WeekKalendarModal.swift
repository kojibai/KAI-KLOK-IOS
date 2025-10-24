//  WeekKalendarModal.swift
//  KaiKlok
//
//  Atlantean Lumitech • “Kairos Kalendar” — Week Modal (full-screen, giant rings, inline labels, progress-only today)
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Atlantean Constants (parity with TSX)

private enum WK {
    // φ breath (≈ 5.236s) and genesis timestamp (UTC: 2024-05-10 06:45:41.888)
    static let kaiPulseSec: Double = 3 + sqrt(5)            // ≈ 5.2360679
    static let pulseMsExact: Double = kaiPulseSec * 1000.0
    static let genesisUTC: Date = {
        var comps = DateComponents()
        comps.calendar = Calendar(identifier: .gregorian)
        comps.timeZone = TimeZone(secondsFromGMT: 0)
        comps.year = 2024; comps.month = 5; comps.day = 10
        comps.hour = 6; comps.minute = 45; comps.second = 41; comps.nanosecond = 888_000_000
        return comps.date!
    }()
    // “day” = fixed number of pulses (from TSX constants)
    static let dayPulses: Double = 17_491.270_421
    static let pulsesPerStep: Double = 11.0
    static let beatsPerDay: Double = 36.0

    // Storage keys
    static let notesKey = "kairosNotes"
    static let hiddenIdsKey = "kairosNotesHiddenIds"

    // Z-layers
    static let zBase: Double = 10_000
}

private let PHI = (1 + sqrt(5.0)) / 2.0

// MARK: - Canonical Day & Palette

private enum Day: String, CaseIterable {
    case Solhara, Aquaris, Flamora, Verdari, Sonari, Kaelith
    var color: Color {
        switch self {
        case .Solhara: return Color(hex: "#ff0024")
        case .Aquaris: return Color(hex: "#ff6f00")
        case .Flamora: return Color(hex: "#ffd600")
        case .Verdari: return Color(hex: "#00c853")
        case .Sonari:  return Color(hex: "#00b0ff")
        case .Kaelith: return Color(hex: "#c186ff")
        }
    }
    var arc: String {
        switch self {
        case .Solhara: return "Ignition ArK"
        case .Aquaris: return "Integration ArK"
        case .Flamora: return "Harmonization ArK"
        case .Verdari: return "Reflection ArK"
        case .Sonari:  return "Purification ArK"
        case .Kaelith: return "Dream ArK"
        }
    }
}

// MARK: - Models

struct HarmonicDayInfo: Identifiable, Equatable {
    var id: String { kaiTimestamp + name }
    let name: String       // Day.rawValue
    let kaiTimestamp: String // “beat:step — D#/M#”
    let startPulse: Double  // absolute pulse @ day start
}

struct Note: Identifiable, Codable, Equatable {
    let id: String
    let text: String
    let pulse: Double   // absolute pulse when created
    let beat: Int
    let step: Int
    let createdAt: TimeInterval
}

private struct LocalKai {
    let beat: Int
    let step: Int
    let pulsesIntoDay: Double
    let harmonicDay: Day
    let dayOfMonth: Int  // 1…42
    let monthIndex1: Int // 1…8
    var chakraStepString: String { "\(beat):\(String(format: "%02d", step))" }
}

// MARK: - Math (pulse-aligned, offline, double-precision port)

private func microPulsesSinceGenesis(_ now: Date) -> Double {
    let dt = now.timeIntervalSince(WK.genesisUTC)  // seconds
    let pulses = dt / WK.kaiPulseSec               // pulses
    return pulses * 1_000_000.0                    // μpulses (double)
}

private func imod(_ n: Double, _ m: Double) -> Double {
    let r = n.truncatingRemainder(dividingBy: m)
    return r < 0 ? r + m : r
}

private func euclidMod(_ n: Int, _ m: Int) -> Int {
    let r = n % m
    return r < 0 ? r + m : r
}

private func computeLocalKai(now: Date) -> LocalKai {
    let μp = microPulsesSinceGenesis(now)                  // double μpulses
    let μpInDay = imod(μp, WK.dayPulses * 1_000_000.0)
    let dayIndex = Int(floor(μp / (WK.dayPulses * 1_000_000.0)))

    // convert back to pulses to avoid rounding drift
    let pulsesIntoDay = floor(μpInDay / 1_000_000.0)

    // beats/steps
    let beat = Int(floor((pulsesIntoDay / WK.dayPulses) * WK.beatsPerDay))
    let intoBeat = (pulsesIntoDay - (Double(beat) * (WK.dayPulses / WK.beatsPerDay)))
    let step = max(0, min(43, Int(floor(intoBeat / WK.pulsesPerStep))))

    // weekday
    let weekdayIdx = euclidMod(dayIndex, 6)
    let harmonicDay = Day.allCases[weekdayIdx]

    // month/day (42-day months, 8 months)
    let dm = euclidMod(dayIndex, 42) + 1
    let monthIndex0 = Int(floor(Double(dayIndex) / 42.0))
    let mi1 = euclidMod(monthIndex0, 8) + 1

    return .init(
        beat: beat,
        step: step,
        pulsesIntoDay: pulsesIntoDay,
        harmonicDay: harmonicDay,
        dayOfMonth: dm,
        monthIndex1: mi1
    )
}

private func dayStartPulse(todayAbsolutePulse: Double, todayDay: Day, targetIndex i: Int) -> Double {
    let wholeDays = floor(todayAbsolutePulse / WK.dayPulses)
    let todayZero = wholeDays * WK.dayPulses
    let curIdx = Day.allCases.firstIndex(of: todayDay) ?? 0
    return todayZero + Double(i - curIdx) * WK.dayPulses
}

private func addDaysWithinMonth(dayOfMonth1: Int, monthIndex1: Int, deltaDays: Int) -> (dayOfMonth: Int, monthIndex1: Int) {
    let dm0 = dayOfMonth1 - 1
    let total = dm0 + deltaDays
    let newDm0 = euclidMod(total, 42)
    let monthDelta = Int(floor(Double(total) / 42.0))
    let newMi1 = euclidMod(monthIndex1 - 1 + monthDelta, 8) + 1
    return (newDm0 + 1, newMi1)
}

private func deriveBeatStep(fromAbsPulse abs: Double) -> (beat: Int, step: Int) {
    let intoDay = imod(abs, WK.dayPulses)
    let beat = Int(floor(intoDay / (WK.dayPulses / WK.beatsPerDay)))
    let intoBeat = intoDay - Double(beat) * (WK.dayPulses / WK.beatsPerDay)
    let step = max(0, min(43, Int(floor(intoBeat / WK.pulsesPerStep))))
    return (beat, step)
}

private func squashSeal(_ s: String) -> String {
    s.replacingOccurrences(of: #"D\s+(\d+)"#, with: "D$1", options: .regularExpression)
     .replacingOccurrences(of: #"/\s*M(\d+)"#, with: "/M$1", options: .regularExpression)
}

// MARK: - Storage

private func loadNotes() -> [Note] {
    guard let d = UserDefaults.standard.data(forKey: WK.notesKey) else { return [] }
    do {
        let raw = try JSONDecoder().decode([Note].self, from: d)
        return raw.map { n in
            if n.beat >= 0 && n.step >= 0 { return n }
            let ds = deriveBeatStep(fromAbsPulse: n.pulse)
            return Note(id: n.id, text: n.text, pulse: n.pulse, beat: ds.beat, step: ds.step, createdAt: n.createdAt)
        }
    } catch { return [] }
}

private func saveNotes(_ ns: [Note]) {
    do {
        let d = try JSONEncoder().encode(ns)
        UserDefaults.standard.set(d, forKey: WK.notesKey)
    } catch { /* ignore */ }
}

private func loadHidden() -> Set<String> {
    (UserDefaults.standard.array(forKey: WK.hiddenIdsKey) as? [String]).map(Set.init) ?? []
}
private func saveHidden(_ ids: Set<String>) {
    UserDefaults.standard.set(Array(ids), forKey: WK.hiddenIdsKey)
}

// MARK: - Export (JSON / CSV)

private func augmentForExport(_ n: Note) -> [String: Any] {
    let dayIndex = Int(floor(n.pulse / WK.dayPulses))
    let day = Day.allCases[euclidMod(dayIndex, 6)]
    let dayOfMonth = euclidMod(dayIndex, 42) + 1
    let monthIndex1 = euclidMod(dayIndex / 42, 8) + 1
    let chakra = "\(n.beat):\(String(format: "%02d", n.step))"
    return [
        "id": n.id,
        "text": n.text,
        "pulse": n.pulse,
        "beat": n.beat,
        "step": n.step,
        "chakraStep": chakra,
        "dayIndex": dayIndex,
        "dayName": day.rawValue,
        "dayOfMonth": dayOfMonth,
        "monthIndex1": monthIndex1
    ]
}

private func exportJSONFile(notes: [Note]) -> URL? {
    let rows = notes.map(augmentForExport(_:))
    guard let data = try? JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted]) else { return nil }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("kairos-notes-P\(Int.random(in: 0...999_999)).json")
    try? data.write(to: url)
    return url
}

private func escapeCSV(_ s: String) -> String {
    if s.contains(#","#) || s.contains(#"""#) || s.contains("\n") {
        return "\"\(s.replacingOccurrences(of: #"""#, with: "\"\""))\""
    }
    return s
}

private func exportCSVFile(notes: [Note]) -> URL? {
    let headers = ["id","text","pulse","beat","step","chakraStep","dayIndex","dayName","dayOfMonth","monthIndex1"]
    var out = headers.joined(separator: ",") + "\n"
    for n in notes {
        let row = augmentForExport(n)
        let chakra = "\(n.beat):\(String(format:"%02d", n.step))"
        let line = [
            "\(n.id)",
            escapeCSV(n.text),
            "\(n.pulse)",
            "\(n.beat)",
            "\(n.step)",
            chakra,
            "\(row["dayIndex"] as? Int ?? 0)",
            "\(row["dayName"] as? String ?? "")",
            "\(row["dayOfMonth"] as? Int ?? 0)",
            "\(row["monthIndex1"] as? Int ?? 0)"
        ].joined(separator: ",") + "\n"
        out += line
    }
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("kairos-notes-P\(Int.random(in: 0...999_999)).csv")
    try? out.data(using: .utf8)?.write(to: url)
    return url
}

// MARK: - Main View

struct WeekKalendarModal: View {
    // hosting
    let onClose: () -> Void

    // live state
    @State private var localKai = computeLocalKai(now: Date())
    @State private var absolutePulseNow: Double = 0
    @State private var monthOpen: Bool = false

    // notes + panel-only hides
    @State private var notes: [Note] = loadNotes()
    @State private var hiddenIds: Set<String> = loadHidden()

    // overlays
    @State private var showNoteEditor = false
    @State private var noteDraft: String = ""
    @State private var noteDraftPulse: Double = 0
    @State private var dayDetail: HarmonicDayInfo?

    // export sheet
    @State private var exportURL: URL?
    @State private var showShare = false

    // aligned φ scheduler
    @State private var targetBoundary: Date = .now
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { geo in
            let headerOffset = geo.safeAreaInsets.top + 72 // push header well into viewport

            ZStack {
                BackdropNebula()
                    .ignoresSafeArea()
                    .opacity(monthOpen ? 0.25 : 0.96)

                // Header + Toggle + Seal (stacked, guaranteed spacing)
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Button { onClose() } label: { GodX() }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Close")
                    }
                    .padding(.top, headerOffset)
                    .padding(.horizontal, 16)

                    TogglePill(monthOpen: monthOpen) {
                        monthOpen = false
                        dayDetail = nil
                    } onMonth: {
                        dayDetail = nil
                        monthOpen = true
                    }
                    .padding(.top, 14)

                    // Seal chip sits BELOW the toggle with a fixed gap
                    SealChip(text: squashSeal("\(localKai.chakraStepString) — D\(localKai.dayOfMonth)/M\(localKai.monthIndex1)"))
                        .padding(.top, 10) // 👈 keeps clear space between pill and tabs

                    Spacer(minLength: 0)
                }
                .ignoresSafeArea()
                .zIndex(WK.zBase + 1)

                // Stage (WEEK RINGS) — GIANT (fills stage)
                WeekRings(
                    localKai: localKai,
                    absolutePulseNow: absolutePulseNow,
                    onPick: { day, idx in
                        let dm = addDaysWithinMonth(dayOfMonth1: localKai.dayOfMonth, monthIndex1: localKai.monthIndex1, deltaDays: idx - (Day.allCases.firstIndex(of: localKai.harmonicDay) ?? 0))
                        let kaiSeal = squashSeal("\(localKai.chakraStepString) — D\(dm.dayOfMonth)/M\(dm.monthIndex1)")
                        let start = dayStartPulse(todayAbsolutePulse: absolutePulseNow, todayDay: localKai.harmonicDay, targetIndex: idx)
                        dayDetail = HarmonicDayInfo(name: day.rawValue, kaiTimestamp: kaiSeal, startPulse: start)
                    }
                )
                .padding(.horizontal, 10)
                .padding(.vertical, 20)
                .ignoresSafeArea()

                // Add note (bottom-trailing)
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            noteDraft = ""
                            noteDraftPulse = absolutePulseNow > 0 ? absolutePulseNow : localKai.pulsesIntoDay
                            showNoteEditor = true
                        } label: { AddNoteButton() }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add note")
                        .padding(.trailing, 16)
                        .padding(.bottom, geo.safeAreaInsets.bottom + 20)
                    }
                }

                // Notes Dock (bottom-left-ish)
                VStack {
                    Spacer()
                    HStack {
                        NotesDock(
                            notes: notes.filter { !hiddenIds.contains($0.id) }.sorted { $0.pulse < $1.pulse },
                            onClear: {
                                var next = hiddenIds
                                for n in notes { next.insert(n.id) }
                                hiddenIds = next
                                saveHidden(next)
                            },
                            onExportJSON: {
                                if let url = exportJSONFile(notes: notes) { exportURL = url; showShare = true }
                            },
                            onExportCSV: {
                                if let url = exportCSVFile(notes: notes) { exportURL = url; showShare = true }
                            }
                        )
                        .padding(.leading, 16)
                        .padding(.bottom, geo.safeAreaInsets.bottom + 16)
                        Spacer()
                    }
                }
            }
            .onAppear { alignAndStart() }
            // iOS 17+ onChange (two-parameter action) — avoids deprecation
            .onChange(of: scenePhase) { oldPhase, newPhase in
                if newPhase == .active { alignAndStart() }
            }
            // export share sheet
            .sheet(isPresented: $showShare, onDismiss: { exportURL = nil }) {
                if let url = exportURL {
                    ShareSheet(activityItems: [url])
                } else {
                    Text("Nothing to share")
                }
            }
            // Month cover — call the correct initializer
            .fullScreenCover(isPresented: $monthOpen) {
                MonthKalendarModal(
                    DAYS: [.Solhara,.Aquaris,.Flamora,.Verdari,.Sonari,.Kaelith],
                    initialData: .init(
                        harmonicDay: DayName(rawValue: localKai.harmonicDay.rawValue) ?? .Solhara,
                        kairos_seal_day_month: squashSeal("\(localKai.chakraStepString) — D\(localKai.dayOfMonth)/M\(localKai.monthIndex1)"),
                        eternalKaiPulseToday: localKai.pulsesIntoDay,
                        SpiralArc: localKai.harmonicDay.arc
                    ),
                    notes: [], // or map your week notes to MonthNote if you want badges
                    onSelectDay: { _,_  in },
                    onAddNote: { _ in },
                    onClose: { monthOpen = false }
                )
                .ignoresSafeArea()
            }
        }
    }

    // MARK: Kai scheduler (align to next φ boundary)
    private func alignAndStart() {
        tick() // snap immediately
        let now = Date()
        let elapsed = now.timeIntervalSince(WK.genesisUTC) * 1000.0
        let periods = ceil(elapsed / WK.pulseMsExact)
        let nextMs = WK.genesisUTC.timeIntervalSince1970 * 1000.0 + periods * WK.pulseMsExact
        targetBoundary = Date(timeIntervalSince1970: nextMs / 1000.0)
        Task.detached { await loop() }
    }

    private func loop() async {
        while true {
            let delay = max(0, targetBoundary.timeIntervalSinceNow)
            try? await Task.sleep(nanoseconds: UInt64((delay) * 1_000_000_000))
            await MainActor.run {
                let now = Date()           // <- was 'var', never mutated
                var nxt = targetBoundary
                while now >= nxt {
                    tick()
                    nxt = nxt.addingTimeInterval(WK.kaiPulseSec)
                }
                targetBoundary = nxt
            }
        }
    }

    private func tick() {
        let now = Date()
        let lk = computeLocalKai(now: now)
        localKai = lk
        let μp = microPulsesSinceGenesis(now)
        absolutePulseNow = floor(μp / 1_000_000.0)
    }
}

// MARK: - Rings Stage (GIANT + labels on stroke + progress-only today)

private struct WeekRings: View {
    let localKai: LocalKai
    let absolutePulseNow: Double
    let onPick: (Day, Int) -> Void

    private struct Ring: Identifiable {
        let id = UUID()
        let day: Day
        let idx: Int
        let frac: CGFloat     // size as fraction of stage
        let color: Color
        let delay: Double
    }

    // Six-day cycle visuals — massive sizes that fill the stage.
    // Outer ring ≈ 96% of minSide; inner rings step down.
    private var rings: [Ring] {
        let fracs: [CGFloat] = [0.96, 0.86, 0.76, 0.66, 0.56, 0.46]
        return Day.allCases.enumerated().map { i, d in
            .init(
                day: d,
                idx: i,
                frac: fracs[i],
                color: d.color,
                delay: (Double(i) * PHI).truncatingRemainder(dividingBy: 1) * WK.kaiPulseSec
            )
        }
    }

    var body: some View {
        GeometryReader { geo in
            let minSide = min(geo.size.width, geo.size.height)
            let dayProgress = CGFloat(min(1.0, max(0.0, localKai.pulsesIntoDay / WK.dayPulses)))

            ZStack {
                ForEach(rings) { ring in
                    let isToday = (localKai.harmonicDay == ring.day)
                    let strokeW = isToday ? max(8, minSide * 0.018) : max(6, minSide * 0.012)

                    // Track geometry per ring
                    let w = ring.frac * minSide
                    let h = w * 0.72
                    let r: CGFloat = max(10, w * 0.08)

                    // Base ring — for NON-today only (today remainder is EMPTY)
                    if !isToday {
                        RacetrackPath(width: w, height: h, radius: r)
                            .stroke(ring.color.opacity(0.58),
                                    style: StrokeStyle(lineWidth: strokeW, lineCap: .round))
                            .frame(width: minSide, height: minSide)
                            .modifier(BreathingStroke(isToday: false, delay: ring.delay))
                            .contentShape(Rectangle())
                            .onTapGesture { onPick(ring.day, ring.idx) }
                    }

                    // PROGRESS arc (TODAY ONLY) — trimmed stroke from 0 → fraction of day
                    if isToday {
                        RacetrackPath(width: w, height: h, radius: r)
                            .trim(from: 0, to: dayProgress)
                            .stroke(
                                AngularGradient(
                                    gradient: Gradient(colors: [.white.opacity(0.92), ring.color, ring.color]),
                                    center: .center
                                ),
                                style: StrokeStyle(lineWidth: strokeW, lineCap: .round, lineJoin: .round)
                            )
                            .frame(width: minSide, height: minSide)
                            .shadow(color: ring.color.opacity(0.45), radius: 12, y: 0)
                            .animation(.easeInOut(duration: WK.kaiPulseSec).repeatForever(autoreverses: true), value: dayProgress)
                            .contentShape(Rectangle())
                            .onTapGesture { onPick(ring.day, ring.idx) }
                    }

                    // Day label positioned relative to each ring
                    ZStack {}
                        .frame(width: minSide, height: minSide)
                        .overlay(
                            Text(ring.day.rawValue)
                                .font(.system(size: max(12, minSide * 0.028), weight: .semibold, design: .rounded))
                                .foregroundStyle(ring.color)
                                .shadow(color: .black.opacity(0.55), radius: 8, y: 2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.ultraThinMaterial, in: Capsule())
                                .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 1))
                                .offset(y: -h/2 - strokeW * 0.6)
                                .modifier(TodayLabelGlow(active: isToday)),
                            alignment: .center
                        )
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .rotation3DEffect(.degrees(18), axis: (x: 1, y: 0, z: 0))
        }
        .allowsHitTesting(true)
    }
}

private struct RacetrackPath: Shape {
    let width: CGFloat
    let height: CGFloat
    let radius: CGFloat
    func path(in rect: CGRect) -> Path {
        let w = width
        let h = height
        let r = min(radius, min(w, h) * 0.5)
        var p = Path()
        p.move(to: CGPoint(x: -w/2 + r, y: -h/2))
        p.addLine(to: CGPoint(x:  w/2 - r, y: -h/2))
        p.addQuadCurve(to: CGPoint(x:  w/2, y: -h/2 + r), control: CGPoint(x:  w/2, y: -h/2))
        p.addLine(to: CGPoint(x:  w/2, y:  h/2 - r))
        p.addQuadCurve(to: CGPoint(x:  w/2 - r, y:  h/2), control: CGPoint(x:  w/2, y:  h/2))
        p.addLine(to: CGPoint(x: -w/2 + r, y:  h/2))
        p.addQuadCurve(to: CGPoint(x: -w/2, y:  h/2 - r), control: CGPoint(x: -w/2, y:  h/2))
        p.addLine(to: CGPoint(x: -w/2, y: -h/2 + r))
        p.addQuadCurve(to: CGPoint(x: -w/2 + r, y: -h/2), control: CGPoint(x: -w/2, y: -h/2))
        let t = CGAffineTransform(translationX: rect.midX, y: rect.midY)
        return p.applying(t)
    }
}

private struct BreathingStroke: ViewModifier {
    let isToday: Bool
    let delay: Double
    @State private var phase: Double = 0
    func body(content: Content) -> some View {
        content
            .opacity(isToday ? 0.9 : 0.58)
            .onAppear {
                withAnimation(Animation.easeInOut(duration: WK.kaiPulseSec).delay(delay).repeatForever(autoreverses: true)) {
                    phase = 1
                }
            }
            .overlay {
                if isToday {
                    content
                        .shadow(color: .white.opacity(0.10), radius: 8)
                        .shadow(color: .white.opacity(0.06), radius: 14)
                }
            }
    }
}

private struct TodayLabelGlow: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        content
            .shadow(color: .white.opacity(active ? 0.32 : 0.0), radius: active ? 10 : 0)
            .animation(.easeInOut(duration: WK.kaiPulseSec).repeatForever(autoreverses: true), value: active)
    }
}

// MARK: - UI Bits

private struct BackdropNebula: View {
    var body: some View {
        LinearGradient(colors: [Color(hex:"#04060c"), Color(hex:"#01050e")], startPoint: .top, endPoint: .bottom)
            .overlay {
                Canvas { ctx, size in
                    var rng = SeededRandom(seed: 777)
                    for _ in 0..<280 {
                        let x = CGFloat(rng.next()) * size.width
                        let y = CGFloat(rng.next()) * size.height
                        let r = CGFloat(rng.next(in: 0.4...1.6))
                        ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)), with: .color(.white.opacity(0.12)))
                    }
                }
                .blendMode(.screen).opacity(0.22)
            }
            .overlay {
                RadialGradient(colors: [Color.cyan.opacity(0.10), .clear], center: .center, startRadius: 0, endRadius: 500)
                    .scaleEffect(1.02)
                    .opacity(0.35)
                    .blur(radius: 30)
                    .animation(.easeInOut(duration: WK.kaiPulseSec*2).repeatForever(autoreverses: true), value: UUID())
            }
    }
}

private struct GodX: View {
    var body: some View {
        ZStack {
            Color.clear.frame(width: 36, height: 36).clipShape(Circle())
            Image(systemName: "xmark")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(
                    LinearGradient(colors: [Color(hex:"#00eaff"), Color(hex:"#ff1559")], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .shadow(color: .cyan.opacity(0.6), radius: 8)
                .shadow(color: .pink.opacity(0.6), radius: 8)
        }
        .contentShape(Circle())
    }
}

private struct TogglePill: View {
    let monthOpen: Bool
    let onWeek: () -> Void
    let onMonth: () -> Void
    var body: some View {
        HStack(spacing: 6) {
            SegButton(title: "Week", active: !monthOpen, action: onWeek)
            SegButton(title: "Month", active: monthOpen, action: onMonth)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(Color.white.opacity(0.08), in: Capsule())
        .overlay(Capsule().stroke(Color.cyan, lineWidth: 2))
        .shadow(color: .cyan.opacity(0.35), radius: 8)
    }
    private struct SegButton: View {
        let title: String; let active: Bool; let action: () -> Void
        var body: some View {
            Button(action: action) {
                Text(title).font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background((active ? Color.cyan : Color.white.opacity(0.12)), in: Capsule())
                    .foregroundStyle(active ? Color.black : Color.white)
            }.buttonStyle(.plain)
        }
    }
}

private struct SealChip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(.body, design: .monospaced).weight(.medium))
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Color.white.opacity(0.10), in: Capsule())
            .overlay(Capsule().stroke(Color.cyan.opacity(0.65), lineWidth: 1))
            .shadow(color: .cyan.opacity(0.35), radius: 8)
    }
}

private struct AddNoteButton: View {
    var body: some View {
        ZStack {
            Circle().fill(Color.cyan)
            Text("＋").font(.system(size: 24, weight: .heavy)).foregroundStyle(Color.black)
        }
        .frame(width: 52, height: 52)
        .shadow(color: .cyan.opacity(0.45), radius: 12)
    }
}

private struct NotesDock: View {
    let notes: [Note]
    let onClear: () -> Void
    let onExportJSON: () -> Void
    let onExportCSV: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Memories").font(.system(size: 14, weight: .semibold))
                Spacer()
                if !notes.isEmpty {
                    Button("Clear", action: onClear).buttonStyle(Chip())
                    Button("⤓ JSON", action: onExportJSON).buttonStyle(Chip())
                    Button("⤓ CSV", action: onExportCSV).buttonStyle(Chip())
                }
            }
            if notes.isEmpty {
                Text("No memories yet.")
                    .font(.system(size: 12))
                    .opacity(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(notes) { n in
                            Text("\(Int(round(n.pulse))) · \(n.beat):\(String(format:"%02d", n.step)) : \(n.text)")
                                .font(.system(size: 13))
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: min(240, UIScreen.main.bounds.height * 0.4))
            }
        }
        .padding(12)
        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
        .frame(width: min(440, UIScreen.main.bounds.width * 0.86))
    }

    private struct Chip: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(LinearGradient(colors: [.white.opacity(0.08), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.14), lineWidth: 1))
                .opacity(configuration.isPressed ? 0.8 : 1)
        }
    }
}

// MARK: - Modals

private struct NoteEditorModal: View {
    let pulseSeed: Double
    @State var text: String
    let onSave: (String, Double) -> Void
    @Environment(\.dismiss) private var dismiss

    init(pulseSeed: Double, initialText: String, onSave: @escaping (String, Double) -> Void) {
        self.pulseSeed = pulseSeed
        self._text = State(initialValue: initialText)
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("Add Memory").font(.headline)
            TextEditor(text: $text)
                .scrollContentBackground(.hidden)
                .frame(height: 140)
                .padding(8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    onSave(text.trimmingCharacters(in: .whitespacesAndNewlines), pulseSeed)
                    dismiss()
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .background(Color.black.opacity(0.8))
        .presentationDetents([.medium])
    }
}

private struct DayDetailSheet: View {
    let info: HarmonicDayInfo
    let onClose: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 10) {
            Text(info.name).font(.title2.bold())
            Text(info.kaiTimestamp).font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
            Text("Start pulse: \(Int(info.startPulse))").font(.caption)
                .foregroundStyle(.secondary)
            Button("Close") { dismiss(); onClose() }.buttonStyle(.bordered)
        }
        .padding(20)
        .background(LinearGradient(colors: [.black.opacity(0.95), .black.opacity(0.85)], startPoint: .top, endPoint: .bottom))
        .presentationDetents([.fraction(0.35), .medium])
    }
}


private struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> Double {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return Double((z ^ (z >> 31)) & 0xFFFFFFFFFFFFFFFF) / Double(UInt64.max)
    }
    mutating func next(in r: ClosedRange<Double>) -> Double {
        r.lowerBound + (r.upperBound - r.lowerBound) * next()
    }
}

#Preview("Week Kalendar • Atlantean") {
    WeekKalendarModal { }
}
