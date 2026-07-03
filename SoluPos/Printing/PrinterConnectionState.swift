import Foundation

enum PrinterConnectionState: Equatable {
    case idle
    case scanning
    case connecting
    case connected(deviceName: String)
    case error(message: String)

    var isLoading: Bool {
        switch self {
        case .scanning, .connecting: return true
        default: return false
        }
    }

    var errorMessage: String? {
        if case .error(let msg) = self { return msg }
        return nil
    }
}

enum PrintOutcome {
    case success
    case notConfigured
    case captureFailed
    case error(message: String)
}
