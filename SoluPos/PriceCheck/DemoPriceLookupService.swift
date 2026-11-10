import Foundation

#if DEBUG
/// Catálogo de ejemplo que pasa por el mismo `LookupResolver` que usará el
/// cliente real. Códigos para probar: 806 (oferta), 0000000187 (id generado),
/// 011418218703 (UPC-A agotado), 011418218700 (duplicado: sus dos variantes
/// apuntan a artículos distintos), cualquier otro (no encontrado).
/// Solo existe en compilaciones DEBUG.
struct DemoPriceLookupService: PriceLookupService {
    private var catalog: [PriceInfo] {
        [
            PriceInfo(itemId: 1, itemNumber: "806", name: "Abrazadera con llave para bebedero campana",
                      regularPrice: 20, promoPrice: 15, promoStart: nil,
                      promoEnd: LocalDate.today().plusDays(9), quantity: 490),
            PriceInfo(itemId: 187, itemNumber: nil, name: "\tMaíz amarillo  quintal ",
                      regularPrice: Decimal(string: "187.50")!, quantity: 12),
            PriceInfo(itemId: 184, itemNumber: "011418218703", name: "Tabcin Gripe y Tos",
                      regularPrice: 10, quantity: -1),
            PriceInfo(itemId: 5, itemNumber: "011418218700", name: "Producto repetido A",
                      regularPrice: 5, quantity: 3),
            PriceInfo(itemId: 6, itemNumber: "0011418218700", name: "Producto repetido B",
                      regularPrice: 9, quantity: 3)
        ]
    }

    func lookup(storeId: String, query: CodeQuery) async -> LookupResult {
        try? await Task.sleep(nanoseconds: 400_000_000)
        return LookupResolver.resolve(query, candidates: catalog)
    }
}
#endif
