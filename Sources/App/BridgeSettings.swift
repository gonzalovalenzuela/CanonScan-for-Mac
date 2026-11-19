// BridgeSettings.swift
// Control del puente AirScan desde CanonScan: encenderlo y que parta con la sesión.
// AirScan bridge control from CanonScan: turn it on and start it at login.

import AppKit
import Combine
import ServiceManagement

@MainActor
final class BridgeSettings: ObservableObject {
    @Published var sharing: Bool {
        didSet {
            guard sharing != oldValue else { return }
            SharedSettings.bridgeEnabled = sharing
            if sharing { launchBridge() }
        }
    }
    @Published private(set) var launchAtLogin = false
    @Published private(set) var needsApproval = false
    @Published var askLaunchAtLogin = false

    private var loginItem: SMAppService { SMAppService.loginItem(identifier: SharedSettings.bridgeBundleID) }
    private var bag = Set<AnyCancellable>()

    init() {
        sharing = SharedSettings.bridgeEnabled
        refreshLoginStatus()
        // Cambios hechos desde la barra de menú / Changes made from the menu bar
        DistributedNotificationCenter.default()
            .publisher(for: SharedSettings.bridgeChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let e = SharedSettings.bridgeEnabled
                if e != self.sharing { self.sharing = e }
            }
            .store(in: &bag)
        // Primera apertura: preguntar una vez / First launch: ask once
        if !SharedSettings.defaults.bool(forKey: "askedLaunchAtLogin") {
            askLaunchAtLogin = true
        }
        if sharing { launchBridge() }
    }

    func answerLaunchAtLogin(_ yes: Bool) {
        SharedSettings.defaults.set(true, forKey: "askedLaunchAtLogin")
        askLaunchAtLogin = false
        setLaunchAtLogin(yes)
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try loginItem.register() } else { try loginItem.unregister() }
        } catch {
            NSLog("CanonScan login item: %@", error.localizedDescription)
        }
        refreshLoginStatus()
        if on { launchBridge() }
    }

    func refreshLoginStatus() {
        let s = loginItem.status
        launchAtLogin = s == .enabled || s == .requiresApproval
        needsApproval = s == .requiresApproval
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// Abre el puente si no está corriendo / Opens the bridge if not running
    func launchBridge() {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: SharedSettings.bridgeBundleID)
        guard running.isEmpty else { return }
        let url = Bundle.main.bundleURL.appendingPathComponent(SharedSettings.bridgeRelativePath)
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        NSWorkspace.shared.openApplication(at: url, configuration: config)
    }
}
