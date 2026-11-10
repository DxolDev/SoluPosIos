import Foundation

/// Cómo debe buscarse un código leído por la cámara o por un lector.
enum CodeQuery: Equatable {
    /// Código generado por SoluPos a partir del `item_id` (10 dígitos con ceros a la izquierda).
    case byId(Int64)
    /// Código guardado en `item_number`; se prueba cada variante, en orden.
    case byNumber([String])
    /// No tiene forma de código de producto (URL, texto, vacío).
    case unrecognized
}

enum CodeInterpreter {
    private static let generatedIdLength = 10
    private static let maxNumberLength = 14

    static func interpret(_ raw: String?) -> CodeQuery {
        let code = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty, code.unicodeScalars.allSatisfy({ $0.value >= 48 && $0.value <= 57 }) else {
            return .unrecognized
        }

        // Etiqueta generada por SoluPos: 0000000187 -> id 187.
        if code.count == generatedIdLength && code.hasPrefix("0") {
            let digits = String(code.drop(while: { $0 == "0" }))
            guard !digits.isEmpty, let id = Int64(digits) else { return .unrecognized }
            return .byId(id)
        }

        // La cámara puede devolver un UPC-A como EAN-13 con un 0 delante, y al revés.
        if code.count == 12 { return .byNumber([code, "0" + code]) }
        if code.count == 13 && code.hasPrefix("0") { return .byNumber([code, String(code.dropFirst())]) }
        if (1...maxNumberLength).contains(code.count) { return .byNumber([code]) }
        return .unrecognized
    }
}
