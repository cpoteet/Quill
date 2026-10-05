import Foundation
import Testing
@testable import QuillKit

@Suite struct ErrorMessageTests {

    // MARK: - Which load failures Settings can fix

    @Test(arguments: [
        APIError.httpError(statusCode: 400, body: ""),
        .httpError(statusCode: 401, body: ""),
        .httpError(statusCode: 403, body: ""),
        .networkError(URLError(.cannotFindHost)),
        .networkError(URLError(.timedOut)),
        .invalidURL,
        .unexpectedHTML,
        .notConnected,
    ])
    func settingsFixableErrors(error: APIError) {
        #expect(error.isFixedInSettings)
    }

    @Test(arguments: [
        APIError.httpError(statusCode: 404, body: ""),
        .httpError(statusCode: 500, body: ""),
        .networkError(URLError(.notConnectedToInternet)),
        .networkError(URLError(.badServerResponse)),
        .decodingError(CocoaError(.coderReadCorrupt)),
    ])
    func errorsSettingsCannotFix(error: APIError) {
        #expect(!error.isFixedInSettings)
    }

    @Test func loadFailureCarriesTheMessageAndTheSettingsFlag() {
        let failure = LoadFailure(APIError.httpError(statusCode: 401, body: ""))
        #expect(failure.message == APIError.httpError(statusCode: 401, body: "").errorDescription)
        #expect(failure.needsSettings)
    }

    @Test func loadFailureFromANonAPIErrorDoesNotPointAtSettings() {
        let failure = LoadFailure(URLError(.timedOut))
        #expect(!failure.needsSettings)
    }

    // MARK: - Anthropic HTTP errors read as sentences, not JSON

    @Test func anthropicRateLimitSaysToWait() {
        #expect(AnthropicError.httpError(429, "{}").errorDescription
                == "You've hit Anthropic's rate limit. Wait a minute and try again.")
    }

    @Test func anthropicOverloadAndServerErrorsSayTryAgainLater() {
        let expected = "Anthropic's API is busy or having problems. Try again in a moment."
        #expect(AnthropicError.httpError(529, "{}").errorDescription == expected)
        #expect(AnthropicError.httpError(500, "{}").errorDescription == expected)
    }

    @Test func anthropicRejectedRequestQuotesAnthropicsOwnMessage() {
        let body = #"{"type":"error","error":{"type":"invalid_request_error","message":"Your credit balance is too low."}}"#
        #expect(AnthropicError.httpError(400, body).errorDescription
                == "Anthropic didn't accept the request: Your credit balance is too low.")
    }

    @Test func anthropicErrorWithoutAReadableBodyNamesTheStatus() {
        #expect(AnthropicError.httpError(418, "<html>teapot</html>").errorDescription
                == "Anthropic returned an error (HTTP 418). Try again.")
        #expect(AnthropicError.httpError(400, #"{"type":"error"}"#).errorDescription
                == "Anthropic returned an error (HTTP 400). Try again.")
        #expect(AnthropicError.httpError(400, #"{"error":{"type":"x","message":""}}"#).errorDescription
                == "Anthropic returned an error (HTTP 400). Try again.")
    }

    @Test func anthropicServerErrorIgnoresTheBodyMessage() {
        let body = #"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#
        #expect(AnthropicError.httpError(529, body).errorDescription
                == "Anthropic's API is busy or having problems. Try again in a moment.")
        #expect(AnthropicError.httpError(499, body).errorDescription
                == "Anthropic didn't accept the request: Overloaded")
    }

    @Test func anthropicUnauthorizedReadsLikeAnInvalidKey() {
        #expect(AnthropicError.httpError(401, "{}").errorDescription == AnthropicError.invalidKey.errorDescription)
    }

    // MARK: - AI rewrite failures

    @Test func aiFailureShowsAnthropicsReason() {
        let error = AnthropicError.networkError(URLError(.notConnectedToInternet))
        #expect(PostEditorView.aiFailureMessage(for: error) == error.errorDescription)
    }

    @Test func aiFailureFromAnythingElseIsGeneric() {
        struct Odd: Error {}
        #expect(PostEditorView.aiFailureMessage(for: Odd()) == "Claude couldn't finish that rewrite. Try again.")
    }

    // MARK: - Editor banner

    @Test func aRetryClearsItsOwnBannerError() {
        let banner = EditorBanner(message: "Upload failed: offline", source: .upload)
        #expect(banner.clearing(.upload) == nil)
    }

    @Test func anotherOperationLeavesTheBannerAlone() {
        let banner = EditorBanner(message: "Upload failed: offline", source: .upload)
        #expect(banner.clearing(.autosave) == banner)
    }

    // MARK: - Toast timing

    @Test func errorToastsStayLongerThanSuccessToasts() {
        #expect(ToastStyle.error.duration == .seconds(6))
        #expect(ToastStyle.success.duration == .seconds(2))
        #expect(ToastStyle.info.duration == .seconds(2))
    }
}
