//
//  VerifierBridge.swift
//  KaiKlok
//
//  Bridges “upload → verify” UX in SwiftUI to match TSX verifier semantics.
//  - Accepts SVG files (preferred) with embedded EternalKlock JSON in <metadata><![CDATA[...]]>
//  - Recomputes canonical SHA-256 over the EXACT file bytes (no normalization).
//  - Extracts EternalKlock payload, validates field ranges & invariants.
//  - Reconstructs a deterministic share URL (same structure as TSX).
//

import SwiftUI
import UniformTypeIdentifiers
import CryptoKit
import Foundation
import MobileCoreServices
import CoreGraphics
import os.log

// MARK: - Types

struct VerifierOutcome: Hashable {
    enum Status: String { case ok, warn, error }
    var status: Status
    var messages: [String]    // human-readable validations
    var canonicalHash: String // sha256 hex of original bytes
    var fileName: String
    var sizeBytes: Int
    var klock: EternalKlock?  // parsed EternalKlock JSON (if any)
    var reconstructedURL: URL?
}

@MainActor
final class VerifierBridge: ObservableObject {
    @Published var lastOutcome: VerifierOutcome?
    @Published var isParsing: Bool = false
    private let log = Logger(subsystem: "KaiKlok", category: "VerifierBridge")

    // Accept SVG only for now (best parity with TSX metadata flow).
    private let allowedTypes: [UTType] = [.svg]

    // MARK: Public API

    func presentPicker() -> some View {
        DocumentPicker(types: allowedTypes) { [weak self] urls in
            guard let self else { return }
            guard let url = urls.first else { return }
            Task { await self.ingest(url: url) }
        }
    }

    func ingest(url: URL) async {
        isParsing = true
        defer { isParsing = false }
        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let outcome = try verifySVGData(data, fileName: url.lastPathComponent)
            self.lastOutcome = outcome
        } catch {
            self.lastOutcome = .init(
                status: .error,
                messages: ["Failed to read/verify: \(error.localizedDescription)"],
                canonicalHash: "-", fileName: url.lastPathComponent, sizeBytes: 0,
                klock: nil, reconstructedURL: nil
            )
        }
    }

    // MARK: Core Verification (SVG)

    private func verifySVGData(_ data: Data, fileName: String) throws -> VerifierOutcome {
        let hex = sha256HexData(data)
        var msgs: [String] = []
        var status: VerifierOutcome.Status = .ok

        guard let svg = String(data: data, encoding: .utf8) else {
            throw VerifierError.invalidEncoding
        }

        // 1) Extract <metadata><![CDATA[ ...JSON... ]]></metadata>
        guard let jsonText = extractMetadataJSON(fromSVG: svg) else {
            status = .warn
            msgs.append("No <metadata> with EternalKlock JSON was found. (SVG may be legacy/exported without payload.)")
            // Even without JSON we still return the canonical hash
            return VerifierOutcome(
                status: status, messages: msgs, canonicalHash: hex,
                fileName: fileName, sizeBytes: data.count, klock: nil,
                reconstructedURL: nil
            )
        }

        // 2) Decode EternalKlock JSON
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        guard let jsonData = jsonText.data(using: .utf8) else { throw VerifierError.invalidMetadataJSON }
        let klock = try decoder.decode(EternalKlock.self, from: jsonData)

        // 3) Validate invariant ranges (no Chronos checks; purely internal consistency)
        validate(klock: klock, into: &msgs, status: &status)

        // 4) Reconstruct a deterministic share URL (like TSX)
        //    Note: We don’t have beat/step in top-level, but we do have both inside Chakra* fields.
        //    We’ll use chakraBeat & chakraStep to reconstruct a payload identical to the TSX share builder.
        let stepIndex = klock.chakraStep.stepIndex
        let beatIndex = klock.chakraBeat.beatIndex
        let chakraDay = klock.harmonicDay // UX label (e.g., Solhara, Aquaris...)
        let url = makeSigilUrl(
            canonicalHash: hex,
            payload: SigilSharePayload(
                pulse: klock.kaiPulseEternal,
                beat: beatIndex,
                stepIndex: stepIndex,
                chakraDay: chakraDay,
                stepsPerBeat: klock.chakraStep.stepsPerBeat,
                canonicalHash: hex,
                expiresAtPulse: klock.kaiPulseEternal + 11
            )
        )

        msgs.insert("Canonical OK • SHA-256 = \(hex)", at: 0)

        return VerifierOutcome(
            status: status,
            messages: msgs,
            canonicalHash: hex,
            fileName: fileName,
            sizeBytes: data.count,
            klock: klock,
            reconstructedURL: url
        )
    }

    // MARK: Helpers

    private func extractMetadataJSON(fromSVG svg: String) -> String? {
        // Finds content between <metadata><![CDATA[ ... ]]></metadata>
        guard let metaOpenRange = svg.range(of: "<metadata><![CDATA[") else { return nil }
        guard let metaCloseRange = svg.range(of: "]]></metadata>", range: metaOpenRange.upperBound..<svg.endIndex) else { return nil }
        let jsonSlice = svg[metaOpenRange.upperBound..<metaCloseRange.lowerBound]
        let s = String(jsonSlice)
        // Defensive trim
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func validate(klock: EternalKlock, into msgs: inout [String], status: inout VerifierOutcome.Status) {
        // Steps/beats consistency
        if klock.chakraStep.stepsPerBeat != 44 {
            status = .warn
            msgs.append("stepsPerBeat expected 44, got \(klock.chakraStep.stepsPerBeat).")
        }
        if klock.chakraBeat.totalBeats != 36 {
            status = .warn
            msgs.append("totalBeats expected 36, got \(klock.chakraBeat.totalBeats).")
        }
        if !(0...43).contains(klock.chakraStep.stepIndex) {
            status = .warn
            msgs.append("stepIndex out of range [0,43]: \(klock.chakraStep.stepIndex).")
        }
        if klock.chakraBeat.pulsesIntoBeat < 0 || klock.chakraBeat.pulsesIntoBeat > klock.chakraBeat.beatPulseCount {
            status = .warn
            msgs.append("pulsesIntoBeat out of range 0..beatPulseCount.")
        }

        // Percents
        if !(0.0...100.0).contains(klock.eternalChakraBeat.percentToNext) {
            status = .warn
            msgs.append("percentToNext outside 0..100.")
        }
        if !(0.0...100.0).contains(klock.harmonicWeekProgress.percent) {
            status = .warn
            msgs.append("week percent outside 0..100.")
        }
        if !(0.0...100.0).contains(klock.eternalMonthProgress.percent) {
            status = .warn
            msgs.append("month percent outside 0..100.")
        }
        if !(0.0...100.0).contains(klock.harmonicYearProgress.percent) {
            status = .warn
            msgs.append("year percent outside 0..100.")
        }

        // Seal echo (eternalSeal mirrors kairos_seal)
        if klock.eternalSeal != klock.kairos_seal && klock.kairos_seal != "" {
            status = .warn
            msgs.append("eternalSeal ≠ kairos_seal (expected identical).")
        }

        if msgs.isEmpty {
            msgs.append("EternalKlock payload OK.")
        }
    }

    private func sha256HexData(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    enum VerifierError: Error {
        case invalidEncoding
        case invalidMetadataJSON
    }
}

// MARK: - Document Picker

fileprivate struct DocumentPicker: UIViewControllerRepresentable {
    let types: [UTType]
    var onPick: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let c = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        c.delegate = context.coordinator
        c.allowsMultipleSelection = false
        return c
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coord { Coord(parent: self) }

    final class Coord: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker
        init(parent: DocumentPicker) { self.parent = parent }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.onPick(urls)
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { parent.onPick([]) }
    }
}

// MARK: - Verifier Modal (full-screen)
// NOTE: Renamed to avoid redeclaration. Present `VerifierModalBridge()` from your callsite.

struct VerifierModalBridge: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var bridge = VerifierBridge()

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // Upload / Pick
                GroupBox {
                    VStack(spacing: 12) {
                        Text("Upload a Sigil SVG to Verify")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("We recompute the canonical SHA-256 over the exact file bytes and parse the embedded EternalKlock snapshot (no Chronos).")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        Button {
                            // Present native picker (dummy focus-resign to close keyboards if any)
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        } label: {
                            Text(" ")
                        }
                        .hidden()

                        bridge.presentPicker()
                            .frame(height: 0)
                    }
                }

                // Results
                if bridge.isParsing {
                    ProgressView("Verifying…").padding(.top, 8)
                } else if let o = bridge.lastOutcome {
                    VerificationResultCard(outcome: o)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .id(o.canonicalHash)
                } else {
                    Spacer(minLength: 0)
                }

                Spacer()
            }
            .padding(16)
            .background(
                LinearGradient(
                    colors: [
                        Color.black,
                        Color(red: 3/255.0, green: 16/255.0, blue: 25/255.0), // 0x03 0x10 0x19
                        Color.black
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )

            .navigationTitle("Verifier")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

private struct VerificationResultCard: View {
    let outcome: VerifierOutcome

    var statusTint: Color {
        switch outcome.status {
        case .ok: return .green
        case .warn: return .yellow
        case .error: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle().fill(statusTint).frame(width: 10, height: 10)
                Text(outcome.status.rawValue.uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(statusTint)
                Spacer()
                Text("\(outcome.fileName) • \(ByteCountFormatter.string(fromByteCount: Int64(outcome.sizeBytes), countStyle: .file))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Canonical hash
            HStack(spacing: 8) {
                Text("Canonical SHA-256:")
                    .font(.callout.weight(.semibold))
                Text(outcome.canonicalHash)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
            }

            // Messages
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(outcome.messages.enumerated()), id: \.offset) { _, m in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "checkmark.seal").foregroundStyle(.cyan)
                        Text(m).font(.footnote)
                    }
                }
            }

            // Extracts from Klock
            if let k = outcome.klock {
                Divider().overlay(Color.white.opacity(0.15))
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    Row("pulse", String(k.kaiPulseEternal))
                    Row("beat:step", "\(k.chakraBeat.beatIndex):\(String(format: "%02d", k.chakraStep.stepIndex))")
                    Row("stepsPerBeat", String(k.chakraStep.stepsPerBeat))
                    Row("totalBeats", String(k.chakraBeat.totalBeats))
                    Row("harmonicDay", k.harmonicDay)
                    Row("eternalSeal", k.eternalSeal)
                    Row("month", "\(k.eternalMonthIndex) — \(k.eternalMonth)")
                    Row("year", k.eternalYearName)
                }
            }

            // Share URL
            if let url = outcome.reconstructedURL {
                Divider().overlay(Color.white.opacity(0.15))
                VStack(alignment: .leading, spacing: 6) {
                    Text("Reconstructed Share URL")
                        .font(.callout.weight(.semibold))
                    Text(url.absoluteString)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                    HStack {
                        Button {
                            UIPasteboard.general.string = url.absoluteString
                        } label: {
                            Label("Copy URL", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.cyan)

                        ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LinearGradient(colors: [Color.white.opacity(0.06), Color.white.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.cyan.opacity(0.28), lineWidth: 1))
        )
    }

    // Force String to avoid any mismatched overloads from other modules.
    @ViewBuilder
    private func Row(_ k: String, _ v: String) -> some View {
        GridRow {
            Text(k).font(.caption.monospaced()).foregroundStyle(.secondary)
            Text(v).font(.caption.monospaced())
        }
    }
}
