import XCTest
@testable import SoluPos

final class PinCryptoTests: XCTestCase {
    func testFormatoDelPin() {
        XCTAssertTrue(PinCrypto.isValidFormat("1234"))
        XCTAssertTrue(PinCrypto.isValidFormat("12345678"))
        XCTAssertFalse(PinCrypto.isValidFormat("123"))
        XCTAssertFalse(PinCrypto.isValidFormat("123456789"))
        XCTAssertFalse(PinCrypto.isValidFormat("12a4"))
        XCTAssertFalse(PinCrypto.isValidFormat(""))
    }

    func testElHashCoincideSoloConElMismoPinYSal() {
        let salt = PinCrypto.newSalt()
        XCTAssertEqual(salt.count, 16)
        let h = PinCrypto.hash("4821", salt: salt, iterations: 1000)
        XCTAssertEqual(h.count, 32)
        XCTAssertTrue(PinCrypto.matches(h, PinCrypto.hash("4821", salt: salt, iterations: 1000)))
        XCTAssertFalse(PinCrypto.matches(h, PinCrypto.hash("4822", salt: salt, iterations: 1000)))
        XCTAssertFalse(PinCrypto.matches(h, PinCrypto.hash("4821", salt: PinCrypto.newSalt(), iterations: 1000)))
    }

    func testPbkdf2VectorConocido() {
        // RFC 7914 (PBKDF2-HMAC-SHA256, "passwd"/"salt", 1 iteración, 32 bytes primeros).
        let h = PinCrypto.hash("passwd", salt: Array("salt".utf8), iterations: 1)
        let hex = h.map { String(format: "%02x", $0) }.joined()
        XCTAssertTrue(hex.hasPrefix("55ac046e56e3089fec1691c22544b605"), hex)
    }

    func testLasSalesSonDistintas() {
        XCTAssertNotEqual(PinCrypto.newSalt(), PinCrypto.newSalt())
    }

    func testBloqueoProgresivo() {
        XCTAssertEqual(PinCrypto.lockSeconds(failures: 0), 0)
        XCTAssertEqual(PinCrypto.lockSeconds(failures: 4), 0)
        XCTAssertEqual(PinCrypto.lockSeconds(failures: 5), 30)
        XCTAssertEqual(PinCrypto.lockSeconds(failures: 6), 60)
        XCTAssertEqual(PinCrypto.lockSeconds(failures: 7), 120)
        XCTAssertEqual(PinCrypto.lockSeconds(failures: 10), 900)
        XCTAssertEqual(PinCrypto.lockSeconds(failures: 500), 900)
    }

    func testKioskPinStoreConBloqueo() {
        var now: Int64 = 1_000_000
        let store = KioskPinStore(service: "com.solupos.contenedor.tests.pin.\(UUID().uuidString)",
                                  iterations: 1000, now: { now })
        defer { store.clear() }
        XCTAssertFalse(store.hasPin())
        store.setPin("4821")
        XCTAssertTrue(store.hasPin())
        XCTAssertEqual(store.verify("0000"), .wrong(attemptsBeforeLock: 4))
        XCTAssertEqual(store.verify("0000"), .wrong(attemptsBeforeLock: 3))
        XCTAssertEqual(store.verify("0000"), .wrong(attemptsBeforeLock: 2))
        XCTAssertEqual(store.verify("0000"), .wrong(attemptsBeforeLock: 1))
        XCTAssertEqual(store.verify("0000"), .locked(seconds: 30))
        // Bloqueado: ni el PIN correcto entra.
        XCTAssertEqual(store.verify("4821"), .locked(seconds: 30))
        now += 31_000
        XCTAssertEqual(store.verify("4821"), .ok)
        XCTAssertEqual(store.verify("0000"), .wrong(attemptsBeforeLock: 4))
    }

    func testTokenStoreEnKeychain() {
        let ts = KeychainTokenStore(service: "com.solupos.contenedor.tests.token.\(UUID().uuidString)")
        XCTAssertNil(ts.get(storeId: "a"))
        ts.set(storeId: "a", token: "  abc123 ")
        XCTAssertEqual(ts.get(storeId: "a"), "abc123")
        ts.set(storeId: "a", token: nil)
        XCTAssertNil(ts.get(storeId: "a"))
    }
}
