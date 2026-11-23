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

    /// Blanco y negro de 1 bit con umbral automático (Otsu).
    /// 1-bit black and white with automatic threshold (Otsu).
    static func toBW(_ img: CGImage) -> CGImage? {
        guard let gray = toGray(img) else { return nil }
        let w = gray.width, h = gray.height
        // Copia en gris de 8 bits / 8-bit gray copy
        var px = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.draw(gray, in: CGRect(x: 0, y: 0, width: w, height: h))

        // Umbral de Otsu sobre el histograma / Otsu threshold over the histogram
        var hist = [Int](repeating: 0, count: 256)
        for v in px { hist[Int(v)] += 1 }
        let total = Double(px.count)
        let sumAll = (0..<256).reduce(0.0) { $0 + Double($1 * hist[$1]) }
        var sumB = 0.0, wB = 0.0, best = 0.0, threshold = 128
        for t in 0..<256 {
            wB += Double(hist[t])
            if wB == 0 { continue }
            let wF = total - wB
            if wF == 0 { break }
            sumB += Double(t * hist[t])
            let mB = sumB / wB, mF = (sumAll - sumB) / wF
            let between = wB * wF * (mB - mF) * (mB - mF)
            if between > best { best = between; threshold = t }
        }

        // Empaqueta a 1 bit: 1 = blanco / Pack to 1 bit: 1 = white
        let rowBytes = (w + 7) / 8
        var bits = [UInt8](repeating: 0, count: rowBytes * h)
        for y in 0..<h {
            let src = y * w, dst = y * rowBytes
            for x in 0..<w where Int(px[src + x]) > threshold {
                bits[dst + x / 8] |= 0x80 >> UInt8(x % 8)
            }
        }
        guard let provider = CGDataProvider(data: Data(bits) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 1, bitsPerPixel: 1, bytesPerRow: rowBytes,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
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
