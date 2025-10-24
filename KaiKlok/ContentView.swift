//  ContentView.swift
//  KaiKlok
//
//  Home shell (no GitHub CTA)
//  • Eternal Klock panel using KaiDialView
//  • Bottom dock: FOUR remarkable neon buttons (Generator • Investor • Kalendar • Wallet)
//  • Living Atlantean background synced to φ breath (5.236s)
//

import SwiftUI
import UIKit
import ActivityKit

// MARK: - ContentView

struct ContentView: View {
    @StateObject private var engine = KairosEngine.shared

    // Modals
    @State private var showGenerator = false
    @State private var showWeekModal = false
    @State private var showEternalKlock = false   // present EternalKlockView on dial tap
    @State private var showInvestor = false       // Investor (IAP) modal
    @State private var showAsterionChat = false   // Atlantean Chat (Asterion)
    @State private var showMaturahSanctum = false // (kept for code parity; not used by orb)
    @State private var showHarmonicPlayer = false // opens OracleChatView (Maturah)

    // NEW: Sovereign Wallet
    @State private var showWallet = false

    // Live Activity refresh timer (avoid duplicates on reappear)
    @State private var liveTimer: Timer?

    // Breath (should be ~5.236s)
    private var breath: Double { KairosConstants.breathSec }

    var body: some View {
        ZStack {
            // Dynamic living background
            AtlanteanBackground(breath: breath)

            // Foreground layout sized like the working example
            GeometryReader { geo in
                let side   = Swift.min(geo.size.width, geo.size.height)
                let dialSz = Swift.min(side * 0.92, 820)
                let panelW = dialSz + 120

                ZStack {
                    HeroStageDomes(breath: breath)

                    EternalKlockPanel(breath: breath, width: panelW) {
                        VStack(spacing: 12) {
                            // Dial
                            ZStack {
                                KaiDialView(moment: engine.moment)
                                    .frame(width: dialSz, height: dialSz)
                                    .accessibilityHidden(true)

                                // Invisible button overlay → opens EternalKlockView
                                Button { showEternalKlock = true } label: { Color.clear }
                                    .accessibilityLabel("Open Eternal Klock")
                                    .accessibilityAddTraits(.isButton)
                            }
                            // Controls live in a bottom safe-area inset
                        }
                        .padding(.vertical, 8)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .contentShape(Rectangle())

                // ==== Asterion + Maturah Orbs — aligned under the dial, clamped above dock ====
                GeometryReader { inner in
                    let W = inner.size.width
                    let H = inner.size.height
                    let centerX = W / 2
                    let centerY = H / 2

                    // Dial geometry
                    let dialBottomY = centerY + dialSz / 2

                    // Size: divine baseline, then 50% smaller (same baseline as Asterion)
                    let phi: CGFloat = 1.61803398875
                    let baseOrb = clamp(72, (side / (phi * phi)) * 0.92, 116)
                    let orb = baseOrb * 0.5

                    // Vertical layout guards
                    let gapBelowDial: CGFloat = 16
                    let dockApprox: CGFloat = 104   // taller now (remarkable dock)
                    let gapAboveDock: CGFloat = 14
                    let targetY = dialBottomY + gapBelowDial
                    let maxY = H - (dockApprox + gapAboveDock)
                    let finalY = min(targetY, maxY)

                    // Horizontal stack: Asterion (left), Maturah (right)
                    HStack(spacing: 18) {
                        PhiChatOrbButton(size: orb, breath: breath) {
                            showAsterionChat = true
                            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        }
                        .accessibilityLabel("Open Asterion Chat")
                        .accessibilityHint("Ask about anything...")

                        // Maturah orb → opens OracleChatView EXACTLY like Asterion
                        MaturahOrbButton(size: orb, breath: breath) {
                            showHarmonicPlayer = true
                            let h = UIImpactFeedbackGenerator(style: .heavy)
                            h.impactOccurred(intensity: 0.9)
                        }
                        .accessibilityLabel("Open Oracle Chat")
                        .accessibilityHint("Ask the Oracle and explore harmonics…")
                    }
                    .position(x: centerX, y: finalY)
                }
                .ignoresSafeArea()
                .zIndex(3) // sits above panel but below top overlays
            }
        }
        .animation(.default.speed(1), value: engine.moment.pulse)

        // ==== Price Card pinned to the top ====
        .overlay(alignment: .top) {
            HStack {
                Spacer(minLength: 0)
                HomePriceChartCard(
                    ctaAmountUsd: 250,
                    title: "Value Index",
                    chartHeight: 120,
                    onExpandChange: { _ in }
                )
                .padding(.top, 10)
                .padding(.horizontal, 16)
                .frame(maxWidth: 740)
                Spacer(minLength: 0)
            }
            .padding(.top, 6)
            .zIndex(4)
        }

        // ==== Always-visible bottom dock (FOUR neon image-only buttons) ====
        .safeAreaInset(edge: .bottom) {
            NeonBottomDock(
                breath: breath,
                generatorTap: { showGenerator = true },
                investorTap:  { showInvestor  = true },
                kalendarTap:  { showWeekModal = true },
                walletTap:    { showWallet    = true }
            )
        }

        // MARK: Modals

        // Sigil generator — FULL SCREEN (like Kalendar)
        .fullScreenCover(isPresented: $showGenerator) {
            ZStack {
                LinearGradient(colors: [Color.black, kaiColor("#02040a")],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                KaiSigilModalView()
                    .tint(.white)
                    .preferredColorScheme(.dark)
            }
        }

        // Investor (Kairos Kurrency / IAP) — FULL SCREEN (like Kalendar)
        .fullScreenCover(isPresented: $showInvestor) {
            ZStack {
                LinearGradient(colors: [Color.black, kaiColor("#02040a")],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                InvestorSigilModalView(
                    isOpen: $showInvestor,
                    userPhiKey: "0xKAI_REX_PHIKEY" // TODO: inject real user ΦKey
                )
                .preferredColorScheme(.dark)
            }
            .safeAreaInset(edge: .top) {
                HStack {
                    Spacer()
                    CloseHaloButton(breath: breath) {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        showInvestor = false
                    }
                    .padding(.trailing, 14)
                }
                .padding(.top, 6)
            }
        }

        // Asterion Chat (full-screen, immersive) + CLOSE BUTTON
        .fullScreenCover(isPresented: $showAsterionChat) {
            ZStack {
                LinearGradient(colors: [Color.black, kaiColor("#02040a")],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                InvestorChatView(
                    amount: 1597,
                    method: .card,
                    entitlement: EntPreview(amount: 1597, sigilCount: 1, nextTier: 2584, pctToNext: 0.62, childGlyphs: nil),
                    apiEndpoint: URL(string: "https://pay.kaiklok.com/api/chat")!,
                    breath: KairosConstants.breathSec,
                    onOpenPayment: { showInvestor = true },
                    onChooseMethod: { _ in },
                    onSetAmount: { _ in }
                )
                .preferredColorScheme(ColorScheme.dark)
            }
            // Gorgeous neon close button, safe-area aware
            .safeAreaInset(edge: .top) {
                HStack {
                    Spacer()
                    CloseHaloButton(breath: breath) {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        showAsterionChat = false
                    }
                    .padding(.trailing, 14)
                }
                .padding(.top, 6)
            }
        }

        // Week Kalendar (full-screen)
        .fullScreenCover(isPresented: $showWeekModal) {
            WeekKalendarModal { showWeekModal = false }
                .ignoresSafeArea()
        }

        // Eternal Klock (full-screen, immersive)
        .fullScreenCover(isPresented: $showEternalKlock) {
            ZStack {
                LinearGradient(
                    colors: [Color.black, kaiColor("#02040a")],
                    startPoint: .top, endPoint: .bottom
                ).ignoresSafeArea()

                EternalKlockView()
                    .tint(.white)
                    .preferredColorScheme(ColorScheme.dark)
            }
            .safeAreaInset(edge: .top) {
                HStack {
                    Spacer()
                    CloseHaloButton(breath: breath) {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        showEternalKlock = false
                    }
                    .padding(.trailing, 14)
                }
                .padding(.top, 6)
            }
        }

        // Oracle Chat / MATURAH — OPEN EXACTLY LIKE ASTERION (same shell & presentation) + CLOSE BUTTON
        .fullScreenCover(isPresented: $showHarmonicPlayer) {
            ZStack {
                LinearGradient(colors: [Color.black, kaiColor("#02040a")],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                OracleChatView()
                    .tint(.white)
                    .preferredColorScheme(ColorScheme.dark)
            }
            // Same close control as Asterion
            .safeAreaInset(edge: .top) {
                HStack {
                    Spacer()
                    CloseHaloButton(breath: breath) {
                        let h = UIImpactFeedbackGenerator(style: .soft)
                        h.impactOccurred()
                        showHarmonicPlayer = false
                    }
                    .padding(.trailing, 14)
                }
                .padding(.top, 6)
            }
        }

        // (Kept, not wired by orb)
        .fullScreenCover(isPresented: $showMaturahSanctum) {
            MaturahSanctumView(onClose: { showMaturahSanctum = false })
                .preferredColorScheme(ColorScheme.dark)
        }

        // NEW: Sovereign Wallet — FULL SCREEN (like Kalendar)
        .fullScreenCover(isPresented: $showWallet) {
            ZStack {
                LinearGradient(colors: [Color.black, kaiColor("#02040a")],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                NavigationStack { SovereignWalletModal() }
                    .preferredColorScheme(ColorScheme.dark)
            }
            .safeAreaInset(edge: .top) {
                HStack {
                    Spacer()
                    CloseHaloButton(breath: breath) {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        showWallet = false
                    }
                    .padding(.trailing, 14)
                }
                .padding(.top, 6)
            }
        }

        // MARK: Live Activity Auto-Start and Refresh
        .onAppear {
            KairosLiveActivityEngine.start(for: "0xKAI_REX_PHIKEY") // TODO: inject real user PhiKey

            // Ensure only a single refresh timer is running
            if liveTimer == nil {
                liveTimer = Timer.scheduledTimer(withTimeInterval: 5.236, repeats: true) { _ in
                    KairosLiveActivityEngine.refreshLiveActivity()
                }
            }
        }
        .onDisappear {
            liveTimer?.invalidate()
            liveTimer = nil
        }
    }
}

// MARK: - Eternal Panel

private struct EternalKlockPanel<Content: View>: View {
    let breath: Double
    let width: CGFloat
    @ViewBuilder var content: () -> Content
    @State private var spin = false

    var body: some View {
        ZStack {
            let card = RoundedRectangle(cornerRadius: 20, style: .continuous)

            // Base card
            card
                .fill(panelLinear())
                .overlay(card.stroke(kaiColor("#00ffff").opacity(0.22), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.45), radius: 80, y: 24)
                .modifier(BreathingBorder(breath: breath))

            // Radial aura (::before)
            card
                .fill(panelRadialAura())
                .blur(radius: 24)
                .allowsHitTesting(false)
                .modifier(BreatheOpacity(breath: breath))

            // Conic sweep (::after)
            card
                .fill(panelConicSweep())
                .blur(radius: 18)
                .allowsHitTesting(false)
                .rotationEffect(.degrees(spin ? 360 : 0))
                .onAppear {
                    withAnimation(.linear(duration: 44).repeatForever(autoreverses: false)) {
                        spin = true
                    }
                }

            VStack(spacing: 0) { content() }
                .padding(.vertical, 8)
        }
        .frame(width: width)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // Split gradients out (keeps type-checker happy)
    private func panelLinear() -> LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 8/255,  green: 22/255, blue: 32/255, opacity: 0.92),
                Color(red: 6/255,  green: 12/255, blue: 18/255, opacity: 0.88)
            ],
            startPoint: .top, endPoint: .bottom
        )
    }
    private func panelRadialAura() -> RadialGradient {
        RadialGradient(colors: [kaiColor("#00ffff").opacity(0.18), .clear],
                       center: .center, startRadius: 0, endRadius: 500)
    }
    private func panelConicSweep() -> AngularGradient {
        AngularGradient(
            gradient: Gradient(stops: [
                .init(color: kaiColor("#00ffff").opacity(0.16), location: 0.08),
                .init(color: kaiColor("#7800ff").opacity(0.16), location: 0.18),
                .init(color: .clear,                           location: 0.32),
                .init(color: Color.white.opacity(0.06),        location: 0.50),
                .init(color: .clear,                           location: 1.00),
            ]),
            center: .center, startAngle: .degrees(220), endAngle: .degrees(580)
        )
    }
}

// MARK: - Neon Bottom Dock (FOUR buttons, phi-breathing, IMAGE-ONLY)

private struct NeonBottomDock: View {
    let breath: Double
    let generatorTap: () -> Void
    let investorTap:  () -> Void
    let kalendarTap:  () -> Void
    let walletTap:    () -> Void

    var body: some View {
        HStack(spacing: 14) {
            DockPill(
                title: "Sigil",
                glyphName: "sigil", fallbackSF: "seal",
                aura: [kaiColor("#37FFE4"), kaiColor("#A78BFA")],
                stroke: kaiColor("#37FFE4"),
                breath: breath,
                action: generatorTap
            )
            DockPill(
                title: "Offer",
                glyphName: "offer", fallbackSF: "cart.badge.plus",
                aura: [kaiColor("#FFD166"), kaiColor("#FF6D00")],
                stroke: kaiColor("#FFD166"),
                breath: breath,
                action: investorTap
            )
            DockPill(
                title: "Kalendar",
                glyphName: "kalendar", fallbackSF: "calendar",
                aura: [kaiColor("#00E5FF"), kaiColor("#7A00FF")],
                stroke: kaiColor("#00E5FF"),
                breath: breath,
                action: kalendarTap
            )
            DockPill(
                title: "Temple",
                glyphName: "temple",
                fallbackSF: "building.columns",
                aura: [kaiColor("#00FFCC"), kaiColor("#00A6FF")],
                stroke: kaiColor("#00FFCC"),
                breath: breath,
                action: walletTap
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(kaiColor("#00ffff").opacity(0.20), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.35), radius: 18, y: 10)
        .shadow(color: kaiColor("#00faff").opacity(0.25), radius: 14)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 10)
        .padding(.top, 2)
        .background(Color.black.opacity(0.0001))
    }
}

private struct DockPill: View {
    let title: String
    let glyphName: String     // Asset name (svg/pdf in Assets)
    let fallbackSF: String    // Fallback SF Symbol
    let aura: [Color]
    let stroke: Color
    let breath: Double
    let action: () -> Void

    @State private var on = false
    @State private var tilt = false

    var body: some View {
        Button(action: {
            let h = UIImpactFeedbackGenerator(style: .soft)
            h.impactOccurred()
            action()
        }) {
            ZStack {
                // Breathing neon aura
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [aura[0].opacity(on ? 0.26 : 0.14),
                                     aura[1].opacity(on ? 0.14 : 0.06),
                                     .clear],
                            center: .center, startRadius: 0, endRadius: 140
                        )
                    )
                    .blur(radius: 16)
                    .scaleEffect(on ? 1.06 : 0.96)
                    .allowsHitTesting(false)
                    .padding(-12)

                // Frosted pill
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(
                        colors: [kaiColor("#0E1820"), kaiColor("#0A1218")],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(stroke.opacity(0.55), lineWidth: 1)
                    )
                    .shadow(color: stroke.opacity(0.35), radius: 16, y: 8)

                // IMAGE ONLY (no label)
                GlyphImage(name: glyphName, fallbackSF: fallbackSF)
                    .frame(width: 34, height: 34)
                    .shadow(color: stroke.opacity(0.8), radius: 6)
                    .accessibilityHidden(true)
            }
            .frame(width: 82, height: 74)
            .rotation3DEffect(.degrees(tilt ? 6 : -6), axis: (x: 0, y: 1, z: 0))
            .animation(.easeInOut(duration: 4.236).repeatForever(autoreverses: true), value: tilt)
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.easeInOut(duration: breath).repeatForever(autoreverses: true)) {
                on = true
            }
            withAnimation(.easeInOut(duration: 4.236).delay(Double.random(in: 0...1)).repeatForever(autoreverses: true)) {
                tilt = true
            }
        }
        // Keep the name for accessibility (no visible label)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
    }
}

// MARK: - Hero Stage Domes

private struct HeroStageDomes: View {
    let breath: Double
    var body: some View {
        ZStack {
            let baseW = Swift.min(UIScreen.main.bounds.width, UIScreen.main.bounds.height) * 1.2
            let baseH = baseW

            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [kaiColor("#00ffff").opacity(0.18),
                                 kaiColor("#00a0ff").opacity(0.08),
                                 .clear],
                        center: .center, startRadius: 0, endRadius: 800
                    )
                )
                .frame(width: baseW, height: baseH)
                .blur(radius: 36)
                .modifier(Breathing(breath: breath))

            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [kaiColor("#be00ff").opacity(0.16), .clear],
                        center: .center, startRadius: 0, endRadius: 800
                    )
                )
                .frame(width: baseW, height: baseH)
                .blur(radius: 36)
                .modifier(BreatheOpacity(breath: breath))
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Living Atlantean Background (Canvas + TimelineView)

private struct AtlanteanBackground: View {
    let breath: Double

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [kaiColor("#05090f"), kaiColor("#0e1b22"), kaiColor("#0c2231")],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            TimelineView(.animation) { timeline in
                AtlanteanCanvas(time: timeline.date.timeIntervalSinceReferenceDate,
                                breath: breath)
            }
            .ignoresSafeArea()
        }
    }
}

private struct AtlanteanCanvas: View {
    let time: TimeInterval
    let breath: Double

    var body: some View {
        Canvas { ctx, size in
            let W = size.width
            let H = size.height
            let C = CGPoint(x: W/2, y: H/2)

            // φ-timed phases
            let phi   = max(0.001, breath)
            let t1    = time.truncatingRemainder(dividingBy: phi) / phi
            let t2    = time.truncatingRemainder(dividingBy: phi * 2) / (phi * 2)
            let wave  = sin(t1 * 2 * .pi) * 0.5 + 0.5
            let wave2 = sin(t2 * 2 * .pi + .pi/3) * 0.5 + 0.5

            // Blob centers
            let top   = CGPoint(x: C.x + CGFloat(sin(time/7) * 80),
                                y: H * 0.22 + CGFloat(cos(time/5) * 40))
            let left  = CGPoint(x: W * 0.22 + CGFloat(sin(time/9) * 60),
                                y: H * 0.36 + CGFloat(cos(time/6) * 30))
            let right = CGPoint(x: W * 0.78 + CGFloat(cos(time/8) * 60),
                                y: H * 0.34 + CGFloat(sin(time/6) * 40))

            // Aurora blobs
            paintBlob(ctx: &ctx, center: top,   baseR: max(W,H) * 0.55,
                      baseColor: kaiColor("#00ffff"), blur: 34, opacity: 0.95, phase: wave)

            paintBlob(ctx: &ctx, center: left,  baseR: max(W,H) * 0.45,
                      baseColor: kaiColor("#7000ff"), blur: 28, opacity: 0.85, phase: wave)

            paintBlob(ctx: &ctx, center: right, baseR: max(W,H) * 0.45,
                      baseColor: kaiColor("#00a0ff"), blur: 28, opacity: 0.85, phase: wave)

            // Plasma ring
            paintRing(ctx: &ctx, center: C, baseR: max(W, H) * 0.42, wave: wave)

            // Spiral sparks
            paintSparks(ctx: &ctx, center: C, span: min(W, H), wave: wave2, time: time)

            // Star mist
            paintStars(ctx: &ctx, size: size, wave: wave)
        }
    }
}

// MARK: - Canvas helpers

private func radialShading(color: Color,
                           center: CGPoint,
                           radius: CGFloat) -> GraphicsContext.Shading {
    let g = Gradient(stops: [
        .init(color: color.opacity(0.22), location: 0.0),
        .init(color: color.opacity(0.001), location: 1.0)
    ])
    return .radialGradient(g, center: center, startRadius: 0, endRadius: radius)
}

private func paintBlob(ctx: inout GraphicsContext,
                       center: CGPoint,
                       baseR: CGFloat,
                       baseColor: Color,
                       blur: CGFloat,
                       opacity: Double,
                       phase: Double)
{
    let r = baseR * CGFloat(0.85 + 0.30 * phase)
    let rect = CGRect(x: center.x - r, y: center.y - r, width: r*2, height: r*2)
    let path = Path(ellipseIn: rect)

    ctx.addFilter(.blur(radius: blur))
    ctx.opacity = opacity
    ctx.fill(path, with: radialShading(color: baseColor, center: center, radius: r))
    ctx.opacity = 1
}

private func paintRing(ctx: inout GraphicsContext,
                       center: CGPoint,
                       baseR: CGFloat,
                       wave: Double)
{
    let r = baseR * CGFloat(1.0 + 0.095 * wave)
    var ring = Path()
    ring.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r*2, height: r*2))
    ctx.addFilter(.blur(radius: 12))
    ctx.stroke(ring, with: .color(kaiColor("#00ffff").opacity(0.12)), lineWidth: 2)
}

private func paintSparks(ctx: inout GraphicsContext,
                         center: CGPoint,
                         span: CGFloat,
                         wave: Double,
                         time: TimeInterval)
{
    let sparks = 88
    let spin = time / 22
    ctx.addFilter(.blur(radius: 0))

    for i in 0..<sparks {
        let k = Double(i) / Double(sparks)
        let ang = k * 2 * Double.pi * 3 + spin
        let rr  = CGFloat((0.18 + 0.58 * k) * Double(span)) * CGFloat(0.86 + 0.14 * wave)
        let x = center.x + rr * CGFloat(cos(ang))
        let y = center.y + rr * CGFloat(sin(ang))
        let dotR: CGFloat = 1.2 + CGFloat(k) * 1.6
        let rect = CGRect(x: x - dotR, y: y - dotR, width: dotR*2, height: dotR*2)
        let color = Color(hue: k, saturation: 0.95, brightness: 1.0, opacity: 0.22 + 0.5 * (1 - k))
        ctx.fill(Path(ellipseIn: rect), with: .color(color))
    }
}

private func paintStars(ctx: inout GraphicsContext,
                        size: CGSize,
                        wave: Double)
{
    let count = 90
    let W = size.width, H = size.height

    @inline(__always)
    func hash(_ i: Int) -> UInt64 {
        let K0: UInt64 = 0x9E3779B97F4A7C15
        let K1: UInt64 = 0xBF58476D1CE4E5B9
        let K2: UInt64 = 0x94D049BB133111EB
        var x = UInt64(i) &+ K0
        x = (x ^ (x >> 30)) &* K1
        x = (x ^ (x >> 27)) &* K2
        x = x ^ (x >> 31)
        return x
    }

    for i in 0..<count {
        let h  = hash(i)
        let lo = h & 0xFFFF_FFFF
        let hi = (h >> 32) & 0xFFFF_FFFF

        let xf = Double(lo) / Double(UInt32.max)
        let yf = Double(hi) / Double(UInt32.max)

        let x = CGFloat(xf) * W
        let y = CGFloat(yf) * H
        let r: CGFloat = 0.4 + CGFloat(lo & 0xFF) / 255.0 * 0.7
        let alphaBase = 0.05 + 0.12 * (1 - CGFloat(i) / CGFloat(count))
        let a = alphaBase * CGFloat(0.75 + 0.25 * wave)
        let rect = CGRect(x: x - r, y: y - r, width: r*2, height: r*2)
        ctx.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(Double(a))))
    }
}

// MARK: - Visual Modifiers

private struct Breathing: ViewModifier {
    let breath: Double
    var reverse: Bool = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(1.0)
            .opacity(0.96)
            .modifier(AnimKey(breath: breath, reverse: reverse) { phase in
                content
                    .scaleEffect(1.0 + 0.035 * phase)
                    .opacity(0.96 + 0.04 * phase)
            })
    }

    private struct AnimKey<T: View>: ViewModifier {
        let breath: Double
        let reverse: Bool
        let build: (CGFloat) -> T
        @State private var phase: CGFloat = 0
        func body(content: Content) -> some View {
            build(phase)
                .onAppear {
                    withAnimation(.easeInOut(duration: breath).repeatForever(autoreverses: true)) {
                        phase = reverse ? -1 : 1
                    }
                }
        }
    }
}

/// FIXED: Correct ViewModifier signature (Content, not `some View`)
private struct BreatheOpacity: ViewModifier {
    let breath: Double
    @State private var on = false
    func body(content: Content) -> some View {
        content
            .opacity(on ? 1.0 : 0.75)
            .onAppear {
                withAnimation(.easeInOut(duration: breath).repeatForever(autoreverses: true)) {
                    on.toggle()
                }
            }
    }
}

/// FIXED: Correct ViewModifier signature (Content, not `some View`)
private struct BreathingBorder: ViewModifier {
    let breath: Double
    @State private var on = false
    func body(content: Content) -> some View {
        content
            .shadow(color: kaiColor("#00ffff").opacity(on ? 0.35 : 0.25), radius: on ? 44 : 32)
            .onAppear {
                withAnimation(.easeInOut(duration: breath).repeatForever(autoreverses: true)) {
                    on.toggle()
                }
            }
    }
}

/// FIXED: Correct ViewModifier signature (Content, not `some View`)
private struct ParallaxDrift: ViewModifier {
    let duration: Double
    @State private var go = false
    func body(content: Content) -> some View {
        content
            .offset(x: go ? 20 : -20, y: go ? 10 : 0)
            .scaleEffect(go ? 1.02 : 1.0)
            .animation(.linear(duration: duration).repeatForever(autoreverses: true), value: go)
            .onAppear { go = true }
    }
}

// MARK: - Clamp & viewport helpers

fileprivate func clamp(_ minV: CGFloat, _ mid: CGFloat, _ maxV: CGFloat) -> CGFloat {
    Swift.min(Swift.max(minV, mid), maxV)
}
fileprivate extension CGFloat {
    static func vmin(_ x: CGFloat) -> CGFloat {
        let w = UIScreen.main.bounds.width
        let h = UIScreen.main.bounds.height
        return Swift.min(w, h) * (x / 100.0)
    }
    static func vw(_ x: CGFloat) -> CGFloat {
        UIScreen.main.bounds.width * (x / 100.0)
    }
}

// MARK: - Small helpers

/// Create a Color from hex strings like "#RRGGBB" or "#RRGGBBAA".
private func kaiColor(_ hex: String, alpha: Double = 1.0) -> Color {
    var hexString = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    if hexString.hasPrefix("#") { hexString.removeFirst() }

    var r: UInt64 = 0, g: UInt64 = 0, b: UInt64 = 0, a: UInt64 = 255
    let scanner = Scanner(string: hexString)

    if hexString.count == 6, scanner.scanHexInt64(&r) {
        g = (r & 0x00FF00) >> 8
        b = (r & 0x0000FF)
        r =  r >> 16
    } else if hexString.count == 8, scanner.scanHexInt64(&r) {
        a =  r & 0x000000FF
        b = (r & 0x0000FF00) >> 8
        g = (r & 0x00FF0000) >> 16
        r =  r >> 24
    } else {
        return Color.white.opacity(alpha)
    }

    let fa = Swift.min(1.0, Swift.max(0.0, alpha * Double(a) / 255.0))
    return Color(red: Double(r) / 255.0,
                 green: Double(g) / 255.0,
                 blue: Double(b) / 255.0,
                 opacity: fa)
}

/// Day color mapping (Solhara → Kaelith)
private func dayColorForIndex(_ i: Int) -> Color {
    switch (i % 6 + 6) % 6 {
    case 0: return kaiColor("#ff1559")
    case 1: return kaiColor("#ff6d00")
    case 2: return kaiColor("#ffd900")
    case 3: return kaiColor("#00ff66")
    case 4: return kaiColor("#05e6ff")
    default: return kaiColor("#c300ff")
    }
}

// MARK: - Generator wrapper

private struct SigilGeneratorSheet: View {
    var body: some View {
        NavigationStack { KaiSigilModalView() }
            .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - Asterion Orb (Floating Chat Button) — uses Assets/asterion

private struct PhiChatOrbButton: View {
    let size: CGFloat
    let breath: Double
    var action: () -> Void
    @State private var spin = false
    @State private var on = false

    var body: some View {
        Button(action: action) {
            ZStack {
                // Glowing aura
                Circle()
                    .fill(
                        RadialGradient(colors: [kaiColor("#37ffe4").opacity(0.22),
                                                kaiColor("#a78bfa").opacity(0.10),
                                                .clear],
                                       center: .center, startRadius: 0, endRadius: size * 0.9)
                    )
                    .blur(radius: 12)
                    .scaleEffect(on ? 1.06 : 0.98)

                // Core orb
                Circle()
                    .fill(LinearGradient(colors: [kaiColor("#0e1b22"), kaiColor("#10242b")],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(
                        Circle().stroke(kaiColor("#37ffe4").opacity(0.55), lineWidth: 1.0)
                    )
                    .shadow(color: kaiColor("#37ffe4").opacity(0.35), radius: 16, y: 8)

                // Slow conic halo
                Circle()
                    .trim(from: 0.08, to: 0.58)
                    .stroke(AngularGradient(gradient: Gradient(colors: [
                        kaiColor("#37ffe4").opacity(0.7),
                        kaiColor("#a78bfa").opacity(0.5),
                        .clear
                    ]), center: .center), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .blur(radius: 0.5)

                // Asterion glyph from Assets
                GlyphImage(name: "asterion", fallbackSF: "sparkles")
                    .frame(width: size * 0.44, height: size * 0.44)
                    .shadow(color: kaiColor("#37ffe4").opacity(0.7), radius: 10)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.linear(duration: 44).repeatForever(autoreverses: false)) { spin = true }
            withAnimation(.easeInOut(duration: breath).repeatForever(autoreverses: true)) { on = true }
        }
    }
}

// MARK: - MATURAH Orb — uses Assets/maturah, opens Oracle Chat

private struct MaturahOrbButton: View {
    let size: CGFloat
    let breath: Double
    var action: () -> Void

    @State private var spinOuter = false
    @State private var spinInner = false
    @State private var pulse = false
    @State private var orbit = false

    var body: some View {
        Button(action: action) {
            ZStack {
                // 1) Etheric neon bloom
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                kaiColor("#00fff0").opacity(pulse ? 0.26 : 0.16),
                                kaiColor("#00a6ff").opacity(pulse ? 0.14 : 0.08),
                                kaiColor("#7a00ff").opacity(pulse ? 0.10 : 0.05),
                                .clear
                            ],
                            center: .center, startRadius: 0, endRadius: size * 1.05
                        )
                    )
                    .blur(radius: 14)
                    .scaleEffect(pulse ? 1.06 : 0.96)

                // 2) Frosted orb core
                Circle()
                    .fill(LinearGradient(colors: [kaiColor("#0d1820"), kaiColor("#0a1218")],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(Circle().stroke(kaiColor("#00ffff").opacity(0.65), lineWidth: 1.2))
                    .shadow(color: kaiColor("#00ffff").opacity(0.38), radius: 16, y: 8)

                // 3) Contra-rotating halo rings
                Circle()
                    .trim(from: 0.06, to: 0.64)
                    .stroke(AngularGradient(gradient: Gradient(colors: [
                        kaiColor("#00ffff").opacity(0.85),
                        kaiColor("#00a6ff").opacity(0.65),
                        kaiColor("#7a00ff").opacity(0.75),
                        kaiColor("#00ffff").opacity(0.85)
                    ]), center: .center), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .rotationEffect(.degrees(spinOuter ? 360 : 0))
                    .blur(radius: 0.4)

                Circle()
                    .trim(from: 0.50, to: 0.96)
                    .stroke(AngularGradient(gradient: Gradient(colors: [
                        kaiColor("#00ffff").opacity(0.65),
                        kaiColor("#7a00ff").opacity(0.65),
                        kaiColor("#00a6ff").opacity(0.55),
                        kaiColor("#00ffff").opacity(0.65)
                    ]), center: .center), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    .rotationEffect(.degrees(spinInner ? -360 : 0))
                    .opacity(0.95)

                // 4) Maturah glyph from Assets
                GlyphImage(name: "maturahbg", fallbackSF: "waveform")
                    .frame(width: size * 0.44, height: size * 0.44)
                    .shadow(color: kaiColor("#00ffff").opacity(0.8), radius: 12)
            }
            .frame(width: size, height: size)
            .background(.ultraThinMaterial.opacity(0.0001))
            .clipShape(Circle())
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.linear(duration: 32).repeatForever(autoreverses: false)) { spinOuter = true }
            withAnimation(.linear(duration: 26).repeatForever(autoreverses: false)) { spinInner = true }
            withAnimation(.easeInOut(duration: breath).repeatForever(autoreverses: true)) { pulse = true }
            withAnimation(.linear(duration: 9).repeatForever(autoreverses: false)) { orbit = true }
        }
    }
}

// MARK: - Regular Polygon / Star Shapes

private struct RegularPolygon: Shape {
    var sides: Int
    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard sides >= 3 else { return path }
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let step = 2 * Double.pi / Double(sides)
        for i in 0..<sides {
            let a = Double(i) * step - Double.pi/2
            let p = CGPoint(x: c.x + CGFloat(cos(a)) * r, y: c.y + CGFloat(sin(a)) * r)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }
}

private struct StarPolygon: Shape {
    let points: Int
    let step: Int
    func path(in rect: CGRect) -> Path {
        guard points >= 3, step >= 1 else { return Path() }
        let r = min(rect.width, rect.height) / 2
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var idx = 0
        var used = Set<Int>()
        var path = Path()
        func vertex(_ i: Int) -> CGPoint {
            let angle = (Double(i) / Double(points)) * 2 * Double.pi - Double.pi/2
            return CGPoint(x: c.x + CGFloat(cos(angle)) * r, y: c.y + CGFloat(sin(angle)) * r)
        }
        path.move(to: vertex(0))
        while !used.contains(idx) {
            used.insert(idx)
            idx = (idx + step) % points
            path.addLine(to: vertex(idx))
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Maturah Sanctum View (kept for parity)

private struct MaturahSanctumView: View {
    var onClose: () -> Void
    @State private var spin = false
    @State private var breathe = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [kaiColor("#0a0604"), kaiColor("#1a0e07")],
                           startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()

            // Solar mandala
            ZStack {
                ForEach(0..<7, id: \.self) { i in
                    Circle()
                        .stroke(kaiColor("#ffd166").opacity(0.14), lineWidth: 1.2)
                        .frame(width: CGFloat(160 + i*60), height: CGFloat(160 + i*60))
                        .blur(radius: 0.6)
                }
                StarPolygon(points: 12, step: 5)
                    .stroke(AngularGradient(gradient: Gradient(colors: [
                        kaiColor("#ffd166"), kaiColor("#ff7b00"), kaiColor("#ff006e"), kaiColor("#ffd166")
                    ]), center: .center),
                    style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .frame(width: 420, height: 420)
                    .shadow(color: kaiColor("#ffd166").opacity(0.45), radius: 20)

                Text("MATURAH")
                    .font(.system(size: 46, weight: .black, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [kaiColor("#fff2c6"), kaiColor("#ffd166"), kaiColor("#ff7b00")],
                                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: kaiColor("#ffd166").opacity(0.6), radius: 14)
                    .scaleEffect(breathe ? 1.03 : 0.97)
            }
            .animation(.linear(duration: 56).repeatForever(autoreverses: false), value: spin)
            .animation(.easeInOut(duration: 5.236).repeatForever(autoreverses: true), value: breathe)
            .onAppear { spin = true; breathe = true }

            VStack {
                Spacer()
                Button {
                    onClose()
                } label: {
                    Label("Return", systemImage: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().stroke(kaiColor("#ffd166").opacity(0.35), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 24)
            }
        }
    }
}

// MARK: - GlyphImage (asset-or-SF fallback)

private struct GlyphImage: View {
    let name: String
    let fallbackSF: String

    var body: some View {
        if let ui = UIImage(named: name) {
            Image(uiImage: ui)
                .resizable()
                .scaledToFit()
                .accessibilityHidden(true)
        } else {
            Image(systemName: fallbackSF)
                .resizable()
                .scaledToFit()
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Close Button (gorgeous neon halo)

private struct CloseHaloButton: View {
    let breath: Double
    let action: () -> Void

    @State private var pulse = false
    @State private var tilt = false

    var body: some View {
        Button(action: {
            action()
        }) {
            ZStack {
                // Neon aura
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                kaiColor("#00ffff").opacity(pulse ? 0.32 : 0.18),
                                kaiColor("#7a00ff").opacity(pulse ? 0.16 : 0.08),
                                .clear
                            ],
                            center: .center, startRadius: 0, endRadius: 46
                        )
                    )
                    .blur(radius: 12)
                    .scaleEffect(pulse ? 1.06 : 0.96)

                // Frosted core
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [kaiColor("#00ffff").opacity(0.85),
                                             kaiColor("#7a00ff").opacity(0.65)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.2
                            )
                    )
                    .shadow(color: kaiColor("#00ffff").opacity(0.35), radius: 12, y: 8)
                    .rotation3DEffect(.degrees(tilt ? 6 : -6), axis: (x: 0, y: 1, z: 0))

                // Glyph
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    .accessibilityHidden(true)
            }
            .frame(width: 54, height: 54)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
        .accessibilityAddTraits(.isButton)
        .onAppear {
            withAnimation(.easeInOut(duration: breath).repeatForever(autoreverses: true)) { pulse = true }
            withAnimation(.easeInOut(duration: 4.236).repeatForever(autoreverses: true)) { tilt = true }
        }
    }
}
