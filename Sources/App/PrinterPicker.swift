// PrinterPicker.swift
// Conexión con la impresora en la barra superior: estado, lista, buscar e IP manual.
// Printer connection in the top bar: status, list, search and manual IP.

import SwiftUI

struct PrinterToolbarButton: View {
    @EnvironmentObject var model: ScanModel
    @EnvironmentObject var browser: PrinterBrowser
    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 6) {
                Circle().fill(statusColor).frame(width: 8, height: 8)
                Text(title).lineLimit(1).truncationMode(.middle)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 260)
        }
        .help(L("Impresora"))
        .popover(isPresented: $open, arrowEdge: .bottom) {
            PrinterPanel()
                .environmentObject(model)
                .environmentObject(browser)
                .frame(width: 320)
                .padding(14)
        }
    }

    private var current: FoundPrinter? {
        browser.printers.first { $0.id == model.selectedPrinterID } ?? browser.printers.first
    }

    private var title: String {
        if model.useManualHost {
            let h = model.manualHost.trimmingCharacters(in: .whitespaces)
            return h.isEmpty ? L("IP manual") : h
        }
        if let p = current { return p.name }
        return browser.searching ? L("Buscando en la red…") : L("Sin impresora")
    }

    private var statusColor: Color {
        if model.targetHost != nil { return .green }
        return browser.searching ? .orange : .secondary
    }
}

/// Panel desplegable con todas las opciones de conexión / Popover with all connection options
struct PrinterPanel: View {
    @EnvironmentObject var model: ScanModel
    @EnvironmentObject var browser: PrinterBrowser

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PrinterStatusRow()

            if !model.useManualHost {
                if browser.printers.count > 1 {
                    Picker("Impresora", selection: Binding(
                        get: { model.selectedPrinterID ?? browser.printers.first?.id },
                        set: { model.selectedPrinterID = $0 }
                    )) {
                        ForEach(browser.printers) { p in Text(p.name).tag(Optional(p.id)) }
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                }
                Button { browser.start() } label: {
                    Label("Buscar de nuevo", systemImage: "arrow.clockwise")
                }
                .disabled(browser.searching)
            }

            Divider()

            Toggle("IP manual", isOn: $model.useManualHost.animation())
                .toggleStyle(.switch)
            if model.useManualHost {
                TextField("Dirección IP", text: $model.manualHost, prompt: Text("192.0.2.10"))
                    .textFieldStyle(.roundedBorder)
            }
        }
    }
}
