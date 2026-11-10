import XCTest
@testable import SoluPos

final class PriceLogicTests: XCTestCase {
    private let today = LocalDate(year: 2026, month: 11, day: 6)

    private func dec(_ s: String) -> Decimal { Decimal(string: s)! }

    private func item(id: Int64 = 1, number: String? = "806", price: String = "20.00",
                      promo: String? = nil, start: LocalDate? = nil, end: LocalDate? = nil,
                      qty: String? = "5") -> PriceInfo {
        PriceInfo(itemId: id, itemNumber: number, name: "  Abrazadera\tcon   llave ",
                  regularPrice: dec(price), promoPrice: promo.map(dec),
                  promoStart: start, promoEnd: end, quantity: qty.map(dec))
    }

    func testNombreSeLimpia() { XCTAssertEqual(item().displayName, "Abrazadera con llave") }

    func testOfertaVigenteSeUsa() {
        XCTAssertEqual(item(promo: "15.00", end: today.plusDays(3)).finalPrice(today: today), dec("15.00"))
    }
    func testOfertaVencidaSeIgnora() {
        XCTAssertEqual(item(promo: "15.00", end: today.minusDays(1)).finalPrice(today: today), dec("20.00"))
    }
    func testOfertaQueAunNoEmpiezaSeIgnora() {
        XCTAssertNil(item(promo: "15.00", start: today.plusDays(1)).activePromo(today: today))
    }
    func testOfertaSinFechasSeConsideraVigente() {
        XCTAssertEqual(item(promo: "15.00").activePromo(today: today), dec("15.00"))
    }
    func testOfertaMayorOIgualAlPrecioSeIgnora() {
        XCTAssertNil(item(promo: "20.00").activePromo(today: today))
        XCTAssertNil(item(promo: "0.00").activePromo(today: today))
    }
    func testExistencia() {
        XCTAssertEqual(item(qty: "490").available, true)
        XCTAssertEqual(item(qty: "0").available, false)
        XCTAssertEqual(item(qty: "-1").available, false)
        XCTAssertNil(item(qty: nil).available)
    }

    // --- Fechas / zona horaria ---
    func testFechaDeGuatemalaNoDependeDeUTC() {
        // 2026-11-07 03:00 UTC = 2026-11-06 21:00 en Guatemala (UTC-6).
        let d = Date(timeIntervalSince1970: 1_794_020_400)
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(cal.component(.day, from: d), 7)
        XCTAssertEqual(LocalDate.today(now: d), LocalDate(year: 2026, month: 11, day: 6))
    }
    func testPlusDaysCruzaMes() {
        XCTAssertEqual(LocalDate(year: 2026, month: 11, day: 30).plusDays(1), LocalDate(year: 2026, month: 12, day: 1))
    }

    // --- Resolución de coincidencias ---
    func testPorNumeroExacto() {
        let r = LookupResolver.resolve(.byNumber(["806"]),
                                       candidates: [item(id: 1, number: "806"), item(id: 2, number: "8061")])
        guard case .found(let info) = r else { return XCTFail("\(r)") }
        XCTAssertEqual(info.itemId, 1)
    }
    func testSearchTrajoSoloCoincidenciasParciales() {
        XCTAssertEqual(LookupResolver.resolve(.byNumber(["806"]), candidates: [item(id: 9, number: "8061")]), .notFound)
    }
    func testUpcPorVariante() {
        let r = LookupResolver.resolve(.byNumber(["011418218703", "0011418218703"]),
                                       candidates: [item(id: 184, number: "011418218703")])
        guard case .found(let info) = r else { return XCTFail("\(r)") }
        XCTAssertEqual(info.itemId, 184)
    }
    func testPorIdExacto() {
        let r = LookupResolver.resolve(.byId(187), candidates: [item(id: 187, number: nil)])
        guard case .found(let info) = r else { return XCTFail("\(r)") }
        XCTAssertEqual(info.itemId, 187)
    }
    func testIdQueNoCoincideEsNoEncontrado() {
        XCTAssertEqual(LookupResolver.resolve(.byId(187), candidates: [item(id: 188)]), .notFound)
    }
    func testDosArticulosDistintosEsAmbiguo() {
        XCTAssertEqual(
            LookupResolver.resolve(.byNumber(["806", "0806"]),
                                   candidates: [item(id: 1, number: "806"), item(id: 2, number: "0806")]),
            .ambiguous)
    }
    func testElMismoArticuloRepetidoNoEsAmbiguo() {
        let r = LookupResolver.resolve(.byNumber(["806"]), candidates: [item(id: 1), item(id: 1)])
        XCTAssertNotEqual(r, .ambiguous)
    }
    func testSinListaEsNoEncontrado() {
        XCTAssertEqual(LookupResolver.resolve(.byId(1), candidates: []), .notFound)
    }
    func testCodigoNoReconocido() {
        XCTAssertEqual(LookupResolver.resolve(.unrecognized, candidates: []), .unrecognized)
    }

    func testProveedorNoConfiguradoDevuelveNotConfigured() async {
        let r = await NotConfiguredPriceLookupService().lookup(storeId: "x", query: .byNumber(["1"]))
        XCTAssertEqual(r, .notConfigured)
    }

    #if DEBUG
    func testDemoResuelveCasosDocumentados() async {
        let demo = DemoPriceLookupService()
        let oferta = await demo.lookup(storeId: "x", query: CodeInterpreter.interpret("806"))
        guard case .found(let a) = oferta else { return XCTFail("\(oferta)") }
        XCTAssertNotNil(a.activePromo(today: LocalDate.today()))
        let agotado = await demo.lookup(storeId: "x", query: CodeInterpreter.interpret("011418218703"))
        guard case .found(let b) = agotado else { return XCTFail("\(agotado)") }
        XCTAssertEqual(b.available, false)
        let dup = await demo.lookup(storeId: "x", query: CodeInterpreter.interpret("011418218700"))
        XCTAssertEqual(dup, .ambiguous)
        let nada = await demo.lookup(storeId: "x", query: CodeInterpreter.interpret("999"))
        XCTAssertEqual(nada, .notFound)
    }
    #endif
}
