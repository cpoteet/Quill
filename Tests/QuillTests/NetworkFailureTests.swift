import Foundation
import Testing
@testable import QuillKit

@Suite struct NetworkFailureTests {

    private struct FakeError: Error, LocalizedError {
        let description: String
        var errorDescription: String? { description }
    }

    @Test(arguments: [
        URLError.Code.notConnectedToInternet,
        .networkConnectionLost,
        .cannotConnectToHost,
        .cannotFindHost,
        .timedOut,
        .dnsLookupFailed,
    ])
    func connectivityCodesAreConnectivityFailures(code: URLError.Code) {
        #expect(NetworkFailure.isConnectivity(URLError(code)))
    }

    @Test func otherURLErrorCodesAreNot() {
        #expect(!NetworkFailure.isConnectivity(URLError(.badURL)))
        #expect(!NetworkFailure.isConnectivity(URLError(.secureConnectionFailed)))
    }

    @Test func englishOfflineTextWithoutAURLErrorIsNot() {
        #expect(!NetworkFailure.isConnectivity(FakeError(description: "The Internet connection appears to be offline.")))
        #expect(!NetworkFailure.isConnectivity(FakeError(description: "Resource not found")))
    }

    @Test func urlErrorBridgedThroughNSErrorIsRecognised() {
        let bridged = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        #expect(NetworkFailure.isConnectivity(bridged))
    }

    @Test func apiErrorShowsFriendlyMessageForConnectivityFailure() {
        let err = APIError.networkError(URLError(.cannotFindHost))
        #expect(err.errorDescription == "Couldn't reach your site. Check the URL and make sure your site is online.")
    }

    @Test func apiErrorPassesThroughOtherNetworkErrors() {
        let err = APIError.networkError(FakeError(description: "The Internet connection appears to be offline."))
        #expect(err.errorDescription == "The Internet connection appears to be offline.")
    }

    @Test func anthropicErrorShowsFriendlyMessageForConnectivityFailure() {
        let err = AnthropicError.networkError(URLError(.notConnectedToInternet))
        #expect(err.errorDescription == "Couldn't reach the Anthropic API. Check your internet connection and try again.")
    }
}
