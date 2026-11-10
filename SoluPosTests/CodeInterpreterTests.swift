import XCTest
@testable import SoluPos

final class CodeInterpreterTests: XCTestCase {
    func testEtiquetaGeneradaSeConvierteEnId() {
        XCTAssertEqual(CodeInterpreter.interpret("0000000187"), .byId(187))
    }
    func testEtiquetaGeneradaConEspaciosSeLimpia() {
        XCTAssertEqual(CodeInterpreter.interpret(" 0000000184\n"), .byId(184))
    }
    func testDiezCerosNoEsUnId() {
        XCTAssertEqual(CodeInterpreter.interpret("0000000000"), .unrecognized)
    }
    func testUpcASeProbaTambienComoEan13() {
        XCTAssertEqual(CodeInterpreter.interpret("011418218703"), .byNumber(["011418218703", "0011418218703"]))
    }
    func testEan13ConCeroInicialSeProbaSinElCero() {
        XCTAssertEqual(CodeInterpreter.interpret("0011418218703"), .byNumber(["0011418218703", "011418218703"]))
    }
    func testEan13NormalSeBuscaTalCual() {
        XCTAssertEqual(CodeInterpreter.interpret("7501055300631"), .byNumber(["7501055300631"]))
    }
    func testCodigoInternoCorto() {
        XCTAssertEqual(CodeInterpreter.interpret("806"), .byNumber(["806"]))
    }
    func testDiezDigitosSinCeroInicialEsNumero() {
        XCTAssertEqual(CodeInterpreter.interpret("1234567890"), .byNumber(["1234567890"]))
    }
    func testUrlYTextoNoSeReconocen() {
        XCTAssertEqual(CodeInterpreter.interpret("https://solupos.com/x"), .unrecognized)
        XCTAssertEqual(CodeInterpreter.interpret("ABC123"), .unrecognized)
        XCTAssertEqual(CodeInterpreter.interpret(""), .unrecognized)
        XCTAssertEqual(CodeInterpreter.interpret(nil), .unrecognized)
    }
    func testDemasiadoLargoNoSeReconoce() {
        XCTAssertEqual(CodeInterpreter.interpret("123456789012345"), .unrecognized)
    }
}
