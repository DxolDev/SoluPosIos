import SwiftUI
import CoreBluetooth

struct PrinterSettingsView: View {
    @EnvironmentObject private var prefs: UserPreferences
    @StateObject private var printerManager = BLEPrinterManager()
    @State private var testImage: UIImage?

    var body: some View {
        Form {
            scanSection
            selectedSection
            paperWidthSection
            statusSection
        }
        .navigationTitle("Configurar impresora")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { printerManager.stopScan() }
    }

    // MARK: - Secciones

    private var scanSection: some View {
        Section("Buscar impresora") {
            if printerManager.discoveredDevices.isEmpty && !printerManager.connectionState.isLoading {
                Text("Enciende la impresora y toca Buscar.")
                    .foregroundStyle(.secondary)
            }
            ForEach(printerManager.discoveredDevices, id: \.identifier) { device in
                Button {
                    printerManager.connect(to: device)
                    prefs.printerConfig = UserPreferences.PrinterConfig(
                        peripheralId: device.identifier.uuidString,
                        name: device.name ?? device.identifier.uuidString,
                        paperWidthMm: prefs.printerConfig?.paperWidthMm ?? 58
                    )
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(device.name ?? "Dispositivo sin nombre")
                                .foregroundStyle(.primary)
                            Text(device.identifier.uuidString)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if prefs.printerConfig?.peripheralId == device.identifier.uuidString {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
            Button {
                printerManager.startScan()
            } label: {
                Label(
                    printerManager.connectionState.isLoading ? "Buscando..." : "Buscar impresoras",
                    systemImage: "magnifyingglass"
                )
            }
            .disabled(printerManager.connectionState.isLoading)
        }
    }

    private var selectedSection: some View {
        Section("Impresora seleccionada") {
            if let config = prefs.printerConfig {
                LabeledContent("Nombre", value: config.name)
                LabeledContent("ID", value: config.peripheralId.prefix(8) + "...")
                Button("Olvidar impresora", role: .destructive) {
                    prefs.clearPrinterConfig()
                    printerManager.disconnect()
                }
            } else {
                Text("Ninguna seleccionada")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var paperWidthSection: some View {
        Section("Ancho de papel") {
            Picker("Papel", selection: Binding(
                get: { prefs.printerConfig?.paperWidthMm ?? 58 },
                set: { mm in
                    if var config = prefs.printerConfig {
                        config.paperWidthMm = mm
                        prefs.printerConfig = config
                    }
                }
            )) {
                Text("58 mm").tag(58)
                Text("80 mm").tag(80)
            }
            .pickerStyle(.segmented)
        }
    }

    private var statusSection: some View {
        Section("Estado") {
            stateRow
            if prefs.printerConfig != nil {
                Button("Imprimir prueba") {
                    Task { await sendTestPrint() }
                }
                .disabled(printerManager.connectionState.isLoading)
            }
        }
    }

    @ViewBuilder
    private var stateRow: some View {
        switch printerManager.connectionState {
        case .idle:
            Text("Sin conexión activa").foregroundStyle(.secondary)
        case .scanning:
            HStack { ProgressView(); Text("Buscando...").padding(.leading, 8) }
        case .connecting:
            HStack { ProgressView(); Text("Conectando...").padding(.leading, 8) }
        case .connected(let name):
            Label("Conectado: \(name)", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .error(let msg):
            Label(msg, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }

    // MARK: - Test print

    private func sendTestPrint() async {
        guard let config = prefs.printerConfig else { return }
        let width = UserPreferences.printableDots(paperWidthMm: config.paperWidthMm)
        let image = makeTestImage(widthPx: width)
        _ = await printerManager.printBitmap(image, config: config)
    }

    private func makeTestImage(widthPx: Int) -> UIImage {
        let size = CGSize(width: CGFloat(widthPx), height: 200)
        UIGraphicsBeginImageContextWithOptions(size, true, 1.0)
        UIColor.white.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        let text = "SoluPos\nPrueba de impresión\n✓ Impresora configurada"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 22),
            .foregroundColor: UIColor.black
        ]
        (text as NSString).draw(
            in: CGRect(x: 12, y: 20, width: CGFloat(widthPx) - 24, height: 160),
            withAttributes: attrs
        )
        let image = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        UIGraphicsEndImageContext()
        return image
    }
}
