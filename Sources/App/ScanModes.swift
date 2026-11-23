// ScanModes.swift
// Modos de escaneo (Documento, Foto, Personalizado, Unir) y sus ajustes guardados.
// Scan modes (Document, Photo, Custom, Stitch) and their saved settings.

import Foundation

enum ScanMode: String, CaseIterable, Codable, Identifiable {
    case document, photo, custom, stitch
    var id: String { rawValue }

    var title: String {
        switch self {
        case .document: return L("Documento")
        case .photo: return L("Foto")
        case .custom: return L("Personalizado")
        case .stitch: return L("Unir")
        }
    }

    var systemImage: String {
        switch self {
        case .document: return "doc.text"
        case .photo: return "photo"
        case .custom: return "slider.horizontal.3"
        case .stitch: return "rectangle.split.2x1"
        }
    }

    /// Valores iniciales, tomados de IJ Scan Utility2 / Defaults, based on IJ Scan Utility2
    var defaults: ModeSettings {
        var s = ModeSettings()
        switch self {
        case .document:
            s.format = .pdf; s.ocr = true; s.deskew = true; s.cropToDocument = true
            s.adjust.whitenBackground = true; s.adjust.autoOrient = true; s.adjust.skipBlank = true
        case .photo:
            s.format = .jpg; s.ocr = false; s.deskew = false; s.cropToDocument = true; s.paper = .glass
            s.adjust.splitPhotos = true
        case .custom:
            s.format = .pdf; s.ocr = true; s.deskew = false; s.cropToDocument = false
        case .stitch:
            s.format = .pdf; s.ocr = true; s.deskew = true; s.cropToDocument = false
        }
        return s
    }
}

extension OutputFormat: Codable {}

struct ModeSettings: Codable, Equatable {
    var colorMode: ColorMode = .color
    var paper: PaperSize = .a4
    var dpi = 300
    var format: OutputFormat = .pdf
    /// PDF con texto buscable / Searchable-text PDF
    var ocr = true
    var deskew = false
    var cropToDocument = false
    var fileName = "IMG"
    var saveFolder = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first?.path
        ?? NSHomeDirectory()
    var dateSubfolder = false
    /// Revisar y elegir dónde guardar / Review and choose where to save
    var reviewBeforeSave = false
    var showInFinder = true
    var adjust = ImageAdjust()
    var pdfQuality: PDFQuality = .high
    /// Pedir contraseña al guardar el PDF / Ask for a password when saving the PDF
    var pdfPassword = false
    var openWithApp = false
    var openAppPath = "/System/Applications/Preview.app"
    var attachToMail = false

    init() {}

    /// Lee ajustes guardados por versiones anteriores: lo que falta toma su valor inicial.
    /// Reads settings saved by earlier versions: missing keys take their default.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func get<T: Decodable>(_ k: CodingKeys, _ v: inout T) { if let x = try? c.decode(T.self, forKey: k) { v = x } }
        get(.colorMode, &colorMode); get(.paper, &paper); get(.dpi, &dpi); get(.format, &format)
        get(.ocr, &ocr); get(.deskew, &deskew); get(.cropToDocument, &cropToDocument)
        get(.fileName, &fileName); get(.saveFolder, &saveFolder); get(.dateSubfolder, &dateSubfolder)
        get(.reviewBeforeSave, &reviewBeforeSave); get(.showInFinder, &showInFinder); get(.adjust, &adjust)
        get(.pdfQuality, &pdfQuality); get(.pdfPassword, &pdfPassword); get(.openWithApp, &openWithApp)
        get(.openAppPath, &openAppPath); get(.attachToMail, &attachToMail)
        // Versión 0.2–0.3 guardaba «grayscale» / Versions 0.2–0.3 saved "grayscale"
        if let legacy = try? decoder.container(keyedBy: LegacyKeys.self),
           let gray = try? legacy.decode(Bool.self, forKey: .grayscale), gray, !c.contains(.colorMode) {
            colorMode = .gray
        }
    }
    private enum LegacyKeys: String, CodingKey { case grayscale }
}

@MainActor
final class ModeStore: ObservableObject {
    @Published var settings: [ScanMode: ModeSettings] {
        didSet { save() }
    }
    private static let key = "modeSettings"

    init() {
        var loaded = [ScanMode: ModeSettings]()
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([String: ModeSettings].self, from: data) {
            for (k, v) in saved { if let m = ScanMode(rawValue: k) { loaded[m] = v } }
        }
        for m in ScanMode.allCases where loaded[m] == nil { loaded[m] = m.defaults }
        settings = loaded
    }

    subscript(mode: ScanMode) -> ModeSettings {
        get { settings[mode] ?? mode.defaults }
        set { settings[mode] = newValue }
    }

    func reset(_ mode: ScanMode) { settings[mode] = mode.defaults }

    private func save() {
        let dict = Dictionary(uniqueKeysWithValues: settings.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(dict) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
