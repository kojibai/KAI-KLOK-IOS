//
//  SigilView.swift
//  KaiKlok
//
//  Kai-Sigil renderer (Lissajous core + neon layering + Canvas fast path)
//  Canonically deterministic with respect to (pulse, beat, stepIndex, chakraDay)
//
//  ⚠️ IMPORTANT
//  • This file intentionally DOES NOT declare `SigilParams`.
//  • Keep exactly one canonical `SigilParams` in the build graph.
//
//  Authored in the style of an Atlantean priest-king:
//  precise ratios, zero drift, and reverence for φ.
//
//  © Kairos Harmonik Kingdom
//

import SwiftUI
import CoreGraphics

// MARK: - Sacred Palette (single source of truth)

private enum SigilPalette {
    static let bgStart = Color.black
    static let bgEnd   = Color.black.opacity(0.85)

    static let outerGlow = Color.cyan            // aura
    static let midTone   = Color.blue.opacity(0.85)
    static let innerLight = Color.white          // breath highlight
}

// MARK: - Local math helpers (names isolated to avoid collisions)

@inline(__always)
private func lissajousPoints(in size: CGSize,
                             a: Double,
                             b: Double,
                             delta: Double,
                             steps: Int = 360) -> [CGPoint] {
    let w = size.width
    let h = size.height
    guard steps > 1, w > 0, h > 0 else { return [] }

    var pts: [CGPoint] = Array(repeating: .zero, count: steps)
    let tau = Double.pi * 2.0
    let denom = Double(steps &- 1) // safe: steps > 1

    var i = 0
    while i < steps {
        let t = (Double(i) / denom) * tau
        // Normalize sin outputs to [0, 1] then scale to canvas size
        let x = ((sin(a * t + delta) + 1.0) * 0.5) * w
        let y = ((sin(b * t)          + 1.0) * 0.5) * h
        pts[i] = CGPoint(x: x, y: y)
        i &+= 1
    }
    return pts
}

@inline(__always)
private func polylinePath(from points: [CGPoint], closed: Bool = true) -> Path {
    var p = Path()
    guard let first = points.first else { return p }
    p.move(to: first)
    // Straight polyline for speed and determinism
    if points.count > 1 {
        var idx = 1
        while idx < points.count {
            p.addLine(to: points[idx])
            idx &+= 1
        }
    }
    if closed { p.closeSubpath() }
    return p
}

// MARK: - Param → curve mapping

/// Eternal steps per beat (44) unless your canon differs.
private let SIGIL_STEPS_PER_BEAT: Int = 44

@inline(__always)
private func deriveABDelta(from params: SigilParams) -> (a: Double, b: Double, delta: Double) {
    // Keep small co-prime-ish integers for vivid knots without degeneracy.
    // a ∈ 1…7, b ∈ 2…6; δ advances with stepIndex over one full breath.
    let a = Double((params.pulse % 7) + 1)
    let b = Double((params.beat  % 5) + 2)

    let clampedStep = max(0, min(SIGIL_STEPS_PER_BEAT - 1, params.stepIndex))
    let delta = (Double(clampedStep) / Double(SIGIL_STEPS_PER_BEAT)) * (Double.pi * 2.0)

    return (a, b, delta)
}

// MARK: - Geometry core (shared between on-screen and export)

/// Minimal scene graph so SVG exporters can reuse the exact geometry.
enum SigilGeometry {
    /// Returns a SwiftUI `Path` for the sigil in the given rect and params.
    static func path(in rect: CGRect, params: SigilParams, sampleCount: Int = 360) -> Path {
        let (a, b, delta) = deriveABDelta(from: params)
        let pts = lissajousPoints(in: rect.size, a: a, b: b, delta: delta, steps: max(24, sampleCount))
        return polylinePath(from: pts, closed: true)
    }

    /// Suggested base stroke width as a function of rect size and UI scale.
    static func baseWidth(for rect: CGRect, lineScale: CGFloat) -> CGFloat {
        let minSide = min(max(rect.width, 1), max(rect.height, 1))
        return max(1.6, minSide * 0.009) * lineScale
    }
}

// MARK: - SigilView (SwiftUI)

@MainActor
public struct SigilView: View {
    public var params: SigilParams
    public var lineScale: CGFloat      // UI control for stroke scaling
    public var glowStrength: CGFloat   // outer glow radius

    public init(params: SigilParams,
                lineScale: CGFloat = 1.0,
                glowStrength: CGFloat = 22.0) {
        self.params = params
        self.lineScale = lineScale
        self.glowStrength = glowStrength
    }

    public var body: some View {
        GeometryReader { geo in
            let rect = CGRect(origin: .zero, size: geo.size)
            let path = SigilGeometry.path(in: rect, params: params)
            let baseW = SigilGeometry.baseWidth(for: rect, lineScale: lineScale)

            Group {
                if #available(iOS 15.0, macOS 12.0, *) {
                    Canvas { ctx, sz in
                        // === Ground ===
                        let bgRect = Path(CGRect(origin: .zero, size: sz))
                        ctx.fill(bgRect, with: .linearGradient(
                            Gradient(colors: [SigilPalette.bgStart, SigilPalette.bgEnd, SigilPalette.bgStart]),
                            startPoint: .zero,
                            endPoint: CGPoint(x: 0, y: sz.height)
                        ))

                        // Subtle inner vignette (breath chamber)
                        let vignette = Gradient(colors: [.clear, .clear, Color.blue.opacity(0.08)])
                        ctx.fill(
                            bgRect,
                            with: .radialGradient(
                                vignette,
                                center: CGPoint(x: sz.width / 2.0, y: sz.height / 2.0),
                                startRadius: 0,
                                endRadius: min(sz.width, sz.height) * 0.6
                            )
                        )

                        // === Neon stack (outer → inner) ===
                        // Outer aura
                        ctx.addFilter(.shadow(color: SigilPalette.outerGlow.opacity(0.55),
                                              radius: glowStrength, x: 0, y: 0))
                        ctx.stroke(path, with: .color(SigilPalette.outerGlow), lineWidth: baseW)

                        // Mid tone—slight blur for plasma depth
                        ctx.addFilter(.blur(radius: 6))
                        ctx.stroke(path, with: .color(SigilPalette.midTone), lineWidth: baseW * 0.65)

                        // Inner highlight—breath edge
                        ctx.addFilter(.shadow(color: SigilPalette.innerLight.opacity(0.9),
                                              radius: 1, x: 0, y: 0))
                        ctx.stroke(path, with: .color(SigilPalette.innerLight), lineWidth: max(0.5, baseW * 0.33))
                    }
                } else {
                    // Fallback (pre-Canvas): layered vectors
                    ZStack {
                        LinearGradient(colors: [SigilPalette.bgStart, SigilPalette.bgEnd, SigilPalette.bgStart],
                                       startPoint: .top, endPoint: .bottom)
                            .ignoresSafeArea()

                        // Outer aura (approx with blur)
                        path
                            .stroke(SigilPalette.outerGlow.opacity(0.85), lineWidth: baseW)
                            .blur(radius: glowStrength * 0.33)

                        // Mid plasma
                        path
                            .stroke(SigilPalette.midTone, lineWidth: baseW * 0.65)
                            .blur(radius: 3)

                        // Inner breath line
                        path
                            .stroke(SigilPalette.innerLight, lineWidth: max(0.5, baseW * 0.33))
                    }
                }
            }
        }
        .drawingGroup() // single offscreen pass: better compositing/perf on complex paths
        .accessibilityLabel(Text("Kai-Sigil, pulse \(params.pulse)"))
        .accessibilityAddTraits(.isImage)
    }
}

// MARK: - Export helpers (for perfect parity with on-screen)

public extension SigilView {
    /// Returns the exact path used for drawing at the given size. Useful for SVG export.
    static func makePath(size: CGSize, params: SigilParams, sampleCount: Int = 360) -> Path {
        SigilGeometry.path(in: CGRect(origin: .zero, size: size), params: params, sampleCount: sampleCount)
    }

    /// Suggested stroke width used by the view for a given size and lineScale.
    static func strokeWidth(size: CGSize, lineScale: CGFloat) -> CGFloat {
        SigilGeometry.baseWidth(for: CGRect(origin: .zero, size: size), lineScale: lineScale)
    }
}

// MARK: - Preview

#if DEBUG
// Keep the preview gated—previews often link wrong initializers and cause confusion.
// Flip to `true` after aligning with your canonical `SigilParams` initializer.
private let ENABLE_SIGILVIEW_PREVIEW = false

#if ENABLE_SIGILVIEW_PREVIEW
struct SigilView_Previews: PreviewProvider {
    static var previews: some View {
        // ⬇️ Replace with your real initializer once confirmed.
        let previewParams = SigilParams(
            pulse: 12345,
            beat: 7,
            stepIndex: 22,
            chakraDay: 0,
            seed: 42,
            userPhiKey: nil,
            kaiSignature: nil,
            timestamp: 12345
        )
        return SigilView(params: previewParams, lineScale: 1.0, glowStrength: 22.0)
            .frame(width: 320, height: 320)
            .background(
                LinearGradient(colors: [SigilPalette.bgStart, SigilPalette.bgEnd, SigilPalette.bgStart],
                               startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            )
            .previewDisplayName("SigilView")
    }
}
#endif
#endif
