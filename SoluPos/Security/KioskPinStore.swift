import Foundation

enum PinCheck: Equatable {
    case ok
    case wrong(attemptsBeforeLock: Int)
    case locked(seconds: Int64)
}

/// PIN único del equipo para salir del modo quiosco. Solo se guarda su hash y
/// su sal, en el Keychain (solo este equipo). El contador de fallos y el
/// bloqueo también viven en el Keychain para que no se puedan borrar desde
/// los ajustes de la app.
final class KioskPinStore {
    static let shared = KioskPinStore()

    private let service: String
    private let now: () -> Int64
    private let iterations: Int

    init(service: String = "com.solupos.contenedor.kioskpin",
         iterations: Int = PinCrypto.iterations,
         now: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }) {
        self.service = service
        self.iterations = iterations
        self.now = now
    }

    private func read(_ key: String) -> Data? { Keychain.get(service: service, account: key) }
    private func write(_ key: String, _ data: Data) { Keychain.set(data, service: service, account: key) }
    private func readInt(_ key: String) -> Int64 {
        read(key).flatMap { String(data: $0, encoding: .utf8) }.flatMap { Int64($0) } ?? 0
    }
    private func writeInt(_ key: String, _ v: Int64) { write(key, Data(String(v).utf8)) }

    func hasPin() -> Bool { read("hash") != nil }

    func setPin(_ pin: String) {
        precondition(PinCrypto.isValidFormat(pin), "PIN inválido")
        let salt = PinCrypto.newSalt()
        write("salt", Data(salt))
        write("hash", Data(PinCrypto.hash(pin, salt: salt, iterations: iterations)))
        writeInt("fails", 0)
        writeInt("lockedUntil", 0)
    }

    func clear() {
        ["salt", "hash", "fails", "lockedUntil"].forEach { Keychain.remove(service: service, account: $0) }
    }

    func lockedSeconds() -> Int64 { max((readInt("lockedUntil") - now()) / 1000, 0) }

    func verify(_ pin: String) -> PinCheck {
        let remaining = lockedSeconds()
        if remaining > 0 { return .locked(seconds: remaining) }
        guard let salt = read("salt"), let hash = read("hash") else { return .wrong(attemptsBeforeLock: 0) }

        if PinCrypto.matches([UInt8](hash), PinCrypto.hash(pin, salt: [UInt8](salt), iterations: iterations)) {
            writeInt("fails", 0)
            writeInt("lockedUntil", 0)
            return .ok
        }
        let fails = readInt("fails") + 1
        let lock = PinCrypto.lockSeconds(failures: Int(fails))
        writeInt("fails", fails)
        writeInt("lockedUntil", lock > 0 ? now() + lock * 1000 : 0)
        return lock > 0 ? .locked(seconds: lock) : .wrong(attemptsBeforeLock: Int(4 - fails + 1))
    }
}
