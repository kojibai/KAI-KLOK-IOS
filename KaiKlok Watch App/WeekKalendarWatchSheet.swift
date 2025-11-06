//  WeekKalendarWatchSheet.swift
//  KaiKlok Watch App — “Kairos Kalendar • μpulse-Exact • Notes & Export”
//  v1.1.0 (watchOS 10+)
//  - Exact boundary-aligned scheduler (genesis + P), zero drift
//  - 6-day Kai week with deterministic chakra colors
//  - Per-note Beat:Step stamping (11 pulses/step) + createdAt
//  - Panel-only hide (non-destructive), persistent with UserDefaults
//  - JSON/CSV export to Documents (Files app) with Kai-tagged filenames
//  - Compact Day Detail sheet + Note composer (watch-safe)
//  - Haptic confirm on successful/failed exports

import SwiftUI
import Foundation
import WatchKit

// MARK: - Kalendar constants (parity with app; local scope to avoid symbol clashes)

private enum KalKKS {
    static let phi: Double = (1 + sqrt(5)) / 2
    static let kaiPulseSec: Double = 3 + sqrt(5)                // ≈ 5.236067977…
    static let pulseMsExact: Double = kaiPulseSec * 1000.0

    // μpulse constants (exact; integer-safe)
    static let onePulseMicro: Int64 = 1_000_000
    static let nDayMicro: Int64 = 17_491_270_421
    static var muPerBeatExact: Int64 { (nDayMicro + 18) / 36 }  // ties-to-even split
    static let pulsesPerStepMicro: Int64 = 11_000_000           // 11 pulses/step
    static let dayPulses: Double = 17_491.270_421

    // Genesis (UTC): 2024-05-10 06:45:41.888
    static let genesisUTC: Date = {
        var c = DateComponents()
        c.calendar = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)
        c.year = 2024; c.month = 5; c.day = 10
        c.hour = 6; c.minute = 45; c.second = 41; c.nanosecond = 888_000_000
        return c.date!
    }()

    // helpers
    static func roundTiesToEven(_ x: Double) -> Int64 {
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
    static func floorDiv(_ n: Int64, _ d: Int64) -> Int64 {
        let q = n / d, r = n % d
        return (r != 0 && ((r > 0) != (d > 0))) ? (q - 1) : q
    }
    static func imod(_ n: Int64, _ m: Int64) -> Int64 { let r = n % m; return r >= 0 ? r : r + m }

    static func microPulsesSinceGenesis(_ now: Date) -> Int64 {
        let deltaSec = now.timeIntervalSince(genesisUTC)
        let pulses = deltaSec / kaiPulseSec
        return roundTiesToEven(pulses * 1_000_000.0)
    }

    static func pad2(_ n: Int) -> String { String(format: "%02d", n) }
}

// MARK: - Canon weekday + colors

private enum DayName: String, CaseIterable, Codable, Identifiable {
    case Solhara, Aquaris, Flamora, Verdari, Sonari, Kaelith
    var id: String { rawValue }
}

private func dayColor(_ d: DayName) -> Color {
    switch d {
    case .Solhara: return Color(hex: "#ff0024")
    case .Aquaris: return Color(hex: "#ff6f00")
    case .Flamora: return Color(hex: "#ffd600")
    case .Verdari: return Color(hex: "#00c853")
    case .Sonari:  return Color(hex: "#00b0ff")
    case .Kaelith: return Color(hex: "#c186ff")
    }
}

// MARK: - Local Kai snapshot (parity with main app, but namespaced)

private struct WKLocalKai: Codable, Equatable {
    let beat: Int              // 0..35
    let step: Int              // 0..43
    let wholePulsesIntoDay: Int
    let dayOfMonth: Int        // 1..42
    let monthIndex1: Int       // 1..8
    let yearIndex0: Int        // 0+
    let weekday: DayName
    var chakraStepString: String { "\(beat):\(KalKKS.pad2(step))" }
}

private func wkComputeLocalKai(_ now: Date) -> WKLocalKai {
    let pμ_total  = KalKKS.microPulsesSinceGenesis(now)
    let pμ_in_day = KalKKS.imod(pμ_total, KalKKS.nDayMicro)
    let dayIndex  = KalKKS.floorDiv(pμ_total, KalKKS.nDayMicro)

    let beat = Int(KalKKS.floorDiv(pμ_in_day, KalKKS.muPerBeatExact))
    let pμ_in_beat = pμ_in_day - Int64(beat) * KalKKS.muPerBeatExact
    var step = Int(KalKKS.floorDiv(pμ_in_beat, KalKKS.pulsesPerStepMicro))
    step = min(max(step, 0), 43)

    let pulsesIntoDay = Int(KalKKS.floorDiv(pμ_in_day, KalKKS.onePulseMicro))
    let weekdayIdx = Int(KalKKS.imod(dayIndex, 6))
    let weekday = DayName.allCases[weekdayIdx]

    let dayIndexNum = Int(dayIndex)
    let dayOfMonth = ((dayIndexNum % 42) + 42) % 42 + 1
    let monthIndex0 = (dayIndexNum / 42) % 8
    let monthIndex1 = ((monthIndex0 + 8) % 8) + 1
    let yearIndex0 = (dayIndexNum / 336)

    return .init(
        beat: beat, step: step, wholePulsesIntoDay: pulsesIntoDay,
        dayOfMonth: dayOfMonth, monthIndex1: monthIndex1, yearIndex0: yearIndex0,
        weekday: weekday
    )
}

// MARK: - Exact boundary-aligned ticker (independent of ContentView's PulseClock)

@MainActor
private final class KaiAlignedTicker: ObservableObject {
    @Published var now: Date = Date()
    @Published var kai: WKLocalKai = wkComputeLocalKai(Date())

    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "kai.kalendar.ticker", qos: .userInteractive)

    deinit { timer?.cancel() }

    func start() {
        scheduleAligned()
    }

    private func scheduleAligned() {
        timer?.cancel(); timer = nil

        func scheduleNext() {
            let nowMs = Date().timeIntervalSince1970 * 1000.0
            let genesisMs = KalKKS.genesisUTC.timeIntervalSince1970 * 1000.0
            let elapsed = nowMs - genesisMs
            let periods = ceil(elapsed / KalKKS.pulseMsExact)
            let boundaryMs = genesisMs + periods * KalKKS.pulseMsExact
            let initialDelay = max(0, boundaryMs - nowMs) / 1000.0

            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now() + initialDelay, repeating: .never, leeway: .nanoseconds(0))
            t.setEventHandler { [weak self] in
                guard let self else { return }
                let d = Date()
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.now = d
                    self.kai = wkComputeLocalKai(d)
                    self.timer?.cancel(); self.timer = nil
                    scheduleNext()
                }
            }
            self.timer = t
            t.resume()
        }
        scheduleNext()
    }
}

// MARK: - Notes (panel-only hide, JSON/CSV export)

private struct KalNote: Identifiable, Codable, Equatable {
    let id: String
    var text: String
    let pulse: Int            // absolute whole pulse
    let beat: Int
    let step: Int
    let createdAt: Double     // epoch seconds

    var chakraStep: String { "\(beat):\(KalKKS.pad2(step))" }
    var dayIndex: Int { Int(floor(Double(pulse) / KalKKS.dayPulses)) }
    var weekday: DayName { DayName.allCases[(dayIndex % 6 + 6) % 6] }
    var dayOfMonth: Int { (dayIndex % 42 + 42) % 42 + 1 }
    var monthIndex1: Int { ((dayIndex / 42) % 8 + 8) % 8 + 1 }
}

@MainActor
private final class KalNoteStore: ObservableObject {
    @Published var notes: [KalNote] = []
    @Published var hidden: Set<String> = []

    private let notesKey = "kairosNotes.watch"
    private let hiddenKey = "kairosNotesHiddenIds.watch"

    init() {
        load()
        loadHidden()
    }

    func add(text: String, at kai: WKLocalKai, absolutePulse: Int) {
        let n = KalNote(
            id: UUID().uuidString,
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            pulse: absolutePulse,
            beat: kai.beat,
            step: kai.step,
            createdAt: Date().timeIntervalSince1970
        )
        notes.append(n)
        save()
    }

    func hide(_ id: String) {
        hidden.insert(id); saveHidden()
    }

    func unhideAll() { hidden.removeAll(); saveHidden() }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: notesKey),
           let arr = try? JSONDecoder().decode([KalNote].self, from: data) {
            notes = arr
        }
    }
    private func save() {
        if let data = try? JSONEncoder().encode(notes) {
            UserDefaults.standard.set(data, forKey: notesKey)
        }
    }
    private func loadHidden() {
        if let data = UserDefaults.standard.array(forKey: hiddenKey) as? [String] {
            hidden = Set(data)
        }
    }
    private func saveHidden() {
        UserDefaults.standard.set(Array(hidden), forKey: hiddenKey)
    }

    // Export helpers
    func exportJSON(tagPulse: Int) -> URL? {
        let rows = notes.map { n -> [String: Any] in
            [
                "id": n.id, "text": n.text, "pulse": n.pulse,
                "beat": n.beat, "step": n.step, "chakraStep": n.chakraStep,
                "dayIndex": n.dayIndex, "dayName": n.weekday.rawValue,
                "dayOfMonth": n.dayOfMonth, "monthIndex1": n.monthIndex1,
                "createdAt": n.createdAt
            ]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted]) else { return nil }
        let url = documentsURL("kairos-notes-P\(tagPulse).json")
        do { try data.write(to: url, options: .atomic); return url } catch { return nil }
    }

    func exportCSV(tagPulse: Int) -> URL? {
        let headers = ["id","text","pulse","beat","step","chakraStep","dayIndex","dayName","dayOfMonth","monthIndex1","createdAt"]
        let csvRows: [String] = [headers.joined(separator: ",")] + notes.map { n in
            func esc(_ s: String) -> String {
                if s.contains("\"") || s.contains(",") || s.contains("\n") { return "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\"" }
                return s
            }
            let cols: [String] = [
                esc(n.id),
                esc(n.text),
                "\(n.pulse)",
                "\(n.beat)",
                "\(n.step)",
                esc(n.chakraStep),
                "\(n.dayIndex)",
                esc(n.weekday.rawValue),
                "\(n.dayOfMonth)",
                "\(n.monthIndex1)",
                "\(n.createdAt)"
            ]
            return cols.joined(separator: ",")
        }
        let data = csvRows.joined(separator: "\n").data(using: .utf8)!
        let url = documentsURL("kairos-notes-P\(tagPulse).csv")
        do { try data.write(to: url, options: .atomic); return url } catch { return nil }
    }

    private func documentsURL(_ filename: String) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent(filename)
    }
}

// MARK: - UI

struct WeekKalendarWatchSheet: View {
    @StateObject private var ticker = KaiAlignedTicker()
    @StateObject private var store  = KalNoteStore()

    @State private var showDayDetail: DayName? = nil
    @State private var showComposer = false
    @State private var composerPrefill = ""
    @State private var exportMessage: String? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 8) {
            // Header
            HStack {
                Image(systemName: "calendar").font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color(hex: "#7ff7ff"))
                Text("Week Kalendar").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 18, weight: .bold))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 6)

            // Today seal + D/M/Y
            HStack(spacing: 6) {
                let k = ticker.kai
                let seal = "\(k.chakraStepString) — D\(k.dayOfMonth)/M\(k.monthIndex1)/Y\(k.yearIndex0)"
                Text(seal)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 6)

            // 6-day week list (compact rows + progress for today)
            VStack(spacing: 6) {
                ForEach(DayName.allCases) { d in
                    WeekRow(
                        day: d,
                        isToday: d == ticker.kai.weekday,
                        progress: min(1.0, Double(ticker.kai.wholePulsesIntoDay) / KalKKS.dayPulses),
                        noteCount: store.notes.filter { $0.weekday == d && !store.hidden.contains($0.id) }.count
                    ) { showDayDetail = d }
                }
            }
            .padding(.horizontal, 6)

            // Actions
            HStack(spacing: 8) {
                Button {
                    composerPrefill = ""
                    showComposer = true
                } label: {
                    Label("Note", systemImage: "square.and.pencil")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(PillButton())

                Button {
                    if let url = store.exportJSON(tagPulse: absolutePulseNow()) {
                        exportMessage = "Saved JSON → \(url.lastPathComponent)"
                        WKInterfaceDevice.current().play(.success)
                    } else {
                        exportMessage = "Export failed."
                        WKInterfaceDevice.current().play(.failure)
                    }
                } label: {
                    Label("JSON", systemImage: "arrow.down.doc")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(PillButton())

                Button {
                    if let url = store.exportCSV(tagPulse: absolutePulseNow()) {
                        exportMessage = "Saved CSV → \(url.lastPathComponent)"
                        WKInterfaceDevice.current().play(.success)
                    } else {
                        exportMessage = "Export failed."
                        WKInterfaceDevice.current().play(.failure)
                    }
                } label: {
                    Label("CSV", systemImage: "tray.and.arrow.down")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(PillButton())
            }
            .padding(.top, 2)

            if let msg = exportMessage {
                Text(msg)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            // Memories dock (panel-only hide)
            VStack(spacing: 4) {
                HStack {
                    Text("Memories").font(.system(size: 12, weight: .semibold))
                    Spacer()
                    if !visibleNotes.isEmpty {
                        Button("Clear Panel") {
                            for n in visibleNotes { store.hide(n.id) }
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 6)

                if visibleNotes.isEmpty {
                    Text("No visible notes. Add one or unhide in a future build.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 6)
                } else {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(visibleNotes) { n in
                                NoteRow(n: n, onHide: { store.hide(n.id) })
                            }
                        }
                        .padding(.horizontal, 6)
                    }
                    .frame(maxHeight: 120)
                }
            }
            .padding(.top, 6)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .onAppear { ticker.start() }
        .sheet(item: $showDayDetail) { day in
            DayDetailSheet(
                day: day,
                liveKai: ticker.kai,
                notes: store.notes.filter { $0.weekday == day },
                onAdd: { text, kai, pulse in store.add(text: text, at: kai, absolutePulse: pulse) }
            )
        }
        .sheet(isPresented: $showComposer) {
            NoteComposerSheet(
                title: "New Note",
                initialText: composerPrefill,
                defaultKai: ticker.kai,
                onCommit: { text, kai, pulse in store.add(text: text, at: kai, absolutePulse: pulse) }
            )
        }
    }

    private var visibleNotes: [KalNote] {
        store.notes
            .filter { !store.hidden.contains($0.id) }
            .sorted { $0.pulse < $1.pulse }
    }

    private func absolutePulseNow() -> Int {
        // Match ContentView logic: whole pulses since genesis (absolute)
        let pμ = KalKKS.microPulsesSinceGenesis(Date())
        return Int(KalKKS.floorDiv(pμ, KalKKS.onePulseMicro))
    }
}

// MARK: - Rows & Sheets

private struct WeekRow: View {
    let day: DayName
    let isToday: Bool
    let progress: Double      // 0..1 for today
    let noteCount: Int
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Circle().fill(dayColor(day)).frame(width: 8, height: 8)
                Text(day.rawValue)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)

                if isToday {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.10))
                            Capsule().fill(dayColor(day).opacity(0.85))
                                .frame(width: max(0, geo.size.width * progress))
                        }
                    }
                    .frame(height: 6)
                    .clipShape(Capsule())
                    .padding(.horizontal, 6)
                } else {
                    Spacer(minLength: 0)
                }

                if noteCount > 0 {
                    Text("\(noteCount)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Color.white.opacity(0.12), in: Capsule())
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(Color(hex: "#08141b"), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct NoteRow: View {
    let n: KalNote
    var onHide: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(dayColor(n.weekday)).frame(width: 6, height: 6).padding(.top, 3)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("\(n.weekday.rawValue) D\(n.dayOfMonth)/M\(n.monthIndex1)")
                        .font(.system(size: 11, weight: .semibold))
                    Spacer()
                    Text(n.chakraStep)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Text(n.text).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
            }
            Button(action: onHide) {
                Image(systemName: "eye.slash").font(.system(size: 12, weight: .bold))
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(Color(hex: "#0a1b24"), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct DayDetailSheet: View {
    let day: DayName
    let liveKai: WKLocalKai
    let notes: [KalNote]
    var onAdd: (_ text: String, _ kai: WKLocalKai, _ absolutePulse: Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showComposer = false

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Circle().fill(dayColor(day)).frame(width: 8, height: 8)
                Text("\(day.rawValue) — Day Detail").font(.system(size: 15, weight: .semibold))
                Spacer()
                Button {
                    dismiss()
                } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 18, weight: .bold)) }
                .buttonStyle(.plain)
            }

            if notes.isEmpty {
                Text("No notes for this day yet.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(notes.sorted { $0.pulse < $1.pulse }) { n in
                            NoteRow(n: n, onHide: {}) // hide from panel only, not here
                                .opacity(0.95)
                        }
                    }.padding(.horizontal, 6)
                }
            }

            Button {
                showComposer = true
            } label: {
                Label("Add Note", systemImage: "square.and.pencil")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(PillButton())

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .sheet(isPresented: $showComposer) {
            // Default to *current* beat:step if same weekday, else beat 0 / step 0 of this day
            let defKai: WKLocalKai = (liveKai.weekday == day)
                ? liveKai
                : WKLocalKai(beat: 0, step: 0, wholePulsesIntoDay: 0, dayOfMonth: liveKai.dayOfMonth, monthIndex1: liveKai.monthIndex1, yearIndex0: liveKai.yearIndex0, weekday: day)
            NoteComposerSheet(
                title: "New \(day.rawValue) Note",
                initialText: "",
                defaultKai: defKai,
                onCommit: onAdd
            )
        }
    }
}

private struct NoteComposerSheet: View {
    let title: String
    let initialText: String
    let defaultKai: WKLocalKai
    var onCommit: (_ text: String, _ kai: WKLocalKai, _ absolutePulse: Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""
    @State private var beat: Int
    @State private var step: Int

    init(title: String, initialText: String, defaultKai: WKLocalKai,
         onCommit: @escaping (_ text: String, _ kai: WKLocalKai, _ absolutePulse: Int) -> Void) {
        self.title = title
        self.initialText = initialText
        self.defaultKai = defaultKai
        self.onCommit = onCommit
        _text = State(initialValue: initialText)
        _beat = State(initialValue: defaultKai.beat)
        _step = State(initialValue: defaultKai.step)
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(title).font(.system(size: 15, weight: .semibold))
            TextField("Type your note…", text: $text)
                .textInputAutocapitalization(.sentences)
                .padding(8)
                .background(Color(hex: "#0a1b24"), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            HStack {
                Stepper("Beat \(beat)", value: $beat, in: 0...35)
                Stepper("Step \(step)", value: $step, in: 0...43)
            }
            .font(.system(size: 11, weight: .semibold))
            .tint(Color(hex: "#7ff7ff"))

            Button {
                let kai = WKLocalKai(
                    beat: beat, step: step,
                    wholePulsesIntoDay: 0,
                    dayOfMonth: defaultKai.dayOfMonth,
                    monthIndex1: defaultKai.monthIndex1,
                    yearIndex0: defaultKai.yearIndex0,
                    weekday: defaultKai.weekday
                )
                // Convert beat:step to absolute pulse for *now* day index
                let absPulse = absolutePulseForNow(beat: beat, step: step)
                onCommit(text, kai, absPulse)
                dismiss()
            } label: {
                Label("Save", systemImage: "checkmark.circle")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(PillButton())

            Spacer(minLength: 0)
        }
        .padding()
    }

    private func absolutePulseForNow(beat: Int, step: Int) -> Int {
        // Absolute pulse = floor(dayIndex)*DAY_PULSES + (beat * pulsesPerBeat + step * 11)
        let now = Date()
        let pμ_total = KalKKS.microPulsesSinceGenesis(now)
        let dayIndex = KalKKS.floorDiv(pμ_total, KalKKS.nDayMicro)
        let base = Double(dayIndex) * KalKKS.dayPulses
        let pulsesPerBeat = Double(KalKKS.muPerBeatExact) / Double(KalKKS.onePulseMicro)
        let intoDay = Double(beat) * pulsesPerBeat + Double(step) * 11.0
        return Int(floor(base + intoDay))
    }
}

// MARK: - Styling helpers

private struct PillButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 6).padding(.horizontal, 12)
            .background(Color(hex: "#0a1b24"), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

private extension Color {
    init(hex: String, alpha: Double = 1.0) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var n: UInt64 = 0
        Scanner(string: s).scanHexInt64(&n)
        let r = Double((n >> 16) & 0xff) / 255.0
        let g = Double((n >>  8) & 0xff) / 255.0
        let b = Double( n        & 0xff) / 255.0
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}
