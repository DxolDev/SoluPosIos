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
    @State private var showPriceTip = false
    @State private var priceCheckStore: Store?
    @State private var tokenVersion = 0
    @State private var didAutoOpenKiosk = false
    @State private var frames: [String: CGRect] = [:]

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
                    .tutorialTarget("add")
            }
            .padding(.trailing, 20)
            .padding(.bottom, 28)

            if !tutorialSteps.isEmpty {
                TutorialOverlay(steps: tutorialSteps, onFinish: dismissTutorial)
            }
        }
        .onPreferenceChange(TutorialFrames.self) { frames = $0 }
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showAddForm, onDismiss: { tokenVersion += 1 }) {
            StoreFormView()
        }
        .sheet(item: $editingStore, onDismiss: { tokenVersion += 1 }) { store in
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
                    KeychainTokenStore.shared.set(storeId: s.id, token: nil)
                    context.delete(s)
                    try? context.save()
                    deletingStore = nil
                }
            }
        }
        .navigationDestination(item: $navigateToWebView) { store in
            WebViewScreen(store: store)
        }
        .navigationDestination(item: $priceCheckStore) { store in
            PriceCheckView(store: store)
        }
        .onAppear {
            if !prefs.tutorialSeen { showTutorial = true }
            if Features.priceCheckEnabled && !prefs.priceTipListSeen { showPriceTip = true }
        }
        .task {
            // Equipo configurado como quiosco: al abrir la app va directo al consultador.
            guard Features.priceCheckEnabled, !didAutoOpenKiosk else { return }
            didAutoOpenKiosk = true
            if let kiosk = try? StoreRepository(context: context).kioskStore() {
                priceCheckStore = kiosk
            }
        }
    }

    // MARK: - Tutorial

    private var tutorialSteps: [TutorialStep] {
        var steps: [TutorialStep] = []
        if showTutorial, let printer = frames["printer"], let add = frames["add"] {
            steps.append(TutorialStep(
                title: "Configura tu impresora",
                message: "Aquí puedes vincular tu impresora térmica Bluetooth para imprimir tickets de venta.",
                highlightFrame: printer))
            steps.append(TutorialStep(
                title: "Agrega tu primera tienda",
                message: "Toca este botón para conectar tu punto de venta y empezar a vender.",
                highlightFrame: add))
        }
        // Novedad: se muestra una vez, incluso a quien ya vio el tutorial original.
        if Features.priceCheckEnabled, showPriceTip, let price = frames["price"], !stores.isEmpty {
            steps.append(TutorialStep(
                title: "Nuevo: consultador de precios",
                message: "Escanea un producto con la cámara y mira su precio al instante. "
                    + "En Editar tienda puedes activar el modo quiosco para dejar un equipo fijo en el pasillo.",
                highlightFrame: price))
        }
        return steps
    }

    private func dismissTutorial() {
        showTutorial = false
        showPriceTip = false
        prefs.tutorialSeen = true
        // Si el consultador está oculto el aviso no se consume: aparecerá cuando se active.
        if Features.priceCheckEnabled { prefs.priceTipListSeen = true }
    }

    /// "Ayuda": reactiva el tutorial, el aviso y los del POS.
    private func replayTutorial() {
        showTutorial = true
        showPriceTip = Features.priceCheckEnabled
        prefs.priceTipListSeen = false
        prefs.webViewTutorialSeen = false
        prefs.priceTipPosSeen = false
    }

    // MARK: - Barra superior custom (azul continuo con el hero)

    private var topBar: some View {
        HStack(spacing: 12) {
            Text("Mis Tiendas")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)

            Spacer()

            Button {
                replayTutorial()
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
                    .tutorialTarget("printer")
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
                let _ = tokenVersion   // refresca el estado del token tras editar
                ForEach(Array(stores.enumerated()), id: \.element.id) { index, store in
                    StoreCard(
                        store: store,
                        priceCheckEnabled: priceCheckEnabled(store),
                        isFirst: index == 0,
                        onPriceCheck: { priceCheckStore = store },
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

    private func priceCheckEnabled(_ store: Store) -> Bool {
        // En desarrollo se habilita siempre para ver el catálogo de demostración.
        #if DEBUG
        return true
        #else
        return KeychainTokenStore.shared.get(storeId: store.id) != nil
        #endif
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
    let priceCheckEnabled: Bool
    let isFirst: Bool
    let onPriceCheck: () -> Void
    let onOpen: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
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
            if Features.priceCheckEnabled {
            Button(action: onPriceCheck) {
                Label(priceCheckEnabled ? "Consultador de precios" : "Consultador: sin token", systemImage: "tag.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(priceCheckEnabled ? Color.brandBlue : Color.secondary.opacity(0.6))
                    .padding(.vertical, 6)
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
                    .modifier(TutorialTargetIf(id: "price", enabled: isFirst))
            }
            .buttonStyle(.plain)
            .disabled(!priceCheckEnabled)
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

private struct TutorialTargetIf: ViewModifier {
    let id: String
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled { content.tutorialTarget(id) } else { content }
    }
}
