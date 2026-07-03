import SwiftUI
import SwiftData

// MARK: - Brand colors
extension Color {
    static let brandDark   = Color(red: 0.08, green: 0.14, blue: 0.55)  // #142390
    static let brandMid    = Color(red: 0.10, green: 0.20, blue: 0.70)  // #1A33B3
    static let brandBlue   = Color(red: 0.15, green: 0.33, blue: 0.92)  // #2655EB
    static let listBg      = Color(red: 0.95, green: 0.95, blue: 0.97)
}

struct StoreListView: View {
    @EnvironmentObject private var prefs: UserPreferences
    @Environment(\.modelContext) private var context
    @Query(sort: \Store.createdAt, order: .reverse) private var stores: [Store]

    @State private var showAddForm = false
    @State private var editingStore: Store?
    @State private var deletingStore: Store?
    @State private var navigateToWebView: Store?
    @State private var showTutorial = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.listBg.ignoresSafeArea()

            VStack(spacing: 0) {
                heroHeader
                if stores.isEmpty {
                    emptyState
                } else {
                    storeList
                }
            }

            // FAB
            Button {
                showAddForm = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 60, height: 60)
                    .background(Color.brandBlue)
                    .clipShape(Circle())
                    .shadow(color: Color.brandBlue.opacity(0.5), radius: 8, x: 0, y: 4)
            }
            .padding(.trailing, 20)
            .padding(.bottom, 28)

            if showTutorial {
                StoreListTutorialOverlay(onDismiss: {
                    prefs.tutorialSeen = true
                    showTutorial = false
                })
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.brandDark, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Mis Tiendas")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    PrinterSettingsView()
                } label: {
                    Image(systemName: "printer")
                        .foregroundStyle(.white)
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showTutorial = true
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .foregroundStyle(.white)
                }
            }
        }
        .sheet(isPresented: $showAddForm) {
            StoreFormView()
        }
        .sheet(item: $editingStore) { store in
            StoreFormView(store: store)
        }
        .confirmationDialog(
            "¿Eliminar tienda?",
            isPresented: Binding(
                get: { deletingStore != nil },
                set: { if !$0 { deletingStore = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Eliminar", role: .destructive) {
                if let s = deletingStore {
                    context.delete(s)
                    try? context.save()
                    deletingStore = nil
                }
            }
        }
        .navigationDestination(item: $navigateToWebView) { store in
            WebViewScreen(store: store)
        }
        .onAppear {
            if !prefs.tutorialSeen { showTutorial = true }
        }
    }

    // MARK: - Hero header

    private var heroHeader: some View {
        ZStack {
            LinearGradient(
                colors: [Color.brandDark, Color.brandMid],
                startPoint: .top,
                endPoint: .bottom
            )
            VStack(spacing: 6) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 60)
                Text("La solución completa para tu punto de venta")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.vertical, 28)
            .padding(.horizontal)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Store list

    private var storeList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(stores) { store in
                    StoreCard(
                        store: store,
                        onOpen: { navigateToWebView = store },
                        onEdit: { editingStore = store },
                        onDelete: { deletingStore = store }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 100)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "storefront")
                .font(.system(size: 60))
                .foregroundStyle(Color.brandBlue.opacity(0.4))
            Text("No hay tiendas configuradas")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Toca el botón + para agregar tu primera tienda.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }
}

// MARK: - StoreCard

private struct StoreCard: View {
    let store: Store
    let onOpen: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            // Avatar círculo azul
            ZStack {
                Circle()
                    .fill(Color.brandBlue)
                    .frame(width: 52, height: 52)
                Image(systemName: "storefront.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(store.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(store.url)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Menu {
                Button("Abrir", systemImage: "globe", action: onOpen)
                Button("Editar", systemImage: "pencil", action: onEdit)
                Divider()
                Button("Eliminar", systemImage: "trash", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis.vertical")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
    }
}
