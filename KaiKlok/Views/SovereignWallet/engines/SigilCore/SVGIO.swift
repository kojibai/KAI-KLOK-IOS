//
//  SVGIO.swift
//  KaiKlok
//
//  Created by BJ Klock on 10/16/25.
//

//
//  SVGIO.swift
//  KaiKlok
//

import Foundation
import UniformTypeIdentifiers
import WebKit
import UIKit

// Embed JSON metadata inside <metadata><![CDATA[...]]></metadata>
public func embedMetadata(svgString: String, meta: WVSigilMetadata) -> String {
    let enc = JSONEncoder()
    enc.outputFormatting = [.sortedKeys]
    let json = (try? enc.encode(meta)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    if let a = svgString.range(of: "<metadata><![CDATA["),
       let b = svgString.range(of: "]]></metadata>") {
        var s = svgString
        s.replaceSubrange(a.upperBound..<b.lowerBound, with: json)
        return s
    } else {
        let node = "<metadata><![CDATA[\(json)]]></metadata>"
        return svgString.replacingOccurrences(of: "</svg>", with: "\(node)</svg>")
    }
}

// Extract JSON back out (parity flags)
public func extractMeta(fromSVG svg: String) -> (raw: String, meta: WVSigilMetadata, contextOk: Bool, typeOk: Bool)? {
    guard let a = svg.range(of: "<metadata><![CDATA["),
          let b = svg.range(of: "]]></metadata>") else { return nil }
    let json = String(svg[a.upperBound..<b.lowerBound])
    guard let data = json.data(using: .utf8) else { return nil }
    let dec = JSONDecoder()
    guard let m = try? dec.decode(WVSigilMetadata.self, from: data) else { return nil }
    let ctxOK = (m.context ?? "").isEmpty || (m.context ?? "").lowercased().contains("sigil")
    let typeOK = (m.type ?? "").isEmpty || (m.type ?? "").lowercased().contains("sigil")
    return (json, m, ctxOK, typeOK)
}

// Optional PNG rasterizer (WKWebView snapshot)
public final class SVGRasterizer: NSObject, WKNavigationDelegate {
    public func rasterize(svgDataURL: URL, target: CGSize, completion: @escaping (Data?) -> Void) {
        let web = WKWebView(frame: CGRect(origin: .zero, size: target))
        web.navigationDelegate = self
        web.isOpaque = false
        web.backgroundColor = .clear
        web.load(URLRequest(url: svgDataURL))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let cfg = WKSnapshotConfiguration()
            cfg.rect = CGRect(origin: .zero, size: target)
            web.takeSnapshot(with: cfg) { image, _ in
                completion(image?.pngData())
            }
        }
    }
}

// Accept SVGs however iOS tags them
public extension UTType {
    static var svgCompat: UTType {
        if let t = UTType("public.svg-image") { return t }
        if let t = UTType(filenameExtension: "svg") { return t }
        return .xml
    }
}
