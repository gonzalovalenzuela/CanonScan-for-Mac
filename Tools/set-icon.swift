// set-icon.swift
// Asigna un ícono personalizado de Finder a un archivo.
// Assigns a custom Finder icon to a file.
//
// Uso / Usage: swift set-icon.swift <imagen.png> <archivo>

import AppKit

let args = CommandLine.arguments
guard args.count == 3, let image = NSImage(contentsOfFile: args[1]) else {
    FileHandle.standardError.write("uso: set-icon.swift imagen.png archivo\n".data(using: .utf8)!)
    exit(2)
}
guard NSWorkspace.shared.setIcon(image, forFile: args[2], options: []) else {
    FileHandle.standardError.write("no se pudo asignar el ícono\n".data(using: .utf8)!)
    exit(1)
}
