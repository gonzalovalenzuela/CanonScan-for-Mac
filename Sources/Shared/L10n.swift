// L10n.swift
// Textos traducidos (es / en) desde Localizable.strings.
// Translated strings (es / en) from Localizable.strings.

import Foundation

/// Devuelve el texto en el idioma del sistema / Returns the text in the system language
func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

/// Igual que L() pero con argumentos de formato / Same as L() with format arguments
func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: NSLocalizedString(key, comment: ""), arguments: args)
}
