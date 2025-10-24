//
//  KairosDisplay.swift
//  KaiKlok
//
//  Created by BJ Klock on the Eternal Kairos
//

import SwiftUI

struct KairosDisplay: View {
    let pulse: Int
    let beat: Int
    let step: Int

    var body: some View {
        VStack(spacing: 12) {
            DisplayItem(label: "Pulse", value: pulse)
            DisplayItem(label: "Beat", value: beat)
            DisplayItem(label: "Step", value: step)
        }
        .font(.title2)
        .foregroundColor(.white)
    }
}

// MARK: - DisplayItem Subcomponent
private struct DisplayItem: View {
    let label: String
    let value: Int

    var body: some View {
        HStack(spacing: 6) {
            Text("\(label):")
                .fontWeight(.medium)
            Text("\(value)")
                .fontWeight(.semibold)
        }
    }
}
