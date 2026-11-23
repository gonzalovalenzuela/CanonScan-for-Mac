// fusion-icon.swift
// Ícono de la app: la impresora del .dmg sobre el fondo azul con forma de macOS.
// App icon: the .dmg printer over the blue background in the macOS shape.
//
// Uso / Usage: swift fusion-icon.swift <impresora.png> <salida.png> [beam] [lado=1024]
//   beam: agrega el haz de escaneo turquesa / adds the turquoise scan beam

import AppKit
import CoreGraphics

let args = CommandLine.arguments
guard args.count >= 3,
      let printer = NSImage(contentsOfFile: args[1])?.cgImage(forProposedRect: nil, context: nil, hints: nil)
else { print("uso: fusion-icon.swift impresora.png salida.png [beam] [lado]"); exit(2) }
let withBeam = args.count > 3 && args[3] == "beam"
let side = args.count > 4 ? Int(args[4]) ?? 1024 : 1024

let space = CGColorSpace(name: CGColorSpace.sRGB)!
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}
func gradient(_ c: [CGColor], _ l: [CGFloat]) -> CGGradient { CGGradient(colorsSpace: space, colors: c as CFArray, locations: l)! }

let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.interpolationQuality = .high
let s = CGFloat(side)

// Forma de macOS con el mismo fondo del ícono anterior / macOS shape with the previous icon's background
let inset = s * 0.098
let body = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
let radius = body.width * 0.225
let squircle = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: rgb(0, 0, 0, 0.35))
ctx.addPath(squircle); ctx.setFillColor(rgb(20, 40, 80)); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(squircle); ctx.clip()
ctx.drawLinearGradient(gradient([rgb(18, 52, 120), rgb(22, 104, 168), rgb(32, 178, 190)], [0, 0.55, 1]),
                       start: CGPoint(x: body.minX, y: body.minY), end: CGPoint(x: body.maxX, y: body.maxY), options: [])
ctx.drawLinearGradient(gradient([rgb(255, 255, 255, 0.18), rgb(255, 255, 255, 0)], [0, 1]),
                       start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.midY), options: [])

// Impresora centrada, un poco más grande que el área útil / Printer centered, slightly larger than the safe area
let p = s * 0.80
let printerRect = CGRect(x: (s - p) / 2, y: (s - p) / 2 - s * 0.015, width: p, height: p)
ctx.draw(printer, in: printerRect)

if withBeam {
    // Haz turquesa sobre la tapa del escáner / Turquoise beam over the scanner lid
    let beamY = printerRect.minY + p * 0.615
    let glowH = s * 0.11
    ctx.saveGState()
    ctx.clip(to: CGRect(x: body.minX + body.width * 0.08, y: beamY - glowH / 2, width: body.width * 0.84, height: glowH))
    ctx.drawLinearGradient(gradient([rgb(90, 255, 220, 0), rgb(90, 255, 220, 0.5), rgb(90, 255, 220, 0)], [0, 0.5, 1]),
                           start: CGPoint(x: 0, y: beamY - glowH / 2), end: CGPoint(x: 0, y: beamY + glowH / 2), options: [])
    ctx.restoreGState()
    let beamW = body.width * 0.86
    let beam = CGRect(x: s / 2 - beamW / 2, y: beamY - s * 0.008, width: beamW, height: s * 0.016)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: s * 0.03, color: rgb(80, 255, 220, 0.9))
    ctx.addPath(CGPath(roundedRect: beam, cornerWidth: beam.height / 2, cornerHeight: beam.height / 2, transform: nil))
    ctx.clip()
    ctx.drawLinearGradient(gradient([rgb(120, 255, 230, 0), rgb(210, 255, 248), rgb(120, 255, 230, 0)], [0, 0.5, 1]),
                           start: CGPoint(x: beam.minX, y: 0), end: CGPoint(x: beam.maxX, y: 0), options: [])
    ctx.restoreGState()
}
ctx.restoreGState()

// Borde interior sutil / Subtle inner stroke
ctx.addPath(squircle)
ctx.setStrokeColor(rgb(255, 255, 255, 0.12))
ctx.setLineWidth(s * 0.004)
ctx.strokePath()

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
print("ok")
