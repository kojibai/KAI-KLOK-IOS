//
//  InvestorSigilModalView.swift
//  KaiKlok
//
//  Crafted for sovereign calm. Exact. Harmonic.
//  iOS 16+ (best on iOS 17+).
//

import SwiftUI
import StoreKit
import UIKit
import AVFoundation

// MARK: - Server API -----------------------------------------------------------

private let API_BASE = URL(string: "https://pay.kaiklok.com")!

struct KaiClockResp: Decodable {
    let nowPulse: Int
    let pulsesPerBeat: Int
}

struct SigilMetadataLite: Codable {
    struct IP: Codable { let expectedCashflowPhi: [Double]? }
    let ip: IP?
}

struct MintReq: Encodable {
    let amountUsd: Double
    let method: String // "iap"
    let iapProductId: String
    let iapTransactionId: UInt64
    let appAccountToken: UUID
    let nowPulse: Int
}

struct MintResp: Decodable {
    let ok: Bool
    let sigilId: String
    let glyphHash: String
    let meta: SigilMetadataLite
    let receiptUrl: String?
}

enum NetError: LocalizedError {
    case badStatus(Int), decode, cancelled, generic(String)
    var errorDescription: String? {
        switch self {
        case .badStatus(let s): return "Server error (\(s))"
        case .decode:           return "Decode failed."
        case .cancelled:        return "Cancelled."
        case .generic(let m):   return m
        }
    }
}

enum API {
    static func fetchClock() async throws -> KaiClockResp {
        var req = URLRequest(url: API_BASE.appending(path: "/api/clock"))
        req.timeoutInterval = 15
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, 200..<300 ~= http.statusCode
        else { throw NetError.badStatus((resp as? HTTPURLResponse)?.statusCode ?? -1) }
        return try JSONDecoder().decode(KaiClockResp.self, from: data)
    }

    static func fetchSigilMeta() async -> SigilMetadataLite? {
        var req = URLRequest(url: API_BASE.appending(path: "/api/sigil/meta"))
        req.timeoutInterval = 15
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, 200..<300 ~= http.statusCode else { return nil }
            return try? JSONDecoder().decode(SigilMetadataLite.self, from: data)
        } catch { return nil }
    }

    static func mintSigil(_ body: MintReq) async throws -> MintResp {
        var req = URLRequest(url: API_BASE.appending(path: "/api/sigil/mint"))
        req.httpMethod  = "POST"
        req.timeoutInterval = 25
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw NetError.generic(msg.isEmpty ? "Mint failed (\((resp as? HTTPURLResponse)?.statusCode ?? -1))" : msg)
        }
        return try JSONDecoder().decode(MintResp.self, from: data)
    }
}

// MARK: - Visual System --------------------------------------------------------

private struct AtlanteanGlass: ViewModifier {
    var radius: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(LinearGradient(colors: [Color.white.opacity(0.22), Color.cyan.opacity(0.20)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.35), radius: 24, y: 8)
            .shadow(color: Color.mint.opacity(0.08), radius: 30)
    }
}

private extension View {
    func atlanteanGlass(radius: CGFloat = 16) -> some View { modifier(AtlanteanGlass(radius: radius)) }
}

private func kaiHex(_ hex: String, alpha: Double = 1.0) -> Color {
    var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.hasPrefix("#") { s.removeFirst() }
    var n: UInt64 = 0
    guard Scanner(string: s).scanHexInt64(&n) else { return .white.opacity(alpha) }
    let r, g, b: Double
    switch s.count {
    case 6:
        r = Double((n >> 16) & 0xff) / 255
        g = Double((n >>  8) & 0xff) / 255
        b = Double( n        & 0xff) / 255
        return Color(red: r, green: g, blue: b, opacity: alpha)
    case 8:
        let rr = Double((n >> 24) & 0xff) / 255
        let gg = Double((n >> 16) & 0xff) / 255
        let bb = Double((n >>  8) & 0xff) / 255
        let aa = Double( n        & 0xff) / 255
        return Color(red: rr, green: gg, blue: bb, opacity: min(1, max(0, alpha * aa)))
    default:
        return .white.opacity(alpha)
    }
}

// MARK: - Aurora Backdrop (soft, harmonic, 5.236s breath) ---------------------

private struct AtlanteanAurora: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let period: Double = 5.236

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let p = (t.truncatingRemainder(dividingBy: period) / period) // 0..1
            let breath = sin(p * 2 * .pi) // -1..1
            let a = reduceMotion ? 0.0 : (breath + 1) / 2 // 0..1

            Canvas { context, size in
                let base = min(size.width, size.height)

                func blob(_ seed: Double, _ hue: CGFloat, _ r: CGFloat) {
                    // gentle drift
                    let phase = reduceMotion ? 0 : CGFloat(sin((t + seed) * (2 * .pi / (period * 2))))
                    let x = size.width * (0.5 + 0.35 * cos(CGFloat(seed) + phase))
                    let y = size.height * (0.35 + 0.25 * sin(CGFloat(seed * 0.8) + phase))
                    let radius = r * (0.85 + 0.35 * a)
                    let rect = CGRect(x: x - radius, y: y - radius, width: radius*2, height: radius*2)

                    let grad = Gradient(colors: [
                        Color(hue: hue, saturation: 0.55, brightness: 1.0, opacity: 0.12 + 0.12 * a),
                        .clear
                    ])
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .radialGradient(grad, center: CGPoint(x: x, y: y), startRadius: 0, endRadius: radius)
                    )
                }

                blob(1.0, 0.52, base * 0.55)   // mint-cyan
                blob(2.2, 0.78, base * 0.45)   // purple
                blob(3.4, 0.62, base * 0.35)   // teal
                blob(4.6, 0.83, base * 0.28)   // magenta
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Pulse Bar (exact 5.236 s, stutter-less) ------------------------------

private struct PulseBar: View {
    private let period: TimeInterval = 5.236  // exact UI period
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let p = (t.truncatingRemainder(dividingBy: period) / period)  // 0...1
            GeometryReader { geo in
                let width = geo.size.width * p
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.10))
                    ZStack(alignment: .trailing) {
                        Capsule()
                            .fill(LinearGradient(colors: [kaiHex("#9DFFF7"), kaiHex("#B2A0FF")],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(0, width))
                        Circle()
                            .fill(Color.white.opacity(0.20))
                            .frame(width: 10, height: 10)
                            .offset(x: max(-5, width - 5))
                            .blur(radius: 1.5)
                    }
                }
                .transaction { $0.animation = nil }
            }
        }
        .frame(height: 5)
        .allowsHitTesting(false)
        .accessibilityLabel("Kai pulse progress")
    }
}

// MARK: - Sparkline (lightweight) ---------------------------------------------

private struct PhiSparkline: View {
    let data: [CGPoint]
    var body: some View {
        Canvas { ctx, size in
            guard data.count > 1 else { return }
            let minX = data.map(\.x).min() ?? 0, maxX = data.map(\.x).max() ?? 1
            let minY = data.map(\.y).min() ?? 0, maxY = data.map(\.y).max() ?? 1
            let pad: CGFloat = 6
            func nx(_ x: CGFloat) -> CGFloat { pad + (size.width - pad*2) * ((x - minX) / max(0.0001, maxX - minX)) }
            func ny(_ y: CGFloat) -> CGFloat { size.height - pad - (size.height - pad*2) * ((y - minY) / max(0.0001, maxY - minY)) }
            var path = Path()
            for (i, p) in data.enumerated() {
                let q = CGPoint(x: nx(p.x), y: ny(p.y))
                i == 0 ? path.move(to: q) : path.addLine(to: q)
            }
            ctx.addFilter(.shadow(color: .mint.opacity(0.45), radius: 7))
            ctx.stroke(path, with: .color(Color.mint.opacity(0.95)), lineWidth: 1.8)
        }
        .frame(height: 66)
        .accessibilityHidden(true)
    }
}

// MARK: - Live Sigil (deterministic & pulse-synced) ----------------------------

private struct SigilStage: View {
    let amount: Double
    let size: CGFloat

    private let pulseMs: Double = 5236
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation) { ctx in
            let now = ctx.date.timeIntervalSinceReferenceDate
            let phase = (now.truncatingRemainder(dividingBy: pulseMs) / pulseMs)
            let pulseIndex = Int(floor(now / pulseMs))

            let scale = reduceMotion ? 1 : (1.0 + 0.015 * sin(phase * 2 * .pi)) // subtle breath

            ZStack {
                OrnamentCanvas(amount: amount, pulseIndex: pulseIndex, size: size)
                    .frame(width: size, height: size)
                    .shadow(color: kaiHex("#37FFE4").opacity(0.18), radius: 12, y: 2)
                KaiGlyphCore(amount: amount, pulseIndex: pulseIndex, phase: reduceMotion ? 0 : phase, size: size)
                    .frame(width: size, height: size)
                    .blendMode(.plusLighter)
            }
            .scaleEffect(scale)
            .transaction { $0.animation = nil }
        }
        .accessibilityLabel("Sigil amount \(Int(amount)) US dollars")
    }

    // Ornament star/poly field (deterministic)
    private struct OrnamentCanvas: View {
        let amount: Double
        let pulseIndex: Int
        let size: CGFloat

        var body: some View {
            Canvas { ctx, _ in
                let seed = hash("\(Int(round(amount*100)))|iap|pulse#\(pulseIndex)")
                var rng = RNG(seed: seed)

                let baseLayers = Int(clamp(3, 10, lerp(3, 10, logScale(amount))))
                let spokes = Int(clamp(6, 20, lerp(6, 20, min(1, amount/2000))))
                let cx = size/2, cy = size/2
                let rBase = size * 0.42

                let hueA = fmod(200 + lerp(0, 40, rng.nextUnit()), 360)
                let hueB = fmod(hueA + 90, 360)

                for i in 0..<baseLayers {
                    let t = Double(i) / Double(max(1, baseLayers-1))
                    let r = rBase * (0.2 + 0.8 * (1 - t*t))
                    let rotation = rng.nextUnit() * .pi * 2
                    let jitter = lerp(0, r * 0.08, t)
                    let width = lerp(1.2, 2.4, 1 - t)

                    var points: [CGPoint] = []
                    for k in 0..<spokes {
                        let ang = rotation + (Double(k)/Double(spokes)) * .pi * 2
                        let rr = r + (rng.nextUnit()-0.5) * jitter
                        points.append(CGPoint(x: cx + cos(ang) * rr, y: cy + sin(ang) * rr))
                    }

                    let opacity = lerp(0.85, 0.25, t)
                    let hue = round(lerp(hueA, hueB, fmod(t * 1.61803398875, 1)))
                    let stroke = Color(hue: hue/360.0, saturation: 0.92, brightness: 0.72, opacity: opacity)
                    let fill   = Color(hue: hue/360.0, saturation: 0.90, brightness: 0.64, opacity: opacity*0.18)

                    var poly = Path()
                    if let first = points.first {
                        poly.move(to: first)
                        for p in points.dropFirst() { poly.addLine(to: p) }
                        poly.closeSubpath()
                        ctx.stroke(poly, with: .color(stroke), lineWidth: width)
                        ctx.fill(poly, with: .color(fill))
                    }
                }

                // dash rings from cents
                let cents = Int(round((amount - floor(amount)) * 100))
                let satellites = max(0, min(6, cents / 17))
                for _ in 0..<satellites {
                    let rr = rBase * lerp(0.18, 0.48, rng.nextUnit())
                    let sw = lerp(0.6, 1.5, rng.nextUnit())
                    let dash = CGFloat(Int(lerp(4, 14, rng.nextUnit())))
                    var ring = Path()
                    ring.addEllipse(in: CGRect(x: cx-rr, y: cy-rr, width: rr*2, height: rr*2))
                    ctx.stroke(ring, with: .color(kaiHex("#E8FBF8").opacity(0.35)), style: StrokeStyle(lineWidth: sw, dash: [dash, dash]))
                }
            }
        }
    }

    // Glyph core (needle + petals; deterministic per pulse)
    private struct KaiGlyphCore: View {
        let amount: Double
        let pulseIndex: Int
        let phase: Double // 0..1
        let size: CGFloat

        var body: some View {
            Canvas { ctx, _ in
                let baseSig = "\(Int(round(amount*100)))|iap"
                let seed = hash("\(baseSig)|pulse#\(pulseIndex)")
                let beat  = Int((seed >> 5) % 63)
                let stepPct = clamp01(phase)
                let chakraIndex = Int((seed >> 17) % UInt64(Chakra.allCases.count))
                let chakra = Chakra.allCases[chakraIndex]

                let cx = size/2, cy = size/2
                let rOuter = size * 0.40
                let rInner = size * 0.18

                let petals = 7 + (beat % 5)
                for i in 0..<petals {
                    let t = Double(i) / Double(petals)
                    let ang = (t + stepPct) * 2 * .pi
                    let rr  = rOuter * (0.76 + 0.18 * sin(ang*2))
                    let p0 = CGPoint(x: cx + cos(ang) * rr, y: cy + sin(ang) * rr)
                    let p1 = CGPoint(x: cx + cos(ang + 0.1) * rr * 0.86, y: cy + sin(ang + 0.1) * rr * 0.86)
                    var petal = Path()
                    petal.move(to: CGPoint(x: cx, y: cy))
                    petal.addQuadCurve(to: p0, control: CGPoint(x: cx + cos(ang-0.14)*rInner, y: cy + sin(ang-0.14)*rInner))
                    petal.addQuadCurve(to: p1, control: CGPoint(x: cx + cos(ang+0.14)*rInner, y: cy + sin(ang+0.14)*rInner))
                    petal.closeSubpath()
                    let hueBase: Double = (chakra.hue + Double(beat%9)*4).truncatingRemainder(dividingBy: 360)
                    let col = Color(hue: hueBase/360, saturation: 0.92, brightness: 0.95, opacity: 0.20 + 0.40 * (1 - t))
                    ctx.fill(petal, with: .color(col))
                }

                let sweepAng = -Double.pi/2 + stepPct * 2 * .pi
                let tip = CGPoint(x: cx + cos(sweepAng) * (rOuter * 0.86),
                                  y: cy + sin(sweepAng) * (rOuter * 0.86))
                var needle = Path()
                needle.move(to: CGPoint(x: cx, y: cy))
                needle.addLine(to: tip)
                ctx.stroke(needle, with: .color(kaiHex("#7ff7ff")), lineWidth: 2.5)

                let cap = CGRect(x: cx-5, y: cy-5, width: 10, height: 10)
                ctx.fill(Path(ellipseIn: cap), with: .color(kaiHex("#8beaff").opacity(0.9)))
                var ring = Path()
                ring.addEllipse(in: CGRect(x: cx-rInner, y: cy-rInner, width: rInner*2, height: rInner*2))
                ctx.stroke(ring, with: .color(kaiHex("#E8FBF8").opacity(0.18)), lineWidth: 1.2)
            }
        }

        private enum Chakra: CaseIterable { case Root, Sacral, SolarPlexus, Heart, Throat, ThirdEye, Crown
            var hue: Double {
                switch self {
                case .Root: return 0
                case .Sacral: return 30
                case .SolarPlexus: return 52
                case .Heart: return 140
                case .Throat: return 196
                case .ThirdEye: return 248
                case .Crown: return 285
                }
            }
        }
    }
}

// MARK: - RNG/Math helpers -----------------------------------------------------

private func hash(_ s: String) -> UInt64 {
    var h: UInt64 = 0x811C9DC5
    for u in s.utf8 {
        h ^= UInt64(u)
        h = h &+ ((h << 1) &+ (h << 4) &+ (h << 7) &+ (h << 8) &+ (h << 24))
    }
    return h
}
private struct RNG {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed &* 6364136223846793005 &+ 1 }
    mutating func next() -> UInt64 {
        state = state &* 2862933555777941757 &+ 3037000493
        return state
    }
    mutating func nextUnit() -> Double { Double(next() % 1_000_000) / 1_000_000.0 }
}
private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
private func clamp(_ lo: Double, _ hi: Double, _ v: Double) -> Double { max(lo, min(hi, v)) }
private func clamp01(_ v: Double) -> Double { clamp(0, 1, v) }
private func logScale(_ amount: Double) -> Double {
    guard amount.isFinite && amount > 0 else { return 0 }
    return min(1, max(0, log10(amount) / 4))
}

// MARK: - Skeletons & Confetti -------------------------------------------------

private struct SkeletonLine: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var height: CGFloat = 16
    var radius: CGFloat = 10
    @State private var phase: CGFloat = 0
    var body: some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(LinearGradient(colors: [Color.white.opacity(0.08), Color.white.opacity(0.16), Color.white.opacity(0.08)],
                                 startPoint: .leading, endPoint: .trailing))
            .mask(
                GeometryReader { geo in
                    Rectangle()
                        .fill(
                            LinearGradient(stops: [
                                .init(color: .white.opacity(0.0), location: 0),
                                .init(color: .white.opacity(0.9), location: 0.5),
                                .init(color: .white.opacity(0.0), location: 1),
                            ], startPoint: .leading, endPoint: .trailing)
                        )
                        .offset(x: (reduceMotion ? geo.size.width/2 : geo.size.width) * phase - geo.size.width)
                }
            )
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 2
                }
            }
            .frame(height: height)
    }
}

private struct ConfettiBurst: View {
    @Binding var active: Bool
    private let colors: [Color] = [.mint, .purple, .cyan, .white]
    private let count = 32

    var body: some View {
        TimelineView(.animation) { context in
            Canvas { ctx, size in
                guard active else { return }
                let t = context.date.timeIntervalSinceReferenceDate
                for i in 0..<count {
                    var rng = RandomNumberGeneratorWithSeed(seed: UInt64(i) ^ UInt64(t * 1000))
                    let life: Double = 1.2
                    let p = (t + Double(i) * 0.02).truncatingRemainder(dividingBy: life) / life
                    let angle = Double.random(in: 0...(2*Double.pi), using: &rng)
                    let r = Double.random(in: 0...1, using: &rng)
                    let radius = (0.15 + 0.85 * (1 - p)) * Double(min(size.width, size.height))/2
                    let x = size.width/2 + CGFloat(cos(angle) * radius)
                    let y = size.height/2 + CGFloat(sin(angle) * radius * 0.6)
                    let s = 4 + 9 * (1 - p) * CGFloat(r+0.2)

                    ctx.opacity = 1 - p
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: s, height: s)),
                             with: .color(colors[i % colors.count]))
                }
            }
        }
        .allowsHitTesting(false)
        .overlay {
            Color.clear.onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) { active = false }
            }
        }
    }
}

private struct RandomNumberGeneratorWithSeed: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed &* 6364136223846793005 &+ 1 }
    mutating func next() -> UInt64 {
        state = state &* 2862933555777941757 &+ 3037000493
        return state
    }
}

// MARK: - Deterministic issuance math -----------------------------------------

private struct IssuancePolicy {
    let baseUsdPerPhi: Double
    let adoptionMaxBoost: Double
    let premiumBeatAmp: Double
    let sizeCurveK: Double
    let tierFib: [Int]
}
private let DEFAULT_POLICY = IssuancePolicy(
    baseUsdPerPhi: 144,
    adoptionMaxBoost: 0.25,
    premiumBeatAmp: 0.10,
    sizeCurveK: 0.08,
    tierFib: [1597, 2584, 4181, 6765, 10946, 17711, 28657, 46368, 75025, 121393]
)

private struct IssuanceQuote {
    let phiPerUsd: Double
    let usdPerPhi: Double
    let chips: (adoption: Double, premium: Double, size: Double, streak: Double, tier: Double, milestone: Double)
    let expl: String
}

private func quotePhiForUsd(meta: SigilMetadataLite?,
                            nowPulse: Int,
                            pulsesPerBeat: Int,
                            usd: Double,
                            policy: IssuancePolicy = DEFAULT_POLICY) -> IssuanceQuote {
    let avgFlow = (meta?.ip?.expectedCashflowPhi ?? []).reduce(0, +) / Double(max(1, meta?.ip?.expectedCashflowPhi?.count ?? 0))
    let adoption = 1.0 + policy.adoptionMaxBoost * clamp01( log10(max(1, avgFlow + 1)) / 3.0 )

    let phase = Double(nowPulse % max(1, pulsesPerBeat)) / Double(max(1, pulsesPerBeat))
    let premium = 1.0 + policy.premiumBeatAmp * sin(phase * 2 * .pi)

    let size = 1.0 + policy.sizeCurveK * sqrt(max(0, usd)) / 40.0
    let streak = 1.0

    let lastBelow = policy.tierFib.last(where: { Double($0) <= usd }) ?? 0
    let tier = 1.0 + (lastBelow > 0 ? 0.03 : 0.0)
    let milestone = policy.tierFib.contains(Int(round(usd))) ? 1.02 : 1.0

    let usdPerPhi = max(0.0001, policy.baseUsdPerPhi * adoption * premium * size * streak * tier * milestone)
    let phiPerUsd = 1.0 / usdPerPhi

    let expl = """
    adoption ×\(String(format: "%.3f", adoption)) · premium ×\(String(format: "%.3f", premium)) · size ×\(String(format: "%.3f", size)) · streak ×\(String(format: "%.3f", streak)) · tier ×\(String(format: "%.3f", tier)) · milestone ×\(String(format: "%.3f", milestone))
    """
    return .init(phiPerUsd: phiPerUsd, usdPerPhi: usdPerPhi,
                 chips: (adoption, premium, size, streak, tier, milestone),
                 expl: expl)
}

private func buildExchangeSeries(meta: SigilMetadataLite?,
                                 nowPulse: Int,
                                 pulsesPerBeat: Int,
                                 usdSample: Double) -> [CGPoint] {
    let start = max(0, nowPulse - pulsesPerBeat * 6)
    let end   = start + pulsesPerBeat * 12
    let step  = max(1, pulsesPerBeat / 7)
    var out: [CGPoint] = []
    for p in stride(from: start, through: end, by: step) {
        let q = quotePhiForUsd(meta: meta, nowPulse: p, pulsesPerBeat: pulsesPerBeat, usd: usdSample)
        out.append(.init(x: CGFloat(p), y: CGFloat(q.usdPerPhi)))
    }
    return out
}

// MARK: - Live Φ Panel (real-time) --------------------------------------------

private struct LivePhiPanel: View {
    let amount: Double
    let meta: SigilMetadataLite?
    let clock: KaiClockResp?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                LinearGradient(colors: [kaiHex("#9DFFF7"), .white], startPoint: .leading, endPoint: .trailing)
                    .mask(Text("Φ ∴ ＄").font(.caption.weight(.bold)))
                    .frame(height: 14)
                Spacer()
                if let c = clock {
                    Label("Pulse \(c.nowPulse)", systemImage: "waveform.path.ecg")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.mint)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.mint.opacity(0.12), in: Capsule())
                        .accessibilityLabel("Pulse \(c.nowPulse)")
                } else {
                    SkeletonLine(height: 14, radius: 6).frame(width: 90)
                }
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(quote != nil ? "\(quote!.phiPerUsd, specifier: "%.6f") Φ / $" : "—")
                        .font(.system(.title3, design: .rounded).weight(.heavy))
                    Text(quote != nil ? "\(quote!.usdPerPhi, specifier: "%.4f") $ / Φ" : "—")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            PhiSparkline(data: series)

            if let q = quote {
                let chips = [
                    "adoption ×\(String(format: "%.3f", q.chips.adoption))",
                    "premium ×\(String(format: "%.3f", q.chips.premium))",
                    "size ×\(String(format: "%.3f", q.chips.size))",
                    "streak ×\(String(format: "%.3f", q.chips.streak))",
                    "tier ×\(String(format: "%.3f", q.chips.tier))",
                    "milestone ×\(String(format: "%.3f", q.chips.milestone))",
                ]
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 6)], spacing: 6) {
                    ForEach(chips, id: \.self) { s in
                        Text(s)
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(
                                LinearGradient(colors: [Color.mint.opacity(0.12), Color.purple.opacity(0.08)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                            )
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.mint.opacity(0.22), lineWidth: 1))
                    }
                }
            }

            Text("Breath-backed issuance seals at mint with the Kai-Klok pulse.")
                .font(.footnote)
                .opacity(0.85)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.mint.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4,4]))
                .fill(Color.white.opacity(0.05))
        )
    }

    private var quote: IssuanceQuote? {
        guard let c = clock else { return nil }
        let amt = amount.isFinite && amount > 0 ? amount : 1
        return quotePhiForUsd(meta: meta, nowPulse: c.nowPulse, pulsesPerBeat: max(1, c.pulsesPerBeat), usd: amt)
    }

    private var series: [CGPoint] {
        guard let c = clock else { return [] }
        let amt = amount.isFinite && amount > 0 ? amount : 1
        return buildExchangeSeries(meta: meta, nowPulse: c.nowPulse, pulsesPerBeat: max(1, c.pulsesPerBeat), usdSample: amt)
    }
}

// MARK: - Main Modal -----------------------------------------------------------

struct InvestorSigilModalView: View {
    @Binding var isOpen: Bool
    let userPhiKey: String

    @StateObject private var iap = IAPManager()   // Provided elsewhere in your app.

    @State private var selected: Product?
    @State private var busy = false
    @State private var error: String?
    @State private var minted: MintResp?
    @State private var meta: SigilMetadataLite?
    @State private var clock: KaiClockResp?

    @State private var showConfetti = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if isOpen {
                // Backdrop stack (instantiate view + layers)
                ZStack {
                    AtlanteanAurora()
                    LinearGradient(stops: [
                        .init(color: Color.black.opacity(0.75), location: 0.0),
                        .init(color: Color.black.opacity(0.85), location: 1.0),
                    ], startPoint: .top, endPoint: .bottom)
                    Color.black.opacity(0.0001)
                        .contentShape(Rectangle())
                        .ignoresSafeArea()
                        .onTapGesture { close() } // tap-outside to dismiss
                }
                .ignoresSafeArea()

                // Content
                ScrollView {
                    VStack(spacing: 18) {

                        // Drag dismiss handle (no X)
                        Capsule()
                            .fill(.white.opacity(0.18))
                            .frame(width: 42, height: 5)
                            .padding(.top, 12)
                            .accessibilityHidden(true)
                            .gesture(
                                DragGesture(minimumDistance: 20)
                                    .onEnded { v in
                                        if v.translation.height > 120 { close() }
                                    }
                            )

                        // Header
                        VStack(spacing: 10) {
                            LinearGradient(colors: [kaiHex("#9DFFF7"), .white, kaiHex("#BDA9FF")],
                                           startPoint: .leading, endPoint: .trailing)
                                .mask(
                                    Text("Kairos Kurrensy")
                                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                                )
                                .shadow(color: .mint.opacity(0.14), radius: 16, y: 2)

                            Text("Exhale Offering, Inhale Sovereignty")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.88))

                            PulseBar()
                        }
                        .padding(.vertical, 10)
                        .atlanteanGlass(radius: 18)

                        // Live Sigil
                        SigilStage(amount: selectedAmountOrFallback, size: 140)
                            .padding(.top, 4)

                        // Products
                        productGrid

                        // Live Φ panel
                        LivePhiPanel(amount: selectedAmountOrFallback, meta: meta, clock: clock)

                        // Error (as toast card)
                        if let error {
                            Text(error)
                                .font(.callout)
                                .foregroundColor(.pink)
                                .padding(12)
                                .background(Color.pink.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12).stroke(Color.pink.opacity(0.3), lineWidth: 1)
                                )
                                .transition(.opacity)
                        }

                        // CTA — single primary
                        Button {
                            Task { await onPurchase() }
                        } label: {
                            HStack(spacing: 10) {
                                if busy { ProgressView().tint(.black) }
                                Text(busy ? "Purchasing…" : "Inhale Sigil-Glyph →")
                                    .font(.headline.weight(.heavy))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                LinearGradient(colors: [kaiHex("#9DFFF7"), kaiHex("#B2A0FF")],
                                               startPoint: .leading, endPoint: .trailing),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                            .foregroundColor(.black)
                            .shadow(color: Color.mint.opacity(0.30), radius: 18, y: 8)
                        }
                        .disabled(busy || selected == nil)
                        .overlay(alignment: .bottom) {
                            if selected == nil && !busy {
                                Text("Select a tier")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .offset(y: 36)
                            }
                        }

                        // Verification notes
                        verificationPanel

                        // Mint result
                        if let minted {
                            mintResult(minted)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                                .onAppear {
                                    showConfetti = true
                                    #if canImport(AVFoundation)
                                    if #available(iOS 13.0, *) {
                                        let session = AVAudioSession.sharedInstance()
                                        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
                                    }
                                    #endif
                                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                                }
                        }

                        // Footer
                        Text("Proof of Breath™")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.8))
                            .padding(.bottom, 8)
                            .opacity(0.9)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 28)
                    .frame(maxWidth: 980)
                }
                .task {
                    await iap.loadProducts()
                    async let m = API.fetchSigilMeta()
                    async let c = API.fetchClock()
                    meta = await m
                    clock = try? await c

                    // Refresh Kai clock periodically to keep Φ price moving in real time
                    Task {
                        while !Task.isCancelled && isOpen {
                            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3s
                            if Task.isCancelled || !isOpen { break }
                            if let newClock = try? await API.fetchClock() {
                                await MainActor.run { self.clock = newClock }
                            }
                        }
                    }
                }

                // Celebration
                ConfettiBurst(active: $showConfetti)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut, value: isOpen)
    }

    // MARK: Product Grid -------------------------------------------------------

    private var productGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose your inhale amount")
                .font(.headline)
                .foregroundStyle(.white)

            if iap.isLoading && iap.products.isEmpty {
                VStack(spacing: 8) {
                    SkeletonLine(height: 52)
                    SkeletonLine(height: 52)
                    SkeletonLine(height: 52)
                }
                .atlanteanGlass()
                .padding(.vertical, 6)
            } else if iap.products.isEmpty {
                Text("No tiers available. Configure In-App Purchase products in App Store Connect.")
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .atlanteanGlass()
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                    ForEach(iap.products, id: \.id) { p in
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) { selected = p }
                            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        } label: {
                            VStack(spacing: 8) {
                                HStack {
                                    Text(p.displayName)
                                        .font(.subheadline.bold())
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                    Spacer()
                                    if selected?.id == p.id {
                                        Image(systemName: "checkmark.seal.fill")
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.black, Color.mint)
                                            .font(.system(size: 14, weight: .bold))
                                            .transition(.scale.combined(with: .opacity))
                                    }
                                }
                                Text(p.displayPrice)
                                    .font(.title3.weight(.heavy))
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                            .background(
                                LinearGradient(colors: [
                                    Color.white.opacity(selected?.id == p.id ? 0.16 : 0.08),
                                    Color.white.opacity(0.05)
                                ], startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(selected?.id == p.id ? Color.mint : Color.white.opacity(0.16), lineWidth: 1)
                                    .shadow(color: (selected?.id == p.id ? Color.mint : .clear).opacity(0.35), radius: 12)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Select tier \(p.displayName) for \(p.displayPrice)")
                    }
                }
            }
        }
        .atlanteanGlass()
    }

    // MARK: Verification Panel --------------------------------------------------

    private var verificationPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            LinearGradient(colors: [.mint, .purple], startPoint: .leading, endPoint: .trailing)
                .mask(Text("Sovereign Verification").font(.headline))

            Text("""
            Every mint binds amount • method • pulse • (IAP tx) into a zk-verifiable Sigil hash.
            Math is the oracle. Proof is the authority. No screenshots — only truth.
            """)
            .font(.subheadline)
            .opacity(0.95)

            RoundedRectangle(cornerRadius: 12)
                .stroke(.mint.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [6,6]))
                .frame(height: 1)
                .overlay(
                    Text("Proof of Breath™")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .background(Color.black)
                        .offset(y: -10),
                    alignment: .topLeading
                )
                .opacity(0.9)
        }
        .padding(14)
        .atlanteanGlass(radius: 16)
    }

    // MARK: Mint Result ---------------------------------------------------------

    @ViewBuilder
    private func mintResult(_ r: MintResp) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "seal.checkmark")
                    .foregroundStyle(.mint)
                Text("Mint complete")
                    .font(.headline)
                    .foregroundStyle(.mint)
                Spacer()
                if let c = clock {
                    Text("Pulse \(c.nowPulse)")
                        .font(.caption.monospacedDigit())
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.white.opacity(0.06), in: Capsule())
                        .accessibilityLabel("Pulse \(c.nowPulse)")
                }
            }

            Group {
                LabeledRow(k: "Sigil ID", v: r.sigilId)
                LabeledRow(k: "Glyph Hash", v: r.glyphHash)
            }

            if let url = r.receiptUrl, let u = URL(string: url) {
                Link("View receipt →", destination: u)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.top, 2)
            }
        }
        .padding(16)
        .background(
            LinearGradient(colors: [Color.white.opacity(0.08), Color.white.opacity(0.04)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.mint.opacity(0.35), lineWidth: 1))
        .padding(.top, 6)
    }

    private struct LabeledRow: View {
        var k: String; var v: String
        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(k):").bold()
                Text(v).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button {
                    UIPasteboard.general.string = v
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 13, weight: .bold))
                        .padding(6)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy \(k)")
            }
            .font(.callout)
        }
    }

    // MARK: Helpers -------------------------------------------------------------

    private var selectedAmount: Double {
        guard let s = selected else { return 0 }
        let digits = s.displayPrice.filter("0123456789.,".contains)
        return Double(digits.replacingOccurrences(of: ",", with: "")) ?? 0
    }

    private var selectedAmountOrFallback: Double {
        let v = selectedAmount
        return v > 0 ? v : 1
    }

    private func close() {
        isOpen = false
        error = nil
        minted = nil
        selected = nil
    }

    private func onPurchase() async {
        guard let product = selected, !busy else { return }
        busy = true; error = nil
        defer { busy = false }

        do {
            let result = try await iap.purchase(product, userPhiKey: userPhiKey)
            let c = try await API.fetchClock()

            let req = MintReq(
                amountUsd: selectedAmount,
                method: "iap",
                iapProductId: result.productID,
                iapTransactionId: result.transactionID,
                appAccountToken: iap.accountToken(for: userPhiKey),
                nowPulse: c.nowPulse
            )
            let r = try await API.mintSigil(req)
            guard r.ok else { throw NetError.generic("Mint failed.") }
            self.clock = c
            withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
                self.minted = r
            }
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}

// MARK: - Preview --------------------------------------------------------------

struct InvestorSigilModalView_Previews: PreviewProvider {
    struct Host: View {
        @State var open = true
        var body: some View {
            InvestorSigilModalView(isOpen: $open, userPhiKey: "demo-user-key")
        }
    }
    static var previews: some View {
        Host()
            .preferredColorScheme(.dark)
    }
}
