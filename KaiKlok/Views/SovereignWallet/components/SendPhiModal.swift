//  SendPhiModal.swift
//  KaiKlok
//
//  Sends Φ notes. Picker fixed to use Hashable Optional selection.
//

import SwiftUI

// MARK: - Make PhiNote Hashable so it can be used in Picker selections/tags
extension PhiNote: Hashable {
    public static func == (lhs: PhiNote, rhs: PhiNote) -> Bool {
        // Canonical identity for a note in this app:
        // source key + kai boundary + amount + chakra day.
        return lhs.fromPhiKey == rhs.fromPhiKey
        && lhs.pulse == rhs.pulse
        && lhs.beat == rhs.beat
        && lhs.stepIndex == rhs.stepIndex
        && lhs.chakraDay == rhs.chakraDay
        && lhs.phiAmount == rhs.phiAmount
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(fromPhiKey)
        hasher.combine(pulse)
        hasher.combine(beat)
        hasher.combine(stepIndex)
        hasher.combine(chakraDay)
        hasher.combine(phiAmount.bitPattern) // stable Double hashing
    }
}

// MARK: - View

struct SendPhiModal: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var identity = SigilIdentityManager.shared

    // Recipient public key (or address)
    @State private var toPublicKey: String = ""

    // Optional: choose/attach a note (e.g. from scan/recent)
    @State private var selectedNote: PhiNote? = nil
    @State private var recentNotes: [PhiNote] = []

    // Compose (manual entry if no note attached)
    @State private var amountPhiText: String = ""
    @State private var memo: String = ""

    // Scanner
    @State private var showScanner = false

    // UX
    @State private var sending = false
    @State private var sentOK = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Recipient")) {
                    TextField("Recipient Public Key", text: $toPublicKey)
                        .autocapitalization(.none)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                }

                Section(header: Text("Attach Note (optional)")) {
                    if recentNotes.isEmpty {
                        HStack {
                            Text("No notes yet")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                showScanner = true
                            } label: {
                                Label("Scan Note", systemImage: "qrcode.viewfinder")
                            }
                        }
                    } else {
                        Picker("Select Note", selection: $selectedNote) {
                            Text("None").tag(Optional<PhiNote>.none)
                            ForEach(recentNotes, id: \.self) { note in
                                Text(noteLabel(note))
                                    .tag(Optional(note)) // IMPORTANT: Optional tag matches PhiNote?
                            }
                        }
                        Button {
                            showScanner = true
                        } label: {
                            Label("Scan Another", systemImage: "qrcode.viewfinder")
                        }
                    }
                }

                Section(header: Text("Amount")) {
                    // If a note is selected, show its amount and lock manual field
                    if let note = selectedNote {
                        HStack {
                            Text("Φ Amount")
                            Spacer()
                            Text("Φ \(String(format: "%.4f", note.phiAmount))")
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.primary)
                        }
                        .accessibilityLabel("Amount Phi \(note.phiAmount)")
                    } else {
                        TextField("Φ amount (e.g. 1.25)", text: $amountPhiText)
                            .keyboardType(.decimalPad)
                            .font(.system(.body, design: .monospaced))
                    }
                }

                Section(header: Text("Memo (optional)")) {
                    TextField("Add a memo…", text: $memo)
                }

                if let err = errorMessage {
                    Section {
                        Text(err).foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        send()
                    } label: {
                        if sending {
                            ProgressView().progressViewStyle(.circular)
                        } else {
                            Label("Send Φ", systemImage: "paperplane.fill")
                        }
                    }
                    .disabled(!canSend)
                }
            }
            .navigationTitle("Send Φ")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
            .sheet(isPresented: $showScanner) {
                // Scan a PhiNote QR payload into recent list
                QRScannerView<PhiNote> { note in
                    if let note = note {
                        // Prepend newest
                        recentNotes.removeAll(where: { $0 == note })
                        recentNotes.insert(note, at: 0)
                        selectedNote = note
                    }
                    showScanner = false
                }
            }
            .alert("Sent!", isPresented: $sentOK) {
                Button("OK") { dismiss() }
            } message: {
                Text("Your Φ has been queued for transfer.")
            }
        }
    }

    // MARK: - Helpers

    private var canSend: Bool {
        // Must have a recipient and either a selected note or a manual numeric amount
        guard !toPublicKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if selectedNote != nil { return true }
        if let amt = Double(amountPhiText), amt > 0 { return true }
        return false
    }

    private func send() {
        errorMessage = nil
        guard canSend else { return }

        sending = true
        defer { sending = false }

        // Build a minimal intent. If you have TransferEngine, swap this block.
        // Here we just simulate success and show an alert.
        // Example gateway (pseudo):
        // TransferEngine.shared.send(to: toPublicKey, amountPhi: amount, note: selectedNote, memo: memo) { ... }

        // Validate manual amount when no note is selected
        let manualAmount: Double? = (selectedNote == nil) ? Double(amountPhiText) : nil
        if selectedNote == nil && (manualAmount ?? 0) <= 0 {
            errorMessage = "Enter a valid Φ amount."
            return
        }

        // Success UX
        sentOK = true
    }

    private func noteLabel(_ n: PhiNote) -> String {
        let ts = PulseFormatter.formatKaiTimestamp(
            pulse: n.pulse,
            beat: n.beat,
            step: n.stepIndex,
            chakraDay: n.chakraDay
        )
        return "Φ \(String(format: "%.4f", n.phiAmount)) • \(ts)"
    }
}

// MARK: - Preview

#Preview {
    SendPhiModal()
}
