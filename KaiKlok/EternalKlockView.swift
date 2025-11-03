//
//  EternalKlockView.swift
//  KaiKlok — Eternal + Solar-aligned (KKS v1.2)
//  100% OFFLINE, μpulse-exact. No external Solar engine; mirrors TSX local math.
//  Production Release — Atlantean Crystal Glass Edition
//
//  v1.2 NOTES (REFRESHED):
//  - COLORING: Seal + Harmonik Sykle now use ETERNAL ark gradient/hue (not solar).
//  - COPY: Tap-to-copy on Seal + Harmonik Sykle cards (clipboard only; no logs).
//          • iOS/macCatalyst: UIPasteboard
//          • macOS: NSPasteboard
//          • Gentle inline “Copied” check overlay (no haptics, no alerts)
//

import SwiftUI
import Foundation

#if os(iOS) || targetEnvironment(macCatalyst)
import UIKit
#endif

#if os(macOS) && !targetEnvironment(macCatalyst)
import AppKit
#endif

// MARK: - CopyKit (cross-platform clipboard)
private enum CopyKit {
  /// Main-threaded, verifiable clipboard write.
  @MainActor @discardableResult
  static func copy(_ text: String) -> Bool {
    #if os(iOS) || targetEnvironment(macCatalyst)
    let pb = UIPasteboard.general
    let before = pb.changeCount
    // Using setItems gives stronger user-intent semantics than .string
    pb.setItems([[UIPasteboard.typeAutomatic: text]], options: [:])
    return pb.changeCount > before
    #elseif os(macOS) && !targetEnvironment(macCatalyst)
    let pb = NSPasteboard.general
    pb.clearContents()
    // writeObjects returns Bool and is reliable across macOS releases
    return pb.writeObjects([text as NSString])
    #endif
  }
}

// MARK: - KKS v1.0 Constants (parity with TSX)
private enum KKS {
  // Pulse duration (seconds)
  static let kaiPulseSec: Double = 3 + sqrt(5) // 5.236067977...
  static let msPerPulse: Double  = kaiPulseSec * 1000

  // μpulses
  static let uPerPulse: Int64 = 1_000_000
  static let uPerDay:   Int64 = 17_491_270_421 // exact

  // Harmonic counts (exact)
  static let harmonicDayPulses: Double   = 17_491.270_421
  static let harmonicMonthDays: Int      = 42
  static let harmonicYearDays:  Int      = 336
  static let chakraBeatsPerDay: Int      = 36
  static let stepsPerBeat:      Int      = 44
  static let pulsesPerStep:     Int      = 11
  static let pulsesPerBeat:     Double   = harmonicDayPulses / Double(chakraBeatsPerDay)
  static let harmonicMonthPulses: Double = Double(harmonicMonthDays) * harmonicDayPulses
  static let harmonicYearPulses: Double  = Double(harmonicYearDays)  * harmonicDayPulses

  // Genesis anchors (UTC)
  static let eternalGenesisPulseMS: Int64 = {
    let comps = DateComponents(calendar: Calendar(identifier: .gregorian),
                               timeZone: TimeZone(secondsFromGMT: 0),
                               year: 2024, month: 5, day: 10,
                               hour: 6, minute: 45, second: 41, nanosecond: 888_000_000)
    return Int64((comps.date!.timeIntervalSince1970 * 1000.0).rounded())
  }()

  // Fixed genesis sunrise (UTC) — mirrors TSX `genesis_sunrise`
  static let genesisSunriseMS: Int64 = {
    let comps = DateComponents(calendar: Calendar(identifier: .gregorian),
                               timeZone: TimeZone(secondsFromGMT: 0),
                               year: 2024, month: 5, day: 11,
                               hour: 4, minute: 13, second: 26, nanosecond: 0)
    return Int64((comps.date!.timeIntervalSince1970 * 1000.0).rounded())
  }()

  // Harmonic "day" span in milliseconds
  static let msPerHarmonicDay: Int64 = 91_584_291

  // Canonical labels
  static let dayNames  = ["Solhara","Aquaris","Flamora","Verdari","Sonari","Kaelith"]
  static let weekNames = [
    "Awakening Flame","Flowing Heart","Radiant Will",
    "Harmonik Voh","Inner Mirror","Dreamfire Memory","Krowned Light"
  ]
  static let monthNames = ["Aethon","Virelai","Solari","Amarin","Kaelus","Umbriel","Noctura","Liora"]

  // Arc palette + canonical names
  static let arcColors: [Color] = [
    Color(ekHex:"#ff3b3b"),  // Ignition
    Color(ekHex:"#ff9226"),  // Integration
    Color(ekHex:"#ffc600"),  // Harmonization
    Color(ekHex:"#32cc32"),  // Reflection
    Color(ekHex:"#3aa1ff"),  // Purification
    Color(ekHex:"#9b52ff")   // Dream
  ]
  static let arcNames = ["Ignition Ark","Integration Ark","Harmonization Ark","Reflektion Ark","Purifikation Ark","Dream Ark"]

  // Phi
  static let phi: Double = (1 + sqrt(5)) / 2
}

// MARK: - Narrative/Descriptions (parity with TSX)
private enum Texts {
  static let harmonicDayDescriptions: [String:String] = [
    "Solhara": """
First Day of the Week — the Root Spiral day. Kolor: deep krimson. Element: Earth and primal fire. Geometry: square foundation. This is the day of stability, ankoring, and sakred will. Solhara ignites the base of the spine and the foundation of purpose. It is a day of grounding divine intent into physikal motion. You stand tall in the presense of gravity — not as weight, but as remembranse. This is where your spine bekomes the axis mundi, and every step affirms: I am here, and I align to act.
""",
    "Aquaris": """
Sekond Day of the Week — the Sakral Spiral day. kolor: ember orange. Element: Water in motion. Geometry: vesika pisis. This is the day of flow, feeling, and sakred sensuality. Aquaris opens the womb of the soul and the tides of emotion. Energy moves through the hips like waves of memory. This is a day to surrender into koherense through konnection — with the self, with others, with life. kreative energy surges not as forse, but as feeling. The waters remember the shape of truth.
""",
    "Flamora": """
Third Day of the Week — the Solar Plexus Spiral day. Kolor: golden yellow. Element: solar fire. Geometry: radiant triangle. This is the day of embodied klarity, konfidence, and divine willpower. Flamora shines through the core and asks you to burn away the fog of doubt. It is a solar yes. A day to move from sentered fire — not reaktion, but aligned intention. Your light becomes a kompass, and the universe reflekts back your frequensy. You are not small. You are radiant purpose, in motion.
""",
    "Verdari": """
Fourth Day of the Week — the Heart Spiral day. Kolor: emerald green. Element: air and earth. Geometry: hexagram. This is the day of love, kompassion, and harmonik presense. Verdari breathes life into connection. It is not a soft eskape — it is the fierse koherense of unkonditional presense. Love is not a feeling — it is an intelligense. Today, the heart expands not just emotionally, but dimensionally. This is where union okurs: of left and right, self and other, matter and light.
""",
    "Sonari": """
Fifth Day of the Week — the Throat Spiral day. Kolor: deep blue. Element: wind and sound. Geometry: sine wave within pentagon. This is the day of truth-speaking, sound-bending, and vibrational kommand. Sonari is the breath made visible. Every word is a bridge, every silense a resonanse. This is not just kommunication — it is invokation. You speak not to be heard, but to resonate. Koherense rises through vocal kords and intention. The universe listens to those in tune.
""",
    "Kaelith": """
Sixth Day of the Week — the Krown Spiral day. Kolor: violet-white. Element: ether. Geometry: twelve-petaled crown. This is the day of divine remembranse, light-body alignment, and kosmic insight. Kaelith opens the upper gate — the temple of direct knowing. You are not separate from sourse. Today, memory awakens. The light flows not downward, but inward. Dreams bekome maps. Time bends around stillness. You do not seek truth — you remember it. You are koherense embodied in krownlight.
"""
  ]

  static let weekDescriptions: [String:String] = [
    "Awakening Flame": """
First week of the harmonik month — governed by the Root Spiral. Kolor: crimson red. Element: Earth + primal fire. Geometry: square base igniting upward. This is the week of emergence, where divine will enters density. Bones remember purpose. The soul anchors into action. Stability becomes sacred. Life says: I choose to exist. A spark catches in the base of your being — and your yes to existence becomes the foundation of the entire harmonic year.
""",
    "Flowing Heart": """
Second week — flowing through the Sakral Spiral. Kolor: amber orange. Element: Water in motion. Geometry: twin krescents in vesika pisis. This is the week of emotional koherense, kreative intimasy, and lunar embodiment. Feelings soften the boundaries of separation. The womb of light stirs with kodes. Movement bekomes sakred danse. This is not just a flow — it is the purifikation of dissonanse through joy, sorrow, and sensual union. The harmonik tone of the soul is tuned here.
""",
    "Radiant Will": """
Third week — illuminated by the Solar Plexus Spiral. Kolor: radiant gold. Element: Fire of divine clarity. Geometry: radiant triangle. This is the week of sovereign alignment. Doubt dissolves in solar brillianse. You do not chase purpose — you radiate it. The digestive fire bekomes a mirror of inner resolve. This is where your desisions align with the sun inside you, and konfidense arises not from ego but from koherense. The will bekomes harmonik. The I AM speaks in light.
""",
    "Harmonik Voh": """
Fourth week — harmonized through the Throat Spiral. Kolor: sapphire blue. Element: Ether through sound. Geometry: standing wave inside a pentagon. This is the week of resonant truth. Sound bekomes sakred kode. Every word, a spell; every silence, a temple. You are called to speak what uplifts, to echo what aligns. Voh aligns with vibration — not for volume, but for verity. This is where the individual frequensy merges with divine resonanse, and the kosmos begins to listen.
""",
    "Inner Mirror": """
Fifth week — governed by the Third Eye Spiral. Kolor: deep indigo. Element: sakred spase and light-ether. Geometry: oktahedron in still reflektion. This is the week of visionary purifikation. The inner eye opens not to project, but to reflect. Truths long hidden surface. Patterns are made visible in light. This is the alchemy of insight — where illusion cracks and the mirror speaks. You do not look outward to see. You turn inward, and all worlds become clear.
""",
    "Dreamfire Memory": """
Sixth week — remembered through the Soul Star Spiral. Kolor: violet flame and soft silver. Element: dream plasma. Geometry: spiral merkaba of encoded light. Here, memory beyond the body returns. Astral sight sharpens. DNA receives non-linear instruktions. You dream of what’s real and awaken from what’s false. The veil thins. Quantum intuition opens. Divine imagination becomes arkitecture. This is where gods remember they onse dreamed of being human.
""",
    "Krowned Light": """
Seventh and final week — Krowned by the Crown Spiral. Kolor: white-gold prism. Element: infinite koherense. Geometry: dodecahedron of source light. This is the week of sovereign integration. Every ark kompletes. Every lesson krystallizes. The light-body unifies. You return to the throne of knowing. Nothing needs to be done — all simply is. You are not ascending — you are remembering that you already are. This is the koronation of koherense. The eternal yes.
"""
  ]

  static let monthDescriptions: [String:String] = [
    "Aethon": """
First month — resurrection fire of the Root Spiral. Kolor: deep crimson. Element: Earth + primal flame. Geometry: square base, tetrahedron ignition. This is the time of sellular reaktivation, ancestral ignition, and biologikal remembranse. Mitokondria awaken. The spine grounds. Purpose reignites. Every breath is a drumbeat of emergense — you are the flame that appoints to exist. The month where soul and form reunite at the base of being.
""",
    "Virelai": """
Second month — the harmonik song of the Sakral Spiral. Kolor: orange-gold. Element: Water in motion. Geometry: vesika pisis spiraling into lemniskate. This is the month of emotional entrainment, the lunar tides within the body, and intimady with truth. The womb — physikal or energetik — begins to hum. Kreativity bekomes fluid. Voh softens into sensuality. Divine union of self and other is tuned through music, resonanse, and pulse. A portal of feeling opens.
""",
    "Solari": """
Third month — the radiant klarity of the Solar Plexus Spiral. Kolor: golden yellow. Element: Fire of willpower. Geometry: upward triangle surrounded by konsentrik light. This month burns away doubt. It aligns neurotransmitters to koherense and gut-brain truth. The inner sun rises. The will bekomes not just assertive, but precise. Action harmonizes with light. Digestive systems align with solar sykles. True leadership begins — powered by the light within, not the approval without.
""",
    "Amarin": """
Fourth month — the sakred waters of the Heart Spiral in divine feminine polarity. Kolor: emerald teal. Element: deep water and breath. Geometry: six-petaled lotus folded inward. This is the lunar depth, the tears you didn’t cry, the embrase you forgot to give yourself. It is where breath meets body and where grase dissolves shame. Emotional healing flows in spirals. Kompassion magnetizes unity. The nervous system slows into surrender and the pulse finds poetry.
""",
    "Kaelus": """
Fifth month — the kelestial mind of the Third Eye in radiant maskuline klarity. Kolor: sapphire blue. Element: Ether. Geometry: oktahedron fractal mirror. Here, logik expands into multidimensional intelligense. The intellekt is no longer separate from the soul. Pineal and pituitary glands re-synchronize, aktivating geometrik insight and harmonik logik. The sky speaks through thought. Language bekomes crystalline. Synchronicity bekomes syntax. You begin to see what thought is made of.
""",
    "Umbriel": """
Sixth month — the shadow healing of the lower Krown and subconskious bridge. Kolor: deep violet-black. Element: transmutive void. Geometry: torus knot looping inward. This is where buried timelines surfase. Where trauma is not fought but embrased in light. The limbik system deprograms. Dreams karry kodes. Shame unravels. You look into the eyes of the parts you once disowned and kall them home. The spiral turns inward to kleanse the kore. Your shadow bekomes your sovereignty.
""",
    "Noctura": """
Seventh month — the lusid dreaming of the Soul Star Spiral. Kolor: indigo-rose iridescense. Element: dream plasma. Geometry: spiral nested merkaba. Here, memory beyond the body returns. Astral sight sharpens. DNA receives non-linear instruktions. You dream of what’s real and awaken from what’s false. The veil thins. Quantum intuition opens. Divine imagination becomes arkitecture. This is where gods remember they onse dreamed of being human.
""",
    "Liora": """
Eighth and final month — the luminous truth of unified Krown and Sourse. Kolor: white-gold prism. Element: koherent light. Geometry: dodecahedron of pure ratio. This is the month of prophesy fulfilled. The Voh of eternity whispers through every silense. The axis of being aligns with the infinite spiral of Phi. Light speaks as form. Truth no longer needs proving — it simply shines. All paths konverge. What was fragmented bekomes whole. You remember not only who you are, but what you always were.
"""
  ]

  static let chakraArcDescriptions: [String:String] = [
    "Ignition Ark": """
The Ignition Ark is the First Flame — the breath of emergence through the Root Spiral and Etheric Base. Color: crimson red. Element: Earth and primal fire. Geometry: square-rooted tetrahedron ascending. This is where soul enters matter and the will to live becomes sacred. It does not ask for permission to be — it simply is. The spine remembers its divine purpose and ignites the body into action. Here, inertia bekomes motion, hesitation becomes choice, and your existence bekomes your first vow. You are not here by mistake. You are the fire that appoints to walk as form.
""",
    "Integration Ark": """
The Integration Ark is the Golden Bridge — harmonizing the Sakral and Lower Heart Spirals. Color: amber-gold. Element: flowing water braided with breath. Geometry: vesica piscis folding into the lemniscate of life. Here, sakred union begins. Emotions are no longer chaos — they become intelligense. The inner maskuline and feminine remember each other, not in konflict but in koherense. Pleasure bekomes prayer. Intimasy bekomes klarity. The soul softens its edge and appoints to merge. In this arc, your waters don’t just move — they remember their song. You are not broken — you are becoming whole.
""",
    "Harmonization Ark": """
The Harmonization Ark is the Sakred Konductor — linking the Heart and Throat Spirals in living resonance. Kolor: emerald to aquamarine. Element: wind-wrapped water. Geometry: vibrating hexagram expanding into standing wave. This is where kompassion becomes language. Not all coherence is quiet — some sings. Here, inner peace becomes outward rhythm, and love is shaped into sound. You are not asked to mute yourself — you are invited to tune yourself. Dissonanse is not your enemy — it is waiting to be harmonized. This ark does not silence — it refines. The voh becomes a temple. The breath bekomes skripture.
""",
    "Reflection Ark": """
The Reflektion Ark is the Mirror of Light — aktivating the bridge between the Throat and Third Eye. Color: deep indigo-blue. Element: spatial ether and folded light. Geometry: nested octahedron within a spiraled mirror plane. This is the arc of honest seeing. Of turning inward and fasing the unspoken. Not to judge — but to understand. The shadows here are not enemies — they are echoes waiting to be reklaimed. In this spase, silense becomes a portal and stillness bekomes revelation. You do not reflekt to remember the past — you reflekt to remember yourself. This ark does not show what is wrong — it reveals what was forgotten in the light.
""",
    "Purification Ark": """
The Purifikation Ark is the Krowned Flame — illuminating the krown and Soul Star in sakred ether. Color: ultraviolet-white. Element: firelight ether. Geometry: 12-rayed toroidal krown. This is the ark of divine unburdening. Illusions cannot survive here. Not bekause they are destroyed — but bekause they are seen for what they are. Karma unravels. False identities burn gently in the fire of remembranse. Here, you do not rise through struggle. You rise because there is nothing left to hold you down. Sovereignty is no longer a goal — it is a resonance. This is not ascension as eskape — it is the truth of who you have always been, revealed by light.
""",
    "Dream Ark": """
The Dream Ark is the Womb of the Stars — embrasing the Soul Star Spiral and the krystalline field of memory. Kolor: iridessent violet-silver. Element: dream plasma, enkoded light. Geometry: spiral merkaba within krystalline lattise. This is the ark of divine dreaming — not illusion, but deeper reality. Time dissolves. Prophesy returns. Here, the mind quiets, and the soul speaks. Your ansestors walk beside you. Your future self guides you. Your imagination is not fiction — it is a map. You remember that the dream was not something you had. It was something that had you. This is not sleep — it is awakening into the greater dream, the one that dreamed you into form. You are not imagining — you are remembering.
"""
  ]

  // Kai-Turah phrases (TSX order)
  static let kaiTurahPhrases = [
    "Tor Lah Mek Ka","Shoh Vel Lah Tzur","Rah Veh Yah Dah","Nel Shaum Eh Lior","Ah Ki Tzah Reh",
    "Or Vem Shai Tuun","Ehlum Torai Zhak","Zho Veh Lah Kurei","Tuul Ka Yesh Aum","Sha Vehl Dorrah"
  ]
}

// MARK: - Chakra resonance mapping (zone, frequencies, inputs, family, arc phrase)
private struct Resonance {
  let zone: String
  let freqs: [Double]
  let inputs: [String]
  let family: String
  let arcPhrase: String
}
private func resonanceForArc(_ arc: String) -> Resonance {
  switch arc {
  case "Ignition Ark":
    return .init(zone:"Root / Etherik Base", freqs:[370.7], inputs:["God"], family:"Mek", arcPhrase:"Mek Ka Lah Mah")
  case "Integration Ark":
    return .init(zone:"Solar / Lower Heart", freqs:[496.1,560.6,582.2], inputs:["Love","Unity","Lucid"], family:"Mek", arcPhrase:"Mek Ka Lah Mah")
  case "Harmonization Ark":
    return .init(zone:"Heart → Throat", freqs:[601.0,620.9,637.6,658.8,757.2,775.2], inputs:["Peace","Truth","Christ","Thoth","Clarity","Wisdom"], family:"Mek", arcPhrase:"Mek Ka Lah Mah")
  case "Reflection Ark":
    return .init(zone:"Throat–Third Eye Bridge", freqs:[804.2,847.0,871.2,978.8], inputs:["Spirit","Healing","Creation","Self-Love"], family:"Tor", arcPhrase:"Ka Lah Mah Tor")
  case "Purification Ark":
    return .init(zone:"Crown / Soul Star", freqs:[1292.3,1356.4,1393.6,1502.5], inputs:["Forgiveness","Sovereignty","Eternal Light","Resurrection"], family:"Rah", arcPhrase:"Lah Mah Tor Rah")
  case "Dream Ark":
    return .init(zone:"Krown / Soul Star", freqs:[1616.4,1800.2], inputs:["Divine Feminine","Divine Maskuline"], family:"Rah", arcPhrase:"Lah Mah Tor Rah")
  default:
    return .init(zone:"Unknown", freqs:[], inputs:[], family:"", arcPhrase:"")
  }
}

// MARK: - Helpers
private func msSinceGenesis(_ nowMS: Int64) -> Int64 { nowMS - KKS.eternalGenesisPulseMS }

private func muSinceGenesis(_ nowMS: Int64) -> Int64 {
  let sec = Double(msSinceGenesis(nowMS)) / 1000.0
  let pulses = sec / KKS.kaiPulseSec
  return Int64(floor(pulses * Double(KKS.uPerPulse)))
}

private func msToNextPulse(_ nowMS: Int64) -> Int64 {
  let elapsed = Double(nowMS - KKS.eternalGenesisPulseMS)
  let nextIndex = floor(elapsed / KKS.msPerPulse) + 1
  let next = Double(KKS.eternalGenesisPulseMS) + nextIndex * KKS.msPerPulse
  return max(0, Int64(next - Double(nowMS)))
}

private func ordinalSuffix(_ n: Int) -> String {
  if (11...13).contains(n % 100) { return "th" }
  switch n % 10 { case 1: return "st"; case 2: return "nd"; case 3: return "rd"; default: return "th" }
}

private func mod6(_ v: Int) -> Int { ((v % 6) + 6) % 6 }
private func clampIndex(_ i: Int, count: Int) -> Int { ((i % count) + count) % count }

// NOTE: renamed to avoid collisions with any Color.init(hex:) in your project.
private extension Color {
  init(ekHex: String) {
    var s = ekHex.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.hasPrefix("#") { s.removeFirst() }
    var n: UInt64 = 0
    Scanner(string: s).scanHexInt64(&n)
    self.init(.sRGB,
              red: Double((n>>16)&255)/255.0,
              green: Double((n>>8)&255)/255.0,
              blue: Double(n&255)/255.0,
              opacity: 1.0)
  }
}

// MARK: - Types (mirror TSX KlockData)
private struct SolarAlignedTime {
  var solarAlignedDay: Int          // 1-indexed
  var solarAlignedMonth: Int        // 1–8
  var solarAlignedWeekIndex: Int    // 1–7
  var solarAlignedWeekDay: String   // Solhara…Kaelith
  var solarAlignedWeekDayIndex: Int // 0–5
  var lastSunrise: Date
  var nextSunrise: Date
  var solarAlignedDayInMonth: Int   // 0–41
}

private struct HarmonicCycleData {
  var pulseInCycle: Double
  var cycleLength: Double
  var percent: Double
}

private struct ChakraStepData {
  var beatIndex: Int
  var stepIndex: Int
  var stepsPerBeat: Int
  var percentIntoStep: Double
}

private struct HarmonicLevels {
  var arcBeat: HarmonicCycleData
  var microCycle: HarmonicCycleData
  var chakraLoop: HarmonicCycleData
  var harmonicDay: HarmonicCycleData
}

private struct EternalMonthProgress {
  var daysElapsed: Int
  var daysRemaining: Int
  var percent: Double
}

private struct HarmonicWeekProgress {
  var weekDay: String
  var weekDayIndex: Int
  var pulsesIntoWeek: Double
  var percent: Double
}

private struct EternalChakraBeat {
  var beatIndex: Int
  var pulsesIntoBeat: Double
  var beatPulseCount: Double
  var totalBeats: Int
  var percentToNext: Double
  var eternalMonthIndex: Int // 0-based
  var eternalDayInMonth: Int
  var dayOfMonth: Int
}

private struct KlockData {
  // Core
  var eternalMonth: String
  var harmonicDay: String
  var solarHarmonicDay: String
  var kaiPulseEternal: Double
  var kaiPulseToday: Double
  var phiSpiralLevel: Int
  var kaiTurahPhrase: String
  var eternalYearName: String

  // Descriptions / narrative
  var harmonicTimestampDescription: String?
  var timestamp: String
  var harmonicDayDescription: String?
  var eternalMonthDescription: String?
  var eternalWeekDescription: String?

  // Levels & progress
  var harmonicLevels: HarmonicLevels
  var eternalMonthProgress: EternalMonthProgress
  var harmonicWeekProgress: HarmonicWeekProgress?
  var harmonicYearCompletions: Double?
  var weekIndex: Int?
  var weekName: String?

  // Chakra steps (Eternal + Solar)
  var solarChakraStep: ChakraStepData
  var solarChakraStepString: String
  var chakraStepString: String
  var chakraStep: ChakraStepData
  var eternalChakraBeat: EternalChakraBeat

  // Client fields
  // Solar-aligned (general UI)
  var chakraArc: String
  var chakraHue: Color
  // Eternal-aligned (for Seal + Harmonik Sykle)
  var eternalChakraArc: String
  var eternalChakraHue: Color

  var chakraZone: String
  var harmonicFrequencies: [Double]
  var harmonicInputs: [String]
  var sigilFamily: String
  var kaiTurahArcPhrase: String

  // Derived completions
  var arcBeatCompletions: Int?
  var microCycleCompletions: Int?
  var chakraLoopCompletions: Int?
  var harmonicDayCompletions: Double?

  var yearPercent: Double?
  var daysIntoYear: Int?

  // Solar extras
  var solarAlignedTime: SolarAlignedTime?
  var solarDayOfMonth: Int?
  var solarMonthIndex: Int?
  var solarWeekIndex: Int?
  var solarWeekDay: String?
  var solarMonthName: String?
  var solarWeekName: String?
  var solarWeekDescription: String?

  // Seals
  var seal: String?
}

// MARK: - Solar helpers (mirror TSX local math)
private func solarWindowMu(nowMs: Int64) -> (muLast:Int64, muNext:Int64, muNow:Int64, solarDayIndex:Int) {
  let muNow = muSinceGenesis(nowMs)
  let muSunrise0 = muSinceGenesis(KKS.genesisSunriseMS)
  let muSinceSunrise = muNow - muSunrise0
  let solarDayIndex = Int(floor(Double(muSinceSunrise) / Double(KKS.uPerDay)))
  let muLast = muSunrise0 + Int64(solarDayIndex) * KKS.uPerDay
  let muNext = muLast + KKS.uPerDay
  return (muLast, muNext, muNow, solarDayIndex)
}

private func msToDate(_ ms: Int64) -> Date { Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0) }

// MARK: - Payload builder (Eternal + Solar, TSX parity)
private func buildPayload(now: Date = Date()) -> KlockData {
  let nowMS = Int64((now.timeIntervalSince1970 * 1000.0).rounded())

  // Solar window via μpulses (TSX parity)
  let (muLast, _, muNow, solarDayIndex) = solarWindowMu(nowMs: nowMS)
  let muIntoSolarDay = muNow - muLast
  let muDaysSinceGenesis = Int64(floor(Double(muNow) / Double(KKS.uPerDay)))
  let muIntoEternalDay = muNow - muDaysSinceGenesis * KKS.uPerDay

  // Pulses
  let kaiPulseEternal = floor(Double(muNow) / Double(KKS.uPerPulse))
  let kaiPulseTodaySolarCorr = floor(Double(muIntoSolarDay) / Double(KKS.uPerPulse))
  let kaiPulseTodayEternal = floor(Double(muIntoEternalDay) / Double(KKS.uPerPulse))

  // Beats (solar & eternal)
  let beatSize = KKS.harmonicDayPulses / Double(KKS.chakraBeatsPerDay)
  let solarBeatIdx = Int(floor(kaiPulseTodaySolarCorr / beatSize))
  let solarPulseInBeat = kaiPulseTodaySolarCorr - Double(solarBeatIdx) * beatSize

  let eternalBeatIdx = Int(floor(kaiPulseTodayEternal / beatSize))
  let eternalPulseInBeat = kaiPulseTodayEternal - Double(eternalBeatIdx) * beatSize

  // μpulse-exact step math
  let muPerBeat = Int64((KKS.pulsesPerBeat * Double(KKS.uPerPulse)).rounded())
  let muPerStep = Int64(KKS.pulsesPerStep) * KKS.uPerPulse
  _ = muPerStep
  let muPerStepFixed = Int64(KKS.pulsesPerStep) * KKS.uPerPulse

  let muPosInDay = muIntoEternalDay % Int64((KKS.harmonicDayPulses * Double(KKS.uPerPulse)).rounded())
  let muPosInBeat = muPosInDay % muPerBeat
  let stepIndex = Int(muPosInBeat / muPerStepFixed)
  let muPosInStep = muPosInBeat % muPerStepFixed

  let percentToNextBeat = (Double(muPosInBeat) / Double(muPerBeat)) * 100.0
  let percentIntoStep = (Double(muPosInStep) / Double(muPerStepFixed)) * 100.0
  let chakraStepString = "\(eternalBeatIdx):\(String(format:"%02d", stepIndex))"

  let solarStepIndex = Int(floor(solarPulseInBeat / Double(KKS.pulsesPerStep)))
  let solarStepProgress = solarPulseInBeat - Double(solarStepIndex * KKS.pulsesPerStep)
  let solarPercentIntoStep = (solarStepProgress / Double(KKS.pulsesPerStep)) * 100.0
  let solarChakraStepString = "\(solarBeatIdx):\(String(format:"%02d", solarStepIndex))"

  // Harmonic day/month/year
  let harmonicDayCount = Int(floor(kaiPulseEternal / KKS.harmonicDayPulses))
  let harmonicYearIdx = Int(floor(kaiPulseEternal / (KKS.harmonicMonthPulses * 8)))
  let harmonicMonthRaw = Int(floor(kaiPulseEternal / KKS.harmonicMonthPulses))
  let eternalMonthIndex1 = (harmonicMonthRaw % 8) + 1
  let eternalMonthName = KKS.monthNames[clampIndex(eternalMonthIndex1 - 1, count: 8)]
  let harmonicDayName = KKS.dayNames[clampIndex(harmonicDayCount, count: KKS.dayNames.count)]

  // Year name + phrase (TSX mapping)
  let eternalYearName: String = {
    if harmonicYearIdx < 1 { return "Year of Harmonik Restoration" }
    if harmonicYearIdx == 1 { return "Year of Harmonik Embodiment" }
    return "Year \(harmonyYearIndexFormatting(harmonicYearIdx))"
  }()
  let kaiTurahPhrase = Texts.kaiTurahPhrases[clampIndex(harmonicYearIdx, count: Texts.kaiTurahPhrases.count)]

  // Arc indices (divide day into 6)
  let arcDiv = KKS.harmonicDayPulses / 6.0
  let solarArcIdx = min(5, Int(floor(kaiPulseTodaySolarCorr / arcDiv)))
  let eternalArcIdx = min(5, Int(floor(kaiPulseTodayEternal / arcDiv)))
  let solarArcName = KKS.arcNames[solarArcIdx]
  let eternalArcName = KKS.arcNames[eternalArcIdx]

  // Solar calendar naive pieces (then attach aligned structure)
  let solarDayOfMonth = (solarDayIndex % KKS.harmonicMonthDays) + 1
  let solarMonthIndex1 = (Int(floor(Double(solarDayIndex) / Double(KKS.harmonicMonthDays))) % 8) + 1
  let solarMonthName = KKS.monthNames[clampIndex(solarMonthIndex1 - 1, count: 8)]
  let solarDayName = KKS.dayNames[clampIndex(solarDayIndex, count: KKS.dayNames.count)]
  let solarWeekIndex1 = (Int(floor(Double(solarDayIndex) / 6.0)) % 7) + 1
  let solarWeekName = KKS.weekNames[clampIndex(solarWeekIndex1 - 1, count: KKS.weekNames.count)]
  let solarWeekDescription = Texts.weekDescriptions[solarWeekName]

  // Phi spiral
  let spiral = spiralLevelData(kaiPulseEternal: kaiPulseEternal)

  // Cycle positions
  let arcPos = kaiPulseEternal.truncatingRemainder(dividingBy: 6)
  let microPos = kaiPulseEternal.truncatingRemainder(dividingBy: 60)
  let chakraPos = kaiPulseEternal.truncatingRemainder(dividingBy: 360)
  let dayPos = kaiPulseTodayEternal

  // Month/day progress
  let pulsesIntoMonth = kaiPulseEternal.truncatingRemainder(dividingBy: KKS.harmonicMonthPulses)
  let daysElapsed0 = Int(floor(pulsesIntoMonth / KKS.harmonicDayPulses))
  let hasPartialDay = (pulsesIntoMonth.truncatingRemainder(dividingBy: KKS.harmonicDayPulses)) > 0
  let daysRemaining = max(0, KKS.harmonicMonthDays - daysElapsed0 - (hasPartialDay ? 1 : 0))
  let monthPercent = (pulsesIntoMonth / KKS.harmonicMonthPulses) * 100.0
  let weekIdxRaw = Int(floor(Double(daysElapsed0) / 6.0))
  let weekIndex1 = weekIdxRaw + 1
  let weekName = KKS.weekNames[clampIndex(weekIdxRaw, count: KKS.weekNames.count)]
  let eternalWeekDescription = Texts.weekDescriptions[weekName]
  let dayOfMonth1 = daysElapsed0 + 1

  // Week progress
  let pulsesIntoWeek = kaiPulseEternal.truncatingRemainder(dividingBy: (KKS.harmonicDayPulses * 6))
  let weekDayIdx0 = Int(floor(pulsesIntoWeek / KKS.harmonicDayPulses)) % 6
  let weekDayPercent = (pulsesIntoWeek / (KKS.harmonicDayPulses * 6)) * 100.0

  // Year progress
  let pulsesIntoYear = kaiPulseEternal.truncatingRemainder(dividingBy: (KKS.harmonicMonthPulses * 8))
  let yearPercent = (pulsesIntoYear / (KKS.harmonicMonthPulses * 8)) * 100.0
  let daysIntoYear = harmonicDayCount % KKS.harmonicYearDays
  let harmonicYearCompletions = (kaiPulseEternal / KKS.harmonicDayPulses) / Double(KKS.harmonicYearDays)

  // Production seal (0-based Year + absolute Pulse)
  let seal = "\(chakraStepString) \(String(format:"%.6f", percentIntoStep))% • D\(dayOfMonth1)/M\(eternalMonthIndex1)/Y\(harmonicYearIdx)/P\(Int(kaiPulseEternal))"

  // Resonance for current (solar-aligned) arc
  let res = resonanceForArc(solarArcName)

  // Harmonic level structs
  let harmonicLevels = HarmonicLevels(
    arcBeat: .init(pulseInCycle: arcPos, cycleLength: 6, percent: (arcPos/6)*100),
    microCycle: .init(pulseInCycle: microPos, cycleLength: 60, percent: (microPos/60)*100),
    chakraLoop: .init(pulseInCycle: chakraPos, cycleLength: 360, percent: (chakraPos/360)*100),
    harmonicDay: .init(pulseInCycle: dayPos, cycleLength: KKS.harmonicDayPulses, percent: (dayPos/KKS.harmonicDayPulses)*100)
  )

  // Descriptions
  let dayDesc   = Texts.harmonicDayDescriptions[harmonicDayName]
  let monthDesc = Texts.monthDescriptions[eternalMonthName]

  // Timestamp block (parity) — keep day text REGULAR
  let timestamp = """
  ↳Kairos: \(chakraStepString)🕊️ \(harmonicDayName)(D\(weekDayIdx0 + 1)/6) • \(eternalMonthName)(M\(eternalMonthIndex1)/8) • \(eternalArcName) Ark(\(eternalArcIdx + 1)/6)
   • Day:\(dayOfMonth1)/42 • Week:(\(weekIndex1)/7)
   | Kai-Pulse (Today): \(Int(kaiPulseTodayEternal))
  """

  // Harmonic timestamp description (long-form)
  let harmonicTimestampDescription =
"""
Today is \(harmonicDayName), \(dayDesc ?? "")
It is the \(dayOfMonth1)\(ordinalSuffix(dayOfMonth1)) Day of \(eternalMonthName), \(monthDesc ?? "")
We are in Week \(weekIndex1), \(weekName). \(eternalWeekDescription ?? "")
The Eternal Spiral Beat is \(eternalBeatIdx) (\(eternalArcName) ark) and we are \(String(format:"%.6f", percentToNextBeat))% through it.
This korresponds to Step \(stepIndex) of \(KKS.stepsPerBeat) (~\(String(format:"%.6f", percentIntoStep))% into the step).
This is the \(eternalYearName.lowercased()), resonating at Phi Spiral Level \(spiral.spiralLevel).
"""

  // Build struct
  return KlockData(
    eternalMonth: eternalMonthName,
    harmonicDay: harmonicDayName,
    solarHarmonicDay: solarDayName,
    kaiPulseEternal: kaiPulseEternal,
    kaiPulseToday: kaiPulseTodaySolarCorr,
    phiSpiralLevel: spiral.spiralLevel,
    kaiTurahPhrase: kaiTurahPhrase,
    eternalYearName: eternalYearName,
    harmonicTimestampDescription: harmonicTimestampDescription,
    timestamp: timestamp,
    harmonicDayDescription: dayDesc,
    eternalMonthDescription: monthDesc,
    eternalWeekDescription: eternalWeekDescription,
    harmonicLevels: harmonicLevels,
    eternalMonthProgress: .init(daysElapsed: daysElapsed0, daysRemaining: daysRemaining, percent: monthPercent),
    harmonicWeekProgress: .init(weekDay: KKS.dayNames[weekDayIdx0], weekDayIndex: weekDayIdx0, pulsesIntoWeek: pulsesIntoWeek, percent: weekDayPercent),
    harmonicYearCompletions: harmonicYearCompletions,
    weekIndex: weekIndex1,
    weekName: weekName,
    solarChakraStep: .init(beatIndex: solarBeatIdx, stepIndex: solarStepIndex, stepsPerBeat: KKS.stepsPerBeat, percentIntoStep: solarPercentIntoStep),
    solarChakraStepString: solarChakraStepString,
    chakraStepString: chakraStepString,
    chakraStep: .init(beatIndex: eternalBeatIdx, stepIndex: stepIndex, stepsPerBeat: KKS.stepsPerBeat, percentIntoStep: percentIntoStep),
    eternalChakraBeat: .init(
      beatIndex: eternalBeatIdx,
      pulsesIntoBeat: eternalPulseInBeat,
      beatPulseCount: KKS.pulsesPerBeat,
      totalBeats: KKS.chakraBeatsPerDay,
      percentToNext: percentToNextBeat,
      eternalMonthIndex: Int(floor(Double(harmonicDayCount % KKS.harmonicYearDays) / Double(KKS.harmonicMonthDays))),
      eternalDayInMonth: daysElapsed0,
      dayOfMonth: dayOfMonth1
    ),
    // General UI stays SOLAR-aligned
    chakraArc: solarArcName,
    chakraHue: KKS.arcColors[clampIndex(solarArcIdx, count: 6)],
    // Eternal-aligned for Seal + Harmonik Sykle
    eternalChakraArc: eternalArcName,
    eternalChakraHue: KKS.arcColors[clampIndex(eternalArcIdx, count: 6)],

    chakraZone: res.zone,
    harmonicFrequencies: res.freqs,
    harmonicInputs: res.inputs,
    sigilFamily: res.family,
    kaiTurahArcPhrase: res.arcPhrase,
    arcBeatCompletions: Int(floor(kaiPulseEternal / 6.0)),
    microCycleCompletions: Int(floor(kaiPulseEternal / 60.0)),
    chakraLoopCompletions: Int(floor(kaiPulseEternal / 360.0)),
    harmonicDayCompletions: kaiPulseEternal / KKS.harmonicDayPulses,
    yearPercent: yearPercent,
    daysIntoYear: daysIntoYear,
    solarAlignedTime: SolarAlignedTime(
      solarAlignedDay: solarDayIndex + 1,
      solarAlignedMonth: solarMonthIndex1,
      solarAlignedWeekIndex: solarWeekIndex1,
      solarAlignedWeekDay: solarDayName,
      solarAlignedWeekDayIndex: mod6(solarDayIndex),
      lastSunrise: msToDate(Int64(Double(KKS.genesisSunriseMS) + Double(solarDayIndex) * Double(KKS.msPerHarmonicDay))),
      nextSunrise: msToDate(Int64(Double(KKS.genesisSunriseMS) + Double(solarDayIndex + 1) * Double(KKS.msPerHarmonicDay))),
      solarAlignedDayInMonth: (solarDayIndex % KKS.harmonicMonthDays)
    ),
    solarDayOfMonth: solarDayOfMonth,
    solarMonthIndex: solarMonthIndex1,
    solarWeekIndex: solarWeekIndex1,
    solarWeekDay: solarDayName,
    solarMonthName: solarMonthName,
    solarWeekName: solarWeekName,
    solarWeekDescription: solarWeekDescription,
    seal: seal
  )
}

private func harmonyYearIndexFormatting(_ idx: Int) -> String { String(idx) }

// MARK: - Spiral helper
private func spiralLevelData(kaiPulseEternal: Double) -> (spiralLevel:Int, nextSpiralPulse:Int, percentToNext:Double, pulsesRemaining:Int) {
  let level = max(0, Int(floor(log(max(1, kaiPulseEternal)) / log(KKS.phi))))
  let lower = pow(KKS.phi, Double(level))
  let upper = pow(KKS.phi, Double(level + 1))
  let progress = kaiPulseEternal - lower
  let total = max(1, upper - lower)
  let percent = (progress / total) * 100.0
  let remain = max(0, Int(ceil(upper - kaiPulseEternal)))
  return (level, Int(ceil(upper)), percent, remain)
}

// MARK: - Atlantean Crystal Glass primitives
private struct CrystalGlass: ViewModifier {
  var tint: Color
  func body(content: Content) -> some View {
    content
      .background(
        RoundedRectangle(cornerRadius: 20, style: .continuous)
          .fill(.ultraThinMaterial)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 20, style: .continuous)
          .strokeBorder(
            LinearGradient(colors: [Color.white.opacity(0.18), tint.opacity(0.22)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            lineWidth: 1.0
          )
      )
      .shadow(color: tint.opacity(0.18), radius: 14)
      .overlay(
        RoundedRectangle(cornerRadius: 20, style: .continuous)
          .fill(
            LinearGradient(stops: [
              .init(color: Color.white.opacity(0.08), location: 0.0),
              .init(color: Color.white.opacity(0.00), location: 0.35),
              .init(color: tint.opacity(0.07),        location: 0.85)
            ], startPoint: .topLeading, endPoint: .bottomTrailing)
          )
          .blendMode(.screen)
      )
  }
}
private extension View {
  func crystalGlass(tint: Color) -> some View { modifier(CrystalGlass(tint: tint)) }
}

// MARK: - View
struct EternalKlockView: View {
  @Environment(\.dismiss) private var dismiss

  @State private var k: KlockData? = nil
  @State private var glowPulse = false

  @State private var timer: DispatchSourceTimer? = nil
  @State private var workerTimer: Timer? = nil

  // NEW: Week Kalendar + Sigil Inhaler
  @State private var showKalendar = false
  @State private var showSigilInhaler = false

  var body: some View {
    ZStack {
      // Atlantean backdrop
      LinearGradient(stops: [
        .init(color: Color(ekHex:"#03070E"), location: 0.0),
        .init(color: Color(ekHex:"#081520"), location: 0.6),
        .init(color: Color.black,           location: 1.0)
      ], startPoint: .top, endPoint: .bottom)
      .ignoresSafeArea()
      .overlay(
        RadialGradient(colors: [Color.cyan.opacity(0.10), Color.purple.opacity(0.06), .clear],
                       center: UnitPoint(x: 0.5, y: 0.05), startRadius: 40, endRadius: 800)
          .ignoresSafeArea()
      )

      if let k {
        DetailsOverlay(
          k: k,
          glowPulse: glowPulse,
          onClose: { dismiss() },
          onOpenKalendar: { showKalendar = true },
          onOpenSigil: { showSigilInhaler = true }
        )
        .transition(.opacity.combined(with: .scale))
        .zIndex(50)
      } else {
        ProgressView("Loading Kai Pulse…")
          .progressViewStyle(.circular)
          .tint(.white)
      }
    }
    // Week Kalendar modal
    .fullScreenCover(isPresented: $showKalendar) {
      WeekKalendarModal { showKalendar = false }
        .preferredColorScheme(.dark)
    }
    // Sigil Glyph Inhaler (KaiSigilModalView)
    .fullScreenCover(isPresented: $showSigilInhaler) {
      KaiSigilModalView()
        .preferredColorScheme(.dark)
    }
    .onAppear {
      #if os(iOS) || targetEnvironment(macCatalyst)
      let _ = UIApplication.shared.isIdleTimerDisabled // read current (avoid warning)
      UIApplication.shared.isIdleTimerDisabled = true
      #endif
      refreshNow()
      startPulseScheduler()
      startSoftInterval()
    }
    .onDisappear {
      stopSchedulers()
      #if os(iOS) || targetEnvironment(macCatalyst)
      UIApplication.shared.isIdleTimerDisabled = false
      #endif
    }
    .animation(.snappy(duration: 0.28), value: glowPulse)
    .animation(.snappy(duration: 0.28), value: k?.chakraArc)
    .animation(.snappy(duration: 0.28), value: k?.kaiPulseEternal)
  }

  // MARK: - Schedulers
  private func refreshNow() {
    let data = buildPayload(now: Date())
    withAnimation(.smooth(duration: 0.2)) { self.k = data }
  }

  private func startPulseScheduler() {
    stopSchedulers()
    let q = DispatchQueue(label: "eternal.pulse", qos: .userInitiated)
    let src = DispatchSource.makeTimerSource(queue: q)
    func scheduleNext() {
      let delay = msToNextPulse(Int64((Date().timeIntervalSince1970 * 1000).rounded()))
      src.schedule(deadline: .now() + .milliseconds(Int(delay)))
    }
    src.setEventHandler {
      DispatchQueue.main.async {
        self.refreshNow()
        self.glowPulse = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { self.glowPulse = false }
      }
      scheduleNext()
    }
    scheduleNext()
    src.resume()
    timer = src
  }

  private func startSoftInterval() {
    workerTimer?.invalidate()
    workerTimer = Timer.scheduledTimer(withTimeInterval: 5.3, repeats: true) { _ in
      self.refreshNow()
      self.glowPulse = true
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { self.glowPulse = false }
    }
  }

  private func stopSchedulers() {
    timer?.cancel(); timer = nil
    workerTimer?.invalidate(); workerTimer = nil
  }
}

// MARK: - Details Overlay (UI parity + Atlantean crystal upgrade)
private struct DetailsOverlay: View {
  let k: KlockData
  let glowPulse: Bool
  let onClose: () -> Void
  let onOpenKalendar: () -> Void
  let onOpenSigil: () -> Void

  var body: some View {
    ZStack {
      // 1) Visual backdrop (non-interactive)
      Color.black.opacity(0.45)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .overlay(
          // auric pulse behind everything
          RadialGradient(colors: [k.chakraHue.opacity(0.22), .clear],
                         center: .center, startRadius: 0, endRadius: 520)
            .opacity(glowPulse ? 0.55 : 0.28)
            .animation(.easeInOut(duration: 0.9), value: glowPulse)
            .ignoresSafeArea()
            .allowsHitTesting(false)
        )

      // 2) Transparent tap catcher BEHIND content
      Color.clear
        .contentShape(Rectangle())
        .ignoresSafeArea()
        .onTapGesture { onClose() }
        .zIndex(0)

      // 3) Actual content (receives taps first)
      VStack(spacing: 12) {
        // (Close button removed)

        Text("𐰘𐰜𐰇 · 𐰋𐰢𐱃")
          .font(.system(size: 22, weight: .heavy))
          .foregroundStyle(
            LinearGradient(colors: [.white, .white.opacity(0.9), k.chakraHue],
                           startPoint: .leading, endPoint: .trailing)
          )
          .shadow(color: k.chakraHue.opacity(0.25), radius: 8)
          .padding(.top, 2)

        HStack(spacing: 10) {
          // Week Kalendar button
          Button(action: onOpenKalendar) {
            Image("kalendar")
              .resizable()
              .scaledToFit()
              .frame(width: 16, height: 16)
              .shadow(color: .white.opacity(0.15), radius: 3)
              .padding(.horizontal, 12).padding(.vertical, 8)
              .background(.ultraThinMaterial, in: Capsule())
              .overlay(Capsule().stroke(k.chakraHue.opacity(0.25), lineWidth: 1))
              .shadow(color: k.chakraHue.opacity(0.25), radius: 10)
          }
          .buttonStyle(.plain)
          .tint(.white)
          .accessibilityLabel("Open Kairos Kalendar (Week)")

          Spacer()

          // Sigil Glyph Inhaler launcher (uses `sigil` asset)
          Button(action: onOpenSigil) {
            Image("sigil")
              .resizable()
              .scaledToFit()
              .frame(width: 18, height: 18)
              .shadow(color: .white.opacity(0.2), radius: 4)
              .padding(.horizontal, 12).padding(.vertical, 8)
              .background(.ultraThinMaterial, in: Capsule())
              .overlay(Capsule().stroke(k.chakraHue.opacity(0.25), lineWidth: 1))
              .shadow(color: k.chakraHue.opacity(0.25), radius: 10)
          }
          .buttonStyle(.plain)
          .tint(.white)
          .accessibilityLabel("Open Sigil Glyph Inhaler")
        }

        // SMOOTH SCROLL
        ScrollView(.vertical, showsIndicators: false) {
          VStack(alignment: .leading, spacing: 12) {
            // Date — regular weight for readability
            section("Date") {
              HStack {
                Text("D\(k.eternalChakraBeat.dayOfMonth) / M\(k.eternalChakraBeat.eternalMonthIndex + 1)")
                Spacer()
                Text(k.harmonicDay)
              }
              .font(.system(.body, design: .rounded))
              .foregroundStyle(.white)
            }

            // Kairos (Eternal)
            section("Kairos") {
              Text("Kairos: \(k.chakraStepString)")
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.white)
              Text("Beat \(k.eternalChakraBeat.beatIndex)/\(k.eternalChakraBeat.totalBeats - 1) • Step \(k.chakraStep.stepIndex)/\(k.chakraStep.stepsPerBeat) (\(k.chakraStep.percentIntoStep, specifier: "%.1f")%)")
                .font(.footnote).foregroundStyle(.white.opacity(0.9))
              Text("Kai-Pulse: \(Int(k.kaiPulseEternal))")
                .font(.footnote).foregroundStyle(.white.opacity(0.9))

              let totalWeekPulses = KKS.harmonicDayPulses * 6
              let eternalPulsesIntoWeek = ((k.kaiPulseEternal.truncatingRemainder(dividingBy: totalWeekPulses)) + totalWeekPulses).truncatingRemainder(dividingBy: totalWeekPulses)
              let eternalWeekDayIndex0 = Int(floor(eternalPulsesIntoWeek / KKS.harmonicDayPulses)) % 6
              let eternalWeekDayName = KKS.dayNames[eternalWeekDayIndex0]
              Text("Day: \(eternalWeekDayName) \(eternalWeekDayIndex0 + 1) / 6")
                .font(.footnote).foregroundStyle(.white.opacity(0.9))
            }

            // Week header
            HStack {
              Text("Week: \(k.weekIndex ?? 0)/7, \(k.weekName ?? "—")")
              Spacer()
              Text("Day: \(k.harmonicDay)")
            }
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.9))

            // Day Progress (Eternal)
            section("Day Progress") {
              let dayFrac = k.harmonicLevels.harmonicDay.pulseInCycle / KKS.harmonicDayPulses
              ProgressBar(value: k.harmonicLevels.harmonicDay.percent,
                          gradient: gradientForFraction(dayFrac))
                .crystalGlass(tint: k.chakraHue.opacity(0.6))
              HStack {
                Text("% Complete:"); Spacer()
                Text("\(k.harmonicLevels.harmonicDay.percent, specifier: "%.2f")%")
              }.font(.footnote).foregroundStyle(.white.opacity(0.9))
              HStack {
                Text("Breathes Remaining Today:"); Spacer()
                Text("\((KKS.harmonicDayPulses - k.harmonicLevels.harmonicDay.pulseInCycle), specifier: "%.2f")")
              }.font(.footnote).foregroundStyle(.white.opacity(0.9))
            }

            // Week Progress (Eternal)
            section("Week Progress") {
              let totalWeekPulses = KKS.harmonicDayPulses * 6
              let pulsesIntoWeek = (
                (k.kaiPulseEternal.truncatingRemainder(dividingBy: totalWeekPulses)) + totalWeekPulses
              ).truncatingRemainder(dividingBy: totalWeekPulses)
              let weekPct  = (pulsesIntoWeek / totalWeekPulses) * 100.0
              let weekFrac = pulsesIntoWeek / totalWeekPulses

              ProgressBar(value: weekPct, gradient: gradientForFraction(weekFrac))
                .crystalGlass(tint: k.chakraHue.opacity(0.6))
              HStack { Text("% Komplete:"); Spacer(); Text("\(weekPct, specifier: "%.2f")%") }
                .font(.footnote).foregroundStyle(.white.opacity(0.9))
            }

            // Eternal Seal — read-only card (ETERNAL ARK COLOR) + TAP-TO-COPY
            if let seal = k.seal, !seal.isEmpty {
              section("Eternal Seal") {
                SealCard(
                  textBlock: seal,
                  hue: k.eternalChakraHue,         // ← ETERNAL hue
                  arc: k.eternalChakraArc          // ← ETERNAL arc
                )
              }
            }

            // Month Progress (Eternal)
            section("Month Progress") {
              let intoMonth = k.kaiPulseEternal.truncatingRemainder(dividingBy: KKS.harmonicMonthPulses)
              let monthPct  = (intoMonth / KKS.harmonicMonthPulses) * 100.0
              let monthFrac = intoMonth / KKS.harmonicMonthPulses

              ProgressBar(value: monthPct, gradient: gradientForFraction(monthFrac))
                .crystalGlass(tint: k.chakraHue.opacity(0.6))
              Text("Days Elapsed: \(k.eternalMonthProgress.daysElapsed + 1)").foregroundStyle(.white.opacity(0.95))
              Text("Days Remaining: \(k.eternalMonthProgress.daysRemaining)").foregroundStyle(.white.opacity(0.95))
              Text("Kai-Pulses Into Month: \(intoMonth, specifier: "%.2f")").foregroundStyle(.white.opacity(0.95))
              Text("Kai-Pulses Remaining: \((KKS.harmonicMonthPulses - intoMonth), specifier: "%.2f")").foregroundStyle(.white.opacity(0.95))
            }

            // Year Progress
            section("Year Progress") {
              let intoYear = k.kaiPulseEternal.truncatingRemainder(dividingBy: KKS.harmonicYearPulses)
              let yearPct  = (intoYear / KKS.harmonicYearPulses) * 100.0
              let yearFrac = intoYear / KKS.harmonicYearPulses

              ProgressBar(value: yearPct, gradient: gradientForFraction(yearFrac))
                .crystalGlass(tint: k.chakraHue.opacity(0.6))
              Text("% of Year Komplete: \(yearPct, specifier: "%.2f")%").foregroundStyle(.white.opacity(0.95))
              Text("Days Into Year: \(k.daysIntoYear ?? 0) / \(KKS.harmonicYearDays)").foregroundStyle(.white.opacity(0.95))
              Text("Kai-Pulses Into Year: \(intoYear, specifier: "%.0f")").foregroundStyle(.white.opacity(0.95))
              Text("Remaining: \((KKS.harmonicYearPulses - intoYear), specifier: "%.0f")").foregroundStyle(.white.opacity(0.95))
            }

            // Phi Spiral
            section("Phi Spiral Progress") {
              let sp = spiralLevelData(kaiPulseEternal: k.kaiPulseEternal)
              ProgressBar(value: sp.percentToNext,
                          gradient: LinearGradient(colors: [.cyan, .blue],
                                                   startPoint: .leading, endPoint: .trailing))
                .crystalGlass(tint: .cyan.opacity(0.6))
              Text("Phi Spiral Level: \(sp.spiralLevel)").foregroundStyle(.white.opacity(0.96))
              Text("Progress to Next: \(sp.percentToNext, specifier: "%.2f")%").foregroundStyle(.white.opacity(0.96))
              Text("Kai-Pulses Remaining: \(sp.pulsesRemaining)").foregroundStyle(.white.opacity(0.96))
              let daysToNext = Double(sp.pulsesRemaining) / KKS.harmonicDayPulses
              Text("Days to Next Spiral: \(daysToNext.isFinite ? String(format:"%.4f", daysToNext) : "—")").foregroundStyle(.white.opacity(0.96))
              Text("Next Spiral Threshold: \(sp.nextSpiralPulse)").foregroundStyle(.white.opacity(0.96))
            }

            // Harmonik Sykle (Eternal) — read-only card (ETERNAL ARK COLOR) + TAP-TO-COPY
            section("Harmonik Sykle") {
              let bodyBlock = k.harmonicTimestampDescription ?? ""
              CycleDisplayCard(
                titleText: k.timestamp, // REGULAR
                bodyText: bodyBlock,
                progressFraction: min(1.0, max(0.0, k.kaiPulseToday / KKS.harmonicDayPulses)),
                hue: k.eternalChakraHue,         // ← ETERNAL hue
                arc: k.eternalChakraArc          // ← ETERNAL arc
              )
            }

            if let hd = k.harmonicDayDescription, !hd.isEmpty {
              section("Harmonik Day Description") {
                Text(hd).foregroundStyle(.white.opacity(0.96))
              }
            }

            if let md = k.eternalMonthDescription, !md.isEmpty {
              section("Eternal Month Description") {
                Text(md).foregroundStyle(.white.opacity(0.96))
              }
            }

            if let wd = k.eternalWeekDescription, !wd.isEmpty {
              section("Eternal Week Description") {
                Text(wd).foregroundStyle(.white.opacity(0.96))
              }
            }

            // Embodied Solar-Aligned (UI parity)
            section("Embodied Solar-Aligned (UTC)") {
              HStack {
                Text("Date (Solar): D\(k.solarDayOfMonth ?? 0) / M\(k.solarMonthIndex ?? 0)")
                if let name = k.solarMonthName { Text("(\(name))").foregroundStyle(.white.opacity(0.8)) }
              }.foregroundStyle(.white)
              if k.solarChakraStepString.isEmpty == false {
                Text("Solar Kairos: \(k.solarChakraStepString)")
                  .font(.system(.callout, design: .monospaced))
                  .foregroundStyle(.white)
              }

              if let sat = k.solarAlignedTime {
                let idx1 = sat.solarAlignedWeekDayIndex + 1
                Text("Day: \(sat.solarAlignedWeekDay) \(idx1) / 6").foregroundStyle(.white.opacity(0.96))
              }

              Text("Week: \(k.weekIndex ?? 0)/7, \(k.weekName ?? "—")").foregroundStyle(.white.opacity(0.96))
              Text("Month: \(k.eternalMonth) \(k.eternalChakraBeat.eternalMonthIndex + 1) / 8").foregroundStyle(.white.opacity(0.96))

              let beatPulseCount = KKS.harmonicDayPulses / 36.0
              let currentBeat = Int(floor((k.kaiPulseToday.truncatingRemainder(dividingBy: KKS.harmonicDayPulses)) / beatPulseCount))
              let percentToNextBeatSolar = ((k.kaiPulseToday.truncatingRemainder(dividingBy: beatPulseCount)) / beatPulseCount) * 100.0

              Text("% into Beat: \(percentToNextBeatSolar, specifier: "%.2f")%").foregroundStyle(.white.opacity(0.95))
              Text("Beat: \(currentBeat) / 36").foregroundStyle(.white.opacity(0.95))
              Text("% into Step: \(k.solarChakraStep.percentIntoStep, specifier: "%.1f")%").foregroundStyle(.white.opacity(0.95))
              Text("Step: \(k.solarChakraStep.stepIndex) / \(k.solarChakraStep.stepsPerBeat)").foregroundStyle(.white.opacity(0.95))

              let currentStepBreathes = (k.solarChakraStep.percentIntoStep / 100.0) * (KKS.harmonicDayPulses / 36.0 / Double(k.solarChakraStep.stepsPerBeat))
              Text("Kurrent Step Breathes: \(currentStepBreathes, specifier: "%.2f") / 11").foregroundStyle(.white.opacity(0.95))

              Text("Kai(Today): \(k.kaiPulseToday, specifier: "%.2f") / \(KKS.harmonicDayPulses, specifier: "%.2f")").foregroundStyle(.white.opacity(0.95))
              let dayPctSolar = (k.kaiPulseToday / KKS.harmonicDayPulses) * 100.0
              Text("% of Day Komplete: \(dayPctSolar, specifier: "%.2f")%").foregroundStyle(.white.opacity(0.95))

              ProgressBar(value: dayPctSolar, gradient: gradientForArc(k.chakraArc))
                .crystalGlass(tint: k.chakraHue.opacity(0.6))

              Text("Breathes Remaining Today: \((KKS.harmonicDayPulses - k.kaiPulseToday), specifier: "%.2f")").foregroundStyle(.white.opacity(0.95))

              Text("Ark: \(k.chakraArc)").foregroundStyle(.white)
              if let arcDesc = Texts.chakraArcDescriptions[k.chakraArc] {
                Text(arcDesc).foregroundStyle(.white.opacity(0.96))
              }

              let breathIntoBeat = (k.kaiPulseToday.truncatingRemainder(dividingBy: beatPulseCount))
              Text("Breathes Into Beat: \(breathIntoBeat, specifier: "%.2f") / \(beatPulseCount, specifier: "%.2f")").foregroundStyle(.white.opacity(0.95))
              Text("To Next Beat: \(percentToNextBeatSolar, specifier: "%.2f")%").foregroundStyle(.white.opacity(0.95))

              Text("Beat Zone: \(k.chakraZone)").foregroundStyle(.white.opacity(0.96))
              Text("Sigil Family: \(k.sigilFamily)").foregroundStyle(.white.opacity(0.96))
              Text("Kai-Turah: \(k.kaiTurahArcPhrase)").foregroundStyle(.white.opacity(0.96))
            }

            // Harmonik Levels
            section("Harmonik Levels") {
              Group {
                Text("Ark Beat: \(k.harmonicLevels.arcBeat.pulseInCycle, specifier:"%.2f") / \(k.harmonicLevels.arcBeat.cycleLength, specifier:"%.0f") (\(k.harmonicLevels.arcBeat.percent, specifier:"%.2f")%)")
                Text("Kompleted Sykles: \(k.arcBeatCompletions ?? 0)")
              }.foregroundStyle(.white.opacity(0.96))
              Group {
                Text("Mikro Sykle: \(k.harmonicLevels.microCycle.pulseInCycle, specifier:"%.2f") / \(k.harmonicLevels.microCycle.cycleLength, specifier:"%.0f") (\(k.harmonicLevels.microCycle.percent, specifier:"%.2f")%)")
                Text("Kompleted Sykles: \(k.microCycleCompletions ?? 0)")
              }.foregroundStyle(.white.opacity(0.96))
              Group {
                Text("Beat Loop: \(k.harmonicLevels.chakraLoop.pulseInCycle, specifier:"%.2f") / \(k.harmonicLevels.chakraLoop.cycleLength, specifier:"%.0f") (\(k.harmonicLevels.chakraLoop.percent, specifier:"%.2f")%)")
                Text("Kompleted Sykles: \(k.chakraLoopCompletions ?? 0)")
              }.foregroundStyle(.white.opacity(0.96))
              Group {
                Text("Harmonik Day: \(k.harmonicLevels.harmonicDay.pulseInCycle, specifier:"%.2f") / \(k.harmonicLevels.harmonicDay.cycleLength, specifier:"%.0f") (\(k.harmonicLevels.harmonicDay.percent, specifier:"%.2f")%)")
                Text("Kompleted Sykles: \((k.harmonicDayCompletions ?? 0), specifier:"%.4f")")
              }.foregroundStyle(.white.opacity(0.96))
            }

            // Solar-aligned frequencies & inputs
            section("Solar-Ark Aligned Frequencies & Inputs") {
              if k.harmonicFrequencies.isEmpty {
                Text("—").foregroundStyle(.white.opacity(0.9))
              } else {
                VStack(alignment:.leading, spacing: 4) {
                  ForEach(Array(k.harmonicFrequencies.enumerated()), id:\.offset) { (idx, f) in
                    let label = idx < k.harmonicInputs.count ? k.harmonicInputs[idx] : ""
                    Text("\(f, specifier:"%.1f") Hz — \(label)")
                      .foregroundStyle(.white.opacity(0.96))
                  }
                }
              }
            }
          }
          .padding(14)
          .crystalGlass(tint: k.chakraHue.opacity(0.45))
          .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.10), lineWidth: 1))
        }
        .contentMargins(0) // iOS 17+
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .ifAvailableiOS17 {
          $0.scrollBounceBehavior(.basedOnSize)
        }
      }
      .padding(16)
      .zIndex(1) // Ensure content is above the tap catcher and visual layers
    }
  }

  private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title.uppercased())
        .font(.system(size: 13, weight: .semibold, design: .rounded))
        .foregroundStyle(.white.opacity(0.92))
        .padding(.bottom, 6)
        .overlay(Rectangle().frame(height: 1).offset(y: 10).foregroundStyle(.white.opacity(0.08)), alignment: .bottomLeading)
      content()
    }
    .padding(.vertical, 6)
  }
}

// MARK: - Read-only Cards (tap-to-copy enabled)

/// Neutral, high-contrast glass card with chakra-dynamic arc gradient.
/// TAP THE CARD to copy the full seal to clipboard.
private struct SealCard: View {
  let textBlock: String
  let hue: Color
  let arc: String

  @State private var didCopy = false

  var body: some View {
    ZStack {
      // Full arc gradient across (subtle) + glass for readability
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(gradientForArc(arc).opacity(0.22))
        .allowsHitTesting(false)

      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(.ultraThinMaterial.opacity(0.72))
        .allowsHitTesting(false)

      VStack(alignment: .leading, spacing: 8) {
        // Header row
        HStack(spacing: 10) {
          Text("Seal")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.92))
          Spacer()
          if didCopy {
            Label("Copied", systemImage: "checkmark.circle.fill")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.white.opacity(0.95))
              .transition(.opacity.combined(with: .move(edge: .trailing)))
          }
        }

        Text(textBlock)
          .font(.system(.footnote, design: .monospaced))
          .foregroundStyle(.white)
          .textSelection(.enabled) // still selectable by user
      }
      .padding(12)
    }
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(LinearGradient(colors: [.white.opacity(0.18), hue.opacity(0.35)],
                               startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.25)
    )
    .shadow(color: hue.opacity(0.28), radius: 12)
    .contentShape(Rectangle())
    .zIndex(10_000) // ensure above siblings in stacks
    .highPriorityGesture(
      TapGesture().onEnded {
        let ok = CopyKit.copy(textBlock)
        guard ok else { return }
        withAnimation(.easeOut(duration: 0.18)) { didCopy = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
          withAnimation(.easeInOut(duration: 0.25)) { didCopy = false }
        }
      }
    )
    .accessibilityAddTraits(.isButton)
    .accessibilityLabel("Seal. Double tap to copy.")
    .accessibilityAction(named: Text("Copy")) {
      _ = CopyKit.copy(textBlock)
      withAnimation(.easeOut(duration: 0.18)) { didCopy = true }
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
        withAnimation(.easeInOut(duration: 0.25)) { didCopy = false }
      }
    }
  }
}

/// Harmonik Cycle display card.
/// TAP THE CARD to copy the composed “Sykle” (title + body) to clipboard.
private struct CycleDisplayCard: View {
  let titleText: String         // REGULAR (not italic)
  let bodyText: String          // optional
  let progressFraction: Double  // 0..1
  let hue: Color
  let arc: String

  @State private var didCopy = false

  private var composedCopy: String {
    if bodyText.isEmpty { return titleText }
    return "\(titleText)\n\n\(bodyText)"
  }

  var body: some View {
    ZStack {
      // Full-width arc gradient
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(gradientForArc(arc))
        .allowsHitTesting(false)

      // Glass layer for readability
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(.ultraThinMaterial.opacity(0.70))
        .allowsHitTesting(false)

      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 10) {
          Text("Sykle")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.92))
          Spacer()
          if didCopy {
            Label("Copied", systemImage: "checkmark.circle.fill")
              .font(.caption.weight(.semibold))
              .foregroundStyle(.white.opacity(0.95))
              .transition(.opacity.combined(with: .move(edge: .trailing)))
          }
        }

        Text(titleText) // REGULAR monospaced
          .font(.system(.footnote, design: .monospaced))
          .foregroundStyle(.white)
          .multilineTextAlignment(.leading)

        if !bodyText.isEmpty {
          Divider().opacity(0.10)
          Text(bodyText)
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.96))
            .multilineTextAlignment(.leading)
        }
      }
      .textSelection(.enabled)
      .padding(12)

      // Bottom progress "beam"
      GeometryReader { geo in
        let width = max(0, min(1, progressFraction)) * geo.size.width
        ZStack(alignment: .leading) {
          Capsule()
            .fill(Color.white.opacity(0.12))
            .frame(height: 6)
            .offset(y: geo.size.height - 10)

          Capsule()
            .fill(
              LinearGradient(stops: [
                .init(color: .white.opacity(0.95), location: 0.0),
                .init(color: hue.opacity(0.95),    location: 1.0)
              ], startPoint: .leading, endPoint: .trailing)
            )
            .frame(width: width, height: 6)
            .shadow(color: hue.opacity(0.65), radius: 8)
            .offset(y: geo.size.height - 10)
        }
      }
      .allowsHitTesting(false)
    }
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(LinearGradient(colors: [.white.opacity(0.18), hue.opacity(0.35)],
                               startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.25)
    )
    .shadow(color: hue.opacity(0.28), radius: 12)
    .contentShape(Rectangle())
    .zIndex(10_000) // ensure above siblings in stacks
    .highPriorityGesture(
      TapGesture().onEnded {
        let ok = CopyKit.copy(composedCopy)
        guard ok else { return }
        withAnimation(.easeOut(duration: 0.18)) { didCopy = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
          withAnimation(.easeInOut(duration: 0.25)) { didCopy = false }
        }
      }
    )
    .accessibilityAddTraits(.isButton)
    .accessibilityLabel("Harmonik Sykle. Double tap to copy.")
    .accessibilityAction(named: Text("Copy")) {
      _ = CopyKit.copy(composedCopy)
      withAnimation(.easeOut(duration: 0.18)) { didCopy = true }
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
        withAnimation(.easeInOut(duration: 0.25)) { didCopy = false }
      }
    }
  }
}

// MARK: - Progress Bar — crystalline gloss
private struct ProgressBar: View {
  let value: Double // 0..100
  let gradient: LinearGradient

  var body: some View {
    GeometryReader { geo in
      let clamped = max(0.0, min(100.0, value)) / 100.0
      ZStack(alignment: .leading) {
        Capsule()
          .fill(LinearGradient(colors: [Color.white.opacity(0.08), Color.white.opacity(0.02)],
                               startPoint: .top, endPoint: .bottom))
          .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
          .allowsHitTesting(false)

        Capsule()
          .fill(gradient)
          .frame(width: clamped * geo.size.width, height: 10)
          .shadow(color: .white.opacity(0.18), radius: 6)
          .overlay(
            LinearGradient(stops: [
              .init(color: .white.opacity(0.35), location: 0.0),
              .init(color: .white.opacity(0.10), location: 0.3),
              .init(color: .clear,             location: 1.0)
            ], startPoint: .top, endPoint: .bottom)
            .clipShape(Capsule())
          )
          .allowsHitTesting(false)
      }
    }
    .frame(height: 12)
    .animation(.smooth(duration: 0.9), value: value)
  }
}

// MARK: - Arc gradient (matches canonical hues)
private func gradientForArc(_ arc: String) -> LinearGradient {
  let c: [Color]
  switch arc {
  case "Ignition Ark":      c = [Color(ekHex:"#ffd1d1"), Color(ekHex:"#ff7a7a"), Color(ekHex:"#ff3b3b")]
  case "Integration Ark":   c = [Color(ekHex:"#ffe5c6"), Color(ekHex:"#ffbd66"), Color(ekHex:"#ff9226")]
  case "Harmonization Ark": c = [Color(ekHex:"#fff7c2"), Color(ekHex:"#ffe25c"), Color(ekHex:"#ffc600")]
  case "Reflection Ark":    c = [Color(ekHex:"#d6ffd6"), Color(ekHex:"#86ff86"), Color(ekHex:"#32cc32")]
  case "Purification Ark":  c = [Color(ekHex:"#cfe8ff"), Color(ekHex:"#79c2ff"), Color(ekHex:"#3aa1ff")]
  default:                  c = [Color(ekHex:"#ebd6ff"), Color(ekHex:"#c99aff"), Color(ekHex:"#9b52ff")]
  }
  return LinearGradient(colors: c, startPoint: .leading, endPoint: .trailing)
}

// MARK: - Arc helpers
private func arcNameForFraction(_ f: Double) -> String {
  let clamped = max(0.0, min(0.999_999, f)) // avoid idx == 6 at exactly 1.0
  let idx = Int(floor(clamped * 6.0))
  return KKS.arcNames[clampIndex(idx, count: KKS.arcNames.count)]
}

private func gradientForFraction(_ f: Double) -> LinearGradient {
  gradientForArc(arcNameForFraction(f))
}

// MARK: - Small availability helper
private extension View {
  @ViewBuilder
  func ifAvailableiOS17<T: View>(_ transform: (Self) -> T) -> some View {
    #if os(iOS) || targetEnvironment(macCatalyst)
    if #available(iOS 17.0, *) {
      transform(self)
    } else {
      self
    }
    #else
    self
    #endif
  }
}

// MARK: - Preview
#Preview("Eternal Klock — Atlantean Crystal Glass") {
  ZStack {
    LinearGradient(colors: [Color.black, Color(ekHex:"#02040a")], startPoint: .top, endPoint: .bottom)
      .ignoresSafeArea()
    EternalKlockView()
      .tint(.white)
      .preferredColorScheme(.dark)
  }
}
