import SwiftUI

struct TutorialStep {
    var title: String? = nil
    let message: String
    let highlightFrame: CGRect
}

/// Frames (coordenadas globales) de los elementos que el tutorial puede señalar.
struct TutorialFrames: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    func tutorialTarget(_ id: String) -> some View {
        background(
            GeometryReader { g in
                Color.clear.preference(key: TutorialFrames.self, value: [id: g.frame(in: .global)])
            }
        )
    }
}

/// Overlay tipo "spotlight": oscurece la pantalla y perfora un hueco alrededor del
/// objetivo. Si el objetivo es ancho (width > 2*height, p. ej. el botón de una
/// tarjeta) el hueco es un rectángulo redondeado (relleno 8, radio 24); si no,
/// un círculo (radio = mitad del lado mayor + 20). Igual que en Android.
struct TutorialOverlay: View {
    let steps: [TutorialStep]
    let onFinish: () -> Void

    @State private var currentStep = 0

    var body: some View {
        if steps.isEmpty {
            Color.clear.onAppear(perform: onFinish)
        } else {
            GeometryReader { geo in
                let step = steps[min(currentStep, steps.count - 1)]
                let lowerHalf = step.highlightFrame.midY > geo.size.height / 2
                ZStack {
                    Color.black.opacity(0.78)
                        .ignoresSafeArea()
                        .mask(spotlightMask(step.highlightFrame))
                        .contentShape(Rectangle())
                        .onTapGesture { }   // bloquea toques hacia lo de abajo

                    VStack {
                        if !lowerHalf { Spacer() }
                        callout(step)
                            .padding(24)
                        if lowerHalf { Spacer() }
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: currentStep)
            }
            .ignoresSafeArea()
        }
    }

    private func spotlightMask(_ b: CGRect) -> some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
            ctx.blendMode = .destinationOut
            if b.width > b.height * 2 {
                let rect = b.insetBy(dx: -8, dy: -8)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 24), with: .color(.black))
            } else {
                let r = max(b.width, b.height) / 2 + 20
                let rect = CGRect(x: b.midX - r, y: b.midY - r, width: 2 * r, height: 2 * r)
                ctx.fill(Path(ellipseIn: rect), with: .color(.black))
            }
        }
        .ignoresSafeArea()
    }

    private func callout(_ step: TutorialStep) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = step.title {
                Text(title).font(.system(size: 17, weight: .bold)).foregroundStyle(.primary)
            }
            Text(step.message).font(.system(size: 15)).foregroundStyle(.primary)
            HStack {
                Button("Omitir", action: onFinish)
                Spacer()
                Button(currentStep < steps.count - 1 ? "Siguiente" : "Entendido") {
                    if currentStep < steps.count - 1 { currentStep += 1 } else { onFinish() }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
