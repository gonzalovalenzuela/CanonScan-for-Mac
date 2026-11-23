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
    @Published var colorMode: ColorMode = .color
    @Published var paper: PaperSize = .a4
    @Published var format: OutputFormat = .pdf
    /// Mejoras de imagen del escaneo manual / Image adjustments for manual scanning
    @Published var adjust = ImageAdjust()
    /// Zona elegida en la vista previa (nil = tamaño de papel) / Region chosen in the preview (nil = paper size)
    @Published var region: ScanRegion?
    /// Imagen de la vista previa y si se está mostrando / Preview image and whether it is shown
    @Published private(set) var previewImage: CGImage?
    @Published var showingPreview = false
    static let previewDPI = 75
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
    /// Página abierta en el editor / Page open in the editor
    @Published var editingPage: ScannedPage?

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

    /// Ajustes de escaneo: con zona, se escanea desde la esquina hasta su borde y se recorta.
    /// Scan settings: with a region, scan from the corner to its edge and crop.
    private func plan(dpi: Int, color: ColorMode, paper: PaperSize) -> (ScanSettings, ScanRegion?) {
        var s = ScanSettings(dpi: dpi, grayscale: color.scansGray)
        if let r = region {
            s.widthMM = r.x + r.w; s.heightMM = r.y + r.h
            return (s, r)
        }
        (s.widthMM, s.heightMM) = paper.sizeMM
        return (s, nil)
    }

    /// Escanea una página, recorta la zona y aplica el color.
    /// Scans one page, crops the region and applies the color.
    private func scanImage(host: String, settings: ScanSettings, crop: ScanRegion? = nil,
                           color: ColorMode = .color) async throws -> CGImage {
        try await Task.detached(priority: .userInitiated) {
            let jpeg = try CHMPClient.scan(host: host, settings: settings) { msg in
                Task { @MainActor in self.status = msg }
            }
            guard var img = ImageTools.decode(jpeg) else {
                throw CHMPError.protocolError(L("no se pudo leer la imagen escaneada"))
            }
            if let crop { img = crop.crop(img, dpi: settings.dpi) }
            switch color {
            case .color: break
            case .gray: if let g = ImageTools.toGray(img) { img = g }
            case .bw: if let g = ImageTools.toGray(img) { img = g }   // B/N al final / B/W at the end
            }
            return img
        }.value
    }

    /// Separa fotos, orienta, corrige, mejora y pasa a B/N. Devuelve vacío si es una página en blanco a omitir.
    /// Splits photos, orients, corrects, enhances and converts to B/W. Returns empty for a blank page to skip.
    nonisolated private static func process(_ input: CGImage, color: ColorMode, adjust a: ImageAdjust,
                                            deskew: Bool, crop: Bool) -> [CGImage] {
        let parts = a.splitPhotos ? DocumentTools.splitPhotos(input) : [input]
        let split = parts.count > 1
        return parts.compactMap { part in
            var img = part
            if a.autoOrient { img = ImageEnhance.autoOrient(img) }
            // Las fotos separadas ya vienen recortadas / Split photos are already cropped
            if !split && (deskew || crop) { img = DocumentTools.correct(img, deskew: deskew, crop: crop) }
            img = ImageEnhance.apply(img, a)
            if a.skipBlank && ImageEnhance.isBlank(img) { return nil }
            if color == .bw, let b = ImageTools.toBW(img) { img = b }
            return img
        }
    }

    // MARK: - Vista previa / Preview

    /// Escaneo rápido del vidrio completo para elegir una zona.
    /// Quick scan of the whole glass to choose a region.
    func preview() {
        guard !busy, let host = targetHost else { return }
        busy = true
        status = L("Vista previa…")
        Task {
            defer { busy = false }
            do {
                var s = ScanSettings(dpi: Self.previewDPI, grayscale: false)
                (s.widthMM, s.heightMM) = (ScanSettings.glassWidthMM, ScanSettings.glassHeightMM)
                previewImage = try await scanImage(host: host, settings: s)
                showingPreview = true
                status = ""
            } catch {
                errorMessage = error.localizedDescription
                status = ""
            }
        }
    }

    func clearRegion() { region = nil }

    private static func page(_ img: CGImage, dpi: Int) -> ScannedPage {
        ScannedPage(image: img, dpi: dpi, thumbnail: NSImage(cgImage: img, size: NSSize(width: img.width, height: img.height)))
    }

    /// Escanea con un modo y guarda según sus ajustes.
    /// Scans with a mode and saves according to its settings.
    func scan(mode: ScanMode) {
        guard !busy, let host = targetHost else { return }
        let ms = modes[mode]
        let (settings, crop) = plan(dpi: ms.dpi, color: ms.colorMode, paper: ms.paper)
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
                    let a = try await scanImage(host: host, settings: settings, crop: crop, color: ms.colorMode)
                    guard Self.confirm(L("Unir: segunda mitad"),
                                       L("Gira el original 180° y pon la otra mitad en la misma esquina."),
                                       ok: L("Escanear")) else { status = ""; return }
                    let b = try await scanImage(host: host, settings: settings, crop: crop, color: ms.colorMode)
                    status = L("Uniendo…")
                    guard let joined = try await Self.background({ DocumentTools.stitch(a, b) }) else {
                        throw CHMPError.protocolError(L("no se pudo leer la imagen escaneada"))
                    }
                    var stitchAdjust = ms.adjust; stitchAdjust.skipBlank = false; stitchAdjust.splitPhotos = false   // Unir nunca descarta ni separa / Stitch never skips or splits
                    let fixed = try await Self.background {
                        Self.process(joined, color: ms.colorMode, adjust: stitchAdjust, deskew: ms.deskew, crop: ms.cropToDocument)
                    }
                    scanned += fixed.map { Self.page($0, dpi: ms.dpi) }
                } else {
                    while true {
                        let img = try await scanImage(host: host, settings: settings, crop: crop, color: ms.colorMode)
                        status = L("Procesando imagen…")
                        let fixed = try await Self.background {
                            Self.process(img, color: ms.colorMode, adjust: ms.adjust, deskew: ms.deskew, crop: ms.cropToDocument)
                        }
                        let title: String
                        if fixed.isEmpty {
                            title = L("Página en blanco omitida")
                        } else {
                            scanned += fixed.map { Self.page($0, dpi: ms.dpi) }
                            title = fixed.count > 1 ? L("%d fotos separadas", fixed.count) : L("Página %d lista", scanned.count)
                        }
                        // PDF: ¿otra página? / PDF: another page?
                        guard ms.format == .pdf,
                              Self.confirm(title,
                                           L("¿Escanear otra página para el mismo PDF?"),
                                           ok: L("Escanear otra"), cancel: L("Terminar"))
                        else { break }
                    }
                }
                guard !scanned.isEmpty else { status = L("Página en blanco omitida"); return }
                try await finish(scanned, mode: mode, settings: ms)
            } catch {
                errorMessage = error.localizedDescription
                status = ""
            }
        }
    }

    /// Guarda directo o pasa a revisión / Saves directly or hands over for review
    private func finish(_ scanned: [ScannedPage], mode: ScanMode, settings ms: ModeSettings) async throws {
        if ms.reviewBeforeSave {
            pages.append(contentsOf: scanned)
            format = ms.format
            status = L("Página %d lista", pages.count)
            await saveAsync(ocr: ms.format == .pdf && ms.ocr, mode: ms)
            return
        }
        var folder = URL(fileURLWithPath: (ms.saveFolder as NSString).expandingTildeInPath, isDirectory: true)
        if ms.dateSubfolder {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            folder.appendPathComponent(f.string(from: Date()), isDirectory: true)
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let pattern = ms.fileName.trimmingCharacters(in: .whitespaces).isEmpty ? "IMG" : ms.fileName
        let ext = ms.format.type.preferredFilenameExtension ?? "pdf"
        var saved = [URL]()
        let items = scanned.map { ($0.image, $0.dpi) }
        if ms.format == .pdf {
            var password: String?
            if ms.pdfPassword {
                guard let p = Self.askPassword() else {
                    pages.append(contentsOf: scanned)
                    status = L("Guardado cancelado")
                    return
                }
                password = p
            }
            status = ms.ocr ? L("Reconociendo texto…") : L("Guardando…")
            let url = Self.nextFile(in: folder, pattern: pattern, ext: ext)
            try await Self.background {
                try DocumentTools.writePDF(pages: items, to: url, ocr: ms.ocr, quality: ms.pdfQuality, password: password)
            }
            saved.append(url)
        } else {
            status = L("Guardando…")
            for item in items {
                let url = Self.nextFile(in: folder, pattern: pattern, ext: ext)
                try await Self.background { try Self.writeImage(item.0, dpi: item.1, format: ms.format, to: url) }
                saved.append(url)
            }
        }
        // Las páginas quedan a la vista en la ventana / Pages stay visible in the window
        pages.append(contentsOf: scanned)
        status = L("Guardado: %@", saved.last?.lastPathComponent ?? "")
        Self.afterSave(saved, ms)
    }

    /// Acciones después de guardar / After-save actions
    private static func afterSave(_ urls: [URL], _ ms: ModeSettings) {
        guard !urls.isEmpty else { return }
        let opensOther = ms.openWithApp || ms.attachToMail
        if ms.showInFinder { reveal(urls, returnToApp: !opensOther) }
        if ms.openWithApp {
            let app = URL(fileURLWithPath: ms.openAppPath)
            NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        }
        if ms.attachToMail, let mail = NSSharingService(named: .composeEmail) {
            mail.perform(withItems: urls)
        }
    }

    /// Muestra en Finder y, si corresponde, devuelve CanonScan al frente.
    /// Shows in Finder and, if appropriate, brings CanonScan back to front.
    private static func reveal(_ urls: [URL], returnToApp: Bool = true) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
        guard returnToApp else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// Nombre de archivo. Sin {fecha}/{hora}: IMG_0001, IMG_0002…; con ellos: «Factura 2026-11-23 11.20», y si existe, « 2».
    /// File name. Without {date}/{time}: IMG_0001…; with them: "Invoice 2026-11-23 11.20", and " 2" if it exists.
    private static func nextFile(in folder: URL, pattern: String, ext: String) -> URL {
        let tokens = ["{fecha}", "{hora}", "{date}", "{time}"]
        guard tokens.contains(where: { pattern.contains($0) }) else {
            var n = 1
            while true {
                let url = folder.appendingPathComponent(String(format: "%@_%04d.%@", pattern, n, ext))
                if !FileManager.default.fileExists(atPath: url.path) { return url }
                n += 1
            }
        }
        let now = Date()
        let d = DateFormatter(); d.dateFormat = "yyyy-MM-dd"
        let h = DateFormatter(); h.dateFormat = "HH.mm"
        let base = pattern
            .replacingOccurrences(of: "{fecha}", with: d.string(from: now))
            .replacingOccurrences(of: "{date}", with: d.string(from: now))
            .replacingOccurrences(of: "{hora}", with: h.string(from: now))
            .replacingOccurrences(of: "{time}", with: h.string(from: now))
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: ".")
        var url = folder.appendingPathComponent("\(base).\(ext)")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base) \(n).\(ext)")
            n += 1
        }
        return url
    }

    /// Pide la contraseña del PDF (dos veces) / Asks for the PDF password (twice)
    private static func askPassword() -> String? {
        while true {
            let a = NSAlert()
            a.messageText = L("Contraseña del PDF")
            a.informativeText = L("Se pedirá para abrir el archivo. No se guarda en CanonScan.")
            let first = NSSecureTextField(frame: NSRect(x: 0, y: 30, width: 260, height: 24))
            first.placeholderString = L("Contraseña")
            let second = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
            second.placeholderString = L("Repetir contraseña")
            let box = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 54))
            box.addSubview(first); box.addSubview(second)
            a.accessoryView = box
            a.window.initialFirstResponder = first
            a.addButton(withTitle: L("Guardar"))
            a.addButton(withTitle: L("Cancelar"))
            guard a.runModal() == .alertFirstButtonReturn else { return nil }
            if !first.stringValue.isEmpty && first.stringValue == second.stringValue { return first.stringValue }
            let e = NSAlert()
            e.messageText = L("Las contraseñas no coinciden o están vacías.")
            e.runModal()
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
        let (settings, crop) = plan(dpi: dpi, color: colorMode, paper: paper)
        let color = colorMode
        let a = adjust
        Task {
            defer { busy = false }
            do {
                let raw = try await scanImage(host: host, settings: settings, crop: crop, color: color)
                status = L("Procesando imagen…")
                let imgs = try await Self.background {
                    Self.process(raw, color: color, adjust: a, deskew: false, crop: false)
                }
                guard !imgs.isEmpty else { status = L("Página en blanco omitida"); return }
                pages += imgs.map { Self.page($0, dpi: settings.dpi) }
                status = imgs.count > 1 ? L("%d fotos separadas", imgs.count) : L("Página %d lista", pages.count)
            } catch {
                errorMessage = error.localizedDescription
                status = ""
            }
        }
    }

    func remove(_ page: ScannedPage) {
        pages.removeAll { $0.id == page.id }
    }

    /// Reemplaza una página editada en su misma posición / Replaces an edited page at the same position
    func replace(_ page: ScannedPage, with image: CGImage) {
        guard let i = pages.firstIndex(where: { $0.id == page.id }) else { return }
        pages[i] = Self.page(image, dpi: page.dpi)
    }

    /// Mueve una página a la posición de otra (arrastrar) / Moves a page to another's position (drag)
    func move(id: UUID, to target: UUID) {
        guard id != target, let from = pages.firstIndex(where: { $0.id == id }),
              let to = pages.firstIndex(where: { $0.id == target }) else { return }
        let p = pages.remove(at: from)
        pages.insert(p, at: to)
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

    /// Botón Guardar… / Save… button
    func save() {
        Task { await saveAsync() }
    }

    /// Pide destino y escribe en segundo plano / Asks for a destination and writes in the background
    func saveAsync(ocr: Bool = false, mode ms: ModeSettings? = nil) async {
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
        // Mantiene «ocupado» si ya venía de un escaneo / Keeps "busy" if it came from a scan
        let wasBusy = busy
        busy = true
        defer { if !wasBusy { busy = false } }
        let items = pages.map { ($0.image, $0.dpi) }
        let fmt = format
        var password: String?
        if fmt == .pdf, ms?.pdfPassword == true {
            guard let p = Self.askPassword() else { status = L("Guardado cancelado"); return }
            password = p
        }
        let quality = ms?.pdfQuality ?? .high
        status = fmt == .pdf && ocr ? L("Reconociendo texto…") : L("Guardando…")
        do {
            try await Self.background {
                switch fmt {
                case .pdf: try DocumentTools.writePDF(pages: items, to: url, ocr: ocr, quality: quality, password: password)
                case .jpg, .png: try Self.writeImages(items, format: fmt, to: url)
                }
            }
            status = L("Guardado: %@", url.lastPathComponent)
            if let ms { Self.afterSave([url], ms) }
        } catch {
            errorMessage = L("No se pudo guardar: %@", error.localizedDescription)
            status = ""
        }
    }

    /// Ejecuta trabajo pesado fuera del hilo principal / Runs heavy work off the main thread
    private static func background<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await Task.detached(priority: .userInitiated, operation: work).value
    }

    private static func writeImages(_ items: [(CGImage, Int)], format: OutputFormat, to url: URL) throws {
        let base = url.deletingPathExtension()
        let ext = url.pathExtension
        for (i, item) in items.enumerated() {
            let target = items.count == 1 ? url
                : base.deletingLastPathComponent()
                    .appendingPathComponent("\(base.lastPathComponent)-\(i + 1)")
                    .appendingPathExtension(ext)
            try writeImage(item.0, dpi: item.1, format: format, to: target)
        }
    }

    private static func writeImage(_ image: CGImage, dpi: Int, format: OutputFormat, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, format.type.identifier as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        let props: [CFString: Any] = [
            kCGImagePropertyDPIWidth: dpi,
            kCGImagePropertyDPIHeight: dpi,
            kCGImageDestinationLossyCompressionQuality: 0.9,
        ]
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
    }

    private static func dateStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return f.string(from: Date())
    }
}
