import SwiftUI
import SwiftData

struct StoreFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var store: Store?

    @State private var name = ""
    @State private var url = ""
    @State private var showValidationError = false

    private var isEditing: Bool { store != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Nombre de la tienda") {
                    TextField("Mi Tienda", text: $name)
                        .autocorrectionDisabled()
                }
                Section("URL del POS") {
                    TextField("http://192.168.1.100", text: $url)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .autocapitalization(.none)
                }
                if showValidationError {
                    Section {
                        Text("Completa todos los campos.")
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle(isEditing ? "Editar tienda" : "Nueva tienda")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar", action: save)
                }
            }
            .onAppear {
                if let s = store {
                    name = s.name
                    url = s.url
                }
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedUrl = url.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty, !trimmedUrl.isEmpty else {
            showValidationError = true
            return
        }
        if let s = store {
            s.name = trimmedName
            s.url = normalizeUrl(trimmedUrl)
        } else {
            let s = Store(name: trimmedName, url: normalizeUrl(trimmedUrl))
            context.insert(s)
        }
        try? context.save()
        dismiss()
    }

    private func normalizeUrl(_ raw: String) -> String {
        guard !raw.hasPrefix("http://"), !raw.hasPrefix("https://") else { return raw }
        return "http://\(raw)"
    }
}
