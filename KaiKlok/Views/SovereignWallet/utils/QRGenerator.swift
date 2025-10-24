//
//  QRGenerator.swift
//  KaiKlok
//
//  Created by BJ Klock on 10/15/25.
//

import UIKit
import CoreImage.CIFilterBuiltins

struct QRGenerator {
    
    static func generateQR<T: Encodable>(_ object: T, size: CGFloat = 240) -> UIImage? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        
        guard let jsonData = try? encoder.encode(object),
              let jsonString = String(data: jsonData, encoding: .utf8)
        else { return nil }

        return generateQR(from: jsonString, size: size)
    }

    static func generateQR(from string: String, size: CGFloat = 240) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        let data = Data(string.utf8)

        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let ciImage = filter.outputImage else { return nil }
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: size / ciImage.extent.size.width,
                                                               y: size / ciImage.extent.size.height))

        if let cgImage = context.createCGImage(scaled, from: scaled.extent) {
            return UIImage(cgImage: cgImage)
        }

        return nil
    }
}
