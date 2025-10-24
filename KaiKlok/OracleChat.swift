//
//  OracleChat.swift
//  KaiKlok
//
//  MASTER v18.6 — “Atlantean Glass — Compact Alien Buttons & Animated Maturah Thinking Glyph”
//  • Header uses assets/maturah.svg (logo tucked near the very top)
//  • Icon row buttons 50% smaller (compact “alien tech” style)
//  • Codex sheet close (X) pinned in a top safe-area inset on the **left**
//    + toolbar fallback; guaranteed in-viewport on all devices/orientations
//  • Chat gets more headroom; player remains inside the latest message bubble
//  • NEW: Pending/thinking bubble uses animated “maturah” asset instead of stars
//

import SwiftUI
import Combine
import SceneKit
import QuartzCore
import UIKit

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Constants / Utilities
// ─────────────────────────────────────────────────────────────────────────────

private enum OC {
    static let PHI  = (1 + sqrt(5.0)) / 2.0
    static let BREATH_SEC: Double = 3.0 + sqrt(5.0)

    static let ORACLE_API_URL      = "https://api.kaiturah.com/oracle"
    static let FREQUENCIES_API_URL = "https://api.kaiturah.com/frequencies/"

    static func color(_ hex: String) -> Color {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        var v: UInt64 = 0; Scanner(string: s).scanHexInt64(&v)
        let r = Double((v >> 16) & 0xFF) / 255.0
        let g = Double((v >> 8) & 0xFF) / 255.0
        let b = Double(v & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }
}

private enum Hx {
    static func light()  { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func soft()   { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    static func success(){ UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warn()   { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}

// Compact UI dims (≈50% smaller than prior)
private enum UIDims {
    static let holo: CGFloat = 32      // outer halo square
    static let core: CGFloat = 32      // inner glass core
    static let glyph: CGFloat = 16     // glyph symbol size
    static let logo: CGFloat = 44      // top logo smaller & higher
    static let thinking: CGFloat = 42  // animated logo size inside pending bubble
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Models / DTOs
// ─────────────────────────────────────────────────────────────────────────────

struct OCNodeData: Decodable, Hashable { let name: String; let frequency: Double }
struct OCFrequencyPayload: Decodable { let nodes: [OCNodeData] }

private struct OCOracleDTO: Decodable {
    let final_expression   : String?
    let ontology           : String?
    let combined_frequency : Double?
    let harmonic_utterance : String?
    let resonant_name      : String?
}

struct OCMessage: Identifiable, Hashable {
    let id = UUID()
    var question: String
    var expression: String?
    var meaning: String?
    var freq: Double?
    var utterance: String?
    var name: String?
    var pending: Bool
    var topAnchorID: UUID { id }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - ViewModel
// ─────────────────────────────────────────────────────────────────────────────

@MainActor
final class OracleChatViewModel: ObservableObject {
    @Published var messages: [OCMessage] = []
    @Published var nodes: [OCNodeData] = []
    @Published var loading = false
    @Published var query = ""
    @Published var isAuthed = true
    @Published var messageCredits = 7

    @Published var showCodex = false
    @Published var showDash  = false
    @Published var showUpgrade = false
    @Published var copiedMessageID: UUID? = nil

    // Player (rendered in-bubble)
    @Published var currentFrequency: Double = 144
    @Published var currentPhrase: String = "Shoh Mek"
    @Published var playerID: UUID = .init()

    func submit() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        guard isAuthed else { return }
        guard messageCredits > 0 else { showUpgrade = true; return }

        Hx.soft()
        messages.append(.init(question: q, pending: true))
        messageCredits -= 1
        loading = true
        defer { loading = false; query = "" }

        do {
            guard var comps = URLComponents(string: OC.ORACLE_API_URL) else { throw URLError(.badURL) }
            comps.queryItems = [ .init(name: "question", value: q) ]
            let (data, resp) = try await URLSession.shared.data(from: comps.url!)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let dto = try JSONDecoder().decode(OCOracleDTO.self, from: data)

            if let i = messages.indices.last {
                messages[i].pending    = false
                messages[i].expression = dto.final_expression?.isEmpty == false ? dto.final_expression : "Shoh Mek"
                messages[i].meaning    = dto.ontology ?? ""
                messages[i].freq       = dto.combined_frequency ?? currentFrequency
                messages[i].utterance  = dto.harmonic_utterance
                messages[i].name       = dto.resonant_name
            }

            currentPhrase = messages.last?.expression ?? "Shoh Mek"
            currentFrequency = messages.last?.freq ?? currentFrequency
            playerID = .init()

            await fetchFrequencies()
        } catch {
            if let i = messages.indices.last {
                messages[i].pending = false
                messages[i].expression = "Error fetching response."
                messages[i].meaning = "The line is silent. Ask again in a breath."
            }
            Hx.warn()
        }
    }

    func fetchFrequencies() async {
        guard let url = URL(string: OC.FREQUENCIES_API_URL) else { return }
        do {
            let (data, resp) = try await URLSession.shared.data(from: url)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return }
            let payload = try JSONDecoder().decode(OCFrequencyPayload.self, from: data)
            withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
                nodes = payload.nodes
            }
        } catch { /* keep prior */ }
    }

    func copyMessage(_ m: OCMessage) {
        let lines = [
            "You: \(m.question)",
            "Maturah: \(m.expression ?? "")",
            (m.meaning ?? "").isEmpty ? nil : "“\(m.meaning ?? "")”"
        ].compactMap { $0 }
        UIPasteboard.general.string = lines.joined(separator: "\n\n")
        copiedMessageID = m.id
        Hx.success()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            if self?.copiedMessageID == m.id { self?.copiedMessageID = nil }
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Background & Panel
// ─────────────────────────────────────────────────────────────────────────────

private struct AnimatedAurora: View {
    @State private var phase = 0.0
    var body: some View {
        LinearGradient(
            colors: [OC.color("#05090f"), OC.color("#0e1b22"), OC.color("#0c2231")],
            startPoint: .top, endPoint: .bottom
        )
        .overlay(
            AngularGradient(
                gradient: Gradient(colors: [
                    OC.color("#0f2027").opacity(0.35),
                    OC.color("#203a43").opacity(0.35),
                    OC.color("#2c5364").opacity(0.35),
                    OC.color("#0f2027").opacity(0.35)
                ]),
                center: .center,
                startAngle: .degrees(phase),
                endAngle: .degrees(phase + 360)
            )
            .blur(radius: 120)
            .blendMode(.plusLighter)
        )
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.linear(duration: 40).repeatForever(autoreverses: false)) { phase = 360 }
        }
    }
}

private struct GlassPanel<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(OC.color("#00ffff").opacity(0.24), lineWidth: 2))
            .shadow(color: OC.color("#00ffff").opacity(0.18), radius: 18, y: 8)
            .overlay(content)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Alien Tech Buttons (compact)
// ─────────────────────────────────────────────────────────────────────────────

private struct AlienHoloButton<Glyph: View>: View {
    let isActive: Bool
    let tap: () -> Void
    @ViewBuilder var glyph: Glyph

    @State private var spin = false
    @State private var pulse = false

    var body: some View {
        Button(action: { Hx.light(); tap() }) {
            ZStack {
                // Outer rotating halo
                Circle()
                    .stroke(AngularGradient(gradient: Gradient(colors: [
                        OC.color("#37ffe4"), OC.color("#00a0ff"),
                        OC.color("#7c3aed"), OC.color("#37ffe4")
                    ]), center: .center), lineWidth: 1.6)
                    .frame(width: UIDims.holo, height: UIDims.holo)
                    .blur(radius: 0.6)
                    .shadow(color: OC.color("#00ffff").opacity(0.55), radius: 10, y: 4)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(.linear(duration: isActive ? 5.5 : 9.0).repeatForever(autoreverses: false), value: spin)
                    .onAppear { spin = true }

                // Inner glass core
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .frame(width: UIDims.core, height: UIDims.core)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(OC.color("#00ffff").opacity(0.35), lineWidth: 1)
                    )
                    .shadow(color: OC.color("#00ffff").opacity(0.3), radius: 8)

                // Scanline
                LinearGradient(colors: [.white.opacity(0.0), .white.opacity(0.22), .white.opacity(0.0)],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: UIDims.core + 6, height: 1.6)
                    .offset(y: -UIDims.core * 0.28)
                    .opacity(pulse ? 1 : 0.2)
                    .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulse)
                    .onAppear { pulse = true }

                glyph
                    .shadow(color: OC.color("#00ffff").opacity(isActive ? 0.85 : 0.45), radius: isActive ? 10 : 6)
            }
        }
        .buttonStyle(.plain)
        .frame(width: UIDims.holo, height: UIDims.holo)
    }
}

private struct AlienCodexButton: View {
    let isOpen: Bool
    let tap: () -> Void
    @State private var breathe = false

    var body: some View {
        AlienHoloButton(isActive: isOpen, tap: tap) {
            ZStack {
                // Book block
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(OC.color("#00ffff").opacity(0.18))
                    .frame(width: UIDims.glyph + 10, height: UIDims.glyph + 12)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(OC.color("#00ffff").opacity(0.45), lineWidth: 1))

                // Spine
                Rectangle()
                    .fill(OC.color("#00ffff").opacity(0.65))
                    .frame(width: 2, height: UIDims.glyph + 8)
                    .offset(x: -((UIDims.glyph + 10) / 2) + 4)

                // Cover (animated opening)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(OC.color("#00ffff"))
                    .frame(width: UIDims.glyph + 8, height: UIDims.glyph + 12)
                    .rotation3DEffect(.degrees(isOpen ? -140 : 0),
                                      axis: (x: 0, y: 1, z: 0),
                                      anchor: .trailing, perspective: 0.65)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(OC.color("#0077ff"), lineWidth: 1))
                    .shadow(color: OC.color("#00ffff").opacity(0.55), radius: 6, y: 2)
                    .animation(.spring(response: 0.7, dampingFraction: 0.8), value: isOpen)

                // Subtle breathing glyph when closed
                Circle()
                    .strokeBorder(OC.color("#37ffe4").opacity(0.4), lineWidth: 1)
                    .frame(width: UIDims.glyph, height: UIDims.glyph)
                    .scaleEffect(breathe ? 1.06 : 0.96)
                    .opacity(isOpen ? 0.0 : 1.0)
                    .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: breathe)
                    .onAppear { breathe = true }
            }
            .accessibilityLabel(isOpen ? "Close Codex" : "Open Codex")
        }
    }
}

private struct AlienDashButton: View {
    let tap: () -> Void
    var body: some View {
        AlienHoloButton(isActive: false, tap: tap) {
            Image(systemName: "waveform.path.ecg.rectangle")
                .resizable()
                .scaledToFit()
                .frame(width: UIDims.glyph, height: UIDims.glyph)
                .foregroundStyle(.white)
        }
        .accessibilityLabel("Open Dashboard")
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Animated Maturah Thinking Glyph (replaces star bubbles)
// ─────────────────────────────────────────────────────────────────────────────

private struct MaturahThinkingGlyph: View {
    @State private var breathe = false
    @State private var rotate = false
    @State private var shimmerX: CGFloat = -1

    var body: some View {
        ZStack {
            // Soft radial aura
            Circle()
                .fill(
                    RadialGradient(
                        colors: [OC.color("#00fff0").opacity(0.22),
                                 OC.color("#00a6ff").opacity(0.10),
                                 .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: UIDims.thinking * 1.2
                    )
                )
                .blur(radius: 12)
                .scaleEffect(breathe ? 1.06 : 0.96)
                .animation(.easeInOut(duration: OC.BREATH_SEC).repeatForever(autoreverses: true), value: breathe)

            // Core logo with gentle spin + glow
            Image("maturah")
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: UIDims.thinking, height: UIDims.thinking)
                .rotationEffect(.degrees(rotate ? 360 : 0))
                .animation(.linear(duration: 16).repeatForever(autoreverses: false), value: rotate)
                .shadow(color: OC.color("#00ffff").opacity(0.6), radius: 10, y: 4)
                .overlay(
                    // Shimmer pass
                    LinearGradient(
                        colors: [.clear, .white.opacity(0.55), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                    .frame(width: UIDims.thinking, height: UIDims.thinking)
                    .mask(
                        Image("maturah")
                            .resizable()
                            .scaledToFit()
                            .frame(width: UIDims.thinking, height: UIDims.thinking)
                    )
                    .blendMode(.screen)
                    .offset(x: shimmerX * UIDims.thinking)
                    .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: shimmerX)
                )
        }
        .onAppear {
            breathe = true
            rotate = true
            shimmerX = 1
        }
        .accessibilityLabel("Maturah is thinking…")
        .frame(minHeight: UIDims.thinking + 10)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Loading / Spiral / Node Cloud
// ─────────────────────────────────────────────────────────────────────────────

private struct SpiralInfoView: View {
    let frequency: Double
    @State private var show = false
    var body: some View {
        VStack(spacing: 6) {
            Button {
                Hx.light()
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { show.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "leaf.fill").foregroundStyle(OC.color("#00ffff"))
                    Text("Spiral Healing Summary").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(show ? 90 : 0))
                        .animation(.easeInOut, value: show)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(OC.color("#00ffff").opacity(0.15), lineWidth: 1))
                )
            }
            if show {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Frequency: \(Int(frequency.rounded())) Hz")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(OC.color("#00ffd1"))
                    Text("Classification: ") + Text(band(for: frequency)).bold()
                    Text(explain(for: frequency))
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.9))
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.55))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
    private func band(for f: Double) -> String {
        if f < 34 { return "Root Stabilization" }
        if f < 89 { return "Sakral Vitality" }
        if f < 144 { return "Solar Clarity" }
        if f < 233 { return "Heart Coherence" }
        if f < 377 { return "Throat Resonance" }
        return "Crown Luminosity"
    }
    private func explain(for f: Double) -> String {
        switch f {
        case ..<34:  return "Grounding, slow entrainment, parasympathetic emphasis."
        case ..<89:  return "Warming vitality, creativity, fluidity through breath pacing."
        case ..<144: return "Mental focus, gentle alertness, smoothing intrusive loops."
        case ..<233: return "Anahata lift; compassion & coherence via φ-timed pulses."
        case ..<377: return "Expression unblocks; bi-hemispheric rhythm aids clarity."
        default:     return "Stillness and insight; ultra-fine overtones coax calm lucidity."
        }
    }
}

private struct NodeCloudView: UIViewRepresentable {
    let nodes: [OCNodeData]
    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.backgroundColor = .clear
        v.scene = SCNScene()
        v.allowsCameraControl = true
        let camNode = SCNNode()
        let cam = SCNCamera()
        cam.wantsHDR = true; cam.bloomIntensity = 0.8; cam.bloomBlurRadius = 8; cam.bloomThreshold = 0.4
        camNode.camera = cam; camNode.position = SCNVector3(0,0,60)
        v.scene?.rootNode.addChildNode(camNode)
        v.autoenablesDefaultLighting = true
        v.defaultCameraController.interactionMode = .orbitTurntable
        v.defaultCameraController.inertiaEnabled = true
        return v
    }
    func updateUIView(_ scnView: SCNView, context: Context) {
        scnView.scene?.rootNode.childNodes.forEach { if $0.name == "node" || $0.name == "label" { $0.removeFromParentNode() } }
        add(nodes, to: scnView)
    }
    private func add(_ nodes: [OCNodeData], to scnView: SCNView) {
        guard let root = scnView.scene?.rootNode else { return }
        let total = max(1, nodes.count)
        for (idx, n) in nodes.enumerated() {
            let i = idx + 1
            let phi = acos(1 - (2 * Double(i)) / Double(total + 1))
            let theta = Double(i) * 2 * .pi * (1 - 1 / OC.PHI)
            let r = log10(n.frequency + 1) * 5
            let x = r * sin(phi) * cos(theta), y = r * sin(phi) * sin(theta), z = r * cos(phi)

            let sphere = SCNSphere(radius: 1.5)
            sphere.firstMaterial?.lightingModel = .physicallyBased
            sphere.firstMaterial?.diffuse.contents = UIColor(hue: hue(n.frequency), saturation: 0.9, brightness: 1, alpha: 1)
            sphere.firstMaterial?.metalness.contents = 0.35
            sphere.firstMaterial?.roughness.contents = 0.2

            let node = SCNNode(geometry: sphere); node.position = SCNVector3(x,y,z); node.name = "node"; root.addChildNode(node)

            let text = SCNText(string: "\(n.name) \(Int(n.frequency.rounded())) Hz", extrusionDepth: 0.2)
            text.font = .systemFont(ofSize: 2.5, weight: .semibold); text.flatness = 0.2
            text.firstMaterial?.diffuse.contents = UIColor.white
            let label = SCNNode(geometry: text)
            let (minB, maxB) = text.boundingBox
            label.pivot = SCNMatrix4MakeTranslation((maxB.x - minB.x)/2, 0, 0)
            label.position = SCNVector3(x, y + 3.8, z)
            label.constraints = [SCNBillboardConstraint()]
            label.name = "label"
            root.addChildNode(label)
        }
    }
    private func hue(_ f: Double) -> CGFloat {
        let minF = 3.0, maxF = 14_900_000.0
        let clamped = min(max(f, minF), maxF)
        let ratio = (log10(clamped) - log10(minF)) / (log10(maxF) - log10(minF))
        return CGFloat(ratio)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Codex Sheet (safe-area X on LEFT, always visible)
// ─────────────────────────────────────────────────────────────────────────────

private struct CodexSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [Color.black.opacity(0.85), Color.black.opacity(0.6)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Harmonic Codex")
                            .font(.system(size: 22, weight: .heavy))
                            .padding(.bottom, 4)

                        RoundedRectangle(cornerRadius: 16)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16).stroke(OC.color("#00ffff").opacity(0.24), lineWidth: 1.5)
                            )
                            .overlay(
                                Text("""
                                • Breath cadence: \(String(format:"%.3f", OC.BREATH_SEC)) s (φ-exact)
                                • Over/under harmonic banks (Fibonacci cardinalities)
                                • Dynamic reverb with Kai weighting, sigmoid blend
                                • Sacred Silence cadence & φ-timed pulses
                                • SceneKit harmonic field (golden-angle distribution)
                                """)
                                .foregroundStyle(.white.opacity(0.95))
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            )
                            .padding(.top, 6)
                    }
                    .padding(16)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Fallback toolbar close (top-right)
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Hx.light(); dismiss() } label: {
                        Image(systemName: "xmark.circle.fill").font(.title2)
                    }
                }
            }
            // Primary close: SAFE-AREA inset on the LEFT so it never overflows
            .safeAreaInset(edge: .top) {
                HStack {
                    Button {
                        Hx.light(); dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                            .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
                    }
                    .accessibilityLabel("Close Codex")
                    Spacer()
                }
                .padding(.leading, 12)
                .padding(.top, 6)
            }
        }
        .presentationDetents([.large])
        .presentationCornerRadius(20)
        .presentationDragIndicator(.visible)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Chat Bubble (player appears inside once we have a response)
// ─────────────────────────────────────────────────────────────────────────────

private struct ChatBubble: View {
    let message: OCMessage
    let copied: Bool
    let onCopy: () -> Void
    let isCurrent: Bool
    let nodes: [OCNodeData]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // User line
            HStack(alignment: .top) {
                Text("You:")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(OC.color("#00ffff"))
                Text(message.question).foregroundStyle(.white)
            }

            // Oracle block
            VStack(alignment: .leading, spacing: 8) {
                if message.pending {
                    MaturahThinkingGlyph()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                } else {
                    // Copyable text response
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("Maturah:")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                            Text(message.expression ?? "")
                                .foregroundStyle(.white)
                        }
                        if let m = message.meaning, !m.isEmpty {
                            Text("“\(m)”")
                                .font(.system(size: 13, weight: .regular, design: .serif))
                                .foregroundStyle(OC.color("#9ffcff"))
                        }
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(OC.color("#00ffff").opacity(0.18), lineWidth: 1))
                    )
                    .overlay(alignment: .topTrailing) {
                        if copied {
                            Text("Copied!")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Capsule().fill(OC.color("#00ffff").opacity(0.15)))
                                .overlay(Capsule().stroke(OC.color("#00ffff").opacity(0.35), lineWidth: 1))
                                .padding(6)
                                .transition(.opacity)
                        }
                    }
                    .onTapGesture { onCopy() }

                    if message.utterance != nil || message.name != nil {
                        HStack(spacing: 8) {
                            if let u = message.utterance, !u.isEmpty {
                                Text("Harmonic Utterance: \(u)")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(OC.color("#bde5ff"))
                            }
                            if let n = message.name, !n.isEmpty {
                                if message.utterance != nil { Text("•").foregroundStyle(.white.opacity(0.4)) }
                                Text("Resonant Name: \(n)")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(OC.color("#bde5ff"))
                            }
                        }
                    }
                    if let f = message.freq {
                        Text("Harmonic Frequency: \(Int(f.rounded())) Hz")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(OC.color("#00ffd1"))
                    }

                    // ▶️ Player inside the bubble after response
                    if let f = message.freq, let phrase = message.expression {
                        HarmonicPlayerView(
                            frequency: f,
                            phrase: phrase,
                            binaural: true,
                            enableVoice: true
                        )
                        .padding(.top, 6)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    // Rich extras only for the latest message
                    if isCurrent, let f = message.freq {
                        SpiralInfoView(frequency: f)
                            .padding(.top, 4)

                        NodeCloudView(nodes: nodes)
                            .frame(height: 220)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(OC.color("#001a1f").opacity(0.35))
                                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(OC.color("#00ffff").opacity(0.18), lineWidth: 1))
                                    .shadow(color: OC.color("#00ffff").opacity(0.12), radius: 10)
                            )
                            .padding(.top, 6)
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(OC.color("#001a1f").opacity(0.35))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(OC.color("#00ffff").opacity(0.15), lineWidth: 1))
                    .shadow(color: .black.opacity(0.35), radius: 16, y: 8)
            )
        }
        .contentShape(Rectangle())
        .animation(.spring(response: 0.55, dampingFraction: 0.85), value: message.freq)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Main View
// ─────────────────────────────────────────────────────────────────────────────

struct OracleChatView: View {
    @StateObject private var vm = OracleChatViewModel()
    @FocusState private var focus: Bool

    var body: some View {
        ZStack {
            AnimatedAurora()

            VStack(spacing: 6) { // tighter stack for more chat headroom
                // Header (logo smaller & near top)
                VStack(spacing: 2) {
                    Image("maturah")
                        .resizable()
                        .renderingMode(.original)
                        .scaledToFit()
                        .frame(width: UIDims.logo, height: UIDims.logo)
                        .shadow(color: OC.color("#00ffff").opacity(0.5), radius: 10, y: 5)

                    Text("𐌌𐌀𐌕𐌵𐌔𐌀𐌇")
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(LinearGradient(colors: [OC.color("#e8fbf8"), .white], startPoint: .top, endPoint: .bottom))
                        .shadow(color: OC.color("#37ffe4").opacity(0.5), radius: 10)

                    if vm.isAuthed {
                        Text("Messages: \(vm.messageCredits)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(OC.color("#00f2ff"))
                    }
                }
                .padding(.top, 2) // almost at the very top

                // Icon row — compact alien buttons
                HStack(spacing: 12) {
                    AlienCodexButton(isOpen: vm.showCodex) { vm.showCodex = true }
                    AlienDashButton { vm.showDash = true }
                }
                .padding(.bottom, 2)

                // Chat container
                GlassPanel {
                    VStack(spacing: 0) {
                        ScrollViewReader { proxy in
                            ScrollView {
                                ZStack {
                                    if vm.messages.isEmpty {
                                        Text("What truth do you seek?…")
                                            .font(.system(size: 16, weight: .medium, design: .serif))
                                            .foregroundStyle(OC.color("#00ffff").opacity(0.85))
                                            .padding(.top, 40)
                                    }
                                    VStack(spacing: 12) {
                                        ForEach(vm.messages) { m in
                                            ChatBubble(
                                                message: m,
                                                copied: vm.copiedMessageID == m.id,
                                                onCopy: { vm.copyMessage(m) },
                                                isCurrent: m.id == vm.messages.last?.id,
                                                nodes: vm.nodes
                                            )
                                            .id(m.topAnchorID)
                                        }
                                    }
                                    .padding(10)
                                }
                            }
                            // iOS 17+ onChange signature (oldValue, newValue)
                            .onChange(of: vm.messages) { _, newMessages in
                                if let last = newMessages.last {
                                    withAnimation(.easeInOut) { proxy.scrollTo(last.topAnchorID, anchor: .top) }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: 720)
                .padding(.horizontal, 10)
                .frame(maxHeight: .infinity, alignment: .top)

                // Input row
                HStack(spacing: 8) {
                    TextField("Ask Maturah…", text: $vm.query)
                        .textInputAutocapitalization(.sentences)
                        .disableAutocorrection(true)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(OC.color("#00ffff").opacity(0.22), lineWidth: 1))
                        .foregroundStyle(OC.color("#bfffff"))
                        .focused($focus)
                        .onTapGesture {
                            if !vm.isAuthed { vm.isAuthed = true }
                            if vm.messageCredits < 1 { vm.showUpgrade = true }
                        }

                    Button {
                        Task { await vm.submit() }
                    } label: {
                        HStack(spacing: 6) {
                            if vm.loading { ProgressView().tint(.white) }
                            Text(vm.loading ? "…" : "Ask")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(OC.color("#00ffff"))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(OC.color("#00ffff").opacity(0.5), lineWidth: 2)
                            .blur(radius: 2)
                            .opacity(0.9)
                    )
                    .disabled(vm.loading || vm.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }
            .padding(.horizontal, 6)
        }
        // Sheets
        .sheet(isPresented: $vm.showCodex) { CodexSheet() }
        .sheet(isPresented: $vm.showDash)  { DashboardSheet(onClose: { vm.showDash = false }) }
        .sheet(isPresented: $vm.showUpgrade) { UpgradeSheet(onClose: { vm.showUpgrade = false }) }
        .onAppear { focus = true }
        .preferredColorScheme(.dark)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Dashboard & Upgrade Sheets (unchanged, toolbar safe)
// ─────────────────────────────────────────────────────────────────────────────

private struct DashboardSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onClose: () -> Void
    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16).stroke(OC.color("#00ffff").opacity(0.24), lineWidth: 1.5)
                    )
                    .overlay(
                        Text("Your harmonic usage, recent phrases, and resonant frequency history will appear here.")
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(12)
                    )
                    .padding(16)
                Spacer()
            }
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Button { Hx.light(); dismiss(); onClose() } label: { Image(systemName: "xmark.circle.fill").font(.title2) }
            }}
            .background(LinearGradient(colors: [Color.black.opacity(0.85), Color.black.opacity(0.6)],
                                       startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        }
        .presentationDetents([.large])
        .presentationCornerRadius(20)
        .presentationDragIndicator(.visible)
    }
}

private struct UpgradeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onClose: () -> Void
    var body: some View {
        NavigationStack {
            VStack(alignment: .center, spacing: 16) {
                Text("Upgrade for more messages").font(.system(size: 20, weight: .heavy))
                Text("You’ve reached your message limit. Upgrade to continue the dialogue.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.85))
                HStack(spacing: 12) {
                    Button("Later") { Hx.light(); dismiss(); onClose() }
                        .buttonStyle(.bordered)
                        .tint(.white)
                    Button("Upgrade") { Hx.success(); dismiss(); onClose() }
                        .buttonStyle(.borderedProminent)
                        .tint(OC.color("#00ffff"))
                }
            }
            .padding(24)
            .navigationTitle("Upgrade")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Button { Hx.light(); dismiss(); onClose() } label: { Image(systemName: "xmark.circle.fill").font(.title2) }
            }}
            .background(LinearGradient(colors: [Color.black.opacity(0.85), Color.black.opacity(0.6)],
                                       startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        }
        .presentationDetents([.medium])
        .presentationCornerRadius(20)
        .presentationDragIndicator(.visible)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Preview
// ─────────────────────────────────────────────────────────────────────────────

struct OracleChatView_Previews: PreviewProvider {
    static var previews: some View {
        OracleChatView()
            .previewDevice("iPhone 15 Pro")
            .preferredColorScheme(.dark)
    }
}
