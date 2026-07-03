import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var prefs: UserPreferences

    var body: some View {
        NavigationStack {
            StoreListView()
        }
    }
}
