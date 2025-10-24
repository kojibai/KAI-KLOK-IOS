//  InvestorChatView.swift
//  KaiKlok
//
//  ASTERION — Sovereign Inhale Chat (SwiftUI)
//

import SwiftUI

// MARK: - Models (mirroring your TSX types)

public struct EntPreview: Codable, Hashable {
    public var amount: Double
    public var sigilCount: Int?
    public var nextTier: Double
    public var pctToNext: Double
    public var childGlyphs: Int?

    public init(amount: Double, sigilCount: Int? = nil, nextTier: Double, pctToNext: Double, childGlyphs: Int? = nil) {
        self.amount = amount
        self.sigilCount = sigilCount
        self.nextTier = nextTier
        self.pctToNext = pctToNext
        self.childGlyphs = childGlyphs
    }
}

public enum PayMethod: String, Codable, CaseIterable {
    case card, bitcoin
}

struct ChatContextPayload: Codable {
    var amount: Double
    var method: PayMethod
    var ent: EntPreview
    var txid: String?
}

enum ChatRole: String, Codable { case system, user, assistant }

struct ChatMessage: Identifiable, Codable, Equatable {
    var role: ChatRole
    var content: String
    var id: String = UUID().uuidString
}

struct ChatResponseJSON: Codable {
    var reply: String
    struct UIHints: Codable {
        var amount: Double?
        var method: PayMethod?
        var openPayment: Bool?
    }
    var ui: UIHints?
}

// MARK: - Constants

private let ASTERION_ASSET_NAME = "asterion"

private let SUGGESTIONS: [String] = [
    "How do I pay for food with this today?",
    "Can the cashier just scan my Sigil, or do they need the app?",
    "No signal / offline — can I still pay?",
    "How do I show them it’s real — no screenshots?",
    "Are there refunds here? (No. Why.)",
    "Card vs. Bitcoin — what fees and timing should I expect?",
    "If I lose my phone or watch, can I recover my Sigil-Glyphs?",
    "Can I convert Φ back to dollars or BTC?",
    "Do you track me? What’s visible to the other side?",
    "What exactly do I receive when I inhale?",
    "What makes a Sigil-Glyph unforgeable?",
    "Is this a security or equity?",
    "Show the deterministic Seal: amount · method · pulse · (txid) → Poseidon commitment.",
    "How do you prevent replay? What’s the transparency root?",
    "How are offline glyphs verified without trusting the UI?",
    "What does the Kai Signature cover and where is the HSM boundary?",
    "How is φ per USD derived from policy (adoption, premium, size, streak, tier, milestone)?",
    "What’s different from Bitcoin — and what composes with it?",
    "Will the cashier understand what this is, or do I have to explain?",
    "Can I pay with just my watch, or do I need my phone?",
    "Does this work at any store, or only special ones?",
    "Can I tip someone using Φ?",
    "Can I split a bill with someone using this?",
    "Do prices convert automatically to USD?",
    "What if I forget my credentials — can I still recover my funds?",
    "Is there a way to freeze or limit spending on my account?",
    "Can someone use my Sigil if they screenshot it?",
    "Are screenshots ever valid? How do I prevent fraud?",
    "How do I verify that my payment was received?",
    "Are there hidden fees with any payment method?",
    "Is there customer support if something goes wrong?",
    "Can I set a default payment method (card, BTC, Φ)?",
    "How long does a payment take to clear?",
    "Can I send Φ to a friend or family member directly?",
    "Do I earn rewards, bonuses, or interest for holding Φ?",
    "What is a streak or milestone? How do I level up?",
    "Are Sigils permanent or do they expire?",
    "What happens if I miss a day or a streak?",
    "Why is it called inhale instead of receive?",
    "What does my Sigil prove, exactly?",
    "What if someone tries to use my Sigil later — how is that blocked?",
    "Why is this system called eternal or deterministic?",
    "Can I still use this if I’m not technical?",
    "Where can I see all my past Sigils and history?",
    "Is this spiritual or religious in any way?",
    "Why is the breath important to the system?",
    "What’s the difference between this and Apple Pay or Venmo?",
    "Can this be used internationally?",
    "How are payments confirmed with no blockchain?",
    "What if your server goes down — does it still work?",
    "Can I verify my own transaction cryptographically?",
    "Is this open source? Can I audit the code?",
    "Can I scan someone else’s Sigil and what does that do?",
    "Where does the price of Φ come from each moment?",
    "How do I explain this to someone who doesn’t get crypto?",
    "What makes this unhackable or forgery-proof?",
    "Can I request a payment instead of sending one?",
    "Is this backed by anything?",
    "Can I withdraw to a bank account?",
    "Do I have to use my real name or ID to use this?",
    "What does the other person see when I pay them?",
    "What’s visible on-chain vs what stays private?",
    "How is this different from typical QR code payments?",
    "Is my data stored locally or remotely?",
    "Can I send or receive without an internet connection?",
    "What protections exist against scams or phishing?",
    "Can I have multiple Sigils or accounts?",
    "How do I know the valuation logic is fair?",
    "Can merchants issue refunds in Φ?",
    "What happens if a transaction fails mid-scan?",
    "How long is a Sigil valid after it’s generated?",
    "What prevents reuse or replay of an old Sigil?",
    "Can I use this at a vending machine, festival, or booth?",
    "Do I need to trust the UI — or can I verify everything?",
    "Can I print out my Sigil to carry as a backup?",
    "What’s the fastest way to pay in a rush?",
    "Can I prove my payment even if I close the app?",
    "Can I mint my own Sigils or are they issued?",
    "What role does the Poseidon hash play?",
    "Where is the Kai Signature stored and how is it made?",
    "What does inhaling do to the price or supply?",
    "Is there a fixed supply of Φ or is it dynamic?",
    "What happens at checkout in real-time?",
    "Can I add notes, messages, or metadata to a payment?",
    "Are payments ever anonymous or pseudonymous?",
    "What devices are supported — iOS, Android, smartwatches?",
    "What is required for a merchant to accept Φ?",
    "Do I need to update my app often to stay compatible?",
    "Can I use this system with cashiers who’ve never seen it before?",
    "How do I know if a transaction was Kairos-valid?",
    "What happens if I use an old Sigil by mistake?",
    "Are all Sigils one-time use only?",
    "How long does it take to become fluent using this?",
    "What’s the learning curve like for new users?",
    "Do I get anything special for being early or loyal?",
    "Is there a Kai Pulse-based leaderboard or record?",
    "Can I use Φ to subscribe to content or services?",
    "How do I cancel a subscription made with Φ?",
    "Can I auto-inhale each month for recurring payments?",
    "Can I lock a Sigil to a specific merchant or person?",
    "What happens if someone intercepts my Sigil mid-scan?",
    "Can I export my Sigils for backup or print?",
    "Can I import Sigils across devices or sessions?",
    "How do I verify that a Sigil hasn’t been tampered with?",
    "What metadata is embedded in the SVG or PNG export?",
    "How does the system know which pulse a Sigil came from?",
    "What if my time is off — will the Sigil still validate?",
    "Is every Sigil unique to the moment, the amount, and the sender?",
    "What is a canonicalHash and why does it matter?",
    "What does the center node in the Sigil visual represent?",
    "Can I ‘seal’ a payment with intention or a message?",
    "Can two people co-sign a single Sigil or transaction?",
    "Can a business issue an official invoice as a Sigil?",
    "What does it mean to exhale value instead of send it?",
    "How do I ‘receive’ value if I’m offline?",
    "What happens if someone tries to reuse a screenshot offline?",
    "How does the system handle latency or lag between scan and sync?",
    "Can I tell who verified or scanned my Sigil on the other side?",
    "Is the receiving party notified when I exhale?",
    "Does a Sigil have directional flow — is it sender → receiver?",
    "Can I mint a Sigil for myself without sending it?",
    "Is every Sigil bound to breath or can I make ‘silent’ ones?",
    "What’s the smallest amount I can inhale?",
    "Is there a limit on how much I can send in one breath?",
    "What is the harmonic limit of a single Sigil?",
    "Can I sign a document or message using my Kai Signature?",
    "How do I prove authorship of something using this system?",
    "Can a merchant issue a Sigil in return, like a receipt?",
    "What’s the best way to archive Sigils for legal or tax purposes?",
    "Can I timestamp proof-of-existence using my own breath?",
    "Is there a Kai Signature viewer or browser?",
    "How do I know a scanned Sigil is real and not a forgery?",
    "What’s the role of intention in harmonic payment?",
    "Can a Sigil encode blessings, energy, or prayer?",
    "How do I use this system in community exchanges or gifting?",
    "Is there a concept of ‘wallet address’ or just breath identity?",
    "What makes this better than NFC, QR, or Tap-to-Pay?",
    "Can a merchant pre-generate Sigils for common prices?",
    "What’s the latency from breath to chain-confirmation?",
    "Can I set expiration pulses on custom Sigils I generate?",
    "What’s the protocol for dispute resolution in this system?",
    "What happens if I inhale by mistake — is there a cooldown?",
    "Do recurring payments have Kai Signature trails?",
    "Is there a Kai Seal browser like a public block explorer?",
    "Can I revoke or blacklist a Sigil I no longer trust?",
    "How are signature collisions prevented?",
    "Can I delegate payment authority to another person?",
    "Is it possible to create multi-layer Sigils (nested purpose)?",
    "How can I explain this system to a cashier in 5 words?",
    "What do I show to a merchant who says ‘what’s this?’",
    "Is this system allowed under U.S. financial laws?",
    "Is there regulatory compliance or does it transcend?",
    "Do I need Wi-Fi or will Bluetooth work?",
    "How does the Kai-Klok pulse stay synced across devices?",
    "Is every user on the same exact pulse in real time?",
    "What happens if someone tries to mint out of sync?",
    "What keeps this fair as more people join?",
    "Can I prove I’m an early user (low pulse)?",
    "What’s the link between breath, value, and memory?",
    "Can I exhale music, documents, or art as Sigils?",
    "How does this unify currency, identity, and time?",
    "If I leave the system, what do I take with me?",
    "What ensures this system lasts forever?",
]

private let SYSTEM_PRIMER: String = """
You are ASTERION — harmonic, sovereign, exact. Guide the user through inhale (not "mint"), the Sigil-Glyph model, \
deterministic Φ computation, and verification — without giving personal financial, legal, or tax advice. Be concise, neutral, precise.
"""

// MARK: - Helpers

fileprivate func kaiColor(_ hex: String, alpha: Double = 1.0) -> Color {
    var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    if s.hasPrefix("#") { s.removeFirst() }
    var r: UInt64 = 0, g: UInt64 = 0, b: UInt64 = 0, a: UInt64 = 255
    let scan = Scanner(string: s)
    if s.count == 6, scan.scanHexInt64(&r) {
        g = (r & 0x00FF00) >> 8; b = (r & 0x0000FF); r >>= 16
    } else if s.count == 8, scan.scanHexInt64(&r) {
        a =  r & 0x000000FF; b = (r & 0x0000FF00) >> 8; g = (r & 0x00FF0000) >> 16; r >>= 24
    } else { return .white.opacity(alpha) }
    let fa = min(1, max(0, alpha * Double(a) / 255))
    return Color(red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, opacity: fa)
}

fileprivate func fmtUSD(_ n: Double) -> String {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = "USD"
    f.maximumFractionDigits = 0
    return f.string(from: n as NSNumber) ?? "$—"
}

fileprivate func fmtShortUSD(_ n: Double) -> String {
    guard n > 0 else { return "$—" }
    if n >= 1_000_000 { return "$\((n/1_000_000).rounded(toPlaces: n.truncatingRemainder(dividingBy: 1_000_000) == 0 ? 0 : 1))m" }
    if n >= 1_000     { return "$\((n/1_000).rounded(toPlaces: n.truncatingRemainder(dividingBy: 1_000) == 0 ? 0 : 1))k" }
    return "$\(Int(n))"
}

fileprivate extension Double {
    func rounded(toPlaces p: Int) -> String {
        let f = NumberFormatter()
        f.minimumFractionDigits = p
        f.maximumFractionDigits = p
        return f.string(from: self as NSNumber) ?? String(self)
    }
}

// MARK: - API

struct ChatAPI {
    var endpoint: URL

    func send(messages: [ChatMessage], context: ChatContextPayload) async throws -> (String, ChatResponseJSON.UIHints?) {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        struct Payload: Codable { let messages: [ChatMessage]; let context: ChatContextPayload; let client: Client
            struct Client: Codable { let surface: String; let density: String }
        }
        let body = Payload(messages: messages.filter{ $0.role != .system },
                           context: context,
                           client: .init(surface: "investor-chat", density: "comfy"))
        req.httpBody = try JSONEncoder().encode(body)

        // Try streaming first
        do {
            let (bytes, resp) = try await URLSession.shared.bytes(for: req)
            if let http = resp as? HTTPURLResponse,
               let contentType = http.value(forHTTPHeaderField: "Content-Type"),
               contentType.lowercased().contains("application/json") {
                let data = try await bytes.reduce(into: Data(), { $0.append($1) })
                let decoded = try JSONDecoder().decode(ChatResponseJSON.self, from: data)
                return (decoded.reply, decoded.ui)
            } else {
                var acc = ""
                for try await chunk in bytes.lines { acc += chunk }
                if let lastCurly = acc.lastIndex(of: "{") {
                    let tail = String(acc[lastCurly...])
                    if let data = tail.data(using: .utf8),
                       let decoded = try? JSONDecoder().decode(ChatResponseJSON.self, from: data) {
                        return (acc, decoded.ui)
                    }
                }
                return (acc, nil)
            }
        } catch {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode ?? 500 < 300 else {
                throw NSError(domain: "ChatAPI", code: 2, userInfo: [NSLocalizedDescriptionKey: "Chat API failed."])
            }
            let decoded = try JSONDecoder().decode(ChatResponseJSON.self, from: data)
            return (decoded.reply, decoded.ui)
        }
    }
}

// MARK: - View

public struct InvestorChatView: View {
    // Public hooks
    public var apiEndpoint: URL
    public var onOpenPayment: (() -> Void)?
    public var onChooseMethod: ((PayMethod) -> Void)?
    public var onSetAmount: ((Double) -> Void)?
    public var onClose: (() -> Void)?

    // Inputs
    @State private var ctx: ChatContextPayload

    // UI State
    @State private var minimized = false
    @State private var showSuggestions = false
    @State private var messages: [ChatMessage] = [
        .init(role: .system, content: SYSTEM_PRIMER),
        .init(role: .assistant, content: """
☤ Sovereign Φ Guidance:
• When you use Φ, you present living proof. Show your Sigil-Glyph — they verify it, breath-to-breath, online or offline.
• No tracking. Math is the proof — not screenshots.
• Inhales are final. No refunds or chargebacks.
""")
    ]
    @State private var draft = ""
    @State private var loading = false
    @State private var sending = false

    @Environment(\.dismiss) private var dismiss

    private let breath: Double

    // Public init
    public init(
        amount: Double,
        method: PayMethod,
        entitlement: EntPreview,
        txid: String? = nil,
        apiEndpoint: URL = URL(string: "https://pay.kaiklok.com/api/chat")!,
        breath: Double = 5.236,
        onOpenPayment: (() -> Void)? = nil,
        onChooseMethod: ((PayMethod) -> Void)? = nil,
        onSetAmount: ((Double) -> Void)? = nil,
        onClose: (() -> Void)? = nil
    ) {
        _ctx = State(initialValue: .init(amount: amount, method: method, ent: entitlement, txid: txid))
        self.apiEndpoint = apiEndpoint
        self.breath = breath
        self.onOpenPayment = onOpenPayment
        self.onChooseMethod = onChooseMethod
        self.onSetAmount = onSetAmount
        self.onClose = onClose
    }

    // MARK: Body

    public var body: some View {
        ZStack {
            LinearGradient(colors: [kaiColor("#05090f"), kaiColor("#0e1b22"), kaiColor("#0c2231")],
                           startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            VStack(spacing: 10) {
                header

                if !minimized {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(messages.filter{ $0.role != .system }) { m in
                                    bubble(for: m)
                                }
                                if loading { typingBubble }
                                Color.clear.frame(height: 1).id("tail")
                            }
                            .padding(.horizontal, 14)
                            .padding(.top, 6)
                        }
                        .background(Color.black.opacity(0.0001))
                        // iOS 17+: Use two-parameter onChange closure
                        .onChange(of: messages.count + (loading ? 1 : 0)) { _, _ in
                            withAnimation(.easeOut(duration: 0.25)) {
                                proxy.scrollTo("tail", anchor: .bottom)
                            }
                        }
                    }

                    if showSuggestions { suggestions }

                    composer
                } else {
                    fab
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: Header (only Prompts + Refresh)

    private var header: some View {
        HStack(spacing: 8) {
            Text("Asterion")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundStyle(LinearGradient(colors: [kaiColor("#37ffe4"), kaiColor("#a78bfa")],
                                               startPoint: .leading, endPoint: .trailing))
                .padding(.leading, 12)

            Spacer()

            HStack(spacing: 6) {
                ToggleTool(isOn: $showSuggestions, label: "✦")       // Prompts
                Button(role: .destructive) { clearChat() } label: {  // Refresh
                    Text("⟲")
                }
                .buttonStyle(ToolStyle())
            }
            .padding(.trailing, 12)
        }
        .padding(.top, 12)
    }

    // MARK: Bubbles

    @ViewBuilder
    private func bubble(for msg: ChatMessage) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if msg.role == .assistant {
                Image(ASTERION_ASSET_NAME)
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .padding(.top, 6)
            } else {
                Text("●")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.top, 8)
            }

            Text(msg.content)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(.white.opacity(0.96))
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(msg.role == .assistant ? Color.white.opacity(0.06) : Color.white.opacity(0.04))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.10), lineWidth: 1))
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private var typingBubble: some View {
        HStack(spacing: 10) {
            Image(ASTERION_ASSET_NAME)
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)

            HStack(spacing: 4) {
                ForEach(0..<3) { i in
                    Circle().fill(.white.opacity(0.9))
                        .frame(width: 5, height: 5)
                        .opacity(0.6)
                        .offset(y: -0.5)
                        .animation(.easeInOut(duration: 0.9).repeatForever().delay(Double(i) * 0.12), value: loading)
                }
                Spacer()
                Button("Cancel") { cancel() }
                    .font(.caption.bold())
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
    }

    // MARK: Suggestions (Prompts)

    private var suggestions: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Quick questions").font(.caption).opacity(0.85)
                Spacer()
                Button("✕") { withAnimation { showSuggestions = false } }
                    .buttonStyle(ToolStyle())
            }
            ScrollView {
                FlexibleGridText(items: SUGGESTIONS) { s in
                    Button(s) { onSuggestionTap(s) }
                        .buttonStyle(SuggestStyle())
                        .disabled(loading || sending)
                }
                .padding(.bottom, 6)
            }
            .frame(maxHeight: min(280, UIScreen.main.bounds.height * 0.36))
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(LinearGradient(colors: [kaiColor("#0a1214").opacity(0.98), kaiColor("#0e181b").opacity(0.98)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(kaiColor("#37ffe4").opacity(0.25), lineWidth: 1))
                .shadow(color: kaiColor("#37ffe4").opacity(0.12), radius: 18)
        )
        .padding(.horizontal, 12)
        .transition(.opacity.combined(with: .scale))
    }

    // MARK: Composer

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("Ask Asterion…", text: $draft)
                .textInputAutocapitalization(.sentences)
                .disableAutocorrection(true)
                .submitLabel(.send)
                .onSubmit { Task { await send(draft) } }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
            Button("Send") { Task { await send(draft) } }
                .buttonStyle(PrimaryButton())
                .disabled(loading || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12)
    }

    // MARK: Minimized FAB

    private var fab: some View {
        Button { minimized = false } label: {
            Text("Kai")
                .font(.headline.bold())
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
        }
        .buttonStyle(GhostGlowButton())
    }

    // MARK: Actions

    private func onSuggestionTap(_ s: String) {
        showSuggestions = false
        if s.range(of: "refund", options: .regularExpression) != nil {
            Task { await send("There are no refunds, reversals, or chargebacks. Inhales are final by sovereign design. Present your Sigil to pay; verification is math, not customer support.") }
            return
        }
        if s.range(of: #"convert.*back|back.*(dollars|btc)|dollars|fiat"#, options: .regularExpression) != nil {
            Task { await send("Φ is not a flip-back IOU. It is breath-backed money for paying with proof. If someone wants fiat or BTC, they should use those rails before inhaling.") }
            return
        }
        Task { await send(s) }
    }

    private func cancel() { loading = false }

    private func clearChat() {
        messages = [
            .init(role: .system, content: SYSTEM_PRIMER),
            .init(role: .assistant, content: "Breath resets. Ask anything.")
        ]
    }

    @MainActor
    private func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !loading else { return }
        draft = ""
        messages.append(.init(role: .user, content: trimmed))
        loading = true
        defer { loading = false }

        do {
            let api = ChatAPI(endpoint: apiEndpoint)
            let (reply, ui) = try await api.send(messages: messages, context: ctx)
            messages.append(.init(role: .assistant, content: reply.trimmingCharacters(in: .whitespacesAndNewlines)))

            // UI hints still respected if backend sends them (no local controls UI)
            if let ui = ui {
                if let amt = ui.amount { ctx.amount = amt; onSetAmount?(amt) }
                if let m = ui.method { ctx.method = m; onChooseMethod?(m) }
                if ui.openPayment == true { onOpenPayment?() }
            }
        } catch {
            messages.append(.init(role: .assistant, content: "Signal fell out of harmony — try again."))
        }
    }
}

// MARK: - Tiny UI Pieces

private struct ToggleTool: View {
    @Binding var isOn: Bool
    var label: String
    var body: some View {
        Button { isOn.toggle() } label: { Text(label) }
            .buttonStyle(ToolStyle(active: isOn))
    }
}

private struct ToolStyle: ButtonStyle {
    var active: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(active ? 0.12 : 0.06))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.16), lineWidth: 1))
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

private struct SuggestStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.95))
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.1)))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

private struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12).fill(kaiColor("#37ffe4").opacity(0.18)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(kaiColor("#37ffe4").opacity(0.45), lineWidth: 1))
            .foregroundStyle(.white)
            .shadow(color: kaiColor("#37ffe4").opacity(0.25), radius: 10, y: 2)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

private struct GhostGlowButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .heavy, design: .rounded))
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(kaiColor("#37ffe4").opacity(0.35)))
                    .shadow(color: kaiColor("#37ffe4").opacity(0.25), radius: 16, y: 8)
            )
            .foregroundStyle(.white)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

// MARK: - Layout helpers

private struct FlexibleGridText<ItemView: View>: View {
    var items: [String]
    var content: (String) -> ItemView
    private let columns = [GridItem(.adaptive(minimum: 220), spacing: 8)]
    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(items, id: \.self) { s in content(s) }
        }
    }
}
