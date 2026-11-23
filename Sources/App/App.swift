// App.swift
// Interfaz principal del escáner / Main scanner window

import SwiftUI

@main
struct CanonScanApp: App {
    @StateObject private var model = ScanModel()
    @StateObject private var bridge = BridgeSettings()

    /// Nombre visible traducido / Localized display name
    static var appName: String {
        Bundle.main.localizedInfoDictionary?["CFBundleDisplayName"] as? String
            ?? Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String ?? "CanonScan"
    }

    var body: some Scene {
        WindowGroup("Escáner Canon") {
            ContentView()
                .environmentObject(model)
                .environmentObject(model.browser)
                .environmentObject(bridge)
                .frame(minWidth: 860, minHeight: 640)
        }
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands {
            // «Acerca de» con copyright y créditos / About with copyright and credits
            CommandGroup(replacing: .appInfo) {
                Button(L("Acerca de %@", Self.appName)) {
                    AboutPanel.show(description: L("Escanea por WiFi o USB con impresoras Canon PIXMA G3010 / G3110."))
                }
            }
        }

        // Ajustes de los modos (⌘,) / Mode settings (⌘,)
        Settings {
            ModeSettingsView().environmentObject(model.modes)
        }
    }
}

// Color de acento tomado del ícono / Accent color taken from the icon
extension Color {
    static let scanAccent = Color(red: 22 / 255, green: 120 / 255, blue: 180 / 255)
    static let scanBeam = Color(red: 90 / 255, green: 240 / 255, blue: 215 / 255)
}

struct ContentView: View {
    @EnvironmentObject var model: ScanModel
    @EnvironmentObject var bridge: BridgeSettings
    @EnvironmentObject var browser: PrinterBrowser

    var body: some View {
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 260, ideal: 280, max: 320)
        } detail: {
            PagesView()
        }
        .tint(.scanAccent)
        .toolbar { toolbar }
        .onAppear { browser.start() }
        .alert("¿Iniciar el puente AirScan al iniciar sesión?", isPresented: $bridge.askLaunchAtLogin) {
            Button("Iniciar al iniciar sesión") { bridge.answerLaunchAtLogin(true) }
            Button("Ahora no", role: .cancel) { bridge.answerLaunchAtLogin(false) }
        } message: {
            Text("El puente hace que la impresora aparezca como escáner en Captura de Imagen y Vista Previa, también para otros equipos de tu red. Puedes cambiarlo después en la barra lateral.")
        }
        .alert("Error", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button(role: .destructive) { model.clear() } label: {
                Label("Borrar todo", systemImage: "trash")
            }
            .help("Borrar todo")
            .disabled(model.busy || model.pages.isEmpty)

            Button { model.save() } label: {
                Label("Guardar…", systemImage: "square.and.arrow.down")
            }
            .help("Guardar…")
            .disabled(model.busy || model.pages.isEmpty)
            .keyboardShortcut("s", modifiers: .command)

            // Vista previa junto a escanear / Preview next to scan
            Button { model.preview() } label: {
                Label("Vista previa", systemImage: "viewfinder")
                    .labelStyle(.titleAndIcon)
            }
            .help(L("Escaneo rápido para elegir una zona"))
            .disabled(model.busy || model.targetHost == nil)

            Button { model.scanPage() } label: {
                Label(model.pages.isEmpty ? LocalizedStringKey("Escanear página") : LocalizedStringKey("Agregar página"),
                      systemImage: model.pages.isEmpty ? "doc.viewfinder" : "plus.viewfinder")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.busy || model.targetHost == nil)
            .keyboardShortcut("r", modifiers: .command)
        }
    }
}

// MARK: - Barra lateral / Sidebar

struct Sidebar: View {
    @EnvironmentObject var model: ScanModel
    @EnvironmentObject var bridge: BridgeSettings
    @EnvironmentObject var browser: PrinterBrowser

    var body: some View {
        Form {
            Section("Impresora") {
                PrinterStatusRow()

                if model.useManualHost {
                    TextField("Dirección IP", text: $model.manualHost, prompt: Text("192.0.2.10"))
                        .textFieldStyle(.roundedBorder)
                } else if browser.printers.count > 1 {
                    Picker("Impresora", selection: Binding(
                        get: { model.selectedPrinterID ?? browser.printers.first?.id },
                        set: { model.selectedPrinterID = $0 }
                    )) {
                        ForEach(browser.printers) { p in Text(p.name).tag(Optional(p.id)) }
                    }
                    .labelsHidden()
                }

                HStack {
                    Toggle("IP manual", isOn: $model.useManualHost.animation())
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    Spacer()
                    if !model.useManualHost {
                        Button { browser.start() } label: {
                            Label("Buscar de nuevo", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .disabled(browser.searching)
                    }
                }
            }

            Section("Escaneo") {
                OptionRow(title: "Resolución", systemImage: "rectangle.and.text.magnifyingglass") {
                    Picker("Resolución", selection: $model.dpi) {
                        Text("150").tag(150)
                        Text("300").tag(300)
                        Text("600").tag(600)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text("dpi").foregroundStyle(.secondary)
                }
                OptionRow(title: "Modo", systemImage: "paintpalette") {
                    Picker("Modo", selection: $model.colorMode) {
                        ForEach(ColorMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                OptionRow(title: "Papel", systemImage: "doc.plaintext") {
                    Picker("Papel", selection: $model.paper) {
                        ForEach(PaperSize.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .disabled(model.region != nil)
                }
            }

            Section("Imagen") {
                AdjustControls(adjust: $model.adjust)
            }

            Section("Guardar como") {
                OptionRow(title: "Formato", systemImage: "doc") {
                    Picker("Formato", selection: $model.format) {
                        ForEach(OutputFormat.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }

            Section("Compartir") {
                Toggle("Compartir como escáner de macOS", isOn: $bridge.sharing)
                    .toggleStyle(.switch)
                Toggle("Iniciar al iniciar sesión", isOn: Binding(
                    get: { bridge.launchAtLogin },
                    set: { bridge.setLaunchAtLogin($0) }
                ))
                .toggleStyle(.switch)
                if bridge.needsApproval {
                    HStack {
                        Text("Falta aprobarlo en Ajustes del Sistema.")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Abrir") { bridge.openLoginItemsSettings() }
                            .controlSize(.small)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .disabled(model.busy)
    }
}

/// Fila con título e ícono sobre su control / Row with title and icon above its control
struct OptionRow<Content: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) { content }
        }
        .padding(.vertical, 2)
    }
}

/// Estado de la impresora con punto de color / Printer status with a colored dot
struct PrinterStatusRow: View {
    @EnvironmentObject var model: ScanModel
    @EnvironmentObject var browser: PrinterBrowser

    private enum Status { case ready(String), searching, missing, manualEmpty }

    private var state: Status {
        if model.useManualHost {
            let h = model.manualHost.trimmingCharacters(in: .whitespaces)
            return h.isEmpty ? .manualEmpty : .ready(h)
        }
        if let p = browser.printers.first(where: { $0.id == model.selectedPrinterID }) ?? browser.printers.first {
            return .ready(p.name)
        }
        return browser.searching ? .searching : .missing
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(color.opacity(0.18)).frame(width: 28, height: 28)
                Image(systemName: "printer.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).lineLimit(1).truncationMode(.middle)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if case .searching = state { ProgressView().controlSize(.small) }
        }
        .padding(.vertical, 2)
    }

    private var color: Color {
        switch state {
        case .ready: return .green
        case .searching: return .orange
        case .missing, .manualEmpty: return .secondary
        }
    }

    private var title: String {
        switch state {
        case .ready(let name): return name
        case .searching: return L("Buscando en la red…")
        case .missing: return L("No se encontró ninguna Canon")
        case .manualEmpty: return L("Escribe la IP de la impresora")
        }
    }

    private var subtitle: String {
        switch state {
        case .ready: return model.useManualHost ? L("Dirección manual") : L("Lista para escanear")
        case .searching: return L("Bonjour")
        case .missing: return L("Prueba «Buscar de nuevo» o usa IP manual")
        case .manualEmpty: return L("IP manual")
        }
    }
}

// MARK: - Páginas / Pages

struct PagesView: View {
    @EnvironmentObject var model: ScanModel

    var body: some View {
        // Sin fondo propio: el fondo estándar sigue las esquinas de la ventana en macOS 26.
        // No custom background: the standard one follows the window corners on macOS 26.
        ZStack {
            if model.showingPreview, let img = model.previewImage {
                PreviewSelector(image: img)
            } else if model.pages.isEmpty && !model.busy {
                EmptyStateView()
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 28)], spacing: 28) {
                        ForEach(Array(model.pages.enumerated()), id: \.element.id) { index, page in
                            PageCard(page: page, number: index + 1, count: model.pages.count)
                        }
                        if model.busy { ScanningCard() }
                    }
                    .padding(28)
                    .animation(.spring(duration: 0.35), value: model.pages.map(\.id))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .top) { ModeBar() }
        .safeAreaInset(edge: .bottom) { StatusBar() }
        .navigationTitle("Escáner Canon")
        .navigationSubtitle(model.pages.isEmpty ? "" : L("Páginas: %lld", model.pages.count))
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            Text("Listo para escanear")
                .font(.title2.weight(.semibold))
            Text("Pon la hoja en el vidrio y presiona «Escanear página».")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
}

/// Tarjeta de página con controles al pasar el mouse / Page card with hover controls
struct PageCard: View {
    @EnvironmentObject var model: ScanModel
    let page: ScannedPage
    let number: Int
    let count: Int
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: page.thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 420)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .shadow(color: .black.opacity(hovering ? 0.28 : 0.16), radius: hovering ? 14 : 8, y: hovering ? 6 : 3)
                .overlay(alignment: .bottom) {
                    if hovering && !model.busy {
                        controls.padding(.bottom, 12).transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .scaleEffect(hovering ? 1.01 : 1)

            HStack(spacing: 6) {
                Text("Página \(number)").font(.callout.weight(.medium))
                Text("· \(page.dpi) dpi").font(.callout).foregroundStyle(.secondary)
            }
        }
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
    }

    private var controls: some View {
        HStack(spacing: 2) {
            Button { model.move(page, by: -1) } label: { Image(systemName: "chevron.left") }
                .disabled(number == 1)
                .help("Mover antes")
            Button { model.move(page, by: 1) } label: { Image(systemName: "chevron.right") }
                .disabled(number == count)
                .help("Mover después")
            Divider().frame(height: 16).padding(.horizontal, 4)
            Button(role: .destructive) { withAnimation { model.remove(page) } } label: {
                Image(systemName: "trash").foregroundStyle(.red)
            }
            .help("Eliminar página")
        }
        .buttonStyle(.borderless)
        .font(.system(size: 14, weight: .medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    }
}

/// Tarjeta animada mientras se escanea / Animated card while scanning
struct ScanningCard: View {
    @EnvironmentObject var model: ScanModel
    @State private var beamDown = false

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { geo in
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                    // Haz que recorre la hoja / Beam sweeping the sheet
                    LinearGradient(colors: [.scanBeam.opacity(0), .scanBeam.opacity(0.55), .scanBeam.opacity(0)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 60)
                        .overlay(Rectangle().fill(Color.scanBeam).frame(height: 2))
                        .offset(y: beamDown ? geo.size.height - 60 : 0)
                    VStack(spacing: 8) {
                        ProgressView()
                        Text(model.status).font(.callout).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .aspectRatio(210.0 / 297.0, contentMode: .fit)
            .frame(height: 420)
            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)

            Text("Escaneando…").font(.callout.weight(.medium)).foregroundStyle(.secondary)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { beamDown = true }
        }
    }
}

/// Barra de estado inferior / Bottom status bar
struct StatusBar: View {
    @EnvironmentObject var model: ScanModel
    @State private var visible = false

    var body: some View {
        Group {
            if visible && !model.status.isEmpty && !model.busy { pill }
        }
        // Muestra cada aviso unos segundos / Show each notice for a few seconds
        .task(id: "\(model.status)|\(model.busy)") {
            guard !model.busy, !model.status.isEmpty else { return }
            withAnimation { visible = true }
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            withAnimation { visible = false }
        }
    }

    private var pill: some View {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text(model.status).lineLimit(1)
            }
            .font(.callout)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
            .padding(.bottom, 14)
            .transition(.opacity)
    }
}
