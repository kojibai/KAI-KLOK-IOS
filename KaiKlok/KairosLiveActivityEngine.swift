//  KairosLiveActivityEngine.swift
//  KaiKlok
//
//  Created by BJ Klock on 9/20/25.
//
//  Eternal Pulse lifecycle for the Kai-Klok Lock Screen Live Activity
//

import Foundation
import ActivityKit

/// Manages the Kai-Klok Live Activity lifecycle (start/update/end).
struct KairosLiveActivityEngine {

    // MARK: - Public API

    /// Start a new Live Activity with the current Kairos state.
    static func start(for userPhiKey: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("⚠️ Live Activities are not enabled for this device or user.")
            return
        }

        let attributes = KaiKlokAttributes(userPhiKey: userPhiKey)
        let state = buildContentState()

        do {
            _ = try Activity<KaiKlokAttributes>.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
            print("✅ Kai-Klok Live Activity started")
        } catch {
            print("❌ Failed to start Live Activity: \(error)")
        }
    }

    /// Refresh all active Kai-Klok Live Activities with the latest Kairos state.
    static func refreshLiveActivity() {
        let state = buildContentState()

        Task {
            for activity in Activity<KaiKlokAttributes>.activities {
                await activity.update(
                    ActivityContent(state: state, staleDate: nil)
                )
            }
        }
    }

    /// End all active Kai-Klok Live Activities.
    /// - Parameter immediate: If `true`, dismiss immediately. Otherwise use a graceful dismissal.
    static func endAll(immediate: Bool = false) {
        Task {
            let finalState = buildContentState() // snapshot at end time
            let content = ActivityContent(state: finalState, staleDate: nil)

            for activity in Activity<KaiKlokAttributes>.activities {
                if #available(iOS 16.2, *) {
                    // Modern API (iOS 16.2+)
                    let policy: ActivityUIDismissalPolicy = immediate ? .immediate : .default
                    await activity.end(content, dismissalPolicy: policy)
                } else {
                    // Fallback for iOS 16.1 (deprecated but kept for compatibility)
                    let policy: ActivityUIDismissalPolicy = immediate ? .immediate : .default
                    await activity.end(dismissalPolicy: policy)
                }
            }
        }
    }

    // MARK: - Internal: Build ContentState snapshot from current Kairos moment

    /// Computes the current lock-screen snapshot:
    /// Day name, Month name, Day number, and BEAT:STEP derived from the φ pulse.
    private static func buildContentState() -> KaiKlokAttributes.ContentState {
        let pulse = KairosEngine.currentPulse()
        let beat  = KairosEngine.currentBeat()
        let step  = KairosEngine.currentStep()

        let bpd = KairosConstants.beatsPerDay
        let spb = KairosConstants.stepsPerBeat

        // Calendar derivations
        let dayIndex   = (pulse / (spb * bpd)) % 6
        let monthIndex = (pulse / (spb * bpd * 6)) % 8
        let dayNumber  = ((pulse / (spb * bpd)) % 42) + 1 // 1-based Kairos day number

        let chakraDay = KairosLabelEngine.dayName(forDayIndex: dayIndex)
        let monthName = KairosLabelEngine.monthName(forMonthIndex: monthIndex)

        return KaiKlokAttributes.ContentState(
            pulse: pulse,
            beat: beat,
            step: step,
            chakraDay: chakraDay,
            monthName: monthName,
            dayNumber: dayNumber,
            phrase: "You are not late. You are now."
        )
    }
}
