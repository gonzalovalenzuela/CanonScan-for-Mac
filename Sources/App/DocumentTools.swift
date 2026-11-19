// DocumentTools.swift
// Correcciones de documento (enderezar, recortar), unión de dos mitades y
// PDF con texto buscable. Usa Vision y Core Image de macOS, sin dependencias.
// Document fixes (deskew, crop), two-half stitching and searchable-text PDF.
// Uses macOS Vision and Core Image, no dependencies.

import AppKit
import CoreImage
import CoreText
import Vision

enum DocumentTools {
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // MARK: - Enderezar y recortar / Deskew and crop

    /// Aplica las correcciones pedidas; si no detecta el documento, devuelve la imagen tal cual.
    /// Applies the requested fixes; if no document is detected, returns the image unchanged.
    static func correct(_ img: CGImage, deskew: Bool, crop: Bool) -> CGImage {
        guard deskew || crop, let quad = detectQuad(img) else { return img }
        let ci = CIImage(cgImage: img)
        let output: CIImage?
        if crop {
            // Recorta al documento y corrige perspectiva / Crop to the document and fix perspective
            let f = CIFilter(name: "CIPerspectiveCorrection")!
            f.setValue(ci, forKey: kCIInputImageKey)
            f.setValue(CIVector(cgPoint: quad.topLeft), forKey: "inputTopLeft")
            f.setValue(CIVector(cgPoint: quad.topRight), forKey: "inputTopRight")
            f.setValue(CIVector(cgPoint: quad.bottomLeft), forKey: "inputBottomLeft")
            f.setValue(CIVector(cgPoint: quad.bottomRight), forKey: "inputBottomRight")
            output = f.outputImage
        } else {
            // Solo gira según el borde superior, sin recortar / Only rotate by the top edge, no crop
            let angle = atan2(quad.topRight.y - quad.topLeft.y, quad.topRight.x - quad.topLeft.x)
            guard abs(angle) > 0.002, abs(angle) < 0.35 else { return img }   // 0,1° a 20° / 0.1° to 20°
            let center = CGPoint(x: ci.extent.midX, y: ci.extent.midY)
            let rotated = ci.transformed(by: CGAffineTransform(translationX: center.x, y: center.y)
                .rotated(by: -angle).translatedBy(x: -center.x, y: -center.y))
            output = rotated.composited(over: CIImage(color: .white).cropped(to: ci.extent)).cropped(to: ci.extent)
        }
        guard let out = output, let cg = ciContext.createCGImage(out, from: out.extent.integral) else { return img }
        return cg
    }

    private struct Quad { var topLeft, topRight, bottomLeft, bottomRight: CGPoint }

    /// Busca el rectángulo del documento o foto / Finds the document or photo rectangle
    private static func detectQuad(_ img: CGImage) -> Quad? {
        let req = VNDetectRectanglesRequest()
        req.maximumObservations = 1
        req.minimumSize = 0.15
        req.minimumConfidence = 0.6
        req.quadratureTolerance = 25
        req.minimumAspectRatio = 0.2
        try? VNImageRequestHandler(cgImage: img, options: [:]).perform([req])
        guard let r = req.results?.first else { return nil }
        // Si ocupa casi toda la imagen, no hay nada que recortar / Nearly full-frame: nothing to crop
        let area = r.boundingBox.width * r.boundingBox.height
        guard area < 0.97 else { return nil }
        let w = CGFloat(img.width), h = CGFloat(img.height)
        func p(_ n: CGPoint) -> CGPoint { CGPoint(x: n.x * w, y: n.y * h) }
        return Quad(topLeft: p(r.topLeft), topRight: p(r.topRight), bottomLeft: p(r.bottomLeft), bottomRight: p(r.bottomRight))
    }

    // MARK: - Unir / Stitch

    /// Une dos mitades: la segunda se escanea con el original girado 180°.
    /// Joins two halves: the second is scanned with the original turned 180°.
    static func stitch(_ first: CGImage, _ second: CGImage) -> CGImage? {
        let w = first.width + second.width, h = max(first.height, second.height)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: first.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            ?? CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        ctx.setFillColor(.white)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.draw(first, in: CGRect(x: 0, y: h - first.height, width: first.width, height: first.height))
        // Segunda mitad girada 180° / Second half rotated 180°
        ctx.saveGState()
        ctx.translateBy(x: CGFloat(w), y: CGFloat(h))
        ctx.rotate(by: .pi)
        ctx.draw(second, in: CGRect(x: 0, y: 0, width: second.width, height: second.height))
        ctx.restoreGState()
        return ctx.makeImage()
    }

    // MARK: - PDF con texto buscable / Searchable PDF

    /// Escribe un PDF; con `ocr`, agrega una capa de texto invisible y buscable.
    /// Writes a PDF; with `ocr`, adds an invisible, searchable text layer.
    static func writePDF(pages: [(image: CGImage, dpi: Int)], to url: URL, ocr: Bool) throws {
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let ctx = CGContext(consumer: consumer, mediaBox: nil, nil) else { throw CocoaError(.fileWriteUnknown) }
        for p in pages {
            // Tamaño físico: píxeles × 72 / dpi / Physical size: px × 72 / dpi
            var box = CGRect(x: 0, y: 0, width: CGFloat(p.image.width) * 72 / CGFloat(p.dpi),
                             height: CGFloat(p.image.height) * 72 / CGFloat(p.dpi))
            ctx.beginPage(mediaBox: &box)
            ctx.draw(p.image, in: box)
            if ocr { drawInvisibleText(for: p.image, in: box, ctx) }
            ctx.endPage()
        }
        ctx.closePDF()
    }

    private static func drawInvisibleText(for img: CGImage, in box: CGRect, _ ctx: CGContext) {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = true
        req.recognitionLanguages = ["es-ES", "en-US"]
        try? VNImageRequestHandler(cgImage: img, options: [:]).perform([req])
        guard let results = req.results else { return }
        ctx.saveGState()
        ctx.setTextDrawingMode(.invisible)
        for obs in results {
            guard let text = obs.topCandidates(1).first?.string, !text.isEmpty else { continue }
            let r = obs.boundingBox
            let rect = CGRect(x: box.minX + r.minX * box.width, y: box.minY + r.minY * box.height,
                              width: r.width * box.width, height: r.height * box.height)
            guard rect.height > 1, rect.width > 1 else { continue }
            // Ajusta el texto al ancho detectado / Fit the text to the detected width
            let font = CTFontCreateWithName("Helvetica" as CFString, rect.height * 0.85, nil)
            let attr = NSAttributedString(string: text, attributes: [.font: font])
            let line = CTLineCreateWithAttributedString(attr)
            let width = CTLineGetTypographicBounds(line, nil, nil, nil)
            guard width > 0 else { continue }
            ctx.saveGState()
            ctx.textMatrix = .identity
            ctx.translateBy(x: rect.minX, y: rect.minY + rect.height * 0.15)
            ctx.scaleBy(x: rect.width / CGFloat(width), y: 1)
            ctx.textPosition = .zero
            CTLineDraw(line, ctx)
            ctx.restoreGState()
        }
        ctx.restoreGState()
    }
}
