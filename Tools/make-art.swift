// make-art.swift
// Genera el ícono de la app (.iconset) y los fondos del instalador.
// Generates the app icon (.iconset) and the installer backgrounds.
//
// Uso / Usage: swift make-art.swift <carpeta-salida> [imagen-instalador.png]

import AppKit
import CoreGraphics

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let installerImage: CGImage? = CommandLine.arguments.count > 2
    ? NSImage(contentsOfFile: CommandLine.arguments[2])?.cgImage(forProposedRect: nil, context: nil, hints: nil)
    : nil
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

/// Dibuja el ícono en un lienzo de lado `s` / Draws the icon on an `s`-sized canvas
func drawIcon(_ ctx: CGContext, _ s: CGFloat) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!

    // Forma base estilo macOS (cuadrado redondeado con margen) / macOS-style rounded square with margin
    let inset = s * 0.098
    let body = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = body.width * 0.225
    let squircle = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Sombra exterior / Drop shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: rgb(0, 0, 0, 0.35))
    ctx.addPath(squircle)
    ctx.setFillColor(rgb(20, 40, 80))
    ctx.fillPath()
    ctx.restoreGState()

    // Fondo con degradado azul profundo → turquesa / Deep blue → teal gradient
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()
    let bg = CGGradient(colorsSpace: space,
                        colors: [rgb(18, 52, 120), rgb(22, 104, 168), rgb(32, 178, 190)] as CFArray,
                        locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: body.minX, y: body.minY),
                           end: CGPoint(x: body.maxX, y: body.maxY), options: [])
    // Brillo superior suave / Soft top highlight
    let hl = CGGradient(colorsSpace: space,
                        colors: [rgb(255, 255, 255, 0.18), rgb(255, 255, 255, 0)] as CFArray,
                        locations: [0, 1])!
    ctx.drawLinearGradient(hl, start: CGPoint(x: 0, y: body.maxY),
                           end: CGPoint(x: 0, y: body.midY), options: [])

    // Hoja de papel / Paper sheet
    let pw = body.width * 0.50, ph = pw * 1.30
    let paper = CGRect(x: body.midX - pw / 2, y: body.midY - ph / 2 - body.height * 0.01, width: pw, height: ph)
    let fold = pw * 0.22
    let sheet = CGMutablePath()
    sheet.move(to: CGPoint(x: paper.minX, y: paper.minY))
    sheet.addLine(to: CGPoint(x: paper.maxX, y: paper.minY))
    sheet.addLine(to: CGPoint(x: paper.maxX, y: paper.maxY - fold))
    sheet.addLine(to: CGPoint(x: paper.maxX - fold, y: paper.maxY))
    sheet.addLine(to: CGPoint(x: paper.minX, y: paper.maxY))
    sheet.closeSubpath()

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.01), blur: s * 0.035, color: rgb(0, 20, 50, 0.45))
    ctx.addPath(sheet)
    ctx.setFillColor(rgb(250, 251, 253))
    ctx.fillPath()
    ctx.restoreGState()

    // Esquina doblada / Folded corner
    let corner = CGMutablePath()
    corner.move(to: CGPoint(x: paper.maxX - fold, y: paper.maxY))
    corner.addLine(to: CGPoint(x: paper.maxX - fold, y: paper.maxY - fold))
    corner.addLine(to: CGPoint(x: paper.maxX, y: paper.maxY - fold))
    corner.closeSubpath()
    ctx.addPath(corner)
    ctx.setFillColor(rgb(206, 216, 228))
    ctx.fillPath()

    // Línea de escaneo a ~45 % de la hoja / Scan line at ~45 % of the sheet
    let beamY = paper.minY + ph * 0.45

    // Líneas de texto: sobre la línea ya "escaneadas" (oscuras), bajo ella tenues.
    // Text lines: above the beam already "scanned" (dark), below it faint.
    let lineH = ph * 0.045
    let left = paper.minX + pw * 0.14
    let widths: [CGFloat] = [0.56, 0.72, 0.64, 0.72, 0.48, 0.70, 0.60, 0.72, 0.40]
    var y = paper.maxY - ph * 0.20
    for w in widths {
        let lw = pw * w * (y > paper.maxY - fold * 1.4 ? 0.8 : 1)
        let r = CGRect(x: left, y: y - lineH, width: lw, height: lineH)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: lineH / 2, cornerHeight: lineH / 2, transform: nil))
        ctx.setFillColor(y > beamY ? rgb(60, 78, 104) : rgb(196, 206, 220))
        ctx.fillPath()
        y -= lineH * 2.05
        if y < paper.minY + ph * 0.10 { break }
    }

    // Resplandor del haz / Beam glow
    let glowH = ph * 0.22
    let glow = CGGradient(colorsSpace: space,
                          colors: [rgb(90, 255, 220, 0), rgb(90, 255, 220, 0.55), rgb(90, 255, 220, 0)] as CFArray,
                          locations: [0, 0.5, 1])!
    ctx.saveGState()
    ctx.clip(to: CGRect(x: body.minX + body.width * 0.12, y: beamY - glowH / 2,
                        width: body.width * 0.76, height: glowH))
    ctx.drawLinearGradient(glow, start: CGPoint(x: 0, y: beamY - glowH / 2),
                           end: CGPoint(x: 0, y: beamY + glowH / 2), options: [])
    ctx.restoreGState()

    // Haz central nítido / Sharp central beam
    let beamW = body.width * 0.80
    let beam = CGRect(x: body.midX - beamW / 2, y: beamY - s * 0.009, width: beamW, height: s * 0.018)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: s * 0.03, color: rgb(80, 255, 220, 0.9))
    ctx.addPath(CGPath(roundedRect: beam, cornerWidth: beam.height / 2, cornerHeight: beam.height / 2, transform: nil))
    let beamGrad = CGGradient(colorsSpace: space,
                              colors: [rgb(120, 255, 230, 0), rgb(200, 255, 245), rgb(120, 255, 230, 0)] as CFArray,
                              locations: [0, 0.5, 1])!
    ctx.clip()
    ctx.drawLinearGradient(beamGrad, start: CGPoint(x: beam.minX, y: 0), end: CGPoint(x: beam.maxX, y: 0), options: [])
    ctx.restoreGState()

    ctx.restoreGState()

    // Borde interior sutil / Subtle inner stroke
    ctx.addPath(squircle)
    ctx.setStrokeColor(rgb(255, 255, 255, 0.12))
    ctx.setLineWidth(s * 0.004)
    ctx.strokePath()
}

func render(size: Int, draw: (CGContext, CGFloat, CGFloat) -> Void, height: Int? = nil) -> CGImage {
    let w = size, h = height ?? size
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    draw(ctx, CGFloat(w), CGFloat(h))
    return ctx.makeImage()!
}

func savePNG(_ img: CGImage, _ url: URL) {
    let rep = NSBitmapImageRep(cgImage: img)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

// Ícono en todos los tamaños / Icon in every size
let iconset = out.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        let img = render(size: px) { ctx, s, _ in drawIcon(ctx, s) }
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        savePNG(img, iconset.appendingPathComponent(name))
    }
}
savePNG(render(size: 1024) { ctx, s, _ in drawIcon(ctx, s) }, out.appendingPathComponent("icon-1024.png"))

// Fondos del instalador (claro y oscuro), ícono tenue abajo a la izquierda.
// Installer backgrounds (light and dark), faint icon at the bottom left.
func background(dark: Bool) -> CGImage {
    render(size: 1240, draw: { ctx, w, h in
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let g = CGGradient(colorsSpace: space,
                           colors: (dark ? [rgb(16, 32, 56, 0.0), rgb(20, 70, 110, 0.55)]
                                         : [rgb(255, 255, 255, 0.0), rgb(190, 225, 240, 0.65)]) as CFArray,
                           locations: [0, 1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: w, y: h), end: CGPoint(x: 0, y: 0), options: [])
        // Cabe bajo la lista de pasos del instalador / Fits under the installer's step list
        let iconSize = w * 0.25
        ctx.saveGState()
        ctx.translateBy(x: w * 0.012, y: w * 0.012)
        ctx.setAlpha(dark ? 0.8 : 0.95)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        // Imagen del instalador si se pasó, si no el ícono de la app.
        // Installer image if given, otherwise the app icon.
        if let photo = installerImage {
            ctx.draw(photo, in: CGRect(x: 0, y: 0, width: iconSize, height: iconSize))
        } else {
            let layer = render(size: Int(iconSize)) { c, s, _ in drawIcon(c, s) }
            ctx.draw(layer, in: CGRect(x: 0, y: 0, width: iconSize, height: iconSize))
        }
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }, height: 836)
}
savePNG(background(dark: false), out.appendingPathComponent("background.png"))
savePNG(background(dark: true), out.appendingPathComponent("background-dark.png"))
print("ok")
