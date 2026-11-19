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

    func save() {
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
                try writePDF(to: url)
            case .jpg, .png:
                try writeImages(to: url)
            }
            status = L("Guardado: %@", url.lastPathComponent)
        } catch {
            errorMessage = L("No se pudo guardar: %@", error.localizedDescription)
        }
    }

    private func writePDF(to url: URL) throws {
        let doc = PDFDocument()
        for (i, p) in pages.enumerated() {
            // Tamaño físico correcto: píxeles × 72 / dpi / Correct physical size: px × 72 / dpi
            let size = NSSize(width: CGFloat(p.image.width) * 72 / CGFloat(p.dpi),
                              height: CGFloat(p.image.height) * 72 / CGFloat(p.dpi))
            let ns = NSImage(cgImage: p.image, size: size)
            guard let page = PDFPage(image: ns) else { throw CocoaError(.fileWriteUnknown) }
            doc.insert(page, at: i)
        }
        guard doc.write(to: url) else { throw CocoaError(.fileWriteUnknown) }
    }

    private func writeImages(to url: URL) throws {
        let base = url.deletingPathExtension()
        let ext = url.pathExtension
        for (i, p) in pages.enumerated() {
            let target = pages.count == 1 ? url
                : base.deletingLastPathComponent()
                    .appendingPathComponent("\(base.lastPathComponent)-\(i + 1)")
                    .appendingPathExtension(ext)
            guard let dest = CGImageDestinationCreateWithURL(target as CFURL, format.type.identifier as CFString, 1, nil)
            else { throw CocoaError(.fileWriteUnknown) }
            let props: [CFString: Any] = [
                kCGImagePropertyDPIWidth: p.dpi,
                kCGImagePropertyDPIHeight: p.dpi,
                kCGImageDestinationLossyCompressionQuality: 0.9,
            ]
            CGImageDestinationAddImage(dest, p.image, props as CFDictionary)
            guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
        }
    }

    private static func dateStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return f.string(from: Date())
    }
}
