// AdjustControls.swift
// Controles de mejoras de imagen, para la barra lateral y los ajustes de modo.
// Image adjustment controls, for the sidebar and the mode settings.

import SwiftUI

struct AdjustControls: View {
    @Binding var adjust: ImageAdjust
    var showRestore = true
    var showSkipBlank = true
    var showSplit = true

    var body: some View {
        if showSplit {
            Toggle("Varias fotos: un archivo por foto", isOn: $adjust.splitPhotos)
        }
        Toggle("Blanquear fondo", isOn: $adjust.whitenBackground)
        Toggle("Orientación automática", isOn: $adjust.autoOrient)
        if showSkipBlank {
            Toggle("Saltar páginas en blanco", isOn: $adjust.skipBlank)
        }
        if showRestore {
            Toggle("Restaurar colores de fotos antiguas", isOn: $adjust.restoreColors)
        }
        AdjustSlider(title: "Brillo", value: $adjust.brightness)
        AdjustSlider(title: "Contraste", value: $adjust.contrast)
        AdjustSlider(title: "Nitidez", value: $adjust.sharpness)
    }
}

/// Deslizador de −50 a +50 con valor y doble clic para volver a 0.
/// −50 to +50 slider with value and double-click to reset to 0.
struct AdjustSlider: View {
    let title: LocalizedStringKey
    @Binding var value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(value == 0 ? "0" : String(format: "%+.0f", value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .onTapGesture(count: 2) { value = 0 }
                    .help(L("Doble clic para volver a 0"))
            }
            Slider(value: $value, in: -50...50, step: 5)
                .controlSize(.small)
        }
    }
}
