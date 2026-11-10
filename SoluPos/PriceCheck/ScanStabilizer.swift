import Foundation

/// Confirma una lectura de cámara. Los códigos cortos (3 dígitos) se confunden
/// fácil, así que se exige ver el mismo valor en varios fotogramas seguidos, y
/// luego se ignora el mismo código unos segundos para no repetir la consulta.
final class ScanStabilizer {
    private let requiredHits: Int
    private let cooldownMs: Int64
    private let candidateWindowMs: Int64
    private let clock: () -> Int64

    private var candidate: String?
    private var hits = 0
    private var candidateAt: Int64 = 0
    private var lastEmitted: String?
    private var lastEmitAt: Int64 = 0

    init(requiredHits: Int = 2,
         cooldownMs: Int64 = 3_000,
         candidateWindowMs: Int64 = 1_000,
         clock: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }) {
        self.requiredHits = requiredHits
        self.cooldownMs = cooldownMs
        self.candidateWindowMs = candidateWindowMs
        self.clock = clock
    }

    /// Devuelve el código cuando queda confirmado; si no, nil.
    func offer(_ code: String?) -> String? {
        guard let code, !code.isEmpty else { return nil }
        let now = clock()
        if code == lastEmitted && now - lastEmitAt < cooldownMs { return nil }

        if code == candidate && now - candidateAt <= candidateWindowMs {
            hits += 1
        } else {
            candidate = code
            hits = 1
        }
        candidateAt = now
        if hits < requiredHits { return nil }

        lastEmitted = code
        lastEmitAt = now
        candidate = nil
        hits = 0
        return code
    }

    func reset() {
        candidate = nil
        hits = 0
        lastEmitted = nil
    }
}
