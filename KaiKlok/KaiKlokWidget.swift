//
//  KaiKlokWidget.swift
//  KaiKlokWidgets
//

import WidgetKit
import SwiftUI

// MARK: - Entry

struct KaiKlokEntry: TimelineEntry {
    let date: Date
    let dayName: String
    let monthName: String
    let dayNumber: Int
    let beat: Int
    let step: Int
}

// MARK: - Provider

struct KaiKlokProvider: TimelineProvider {
    func placeholder(in context: Context) -> KaiKlokEntry {
        KaiKlokEntry(date: Date(),
                     dayName: "Solhara",
                     monthName: "Aethon",
                     dayNumber: 1,
                     beat: 0,
                     step: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (KaiKlokEntry) -> Void) {
        completion(Self.makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<KaiKlokEntry>) -> Void) {
        // Build 30 minutes of entries (every ~5 minutes). WidgetKit will
        // actually render using "now", so using currentPulse() is fine.
        var entries: [KaiKlokEntry] = []
        let start = Date()
        for offset in stride(from: 0, through: 30, by: 5) {
            let when = Calendar.current.date(byAdding: .minute, value: offset, to: start) ?? start
            entries.append(Self.makeEntry(at: when))
        }
        completion(Timeline(entries: entries, policy: .after(start.addingTimeInterval(30*60))))
    }

    // MARK: - Helpers

    static func makeEntry(at _: Date = Date()) -> KaiKlokEntry {
        // Use your existing KairosTime API
        let pulse = KairosTime.currentPulse()
        let m = KairosTime.decodeMoment(for: pulse) // KairosMoment (beat/step inside)

        let bpd = KairosConstants.beatsPerDay
        let spb = KairosConstants.stepsPerBeat

        let dayIndex   = (pulse / (spb * bpd)) % 6
        let monthIndex = (pulse / (spb * bpd * 6)) % 8
        let dayNumber  = ((pulse / (spb * bpd)) % 42) + 1

        let dayName   = KairosLabelEngine.dayName(forDayIndex: dayIndex)
        let monthName = KairosLabelEngine.monthName(forMonthIndex: monthIndex)

        return KaiKlokEntry(date: Date(),
                            dayName: dayName,
                            monthName: monthName,
                            dayNumber: dayNumber,
                            beat: m.beat,
                            step: m.step)
    }
}

// MARK: - View

struct KaiKlokWidgetEntryView: View {
    var entry: KaiKlokProvider.Entry

    var body: some View {
        VStack(spacing: 4) {
            Text("\(entry.dayName), \(entry.monthName) \(entry.dayNumber)")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            Text("BEAT: \(entry.beat) · STEP: \(entry.step)")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .opacity(0.85)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(8)
        .background(Color.black)
        .foregroundStyle(.white)
    }
}

// MARK: - Widget

struct KaiKlokWidget: Widget {
    let kind: String = "KaiKlokWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: KaiKlokProvider()) { entry in
            KaiKlokWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Kai-Klok")
        .description("Day • Month • Day# and Kairos BEAT:STEP.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryRectangular, .accessoryInline
        ])
    }
}
