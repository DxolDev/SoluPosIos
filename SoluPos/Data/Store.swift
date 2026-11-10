import Foundation
import SwiftData

@Model
final class Store {
    var id: String
    var name: String
    var url: String
    var createdAt: Date
    /// Al abrir la app entra directo al consultador de esta tienda (equipo fijo en piso).
    /// Con valor por defecto para que la migración ligera conserve las tiendas existentes.
    var kioskMode: Bool = false
    var kioskFrontCamera: Bool = false

    init(name: String, url: String) {
        self.id = UUID().uuidString
        self.name = name
        self.url = url
        self.createdAt = Date()
    }
}
