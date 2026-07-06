import Foundation

/// Shared substring heuristic for detecting "device/server unreachable"-style errors from a
/// `localizedDescription`, used by both `APIError` and `AnthropicError` so their offline/
/// connectivity detection can't independently drift out of sync.
enum NetworkErrorHeuristics {
    static func isConnectivityFailure(_ message: String) -> Bool {
        message.contains("Could not connect")
            || message.contains("Cannot connect")
            || message.contains("not found")
            || message.contains("offline")
    }
}
