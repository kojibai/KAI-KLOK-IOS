//
//  SigilMath.swift
//  KaiKlok
//
//  Created by BJ Klock on 9/13/25.
//  NOTE: This file intentionally does NOT reference SigilParams.
//

import Foundation
import CoreGraphics

/// Deterministic pseudo-random, stable across platforms
@inline(__always)
func splitmix64(_ x0: UInt64) -> UInt64 {
    var x = x0 &+ 0x9E3779B97F4A7C15
    x = (x ^ (x >> 30)) &* 0xBF58476D1CE4E5B9
    x = (x ^ (x >> 27)) &* 0x94D049BB133111EB
    return x ^ (x >> 31)
}

/// Fibonacci-ratio harmonics with binaural offset derived from seed
struct HarmonicRatios {
    let a: Double
    let b: Double
    let phase: Double
}

/// Cheap, deterministic ratios (swap with your exact TS formula if desired)
@inline(__always)
func ratios(fromSeed seed: UInt64, beat: Int, step: Int) -> HarmonicRatios {
    let s1 = splitmix64(seed ^ UInt64(beat) &* 0x9E37)
    let s2 = splitmix64(seed ^ UInt64(step) &* 0x94D0)

    // choose neighboring Fibonacci numbers
    let fibs: [Double] = [3, 5, 8, 13, 21, 34, 55, 89, 144]
    let i  = Int(s1 % UInt64(fibs.count - 2))
    let a  = fibs[i]
    let b  = fibs[i + 2]

    // binaural-style tiny detune
    let detune = (Double(Int64(bitPattern: s2) % 997) / 997.0) * 0.018  // ~ ±1.8%
    let phase  = (Double((s1 >> 11) % 3600) / 3600.0) * 2 * .pi

    return HarmonicRatios(a: a, b: b * (1.0 + detune), phase: phase)
}

/// Lissajous-style curve (param-free: no SigilParams dependency)
@inline(__always)
func lissajousPoints(
    size: CGSize,
    seed: UInt64,
    pulse: Int,
    beat: Int,
    stepIndex: Int,
    samples: Int = 2600
) -> [CGPoint] {
    let R  = min(size.width, size.height) * 0.44
    let cx = size.width * 0.5
    let cy = size.height * 0.5

    // fold in pulse for variety but keep signature deterministic
    let r = ratios(fromSeed: seed ^ UInt64(pulse),
                   beat: beat,
                   step: stepIndex)

    var pts: [CGPoint] = []
    pts.reserveCapacity(samples)

    let twoPi = 2.0 * Double.pi
    for i in 0..<samples {
        let t = Double(i) / Double(samples)
        let x = sin(r.a * twoPi * t + r.phase)
        let y = sin(r.b * twoPi * t)
        pts.append(CGPoint(x: cx + CGFloat(x) * R, y: cy + CGFloat(y) * R))
    }
    return pts
}

/// Smooth path through points
@inline(__always)
func makePath(_ points: [CGPoint]) -> CGPath {
    let path = CGMutablePath()
    guard let first = points.first else { return path }
    path.move(to: first)
    for p in points.dropFirst() { path.addLine(to: p) }
    path.closeSubpath()
    return path
}
