//
//  SigilMetadata.swift
//  KaiKlok
//
//  Created by BJ Klock on 9/13/25.
//  NOTE: This file intentionally does NOT reference SigilParams.
//

import Foundation

public struct SigilMetadata: Codable, Equatable {
    public let pulse: Int
    public let beat: Int
    public let stepIndex: Int
    public let chakraDay: Int
    public let userPhiKey: String?
    public let kaiSignature: String?
    public let timestamp: Int

    public init(
        pulse: Int,
        beat: Int,
        stepIndex: Int,
        chakraDay: Int,
        userPhiKey: String?,
        kaiSignature: String?,
        timestamp: Int
    ) {
        self.pulse = pulse
        self.beat = beat
        self.stepIndex = stepIndex
        self.chakraDay = chakraDay
        self.userPhiKey = userPhiKey
        self.kaiSignature = kaiSignature
        self.timestamp = timestamp
    }

    /// JSON string (pretty = true for debug)
    public func jsonString(pretty: Bool = false) -> String {
        let enc = JSONEncoder()
        if pretty { enc.outputFormatting = [.prettyPrinted, .sortedKeys] }
        let data = (try? enc.encode(self)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
