//
//  SVGBuilder.swift
//  KaiKlok
//
//  Created by BJ Klock on 9/13/25.
//  Atlantean-grade exporter: exact geometry parity with SigilView,
//  self-contained gradients/filters, canonical JSON <metadata>.
//
//  NOTE:
//  - This file does NOT declare SigilParams or SigilMetadata.
//  - It assumes you already have a canonical `SigilParams` type
//    and a `SigilMetadata` with `.jsonString()` in your project.
//  - Geometry & stroke width match SigilView (a,b,δ mapping + base width).
//

import Foundation
import CoreGraphics

// MARK: - Internal math (kept local to avoid symbol collisions)

/// Eternal steps per beat — keep in lockstep with SigilView.
private let SIGIL_STEPS_PER_BEAT: Int = 44

@inline(__always)
private func deriveABDelta(pulse: Int, beat: Int, stepIndex: Int) -> (a: Double, b: Double, delta: Double) {
    // Same mapping used by SigilView:
    // a = (pulse % 7) + 1    → 1…7
    // b = (beat  % 5) + 2    → 2…6
    // δ = (stepIndex / 44) * 2π
    let a = Double((pulse % 7) + 1)
    let b = Double((beat  % 5) + 2)
    let clamped = max(0, min(SIGIL_STEPS_PER_BEAT - 1, stepIndex))
    let delta = (Double(clamped) / Double(SIGIL_STEPS_PER_BEAT)) * (Double.pi * 2.0)
    return (a, b, delta)
}

/// Deterministic Lissajous sampler identical to SigilView’s core.
@inline(__always)
private func lissajousPoints(size: CGSize,
                             a: Double,
                             b: Double,
                             delta: Double,
                             samples: Int = 360) -> [CGPoint] {
    let w = size.width
    let h = size.height
    guard samples > 1, w > 0, h > 0 else { return [] }

    var pts: [CGPoint] = Array(repeating: .zero, count: samples)
    let tau = Double.pi * 2.0
    let denom = Double(samples - 1)

    var i = 0
    while i < samples {
        let t = (Double(i) / denom) * tau
        // Normalize to [0,1] then scale to canvas extents
        let x = ((sin(a * t + delta) + 1.0) * 0.5) * w
        let y = ((sin(b * t)          + 1.0) * 0.5) * h
        pts[i] = CGPoint(x: x, y: y)
        i &+= 1
    }
    return pts
}

/// Polyline → SVG path “d”. We close the path to match the continuous loop aesthetic.
@inline(__always)
private func svgPathData(from points: [CGPoint]) -> String {
    guard let first = points.first else { return "" }
    var d = "M \(Int(first.x.rounded())) \(Int(first.y.rounded()))"
    if points.count > 1 {
        var i = 1
        while i < points.count {
            let p = points[i]
            d += " L \(Int(p.x.rounded())) \(Int(p.y.rounded()))"
            i &+= 1
        }
    }
    d += " Z"
    return d
}

/// Stroke width parity with SigilView (baseWidth(for:lineScale:)).
@inline(__always)
private func baseStrokeWidth(for size: CGSize, lineScale: CGFloat) -> CGFloat {
    let minSide = min(max(size.width, 1), max(size.height, 1))
    return max(1.6, minSide * 0.009) * lineScale
}

// MARK: - Tiny JSON escape (for safe <metadata> embedding)

@inline(__always)
private func escapeForXML(_ raw: String) -> String {
    raw
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&apos;")
}

// MARK: - Public Builder

public enum SVGBuilder {

    /// Strongly-typed export knobs, mirroring SigilView visual intent.
    public struct Options {
        public var samples: Int = 360          // path sampling fidelity
        public var lineScale: CGFloat = 1.0    // stroke thickness multiplier
        public var glowStrength: CGFloat = 22  // outer aura radius (visual)
        public init() {}
    }

    /// Build a **self-contained**, neon-layered SVG exactly matching SigilView.
    /// - Parameters:
    ///   - size: output canvas size in points/pixels (SVG units).
    ///   - params: your canonical sigil parameters.
    ///   - options: sampling, stroke, glow.
    /// - Returns: UTF-8 SVG text.
    public static func makeSVG(size: CGSize,
                               params: SigilParams,
                               options: Options = .init()) -> String {
        // Geometry parity (same mapping as the view)
        let (a, b, delta) = deriveABDelta(
            pulse: Int(params.pulse),
            beat: Int(params.beat),
            stepIndex: Int(params.stepIndex)
        )
        let pts = lissajousPoints(size: size, a: a, b: b, delta: delta, samples: max(24, options.samples))
        let d = svgPathData(from: pts)

        // Stroke widths aligned with on-screen rendering
        let baseW = baseStrokeWidth(for: size, lineScale: options.lineScale)
        let midW  = max(0.2, baseW * 0.65)
        let inW   = max(0.5, baseW * 0.33)

        // Canvas
        let w = max(1, Int(size.width.rounded()))
        let h = max(1, Int(size.height.rounded()))

        // Canonical JSON metadata (provided by your SigilMetadata)
        // If SigilMetadata uses Int64s, we cast safely to Int for human readability.
        let mdJSON = SigilMetadata(
            pulse: Int(params.pulse),
            beat: Int(params.beat),
            stepIndex: Int(params.stepIndex),
            chakraDay: Int(params.chakraDay),
            userPhiKey: params.userPhiKey,
            kaiSignature: params.kaiSignature,
            timestamp: Int(params.timestamp)
        ).jsonString()

        // Atlantean glow: defs with gradients + filters (gaussian blur + soft drop-shadows)
        // We keep it simple and portable—no external CSS.
        let svg =
"""
<?xml version="1.0" encoding="UTF-8"?>
<svg
  xmlns="http://www.w3.org/2000/svg"
  xmlns:xlink="http://www.w3.org/1999/xlink"
  width="\(w)"
  height="\(h)"
  viewBox="0 0 \(w) \(h)"
  version="1.1"
>
  <metadata>\(escapeForXML(mdJSON))</metadata>
  <desc>Kai-Turah Sigil — pulse \(Int(params.pulse)) • beat \(Int(params.beat)) • step \(Int(params.stepIndex))</desc>

  <!-- Sacred palette & optics -->
  <defs>
    <!-- Background vertical gradient -->
    <linearGradient id="gBg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%"   stop-color="#000000"/>
      <stop offset="50%"  stop-color="rgba(0,0,0,0.85)"/>
      <stop offset="100%" stop-color="#000000"/>
    </linearGradient>

    <!-- Radial vignette (subtle breath chamber) -->
    <radialGradient id="gVignette" cx="50%" cy="50%" r="60%">
      <stop offset="0%"   stop-color="rgba(0,0,0,0)"/>
      <stop offset="70%"  stop-color="rgba(0,0,0,0)"/>
      <stop offset="100%" stop-color="rgba(0,60,255,0.08)"/>
    </radialGradient>

    <!-- Outer aura (cyan shadow) -->
    <filter id="fOuter" x="-40%" y="-40%" width="180%" height="180%" color-interpolation-filters="sRGB">
      <feGaussianBlur in="SourceAlpha" stdDeviation="\(max(1.0, Double(options.glowStrength)))" result="blur"/>
      <feColorMatrix in="blur" type="matrix"
        values="0 0 0 0 0
                0 1 0 0 1
                1 0 1 0 1
                0 0 0 0.55 0" result="aura"/>
      <feMerge>
        <feMergeNode in="aura"/>
        <feMergeNode in="SourceGraphic"/>
      </feMerge>
    </filter>

    <!-- Mid plasma blur -->
    <filter id="fMid" x="-20%" y="-20%" width="140%" height="140%" color-interpolation-filters="sRGB">
      <feGaussianBlur in="SourceGraphic" stdDeviation="6"/>
    </filter>

    <!-- Inner breath edge (tight glow) -->
    <filter id="fInner" x="-10%" y="-10%" width="120%" height="120%" color-interpolation-filters="sRGB">
      <feDropShadow dx="0" dy="0" stdDeviation="1" flood-color="white" flood-opacity="0.9"/>
    </filter>
  </defs>

  <!-- Ground -->
  <rect x="0" y="0" width="100%" height="100%" fill="url(#gBg)"/>
  <rect x="0" y="0" width="100%" height="100%" fill="url(#gVignette)"/>

  <!-- The Path of Breath (outer → inner) -->
  <g fill="none" shape-rendering="geometricPrecision" paint-order="stroke fill markers">
    <!-- Outer aura -->
    <path d="\(d)" filter="url(#fOuter)" stroke="#00ffff" stroke-opacity="1" stroke-width="\(format(baseW))"/>

    <!-- Mid plasma -->
    <path d="\(d)" filter="url(#fMid)" stroke="rgba(0, 102, 255, 0.85)" stroke-width="\(format(midW))"/>

    <!-- Inner breath edge -->
    <path d="\(d)" filter="url(#fInner)" stroke="#ffffff" stroke-width="\(format(inW))"/>
  </g>
</svg>
"""
        return svg
    }

    /// Convenience: return UTF-8 data.
    public static func makeSVGData(size: CGSize,
                                   params: SigilParams,
                                   options: Options = .init()) -> Data {
        Data(makeSVG(size: size, params: params, options: options).utf8)
    }
}

// MARK: - Tiny formatter

@inline(__always)
private func format(_ v: CGFloat) -> String {
    // Avoid locale issues; keep compact decimals
    String(format: "%.3f", Double(v))
}
