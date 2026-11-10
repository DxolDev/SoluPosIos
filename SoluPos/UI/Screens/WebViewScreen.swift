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
    @State private var showPriceTip = false
    @State private var frames: [String: CGRect] = [:]
    // Consultador de precios dentro del POS
    @State private var scannerForPrice = false
    @State private var priceResult: PriceResultItem?
    private let priceLookup: PriceLookupService = PriceLookupProvider.create()
    @State private var printOutcome: PrintOutcome?
    @State private var previewItem: PrintPreviewItem?

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

            if !posSteps.isEmpty {
                TutorialOverlay(steps: posSteps, onFinish: {
                    showTutorial = false
                    showPriceTip = false
                    prefs.webViewTutorialSeen = true
                    if Features.priceCheckEnabled { prefs.priceTipPosSeen = true }
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
                        showScanner = false      // quita el overlay al instante
                        if scannerForPrice {
                            scannerForPrice = false
                            lookupPrice(barcode)
                        } else {
                            injectBarcode(barcode)   // inyecta en el WebView vivo detrás
                        }
                    },
                    onCancel: { showScanner = false; scannerForPrice = false }
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
                        .tutorialTarget("back")
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
        // Resultado del consultador: el item vive en @State (id estable), no se deriva en el binding.
        .sheet(item: Features.priceCheckEnabled ? $priceResult : .constant(nil)) { item in
            PriceResultSheet(
                result: item.result,
                scannedCode: item.code,
                today: LocalDate.today(),
                onClose: { priceResult = nil },
                onScanAnother: {
                    priceResult = nil
                    scannerForPrice = true
                    showScanner = true
                }
            )
            .presentationDetents([.medium, .large])
        }
        .onPreferenceChange(TutorialFrames.self) { frames = $0 }
        .overlay(printOutcomeOverlay)
        .onAppear {
            if Features.priceCheckEnabled && !prefs.priceTipPosSeen { showPriceTip = true }
            prefs.lastStoreId = store.id
            printHandler.onPrint = { [self] in
                Task { await handlePrint() }
            }
            if !prefs.webViewTutorialSeen { showTutorial = true }
        }
    }

    // MARK: - Floating buttons

    private var floatingButtons: some View {
        VStack(spacing: 8) {
            // El botón "volver a tiendas" del Android es innecesario en iOS:
            // el NavigationStack ya provee el botón atrás nativo (chevron).
            // Consultar precio: botón pequeño sobre el del escáner (bottom 88 pt, end 24 pt).
            if Features.priceCheckEnabled {
            Button {
                closeKeyboard()
                scannerForPrice = true
                showScanner = true
            } label: {
                Image(systemName: "tag.fill")
                    .font(.system(size: 18))
                    .frame(width: 40, height: 40)
                    .background(Color(.systemBackground))
                    .foregroundStyle(Color.brandBlue)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 4)
            }
            .accessibilityLabel("Consultar precio")
            .tutorialTarget("price")
            .padding(.trailing, 8)
            }

            Button {
                // Igual que Android: antes de abrir el escáner ocultamos el teclado
                // y desenfocamos. El destino del escaneo NO se recuerda — lo resuelve
                // el JS del inyector (primer input del POS) al momento de inyectar.
                closeKeyboard()
                scannerForPrice = false
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
            .tutorialTarget("scanner")
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

    // MARK: - Tutorial del POS

    private var posSteps: [TutorialStep] {
        var steps: [TutorialStep] = []
        let priceStep = frames["price"].flatMap { f in
            (Features.priceCheckEnabled && showPriceTip) ? TutorialStep(
                title: "Consulta precios sin salir de la venta",
                message: "Escanea un producto para ver su precio, su oferta y si hay existencia. No modifica el carrito.",
                highlightFrame: f) : nil
        }
        if showTutorial, let scanner = frames["scanner"] {
            steps.append(TutorialStep(
                title: "Escanea productos",
                message: "Toca este botón para escanear códigos de barras o QR con la cámara y agregarlos a la venta.",
                highlightFrame: scanner))
            if let priceStep { steps.append(priceStep) }
            if let back = frames["back"] {
                steps.append(TutorialStep(
                    title: "Volver a tus tiendas",
                    message: "Usa este botón para retroceder dentro del POS; si ya estás al inicio, vuelves a la lista de tiendas.",
                    highlightFrame: back))
            }
        } else if !showTutorial, let priceStep {
            steps.append(priceStep)
        }
        return steps
    }

    // MARK: - Consultador de precios

    private func lookupPrice(_ barcode: String) {
        let storeId = store.id
        Task {
            let query = CodeInterpreter.interpret(barcode)
            let result: LookupResult = query == .unrecognized
                ? .unrecognized
                : await priceLookup.lookup(storeId: storeId, query: query)
            priceResult = PriceResultItem(code: barcode, result: result)
        }
    }

    // MARK: - Scanner injection

    private func injectBarcode(_ barcode: String) {
        // Guard explícito (no optional chaining) para no saltar la inyección en
        // silencio si el WebView aún no existe.
        guard let webView else { return }
        webView.evaluateJavaScript(BarcodeInjector.buildScript(barcode: barcode), completionHandler: nil)
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

private struct PriceResultItem: Identifiable {
    let id = UUID()
    let code: String
    let result: LookupResult
}

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
