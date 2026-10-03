import AppKit
import Foundation

@MainActor public final class OnboardingModel: ObservableObject {
    public enum State: Equatable {
        case welcome
        case waiting(site: DiscoveredSite, nonce: String)
        case manual(automatic: Bool)
        case aiSetup(siteName: String?)
        case finished
    }

    public struct Dependencies {
        var discover: @MainActor (URL) async throws -> DiscoveredSite
        var loadIcon: @MainActor (URL) async -> NSImage?
        var openURL: @MainActor (URL) -> Void
        var verifyAndSave: @MainActor (Credentials) async throws -> Void
        var verifyKey: @MainActor (String) async throws -> Void
        var saveAISettings: @MainActor (AISettings) throws -> Void
        var deviceName: @MainActor () -> String
        var makeNonce: @MainActor () -> String

        public static var live: Dependencies {
            Dependencies(
                discover: { try await SiteDiscovery().discover($0) },
                loadIcon: { await SiteDiscovery().loadIcon($0) },
                openURL: { NSWorkspace.shared.open($0) },
                verifyAndSave: { try await ConnectSite.verifyAndSave($0) },
                verifyKey: { try await AnthropicClient(apiKey: $0).verifyKey() },
                saveAISettings: { try AISettingsStore.save($0) },
                deviceName: { Host.current().localizedName ?? "Mac" },
                makeNonce: { AppAuthorization.makeNonce() }
            )
        }
    }

    private static let declinedMessage = "Quill wasn't approved. Try again, or use an application password."
    private static let anthropicUnreachableMessage = "Couldn't reach Anthropic. Check your connection, or skip and add the key later in Settings."
    private static let anthropicConsoleURL = URL(string: "https://console.anthropic.com/settings/keys")!

    @Published public private(set) var state: State = .welcome {
        didSet { if state != oldValue { errorMessage = nil } }
    }
    @Published public var address = ""
    @Published public var username = ""
    @Published public var appPassword = ""
    @Published public var apiKey = ""
    @Published public private(set) var siteIcon: NSImage?
    @Published public private(set) var isBusy = false
    @Published public private(set) var errorMessage: String?
    public weak var appState: AppState?

    private let dependencies: Dependencies
    private var discovery: (address: URL, site: DiscoveredSite)?

    public init(dependencies: Dependencies = .live) {
        self.dependencies = dependencies
    }

    public var showsPanel: Bool {
        if case .aiSetup = state { return true }
        return appState?.credentials == nil
    }

    public var profileURL: URL? {
        if let site = discoveredSiteForAddress {
            return SiteDiscovery.profileURL(site: site.siteURL, authorizationURL: site.authorizationURL)
        }
        guard let site = try? SiteDiscovery.normalize(address) else { return nil }
        return SiteDiscovery.profileURL(site: site, authorizationURL: nil)
    }

    private var discoveredSiteForAddress: DiscoveredSite? {
        guard let discovery, (try? SiteDiscovery.normalize(address)) == discovery.address else { return nil }
        return discovery.site
    }

    // MARK: - Welcome

    public func continueTapped() async {
        guard state == .welcome, !isBusy else { return }
        isBusy = true
        errorMessage = nil
        let site: DiscoveredSite
        do {
            let url = try SiteDiscovery.normalize(address)
            site = try await dependencies.discover(url)
            discovery = (url, site)
        } catch {
            isBusy = false
            errorMessage = error.localizedDescription
            return
        }
        isBusy = false
        guard state == .welcome else { return }

        guard site.authorizationURL != nil else {
            state = .manual(automatic: true)
            return
        }
        let nonce = dependencies.makeNonce()
        state = .waiting(site: site, nonce: nonce)
        reopenBrowser()
        siteIcon = nil
        guard let iconURL = site.iconURL else { return }
        let icon = await dependencies.loadIcon(iconURL)
        if state == .waiting(site: site, nonce: nonce) { siteIcon = icon }
    }

    public func useManualEntry() {
        guard state == .welcome, !isBusy else { return }
        state = .manual(automatic: false)
    }

    // MARK: - Waiting

    public func cancelWaiting() {
        guard case .waiting = state, !isBusy else { return }
        state = .welcome
    }

    public func reopenBrowser() {
        guard case .waiting(let site, let nonce) = state, let base = site.authorizationURL else { return }
        dependencies.openURL(AppAuthorization.approvalURL(base: base, nonce: nonce, deviceName: dependencies.deviceName()))
    }

    public func handleCallback(_ url: URL) async {
        guard case .waiting(let site, let nonce) = state, !isBusy else { return }
        switch AppAuthorization.parseCallback(url, expectedNonce: nonce) {
        case .ignored:
            return
        case .rejected:
            state = .welcome
            errorMessage = Self.declinedMessage
        case .approved(let username, let password):
            let credentials = Credentials(siteURL: site.siteURL, username: username, appPassword: password)
            do {
                try await connect(credentials, siteName: site.name)
            } catch {
                state = .welcome
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Manual

    public func back() {
        guard case .manual = state, !isBusy else { return }
        state = .welcome
    }

    public func connectManually() async {
        guard case .manual = state, !isBusy else { return }
        errorMessage = nil
        do {
            let url = try SiteDiscovery.normalize(address)
            let site = discoveredSiteForAddress
            let credentials = Credentials(siteURL: site?.siteURL ?? url, username: username, appPassword: appPassword)
            try await connect(credentials, siteName: site?.name)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func openProfilePage() {
        guard let profileURL else { return }
        dependencies.openURL(profileURL)
    }

    private func connect(_ credentials: Credentials, siteName: String?) async throws {
        isBusy = true
        defer { isBusy = false }
        try await dependencies.verifyAndSave(credentials)
        state = appState?.aiEnabled == true ? .finished : .aiSetup(siteName: siteName)
        await appState?.connect(credentials)
    }

    // MARK: - AI

    public func saveAIKey() async {
        guard case .aiSetup = state, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        errorMessage = nil
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await dependencies.verifyKey(key)
            let settings = AISettings(apiKey: key)
            try dependencies.saveAISettings(settings)
            appState?.aiSettings = settings
            state = .finished
        } catch AnthropicError.networkError {
            errorMessage = Self.anthropicUnreachableMessage
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func skipAI() {
        guard case .aiSetup = state, !isBusy else { return }
        state = .finished
    }

    public func openAnthropicConsole() {
        dependencies.openURL(Self.anthropicConsoleURL)
    }
}
