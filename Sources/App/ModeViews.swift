// ModeViews.swift
// Fila de botones de modo y ventana de Ajustes de cada modo.
// Mode button row and per-mode Settings window.

import SwiftUI

/// Fila de modos sobre las páginas: cada botón escanea al presionarlo.
/// Mode row above the pages: each button scans when pressed.
struct ModeBar: View {
    @EnvironmentObject var model: ScanModel
    @EnvironmentObject var browser: PrinterBrowser

    var body: some View {
        VStack(spacing: 0) {
        HStack(spacing: 10) {
            ForEach(ScanMode.allCases) { mode in
                Button { model.scan(mode: mode) } label: {
                    VStack(spacing: 6) {
                        Image(systemName: mode.systemImage)
                            .font(.system(size: 22, weight: .regular))
                            .frame(height: 26)
                        Text(mode.title).font(.callout)
                    }
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .contentShape(Rectangle())
                }
                .buttonStyle(ModeButtonStyle())
                .help(summary(mode))
                // Solo escanear requiere impresora / Only scanning needs a printer
                .disabled(model.busy || model.targetHost == nil)
            }
            SettingsButton()
                .buttonStyle(ModeButtonStyle())
                .help(L("Ajustes de los modos…"))
        }
        .padding(.horizontal, 28)
        .padding(.top, 14)
        .padding(.bottom, model.region == nil ? 6 : 2)
        if let r = model.region {
            // Zona activa / Active region
            HStack(spacing: 8) {
                Image(systemName: "viewfinder").foregroundStyle(Color.scanAccent)
                Text(L("Zona: %@ × %@ mm", Self.mm(r.w), Self.mm(r.h)))
                Button { model.showingPreview = model.previewImage != nil } label: { Text("Editar") }
                    .buttonStyle(.borderless)
                    .disabled(model.previewImage == nil)
                Button(role: .destructive) { model.clearRegion() } label: { Text("Quitar zona") }
                    .buttonStyle(.borderless)
            }
            .font(.callout)
            .padding(.horizontal, 28)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        }
    }

    static func mm(_ v: Double) -> String { String(format: "%.0f", v) }

    /// Resumen del modo para el tooltip / Mode summary for the tooltip
    private func summary(_ mode: ScanMode) -> String {
        let s = model.modes[mode]
        let color = s.colorMode.title
        let dest = s.reviewBeforeSave ? L("Revisar antes de guardar")
            : (s.saveFolder as NSString).abbreviatingWithTildeInPath
        let area = model.region != nil ? L("Zona") : s.paper.title
        return "\(mode.title): \(s.dpi) dpi · \(color) · \(area) · \(s.format.rawValue) · \(dest)"
    }
}

struct ModeButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(enabled ? Color.scanAccent : Color.secondary)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.scanAccent.opacity(configuration.isPressed ? 0.22 : 0.09))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.scanAccent.opacity(0.18))
            )
            .opacity(enabled ? 1 : 0.55)
    }
}

// MARK: - Ajustes / Settings

struct ModeSettingsView: View {
    @EnvironmentObject var modes: ModeStore
    @State private var selected: ScanMode = .document

    var body: some View {
        TabView(selection: $selected) {
            ForEach(ScanMode.allCases) { mode in
                ModeForm(mode: mode)
                    .tabItem { Label(mode.title, systemImage: mode.systemImage) }
                    .tag(mode)
            }
        }
        .frame(width: 520, height: 690)
    }
}

struct ModeForm: View {
    @EnvironmentObject var modes: ModeStore
    let mode: ScanMode

    private var s: Binding<ModeSettings> {
        Binding(get: { modes[mode] }, set: { modes[mode] = $0 })
    }

    var body: some View {
        Form {
            Section("Escaneo") {
                Picker("Modo", selection: s.colorMode) {
                    ForEach(ColorMode.allCases) { Text($0.title).tag($0) }
                }
                Picker("Papel", selection: s.paper) {
                    ForEach(PaperSize.allCases) { Text($0.title).tag($0) }
                }
                Picker("Resolución", selection: s.dpi) {
                    Text("150 dpi").tag(150)
                    Text("300 dpi").tag(300)
                    Text("600 dpi").tag(600)
                }
                Toggle(mode == .photo ? "Recortar a la foto" : "Recortar al documento", isOn: s.cropToDocument)
                Toggle("Enderezar", isOn: s.deskew)
                if mode == .stitch {
                    Text("Escanea dos mitades: la segunda con el original girado 180°.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Imagen") {
                AdjustControls(adjust: s.adjust,
                               showRestore: mode == .photo || mode == .custom,
                               showSkipBlank: mode != .stitch)
            }

            Section("Guardar") {
                Picker("Formato", selection: s.format) {
                    ForEach(OutputFormat.allCases) { Text($0.rawValue).tag($0) }
                }
                if s.wrappedValue.format == .pdf {
                    Toggle("PDF con texto buscable (OCR)", isOn: s.ocr)
                }
                Toggle("Revisar antes de guardar", isOn: s.reviewBeforeSave)
                if !s.wrappedValue.reviewBeforeSave {
                    TextField("Nombre de archivo", text: s.fileName)
                    LabeledContent("Guardar en") {
                        HStack {
                            Text((s.wrappedValue.saveFolder as NSString).abbreviatingWithTildeInPath)
                                .lineLimit(1).truncationMode(.middle)
                                .foregroundStyle(.secondary)
                            Button("Cambiar…") { chooseFolder() }
                        }
                    }
                    Toggle("Guardar en subcarpeta con la fecha", isOn: s.dateSubfolder)
                }
            }

            Section("Después de guardar") {
                Toggle("Mostrar en Finder", isOn: s.showInFinder)
            }

            HStack {
                Spacer()
                Button("Restaurar valores") { modes.reset(mode) }
            }
        }
        .formStyle(.grouped)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath: (s.wrappedValue.saveFolder as NSString).expandingTildeInPath)
        if panel.runModal() == .OK, let url = panel.url { s.wrappedValue.saveFolder = url.path }
    }
}

// MARK: - Abrir Ajustes en macOS 13 y 14+ / Open Settings on macOS 13 and 14+

/// En macOS 14+ Apple exige SettingsLink; en 13 se usa la acción del menú.
/// On macOS 14+ Apple requires SettingsLink; on 13 the menu action is used.
struct SettingsButton: View {
    private var label: some View {
        Image(systemName: "gearshape").font(.system(size: 16))
            .frame(width: 40, height: 58)
            .contentShape(Rectangle())
    }

    var body: some View {
        if #available(macOS 14, *) {
            SettingsLink { label }
        } else {
            Button {
                NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                NSApp.activate(ignoringOtherApps: true)
            } label: { label }
        }
    }
}
