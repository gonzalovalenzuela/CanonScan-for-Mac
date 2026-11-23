// PageEditor.swift
// Editor de una página: girar y recortar a mano. Los cambios quedan en la ventana.
// Single-page editor: rotate and crop by hand. Changes stay in the window.

import SwiftUI

struct PageEditor: View {
    @EnvironmentObject var model: ScanModel
    let page: ScannedPage

    @State private var image: CGImage
    @State private var selection: CGRect?      // normalizada 0–1 / normalized 0–1
    @State private var dragStart: CGPoint?

    init(page: ScannedPage) {
        self.page = page
        _image = State(initialValue: page.image)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Editar página").font(.headline)
                Spacer()
                Button { rotate(clockwise: false) } label: { Image(systemName: "rotate.left") }
                    .help(L("Girar a la izquierda"))
                Button { rotate(clockwise: true) } label: { Image(systemName: "rotate.right") }
                    .help(L("Girar a la derecha"))
                Divider().frame(height: 18)
                Button("Recortar") { applyCrop() }
                    .disabled(selection == nil)
                Button("Restablecer") {
                    image = page.image
                    selection = nil
                }
            }

            Text("Arrastra sobre la imagen para elegir el recorte.")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            GeometryReader { geo in
                let size = fitted(in: geo.size)
                ZStack(alignment: .topLeading) {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .frame(width: size.width, height: size.height)
                        .background(Color.white)
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
                Text("\(image.width) × \(image.height) px").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancelar", role: .cancel) { model.editingPage = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Listo") {
                    model.replace(page, with: image)
                    model.editingPage = nil
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 640, idealWidth: 760, minHeight: 640, idealHeight: 820)
    }

    private func rotate(clockwise: Bool) {
        image = DocumentTools.rotate(image, clockwise: clockwise)
        selection = nil
    }

    private func applyCrop() {
        guard let s = selection, s.width > 0.01, s.height > 0.01 else { return }
        image = DocumentTools.crop(image, normalized: s)
        selection = nil
    }

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
