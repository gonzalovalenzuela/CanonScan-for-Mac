// ImageTools.swift
// Utilidades de imagen compartidas por la app y el puente AirScan.
// Image helpers shared by the app and the AirScan bridge.

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum ImageTools {
    /// Decodifica un JPEG / Decodes a JPEG
    static func decode(_ jpeg: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(jpeg as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    /// Convierte a un canal de gris real / Converts to a true single gray channel
    static func toGray(_ img: CGImage) -> CGImage? {
        if img.colorSpace?.model == .monochrome { return img }
        guard let space = CGColorSpace(name: CGColorSpace.genericGrayGamma2_2),
              let ctx = CGContext(data: nil, width: img.width, height: img.height,
                                  bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: img.height))
        return ctx.makeImage()
    }

    /// Recorta una zona dada en 1/300 de pulgada (unidades eSCL).
    /// Crops a region given in 1/300 inch (eSCL units).
    static func crop(_ img: CGImage, dpi: Int, x: Int, y: Int, width: Int, height: Int) -> CGImage {
        let k = Double(dpi) / 300
        let rect = CGRect(x: Double(x) * k, y: Double(y) * k, width: Double(width) * k, height: Double(height) * k)
            .integral
            .intersection(CGRect(x: 0, y: 0, width: img.width, height: img.height))
        guard !rect.isEmpty, rect.size != CGSize(width: img.width, height: img.height) else { return img }
        return img.cropping(to: rect) ?? img
    }

    /// Codifica en JPEG con los dpi indicados / Encodes as JPEG with the given dpi
    static func jpeg(_ img: CGImage, dpi: Int, quality: Double = 0.9) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        let props: [CFString: Any] = [
            kCGImagePropertyDPIWidth: dpi,
            kCGImagePropertyDPIHeight: dpi,
            kCGImageDestinationLossyCompressionQuality: quality,
        ]
        CGImageDestinationAddImage(dest, img, props as CFDictionary)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }
}
