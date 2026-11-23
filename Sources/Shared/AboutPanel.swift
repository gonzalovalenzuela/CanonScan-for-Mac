// AboutPanel.swift
// Panel «Acerca de» compartido por CanonScan y el puente: versión, copyright,
// enlace al repositorio, créditos y aviso de marcas.
// About panel shared by CanonScan and the bridge: version, copyright,
// repository link, credits and trademark notice.

import AppKit

enum AboutPanel {
    static let repoURL = "https://github.com/gonzalovalenzuela/CanonScan-for-Mac"

    /// Muestra el panel con una descripción propia de cada app.
    /// Shows the panel with a description specific to each app.
    /// `name` reemplaza el nombre del bundle / `name` replaces the bundle name.
    static func show(name: String? = nil, description: String) {
        let credits = NSMutableAttributedString()
        let body: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.labelColor,
        ]
        let note: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        func add(_ s: String, _ a: [NSAttributedString.Key: Any]) {
            credits.append(NSAttributedString(string: s, attributes: a))
        }
        func link(_ title: String, _ url: String) {
            var a = body
            a[.link] = URL(string: url)
            credits.append(NSAttributedString(string: title, attributes: a))
        }

        add(description + "\n\n", body)
        link("github.com/gonzalovalenzuela/CanonScan-for-Mac", repoURL)
        add("\n\n" + L("Cliente CHMP basado en:") + "\n", body)
        link("dfrancio-DF/canon-g3010-sane", "https://github.com/dfrancio-DF/canon-g3010-sane")
        add(" · ", body)
        link("wailun42/canon-g3010-chmp-scanner", "https://github.com/wailun42/canon-g3010-chmp-scanner")
        add(" (MIT)\n\n", body)
        add(L("Canon y PIXMA son marcas de Canon Inc. Este proyecto no está afiliado a Canon."), note)

        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        credits.addAttribute(.paragraphStyle, value: centered, range: NSRange(location: 0, length: credits.length))

        // Trae la app al frente (necesario en el puente de barra de menú).
        // Bring the app to front (needed for the menu bar bridge).
        NSApp.activate(ignoringOtherApps: true)
        var options: [NSApplication.AboutPanelOptionKey: Any] = [.credits: credits]
        if let name { options[.applicationName] = name }
        NSApp.orderFrontStandardAboutPanel(options: options)
    }
}
