// SharedSettings.swift
// Ajustes compartidos entre CanonScan y el puente AirScan.
// Settings shared between CanonScan and the AirScan bridge.

import Foundation

enum SharedSettings {
    /// Dominio de ajustes de la app principal / Main app's defaults domain
    static let suite = "cl.local.canonscan"
    /// Aviso entre procesos cuando cambia el puente / Cross-process notice when the bridge changes
    static let bridgeChanged = Notification.Name("cl.local.canonscan.bridgeChanged")
    static let bridgeBundleID = "cl.local.canonscan.bridge"
    /// Ruta del puente dentro de CanonScan.app / Bridge path inside CanonScan.app
    static let bridgeRelativePath = "Contents/Library/LoginItems/CanonScanBridge.app"

    static var defaults: UserDefaults { UserDefaults(suiteName: suite) ?? .standard }

    /// Puente encendido (por defecto sí) / Bridge enabled (default on)
    static var bridgeEnabled: Bool {
        get { defaults.object(forKey: "bridgeEnabled") as? Bool ?? true }
        set {
            defaults.set(newValue, forKey: "bridgeEnabled")
            notifyChange()
        }
    }

    static var useManualHost: Bool { defaults.bool(forKey: "useManualHost") }
    static var manualHost: String {
        (defaults.string(forKey: "manualHost") ?? "").trimmingCharacters(in: .whitespaces)
    }

    static func notifyChange() {
        DistributedNotificationCenter.default().postNotificationName(
            bridgeChanged, object: nil, userInfo: nil, deliverImmediately: true)
    }
}
