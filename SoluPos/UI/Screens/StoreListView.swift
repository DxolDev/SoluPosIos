import SwiftUI
import SwiftData

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
        ZStack {
            mainContent
            if showTutorial {
                StoreListTutorialOverlay(onDismiss: {
                    prefs.tutorialSeen = true
                    showTutorial = false
                })
            }
        }
        .navigationTitle("SoluPos")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showTutorial = true
                } label: {
                    Image(systemName: "questionmark.circle")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    PrinterSettingsView()
                } label: {
                    Image(systemName: "printer")
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

    @ViewBuilder
    private var mainContent: some View {
        VStack(spacing: 0) {
            heroHeader
            if stores.isEmpty {
                emptyState
            } else {
                storeList
            }
        }
        .safeAreaInset(edge: .bottom) {
            addButton
        }
    }

    private var heroHeader: some View {
        VStack(spacing: 8) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(height: 52)
            Text("La solución completa para tu punto de venta")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal)
        .background(Color.black)
    }

    private var storeList: some View {
        List {
            ForEach(stores) { store in
                StoreCard(
                    store: store,
                    onOpen: { navigateToWebView = store },
                    onEdit: { editingStore = store },
                    onDelete: { deletingStore = store }
                )
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }
        }
        .listStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "storefront")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("No hay tiendas configuradas")
                .font(.headline)
            Text("Toca + para agregar tu primera tienda.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
    }

    private var addButton: some View {
        Button {
            showAddForm = true
        } label: {
            Label("Nueva tienda", systemImage: "plus")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .padding()
        .background(.regularMaterial)
    }
}

private struct StoreCard: View {
    let store: Store
    let onOpen: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(store.name)
                    .font(.headline)
                Text(store.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Menu {
                Button("Abrir", action: onOpen)
                Button("Editar", action: onEdit)
                Button("Eliminar", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
    }
}
