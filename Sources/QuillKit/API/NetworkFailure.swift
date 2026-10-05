import Foundation

enum NetworkFailure {
    private static let connectivityCodes: Set<URLError.Code> = [
        .notConnectedToInternet,
        .networkConnectionLost,
        .cannotConnectToHost,
        .cannotFindHost,
        .timedOut,
        .dnsLookupFailed,
    ]

    static func isConnectivity(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        return connectivityCodes.contains(urlError.code)
    }
}
