import SwiftUI

struct TutorialStep {
    let message: String
    let highlightFrame: CGRect
}

struct TutorialOverlay: View {
    let steps: [TutorialStep]
    let onDismiss: () -> Void

    @State private var currentStep = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.65)
                .ignoresSafeArea()
                .mask(spotlightMask)
                .allowsHitTesting(true)
                .onTapGesture(perform: advance)

            VStack {
                Spacer()
                callout
                    .padding()
                    .padding(.bottom, 20)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: currentStep)
    }

    private var spotlight: CGRect {
        guard steps.indices.contains(currentStep) else { return .zero }
        return steps[currentStep].highlightFrame.insetBy(dx: -12, dy: -12)
    }

    private var spotlightMask: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
            ctx.blendMode = .destinationOut
            let path = Path(roundedRect: spotlight, cornerRadius: 12)
            ctx.fill(path, with: .color(.black))
        }
        .ignoresSafeArea()
    }

    private var callout: some View {
        VStack(alignment: .leading, spacing: 12) {
            if steps.indices.contains(currentStep) {
                Text(steps[currentStep].message)
                    .font(.body)
                    .foregroundStyle(.white)
            }
            HStack {
                Text("\(currentStep + 1) / \(steps.count)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Button(currentStep < steps.count - 1 ? "Siguiente" : "Entendido") {
                    advance()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func advance() {
        if currentStep < steps.count - 1 {
            currentStep += 1
        } else {
            onDismiss()
        }
    }
}

struct StoreListTutorialOverlay: View {
    let onDismiss: () -> Void

    @State private var printerFrame: CGRect = .zero
    @State private var addFrame: CGRect = .zero

    var body: some View {
        GeometryReader { geo in
            TutorialOverlay(
                steps: [
                    TutorialStep(
                        message: "Toca el ícono de impresora para configurar tu impresora térmica PT-210.",
                        highlightFrame: printerFrame
                    ),
                    TutorialStep(
                        message: "Toca + para agregar una nueva tienda con su nombre y URL del POS.",
                        highlightFrame: addFrame
                    )
                ],
                onDismiss: onDismiss
            )
        }
        .onPreferenceChange(PrinterButtonFrameKey.self) { printerFrame = $0 }
        .onPreferenceChange(AddButtonFrameKey.self) { addFrame = $0 }
    }
}

// Preference keys para capturar los frames de los botones
struct PrinterButtonFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

struct AddButtonFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}
