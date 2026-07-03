import SwiftUI
import SwiftData

@main
struct SoluPosApp: App {
    let container: ModelContainer

    // Instancia única compartida: la conexión BLE hecha en Ajustes debe estar
    // disponible al imprimir desde el WebView.
    @StateObject private var printerManager = BLEPrinterManager()

    init() {
        do {
            container = try ModelContainer(for: Store.self)
        } catch {
            fatalError("SwiftData container failed: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(container)
                .environmentObject(UserPreferences.shared)
                .environmentObject(printerManager)
        }
    }
}
