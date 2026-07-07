import SwiftUI
import SwiftData

// MARK: - Brand colors (colores exactos del Android — Color.kt)
extension Color {
    static let heroTop     = Color(red: 0.016, green: 0.106, blue: 0.302) // #041B4D HeroGradientTop
    static let heroBottom  = Color(red: 0.043, green: 0.180, blue: 0.510) // #0B2E82 HeroGradientBottom
    static let storeIcon   = Color(red: 0.008, green: 0.129, blue: 0.639) // #0221A3 StoreIconBlue
    static let brandBlue   = Color(red: 0.084, green: 0.271, blue: 0.753) // #1565C0 Blue800
    static let blue100     = Color(red: 0.733, green: 0.871, blue: 0.984) // #BBDEFB Blue100 (FAB)
    static let brandDark   = Color(red: 0.016, green: 0.106, blue: 0.302) // #041B4D = heroTop
    static let listBg      = Color(red: 0.96, green: 0.96, blue: 0.98)
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
                // Barra superior azul + hero forman un bloque continuo
                VStack(spacing: 0) {
                    topBar
                    heroHeader
                }

                if stores.isEmpty {
                    emptyState
                } else {
                    storeList
                }
            }

            // FAB azul claro (Material3 primaryContainer) con "+" azul oscuro
            Button {
                showAddForm = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(Color.brandBlue)
                    .frame(width: 60, height: 60)
                    .background(Color.blue100)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .shadow(color: .black.opacity(0.22), radius: 6, x: 0, y: 3)
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
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
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

    // MARK: - Barra superior custom (azul continuo con el hero)

    private var topBar: some View {
        HStack(spacing: 12) {
            Text("Mis Tiendas")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)

            Spacer()

            Button {
                showTutorial = true
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 22))
                    .foregroundStyle(.white)
            }

            NavigationLink {
                PrinterSettingsView()
            } label: {
                Image(systemName: "printer")
                    .font(.system(size: 22))
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background(Color.heroTop.ignoresSafeArea(edges: .top))
    }

    // MARK: - Hero header (compacto, logo grande)

    private var heroHeader: some View {
        VStack(spacing: 10) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 36)
            Text("La solución completa para tu punto de venta")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 12)
        .padding(.bottom, 26)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [Color.heroTop, Color.heroBottom],
                startPoint: .top,
                endPoint: .bottom
            )
        )
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
            Text("No hay tiendas guardadas.")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Toca + para agregar una.")
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
            // Avatar círculo azul (#0221A3 del Android)
            ZStack {
                Circle()
                    .fill(Color.storeIcon)
                    .frame(width: 52, height: 52)
                Image(systemName: "storefront.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(store.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(store.url)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.brandBlue)
                    .lineLimit(1)
            }

            Spacer()

            Menu {
                Button("Abrir", systemImage: "globe", action: onOpen)
                Button("Editar", systemImage: "pencil", action: onEdit)
                Divider()
                Button("Eliminar", systemImage: "trash", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16))
                    .rotationEffect(.degrees(90)) // tres puntos verticales, como el MoreVert de Android
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(red: 0.93, green: 0.93, blue: 0.95))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
    }
}
