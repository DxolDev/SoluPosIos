import Foundation

/// Guarda el token de consulta de cada tienda. Nunca va en SwiftData ni en texto plano.
protocol TokenStore {
    func get(storeId: String) -> String?
    func set(storeId: String, token: String?)
}

/// Token en el Keychain, solo en este equipo y sin respaldo/sincronización.
struct KeychainTokenStore: TokenStore {
    static let shared = KeychainTokenStore()
    private let service: String

    init(service: String = "com.solupos.contenedor.token") { self.service = service }

    func get(storeId: String) -> String? {
        guard let data = Keychain.get(service: service, account: storeId),
              let s = String(data: data, encoding: .utf8), !s.isEmpty else { return nil }
        return s
    }

    func set(storeId: String, token: String?) {
        let clean = token?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if clean.isEmpty {
            Keychain.remove(service: service, account: storeId)
        } else {
            Keychain.set(Data(clean.utf8), service: service, account: storeId)
        }
    }
}
