//
//  ValuationModal.swift
//  KaiKlok
//
//  Created by BJ Klock on 10/16/25.
//

import SwiftUI

public struct ValuationModal: View {
    public var open: Bool
    public var onClose: () -> Void
    public var meta: WVSigilMetadata
    public var nowPulse: Int
    public var initialGlyph: InitialGlyph?
    public var onAttach: ((ValueSeal) -> Void)?

    @State private var computed: ValueSeal?

    public init(
        open: Bool,
        onClose: @escaping () -> Void,
        meta: WVSigilMetadata,
        nowPulse: Int,
        initialGlyph: InitialGlyph? = nil,
        onAttach: ((ValueSeal) -> Void)? = nil
    ) {
        self.open = open
        self.onClose = onClose
        self.meta = meta
        self.nowPulse = nowPulse
        self.initialGlyph = initialGlyph
        self.onAttach = onAttach
    }

    public var body: some View {
        Group {
            if open {
                NavigationStack {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Φ Valuation")
                            .font(.title3).bold() // correct: call bold() as a modifier

                        if let ig = initialGlyph {
                            Text("Canonical: \(ig.hash)")
                                .font(.footnote.monospaced())
                        }

                        Group {
                            if let c = computed {
                                HStack {
                                    Text("Estimated Φ").foregroundStyle(.secondary)
                                    Spacer()
                                    Text(String(format: "%.3f", c.valuePhi))
                                        .font(.title2).bold()
                                }
                                if let h = c.headHash {
                                    Text("Head Root: \(h)")
                                        .font(.footnote.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Text("Tap ‘Compute’ to estimate current Φ.")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding()
                        .background(.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        HStack {
                            Button("Compute") {
                                let head = meta.transfersWindowRoot ?? meta.transfersWindowRootV14
                                // FIX: buildValueSeal already returns ValueSeal
                                computed = buildValueSeal(meta, nowPulse: nowPulse, headHash: head)
                            }
                            .buttonStyle(.bordered)

                            if let c = computed, let attach = onAttach {
                                Button("Attach to Sigil") {
                                    attach(c)
                                    onClose()
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }

                        Spacer()
                    }
                    .padding()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Close") { onClose() }
                        }
                    }
                }
            }
        }
    }
}
