// ScanOptions.swift
// Tamaños de papel, modos de color y zona elegida en la vista previa.
// Paper sizes, color modes and the region chosen in the preview.

import Foundation
import CoreGraphics

enum PaperSize: String, CaseIterable, Codable, Identifiable {
    case a4, letter, a5, card, photo10x15, photo13x18, glass
    var id: String { rawValue }

    var title: String {
        switch self {
        case .a4: return "A4"
        case .letter: return L("Carta")
        case .a5: return "A5"
        case .card: return L("Tarjeta")
        case .photo10x15: return L("Foto 10×15")
        case .photo13x18: return L("Foto 13×18")
        case .glass: return L("Vidrio completo")
        }
    }

    /// Ancho y alto en mm (vertical) / Width and height in mm (portrait)
    var sizeMM: (w: Double, h: Double) {
        switch self {
        case .a4: return (210, 297)
        case .letter: return (215.9, 279.4)
        case .a5: return (148, 210)
        case .card: return (90, 55)
        case .photo10x15: return (100, 150)
        case .photo13x18: return (127, 178)
        case .glass: return (ScanSettings.glassWidthMM, ScanSettings.glassHeightMM)
        }
    }
}

enum ColorMode: String, CaseIterable, Codable, Identifiable {
    case color, gray, bw
    var id: String { rawValue }
    var title: String {
        switch self {
        case .color: return L("Color")
        case .gray: return L("Gris")
        case .bw: return L("B/N")
        }
    }
    /// El escáner trabaja en gris para B/N / The scanner works in gray for B/W
    var scansGray: Bool { self != .color }
}

/// Calidad de las imágenes dentro del PDF / Quality of images inside the PDF
enum PDFQuality: String, CaseIterable, Codable, Identifiable {
    case maximum, high, normal, small
    var id: String { rawValue }
    var title: String {
        switch self {
        case .maximum: return L("Máxima")
        case .high: return L("Alta")
        case .normal: return L("Normal")
        case .small: return L("Pequeño")
        }
    }
    /// Calidad JPEG dentro del PDF / JPEG quality inside the PDF
    var jpegQuality: Double {
        switch self {
        case .maximum: return 0.95
        case .high: return 0.8
        case .normal: return 0.6
        case .small: return 0.4
        }
    }
}

/// Zona en mm desde la esquina del vidrio / Region in mm from the glass corner
struct ScanRegion: Equatable, Codable {
    var x: Double, y: Double, w: Double, h: Double

    /// Recorta una imagen escaneada desde la esquina a la zona.
    /// Crops an image scanned from the corner to the region.
    func crop(_ img: CGImage, dpi: Int) -> CGImage {
        let k = Double(dpi) / 25.4
        let rect = CGRect(x: x * k, y: y * k, width: w * k, height: h * k).integral
            .intersection(CGRect(x: 0, y: 0, width: img.width, height: img.height))
        guard !rect.isEmpty else { return img }
        return img.cropping(to: rect) ?? img
    }
}
