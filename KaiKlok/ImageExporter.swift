//  ImageExporter.swift
//  KaiKlok
//
//  Created by BJ Klock on 9/13/25.
//  Exact-export utilities for PNG (SwiftUI View → image bytes) and SVG (via SVGBuilder).
//
//  v1.0.1
//  - Fix: MainActor isolation violation from default args using UIScreen.main.scale.
//         Use `scale: CGFloat? = nil` and resolve inside @MainActor methods.
//

import SwiftUI
import UniformTypeIdentifiers
import UIKit

public enum ImageExporter {

    // MARK: - PNG (SwiftUI View → Data)

    /// Renders a SwiftUI view to PNG data.
    /// - Parameters:
    ///   - view: The SwiftUI view to render.
    ///   - size: Output canvas size in points.
    ///   - scale: Pixel scale (defaults to device scale if `nil`).
    ///   - background: Optional background color to composite under the view (default = clear).
    /// - Returns: PNG-encoded data or `nil` if rendering failed.
    @MainActor
    public static func png<V: View>(
        of view: V,
        size: CGSize,
        scale: CGFloat? = nil,
        background: UIColor? = nil
    ) -> Data? {
        let resolvedScale = scale ?? UIScreen.main.scale

        if #available(iOS 16.0, *) {
            let content = view
                .frame(width: size.width, height: size.height)
                .background(Color(background ?? .clear))
            let renderer = ImageRenderer(content: content)
            renderer.scale = resolvedScale
            // Prefer cgImage (faster, no alpha premult issues), fall back to uiImage
            if let cg = renderer.cgImage { return UIImage(cgImage: cg).pngData() }
            if let ui = renderer.uiImage { return ui.pngData() }
            return nil
        } else {
            // iOS 15 fallback: snapshot a UIHostingController’s view with UIGraphics renderer
            let host = UIHostingController(rootView:
                view
                    .frame(width: size.width, height: size.height)
                    .background(Color(background ?? .clear))
            )
            host.view.bounds = CGRect(origin: .zero, size: size)
            host.view.backgroundColor = background ?? .clear

            let format = UIGraphicsImageRendererFormat()
            format.scale = resolvedScale
            format.opaque = (background?.cgColor.alpha ?? 0) >= 1.0

            let renderer = UIGraphicsImageRenderer(size: size, format: format)
            let img = renderer.image { _ in
                // Ensure layout before draw
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            return img.pngData()
        }
    }

    // MARK: - SVG (Sigil → Data)

    /// Builds a self-contained SVG for the given sigil params, matching SigilView visuals.
    /// - Parameters:
    ///   - size: Output canvas size in px/SVG units.
    ///   - params: Your canonical SigilParams.
    ///   - options: SVG rendering options (sampling, stroke scale, glow).
    /// - Returns: UTF-8 SVG data.
    public static func svg(
        size: CGSize,
        params: SigilParams,
        options: SVGBuilder.Options = .init()
    ) -> Data {
        SVGBuilder.makeSVGData(size: size, params: params, options: options)
    }

    // MARK: - File Save Helpers

    /// Saves raw data to a temporary file with the correct extension for the given UTType.
    /// - Parameters:
    ///   - data: File contents.
    ///   - suggestedName: Basename without extension (e.g. "sigil_12345").
    ///   - utType: Uniform Type (e.g. .png, .svg).
    /// - Returns: File URL in the temporary directory.
    public static func save(
        _ data: Data,
        suggestedName: String,
        utType: UTType
    ) throws -> URL {
        let ext = utType.preferredFilenameExtension ?? {
            switch utType {
            case .png: return "png"
            case .jpeg: return "jpg"
            case .svg: return "svg"
            default: return "bin"
            }
        }()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(suggestedName).\(ext)")
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - One-shot writers (PNG/SVG → URL)

    /// Renders a SwiftUI view as PNG and writes it to a temporary file.
    /// - Returns: URL of the written PNG.
    @MainActor
    public static func writePNG<V: View>(
        of view: V,
        size: CGSize,
        scale: CGFloat? = nil,
        background: UIColor? = nil,
        suggestedName: String = "sigil"
    ) throws -> URL {
        guard let data = png(of: view, size: size, scale: scale, background: background) else {
            throw ExportError.renderFailed
        }
        return try save(data, suggestedName: suggestedName, utType: .png)
    }

    /// Builds the sigil SVG and writes it to a temporary file.
    /// - Returns: URL of the written SVG.
    public static func writeSVG(
        size: CGSize,
        params: SigilParams,
        options: SVGBuilder.Options = .init(),
        suggestedName: String = "sigil"
    ) throws -> URL {
        let data = svg(size: size, params: params, options: options)
        return try save(data, suggestedName: suggestedName, utType: .svg)
    }

    // MARK: - Share Sheet Convenience

    /// Presents a share sheet for the provided file URLs.
    /// - Note: Caller is responsible for keeping strong reference to the presented controller if needed.
    @MainActor
    public static func presentShareSheet(
        for items: [URL],
        from presenter: UIViewController,
        sourceView: UIView? = nil,
        completion: UIActivityViewController.CompletionWithItemsHandler? = nil
    ) {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let pop = vc.popoverPresentationController {
            pop.sourceView = sourceView ?? presenter.view
            pop.sourceRect = (sourceView?.bounds ?? presenter.view.bounds)
        }
        vc.completionWithItemsHandler = completion
        presenter.present(vc, animated: true)
    }

    // MARK: - Errors

    public enum ExportError: Error {
        case renderFailed
    }
}

// MARK: - UTType for SVG (if not present)

extension UTType {
    /// System UTType.svg exists on modern SDKs; define if missing for compatibility.
    public static var svg: UTType {
        if let t = UTType(filenameExtension: "svg") { return t }
        // Fallback dynamic declaration
        return UTType(importedAs: "public.svg-image")
    }
}
