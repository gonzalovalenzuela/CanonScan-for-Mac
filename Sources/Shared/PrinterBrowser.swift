// PrinterBrowser.swift
// Busca impresoras Canon en la red local por Bonjour y obtiene su IPv4.
// Finds Canon printers on the local network via Bonjour and resolves their IPv4.

import Foundation
import Network

struct FoundPrinter: Identifiable, Hashable {
    let id: String      // nombre Bonjour / Bonjour name
    let name: String
    let host: String    // IPv4
}

@MainActor
final class PrinterBrowser: ObservableObject {
    @Published private(set) var printers: [FoundPrinter] = []
    @Published private(set) var searching = false

    private var browser: NWBrowser?
    private var resolving: [String: NWConnection] = [:]
    private var usbTimer: Timer?
    private let queue = DispatchQueue(label: "cl.local.canonscan.browser")

    func start() {
        stop()
        printers = []
        searching = true
        // Las Canon G3010/G3110 anuncian impresión IPP; el escaneo CHMP va al mismo equipo.
        // Canon G3010/G3110 advertise IPP printing; CHMP scanning targets the same device.
        let b = NWBrowser(for: .bonjour(type: "_ipps._tcp", domain: "local."), using: .tcp)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in self?.handle(results) }
        }
        b.stateUpdateHandler = { [weak self] state in
            if case .failed = state { Task { @MainActor in self?.searching = false } }
        }
        b.start(queue: queue)
        browser = b
        // Impresoras por USB: al inicio y cada 3 s (conectar/desconectar el cable).
        // USB printers: at start and every 3 s (plugging/unplugging the cable).
        refreshUSB()
        usbTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshUSB() }
        }
        // Deja de mostrar "buscando" después de unos segundos / Stop "searching" after a few seconds
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            self?.searching = false
        }
    }

    func stop() {
        usbTimer?.invalidate()
        usbTimer = nil
        browser?.cancel()
        browser = nil
        resolving.values.forEach { $0.cancel() }
        resolving.removeAll()
    }

    /// USB primero en la lista, luego las de red / USB first in the list, then network ones
    private func refreshUSB() {
        let usb = USBTransport.connectedPrinters().map {
            FoundPrinter(id: "usb-\($0.locationID)", name: "\($0.name) (USB)", host: CHMPClient.usbHost)
        }
        let updated = usb + printers.filter { $0.host != CHMPClient.usbHost }
        if updated != printers { printers = updated }
    }

    private func handle(_ results: Set<NWBrowser.Result>) {
        for r in results {
            guard case let .service(name, _, _, _) = r.endpoint,
                  name.localizedCaseInsensitiveContains("canon"),
                  resolving[name] == nil,
                  !printers.contains(where: { $0.id == name }) else { continue }
            resolve(name: name, endpoint: r.endpoint)
        }
    }

    /// Conecta brevemente al servicio para saber su IPv4 / Briefly connect to learn its IPv4
    private func resolve(name: String, endpoint: NWEndpoint) {
        let params = NWParameters.tcp
        if let ip = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ip.version = .v4
        }
        let conn = NWConnection(to: endpoint, using: params)
        resolving[name] = conn
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                var host: String?
                if case let .hostPort(h, _) = conn.currentPath?.remoteEndpoint, case let .ipv4(addr) = h {
                    // Quita el sufijo de interfaz (%en0) si viene / Drop interface suffix if present
                    host = "\(addr)".split(separator: "%").first.map(String.init)
                }
                conn.cancel()
                Task { @MainActor in
                    guard let self else { return }
                    self.resolving[name] = nil
                    if let host, !self.printers.contains(where: { $0.id == name }) {
                        self.printers.append(FoundPrinter(id: name, name: name, host: host))
                    }
                }
            case .failed, .cancelled:
                Task { @MainActor in self?.resolving[name] = nil }
            default:
                break
            }
        }
        conn.start(queue: queue)
    }
}
