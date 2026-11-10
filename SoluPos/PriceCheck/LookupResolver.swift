import Foundation

/// Decide qué artículo corresponde a un código entre los resultados que devolvió
/// la búsqueda. `search` también coincide con nombres, por eso se exige igualdad
/// exacta. Ante la duda se prefiere no mostrar precio a mostrar uno equivocado.
enum LookupResolver {
    static func resolve(_ query: CodeQuery, candidates: [PriceInfo]) -> LookupResult {
        let matches: [PriceInfo]
        switch query {
        case .byId(let id):
            matches = candidates.filter { $0.itemId == id }
        case .byNumber(let variants):
            matches = candidates.filter { c in c.itemNumber.map(variants.contains) ?? false }
        case .unrecognized:
            return .unrecognized
        }
        var seen = Set<Int64>()
        let distinct = matches.filter { seen.insert($0.itemId).inserted }
        switch distinct.count {
        case 0: return .notFound
        case 1: return .found(distinct[0])
        default: return .ambiguous
        }
    }
}
