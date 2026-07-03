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
    private var title: String { isEditing ? "Editar Tienda" : "Nueva Tienda" }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color(red: 0.95, green: 0.95, blue: 0.97).ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Título sección
                        VStack(alignment: .leading, spacing: 4) {
                            Text(isEditing ? "Editar tienda" : "Agregar una nueva tienda")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(.primary)
                            Text("Ingresa la información de tu tienda para acceder a tu sistema.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 8)

                        // Campo nombre
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Nombre de la tienda")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.brandBlue)

                            HStack(spacing: 12) {
                                Image(systemName: "storefront")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 22)
                                TextField("Ej. Tienda Principal", text: $name)
                                    .autocorrectionDisabled()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 14)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color(.systemGray4), lineWidth: 1)
                            )
                        }

                        // Campo URL
                        VStack(alignment: .leading, spacing: 8) {
                            Text("URL de la tienda")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.brandBlue)

                            HStack(spacing: 12) {
                                Image(systemName: "link")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 22)
                                TextField("Ej. https://mi-tienda.com", text: $url)
                                    .keyboardType(.URL)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 14)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color(.systemGray4), lineWidth: 1)
                            )

                            Text("Asegúrate de incluir **https://**")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if showValidationError {
                            Text("Completa todos los campos.")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 100)
                }

                // Botón anclado al fondo
                Button(action: save) {
                    Label("Guardar Tienda", systemImage: "sdcard")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.brandBlue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.heroTop, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .foregroundStyle(.white)
                    }
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
        let trimmedUrl  = url.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty, !trimmedUrl.isEmpty else {
            showValidationError = true
            return
        }
        let finalUrl = normalizeUrl(trimmedUrl)
        if let s = store {
            s.name = trimmedName
            s.url  = finalUrl
        } else {
            context.insert(Store(name: trimmedName, url: finalUrl))
        }
        try? context.save()
        dismiss()
    }

    private func normalizeUrl(_ raw: String) -> String {
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") { return raw }
        return "https://\(raw)"
    }
}
