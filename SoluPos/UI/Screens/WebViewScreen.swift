import SwiftUI
import WebKit
import Combine

struct WebViewScreen: View {
    let store: Store

    @EnvironmentObject private var prefs: UserPreferences
    @Environment(\.dismiss) private var dismiss

    @State private var webView: WKWebView?
    @State private var showScanner = false
    @State private var showTutorial = false
    @State private var keyboardVisible = false
    @State private var printOutcome: PrintOutcome?
    @State private var previewImage: UIImage?

    private let printHandler = PrintMessageHandler()
    @EnvironmentObject private var printerManager: BLEPrinterManager

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let url = URL(string: store.url) {
                POSWebView(
                    url: url,
                    printHandler: printHandler,
                    webViewRef: { webView = $0 }
                )
                .ignoresSafeArea()
            } else {
                ContentUnavailableView(
                    "URL inválida",
                    systemImage: "exclamationmark.triangle",
                    description: Text(store.url)
                )
            }

            if !keyboardVisible {
                floatingButtons
            }

            if showTutorial {
                WebViewTutorialOverlay(onDismiss: {
                    prefs.webViewTutorialSeen = true
                    showTutorial = false
                })
            }
        }
        .navigationTitle(store.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    // Como Android: retroceder dentro del POS primero;
                    // salir a la lista de tiendas solo si no hay historial.
                    if let wv = webView, wv.canGoBack {
                        wv.goBack()
                    } else {
                        dismiss()
                    }
                } label: {
                    Image(systemName: "chevron.left")
                }
            }
        }
        .sheet(isPresented: $showScanner) {
            ScannerView(
                onResult: { barcode in
                    showScanner = false
                    injectBarcode(barcode)
                },
                onCancel: { showScanner = false }
            )
            .ignoresSafeArea()
        }
        .sheet(item: Binding(
            get: { previewImage.map { PrintPreviewItem(image: $0) } },
            set: { if $0 == nil { previewImage = nil } }
        )) { item in
            PrintPreviewSheet(
                image: item.image,
                onConfirm: {
                    previewImage = nil
                    Task { await sendToPrinter(item.image) }
                },
                onCancel: { previewImage = nil }
            )
        }
        .overlay(printOutcomeOverlay)
        .onAppear {
            prefs.lastStoreId = store.id
            printHandler.onPrint = { [self] in
                Task { await handlePrint() }
            }
            if !prefs.webViewTutorialSeen { showTutorial = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) { keyboardVisible = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) { keyboardVisible = false }
        }
    }

    // MARK: - Floating buttons

    private var floatingButtons: some View {
        VStack(spacing: 12) {
            // El botón "volver a tiendas" del Android es innecesario en iOS:
            // el NavigationStack ya provee el botón atrás nativo (chevron).
            Button {
                showScanner = true
            } label: {
                Image(systemName: "barcode.viewfinder")
                    .font(.title2)
                    .frame(width: 56, height: 56)
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(Circle())
                    .shadow(radius: 6)
            }
        }
        .padding(.trailing, 16)
        .padding(.bottom, 24)
    }

    // MARK: - Print flow

    @MainActor
    private func handlePrint() async {
        guard let wv = webView else {
            printOutcome = .captureFailed
            return
        }
        guard let config = prefs.printerConfig else {
            printOutcome = .notConfigured
            return
        }
        let image = await ReceiptCapture.capture(webView: wv, paperWidthMm: config.paperWidthMm)
        guard let image else {
            printOutcome = .captureFailed
            return
        }
        previewImage = image
    }

    private func sendToPrinter(_ image: UIImage) async {
        guard let config = prefs.printerConfig else { return }
        let outcome = await printerManager.printBitmap(image, config: config)
        await MainActor.run { printOutcome = outcome }
    }

    // MARK: - Scanner injection

    private func injectBarcode(_ barcode: String) {
        webView?.evaluateJavaScript(BarcodeInjector.buildScript(barcode: barcode), completionHandler: nil)
    }

    // MARK: - Outcome snackbar

    @ViewBuilder
    private var printOutcomeOverlay: some View {
        if let outcome = printOutcome {
            VStack {
                Spacer()
                printOutcomeSnackbar(outcome)
                    .padding(.bottom, 80)
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    printOutcome = nil
                }
            }
        }
    }

    @ViewBuilder
    private func printOutcomeSnackbar(_ outcome: PrintOutcome) -> some View {
        switch outcome {
        case .success:
            snackbar("Impreso correctamente", icon: "checkmark.circle.fill", color: .green)
        case .notConfigured:
            snackbar("Configura la impresora primero", icon: "exclamationmark.triangle.fill", color: .orange)
        case .captureFailed:
            snackbar("No se pudo capturar el recibo", icon: "xmark.circle.fill", color: .red)
        case .error(let msg):
            snackbar(msg, icon: "xmark.circle.fill", color: .red)
        }
    }

    private func snackbar(_ text: String, icon: String, color: Color) -> some View {
        Label(text, systemImage: icon)
            .foregroundStyle(color)
            .padding()
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(radius: 4)
            .padding(.horizontal)
    }
}

// MARK: - Helpers

private struct PrintPreviewItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct PrintPreviewSheet: View {
    let image: UIImage
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding()
            }
            .navigationTitle("Vista previa")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Imprimir", action: onConfirm)
                }
            }
        }
    }
}

struct WebViewTutorialOverlay: View {
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()
            VStack {
                Spacer()
                VStack(alignment: .leading, spacing: 16) {
                    tutorialStep(
                        icon: "barcode.viewfinder",
                        title: "Escanear código",
                        body: "Toca el botón azul para abrir la cámara y escanear un código de barras o QR. El código se inyecta directamente en el campo activo del POS."
                    )
                    Divider()
                    tutorialStep(
                        icon: "chevron.left",
                        title: "Volver",
                        body: "Usa el botón atrás para retroceder dentro del POS; si ya estás al inicio, vuelves a la lista de tiendas."
                    )
                    Button("Entendido") { onDismiss() }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                }
                .padding(20)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .padding()
            }
        }
        .onTapGesture(perform: onDismiss)
    }

    private func tutorialStep(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(body).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
