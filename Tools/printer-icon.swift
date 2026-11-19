// printer-icon.swift
// Dibuja un ícono original de multifuncional con tanques de tinta (sin marcas).
// Draws an original ink-tank multifunction printer icon (no trademarks).
//
// Uso / Usage: swift printer-icon.swift <salida.png> [lado=1024]

import AppKit
import CoreGraphics

let args = CommandLine.arguments
let outPath = args.count > 1 ? args[1] : "printer-icon.png"
let side = args.count > 2 ? Int(args[2]) ?? 1024 : 1024

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}
let space = CGColorSpace(name: CGColorSpace.sRGB)!
func gradient(_ colors: [CGColor], _ locs: [CGFloat]? = nil) -> CGGradient {
    CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locs)!
}
func poly(_ pts: [CGPoint]) -> CGPath {
    let p = CGMutablePath(); p.addLines(between: pts); p.closeSubpath(); return p
}
func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

/// Polígono con esquinas redondeadas por arcos / Polygon with arc-rounded corners
func roundedPoly(_ pts: [CGPoint], _ r: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let n = pts.count
    let last = pts[n - 1], first = pts[0]
    p.move(to: CGPoint(x: (last.x + first.x) / 2, y: (last.y + first.y) / 2))
    for i in 0..<n {
        p.addArc(tangent1End: pts[i], tangent2End: pts[(i + 1) % n], radius: r)
    }
    p.closeSubpath()
    return p
}

/// Rellena un camino con degradado vertical / Fills a path with a vertical gradient
func fill(_ ctx: CGContext, _ path: CGPath, _ g: CGGradient, from y0: CGFloat, to y1: CGFloat) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: y0), end: CGPoint(x: 0, y: y1),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

func draw(_ ctx: CGContext, _ s: CGFloat) {
    // Todo se diseña en 1024 y se escala / Designed at 1024 and scaled
    ctx.scaleBy(x: s / 1024, y: s / 1024)

    // Sombra en el piso / Floor shadow
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 40, color: rgb(0, 0, 0, 0.45))
    ctx.addEllipse(in: CGRect(x: 120, y: 200, width: 784, height: 90))
    ctx.setFillColor(rgb(0, 0, 0, 0.35))
    ctx.fillPath()
    ctx.restoreGState()

    // Geometría del cuerpo / Body geometry
    let fl: CGFloat = 130, fr: CGFloat = 894      // frente izq/der / front left/right
    let fb: CGFloat = 270, ft: CGFloat = 520      // frente abajo/arriba / front bottom/top
    let bl: CGFloat = 205, br: CGFloat = 819, bt: CGFloat = 730   // borde trasero / back edge

    // Silueta completa con esquinas redondeadas; la cara superior se recorta dentro.
    // Full rounded silhouette; the top face is clipped inside it.
    let body = roundedPoly([CGPoint(x: fl, y: fb), CGPoint(x: fr, y: fb), CGPoint(x: fr, y: ft),
                            CGPoint(x: br, y: bt), CGPoint(x: bl, y: bt), CGPoint(x: fl, y: ft)], 22)
    // Cara frontal / Front face
    fill(ctx, body, gradient([rgb(52, 56, 64), rgb(26, 28, 33), rgb(16, 17, 20)], [0, 0.55, 1]),
         from: ft, to: fb)
    // Cara superior / Top face
    ctx.saveGState()
    ctx.addPath(body); ctx.clip()
    let top = poly([CGPoint(x: fl - 20, y: ft), CGPoint(x: fr + 20, y: ft), CGPoint(x: br + 20, y: bt + 20), CGPoint(x: bl - 20, y: bt + 20)])
    fill(ctx, top, gradient([rgb(44, 47, 54), rgb(70, 75, 85)]), from: bt, to: ft)
    ctx.restoreGState()

    // Brillo del borde frontal superior / Front top edge highlight
    ctx.setStrokeColor(rgb(140, 148, 162, 0.55))
    ctx.setLineWidth(5)
    ctx.move(to: CGPoint(x: fl + 10, y: ft + 4)); ctx.addLine(to: CGPoint(x: fr - 10, y: ft + 4))
    ctx.strokePath()

    // Tapa del escáner / Scanner lid
    let lid = roundedPoly([CGPoint(x: 210, y: 560), CGPoint(x: 760, y: 560), CGPoint(x: 712, y: 705), CGPoint(x: 252, y: 705)], 10)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 12, color: rgb(0, 0, 0, 0.5))
    fill(ctx, lid, gradient([rgb(36, 39, 45), rgb(62, 67, 77)]), from: 705, to: 560)
    ctx.restoreGState()
    // Reflejo diagonal en la tapa / Diagonal reflection on the lid
    ctx.saveGState()
    ctx.addPath(lid); ctx.clip()
    ctx.addPath(poly([CGPoint(x: 330, y: 560), CGPoint(x: 470, y: 560), CGPoint(x: 560, y: 705), CGPoint(x: 420, y: 705)]))
    ctx.setFillColor(rgb(255, 255, 255, 0.06)); ctx.fillPath()
    ctx.restoreGState()
    // Ranura para abrir la tapa / Lid grip groove
    ctx.addPath(rounded(CGRect(x: 420, y: 568, width: 130, height: 14), 7))
    ctx.setFillColor(rgb(18, 19, 23)); ctx.fillPath()

    // Panel de control con LEDs / Control panel with LEDs
    let panel = roundedPoly([CGPoint(x: 780, y: 552), CGPoint(x: 872, y: 552), CGPoint(x: 838, y: 660), CGPoint(x: 770, y: 660)], 6)
    fill(ctx, panel, gradient([rgb(28, 30, 35), rgb(46, 50, 58)]), from: 660, to: 552)
    let leds: [(CGFloat, CGFloat, CGColor)] = [(808, 630, rgb(90, 230, 120)), (822, 600, rgb(235, 240, 245)),
                                                (836, 572, rgb(235, 240, 245))]
    for (x, y, c) in leds {
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 10, color: c)
        ctx.addEllipse(in: CGRect(x: x - 6, y: y - 6, width: 12, height: 12))
        ctx.setFillColor(c); ctx.fillPath()
        ctx.restoreGState()
    }

    // Tanque de tinta negra a la izquierda / Black ink tank on the left
    let leftTank = CGRect(x: 158, y: 320, width: 104, height: 160)
    fill(ctx, rounded(leftTank, 14), gradient([rgb(60, 64, 72), rgb(30, 32, 37)]), from: leftTank.maxY, to: leftTank.minY)
    let lw = CGRect(x: 186, y: 350, width: 48, height: 100)
    fill(ctx, rounded(lw, 10), gradient([rgb(70, 74, 82), rgb(8, 8, 10)], [0, 0.35]), from: lw.maxY, to: lw.minY)

    // Ranura de salida y bandeja / Output slot and tray
    let slot = rounded(CGRect(x: 300, y: 395, width: 420, height: 34), 10)
    ctx.addPath(slot); ctx.setFillColor(rgb(6, 6, 8)); ctx.fillPath()

    // Hoja saliendo hacia el frente / Sheet coming out toward the viewer
    let sheet = roundedPoly([CGPoint(x: 318, y: 412), CGPoint(x: 702, y: 412), CGPoint(x: 744, y: 190), CGPoint(x: 276, y: 190)], 4)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 16, color: rgb(0, 0, 0, 0.45))
    fill(ctx, sheet, gradient([rgb(226, 232, 240), rgb(252, 253, 255)]), from: 412, to: 190)
    ctx.restoreGState()
    // Contenido impreso genérico (bloques de color, sin texto) / Generic printed content (color blocks, no text)
    ctx.saveGState()
    ctx.addPath(sheet); ctx.clip()
    func band(_ y0: CGFloat, _ y1: CGFloat, _ x0: CGFloat, _ x1: CGFloat, _ c: CGColor) {
        // Bloque que sigue la perspectiva de la hoja / Block following the sheet perspective
        func xAt(_ t: CGFloat, _ y: CGFloat) -> CGFloat {
            let k = (412 - y) / 222
            let left = 318 - 42 * k, right = 702 + 42 * k
            return left + (right - left) * t
        }
        ctx.addPath(poly([CGPoint(x: xAt(x0, y0), y: y0), CGPoint(x: xAt(x1, y0), y: y0),
                          CGPoint(x: xAt(x1, y1), y: y1), CGPoint(x: xAt(x0, y1), y: y1)]))
        ctx.setFillColor(c); ctx.fillPath()
    }
    band(390, 360, 0.08, 0.92, rgb(40, 140, 220))          // encabezado azul / blue header
    band(345, 280, 0.08, 0.44, rgb(230, 70, 120))          // imagen magenta / magenta picture
    band(345, 280, 0.08, 0.44, rgb(0, 0, 0, 0))
    band(318, 280, 0.08, 0.44, rgb(250, 190, 40))          // franja amarilla / yellow stripe
    for (i, y) in [342.0, 324, 306, 288].enumerated() {
        band(CGFloat(y), CGFloat(y) - 8, 0.52, i == 3 ? 0.78 : 0.92, rgb(150, 160, 175))
    }
    band(262, 222, 0.08, 0.92, rgb(60, 190, 200, 0.85))    // franja turquesa / teal band
    ctx.restoreGState()

    // Bloque de tanques de color a la derecha / Color tank block on the right
    let tankBox = CGRect(x: 734, y: 300, width: 140, height: 190)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: -4, height: -4), blur: 10, color: rgb(0, 0, 0, 0.5))
    fill(ctx, rounded(tankBox, 16), gradient([rgb(64, 68, 77), rgb(30, 32, 37)]), from: tankBox.maxY, to: tankBox.minY)
    ctx.restoreGState()
    let inks: [(CGColor, CGColor, CGFloat)] = [
        (rgb(40, 190, 255), rgb(0, 90, 200), 0.78),     // cian / cyan
        (rgb(255, 70, 160), rgb(170, 0, 90), 0.62),     // magenta
        (rgb(255, 225, 60), rgb(225, 150, 0), 0.70),    // amarillo / yellow
    ]
    for (i, ink) in inks.enumerated() {
        let win = CGRect(x: 752 + CGFloat(i) * 40, y: 328, width: 28, height: 134)
        // Vidrio vacío / Empty glass
        fill(ctx, rounded(win, 8), gradient([rgb(90, 96, 108), rgb(50, 54, 62)]), from: win.maxY, to: win.minY)
        // Tinta hasta su nivel / Ink up to its level
        ctx.saveGState()
        ctx.addPath(rounded(win, 8)); ctx.clip()
        let level = win.minY + win.height * ink.2
        ctx.drawLinearGradient(gradient([ink.0, ink.1]), start: CGPoint(x: 0, y: level), end: CGPoint(x: 0, y: win.minY), options: [])
        // Brillo vertical del vidrio / Vertical glass highlight
        ctx.setFillColor(rgb(255, 255, 255, 0.28))
        ctx.fill(CGRect(x: win.minX + 5, y: win.minY + 6, width: 5, height: win.height - 12))
        ctx.restoreGState()
    }

    // Línea inferior del cuerpo / Body bottom line
    ctx.setStrokeColor(rgb(0, 0, 0, 0.6)); ctx.setLineWidth(4)
    ctx.move(to: CGPoint(x: fl + 18, y: fb + 2)); ctx.addLine(to: CGPoint(x: fr - 18, y: fb + 2))
    ctx.strokePath()
}

let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.interpolationQuality = .high
draw(ctx, CGFloat(side))
let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outPath))
print("ok")
