//  HomePriceChartCard.swift
//  KaiKlok
//
//  App Review–ready: adaptive ticker, no overlap on small widths,
//  Dynamic Type–aware, axis labels that abbreviate, safe tap areas.
//  Parity with TSX HomePriceChartCard + KaiPriceChart
//  - Slim ticker ↔ expandable live chart (ticks every 3+√5 s)
//  - 24h % computed from same priceFn at (p - pulsesPerDay)
//  - Chart engine keeps ticking while collapsed
//  - In-app purchase via StoreKit 2 (correct for iOS digital goods)
//  - Uses KaiValuation.quotePhiForUsd → USD/Φ = 1 / phiPerUsd (exact TS math)
//  - Drop-in: add to ContentView to appear at the top
//
//  v1.0.1
//  - Fix: call to MainActor-isolated `tick()` from nonisolated Timer closure.
//         Re-entrants now hop to the MainActor via `Task { @MainActor in ... }`.
//  - Fix: Combine sinks that touch MainActor state also hop to MainActor.
//

import SwiftUI
import Combine
import Foundation
import StoreKit

// MARK: - Public View

struct HomePriceChartCard: View {
    // Public props (parity with TSX defaults)
    var ctaAmountUsd: Double = 144
    var apiBase: String = "https://pay.kaiklok.com"
    var title: String = "Value Index"
    var chartHeight: CGFloat = 120
    var onExpandChange: ((Bool) -> Void)? = nil

    @StateObject private var vm: VM = VM()
    @ScaledMetric(relativeTo: .body) private var minTapHeight: CGFloat = 44
    @ScaledMetric(relativeTo: .body) private var basePad: CGFloat = 12

    init(
        ctaAmountUsd: Double = 144,
        apiBase: String = "https://pay.kaiklok.com",
        title: String = "Value Index",
        chartHeight: CGFloat = 120,
        onExpandChange: ((Bool) -> Void)? = nil
    ) {
        self.ctaAmountUsd = ctaAmountUsd
        self.apiBase = apiBase
        self.title = title
        self.chartHeight = chartHeight
        self.onExpandChange = onExpandChange
    }

    var body: some View {
        VStack(spacing: 10) {
            // Slim ticker strip — tap to expand/collapse
            Button(action: toggleExpanded) {
                TickerRow(
                    title: title,
                    priceLong: vm.priceLabel,
                    priceShort: vm.priceShortLabel,
                    pctLong: vm.pctLabelWithArrow,
                    pctShort: vm.pctShortLabel,
                    pctPositive: vm.pct24h >= 0
                )
                .padding(.horizontal, basePad).padding(.vertical, basePad * 0.65)
                .frame(maxWidth: .infinity, minHeight: minTapHeight, alignment: .center)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.linearGradient(
                            Gradient(colors: [Color.white.opacity(0.06), Color.white.opacity(0.02)]),
                            startPoint: .top, endPoint: .bottom))
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1))
                )
                .contentShape(Rectangle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(title). \(vm.accessibilityTickerSummary)")
                .accessibilityHint("Double tap to \(vm.expanded ? "collapse" : "expand") live chart.")
            }
            .buttonStyle(PlainButtonStyle())

            // Expandable region
            VStack(spacing: 10) {
                // Chart (auto width)
                KaiPriceChartSwiftUI(points: vm.livePoints)
                    .frame(height: chartHeight)
                    .accessibilityLabel("Live Φ value in fiat over Kai pulses")

                // Controls
                HStack {
                    HStack(spacing: 6) {
                        Text("Exhale:")
                            .foregroundStyle(Color(hex: 0xAEE8DF))
                            .font(.footnote)
                            .lineLimit(1)
                        ForEach([144, 233, 987], id: \.self) { v in
                            Chip(title: "$\(v.formatted(.number.grouping(.automatic)))",
                                 active: vm.sample == Double(v)) {
                                vm.sample = Double(v)
                            }
                        }
                        Chip(title: "+5%", active: false, dashed: true) {
                            vm.sample = max(1, (vm.sample * 1.05).rounded())
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .layoutPriority(1)

                    Spacer(minLength: 8)

                    HStack(spacing: 8) {
                        // Inhale icon button (uses SF Symbol)
                        Button(action: { openCheckout() }) {
                            Image(systemName: "wind")
                                .imageScale(.medium)
                                .font(.system(size: 16, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityLabel("Inhale \(Int(vm.sample)) dollars")
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                }

                if let err = vm.errorMessage, !err.isEmpty {
                    ErrorBanner(err)
                }
                if vm.showToast {
                    ToastBanner("Inhale sealed. Thank you, sovereign.")
                }

                // Keep engine alive even if parent hides the whole block
                EngineKeepAliveView()
                    .frame(width: 1, height: 1)
                    .opacity(0.001)
            }
            .padding(basePad)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.linearGradient(
                        Gradient(colors: [Color.black.opacity(0.75), Color.black.opacity(0.55)]),
                        startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1))
            )
            .opacity(vm.expanded ? 1 : 0)
            .frame(height: vm.expanded ? nil : 0)
            .clipped()
            .animation(.easeInOut(duration: 0.18), value: vm.expanded)
        }
        .foregroundStyle(Color(hex: 0xE8FBF8))
        .environment(\.colorScheme, .dark)
        .dynamicTypeSize(.xSmall ... .xxxLarge) // opt into Dynamic Type scaling safely
        .task {
            await vm.configure(apiBase: apiBase, defaultUsd: ctaAmountUsd)
        }
        .onAppear { vm.onExpandChange = onExpandChange }
        .onDisappear { vm.teardown() }
    }

    private func toggleExpanded() { setExpanded(!vm.expanded) }
    private func setExpanded(_ x: Bool) {
        vm.expanded = x
        vm.onExpandChange?(x)
    }
    private func openCheckout() { Task { await vm.beginInlineCheckout() } }
}

// MARK: - Adaptive Ticker Row (no overlap on narrow widths)

private struct TickerRow: View {
    let title: String
    let priceLong: String
    let priceShort: String
    let pctLong: String
    let pctShort: String
    let pctPositive: Bool

    @ScaledMetric(relativeTo: .footnote) private var logoSize: CGFloat = 18

    var body: some View {
        ViewThatFits {
            // Full layout
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    PhiLogo().frame(width: logoSize, height: logoSize)
                    Text(title)
                        .font(.callout.weight(.semibold))
                        .opacity(0.9)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .truncationMode(.tail)
                }
                .layoutPriority(0)

                Spacer(minLength: 8)

                Text(priceLong)
                    .font(.system(.subheadline, design: .monospaced).weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .allowsTightening(true)
                    .layoutPriority(2)

                Text(pctLong)
                    .font(.system(.footnote, design: .monospaced).weight(.semibold))
                    .foregroundStyle(pctPositive ? Color(hex: 0x28C76F) : Color(hex: 0xFF4D4F))
                    .opacity(0.95)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .layoutPriority(1)
            }

            // Medium layout (shorter %)
            HStack(spacing: 10) {
                PhiLogo().frame(width: logoSize, height: logoSize)
                Text(title)
                    .font(.callout.weight(.semibold))
                    .opacity(0.9)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                Text(priceLong)
                    .font(.system(.subheadline, design: .monospaced).weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .allowsTightening(true)

                Text(pctShort)
                    .font(.system(.footnote, design: .monospaced).weight(.semibold))
                    .foregroundStyle(pctPositive ? Color(hex: 0x28C76F) : Color(hex: 0xFF4D4F))
                    .opacity(0.95)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            // Compact layout (price only)
            HStack(spacing: 10) {
                PhiLogo().frame(width: logoSize, height: logoSize)
                Text(title)
                    .font(.callout.weight(.semibold))
                    .opacity(0.9)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                Text(priceShort)
                    .font(.system(.subheadline, design: .monospaced).weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .allowsTightening(true)
            }
        }
    }
}

// MARK: - ViewModel

extension HomePriceChartCard {
    @MainActor
    final class VM: ObservableObject {
        // Kai constants (KKS v1.0 — EXACT bridge)
        static let kaiEpochMs: Double = 1715323541888                 // 2024-05-10 06:45:41.888 UTC
        static let breathS: Double = 3.0 + sqrt(5.0)                  // φ-exact breath period
        static let breathMs: Double = breathS * 1000.0                // ≈ 5236.0679 ms
        static let pulsesPerDay: Int = Int(round(86_400.0 / breathS)) // ≈ 16,501 pulses / 24h

        // Public-ish UI state
        @Published var expanded: Bool = false
        @Published var sample: Double = 144             // USD sample (drives issuance quote)
        @Published var showToast: Bool = false
        @Published var errorMessage: String? = nil

        // Engine state
        @Published var livePoints: [KPoint] = []
        @Published var lastTick: (pulse: Int, price: Double)? = nil

        // Wiring
        var apiBase: String = ""
        var onExpandChange: ((Bool) -> Void)?

        // Meta (from server → valuation meta)
        private var serverMeta: SigilMeta? = nil
        private var valuationMeta: KaiValuation.Metadata = .defaultIndexMeta()

        // Timer & subscriptions
        private var timer: Timer?
        private var cancellables = Set<AnyCancellable>()

        // MARK: Configure

        func configure(apiBase: String, defaultUsd: Double) async {
            self.apiBase = apiBase
            self.sample = defaultUsd

            // React to USD sample changes (recompute existing window for exact parity)
            $sample
                .removeDuplicates(by: { Int($0.rounded()) == Int($1.rounded()) })
                .sink { [weak self] _ in
                    Task { @MainActor in self?.reseedSeriesPreservingWindow() }
                }
                .store(in: &cancellables)

            // App lifecycle: re-sync pulse timer precisely after foregrounding
            #if canImport(UIKit)
            NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
                .sink { [weak self] _ in
                    Task { @MainActor in self?.schedulePulseAlignedTicks() }
                }
                .store(in: &cancellables)
            NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
                .sink { [weak self] _ in
                    Task { @MainActor in self?.invalidateTimer() }
                }
                .store(in: &cancellables)
            #endif

            await fetchSigilMeta() // may re-seed on success
            seedSeries()
            schedulePulseAlignedTicks()
        }

        func teardown() {
            invalidateTimer()
            cancellables.removeAll()
        }

        // MARK: Labels

        var priceLabel: String {
            guard let t = lastTick, t.price > 0 else { return "—" }
            return String(format: "$%.2f / Φ", t.price)
        }
        var priceShortLabel: String {
            guard let t = lastTick, t.price > 0 else { return "—" }
            return Self.abbrevCurrency(t.price) // e.g., $1.2K
        }

        var pct24h: Double {
            guard let t = lastTick else { return 0 }
            let prevPulse = t.pulse - VM.pulsesPerDay
            let prev = computePrice(pulse: prevPulse)
            guard prev > 0 else { return 0 }
            return ((t.price - prev) / prev) * 100.0
        }

        var pctLabelWithArrow: String {
            let pct = pct24h
            let s = String(format: "%@%.2f%%", pct >= 0 ? "+" : "−", abs(pct))
            return "\(pct >= 0 ? "▲" : "▼") \(s)"
        }
        var pctShortLabel: String {
            let pct = pct24h
            let s = String(format: "%@%.0f%%", pct >= 0 ? "+" : "−", abs(pct))
            return "\(pct >= 0 ? "▲" : "▼") \(s)"
        }

        var accessibilityTickerSummary: String {
            let dir = pct24h >= 0 ? "up" : "down"
            return "Price \(priceLabel). Twenty-four hour change \(String(format: "%.2f", abs(pct24h))) percent, \(dir)."
        }

        // MARK: Engine

        struct KPoint: Identifiable { let id = UUID(); let p: Int; let price: Double; let vol: Double }

        private func kaiPulseNow() -> Double {
            let nowMs = Date().timeIntervalSince1970 * 1000.0
            return (nowMs - VM.kaiEpochMs) / VM.breathMs
        }

        private func seedSeries(windowPoints: Int = 240) {
            let pEnd = Int(floor(kaiPulseNow()))
            let pStart = pEnd - max(2, windowPoints) + 1
            var pts: [KPoint] = []
            var prev: Double? = nil
            for p in pStart...pEnd {
                let (pr, vol) = computeForPulse(p, prevPrice: prev)
                prev = pr
                pts.append(.init(p: p, price: pr, vol: vol))
            }
            livePoints = pts
            if let last = pts.last {
                lastTick = (last.p, last.price)
            }
        }

        private func reseedSeriesPreservingWindow() {
            guard !livePoints.isEmpty else { seedSeries(); return }
            var pts: [KPoint] = []
            var prev: Double? = nil
            for p in livePoints.map({ $0.p }) {
                let (pr, vol) = computeForPulse(p, prevPrice: prev)
                prev = pr
                pts.append(.init(p: p, price: pr, vol: vol))
            }
            livePoints = pts
            if let last = pts.last { lastTick = (last.p, last.price) }
        }

        private func schedulePulseAlignedTicks() {
            invalidateTimer()
            tick() // immediate alignment (MainActor)
        }

        private func invalidateTimer() {
            timer?.invalidate()
            timer = nil
        }

        @objc private func tick() {
            let now = kaiPulseNow()
            let nextDelayMs = max(1.0, (1.0 - (now - floor(now))) * VM.breathMs + 2.0) // aim just after boundary
            let pInt = Int(floor(now))

            // Append next point if new pulse
            if livePoints.last?.p != pInt {
                let prevPrice = livePoints.last?.price
                let (pr, vol) = computeForPulse(pInt, prevPrice: prevPrice)
                var next = livePoints
                next.append(.init(p: pInt, price: pr, vol: vol))
                if next.count > 240 { next.removeFirst(next.count - 240) }
                livePoints = next
                lastTick = (pInt, pr)
            }

            // Re-arm aligned to next integer pulse (hop into MainActor from nonisolated timer callback)
            timer = Timer.scheduledTimer(withTimeInterval: nextDelayMs / 1000.0, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.tick()
                }
            }
            if let t = timer {
                RunLoop.main.add(t, forMode: .common)
            }
        }

        private func computeForPulse(_ p: Int, prevPrice: Double?) -> (Double, Double) {
            // 1) EXACT TS parity price from issuance math (deterministic)
            let real = computeIndexPrice(pulse: p)
            if real > 0 {
                return (round2(real), phiVol(pulse: p))
            }

            // 2) Fallback φ-oscillator (deterministic; mirrors TS spirit)
            let base = prevPrice ?? 1.618
            let price = max(0.0001, phiFallbackPrice(pulse: p, base: base))
            let vol = phiVol(pulse: p)
            return (round2(price), vol)
        }

        private func computePrice(pulse p: Int) -> Double {
            let (pr, _) = computeForPulse(p, prevPrice: lastTick?.price ?? 1.618)
            return pr
        }

        // EXACT price: USD per Φ = 1 / phiPerUsd from Issuance quote (TS parity)
        private func computeIndexPrice(pulse: Int) -> Double {
            let usdSample = max(1, Int(sample.rounded()))
            let ctx = KaiValuation.IssuanceContext(
                nowPulse: pulse,
                usd: Double(usdSample),
                currentStreakDays: 0,
                lifetimeUsdSoFar: 0,
                plannedHoldBeats: 0,
                choirNearby: nil,
                breathPhase01: nil
            )
            let q = KaiValuation.quotePhiForUsd(meta: valuationMeta, ctx: ctx)
            return q.phiPerUsd > 0 ? (1.0 / q.phiPerUsd) : 0.0
        }

        // φ-oscillator + helpers (fallback; deterministic)
        private func phiFallbackPrice(pulse: Int, base: Double) -> Double {
            let φ = (1.0 + sqrt(5.0)) / 2.0
            let slow  = sin((2.0 * .pi * Double(pulse)) / 44.0) * 0.85
            let fast1 = sin(2.0 * .pi * φ * Double(pulse)) * 0.42
            let fast2 = sin(2.0 * .pi * (φ - 1.0) * Double(pulse)) * 0.28
            let noise = sin(Double(pulse) * 0.1618) * 0.35
            return base + slow + fast1 + fast2 + noise
        }

        private func phiVol(pulse: Int) -> Double {
            let v = abs(sin((2.0 * .pi * Double(pulse)) / 11.0))
            return max(0.0, min(1.0, 0.35 + 0.65 * v))
        }

        private func round2(_ x: Double) -> Double { (x * 100.0).rounded() / 100.0 }

        // MARK: Meta + Purchases

        private func fetchSigilMeta() async {
            guard let url = URL(string: "\(apiBase)/api/sigil/meta") else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "GET"
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                let statusCode = (resp as? HTTPURLResponse)?.statusCode ?? -1
                guard (200..<300).contains(statusCode) else { return }
                let decoded = try JSONDecoder().decode(SigilMeta.self, from: data)
                self.serverMeta = decoded
                self.valuationMeta = decoded.toValuationMeta()
                reseedSeriesPreservingWindow()
            } catch {
                // keep defaults; deterministic fallback path remains
            }
        }

        func beginInlineCheckout() async {
            errorMessage = nil
            showToast = false

            // Map the chosen USD sample to your approved StoreKit product
            let usd = max(1, Int(sample.rounded()))
            let pid = ProductCatalog.closestProductId(forUSD: usd)

            do {
                let outcome = try await StoreKitProvider().buy(productId: pid.id)
                switch outcome {
                case .success(let txnId):
                    // Optionally notify your server to mint/unlock
                    await confirmToServer(transactionId: txnId, productId: pid.id, usd: pid.usd)
                    self.showToast = true
                case .cancelled:
                    break
                case .pending:
                    self.errorMessage = "Purchase pending."
                }
            } catch {
                self.errorMessage = (error as NSError).localizedDescription
            }
        }

        private func confirmToServer(transactionId: String, productId: String, usd: Int) async {
            guard let url = URL(string: "\(apiBase)/api/iap/confirm") else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: Any] = [
                "platform": "ios-iap",
                "transactionId": transactionId,
                "productId": productId,
                "usd": usd
            ]
            do {
                req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
                _ = try await URLSession.shared.data(for: req)
            } catch {
                // non-fatal: UI already shows success; you can retry later
            }
        }

        // MARK: Utils

        static func abbrevCurrency(_ value: Double) -> String {
            let absV = abs(value)
            let sign = value < 0 ? "-" : ""
            let (num, suffix): (Double, String) =
                absV >= 1_000_000_000 ? (absV / 1_000_000_000, "B") :
                absV >= 1_000_000     ? (absV / 1_000_000, "M") :
                absV >= 1_000         ? (absV / 1_000, "K") :
                                         (absV, "")
            return "\(sign)$\(String(format: num >= 100 ? "%.0f" : "%.1f", num))\(suffix)"
        }
    }
}

// MARK: - Product Catalog (map USD → StoreKit product ID)

private enum ProductCatalog {
    // Define the in-app products you created in App Store Connect
    // Adjust IDs to match your bundle’s product identifiers.
    private static let products: [(usd: Int, id: String)] = [
        (144, "sigil.inhale.usd.144"),
        (233, "sigil.inhale.usd.233"),
        (250, "sigil.inhale.usd.250"),
        (418, "sigil.inhale.usd.418"),
        (987, "sigil.inhale.usd.987")
    ]

    static func closestProductId(forUSD usd: Int) -> (id: String, usd: Int) {
        guard let exact = products.first(where: { $0.usd == usd }) else {
            // Pick the nearest SKU so StoreKit has a valid product
            let nearest = products.min(by: { abs($0.usd - usd) < abs($1.usd - usd) })!
            return (nearest.id, nearest.usd)
        }
        return (exact.id, exact.usd)
    }
}

// MARK: - Server Meta → Valuation Meta

/// Minimal decoding of server metadata with graceful fallbacks.
/// Only the fields we can map into KaiValuation.Metadata are included.
private struct SigilMeta: Decodable {
    struct IP: Decodable {
        struct Flow: Decodable { let atPulse: Int; let amountPhi: Double }
        let expectedCashflowPhi: [Flow]?
    }
    struct Transfer: Decodable { let senderKaiPulse: Int; let receiverKaiPulse: Int? }

    // Identity / rhythm
    let kaiPulse: Int?
    let pulse: Int?
    let userPhiKey: String?
    let beat: Int?
    let stepIndex: Int?
    let stepsPerBeat: Int?

    // Craft signals
    let seriesSize: Int?
    let quality: String?
    let creatorVerified: Bool?
    let creatorRep: Double?

    // Resonance
    let frequencyHz: Double?

    // Lineage
    let transfers: [Transfer]?
    let cumulativeTransfers: Int?

    // Optional intrinsic IP cashflows
    let ip: IP?

    // Policy hook
    let valuationPolicyId: String?

    // Map → KaiValuation.Metadata (conservative; defaults preserved)
    func toValuationMeta() -> KaiValuation.Metadata {
        var m = KaiValuation.Metadata.defaultIndexMeta()
        m.kaiPulse = kaiPulse ?? pulse
        m.pulse = pulse
        m.userPhiKey = userPhiKey
        m.beat = beat
        m.stepIndex = stepIndex
        m.stepsPerBeat = stepsPerBeat

        if let s = seriesSize { m.seriesSize = max(1, s) }
        if let q = quality?.lowercased() {
            switch q {
            case "low":  m.quality = .low
            case "high": m.quality = .high
            default:     m.quality = .med
            }
        }
        if let cv = creatorVerified { m.creatorVerified = cv }
        if let cr = creatorRep { m.creatorRep = max(0, min(1, cr)) }

        m.frequencyHz = frequencyHz

        if let ts = transfers {
            m.transfers = ts.map { KaiValuation.Transfer(senderKaiPulse: $0.senderKaiPulse, receiverKaiPulse: $0.receiverKaiPulse) }
        }
        m.cumulativeTransfers = cumulativeTransfers

        if let flows = ip?.expectedCashflowPhi {
            m.ipCashflows = flows.map { KaiValuation.IPFlow(atPulse: $0.atPulse, amountPhi: $0.amountPhi) }
        }

        m.valuationPolicyId = valuationPolicyId
        return m
    }
}

// MARK: - Chart (SwiftUI) — adaptive ticks, safe badges

private struct KaiPriceChartSwiftUI: View {
    let points: [HomePriceChartCard.VM.KPoint]

    // chart paddings scale a bit with Dynamic Type
    @ScaledMetric(relativeTo: .footnote) private var padTop: CGFloat = 28
    @ScaledMetric(relativeTo: .footnote) private var padLeft: CGFloat = 64
    @ScaledMetric(relativeTo: .footnote) private var padBottom: CGFloat = 36
    @ScaledMetric(relativeTo: .footnote) private var padRight: CGFloat = 20

    var body: some View {
        GeometryReader { geo in
            let padding = EdgeInsets(top: padTop, leading: padLeft, bottom: padBottom, trailing: padRight)
            let W = max(10.0, geo.size.width - padding.leading - padding.trailing)
            let H = max(10.0, geo.size.height - padding.top - padding.bottom)

            let xs = points.map { Double($0.p) }
            let ys = points.map { $0.price }
            let minX = xs.min() ?? 0, maxX = xs.max() ?? 1
            let minYv = ys.min() ?? 1, maxYv = ys.max() ?? 2
            let pad = (maxYv - minYv) * 0.12
            let minY = max(0.0, minYv - pad), maxY = maxYv + pad

            let sx: (Double) -> CGFloat = { x in
                guard maxX != minX else { return padding.leading }
                return CGFloat((x - minX) / (maxX - minX)) * W + padding.leading
            }
            let sy: (Double) -> CGFloat = { y in
                guard maxY != minY else { return padding.top }
                let ny = 1.0 - (y - minY) / (maxY - minY)
                return CGFloat(ny) * H + padding.top
            }

            ZStack {
                // Grid
                GridBackground(padding: padding, width: W, height: H)

                // Area
                if points.count >= 2 {
                    Path { p in
                        p.move(to: CGPoint(x: sx(Double(points[0].p)), y: sy(points[0].price)))
                        for pt in points.dropFirst() {
                            p.addLine(to: CGPoint(x: sx(Double(pt.p)), y: sy(pt.price)))
                        }
                        // close to bottom
                        p.addLine(to: CGPoint(x: sx(Double(points.last!.p)), y: padding.top + H))
                        p.addLine(to: CGPoint(x: sx(Double(points.first!.p)), y: padding.top + H))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(gradient: Gradient(colors: [
                        Color(hex: 0x37FFE4).opacity(0.28),
                        Color(hex: 0x37FFE4).opacity(0.00)
                    ]), startPoint: .top, endPoint: .bottom))
                }

                // Line
                Path { p in
                    guard let first = points.first else { return }
                    p.move(to: CGPoint(x: sx(Double(first.p)), y: sy(first.price)))
                    for pt in points.dropFirst() {
                        p.addLine(to: CGPoint(x: sx(Double(pt.p)), y: sy(pt.price)))
                    }
                }
                .stroke(Color(hex: 0x37E6D4), style: StrokeStyle(lineWidth: 2.25, lineCap: .round, lineJoin: .round))
                .shadow(color: Color.black.opacity(0.5), radius: 2, x: 0, y: 0)

                // Current price badge — pinned, no overlap with plot
                if let last = points.last {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(last.price, format: .currency(code: "USD"))
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(hex: 0x0A0F12).opacity(0.85))
                                    .overlay(RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.white.opacity(0.2), lineWidth: 1))
                            )
                    }
                    .padding(.trailing, 8)
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }

                // Axes labels (compact & adaptive)
                AxisLabels(
                    padding: padding,
                    minX: minX, maxX: maxX,
                    minY: minY, maxY: maxY,
                    W: W, H: H
                )
            }
        }
        .background(Color.clear)
    }
}

private struct GridBackground: View {
    let padding: EdgeInsets
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        let W = width
        let H = height
        let left = padding.leading, top = padding.top

        // Adaptive tick density by width/height
        let xTicks = max(3, Int(W / 80))
        let yTicks = max(2, Int(H / 60))

        return GeometryReader { _ in
            Path { p in
                for i in 0...xTicks {
                    let x = left + CGFloat(Double(i)/Double(xTicks)) * W
                    p.move(to: CGPoint(x: x, y: top))
                    p.addLine(to: CGPoint(x: x, y: top + H))
                }
                for i in 0...yTicks {
                    let y = top + CGFloat(Double(i)/Double(yTicks)) * H
                    p.move(to: CGPoint(x: left, y: y))
                    p.addLine(to: CGPoint(x: left + W, y: y))
                }
            }
            .stroke(Color.white.opacity(0.13), lineWidth: 1)
        }
    }
}

private struct AxisLabels: View {
    let padding: EdgeInsets
    let minX: Double, maxX: Double
    let minY: Double, maxY: Double
    let W: CGFloat, H: CGFloat

    @ScaledMetric(relativeTo: .footnote) private var labelPad: CGFloat = 22
    @ScaledMetric(relativeTo: .footnote) private var yInset: CGFloat = 4

    var body: some View {
        let xTicks = max(3, Int(W / 80))
        let yTicks = max(2, Int(H / 60))

        // X ticks + "pulse"
        ForEach(0...xTicks, id: \.self) { i in
            let v = minX + (Double(i)/Double(xTicks)) * (maxX - minX)
            let x = padding.leading + CGFloat(Double(i)/Double(xTicks)) * W
            Text("\(Int(v))")
                .font(.caption2)
                .foregroundStyle(Color(hex: 0xA2BBB6))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .position(x: x, y: padding.top + H + labelPad)
                .accessibilityLabel("Pulse \(Int(v))")
        }
        Text("pulse")
            .font(.caption2)
            .foregroundStyle(Color(hex: 0xA2BBB6))
            .position(x: padding.leading, y: padding.top + H + labelPad + 14)

        // Y ticks — labels increase upward (min at bottom, max at top)
        ForEach(0...yTicks, id: \.self) { i in
            let f = Double(i) / Double(yTicks)                 // 0 = top, 1 = bottom (screen space)
            let v = maxY - f * (maxY - minY)                   // numeric value
            let y = padding.top + CGFloat(f) * H               // position unchanged
            Text(Self.abbrevCurrency(v))
                .font(.caption2)
                .foregroundStyle(Color(hex: 0xA2BBB6))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .position(x: padding.leading - 44, y: y + yInset)
                .accessibilityLabel("\(Self.spokenCurrency(v))")
        }
    }

    static func abbrevCurrency(_ value: Double) -> String {
        let absV = abs(value)
        let sign = value < 0 ? "-" : ""
        let (num, suffix): (Double, String) =
            absV >= 1_000_000_000 ? (absV / 1_000_000_000, "B") :
            absV >= 1_000_000     ? (absV / 1_000_000, "M") :
            absV >= 1_000         ? (absV / 1_000, "K") :
                                     (absV, "")
        return "\(sign)$\(String(format: num >= 100 ? "%.0f" : "%.1f", num))\(suffix)"
    }
    static func spokenCurrency(_ value: Double) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .currency
        nf.maximumFractionDigits = 2
        return nf.string(from: NSNumber(value: value)) ?? "$\(value)"
    }
}

// MARK: - UI Bits

private struct Chip: View {
    let title: String
    var active: Bool
    var dashed: Bool = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.vertical, 6).padding(.horizontal, 10)
                .background(
                    Capsule()
                        .strokeBorder(active ? Color(hex: 0x37FFE4) : Color.white.opacity(0.12),
                                      style: StrokeStyle(lineWidth: 1, dash: dashed ? [5,4] : []))
                        .background(
                            Capsule().fill(active
                                           ? Color.white.opacity(0.10)
                                           : Color.white.opacity(0.04))
                        )
                )
        }.buttonStyle(.plain)
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .bold))
            .padding(.vertical, 8).padding(.horizontal, 14)
            .foregroundStyle(Color(hex: 0x031A17))
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        RadialGradient(colors: [Color(hex: 0x37FFE4),
                                                Color(hex: 0x37FFE4).opacity(0.2),
                                                .clear],
                                       center: .topLeading, startRadius: 0, endRadius: 140)
                    )
                    .overlay(
                        LinearGradient(colors: [Color(hex: 0x37FFE4).opacity(0.25),
                                                Color(hex: 0xA78BFA).opacity(0.25)],
                                       startPoint: .leading, endPoint: .trailing)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}

private struct ErrorBanner: View {
    let message: String
    init(_ message: String) { self.message = message }
    var body: some View {
        Text(message)
            .font(.footnote)
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(Color.red.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.red.opacity(0.25), lineWidth: 1)))
            .foregroundStyle(Color(hex: 0xFFB4B4))
            .accessibilityLabel("Error: \(message)")
    }
}

private struct ToastBanner: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(hex: 0x37FFE4))
                .frame(width: 8, height: 8)
                .shadow(color: Color(hex: 0x37FFE4), radius: 6)
            Text(text).font(.footnote)
                .lineLimit(2).minimumScaleFactor(0.8)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(Color.white.opacity(0.06))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.28), lineWidth: 1)))
        .accessibilityLabel(text)
    }
}

// Keep engine alive even if parent removes chart view
private struct EngineKeepAliveView: View { var body: some View { Color.clear } }

// MARK: - Phi Logo (breathing, masked)

private struct PhiLogo: View {
    @State private var t: Double = 0
    var body: some View {
        ZStack {
            AngularGradient(colors: [
                Color(hex: 0xFF3366),
                Color(hex: 0xFF9A00),
                Color(hex: 0xFFE600),
                Color(hex: 0x1DD07A),
                Color(hex: 0x00B8FF),
                Color(hex: 0x7A4DFF),
                Color(hex: 0xFF33D1),
                Color(hex: 0xFF3366)
            ], center: .center, angle: .degrees(t))
                .saturation(1.05).brightness(0.05).contrast(1.02)
                .mask(
                    Image("phi") // add /assets/phi.svg as "phi" in Assets
                        .resizable().scaledToFit()
                )
                .scaleEffect(1 + 0.015 * sin(t/12))
                .animation(.easeInOut(duration: HomePriceChartCard.VM.breathS).repeatForever(autoreverses: true), value: t)
            RadialGradient(colors: [Color(hex: 0x37FFE4).opacity(0.15),
                                    Color(hex: 0xA78BFA).opacity(0.10),
                                    .clear], center: .center, startRadius: 0, endRadius: 18)
                .blur(radius: 1.2).opacity(0.35)
        }
        .frame(width: 18, height: 18)
        .onAppear { withAnimation { t = 360 } }
        .accessibilityHidden(true)
    }
}

// MARK: - Helpers

private extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF)/255.0
        let g = Double((hex >> 8) & 0xFF)/255.0
        let b = Double(hex & 0xFF)/255.0
        self = Color(red: r, green: g, blue: b, opacity: alpha)
    }
}
