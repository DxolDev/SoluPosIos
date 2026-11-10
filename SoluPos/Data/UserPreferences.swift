import Foundation

final class UserPreferences: ObservableObject {
    static let shared = UserPreferences()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let lastStoreId = "lastStoreId"
        static let printerConfig = "printerConfig"
        static let tutorialSeen = "tutorialSeen"
        static let webViewTutorialSeen = "webViewTutorialSeen"
        // Avisos del consultador de precios: se muestran una vez, también a quien ya vio el tutorial original.
        static let priceTipListSeen = "has_seen_price_tip_list"
        static let priceTipPosSeen = "has_seen_price_tip_pos"
    }

    struct PrinterConfig: Codable {
        var peripheralId: String  // CBPeripheral.identifier.uuidString
        var name: String
        var paperWidthMm: Int
        var serviceUUID: String
        var characteristicUUID: String

        init(peripheralId: String, name: String, paperWidthMm: Int = 58,
             serviceUUID: String = "", characteristicUUID: String = "") {
            self.peripheralId = peripheralId
            self.name = name
            self.paperWidthMm = paperWidthMm
            self.serviceUUID = serviceUUID
            self.characteristicUUID = characteristicUUID
        }
    }

    @Published var lastStoreId: String? {
        didSet { defaults.set(lastStoreId, forKey: Keys.lastStoreId) }
    }

    @Published var printerConfig: PrinterConfig? {
        didSet {
            if let config = printerConfig,
               let data = try? JSONEncoder().encode(config) {
                defaults.set(data, forKey: Keys.printerConfig)
            } else {
                defaults.removeObject(forKey: Keys.printerConfig)
            }
        }
    }

    @Published var tutorialSeen: Bool {
        didSet { defaults.set(tutorialSeen, forKey: Keys.tutorialSeen) }
    }

    @Published var webViewTutorialSeen: Bool {
        didSet { defaults.set(webViewTutorialSeen, forKey: Keys.webViewTutorialSeen) }
    }

    @Published var priceTipListSeen: Bool {
        didSet { defaults.set(priceTipListSeen, forKey: Keys.priceTipListSeen) }
    }

    @Published var priceTipPosSeen: Bool {
        didSet { defaults.set(priceTipPosSeen, forKey: Keys.priceTipPosSeen) }
    }

    private init() {
        lastStoreId = defaults.string(forKey: Keys.lastStoreId)
        tutorialSeen = defaults.bool(forKey: Keys.tutorialSeen)
        webViewTutorialSeen = defaults.bool(forKey: Keys.webViewTutorialSeen)
        priceTipListSeen = defaults.bool(forKey: Keys.priceTipListSeen)
        priceTipPosSeen = defaults.bool(forKey: Keys.priceTipPosSeen)

        if let data = defaults.data(forKey: Keys.printerConfig),
           let config = try? JSONDecoder().decode(PrinterConfig.self, from: data) {
            printerConfig = config
        } else {
            printerConfig = nil
        }
    }

    func clearPrinterConfig() {
        printerConfig = nil
    }

    func resetTutorials() {
        tutorialSeen = false
        webViewTutorialSeen = false
        priceTipListSeen = false
        priceTipPosSeen = false
    }

    static func printableDots(paperWidthMm: Int) -> Int {
        paperWidthMm <= 58 ? 384 : 576
    }

    static func printableMm(paperWidthMm: Int) -> Float {
        Float(printableDots(paperWidthMm: paperWidthMm)) * 25.4 / 203.0
    }
}
