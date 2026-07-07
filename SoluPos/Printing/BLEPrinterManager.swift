import Foundation
@preconcurrency import CoreBluetooth
import UIKit
import Combine

// IMPORTANTE: Antes de usar, identificar los UUIDs reales del PT-210 con LightBlue.
// Los UUIDs de abajo son los más comunes en impresoras térmicas BLE de 58mm.
// Si no coinciden, la app los descubre automáticamente buscando la primera
// característica con propiedad .write o .writeWithoutResponse.
private let knownServiceUUIDs = [
    CBUUID(string: "FF00"),
    CBUUID(string: "49535343-FE7D-4AE5-8FA9-9FAFD205E455")
]

final class BLEPrinterManager: NSObject, ObservableObject {
    @Published var connectionState: PrinterConnectionState = .idle
    @Published var discoveredDevices: [CBPeripheral] = []

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?

    private var pendingData: Data?
    private var sendCompletion: ((Result<Void, Error>) -> Void)?
    private var dataOffset = 0
    // Modo de escritura elegido al descubrir la característica: .withResponse (con ACK,
    // control de flujo real) si la característica lo soporta; .withoutResponse (pacing
    // manual) como fallback.
    private var writeType: CBCharacteristicWriteType = .withoutResponse
    // Watchdog por franja: falla el envío si nunca llega la confirmación esperada,
    // para no colgar la impresión indefinidamente.
    private var sendWatchdog: DispatchWorkItem?

    // Tamaño de tira para evitar que el PT-210 encoja imágenes altas (puerto de Android)
    static let stripHeightPx = 128

    // Pausa entre franjas para no desbordar el buffer de la PT-210: BLE .withoutResponse
    // no tiene ACK del periférico, así que hay que darle tiempo real de impresión
    // (mecánico) antes de mandar la siguiente franja. Valor de partida empírico — si el
    // papel sigue saliendo con texto corrupto, subir este valor (o bajar stripHeightPx).
    static let interStripDelayNs: UInt64 = 120_000_000 // 120ms

    // Cola serial dedicada para el delegate del CBCentralManager y los re-disparos
    // recursivos de sendNextChunk: DispatchQueue.global(qos:) es concurrente, así que
    // peripheralIsReady(toSendWriteWithoutResponse:) y la recursión de sendNextChunk
    // podían correr al mismo tiempo en hilos distintos y competir por dataOffset/
    // pendingData sin sincronización, corrompiendo los bytes enviados a la impresora.
    private let bleQueue = DispatchQueue(label: "com.solupos.contenedor.ble-printer")

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: bleQueue)
    }

    // MARK: - Scan

    func startScan() {
        discoveredDevices = []
        connectionState = .scanning
        if central.state == .poweredOn {
            central.scanForPeripherals(withServices: nil, options: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
                self?.stopScan()
            }
        }
    }

    func stopScan() {
        central.stopScan()
        if case .scanning = connectionState { connectionState = .idle }
    }

    // MARK: - Connect & Print

    func connect(to peripheral: CBPeripheral) {
        stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        connectionState = .connecting
        central.connect(peripheral, options: nil)
    }

    func printBitmap(_ image: UIImage, config: UserPreferences.PrinterConfig) async -> PrintOutcome {
        // Enviar en tiras de 128px (mismo workaround que Android: el PT-210 encoge imágenes altas)
        guard let strips = ReceiptCapture.toEscPosRasterStrips(image: image, stripHeightPx: Self.stripHeightPx) else {
            return .captureFailed
        }
        // Cada tira se envía y se espera por separado (con pausa) para no desbordar el
        // buffer de la impresora: BLE .withoutResponse no tiene ACK del periférico.
        for strip in strips {
            let outcome = await sendData(strip, config: config)
            if case .success = outcome {} else { return outcome }
            try? await Task.sleep(nanoseconds: Self.interStripDelayNs)
        }
        return .success
    }

    // MARK: - Private Send

    private func sendData(_ data: Data, config: UserPreferences.PrinterConfig) async -> PrintOutcome {
        guard let peripheral = peripheral,
              let characteristic = writeCharacteristic else {
            return .error(message: "No hay conexión con la impresora. Conecta primero.")
        }
        return await withCheckedContinuation { continuation in
            // Todo el envío arranca y corre dentro de bleQueue (cola serial) para
            // serializar con los callbacks del delegate y garantizar visibilidad de
            // memoria de pendingData/dataOffset.
            bleQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: .error(message: "Impresora no disponible"))
                    return
                }
                self.pendingData = data
                self.dataOffset = 0
                self.sendCompletion = { result in
                    switch result {
                    case .success: continuation.resume(returning: .success)
                    case .failure(let e): continuation.resume(returning: .error(message: e.localizedDescription))
                    }
                }
                // Watchdog: si el envío de esta franja no termina en 15s (p.ej. el
                // periférico nunca manda el ACK esperado), falla en vez de colgar.
                let watchdog = DispatchWorkItem { [weak self] in
                    self?.finishSend(.failure(NSError(domain: "BLEPrinter", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Tiempo de espera agotado enviando a la impresora"])))
                }
                self.sendWatchdog = watchdog
                self.bleQueue.asyncAfter(deadline: .now() + 15, execute: watchdog)
                self.sendNextChunk(peripheral: peripheral, characteristic: characteristic)
            }
        }
    }

    private func sendNextChunk(peripheral: CBPeripheral, characteristic: CBCharacteristic) {
        // Siempre en bleQueue: nunca corre concurrentemente consigo mismo.
        guard let data = pendingData else { return }
        guard dataOffset < data.count else {
            finishSend(.success(()))
            return
        }

        let mtu = peripheral.maximumWriteValueLength(for: writeType)
        let chunkSize = min(mtu, data.count - dataOffset)
        let chunk = data.subdata(in: dataOffset..<(dataOffset + chunkSize))

        switch writeType {
        case .withResponse:
            // Control de flujo real: se escribe un paquete y el ACK del periférico
            // (didWriteValueFor) dispara el siguiente. Un envío en vuelo a la vez.
            peripheral.writeValue(chunk, for: characteristic, type: .withResponse)
            dataOffset += chunkSize
        case .withoutResponse:
            // Sin ACK: pacing manual. Se respeta la cola local (canSend) y se espacian
            // los paquetes en proporción a su tamaño (~12 bytes/ms, por debajo de lo que
            // imprime la PT-210) para que su buffer se vacíe y no se desborde.
            guard peripheral.canSendWriteWithoutResponse else {
                scheduleNextChunk(afterMs: 8, peripheral, characteristic)
                return
            }
            peripheral.writeValue(chunk, for: characteristic, type: .withoutResponse)
            dataOffset += chunkSize
            scheduleNextChunk(afterMs: max(4, chunkSize / 12), peripheral, characteristic)
        @unknown default:
            finishSend(.failure(NSError(domain: "BLEPrinter", code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Tipo de escritura no soportado"])))
        }
    }

    private func scheduleNextChunk(afterMs ms: Int, _ peripheral: CBPeripheral, _ characteristic: CBCharacteristic) {
        bleQueue.asyncAfter(deadline: .now() + .milliseconds(ms)) { [weak self] in
            self?.sendNextChunk(peripheral: peripheral, characteristic: characteristic)
        }
    }

    private func finishSend(_ result: Result<Void, Error>) {
        // Siempre en bleQueue. Resume la continuación exactamente una vez.
        sendWatchdog?.cancel()
        sendWatchdog = nil
        guard let completion = sendCompletion else { return }
        sendCompletion = nil
        pendingData = nil
        completion(result)
    }

    // MARK: - Disconnect

    func disconnect() {
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        peripheral = nil
        writeCharacteristic = nil
        connectionState = .idle
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEPrinterManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            // Listo para escanear
        } else {
            connectionState = .error(message: "Bluetooth no disponible: \(central.state.rawValue)")
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        guard peripheral.name != nil else { return }
        DispatchQueue.main.async {
            if !self.discoveredDevices.contains(where: { $0.identifier == peripheral.identifier }) {
                self.discoveredDevices.append(peripheral)
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        DispatchQueue.main.async {
            self.connectionState = .error(message: error?.localizedDescription ?? "Error al conectar")
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        DispatchQueue.main.async {
            self.connectionState = .idle
        }
        writeCharacteristic = nil
    }
}

// MARK: - CBPeripheralDelegate

extension BLEPrinterManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let services = peripheral.services else {
            DispatchQueue.main.async { self.connectionState = .error(message: "Error descubriendo servicios") }
            return
        }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard error == nil, let characteristics = service.characteristics else { return }
        // Preferir una característica con .write (escritura con respuesta/ACK → control
        // de flujo real, evita desbordar el buffer de la impresora). Sólo si no hay
        // ninguna, caer en .writeWithoutResponse (con pacing manual). didDiscover... se
        // llama una vez por servicio: la rama .write siempre "sube de categoría", y la
        // de fallback sólo actúa si aún no se eligió nada.
        if let writable = characteristics.first(where: { $0.properties.contains(.write) }) {
            writeCharacteristic = writable
            writeType = .withResponse
            setConnected(peripheral)
            return
        }
        if writeCharacteristic == nil,
           let woResp = characteristics.first(where: { $0.properties.contains(.writeWithoutResponse) }) {
            writeCharacteristic = woResp
            writeType = .withoutResponse
            setConnected(peripheral)
        }
    }

    private func setConnected(_ peripheral: CBPeripheral) {
        DispatchQueue.main.async {
            self.connectionState = .connected(deviceName: peripheral.name ?? peripheral.identifier.uuidString)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didWriteValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        // Sólo se usa en modo .withResponse: el ACK de cada escritura dispara el
        // siguiente chunk (control de flujo). Corre en bleQueue.
        if let error = error {
            finishSend(.failure(error))
            return
        }
        sendNextChunk(peripheral: peripheral, characteristic: characteristic)
    }

    // Nota: no implementamos peripheralIsReady(toSendWriteWithoutResponse:) para avanzar
    // el envío. El modo .withoutResponse se auto-agenda con pacing en sendNextChunk y el
    // modo .withResponse lo hace didWriteValueFor; tener un segundo "driver" duplicaría
    // envíos y reintroduciría la corrupción.
}
