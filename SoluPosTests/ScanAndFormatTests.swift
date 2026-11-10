import XCTest
@testable import SoluPos

final class ScanAndFormatTests: XCTestCase {
    private var now: Int64 = 0
    private func stabilizer() -> ScanStabilizer { ScanStabilizer(clock: { [unowned self] in self.now }) }

    func testUnaSolaLecturaNoBasta() { XCTAssertNil(stabilizer().offer("806")) }

    func testDosLecturasIgualesConfirman() {
        let s = stabilizer()
        XCTAssertNil(s.offer("806"))
        now += 100
        XCTAssertEqual(s.offer("806"), "806")
    }

    func testLecturasDistintasNoSeSuman() {
        let s = stabilizer()
        _ = s.offer("806"); now += 100
        XCTAssertNil(s.offer("807")); now += 100
        XCTAssertNil(s.offer("806"))
    }

    func testLecturaVencidaNoCuenta() {
        let s = stabilizer()
        _ = s.offer("806"); now += 5_000
        XCTAssertNil(s.offer("806"))
    }

    func testElMismoCodigoEnfriaTresSegundos() {
        let s = stabilizer()
        _ = s.offer("806"); now += 100; _ = s.offer("806")
        now += 200
        XCTAssertNil(s.offer("806")); now += 100
        XCTAssertNil(s.offer("806"))
        now += 4_000
        _ = s.offer("806"); now += 100
        XCTAssertNotNil(s.offer("806"))
    }

    func testOtroCodigoNoEsperaElEnfriamiento() {
        let s = stabilizer()
        _ = s.offer("806"); now += 100; _ = s.offer("806"); now += 100
        _ = s.offer("659"); now += 100
        XCTAssertEqual(s.offer("659"), "659")
    }

    func testNulosYVaciosSeIgnoran() {
        let s = stabilizer()
        XCTAssertNil(s.offer(nil)); XCTAssertNil(s.offer(""))
    }

    func testFormatoQuetzales() {
        XCTAssertEqual(formatQuetzales(Decimal(string: "20")!), "Q20.00")
        XCTAssertEqual(formatQuetzales(Decimal(string: "187.5")!), "Q187.50")
        XCTAssertEqual(formatQuetzales(Decimal(string: "1234.5")!), "Q1,234.50")
        XCTAssertEqual(formatQuetzales(Decimal(string: "0.987")!), "Q0.99")
        XCTAssertEqual(formatQuetzales(Decimal(string: "0.985")!), "Q0.99")
    }

    func testQuioscoNoMuestraJergaNiCodigo() {
        let casos: [LookupResult] = [.notFound, .ambiguous, .notConfigured, .unauthorized]
        for r in casos {
            let m = r.message(kiosk: true)!
            let text = (m.title + " " + (m.detail ?? "")).lowercased()
            for bad in ["token", "solupos", "código", "api", "item"] {
                XCTAssertFalse(text.contains(bad), "\(r) muestra '\(bad)'")
            }
        }
    }

    func testMensajesDeCajeroSonTecnicosYDistintos() {
        XCTAssertEqual(LookupResult.notFound.message(kiosk: false)?.title, "Producto no encontrado")
        XCTAssertEqual(LookupResult.ambiguous.message(kiosk: false)?.title, "Código duplicado")
        XCTAssertEqual(LookupResult.unrecognized.message(kiosk: false)?.title, "Código no reconocido")
        XCTAssertEqual(LookupResult.notConfigured.message(kiosk: false)?.title, "Consultador sin configurar")
        XCTAssertEqual(LookupResult.unauthorized.message(kiosk: false)?.title, "Sin permiso")
        XCTAssertEqual(LookupResult.notFound.message(kiosk: true)?.title, "No encontramos este producto")
        XCTAssertEqual(LookupResult.offline.message(kiosk: true)?.title, "Sin conexión")
        XCTAssertEqual(LookupResult.failure("x").message(kiosk: true)?.title, "No se pudo consultar")
    }

    func testEncontradoNoTieneMensaje() {
        let info = PriceInfo(itemId: 1, itemNumber: nil, name: "x", regularPrice: 1)
        XCTAssertNil(LookupResult.found(info).message(kiosk: false))
    }
}
