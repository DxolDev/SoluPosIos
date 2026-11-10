import SwiftUI
import SwiftData

struct StoreFormView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var store: Store?

    @State private var name = ""
    @State private var url = ""
    @State private var showValidationError = false
    // Consultador de precios
    @State private var hasToken = false
    @State private var token = ""
    @State private var kioskMode = false
    @State private var kioskFrontCamera = false
    @State private var deviceHasPin = false
    @State private var pin = ""
    @State private var pinError = false

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

                        if Features.priceCheckEnabled { priceCheckSection }

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
                    hasToken = KeychainTokenStore.shared.get(storeId: s.id) != nil
                    if Features.priceCheckEnabled {
                        kioskMode = s.kioskMode
                        kioskFrontCamera = s.kioskFrontCamera
                    }
                }
                deviceHasPin = KioskPinStore.shared.hasPin()
            }
        }
    }

    // MARK: - Consultador de precios

    private var priceCheckSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Consultador de precios")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.brandBlue)

            VStack(alignment: .leading, spacing: 8) {
                Text("Token de consulta").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.brandBlue)
                HStack(spacing: 12) {
                    Image(systemName: "key").foregroundStyle(.secondary).frame(width: 22)
                    SecureField(hasToken ? "Guardado. Deja vacío para conservarlo" : "Lo entrega el administrador",
                                text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .fieldStyle()
                Text("Se guarda cifrado en este equipo.").font(.caption).foregroundStyle(.secondary)
            }

            Toggle(isOn: $kioskMode.animation()) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Modo quiosco")
                    Text("Al abrir la app entra directo al consultador de esta tienda.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .onChange(of: kioskMode) { _, _ in pinError = false }

            if kioskMode {
                Toggle("Usar cámara frontal", isOn: $kioskFrontCamera)

                VStack(alignment: .leading, spacing: 8) {
                    Text("PIN para salir del quiosco").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.brandBlue)
                    HStack(spacing: 12) {
                        Image(systemName: "lock").foregroundStyle(.secondary).frame(width: 22)
                        SecureField("PIN", text: $pin).keyboardType(.numberPad)
                            .onChange(of: pin) { _, v in
                                let f = String(v.filter { $0.isASCII && $0.isNumber }.prefix(PinCrypto.maxLength))
                                if f != v { pin = f }
                                pinError = false
                            }
                    }
                    .fieldStyle(error: pinError)
                    Text(pinError ? "El PIN debe tener de 4 a 8 dígitos"
                         : deviceHasPin ? "Ya hay un PIN en este equipo. Déjalo vacío para conservarlo."
                         : "De 4 a 8 dígitos")
                        .font(.caption)
                        .foregroundStyle(pinError ? Color.red : Color.secondary)
                }
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedUrl  = url.trimmingCharacters(in: .whitespaces)
        // Con el quiosco activo hace falta un PIN: el existente del equipo o uno nuevo válido.
        let pinNeeded = kioskMode && (!deviceHasPin || !pin.isEmpty)
        let invalidPin = pinNeeded && !PinCrypto.isValidFormat(pin)
        guard !trimmedName.isEmpty, !trimmedUrl.isEmpty, !invalidPin else {
            showValidationError = trimmedName.isEmpty || trimmedUrl.isEmpty
            pinError = invalidPin
            return
        }
        let finalUrl = normalizeUrl(trimmedUrl)
        let saved: Store
        if let s = store {
            s.name = trimmedName
            s.url  = finalUrl
            saved = s
        } else {
            saved = Store(name: trimmedName, url: finalUrl)
            context.insert(saved)
        }
        // Con el consultador oculto no se tocan los campos del quiosco.
        if Features.priceCheckEnabled {
            saved.kioskMode = kioskMode
            saved.kioskFrontCamera = kioskFrontCamera
        }
        try? context.save()
        // Un equipo solo puede ser quiosco de una tienda.
        if kioskMode { try? StoreRepository(context: context).clearKioskExcept(id: saved.id) }
        if !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            KeychainTokenStore.shared.set(storeId: saved.id, token: token)
        }
        if kioskMode && !pin.isEmpty { KioskPinStore.shared.setPin(pin) }
        dismiss()
    }

    private func normalizeUrl(_ raw: String) -> String {
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") { return raw }
        return "https://\(raw)"
    }
}

private extension View {
    func fieldStyle(error: Bool = false) -> some View {
        self.padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(error ? Color.red : Color(.systemGray4), lineWidth: 1))
    }
}
