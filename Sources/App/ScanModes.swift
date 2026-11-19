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
        case .photo:
            s.format = .jpg; s.ocr = false; s.deskew = false; s.cropToDocument = true
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
    var grayscale = false
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
