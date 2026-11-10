import Foundation

/// Las ofertas se evalúan en hora de Guatemala, sin importar la zona del equipo.
let guatemalaTimeZone = TimeZone(identifier: "America/Guatemala")!

/// Fecha sin hora (equivalente a java.time.LocalDate), calculada en hora de Guatemala.
struct LocalDate: Comparable, Hashable {
    let year: Int
    let month: Int
    let day: Int

    static var guatemalaCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = guatemalaTimeZone
        return cal
    }

    init(year: Int, month: Int, day: Int) {
        self.year = year; self.month = month; self.day = day
    }

    /// Hoy en hora de Guatemala. `now` es inyectable para pruebas.
    static func today(now: Date = Date()) -> LocalDate {
        let c = guatemalaCalendar.dateComponents([.year, .month, .day], from: now)
        return LocalDate(year: c.year!, month: c.month!, day: c.day!)
    }

    private var date: Date {
        Self.guatemalaCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    func plusDays(_ n: Int) -> LocalDate {
        let d = Self.guatemalaCalendar.date(byAdding: .day, value: n, to: date)!
        return LocalDate.today(now: d)
    }

    func minusDays(_ n: Int) -> LocalDate { plusDays(-n) }

    static func < (a: LocalDate, b: LocalDate) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }
}

/// Lo único que la app necesita saber de un producto; nada de costos ni proveedores.
struct PriceInfo: Equatable {
    let itemId: Int64
    let itemNumber: String?
    let name: String
    let regularPrice: Decimal
    var promoPrice: Decimal? = nil
    var promoStart: LocalDate? = nil
    var promoEnd: LocalDate? = nil
    /// Existencia total; nil si no se conoce.
    var quantity: Decimal? = nil

    /// Nombre sin tabulaciones ni espacios sobrantes (la API los trae a veces).
    var displayName: String {
        name.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// La oferta solo cuenta si hoy está dentro de su rango; sin fechas se considera vigente.
    func activePromo(today: LocalDate) -> Decimal? {
        guard let promo = promoPrice else { return nil }
        if promo <= 0 || promo >= regularPrice { return nil }
        if let start = promoStart, today < start { return nil }
        if let end = promoEnd, today > end { return nil }
        return promo
    }

    func finalPrice(today: LocalDate) -> Decimal { activePromo(today: today) ?? regularPrice }

    /// nil = no se sabe; cero o negativo (se ha visto -1) = agotado.
    var available: Bool? { quantity.map { $0 > 0 } }
}

enum LookupResult: Equatable {
    case found(PriceInfo)
    case notFound
    /// El código coincide con dos artículos distintos: no se muestra ningún precio.
    case ambiguous
    case unrecognized
    case notConfigured
    case unauthorized
    case offline
    case failure(String)
}

/// Punto de unión con el proxy. Las pantallas solo conocen este protocolo.
protocol PriceLookupService {
    func lookup(storeId: String, query: CodeQuery) async -> LookupResult
}

/// Sustituto hasta que exista el proxy: indica que la tienda no está lista.
struct NotConfiguredPriceLookupService: PriceLookupService {
    func lookup(storeId: String, query: CodeQuery) async -> LookupResult { .notConfigured }
}

/// En DEBUG devuelve el catálogo de demostración; en release, NotConfigured.
enum PriceLookupProvider {
    static func create() -> PriceLookupService {
        #if DEBUG
        return DemoPriceLookupService()
        #else
        return NotConfiguredPriceLookupService()
        #endif
    }
}
