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
    @State private var printOutcome: PrintOutcome?
    @State private var previewItem: PrintPreviewItem?
    @State private var scanDebug: String?

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

            // El botón del escáner queda siempre visible (también con el teclado
            // abierto), elevado por encima del teclado — así puedes escanear
            // mientras buscas un producto en el POS.
            floatingButtons

            if showTutorial {
                WebViewTutorialOverlay(onDismiss: {
                    prefs.webViewTutorialSeen = true
                    showTutorial = false
                })
            }

            // Escáner como overlay INLINE (port fiel del Android: un Box dentro del
            // mismo contenedor, NO un modal). Al inyectar, el JS hace el.focus() y sube
            // el teclado del WKWebView; con un .fullScreenCover eso ocurría durante la
            // transición de descarte del modal y colgaba el main thread (watchdog →
            // "se congela y se cierra"). Sin modal no hay transición con la que chocar.
            if showScanner {
                ScannerView(
                    onResult: { barcode in
                        injectBarcode(barcode)   // inyecta en el WebView vivo detrás
                        showScanner = false      // quita el overlay al instante
                    },
                    onCancel: { showScanner = false }
                )
                .ignoresSafeArea()
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
        // Ocultar la barra de navegación mientras se escanea: el escáner es un overlay
        // inline a pantalla completa y el chevron atrás no debe quedar sobre la cámara.
        .toolbar(showScanner ? .hidden : .visible, for: .navigationBar)
        // El item se conserva en @State (identidad estable): antes se derivaba en el
        // get de un Binding creando un PrintPreviewItem con UUID() nuevo en cada body
        // eval, y .sheet(item:) lo leía como "item cambió" → descartaba y re-presentaba
        // la hoja en bucle ("sube y baja"). Con el item estable se presenta una vez.
        .sheet(item: $previewItem) { item in
            PrintPreviewSheet(
                image: item.image,
                onConfirm: {
                    let img = item.image
                    previewItem = nil
                    Task { await sendToPrinter(img) }
                },
                onCancel: { previewItem = nil }
            )
        }
        .overlay(printOutcomeOverlay)
        .overlay(scanDebugOverlay)
        .onAppear {
            prefs.lastStoreId = store.id
            printHandler.onPrint = { [self] in
                Task { await handlePrint() }
            }
            if !prefs.webViewTutorialSeen { showTutorial = true }
        }
    }

    // MARK: - Floating buttons

    private var floatingButtons: some View {
        VStack(spacing: 12) {
            // El botón "volver a tiendas" del Android es innecesario en iOS:
            // el NavigationStack ya provee el botón atrás nativo (chevron).
            Button {
                // Igual que Android: antes de abrir el escáner ocultamos el teclado
                // y desenfocamos. El destino del escaneo NO se recuerda — lo resuelve
                // el JS del inyector (primer input del POS) al momento de inyectar.
                closeKeyboard()
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
        // El botón sube SOLO con el keyboard-avoidance NATIVO de SwiftUI (equivalente al
        // imePadding de Android): al aparecer el teclado, SwiftUI reduce el safe area
        // inferior del ZStack y este botón —anclado abajo y que SÍ respeta el safe area—
        // queda justo encima del teclado. El POSWebView no se mueve porque tiene
        // .ignoresSafeArea(). (Antes había además un tracking MANUAL de keyboardHeight que
        // se sumaba al nativo → doble desplazamiento → el botón terminaba arriba del todo.)
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
        previewItem = PrintPreviewItem(image: image)
    }

    private func sendToPrinter(_ image: UIImage) async {
        guard let config = prefs.printerConfig else { return }
        let outcome = await printerManager.printBitmap(image, config: config)
        await MainActor.run { printOutcome = outcome }
    }

    // MARK: - Scanner injection

    private func injectBarcode(_ barcode: String) {
        print("[SCAN] injectBarcode(\"\(barcode)\") — webView disponible: \(webView != nil)")
        guard let webView else {
            // Nunca fallar en silencio: si no hay WebView, dejarlo en consola y en
            // el overlay. (Antes el optional chaining se saltaba la inyección sin
            // rastro alguno, que era justo el síntoma reportado.)
            let msg = "⚠️ WebView no disponible al inyectar"
            print("[SCAN] \(msg)")
            scanDebug = msg
            return
        }
        webView.evaluateJavaScript(BarcodeInjector.buildScript(barcode: barcode)) { result, error in
            let message: String
            if let error = error {
                message = "JS error: \(error.localizedDescription)"
            } else if let json = result as? String {
                message = Self.describeScanResult(json)
            } else {
                message = "Sin respuesta del inyector"
            }
            print("[SCAN] resultado inyección: \(message)")
            DispatchQueue.main.async {
                scanDebug = message
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                    if scanDebug == message { scanDebug = nil }
                }
            }
        }
    }

    // Convierte el JSON de diagnóstico del injector en un texto legible.
    private static func describeScanResult(_ json: String) -> String {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "Resultado no parseable"
        }
        let found = obj["found"] as? Bool ?? false
        let inputs = obj["inputCount"] as? Int ?? -1
        let iframes = obj["iframes"] as? Int ?? -1
        if !found {
            return "⚠️ No se encontró campo (inputs: \(inputs), iframes: \(iframes))"
        }
        let tag = obj["tag"] as? String ?? "?"
        let id = obj["id"] as? String ?? ""
        let source = obj["source"] as? String ?? "?"
        let value = obj["valueAfter"] as? String ?? ""
        let idPart = id.isEmpty ? "" : "#\(id)"
        return "✅ \(tag)\(idPart) (\(source)) = \"\(value)\""
    }

    // MARK: - Overlay de diagnóstico del escaneo (temporal)

    @ViewBuilder
    private var scanDebugOverlay: some View {
        if let msg = scanDebug {
            VStack {
                Text(msg)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.top, 8)
                    .padding(.horizontal, 12)
                Spacer()
            }
        }
    }

    // Cierra el teclado nativo (para que no tape la cámara), equivalente al
    // hideSoftInputFromWindow + clearFocus de Android. El blur del input lo hace
    // el propio JS del inyector al escanear (document.activeElement.blur()).
    private func closeKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )
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
