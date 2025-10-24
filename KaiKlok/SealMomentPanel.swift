//
//  SealMomentPanel.swift
//  KaiKlok
//
//  Created by BJ Klock on 9/18/25.
//  Styled by: “the Atlantean priest-king dev”
//

import SwiftUI
import UIKit

// MARK: - Tokens (Atlantean φ-breath + palette)

private enum SealUI {
    // Rhythm
    static let pulse: TimeInterval = 5.236 // φ breath (3 + √5)
    // Radii / layout
    static let corner: CGFloat = 22
    static let haloRadius: CGFloat = 160

    // Color system mapped from your CSS tokens
    static let inkBG  = Color(red: 0.02, green: 0.04, blue: 0.05)        // #040708-ish
    static let glass  = Color.white.opacity(0.06)                         // --sp-glass
    static let border = Color.white.opacity(0.08)                         // --sp-border
    static let ring   = Color(red: 55/255, green: 230/255, blue: 212/255).opacity(0.45) // --sp-ring
    static let text   = Color(red: 0.91, green: 0.98, blue: 0.97)         // --sp-text
    static let dim    = Color(red: 0.68, green: 0.91, blue: 0.87)         // --sp-dim
    static let cyan   = Color(hex: 0x37E6D4)                              // --c-cyan
    static let cyan2  = Color(hex: 0x5CE1FF)                              // --c-cyan-2
    static let mint   = Color(hex: 0x57F0C7)                              // --c-mint
    static let vio    = Color(hex: 0xA78BFA)                              // --c-vio
    static let rose   = Color(hex: 0xFF6B6B)                              // --c-rose
    static let neon   = Color(red: 0.31, green: 0.93, blue: 0.94)

    // Aurora backdrop (from CSS auroraTop/Bottom vibe)
    static let auraTop    = Color(red: 0.07, green: 0.51, blue: 0.63)
    static let auraBottom = Color(red: 0.02, green: 0.09, blue: 0.13)
}

// MARK: - Panel

struct SealMomentPanel: View {
    let hash: String
    let url: URL
    let onClose: () -> Void
    /// Optional ZIP action (kept nil by default, hook up later)
    let onDownloadZip: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var toast: String = ""
    @State private var appear: Bool = false
    @State private var pulsePhase: Double = 0    // 0..1 over φ cycle
    @State private var taskCancelled = false

    var body: some View {
        ZStack {
            // Atlantean veil (breathing gradient + stars)
            AtlanteanBackdrop(phase: pulsePhase)
                .ignoresSafeArea()

            // Breathing halo behind glass card
            HaloRings(phase: pulsePhase)
                .frame(width: SealUI.haloRadius * 2.2, height: SealUI.haloRadius * 2.2)
                .blur(radius: 22)
                .opacity(0.75)
                .allowsHitTesting(false)

            // Glass card
            VStack(spacing: 16) {
                header
                Divider().blendMode(.overlay).opacity(0.35)

                metaSection(
                    title: "Hash",
                    primary: hash.isEmpty ? "—" : String(hash.prefix(16)),
                    secondary: hash.isEmpty ? nil : "Full: \(hash)",
                    copyText: hash,
                    copyLabel: "Hash"
                )

                metaSection(
                    title: "URL",
                    primary: url.absoluteString,
                    secondary: nil,
                    copyText: url.absoluteString,
                    copyLabel: "Link",
                    trailing: AnyView(
                        Link(destination: url) {
                            AtlanteanIcon(systemName: "arrow.up.right.square")
                        }
                    )
                )

                actionRow

                Text("Use the link within the next 11 breaths to claim this kairos moment.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                    .accessibilityHint("Time-limited claim window of roughly 11 × 5.236 seconds.")
            }
            .padding(18)
            .frame(maxWidth: 560)
            .background(
                GlassCardBackground(phase: pulsePhase) // ⟵ split out to reduce type-check load
            )
            .overlay(alignment: .bottom) { toastView }
            .scaleEffect(appear ? 1.0 : 0.965)
            .opacity(appear ? 1.0 : 0.0)
            .animation(.spring(response: 0.50, dampingFraction: 0.90), value: appear)
            .padding(.horizontal, 18)
            .accessibilityElement(children: .contain)
        }
        .contentShape(Rectangle())     // block background taps
        .onTapGesture { /* inert */ }
        .accessibilityAddTraits(.isModal)
        .task {
            appear = true
            await startKaiPulse()
        }
        .onDisappear {
            taskCancelled = true
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Label {
                Text("Moment Sealed")
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(SealUI.text)
            } icon: {
                ZStack {
                    Circle().fill(SealUI.neon.opacity(0.20))
                    Image(systemName: "seal.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: SealUI.neon.opacity(0.8), radius: 6)
                }
                .frame(width: 28, height: 28)
                .scaleEffect(1.0 + (reduceMotion ? 0 : 0.015 * sin(pulsePhase * .pi * 2)))
                .animation(.linear(duration: 0.6), value: pulsePhase)
            }
            .labelStyle(.titleAndIcon)
            Spacer()

            Button(action: {
                haptic(.light)
                withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) { appear = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { onClose() }
            }) {
                AtlanteanIcon(systemName: "xmark")
            }
            .buttonStyle(GlassTactileButton())
            .accessibilityLabel("Close")
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Meta row builder

    @ViewBuilder
    private func metaSection(
        title: String,
        primary: String,
        secondary: String?,
        copyText: String,
        copyLabel: String,
        trailing: AnyView? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.footnote.weight(.heavy))
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(primary)
                    .font(.system(.callout, design: .monospaced).weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .textSelection(.enabled)

                Spacer(minLength: 8)

                Button {
                    copy(copyText, copyLabel)
                } label: {
                    AtlanteanIcon(systemName: "doc.on.doc")
                }
                .buttonStyle(GlassTactileButton())

                if let trailing = trailing { trailing }
            }

            if let secondary = secondary, !secondary.isEmpty {
                Text(secondary)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Actions

    private var actionRow: some View {
        HStack(spacing: 12) {
            ShareLink(item: url) {
                Label("Share", systemImage: "square.and.arrow.up")
                    .font(.headline)
            }
            .buttonStyle(AtlanteanProminent())
            .tint(.white)
            .accessibilityHint("Share the sealable claim link.")

            if let onZip = onDownloadZip {
                Button {
                    haptic(.medium)
                    onZip()
                } label: {
                    Label("Download ZIP", systemImage: "archivebox.fill")
                        .font(.headline)
                }
                .buttonStyle(AtlanteanSecondary())
                .tint(SealUI.cyan)
                .accessibilityHint("Download packaged assets for this seal.")
            }

            Spacer(minLength: 4)
        }
        .padding(.top, 6)
    }

    // MARK: Toast

    @ViewBuilder
    private var toastView: some View {
        if !toast.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill").imageScale(.small)
                Text(toast).font(.footnote.weight(.semibold))
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(.black.opacity(0.72), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 1))
            .padding(.bottom, 14)
            .transition(.asymmetric(insertion: .scale.combined(with: .opacity),
                                   removal: .opacity))
            .shadow(color: .black.opacity(0.5), radius: 10, y: 6)
            .accessibilityHidden(true)
        }
    }

    // MARK: Copy + Haptics

    private func copy(_ text: String, _ label: String) {
        UIPasteboard.general.string = text
        haptic(.success)
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) { toast = "\(label) copied" }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) {
            withAnimation(.easeOut(duration: 0.25)) { toast = "" }
        }
    }

    private func haptic(_ style: HapticStyle) {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        switch style {
        case .light:
            let gen = UIImpactFeedbackGenerator(style: .light); gen.impactOccurred()
        case .medium:
            let gen = UIImpactFeedbackGenerator(style: .medium); gen.impactOccurred()
        case .success:
            let gen = UINotificationFeedbackGenerator(); gen.notificationOccurred(.success)
        }
    }

    // MARK: φ-Pulse Driver

    private func startKaiPulse() async {
        if reduceMotion {
            // Static phase to honor Reduced Motion
            pulsePhase = 0
            return
        }
        let start = CACurrentMediaTime()
        taskCancelled = false
        while appear && !taskCancelled {
            let t = CACurrentMediaTime() - start
            let phase = (t.truncatingRemainder(dividingBy: SealUI.pulse)) / SealUI.pulse // 0..1
            await MainActor.run { self.pulsePhase = phase }
            try? await Task.sleep(nanoseconds: 16_000_000) // ~60fps
        }
    }

    private enum HapticStyle { case light, medium, success }
}

// MARK: - Subviews & Styles

/// Neon icon with consistent sizing and glow.
private struct AtlanteanIcon: View {
    let systemName: String
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.06))
                .overlay(Circle().stroke(.white.opacity(0.28), lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: SealUI.neon.opacity(0.9), radius: 4)
        }
        .frame(width: 30, height: 30)
        .contentShape(Circle())
        .accessibilityHidden(true)
    }
}

/// Primary glassy, prominent button.
private struct AtlanteanProminent: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [SealUI.cyan.opacity(0.36), SealUI.mint.opacity(0.28)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.35), lineWidth: 1))
            )
            .shadow(color: .black.opacity(0.45), radius: 12, y: 6)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Secondary outlined button with neon edge.
private struct AtlanteanSecondary: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                LinearGradient(colors: [SealUI.neon.opacity(0.8), .clear],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                lineWidth: 1.2
                            )
                    )
            )
            .shadow(color: .black.opacity(0.35), radius: 10, y: 5)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Circular glass button used for header icons.
private struct GlassTactileButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 34, height: 34)
            .background(
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(Circle().stroke(.white.opacity(0.30), lineWidth: 1))
            )
            .shadow(color: .black.opacity(0.45), radius: 12, y: 6)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.85), value: configuration.isPressed)
    }
}

// MARK: - Visual Effects

/// The heavy card background split out to keep the compiler happy.
private struct GlassCardBackground: View {
    let phase: Double
    var body: some View {
        let corner = SealUI.corner
        // Pre-build shapes & gradients so the type checker does less work
        let baseShape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        let borderGradient = LinearGradient(
            colors: [.white.opacity(0.40), .white.opacity(0.10)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        let neonEdge = LinearGradient(
            colors: [SealUI.neon.opacity(0.55), .clear],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )

        return baseShape
            .fill(.ultraThinMaterial)
            .background(SealUI.glass, in: baseShape)
            .overlay(
                baseShape.strokeBorder(borderGradient, lineWidth: 1)
            )
            .overlay(
                baseShape
                    .inset(by: 1.5)
                    .stroke(neonEdge, lineWidth: 1.2)
                    .opacity(0.7)
                    .blendMode(.screen)
            )
            .shadow(color: .black.opacity(0.6), radius: 30, x: 0, y: 16)
            .overlay(alignment: .topLeading) {
                LightSweep(phase: phase)
                    .clipShape(baseShape)
                    .allowsHitTesting(false)
            }
    }
}

/// Animated aurora + gradient starfield backdrop.
private struct AtlanteanBackdrop: View {
    let phase: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            LinearGradient(colors: [SealUI.auraTop, SealUI.auraBottom], startPoint: .top, endPoint: .bottom)

            // Starfield
            Canvas { ctx, size in
                let starCount = 140
                var rng = SeededRandom(seed: 777)
                for _ in 0..<starCount {
                    let x = CGFloat(rng.next()) * size.width
                    let y = CGFloat(rng.next()) * size.height
                    let r = CGFloat(rng.next(in: 0.3...1.4))
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                             with: .color(.white.opacity(0.18)))
                }
            }
            .blendMode(.screen)
            .opacity(0.65)

            // Breathing aurora sheet
            AuroraSheet(phase: reduceMotion ? 0 : phase)
                .blendMode(.plusLighter)
                .opacity(0.55)
                .animation(.linear(duration: 0.3), value: phase)
        }
    }
}

/// Breathing rings that resonate with φ-pulse.
private struct HaloRings: View {
    let phase: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Canvas { ctx, size in
            let p = reduceMotion ? 0 : phase
            let center = CGPoint(x: size.width/2, y: size.height/2)
            let baseRadius = min(size.width, size.height) * 0.32
            let k = CGFloat(sin(p * .pi * 2) * 0.12 + 0.14)
            for i in 0..<5 {
                let r = baseRadius + CGFloat(i) * 18
                var path = Path()
                path.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r*2, height: r*2))
                let opacity = Double(0.22 - CGFloat(i) * 0.035)
                let grad = GraphicsContext.Shading.linearGradient(
                    Gradient(colors: [SealUI.mint.opacity(opacity), SealUI.cyan.opacity(0.02)]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: size.width, y: size.height)
                )
                ctx.stroke(path, with: grad, lineWidth: 1.0 + k * 2.0)
            }
        }
    }
}

/// Light sweep highlight that drifts across card edge.
private struct LightSweep: View {
    let phase: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let xOffset = CGFloat(sin((reduceMotion ? 0 : phase) * .pi * 2)) * w * 0.18
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.18), .white.opacity(0.04), .clear],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .frame(width: max(120, w * 0.32))
                .offset(x: xOffset, y: 0)
                .blur(radius: 18)
                .opacity(0.65)
        }
    }
}

/// Organic aurora ribbon (GPU-cheap).
private struct AuroraSheet: View {
    let phase: Double
    var body: some View {
        Canvas { ctx, size in
            var path = Path()
            let height = size.height
            let width = size.width
            let waves = 3
            let amp = height * 0.12
            let baseY = height * 0.28

            path.move(to: .init(x: 0, y: baseY))
            for x in stride(from: 0.0, through: width, by: 8.0) {
                let t = Double(x / width)
                let y = baseY
                    + sin((t * .pi * 2 * Double(waves)) + phase * .pi * 2) * amp
                    + sin((t * .pi * 6) - phase * .pi * 2) * amp * 0.25
                path.addLine(to: CGPoint(x: x, y: y))
            }
            path.addLine(to: CGPoint(x: width, y: height))
            path.addLine(to: CGPoint(x: 0, y: height))
            path.closeSubpath()

            let shading = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [
                    SealUI.mint.opacity(0.25),
                    SealUI.cyan2.opacity(0.18),
                    .clear
                ]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: width, y: height)
            )
            ctx.fill(path, with: shading)
        }
    }
}

// MARK: - Utilities

/// Deterministic RNG for star placement (stable backdrop)
private struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> Double {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return Double((z ^ (z >> 31)) & 0xFFFFFFFFFFFFFFFF) / Double(UInt64.max)
    }
    mutating func next(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + (range.upperBound - range.lowerBound) * next()
    }
}

private extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xff) / 255.0
        let g = Double((hex >> 8) & 0xff) / 255.0
        let b = Double(hex & 0xff) / 255.0
        self = Color(red: r, green: g, blue: b)
    }
}

// MARK: - Previews

#Preview("SealMomentPanel • Atlantean") {
    ZStack {
        LinearGradient(colors: [SealUI.auraTop, SealUI.auraBottom], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        SealMomentPanel(
            hash: "b41e9c7d2f0a8845c2a7f9d1a3b4c56d77e1aa9c33445566ffeeddccbbaa9988",
            url: URL(string: "https://kaiklok.com/s/eternal?claim=phi")!,
            onClose: {}
        )
    }
}
