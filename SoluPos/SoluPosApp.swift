import SwiftUI
import SwiftData

@main
struct SoluPosApp: App {
    let container: ModelContainer

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
        }
    }
}
