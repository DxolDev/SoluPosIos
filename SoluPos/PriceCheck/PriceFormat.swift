import Foundation

private let quetzalFormatter: NumberFormatter = {
    let f = NumberFormatter()
    f.locale = Locale(identifier: "en_US")
    f.numberStyle = .decimal
    f.usesGroupingSeparator = true
    f.minimumFractionDigits = 2
    f.maximumFractionDigits = 2
    f.roundingMode = .halfUp
    return f
}()

/// `Q1,234.50` (separadores en_US, 2 decimales, redondeo half-up).
func formatQuetzales(_ value: Decimal) -> String {
    "Q" + (quetzalFormatter.string(from: value as NSDecimalNumber) ?? "0.00")
}

struct LookupMessage: Equatable {
    let title: String
    let detail: String?
}

extension LookupResult {
    /// Texto para los resultados que no son un precio. En el quiosco el cliente no
    /// ve jerga técnica ni el código; el detalle técnico queda para el cajero.
    func message(kiosk: Bool) -> LookupMessage? {
        switch self {
        case .found:
            return nil
        case .notFound:
            return kiosk
                ? LookupMessage(title: "No encontramos este producto", detail: "Pida ayuda a un vendedor")
                : LookupMessage(title: "Producto no encontrado",
                                detail: "Este código no está registrado en la tienda. Si el producto existe, falta asignarle el código en SoluPos.")
        case .ambiguous:
            return kiosk
                ? LookupMessage(title: "No encontramos este producto", detail: "Pida ayuda a un vendedor")
                : LookupMessage(title: "Código duplicado",
                                detail: "Este código coincide con más de un artículo, por eso no se muestra precio. Corríjalo en SoluPos.")
        case .unrecognized:
            return kiosk
                ? LookupMessage(title: "No pudimos leer el código", detail: "Intente de nuevo")
                : LookupMessage(title: "Código no reconocido", detail: "No tiene el formato de un código de producto.")
        case .notConfigured:
            return kiosk
                ? LookupMessage(title: "Consultador no disponible", detail: nil)
                : LookupMessage(title: "Consultador sin configurar",
                                detail: "Esta tienda no tiene token de consulta. Edita la tienda para agregarlo.")
        case .unauthorized:
            return kiosk
                ? LookupMessage(title: "Consultador no disponible", detail: nil)
                : LookupMessage(title: "Sin permiso",
                                detail: "El token de esta tienda no tiene permiso. Pide uno nuevo al administrador.")
        case .offline:
            return LookupMessage(title: "Sin conexión", detail: "Intente de nuevo en unos segundos")
        case .failure:
            return LookupMessage(title: "No se pudo consultar", detail: "Intente de nuevo")
        }
    }
}
