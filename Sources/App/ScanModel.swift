// ScanModel.swift
// Estado de la app: páginas escaneadas, opciones y guardado.
// App state: scanned pages, options and saving.

import AppKit
import PDFKit
import UniformTypeIdentifiers

enum OutputFormat: String, CaseIterable, Identifiable {
    case pdf = "PDF", jpg = "JPG", png = "PNG"
    var id: String { rawValue }
    var type: UTType {
        switch self {
        case .pdf: return .pdf
        case .jpg: return .jpeg
        case .png: return .png
        }
    }
}

struct ScannedPage: Identifiable {
    let id = UUID()
    let image: CGImage
    let dpi: Int
    let thumbnail: NSImage
}

@MainActor
final class ScanModel: ObservableObject {
    // Opciones / Options
    @Published var dpi = 300
    @Published var grayscale = false
    @Published var format: OutputFormat = .pdf
    // Se guardan y se avisan al puente / Saved and announced to the bridge
    @Published var useManualHost: Bool {
        didSet { UserDefaults.standard.set(useManualHost, forKey: "useManualHost"); SharedSettings.notifyChange() }
    }
    @Published var manualHost: String {
        didSet { UserDefaults.standard.set(manualHost, forKey: "manualHost"); SharedSettings.notifyChange() }
    }
    @Published var selectedPrinterID: String?

    // Estado / State
    @Published private(set) var pages: [ScannedPage] = []
    @Published private(set) var busy = false
    @Published private(set) var status = ""
    @Published var errorMessage: String?

    let browser = PrinterBrowser()
    let modes = ModeStore()

    init() {
        useManualHost = UserDefaults.standard.bool(forKey: "useManualHost")
        manualHost = UserDefaults.standard.string(forKey: "manualHost") ?? ""
    }

    var targetHost: String? {
        if useManualHost {
            let h = manualHost.trimmingCharacters(in: .whitespaces)
            return h.isEmpty ? nil : h
        }
        return browser.printers.first { $0.id == selectedPrinterID }?.host
            ?? browser.printers.first?.host
    }

    // MARK: - Escaneo / Scanning

    /// Escanea una página y la decodifica / Scans one page and decodes it
    private func scanImage(host: String, settings: ScanSettings) async throws -> CGImage {
        try await Task.detached(priority: .userInitiated) {
            let jpeg = try CHMPClient.scan(host: host, settings: settings) { msg in
                Task { @MainActor in self.status = msg }
            }
            guard var img = ImageTools.decode(jpeg) else {
                throw CHMPError.protocolError(L("no se pudo leer la imagen escaneada"))
            }
            if settings.grayscale, let gray = ImageTools.toGray(img) { img = gray }
            return img
        }.value
    }

    private static func page(_ img: CGImage, dpi: Int) -> ScannedPage {
        ScannedPage(image: img, dpi: dpi, thumbnail: NSImage(cgImage: img, size: NSSize(width: img.width, height: img.height)))
    }

    /// Escanea con un modo y guarda según sus ajustes.
    /// Scans with a mode and saves according to its settings.
    func scan(mode: ScanMode) {
        guard !busy, let host = targetHost else { return }
        let ms = modes[mode]
        let settings = ScanSettings(dpi: ms.dpi, grayscale: ms.grayscale)
        busy = true
        status = L("Conectando…")
        Task {
            defer { busy = false }
            do {
                var scanned = [ScannedPage]()
                if mode == .stitch {
                    guard Self.confirm(L("Unir: primera mitad"),
                                       L("Pon la mitad izquierda del original sobre el vidrio, alineada con la esquina."),
                                       ok: L("Escanear")) else { status = ""; return }
                    let a = try await scanImage(host: host, settings: settings)
                    guard Self.confirm(L("Unir: segunda mitad"),
                                       L("Gira el original 180° y pon la otra mitad en la misma esquina."),
                                       ok: L("Escanear")) else { status = ""; return }
                    let b = try await scanImage(host: host, settings: settings)
                    status = L("Uniendo…")
                    guard let joined = DocumentTools.stitch(a, b) else {
                        throw CHMPError.protocolError(L("no se pudo leer la imagen escaneada"))
                    }
                    let fixed = DocumentTools.correct(joined, deskew: ms.deskew, crop: ms.cropToDocument)
                    scanned.append(Self.page(fixed, dpi: ms.dpi))
                } else {
                    while true {
                        let img = try await scanImage(host: host, settings: settings)
                        let fixed = DocumentTools.correct(img, deskew: ms.deskew, crop: ms.cropToDocument)
                        scanned.append(Self.page(fixed, dpi: ms.dpi))
                        // PDF: ¿otra página? / PDF: another page?
                        guard ms.format == .pdf,
                              Self.confirm(L("Página %d lista", scanned.count),
                                           L("¿Escanear otra página para el mismo PDF?"),
                                           ok: L("Escanear otra"), cancel: L("Terminar"))
                        else { break }
                    }
                }
                try finish(scanned, mode: mode, settings: ms)
            } catch {
                errorMessage = error.localizedDescription
                status = ""
            }
        }
    }

    /// Guarda directo o pasa a revisión / Saves directly or hands over for review
    private func finish(_ scanned: [ScannedPage], mode: ScanMode, settings ms: ModeSettings) throws {
        if ms.reviewBeforeSave {
            pages.append(contentsOf: scanned)
            format = ms.format
            status = L("Página %d lista", pages.count)
            save(ocr: ms.format == .pdf && ms.ocr, revealInFinder: ms.showInFinder)
            return
        }
        var folder = URL(fileURLWithPath: (ms.saveFolder as NSString).expandingTildeInPath, isDirectory: true)
        if ms.dateSubfolder {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            folder.appendPathComponent(f.string(from: Date()), isDirectory: true)
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let prefix = ms.fileName.trimmingCharacters(in: .whitespaces).isEmpty ? "IMG" : ms.fileName
        let ext = ms.format.type.preferredFilenameExtension ?? "pdf"
        var saved = [URL]()
        if ms.format == .pdf {
            let url = Self.nextFile(in: folder, prefix: prefix, ext: ext)
            status = ms.ocr ? L("Reconociendo texto…") : L("Guardando…")
            try DocumentTools.writePDF(pages: scanned.map { ($0.image, $0.dpi) }, to: url, ocr: ms.ocr)
            saved.append(url)
        } else {
            for p in scanned {
                let url = Self.nextFile(in: folder, prefix: prefix, ext: ext)
                try Self.writeImage(p, format: ms.format, to: url)
                saved.append(url)
            }
        }
        // Las páginas quedan a la vista en la ventana / Pages stay visible in the window
        pages.append(contentsOf: scanned)
        status = L("Guardado: %@", saved.last?.lastPathComponent ?? "")
        if ms.showInFinder { Self.reveal(saved) }
    }

    /// Muestra en Finder y devuelve CanonScan al frente / Shows in Finder and brings CanonScan back to front
    private static func reveal(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// Siguiente nombre libre: IMG_0001, IMG_0002… / Next free name: IMG_0001, IMG_0002…
    private static func nextFile(in folder: URL, prefix: String, ext: String) -> URL {
        var n = 1
        while true {
            let url = folder.appendingPathComponent(String(format: "%@_%04d.%@", prefix, n, ext))
            if !FileManager.default.fileExists(atPath: url.path) { return url }
            n += 1
        }
    }

    /// Diálogo de confirmación / Confirmation dialog
    private static func confirm(_ title: String, _ message: String, ok: String, cancel: String = L("Cancelar")) -> Bool {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = message
        a.addButton(withTitle: ok)
        a.addButton(withTitle: cancel)
        return a.runModal() == .alertFirstButtonReturn
    }

    func scanPage() {
        guard !busy, let host = targetHost else { return }
        busy = true
        status = L("Conectando…")
        let settings = ScanSettings(dpi: dpi, grayscale: grayscale)

        Task.detached(priority: .userInitiated) {
            do {
                let jpeg = try CHMPClient.scan(host: host, settings: settings) { msg in
                    Task { @MainActor in self.status = msg }
                }
                guard let page = Self.makePage(jpeg: jpeg, settings: settings) else {
                    throw CHMPError.protocolError(L("no se pudo leer la imagen escaneada"))
                }
                await MainActor.run {
                    self.pages.append(page)
                    self.status = L("Página %d lista", self.pages.count)
                    self.busy = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.status = ""
                    self.busy = false
                }
            }
        }
    }

    /// Decodifica el JPEG; en modo gris lo convierte a un canal real.
    /// Decodes the JPEG; in gray mode converts it to a true single channel.
    nonisolated private static func makePage(jpeg: Data, settings: ScanSettings) -> ScannedPage? {
        guard var img = ImageTools.decode(jpeg) else { return nil }
        if settings.grayscale, let gray = ImageTools.toGray(img) { img = gray }
        let thumb = NSImage(cgImage: img, size: NSSize(width: img.width, height: img.height))
        return ScannedPage(image: img, dpi: settings.dpi, thumbnail: thumb)
    }

    func remove(_ page: ScannedPage) {
        pages.removeAll { $0.id == page.id }
    }

    func move(_ page: ScannedPage, by offset: Int) {
        guard let i = pages.firstIndex(where: { $0.id == page.id }) else { return }
        let j = i + offset
        guard pages.indices.contains(j) else { return }
        pages.swapAt(i, j)
    }

    func clear() {
        pages.removeAll()
        status = ""
    }

    // MARK: - Guardado / Saving

    func save(ocr: Bool = false, revealInFinder: Bool = false) {
        guard !pages.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.type]
        panel.canCreateDirectories = true
        let stamp = Self.dateStamp()
        panel.nameFieldStringValue = L("Escaneo %@", stamp) + "." + (format.type.preferredFilenameExtension ?? "")
        if format != .pdf && pages.count > 1 {
            panel.message = L("Se guardará un archivo por página, numerado (-1, -2, …).")
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            switch format {
            case .pdf:
                try DocumentTools.writePDF(pages: pages.map { ($0.image, $0.dpi) }, to: url, ocr: ocr)
            case .jpg, .png:
                try writeImages(to: url)
            }
            status = L("Guardado: %@", url.lastPathComponent)
            if revealInFinder { Self.reveal([url]) }
        } catch {
            errorMessage = L("No se pudo guardar: %@", error.localizedDescription)
        }
    }

    private func writeImages(to url: URL) throws {
        let base = url.deletingPathExtension()
        let ext = url.pathExtension
        for (i, p) in pages.enumerated() {
            let target = pages.count == 1 ? url
                : base.deletingLastPathComponent()
                    .appendingPathComponent("\(base.lastPathComponent)-\(i + 1)")
                    .appendingPathExtension(ext)
            try Self.writeImage(p, format: format, to: target)
        }
    }

    private static func writeImage(_ p: ScannedPage, format: OutputFormat, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, format.type.identifier as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        let props: [CFString: Any] = [
            kCGImagePropertyDPIWidth: p.dpi,
            kCGImagePropertyDPIHeight: p.dpi,
            kCGImageDestinationLossyCompressionQuality: 0.9,
        ]
        CGImageDestinationAddImage(dest, p.image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
    }

    private static func dateStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return f.string(from: Date())
    }
}
