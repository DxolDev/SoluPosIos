import Foundation
import CoreBluetooth
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

    // Tamaño de tira para evitar que el PT-210 encoja imágenes altas (puerto de Android)
    static let stripHeightPx = 128

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: DispatchQueue.global(qos: .userInitiated))
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
        guard let data = ReceiptCapture.toEscPosRaster(image: image) else {
            return .captureFailed
        }
        // Enviar en tiras de 128px (mismo workaround que Android: el PT-210 encoge imágenes altas)
        return await sendData(data, config: config)
    }

    // MARK: - Private Send

    private func sendData(_ data: Data, config: UserPreferences.PrinterConfig) async -> PrintOutcome {
        guard let peripheral = peripheral,
              let characteristic = writeCharacteristic else {
            return .error(message: "No hay conexión con la impresora. Conecta primero.")
        }
        return await withCheckedContinuation { continuation in
            self.pendingData = data
            self.dataOffset = 0
            self.sendCompletion = { result in
                switch result {
                case .success: continuation.resume(returning: .success)
                case .failure(let e): continuation.resume(returning: .error(message: e.localizedDescription))
                }
            }
            sendNextChunk(peripheral: peripheral, characteristic: characteristic)
        }
    }

    private func sendNextChunk(peripheral: CBPeripheral, characteristic: CBCharacteristic) {
        guard var data = pendingData else { return }
        guard dataOffset < data.count else {
            sendCompletion?(.success(()))
            pendingData = nil
            sendCompletion = nil
            return
        }

        let mtu = peripheral.maximumWriteValueLength(for: .withoutResponse)
        let chunkSize = min(mtu, data.count - dataOffset)
        let chunk = data.subdata(in: dataOffset..<(dataOffset + chunkSize))

        if peripheral.canSendWriteWithoutResponse {
            peripheral.writeValue(chunk, for: characteristic, type: .withoutResponse)
            dataOffset += chunkSize
            // Recursión para el siguiente chunk sin bloquear el thread
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.sendNextChunk(peripheral: peripheral, characteristic: characteristic)
            }
        }
        // Si no puede enviar, peripheralIsReady(toSendWriteWithoutResponse:) disparará el siguiente chunk
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
        for char in characteristics {
            if char.properties.contains(.write) || char.properties.contains(.writeWithoutResponse) {
                writeCharacteristic = char
                DispatchQueue.main.async {
                    self.connectionState = .connected(deviceName: peripheral.name ?? peripheral.identifier.uuidString)
                }
                return
            }
        }
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        guard let char = writeCharacteristic else { return }
        sendNextChunk(peripheral: peripheral, characteristic: char)
    }
}
