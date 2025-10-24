//
//  KaiKlokLiveActivity.swift
//  KaiKlokWidgets
//
//  Lock Screen + Dynamic Island for Kairos Time — Styled Like Native Clock
//

import SwiftUI
import ActivityKit
#if canImport(WidgetKit)
import WidgetKit
#endif

// Make sure KaiKlokAttributes is shared with BOTH targets (app + widget).

@available(iOS 16.1, *)
struct KaiKlokLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: KaiKlokAttributes.self) { context in
            // ⏱ LOCK SCREEN LIVE ACTIVITY (Lock Screen)
            ZStack {
                Color.black
                VStack(spacing: 4) {
                    // DAY NAME + MONTH NAME + DAY NUMBER
                    Text("\(context.state.chakraDay), \(context.state.monthName) \(context.state.dayNumber)")
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    // BEAT · STEP
                    Text("BEAT: \(context.state.beat) · STEP: \(context.state.step)")
                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding()
            }
        } dynamicIsland: { context in
            // 🌀 Dynamic Island
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text("\(context.state.chakraDay), \(context.state.monthName) \(context.state.dayNumber)")
                            .font(.subheadline)
                            .foregroundStyle(.white)
                        Text("B:\(context.state.beat) · S:\(context.state.step)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .padding(.vertical, 2)
                }
            } compactLeading: {
                Text("Φ").font(.caption2.bold())
            } compactTrailing: {
                Text("B\(context.state.beat)").font(.caption2.monospacedDigit())
            } minimal: {
                Text("Φ").font(.caption2.bold())
            }
        }
    }
}

// MARK: - Entry point ONLY for the Widget Extension
//
// Add `KAI_WIDGETS` to the Widget extension target’s
// “Build Settings → Swift Compiler – Custom Flags → Active Compilation Conditions”.
// Do NOT add it to the app target.
#if canImport(WidgetKit) && KAI_WIDGETS
@main
struct KaiKlokWidgetBundle: WidgetBundle {
    var body: some Widget {
        if #available(iOS 16.1, *) {
            KaiKlokLiveActivity()
        }
    }
}
#endif
