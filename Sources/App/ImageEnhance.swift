// ImageEnhance.swift
// Mejoras de imagen: blanquear fondo, brillo/contraste/nitidez, restaurar
// colores, orientación automática y detección de páginas en blanco.
// Image enhancements: whiten background, brightness/contrast/sharpness,
// color restoration, automatic orientation and blank page detection.

import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

/// Ajustes de imagen (por modo y para el escaneo manual).
/// Image adjustments (per mode and for manual scanning).
struct ImageAdjust: Codable, Equatable {
    var whitenBackground = false
    var autoOrient = false
    var skipBlank = false
    var restoreColors = false
    /// Separa varias fotos del vidrio en páginas distintas / Splits several photos into separate pages
    var splitPhotos = false
    /// −50 a +50 / −50 to +50
    var brightness = 0.0
    var contrast = 0.0
    var sharpness = 0.0

    init() {}

    /// Tolerante a claves faltantes / Tolerant of missing keys
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func get<T: Decodable>(_ k: CodingKeys, _ v: inout T) { if let x = try? c.decode(T.self, forKey: k) { v = x } }
        get(.whitenBackground, &whitenBackground); get(.autoOrient, &autoOrient); get(.skipBlank, &skipBlank)
        get(.restoreColors, &restoreColors); get(.brightness, &brightness); get(.contrast, &contrast)
        get(.sharpness, &sharpness); get(.splitPhotos, &splitPhotos)
    }

    var changesPixels: Bool {
        whitenBackground || restoreColors || brightness != 0 || contrast != 0 || sharpness != 0
    }
}

enum ImageEnhance {
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    // MARK: - Tono y color / Tone and color

    /// Aplica blanquear fondo, restaurar colores, brillo, contraste y nitidez.
    /// Applies whiten background, color restoration, brightness, contrast and sharpness.
    static func apply(_ img: CGImage, _ a: ImageAdjust) -> CGImage {
        guard a.changesPixels else { return img }
        var ci = CIImage(cgImage: img)
        let gray = img.colorSpace?.model == .monochrome

        if a.restoreColors && !gray {
            // Ajuste automático de Core Image + algo más de saturación
            // Core Image auto adjustment + a bit more saturation
            for f in ci.autoAdjustmentFilters(options: [.redEye: false]) {
                f.setValue(ci, forKey: kCIInputImageKey)
                if let out = f.outputImage { ci = out }
            }
            let sat = CIFilter.colorControls()
            sat.inputImage = ci; sat.saturation = 1.25
            ci = sat.outputImage ?? ci
        }

        if a.whitenBackground, let white = paperWhite(img) {
            // Estira los niveles para que el papel quede blanco y aclara el reverso que se transparenta.
            // Stretch levels so the paper turns white and lighten bleed-through.
            let scale = 1.0 / max(white, 0.5)
            let m = CIFilter.colorMatrix()
            m.inputImage = ci
            m.rVector = CIVector(x: scale, y: 0, z: 0, w: 0)
            m.gVector = CIVector(x: 0, y: scale, z: 0, w: 0)
            m.bVector = CIVector(x: 0, y: 0, z: scale, w: 0)
            ci = m.outputImage ?? ci
            let curve = CIFilter.toneCurve()
            curve.inputImage = ci
            curve.point0 = CGPoint(x: 0, y: 0)
            curve.point1 = CGPoint(x: 0.25, y: 0.2)
            curve.point2 = CGPoint(x: 0.5, y: 0.5)
            curve.point3 = CGPoint(x: 0.82, y: 0.97)
            curve.point4 = CGPoint(x: 1, y: 1)
            ci = curve.outputImage ?? ci
        }

        if a.brightness != 0 || a.contrast != 0 {
            let c = CIFilter.colorControls()
            c.inputImage = ci
            c.brightness = Float(a.brightness / 250)          // ±0,2
            c.contrast = Float(1 + a.contrast / 125)          // 0,6 a 1,4
            c.saturation = 1
            ci = c.outputImage ?? ci
        }

        if a.sharpness > 0 {
            let s = CIFilter.sharpenLuminance()
            s.inputImage = ci; s.sharpness = Float(a.sharpness / 50 * 0.9); s.radius = 1.5
            ci = s.outputImage ?? ci
        } else if a.sharpness < 0 {
            let b = CIFilter.gaussianBlur()
            b.inputImage = ci; b.radius = Float(-a.sharpness / 50 * 1.5)
            ci = b.outputImage?.cropped(to: CGRect(x: 0, y: 0, width: img.width, height: img.height)) ?? ci
        }

        let extent = CGRect(x: 0, y: 0, width: img.width, height: img.height)
        let space = gray ? CGColorSpace(name: CGColorSpace.genericGrayGamma2_2)! : CGColorSpace(name: CGColorSpace.sRGB)!
        let format: CIFormat = gray ? .L8 : .RGBA8
        return context.createCGImage(ci.cropped(to: extent), from: extent, format: format, colorSpace: space) ?? img
    }

    /// Nivel del papel: percentil 90 de luminancia (0–1) / Paper level: 90th luminance percentile (0–1)
    private static func paperWhite(_ img: CGImage) -> Double? {
        guard let hist = histogram(img) else { return nil }
        let total = hist.reduce(0, +)
        var acc = 0
        for (i, n) in hist.enumerated() {
            acc += n
            if Double(acc) >= Double(total) * 0.90 { return Double(i) / 255 }
        }
        return nil
    }

    /// Histograma de luminancia sobre una copia chica / Luminance histogram over a small copy
    private static func histogram(_ img: CGImage, side: Int = 256) -> [Int]? {
        let k = Double(side) / Double(max(img.width, img.height))
        let w = max(1, Int(Double(img.width) * k)), h = max(1, Int(Double(img.height) * k))
        var px = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        var hist = [Int](repeating: 0, count: 256)
        for v in px { hist[Int(v)] += 1 }
        return hist
    }

    // MARK: - Página en blanco / Blank page

    /// En blanco si casi no hay píxeles oscuros respecto del papel.
    /// Blank if there are almost no dark pixels relative to the paper.
    static func isBlank(_ img: CGImage) -> Bool {
        guard let hist = histogram(img, side: 400), let white = paperWhite(img) else { return false }
        let limit = max(0, Int(white * 255) - 60)        // claramente más oscuro que el papel
        let dark = hist[0..<max(limit, 1)].reduce(0, +)
        let total = hist.reduce(0, +)
        return Double(dark) / Double(total) < 0.002      // menos de 0,2 % / under 0.2 %
    }

    // MARK: - Orientación automática / Automatic orientation

    /// Gira la página según dónde Vision reconoce más texto (0°, 90°, 180°, 270°).
    /// Rotates the page to where Vision recognizes the most text (0°, 90°, 180°, 270°).
    static func autoOrient(_ img: CGImage) -> CGImage {
        let small = downscaled(img, maxSide: 1200) ?? img
        let orientations: [CGImagePropertyOrientation] = [.up, .right, .down, .left]
        var best: (CGImagePropertyOrientation, Double) = (.up, 0)
        for o in orientations {
            let req = VNRecognizeTextRequest()
            req.recognitionLevel = .fast
            req.usesLanguageCorrection = false
            try? VNImageRequestHandler(cgImage: small, orientation: o, options: [:]).perform([req])
            let score = (req.results ?? []).reduce(0.0) { acc, obs in
                guard let c = obs.topCandidates(1).first else { return acc }
                return acc + Double(c.confidence) * Double(c.string.count)
            }
            if score > best.1 { best = (o, score) }
        }
        // Solo gira si hay texto claro y conviene / Only rotate with clear text and a better result
        guard best.0 != .up, best.1 > 40 else { return img }
        let ci = CIImage(cgImage: img).oriented(best.0)
        return context.createCGImage(ci, from: ci.extent) ?? img
    }

    private static func downscaled(_ img: CGImage, maxSide: Int) -> CGImage? {
        let k = Double(maxSide) / Double(max(img.width, img.height))
        guard k < 1 else { return img }
        let w = Int(Double(img.width) * k), h = Int(Double(img.height) * k)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }
}
