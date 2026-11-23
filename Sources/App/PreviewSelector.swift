// PreviewSelector.swift
// Vista previa del vidrio: arrastra para elegir la zona a escanear.
// Glass preview: drag to choose the region to scan.

import SwiftUI

struct PreviewSelector: View {
    @EnvironmentObject var model: ScanModel
    let image: CGImage

    /// Selección en coordenadas normalizadas 0–1 / Selection in normalized 0–1 coordinates
    @State private var selection: CGRect?
    @State private var dragStart: CGPoint?

    private let glassW = ScanSettings.glassWidthMM
    private let glassH = ScanSettings.glassHeightMM

    var body: some View {
        VStack(spacing: 12) {
            Text("Arrastra sobre la vista previa para elegir la zona.")
                .foregroundStyle(.secondary)

            GeometryReader { geo in
                let size = fitted(in: geo.size)
                ZStack(alignment: .topLeading) {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .frame(width: size.width, height: size.height)
                    // Oscurece fuera de la selección / Dim outside the selection
                    if let s = selection {
                        let r = CGRect(x: s.minX * size.width, y: s.minY * size.height,
                                       width: s.width * size.width, height: s.height * size.height)
                        Path { p in
                            p.addRect(CGRect(origin: .zero, size: size))
                            p.addRect(r)
                        }
                        .fill(Color.black.opacity(0.35), style: FillStyle(eoFill: true))
                        Rectangle()
                            .strokeBorder(Color.scanAccent, style: StrokeStyle(lineWidth: 2, dash: [6, 3]))
                            .frame(width: r.width, height: r.height)
                            .offset(x: r.minX, y: r.minY)
                        Text(L("%@ × %@ mm", ModeBar.mm(s.width * glassW), ModeBar.mm(s.height * glassH)))
                            .font(.caption.monospacedDigit())
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(.regularMaterial, in: Capsule())
                            .offset(x: r.minX + 4, y: max(r.minY - 24, 4))
                    }
                }
                .frame(width: size.width, height: size.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { g in
                            let start = dragStart ?? g.startLocation
                            dragStart = start
                            selection = normalized(from: start, to: g.location, in: size)
                        }
                        .onEnded { _ in dragStart = nil }
                )
                .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            HStack {
                Button("Cerrar") { model.showingPreview = false }
                Spacer()
                Button("Sin zona") {
                    selection = nil
                    model.clearRegion()
                }
                .disabled(selection == nil && model.region == nil)
                Button("Usar zona") {
                    if let s = selection {
                        model.region = ScanRegion(x: s.minX * glassW, y: s.minY * glassH,
                                                  w: s.width * glassW, h: s.height * glassH)
                    }
                    model.showingPreview = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(selection == nil)
            }
        }
        .padding(24)
        .onAppear {
            // Muestra la zona actual si hay / Show the current region if any
            if let r = model.region {
                selection = CGRect(x: r.x / glassW, y: r.y / glassH, width: r.w / glassW, height: r.h / glassH)
            }
        }
    }

    /// Tamaño de la imagen ajustado al espacio disponible / Image size fitted to the available space
    private func fitted(in space: CGSize) -> CGSize {
        let aspect = CGFloat(image.width) / CGFloat(image.height)
        let w = min(space.width, space.height * aspect)
        return CGSize(width: w, height: w / aspect)
    }

    private func normalized(from a: CGPoint, to b: CGPoint, in size: CGSize) -> CGRect {
        let x0 = min(max(min(a.x, b.x), 0), size.width), x1 = min(max(max(a.x, b.x), 0), size.width)
        let y0 = min(max(min(a.y, b.y), 0), size.height), y1 = min(max(max(a.y, b.y), 0), size.height)
        return CGRect(x: x0 / size.width, y: y0 / size.height,
                      width: (x1 - x0) / size.width, height: (y1 - y0) / size.height)
    }
}
