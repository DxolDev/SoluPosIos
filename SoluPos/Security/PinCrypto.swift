import Foundation
import CommonCrypto
import Security

/// Funciones puras del PIN del quiosco: hash con sal y tiempo de bloqueo.
enum PinCrypto {
    static let minLength = 4
    static let maxLength = 8
    static let iterations = 120_000
    private static let keyBytes = 32

    static func isValidFormat(_ pin: String) -> Bool {
        (minLength...maxLength).contains(pin.count)
            && pin.unicodeScalars.allSatisfy { $0.value >= 48 && $0.value <= 57 }
    }

    static func newSalt() -> [UInt8] {
        var salt = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, salt.count, &salt)
        return salt
    }

    /// PBKDF2-HMAC-SHA256, 256 bits.
    static func hash(_ pin: String, salt: [UInt8], iterations: Int = PinCrypto.iterations) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: keyBytes)
        let status = pin.withCString { pw in
            CCKeyDerivationPBKDF(
                CCPBKDFAlgorithm(kCCPBKDF2),
                pw, strlen(pw),
                salt, salt.count,
                CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                UInt32(iterations),
                &out, out.count)
        }
        precondition(status == kCCSuccess, "PBKDF2 falló")
        return out
    }

    /// Comparación en tiempo constante.
    static func matches(_ expected: [UInt8], _ actual: [UInt8]) -> Bool {
        var diff = expected.count ^ actual.count
        for i in 0..<min(expected.count, actual.count) { diff |= Int(expected[i] ^ actual[i]) }
        return diff == 0
    }

    /// Hasta 4 fallos no hay espera; desde el 5.º, 30 s duplicándose, con tope de 15 min.
    static func lockSeconds(failures: Int) -> Int64 {
        if failures < 5 { return 0 }
        let doublings = min(failures - 5, 5)
        return min(Int64(30) << Int64(doublings), 15 * 60)
    }
}
