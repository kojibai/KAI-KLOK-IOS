//
//  FilesIO.swift
//  KaiKlok
//
//  Created by BJ Klock on 10/16/25.
//

//
//  FilesIO.swift
//  KaiKlok
//

import Foundation

public func safeFilename(_ base: String) -> String {
    let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
    return base.components(separatedBy: invalid).joined(separator: "_")
}

public func pulseFilename(_ prefix: String, _ sigilPulse: Int, _ second: Int) -> String {
    "\(safeFilename(prefix))_\(sigilPulse)_\(second)"
}
