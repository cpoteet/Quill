import AppKit
import Foundation
import Testing
@testable import QuillKit

// MARK: - Fixtures

private let lantern = DiscoveredSite(
    siteURL: URL(string: "https://example.com")!,
    name: "Lantern & Ink",
    iconURL: nil,
    authorizationURL: URL(string: "https://example.com/wp-admin/authorize-application.php")!,
    installURL: nil
)

private let approvedCallback = URL(string: "quill://authorize?nonce=n1&user_login=chris&password=abcd+efgh+ijkl")!

private struct CheckFailed: LocalizedError {
    var errorDescription: String? { "Sorry, you are not allowed to do that." }
}

@MainActor
private final class FakeEffects {
    var discoverResult: Result<DiscoveredSite, SiteDiscoveryError> = .success(lantern)
    var discoverCalls: [URL] = []
    var opened: [URL] = []
    var verified: [Credentials] = []
    var verifyError: Error?
    var keysChecked: [String] = []
    var keyError: Error?
    var savedSettings: [AISettings] = []
    var appState: AppState?

    var dependencies: OnboardingModel.Dependencies {
        OnboardingModel.Dependencies(
            discover: { url in
                self.discoverCalls.append(url)
                await Task.yield()
                return try self.discoverResult.get()
            },
            loadIcon: { _ in nil },
            openURL: { self.opened.append($0) },
            verifyAndSave: { credentials in
                self.verified.append(credentials)
                if let error = self.verifyError { throw error }
            },
            verifyKey: { key in
                self.keysChecked.append(key)
                if let error = self.keyError { throw error }
            },
            saveAISettings: { self.savedSettings.append($0) },
            deviceName: { "Studio" },
            makeNonce: { "n1" }
        )
    }
}

@MainActor
private func makeModel(_ effects: FakeEffects, aiKey: String? = nil) -> (OnboardingModel, AppState) {
    let appState = AppState()
    appState.aiSettings = aiKey.map { AISettings(apiKey: $0) }
    effects.appState = appState
    let model = OnboardingModel(dependencies: effects.dependencies)
    model.appState = appState
    model.address = "example.com"
    return (model, appState)
}

// MARK: - OnboardingModel

@MainActor @Suite(.serialized) struct OnboardingModelTests {

    @Test func continueOpensApproval() async throws {
        let effects = FakeEffects()
        let (model, _) = makeModel(effects)
        await model.continueTapped()
        #expect(model.state == .waiting(site: lantern, nonce: "n1"))
        #expect(effects.opened.count == 1)
        let opened = try #require(effects.opened.first)
        let successURL = URLComponents(url: opened, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "success_url" }?.value
        #expect(successURL?.contains("nonce=n1") == true)
    }

    @Test func continueWithoutAuthorizationGoesManual() async {
        let effects = FakeEffects()
        effects.discoverResult = .success(DiscoveredSite(siteURL: lantern.siteURL, name: "Lantern & Ink", iconURL: nil, authorizationURL: nil, installURL: nil))
        let (model, _) = makeModel(effects)
        await model.continueTapped()
        #expect(model.state == .manual(automatic: true))
        #expect(effects.opened.isEmpty)
    }

    @Test func continueShowsDiscoveryError() async {
        let effects = FakeEffects()
        effects.discoverResult = .failure(.notWordPress)
        let (model, _) = makeModel(effects)
        await model.continueTapped()
        #expect(model.state == .welcome)
        #expect(model.errorMessage == "This doesn't look like a WordPress site, or its REST API is turned off.")
    }

    @Test func continueIgnoredWhenNotWelcome() async {
        let effects = FakeEffects()
        let (model, _) = makeModel(effects)
        await model.continueTapped()
        await model.continueTapped()
        #expect(effects.discoverCalls.count == 1)
        #expect(effects.opened.count == 1)
    }

    @Test func continueIgnoredWhileBusy() async {
        let effects = FakeEffects()
        let (model, _) = makeModel(effects)
        async let first: Void = model.continueTapped()
        async let second: Void = model.continueTapped()
        _ = await (first, second)
        #expect(effects.discoverCalls.count == 1)
        #expect(effects.opened.count == 1)
    }

    @Test func declineReturnsToWelcome() async {
        let effects = FakeEffects()
        let (model, _) = makeModel(effects)
        await model.continueTapped()
        await model.handleCallback(URL(string: "quill://authorize?nonce=n1&success=false")!)
        #expect(model.state == .welcome)
        #expect(model.notice == OnboardingModel.Notice(title: "Quill wasn't approved.", detail: "Continue to try again, or use an application password."))
        #expect(model.errorMessage == nil)
    }

    @Test func continueClearsNotice() async {
        let effects = FakeEffects()
        let (model, _) = makeModel(effects)
        await model.continueTapped()
        await model.handleCallback(URL(string: "quill://authorize?nonce=n1&success=false")!)
        await model.continueTapped()
        #expect(model.notice == nil)
    }

    @Test func staleNonceIgnored() async {
        let effects = FakeEffects()
        let (model, _) = makeModel(effects)
        await model.continueTapped()
        model.cancelWaiting()
        await model.handleCallback(approvedCallback)
        #expect(model.state == .welcome)
        #expect(effects.verified.isEmpty)
    }

    @Test func approvalWithoutKeyGoesToAISetup() async {
        let effects = FakeEffects()
        let (model, appState) = makeModel(effects)
        await model.continueTapped()
        await model.handleCallback(approvedCallback)
        #expect(model.state == .aiSetup(siteName: "Lantern & Ink"))
        #expect(appState.credentials?.username == "chris")
        #expect(effects.verified.first == Credentials(siteURL: lantern.siteURL, username: "chris", appPassword: "abcd efgh ijkl"))
    }

    @Test func approvalWithKeySkipsAI() async {
        let effects = FakeEffects()
        let (model, _) = makeModel(effects, aiKey: "k")
        await model.continueTapped()
        await model.handleCallback(approvedCallback)
        #expect(model.state == .finished)
    }

    @Test func approvalCheckFails() async {
        let effects = FakeEffects()
        effects.verifyError = CheckFailed()
        let (model, appState) = makeModel(effects)
        await model.continueTapped()
        await model.handleCallback(approvedCallback)
        #expect(model.state == .welcome)
        #expect(model.notice == OnboardingModel.Notice(title: "Quill was approved, but couldn't connect.", detail: "Sorry, you are not allowed to do that."))
        #expect(model.errorMessage == nil)
        #expect(appState.credentials == nil)
    }

    @Test func replayedCallbackIgnored() async {
        let effects = FakeEffects()
        let (model, _) = makeModel(effects)
        await model.continueTapped()
        await model.handleCallback(approvedCallback)
        await model.handleCallback(approvedCallback)
        #expect(effects.verified.count == 1)
        #expect(model.state == .aiSetup(siteName: "Lantern & Ink"))
    }

    @Test func manualConnectGoesToAISetupWithoutName() async {
        let effects = FakeEffects()
        let (model, appState) = makeModel(effects)
        model.useManualEntry()
        #expect(model.state == .manual(automatic: false))
        model.username = "chris"
        model.appPassword = "abcd efgh"
        await model.connectManually()
        #expect(model.state == .aiSetup(siteName: nil))
        #expect(effects.verified.first?.siteURL == URL(string: "https://example.com")!)
        #expect(appState.credentials?.username == "chris")
    }

    @Test func profileURLFromDiscovery() async {
        let effects = FakeEffects()
        effects.discoverResult = .success(DiscoveredSite(siteURL: URL(string: "https://example.com/blog")!, name: nil, iconURL: nil, authorizationURL: nil, installURL: nil))
        let (model, _) = makeModel(effects)
        await model.continueTapped()
        #expect(model.state == .manual(automatic: true))
        #expect(model.profileURL == URL(string: "https://example.com/blog/wp-admin/profile.php#application-passwords-section")!)
    }

    @Test func profileURLUsesInstallAddress() async {
        let effects = FakeEffects()
        effects.discoverResult = .success(DiscoveredSite(siteURL: URL(string: "https://example.com")!, name: nil, iconURL: nil, authorizationURL: nil, installURL: URL(string: "https://www.example.com")!))
        let (model, _) = makeModel(effects)
        await model.continueTapped()
        #expect(model.profileURL == URL(string: "https://www.example.com/wp-admin/profile.php#application-passwords-section")!)
    }

    @Test func skipSavesNothing() async {
        let effects = FakeEffects()
        let (model, _) = makeModel(effects)
        await model.continueTapped()
        await model.handleCallback(approvedCallback)
        model.skipAI()
        #expect(model.state == .finished)
        #expect(effects.savedSettings.isEmpty)
    }

    @Test func saveRejectedKey() async {
        let effects = FakeEffects()
        effects.keyError = AnthropicError.invalidKey
        let (model, appState) = makeModel(effects)
        await model.continueTapped()
        await model.handleCallback(approvedCallback)
        model.apiKey = "sk-ant-bad"
        await model.saveAIKey()
        #expect(model.state == .aiSetup(siteName: "Lantern & Ink"))
        #expect(model.errorMessage == "Anthropic didn't accept this key.")
        #expect(effects.savedSettings.isEmpty)
        #expect(!appState.aiEnabled)
    }

    @Test func saveUnreachable() async {
        let effects = FakeEffects()
        effects.keyError = AnthropicError.networkError(URLError(.notConnectedToInternet))
        let (model, _) = makeModel(effects)
        await model.continueTapped()
        await model.handleCallback(approvedCallback)
        model.apiKey = "sk-ant-x"
        await model.saveAIKey()
        #expect(model.state == .aiSetup(siteName: "Lantern & Ink"))
        #expect(model.errorMessage == "Couldn't reach Anthropic. Check your connection, or skip and add the key later in Settings.")
    }

    @Test func saveGoodKey() async {
        let effects = FakeEffects()
        let (model, appState) = makeModel(effects)
        await model.continueTapped()
        await model.handleCallback(approvedCallback)
        model.apiKey = "sk-ant-x"
        await model.saveAIKey()
        #expect(model.state == .finished)
        #expect(effects.keysChecked == ["sk-ant-x"])
        #expect(effects.savedSettings.map(\.apiKey) == ["sk-ant-x"])
        #expect(appState.aiEnabled)
    }
}
