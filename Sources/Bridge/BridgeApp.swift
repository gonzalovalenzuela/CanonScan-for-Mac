// BridgeApp.swift
// Puente AirScan de CanonScan: vive en la barra de menú y anuncia la
// impresora Canon como escáner nativo de macOS.
// CanonScan AirScan bridge: lives in the menu bar and advertises the
// Canon printer as a native macOS scanner.

import SwiftUI
import Combine

@main
struct CanonScanBridgeApp: App {
    @StateObject private var bridge = BridgeController()

    var body: some Scene {
        MenuBarExtra {
            BridgeMenu().environmentObject(bridge)
        } label: {
            Image(systemName: bridge.scanning ? "scanner.fill" : "scanner")
        }
    }
}

@MainActor
final class BridgeController: ObservableObject {
    enum State: Equatable { case off, searching, sharing(String), failed(String) }

    @Published private(set) var state: State = .off
    @Published private(set) var scanning = false
    @Published var enabled: Bool {
        didSet {
            guard enabled != oldValue else { return }
            SharedSettings.bridgeEnabled = enabled
            apply()
        }
    }

    private let browser = PrinterBrowser()
    private var server: ESCLServer?
    private var serverHost: String?
    private var bag = Set<AnyCancellable>()

    init() {
        // Una sola copia: si ya hay otra corriendo, esta se cierra.
        // Single instance: if another copy is already running, this one quits.
        let me = ProcessInfo.processInfo.processIdentifier
        // Queda la de PID menor, aunque arranquen a la vez / The lowest PID stays, even if both start at once
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: SharedSettings.bridgeBundleID)
        if others.contains(where: { $0.processIdentifier < me }) {
            enabled = false
            DispatchQueue.main.async { NSApp.terminate(nil) }
            return
        }
        enabled = SharedSettings.bridgeEnabled
        // Cambios hechos desde CanonScan / Changes made from CanonScan
        DistributedNotificationCenter.default()
            .publisher(for: SharedSettings.bridgeChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reloadSettings() }
            .store(in: &bag)
        // Impresora encontrada o perdida / Printer found or lost
        browser.$printers
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.apply() }
            .store(in: &bag)
        // Si aún no hay impresora (p. ej. permiso de red recién dado), busca de nuevo.
        // If there's no printer yet (e.g. network permission just granted), search again.
        Timer.publish(every: 20, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in
                guard let self, self.enabled, self.state == .searching, !SharedSettings.useManualHost else { return }
                self.browser.start()
            }
            .store(in: &bag)
        apply()
    }

    private func reloadSettings() {
        let e = SharedSettings.bridgeEnabled
        if e != enabled { enabled = e } else { apply() }   // también pudo cambiar la IP / the IP may have changed too
    }

    /// Arranca, detiene o mueve el servidor según los ajustes.
    /// Starts, stops or moves the server according to the settings.
    private func apply() {
        guard enabled else {
            stopServer()
            browser.stop()
            state = .off
            return
        }
        let target: (host: String, name: String)?
        if SharedSettings.useManualHost {
            let h = SharedSettings.manualHost
            target = h.isEmpty ? nil : (h, "Canon (\(h))")
            browser.stop()
        } else {
            if browser.printers.isEmpty && !browser.searching { browser.start() }
            target = browser.printers.first.map { ($0.host, $0.name) }
        }
        guard let target else {
            stopServer()
            state = .searching
            return
        }
        guard serverHost != target.host || server == nil else { return }
        stopServer()
        let s = ESCLServer(printerHost: target.host, serviceName: target.name)
        s.onActivity = { [weak self] active in self?.scanning = active }
        do {
            try s.start()
            server = s
            serverHost = target.host
            state = .sharing(target.name)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func stopServer() {
        server?.stop()
        server = nil
        serverHost = nil
        scanning = false
    }

    var statusText: String {
        if scanning { return L("Escaneando…") }
        switch state {
        case .off: return L("Puente apagado")
        case .searching: return L("Buscando impresora…")
        case .sharing(let name): return L("Compartiendo «%@»", name)
        case .failed(let msg): return msg
        }
    }

    func openCanonScan() {
        // CanonScan.app/Contents/Library/LoginItems/CanonScanBridge.app → CanonScan.app
        let app = Bundle.main.bundleURL
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        NSWorkspace.shared.openApplication(at: app, configuration: .init())
    }
}

struct BridgeMenu: View {
    @EnvironmentObject var bridge: BridgeController

    var body: some View {
        Text(bridge.statusText)
        Divider()
        Toggle("Compartir como escáner de macOS", isOn: $bridge.enabled)
        Button("Abrir CanonScan") { bridge.openCanonScan() }
        Divider()
        Button("Salir del puente") { NSApp.terminate(nil) }
    }
}
