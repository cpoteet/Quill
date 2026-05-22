# WPWriter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build WPWriter, a native macOS two-column app for writing and managing WordPress content, distributable as a double-clickable `.app` bundle built entirely with Swift Package Manager.

**Architecture:** A `WPWriterKit` library target holds all logic (models, API client, storage, SwiftUI views); a thin `WPWriter` executable calls `WPWriterApp.main()`. The editor is Quill.js v1.3.7 (bundled locally, no npm) running inside a `WKWebView`. WordPress is reached via REST API with Application Passwords auth stored in the macOS Keychain. Offline drafts are persisted to SQLite via SQLite.swift.

**Tech Stack:** Swift 6, SwiftUI (macOS 13+), WKWebView, URLSession async/await, SQLite.swift 0.15.3, Tiptap 2.x (loaded via esm.sh CDN inside WKWebView — no npm needed), macOS Security framework (Keychain)

---

## File Map

```
WPWriter/
├── Package.swift
├── build.sh
├── Sources/
│   ├── WPWriter/
│   │   └── main.swift                         # Entry point: calls WPWriterApp.main()
│   └── WPWriterKit/
│       ├── App/
│       │   ├── WPWriterApp.swift              # SwiftUI App struct, WindowGroup, Preferences
│       │   └── AppState.swift                 # @Observable root state (section, selectedPost, etc.)
│       ├── Auth/
│       │   ├── Credentials.swift              # Codable struct: siteURL, username, appPassword
│       │   └── KeychainStore.swift            # SecItemAdd/Copy/Delete wrapper
│       ├── API/
│       │   ├── APIError.swift                 # Typed errors for HTTP/decode failures
│       │   ├── WordPressClient.swift          # async/await REST client (posts, pages, media, taxonomies)
│       │   └── Models/
│       │       ├── WPPost.swift               # Decodable post + encodable create/update payload
│       │       ├── WPMedia.swift              # Decodable media item
│       │       └── WPTaxonomy.swift           # Decodable category + tag
│       ├── Storage/
│       │   ├── Database.swift                 # SQLite connection, migrations, schema creation
│       │   ├── DraftStore.swift               # CRUD for local-only drafts
│       │   ├── AutosaveStore.swift            # Per-WP-post-ID autosave snapshots
│       │   └── TaxonomyCache.swift            # Cached categories/tags with invalidation timestamp
│       ├── Views/
│       │   ├── ContentView.swift              # NavigationSplitView root (sidebar + editor column)
│       │   ├── Sidebar/
│       │   │   ├── SidebarView.swift          # Source list (Posts/Pages/Local Drafts/Media) + item list
│       │   │   └── PostListRow.swift          # Single row: title + date + status badge
│       │   ├── Editor/
│       │   │   ├── EditorView.swift           # NSViewRepresentable wrapping WKWebView + Quill
│       │   │   ├── EditorCoordinator.swift    # WKScriptMessageHandler, WKNavigationDelegate
│       │   │   └── PostEditorView.swift       # Toolbar (Save/Preview/Publish) + EditorView + autosave timer
│       │   ├── Settings/
│       │   │   ├── PostSettingsPanel.swift    # Drawer: status, date, categories, tags, featured image, excerpt
│       │   │   └── PreferencesView.swift      # Site URL + credentials form, saves to Keychain
│       │   └── Media/
│       │       └── MediaPickerView.swift      # Sheet: browse WP media library or upload from disk
│       └── Resources/
│           └── editor.html                    # Tiptap editor (imports Tiptap 2.x from esm.sh CDN at runtime)
└── Tests/
    └── WPWriterTests/
        ├── KeychainStoreTests.swift
        ├── WordPressClientTests.swift
        ├── DraftStoreTests.swift
        ├── AutosaveStoreTests.swift
        └── TaxonomyCacheTests.swift
```

---

## Task 1: Project Scaffold

**Files:**
- Create: `Package.swift`
- Create: `Sources/WPWriter/main.swift`
- Create: `Sources/WPWriterKit/App/WPWriterApp.swift`
- Create: `Sources/WPWriterKit/App/AppState.swift` (stub)
- Create: `Sources/WPWriterKit/Views/ContentView.swift` (stub)
- Create: `build.sh`

- [ ] **Step 1: Create directory tree**

```bash
mkdir -p "Sources/WPWriter"
mkdir -p "Sources/WPWriterKit/App"
mkdir -p "Sources/WPWriterKit/Auth"
mkdir -p "Sources/WPWriterKit/API/Models"
mkdir -p "Sources/WPWriterKit/Storage"
mkdir -p "Sources/WPWriterKit/Views/Sidebar"
mkdir -p "Sources/WPWriterKit/Views/Editor"
mkdir -p "Sources/WPWriterKit/Views/Settings"
mkdir -p "Sources/WPWriterKit/Views/Media"
mkdir -p "Sources/WPWriterKit/Resources"
mkdir -p "Tests/WPWriterTests"
```

- [ ] **Step 2: Write `Package.swift`**

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WPWriter",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "WPWriter", targets: ["WPWriter"]),
    ],
    dependencies: [
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.15.3"),
    ],
    targets: [
        .executableTarget(
            name: "WPWriter",
            dependencies: ["WPWriterKit"],
            path: "Sources/WPWriter"
        ),
        .target(
            name: "WPWriterKit",
            dependencies: [
                .product(name: "SQLite", package: "SQLite.swift"),
            ],
            path: "Sources/WPWriterKit",
            resources: [.copy("Resources")]
        ),
        .testTarget(
            name: "WPWriterTests",
            dependencies: ["WPWriterKit"],
            path: "Tests/WPWriterTests"
        ),
    ]
)
```

- [ ] **Step 3: Write `Sources/WPWriter/main.swift`**

```swift
import WPWriterKit
WPWriterApp.main()
```

- [ ] **Step 4: Write stub `Sources/WPWriterKit/App/WPWriterApp.swift`**

```swift
import SwiftUI

public struct WPWriterApp: App {
    public init() {}

    public var body: some Scene {
        WindowGroup("WPWriter") {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
```

- [ ] **Step 5: Write stub `Sources/WPWriterKit/Views/ContentView.swift`**

```swift
import SwiftUI

public struct ContentView: View {
    public init() {}

    public var body: some View {
        Text("WPWriter")
            .frame(minWidth: 900, minHeight: 600)
    }
}
```

- [ ] **Step 6: Verify compile**

```bash
swift build 2>&1
```
Expected: `Build complete!`

- [ ] **Step 7: Write `build.sh` (skeleton — completed in Task 19)**

```bash
#!/usr/bin/env bash
set -euo pipefail

APP_NAME="WPWriter"
BUNDLE_ID="com.wpwriter.app"
MIN_MACOS="13.0"

echo "Building $APP_NAME..."
swift build -c release 2>&1

BINARY=".build/release/$APP_NAME"
APP_DIR="$APP_NAME.app/Contents"

rm -rf "$APP_NAME.app"
mkdir -p "$APP_DIR/MacOS"
mkdir -p "$APP_DIR/Resources"

cp "$BINARY" "$APP_DIR/MacOS/$APP_NAME"

# Resources (skeleton — completed in Task 18)

cat > "$APP_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

echo "Done: $APP_NAME.app"
```

```bash
chmod +x build.sh
```

- [ ] **Step 8: Commit**

```bash
git init
git add Package.swift build.sh Sources/ Tests/
git commit -m "feat: project scaffold — SPM package, stub app, build script"
```

---

## Task 2: Credentials Model & Keychain Store

**Files:**
- Create: `Sources/WPWriterKit/Auth/Credentials.swift`
- Create: `Sources/WPWriterKit/Auth/KeychainStore.swift`
- Create: `Tests/WPWriterTests/KeychainStoreTests.swift`

- [ ] **Step 1: Write failing test**

`Tests/WPWriterTests/KeychainStoreTests.swift`:
```swift
import XCTest
@testable import WPWriterKit

final class KeychainStoreTests: XCTestCase {
    let testCredentials = Credentials(
        siteURL: URL(string: "https://example.com")!,
        username: "testuser",
        appPassword: "xxxx yyyy zzzz"
    )

    override func setUp() {
        super.setUp()
        try? KeychainStore.delete()
    }

    override func tearDown() {
        super.tearDown()
        try? KeychainStore.delete()
    }

    func testSaveAndLoad() throws {
        try KeychainStore.save(testCredentials)
        let loaded = try KeychainStore.load()
        XCTAssertEqual(loaded?.siteURL, testCredentials.siteURL)
        XCTAssertEqual(loaded?.username, testCredentials.username)
        XCTAssertEqual(loaded?.appPassword, testCredentials.appPassword)
    }

    func testLoadReturnsNilWhenEmpty() throws {
        let result = try KeychainStore.load()
        XCTAssertNil(result)
    }

    func testDeleteRemovesCredentials() throws {
        try KeychainStore.save(testCredentials)
        try KeychainStore.delete()
        let result = try KeychainStore.load()
        XCTAssertNil(result)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter KeychainStoreTests 2>&1 | tail -20
```
Expected: compile error — `Credentials` and `KeychainStore` not defined.

- [ ] **Step 3: Write `Sources/WPWriterKit/Auth/Credentials.swift`**

```swift
import Foundation

public struct Credentials: Codable, Sendable {
    public var siteURL: URL
    public var username: String
    public var appPassword: String

    public init(siteURL: URL, username: String, appPassword: String) {
        self.siteURL = siteURL
        self.username = username
        self.appPassword = appPassword
    }

    var basicAuthHeader: String {
        let raw = "\(username):\(appPassword)"
        return "Basic " + Data(raw.utf8).base64EncodedString()
    }
}
```

- [ ] **Step 4: Write `Sources/WPWriterKit/Auth/KeychainStore.swift`**

```swift
import Foundation
import Security

public enum KeychainError: Error {
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
    case deleteFailed(OSStatus)
}

public struct KeychainStore {
    private static let service = "com.wpwriter.app"
    private static let account = "wordpress-credentials"

    public static func save(_ credentials: Credentials) throws {
        let data = try JSONEncoder().encode(credentials)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.saveFailed(status) }
    }

    public static func load() throws -> Credentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.loadFailed(status)
        }
        return try JSONDecoder().decode(Credentials.self, from: data)
    }

    public static func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
swift test --filter KeychainStoreTests 2>&1 | tail -10
```
Expected: `Test Suite 'KeychainStoreTests' passed`

- [ ] **Step 6: Commit**

```bash
git add Sources/WPWriterKit/Auth/ Tests/WPWriterTests/KeychainStoreTests.swift
git commit -m "feat: credentials model and Keychain store"
```

---

## Task 3: WordPress API Models

**Files:**
- Create: `Sources/WPWriterKit/API/APIError.swift`
- Create: `Sources/WPWriterKit/API/Models/WPPost.swift`
- Create: `Sources/WPWriterKit/API/Models/WPMedia.swift`
- Create: `Sources/WPWriterKit/API/Models/WPTaxonomy.swift`

- [ ] **Step 1: Write `Sources/WPWriterKit/API/APIError.swift`**

```swift
import Foundation

public enum APIError: Error, LocalizedError {
    case invalidURL
    case httpError(statusCode: Int, body: String)
    case decodingError(Error)
    case networkError(Error)
    case noCredentials

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid site URL."
        case .httpError(let code, let body): return "HTTP \(code): \(body)"
        case .decodingError(let e): return "Decode error: \(e.localizedDescription)"
        case .networkError(let e): return e.localizedDescription
        case .noCredentials: return "No credentials saved. Open Preferences to add your site."
        }
    }
}
```

- [ ] **Step 2: Write `Sources/WPWriterKit/API/Models/WPPost.swift`**

```swift
import Foundation

public struct WPPost: Identifiable, Codable, Sendable {
    public let id: Int
    public var title: RenderedString
    public var content: RenderedString
    public var excerpt: RenderedString
    public var status: String            // "publish", "draft", "future", "trash"
    public var date: String              // ISO8601, server local time
    public var modified: String          // ISO8601 — used for conflict detection
    public var slug: String
    public var link: String
    public var featuredMedia: Int        // media ID, 0 if none
    public var categories: [Int]
    public var tags: [Int]

    enum CodingKeys: String, CodingKey {
        case id, title, content, excerpt, status, date, modified, slug, link
        case featuredMedia = "featured_media"
        case categories, tags
    }
}

public struct RenderedString: Codable, Sendable {
    public var rendered: String
    public var raw: String?

    public init(raw: String) {
        self.rendered = raw
        self.raw = raw
    }
}

public struct PostPayload: Encodable, Sendable {
    public var title: String
    public var content: String
    public var excerpt: String
    public var status: String
    public var date: String?
    public var featuredMedia: Int?
    public var categories: [Int]
    public var tags: [Int]

    enum CodingKeys: String, CodingKey {
        case title, content, excerpt, status, date
        case featuredMedia = "featured_media"
        case categories, tags
    }

    public init(
        title: String,
        content: String,
        excerpt: String = "",
        status: String,
        date: String? = nil,
        featuredMedia: Int? = nil,
        categories: [Int] = [],
        tags: [Int] = []
    ) {
        self.title = title
        self.content = content
        self.excerpt = excerpt
        self.status = status
        self.date = date
        self.featuredMedia = featuredMedia
        self.categories = categories
        self.tags = tags
    }
}
```

- [ ] **Step 3: Write `Sources/WPWriterKit/API/Models/WPMedia.swift`**

```swift
import Foundation

public struct WPMedia: Identifiable, Codable, Sendable {
    public let id: Int
    public var title: RenderedString
    public var sourceURL: String
    public var mediaType: String         // "image", "file", etc.
    public var mimeType: String
    public var mediaDetails: MediaDetails?

    enum CodingKeys: String, CodingKey {
        case id, title
        case sourceURL = "source_url"
        case mediaType = "media_type"
        case mimeType = "mime_type"
        case mediaDetails = "media_details"
    }
}

public struct MediaDetails: Codable, Sendable {
    public var width: Int?
    public var height: Int?
    public var sizes: [String: MediaSize]?
}

public struct MediaSize: Codable, Sendable {
    public var sourceURL: String
    public var width: Int
    public var height: Int

    enum CodingKeys: String, CodingKey {
        case sourceURL = "source_url"
        case width, height
    }
}
```

- [ ] **Step 4: Write `Sources/WPWriterKit/API/Models/WPTaxonomy.swift`**

```swift
import Foundation

public struct WPCategory: Identifiable, Codable, Sendable {
    public let id: Int
    public var name: String
    public var slug: String
    public var count: Int
    public var parent: Int
}

public struct WPTag: Identifiable, Codable, Sendable {
    public let id: Int
    public var name: String
    public var slug: String
    public var count: Int
}
```

- [ ] **Step 5: Verify compile**

```bash
swift build 2>&1
```
Expected: `Build complete!`

- [ ] **Step 6: Commit**

```bash
git add Sources/WPWriterKit/API/
git commit -m "feat: WordPress REST API models and error types"
```

---

## Task 4: WordPress REST Client

**Files:**
- Create: `Sources/WPWriterKit/API/WordPressClient.swift`
- Create: `Tests/WPWriterTests/WordPressClientTests.swift`

- [ ] **Step 1: Write failing test**

`Tests/WPWriterTests/WordPressClientTests.swift`:
```swift
import XCTest
@testable import WPWriterKit

final class WordPressClientTests: XCTestCase {
    var client: WordPressClient!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        let credentials = Credentials(
            siteURL: URL(string: "https://example.com")!,
            username: "user",
            appPassword: "pass"
        )
        client = WordPressClient(credentials: credentials, session: session)
    }

    func testFetchPostsDecodesList() async throws {
        let json = """
        [{"id":1,"title":{"rendered":"Hello","raw":"Hello"},
          "content":{"rendered":"<p>World</p>","raw":"<p>World</p>"},
          "excerpt":{"rendered":"","raw":""},
          "status":"publish","date":"2024-01-01T00:00:00",
          "modified":"2024-01-01T00:00:00","slug":"hello","link":"https://example.com/hello",
          "featured_media":0,"categories":[],"tags":[]}]
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://example.com")!,
                statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, json)
        }

        let posts = try await client.fetchPosts()
        XCTAssertEqual(posts.count, 1)
        XCTAssertEqual(posts[0].id, 1)
        XCTAssertEqual(posts[0].title.rendered, "Hello")
    }

    func testFetchPostsThrowsOnHTTPError() async {
        MockURLProtocol.requestHandler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://example.com")!,
                statusCode: 401, httpVersion: nil, headerFields: nil
            )!
            return (response, Data())
        }

        do {
            _ = try await client.fetchPosts()
            XCTFail("Expected error")
        } catch APIError.httpError(let code, _) {
            XCTAssertEqual(code, 401)
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }
}

// MARK: - Mock URLProtocol
final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter WordPressClientTests 2>&1 | tail -10
```
Expected: compile error — `WordPressClient` not defined.

- [ ] **Step 3: Write `Sources/WPWriterKit/API/WordPressClient.swift`**

```swift
import Foundation

public struct WordPressClient: Sendable {
    private let credentials: Credentials
    private let session: URLSession

    public init(credentials: Credentials, session: URLSession = .shared) {
        self.credentials = credentials
        self.session = session
    }

    // MARK: - Posts

    public func fetchPosts(page: Int = 1, perPage: Int = 100) async throws -> [WPPost] {
        let url = try endpoint("posts", query: ["per_page": "\(perPage)", "page": "\(page)", "context": "edit"])
        return try await get(url)
    }

    public func fetchPages(page: Int = 1, perPage: Int = 100) async throws -> [WPPost] {
        let url = try endpoint("pages", query: ["per_page": "\(perPage)", "page": "\(page)", "context": "edit"])
        return try await get(url)
    }

    public func fetchPost(id: Int) async throws -> WPPost {
        let url = try endpoint("posts/\(id)", query: ["context": "edit"])
        return try await get(url)
    }

    public func createPost(_ payload: PostPayload) async throws -> WPPost {
        let url = try endpoint("posts")
        return try await post(url, body: payload)
    }

    public func updatePost(id: Int, payload: PostPayload) async throws -> WPPost {
        let url = try endpoint("posts/\(id)")
        return try await put(url, body: payload)
    }

    public func createPage(_ payload: PostPayload) async throws -> WPPost {
        let url = try endpoint("pages")
        return try await post(url, body: payload)
    }

    public func updatePage(id: Int, payload: PostPayload) async throws -> WPPost {
        let url = try endpoint("pages/\(id)")
        return try await put(url, body: payload)
    }

    // MARK: - Media

    public func fetchMedia(page: Int = 1, perPage: Int = 50) async throws -> [WPMedia] {
        let url = try endpoint("media", query: ["per_page": "\(perPage)", "page": "\(page)"])
        return try await get(url)
    }

    public func uploadMedia(data: Data, filename: String, mimeType: String) async throws -> WPMedia {
        let url = try endpoint("media")
        var request = authorizedRequest(url: url, method: "POST")
        request.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        request.setValue("attachment; filename=\"\(filename)\"", forHTTPHeaderField: "Content-Disposition")
        request.httpBody = data
        return try await perform(request)
    }

    // MARK: - Taxonomies

    public func fetchCategories() async throws -> [WPCategory] {
        let url = try endpoint("categories", query: ["per_page": "100"])
        return try await get(url)
    }

    public func fetchTags() async throws -> [WPTag] {
        let url = try endpoint("tags", query: ["per_page": "100"])
        return try await get(url)
    }

    // MARK: - Autosave (for Preview)

    public func createAutosave(postID: Int, payload: PostPayload) async throws -> WPPost {
        let url = try endpoint("posts/\(postID)/autosaves")
        return try await post(url, body: payload)
    }

    // MARK: - Helpers

    private func endpoint(_ path: String, query: [String: String] = [:]) throws -> URL {
        guard var components = URLComponents(
            url: credentials.siteURL.appendingPathComponent("/wp-json/wp/v2/\(path)"),
            resolvingAgainstBaseURL: false
        ) else { throw APIError.invalidURL }
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw APIError.invalidURL }
        return url
    }

    private func authorizedRequest(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(credentials.basicAuthHeader, forHTTPHeaderField: "Authorization")
        return request
    }

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        let request = authorizedRequest(url: url, method: "GET")
        return try await perform(request)
    }

    private func post<T: Decodable, B: Encodable>(_ url: URL, body: B) async throws -> T {
        var request = authorizedRequest(url: url, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await perform(request)
    }

    private func put<T: Decodable, B: Encodable>(_ url: URL, body: B) async throws -> T {
        var request = authorizedRequest(url: url, method: "PUT")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await perform(request)
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }
        if let http = response as? HTTPURLResponse, http.statusCode >= 300 {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw APIError.httpError(statusCode: http.statusCode, body: body)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter WordPressClientTests 2>&1 | tail -10
```
Expected: `Test Suite 'WordPressClientTests' passed`

- [ ] **Step 5: Commit**

```bash
git add Sources/WPWriterKit/API/WordPressClient.swift Tests/WPWriterTests/WordPressClientTests.swift
git commit -m "feat: WordPress REST API client with mock-testable URLSession injection"
```

---

## Task 5: Database Schema

**Files:**
- Create: `Sources/WPWriterKit/Storage/Database.swift`

- [ ] **Step 1: Write `Sources/WPWriterKit/Storage/Database.swift`**

```swift
import Foundation
import SQLite

public final class AppDatabase: @unchecked Sendable {
    let db: Connection

    // local_drafts columns
    let drafts = Table("local_drafts")
    let draftID = Expression<Int64>("id")
    let draftTitle = Expression<String>("title")
    let draftContent = Expression<String>("content")
    let draftExcerpt = Expression<String>("excerpt")
    let draftCreatedAt = Expression<Double>("created_at")
    let draftUpdatedAt = Expression<Double>("updated_at")

    // autosaves columns
    let autosaves = Table("autosaves")
    let autosavePostID = Expression<Int>("post_id")
    let autosaveTitle = Expression<String>("title")
    let autosaveContent = Expression<String>("content")
    let autosaveSavedAt = Expression<Double>("saved_at")
    let autosaveServerModified = Expression<String>("server_modified")

    // taxonomy_cache columns
    let taxonomyCache = Table("taxonomy_cache")
    let taxType = Expression<String>("type")       // "category" or "tag"
    let taxID = Expression<Int>("wp_id")
    let taxName = Expression<String>("name")
    let taxSlug = Expression<String>("slug")
    let taxFetchedAt = Expression<Double>("fetched_at")

    public init(path: String) throws {
        db = try Connection(path)
        try migrate()
    }

    private func migrate() throws {
        try db.run(drafts.create(ifNotExists: true) { t in
            t.column(draftID, primaryKey: .autoincrement)
            t.column(draftTitle)
            t.column(draftContent)
            t.column(draftExcerpt)
            t.column(draftCreatedAt)
            t.column(draftUpdatedAt)
        })

        try db.run(autosaves.create(ifNotExists: true) { t in
            t.column(autosavePostID, primaryKey: true)
            t.column(autosaveTitle)
            t.column(autosaveContent)
            t.column(autosaveSavedAt)
            t.column(autosaveServerModified)
        })

        try db.run(taxonomyCache.create(ifNotExists: true) { t in
            t.column(taxType)
            t.column(taxID)
            t.column(taxName)
            t.column(taxSlug)
            t.column(taxFetchedAt)
            t.primaryKey(taxType, taxID)
        })
    }

    public static func production() throws -> AppDatabase {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WPWriter", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return try AppDatabase(path: dir.appendingPathComponent("drafts.db").path)
    }

    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(path: ":memory:")
    }
}
```

- [ ] **Step 2: Verify compile**

```bash
swift build 2>&1
```
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/WPWriterKit/Storage/Database.swift
git commit -m "feat: SQLite database schema and migrations"
```

---

## Task 6: Draft Store

**Files:**
- Create: `Sources/WPWriterKit/Storage/DraftStore.swift`
- Create: `Tests/WPWriterTests/DraftStoreTests.swift`

- [ ] **Step 1: Write failing test**

`Tests/WPWriterTests/DraftStoreTests.swift`:
```swift
import XCTest
@testable import WPWriterKit

final class DraftStoreTests: XCTestCase {
    var db: AppDatabase!
    var store: DraftStore!

    override func setUp() throws {
        db = try AppDatabase.inMemory()
        store = DraftStore(db: db)
    }

    func testCreateAndFetch() throws {
        let id = try store.create(title: "Test", content: "<p>Hello</p>", excerpt: "")
        let drafts = try store.fetchAll()
        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(drafts[0].id, id)
        XCTAssertEqual(drafts[0].title, "Test")
    }

    func testUpdate() throws {
        let id = try store.create(title: "Original", content: "", excerpt: "")
        try store.update(id: id, title: "Updated", content: "<p>New</p>", excerpt: "Excerpt")
        let drafts = try store.fetchAll()
        XCTAssertEqual(drafts[0].title, "Updated")
        XCTAssertEqual(drafts[0].content, "<p>New</p>")
    }

    func testDelete() throws {
        let id = try store.create(title: "ToDelete", content: "", excerpt: "")
        try store.delete(id: id)
        let drafts = try store.fetchAll()
        XCTAssertTrue(drafts.isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter DraftStoreTests 2>&1 | tail -10
```
Expected: compile error — `DraftStore` not defined.

- [ ] **Step 3: Write `Sources/WPWriterKit/Storage/DraftStore.swift`**

```swift
import Foundation
import SQLite

public struct LocalDraft: Identifiable, Sendable {
    public let id: Int64
    public var title: String
    public var content: String
    public var excerpt: String
    public var createdAt: Date
    public var updatedAt: Date
}

public final class DraftStore: @unchecked Sendable {
    private let db: AppDatabase

    public init(db: AppDatabase) {
        self.db = db
    }

    @discardableResult
    public func create(title: String, content: String, excerpt: String) throws -> Int64 {
        let now = Date().timeIntervalSince1970
        return try db.db.run(db.drafts.insert(
            db.draftTitle <- title,
            db.draftContent <- content,
            db.draftExcerpt <- excerpt,
            db.draftCreatedAt <- now,
            db.draftUpdatedAt <- now
        ))
    }

    public func fetchAll() throws -> [LocalDraft] {
        try db.db.prepare(db.drafts.order(db.draftUpdatedAt.desc)).map { row in
            LocalDraft(
                id: row[db.draftID],
                title: row[db.draftTitle],
                content: row[db.draftContent],
                excerpt: row[db.draftExcerpt],
                createdAt: Date(timeIntervalSince1970: row[db.draftCreatedAt]),
                updatedAt: Date(timeIntervalSince1970: row[db.draftUpdatedAt])
            )
        }
    }

    public func update(id: Int64, title: String, content: String, excerpt: String) throws {
        let row = db.drafts.filter(db.draftID == id)
        try db.db.run(row.update(
            db.draftTitle <- title,
            db.draftContent <- content,
            db.draftExcerpt <- excerpt,
            db.draftUpdatedAt <- Date().timeIntervalSince1970
        ))
    }

    public func delete(id: Int64) throws {
        try db.db.run(db.drafts.filter(db.draftID == id).delete())
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter DraftStoreTests 2>&1 | tail -10
```
Expected: `Test Suite 'DraftStoreTests' passed`

- [ ] **Step 5: Commit**

```bash
git add Sources/WPWriterKit/Storage/DraftStore.swift Tests/WPWriterTests/DraftStoreTests.swift
git commit -m "feat: local draft store (SQLite CRUD)"
```

---

## Task 7: Autosave Store

**Files:**
- Create: `Sources/WPWriterKit/Storage/AutosaveStore.swift`
- Create: `Tests/WPWriterTests/AutosaveStoreTests.swift`

- [ ] **Step 1: Write failing test**

`Tests/WPWriterTests/AutosaveStoreTests.swift`:
```swift
import XCTest
@testable import WPWriterKit

final class AutosaveStoreTests: XCTestCase {
    var db: AppDatabase!
    var store: AutosaveStore!

    override func setUp() throws {
        db = try AppDatabase.inMemory()
        store = AutosaveStore(db: db)
    }

    func testSaveAndLoad() throws {
        try store.save(postID: 42, title: "Post", content: "<p>Hi</p>", serverModified: "2024-01-01T00:00:00")
        let snap = try store.load(postID: 42)
        XCTAssertNotNil(snap)
        XCTAssertEqual(snap?.title, "Post")
        XCTAssertEqual(snap?.serverModified, "2024-01-01T00:00:00")
    }

    func testLoadReturnsNilForUnknownPost() throws {
        let snap = try store.load(postID: 999)
        XCTAssertNil(snap)
    }

    func testSaveOverwritesExisting() throws {
        try store.save(postID: 1, title: "Old", content: "old", serverModified: "2024-01-01T00:00:00")
        try store.save(postID: 1, title: "New", content: "new", serverModified: "2024-01-02T00:00:00")
        let snap = try store.load(postID: 1)
        XCTAssertEqual(snap?.title, "New")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter AutosaveStoreTests 2>&1 | tail -10
```
Expected: compile error — `AutosaveStore` not defined.

- [ ] **Step 3: Write `Sources/WPWriterKit/Storage/AutosaveStore.swift`**

```swift
import Foundation
import SQLite

public struct AutosaveSnapshot: Sendable {
    public let postID: Int
    public var title: String
    public var content: String
    public var savedAt: Date
    public var serverModified: String
}

public final class AutosaveStore: @unchecked Sendable {
    private let db: AppDatabase

    public init(db: AppDatabase) {
        self.db = db
    }

    public func save(postID: Int, title: String, content: String, serverModified: String) throws {
        try db.db.run(db.autosaves.insert(or: .replace,
            db.autosavePostID <- postID,
            db.autosaveTitle <- title,
            db.autosaveContent <- content,
            db.autosaveSavedAt <- Date().timeIntervalSince1970,
            db.autosaveServerModified <- serverModified
        ))
    }

    public func load(postID: Int) throws -> AutosaveSnapshot? {
        let query = db.autosaves.filter(db.autosavePostID == postID)
        guard let row = try db.db.pluck(query) else { return nil }
        return AutosaveSnapshot(
            postID: row[db.autosavePostID],
            title: row[db.autosaveTitle],
            content: row[db.autosaveContent],
            savedAt: Date(timeIntervalSince1970: row[db.autosaveSavedAt]),
            serverModified: row[db.autosaveServerModified]
        )
    }

    public func delete(postID: Int) throws {
        try db.db.run(db.autosaves.filter(db.autosavePostID == postID).delete())
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter AutosaveStoreTests 2>&1 | tail -10
```
Expected: `Test Suite 'AutosaveStoreTests' passed`

- [ ] **Step 5: Commit**

```bash
git add Sources/WPWriterKit/Storage/AutosaveStore.swift Tests/WPWriterTests/AutosaveStoreTests.swift
git commit -m "feat: autosave store (upsert per WP post ID)"
```

---

## Task 8: Taxonomy Cache

**Files:**
- Create: `Sources/WPWriterKit/Storage/TaxonomyCache.swift`
- Create: `Tests/WPWriterTests/TaxonomyCacheTests.swift`

- [ ] **Step 1: Write failing test**

`Tests/WPWriterTests/TaxonomyCacheTests.swift`:
```swift
import XCTest
@testable import WPWriterKit

final class TaxonomyCacheTests: XCTestCase {
    var db: AppDatabase!
    var cache: TaxonomyCache!

    override func setUp() throws {
        db = try AppDatabase.inMemory()
        cache = TaxonomyCache(db: db)
    }

    func testSaveAndLoadCategories() throws {
        let cats = [
            WPCategory(id: 1, name: "Tech", slug: "tech", count: 5, parent: 0),
            WPCategory(id: 2, name: "News", slug: "news", count: 3, parent: 0),
        ]
        try cache.saveCategories(cats)
        let loaded = try cache.loadCategories()
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].name, "Tech")
    }

    func testStaleAfterTTL() throws {
        let staleDate = Date().addingTimeInterval(-25 * 3600)  // 25 hours ago
        let cats = [WPCategory(id: 1, name: "Old", slug: "old", count: 0, parent: 0)]
        try cache.saveCategories(cats, fetchedAt: staleDate)
        XCTAssertTrue(try cache.isCategoryStale())
    }

    func testFreshWithinTTL() throws {
        let cats = [WPCategory(id: 1, name: "Fresh", slug: "fresh", count: 0, parent: 0)]
        try cache.saveCategories(cats)
        XCTAssertFalse(try cache.isCategoryStale())
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter TaxonomyCacheTests 2>&1 | tail -10
```
Expected: compile error — `TaxonomyCache` not defined.

- [ ] **Step 3: Write `Sources/WPWriterKit/Storage/TaxonomyCache.swift`**

```swift
import Foundation
import SQLite

public final class TaxonomyCache: @unchecked Sendable {
    private let db: AppDatabase
    private let ttl: TimeInterval = 24 * 3600   // 24 hours

    public init(db: AppDatabase) {
        self.db = db
    }

    public func saveCategories(_ categories: [WPCategory], fetchedAt: Date = .init()) throws {
        try db.db.run(db.taxonomyCache.filter(db.taxType == "category").delete())
        for cat in categories {
            try db.db.run(db.taxonomyCache.insert(or: .replace,
                db.taxType <- "category",
                db.taxID <- cat.id,
                db.taxName <- cat.name,
                db.taxSlug <- cat.slug,
                db.taxFetchedAt <- fetchedAt.timeIntervalSince1970
            ))
        }
    }

    public func loadCategories() throws -> [WPCategory] {
        try db.db.prepare(db.taxonomyCache.filter(db.taxType == "category").order(db.taxName)).map { row in
            WPCategory(id: row[db.taxID], name: row[db.taxName], slug: row[db.taxSlug], count: 0, parent: 0)
        }
    }

    public func isCategoryStale() throws -> Bool {
        guard let row = try db.db.pluck(db.taxonomyCache.filter(db.taxType == "category")) else { return true }
        return Date().timeIntervalSince1970 - row[db.taxFetchedAt] > ttl
    }

    public func saveTags(_ tags: [WPTag], fetchedAt: Date = .init()) throws {
        try db.db.run(db.taxonomyCache.filter(db.taxType == "tag").delete())
        for tag in tags {
            try db.db.run(db.taxonomyCache.insert(or: .replace,
                db.taxType <- "tag",
                db.taxID <- tag.id,
                db.taxName <- tag.name,
                db.taxSlug <- tag.slug,
                db.taxFetchedAt <- fetchedAt.timeIntervalSince1970
            ))
        }
    }

    public func loadTags() throws -> [WPTag] {
        try db.db.prepare(db.taxonomyCache.filter(db.taxType == "tag").order(db.taxName)).map { row in
            WPTag(id: row[db.taxID], name: row[db.taxName], slug: row[db.taxSlug], count: 0)
        }
    }

    public func isTagStale() throws -> Bool {
        guard let row = try db.db.pluck(db.taxonomyCache.filter(db.taxType == "tag")) else { return true }
        return Date().timeIntervalSince1970 - row[db.taxFetchedAt] > ttl
    }
}
```

- [ ] **Step 4: Run all tests**

```bash
swift test 2>&1 | tail -15
```
Expected: all test suites pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/WPWriterKit/Storage/TaxonomyCache.swift Tests/WPWriterTests/TaxonomyCacheTests.swift
git commit -m "feat: taxonomy cache with 24-hour TTL"
```

---

## Task 9: AppState

**Files:**
- Modify: `Sources/WPWriterKit/App/AppState.swift`

- [ ] **Step 1: Write `Sources/WPWriterKit/App/AppState.swift`**

```swift
import Foundation
import Observation

public enum SidebarSection: String, Hashable, CaseIterable {
    case posts = "Posts"
    case pages = "Pages"
    case localDrafts = "Local Drafts"
    case media = "Media"
}

public enum PostItem: Identifiable, Hashable {
    case remote(WPPost)
    case local(LocalDraft)

    public var id: String {
        switch self {
        case .remote(let p): return "remote-\(p.id)"
        case .local(let d): return "local-\(d.id)"
        }
    }

    public var title: String {
        switch self {
        case .remote(let p): return p.title.rendered.isEmpty ? "Untitled" : p.title.rendered
        case .local(let d): return d.title.isEmpty ? "Untitled" : d.title
        }
    }

    public var statusBadge: String {
        switch self {
        case .remote(let p): return p.status
        case .local: return "local"
        }
    }
}

@Observable
public final class AppState {
    public var selectedSection: SidebarSection = .posts
    public var selectedItem: PostItem?
    public var searchText: String = ""
    public var isSettingsPanelOpen: Bool = false
    public var credentials: Credentials?
    public var isShowingPreferences: Bool = false

    public var posts: [WPPost] = []
    public var pages: [WPPost] = []
    public var localDrafts: [LocalDraft] = []
    public var categories: [WPCategory] = []
    public var tags: [WPTag] = []

    public var isLoadingList: Bool = false
    public var listError: String?

    public init() {}

    public var filteredItems: [PostItem] {
        let items: [PostItem]
        switch selectedSection {
        case .posts:   items = posts.map { .remote($0) }
        case .pages:   items = pages.map { .remote($0) }
        case .localDrafts: items = localDrafts.map { .local($0) }
        case .media:   return []
        }
        guard !searchText.isEmpty else { return items }
        return items.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }
}
```

- [ ] **Step 2: Verify compile**

```bash
swift build 2>&1
```
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/WPWriterKit/App/AppState.swift
git commit -m "feat: observable AppState with section/item selection and filtered list"
```

---

## Task 10: Preferences Window

**Files:**
- Create: `Sources/WPWriterKit/Views/Settings/PreferencesView.swift`
- Modify: `Sources/WPWriterKit/App/WPWriterApp.swift`

- [ ] **Step 1: Write `Sources/WPWriterKit/Views/Settings/PreferencesView.swift`**

```swift
import SwiftUI

public struct PreferencesView: View {
    @State private var siteURL: String = ""
    @State private var username: String = ""
    @State private var appPassword: String = ""
    @State private var isSaving: Bool = false
    @State private var saveError: String?
    @State private var saveSuccess: Bool = false

    var onSave: (Credentials) -> Void

    public init(onSave: @escaping (Credentials) -> Void) {
        self.onSave = onSave
    }

    public var body: some View {
        Form {
            Section("WordPress Site") {
                TextField("Site URL", text: $siteURL, prompt: Text("https://yoursite.com"))
                    .textFieldStyle(.roundedBorder)
            }
            Section("Application Password") {
                TextField("Username", text: $username)
                    .textFieldStyle(.roundedBorder)
                SecureField("Application Password", text: $appPassword, prompt: Text("xxxx xxxx xxxx xxxx xxxx xxxx"))
                    .textFieldStyle(.roundedBorder)
                Text("Generate one in WordPress Admin → Users → Profile → Application Passwords.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let error = saveError {
                Text(error).foregroundStyle(.red).font(.caption)
            }
            if saveSuccess {
                Text("Saved successfully.").foregroundStyle(.green).font(.caption)
            }
            HStack {
                Spacer()
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaving || siteURL.isEmpty || username.isEmpty || appPassword.isEmpty)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .padding()
        .onAppear(perform: loadExisting)
    }

    private func loadExisting() {
        guard let creds = try? KeychainStore.load() else { return }
        siteURL = creds.siteURL.absoluteString
        username = creds.username
        appPassword = creds.appPassword
    }

    private func save() {
        saveError = nil
        saveSuccess = false
        guard let url = URL(string: siteURL), url.scheme != nil else {
            saveError = "Invalid URL. Include https://"
            return
        }
        isSaving = true
        let creds = Credentials(siteURL: url, username: username, appPassword: appPassword)
        do {
            try KeychainStore.save(creds)
            onSave(creds)
            saveSuccess = true
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
    }
}
```

- [ ] **Step 2: Update `Sources/WPWriterKit/App/WPWriterApp.swift` to add Settings scene**

```swift
import SwiftUI

public struct WPWriterApp: App {
    @State private var appState = AppState()

    public init() {}

    public var body: some Scene {
        WindowGroup("WPWriter") {
            ContentView()
                .environment(appState)
                .onAppear {
                    appState.credentials = try? KeychainStore.load()
                    if appState.credentials == nil {
                        appState.isShowingPreferences = true
                    }
                }
                .sheet(isPresented: $appState.isShowingPreferences) {
                    PreferencesView { creds in
                        appState.credentials = creds
                        appState.isShowingPreferences = false
                    }
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            PreferencesView { creds in
                appState.credentials = creds
            }
            .environment(appState)
        }
    }
}
```

- [ ] **Step 3: Verify compile**

```bash
swift build 2>&1
```
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Sources/WPWriterKit/Views/Settings/PreferencesView.swift Sources/WPWriterKit/App/WPWriterApp.swift
git commit -m "feat: preferences window with Keychain credential save/load"
```

---

## Task 11: Sidebar & Content List

**Files:**
- Create: `Sources/WPWriterKit/Views/Sidebar/PostListRow.swift`
- Create: `Sources/WPWriterKit/Views/Sidebar/SidebarView.swift`
- Modify: `Sources/WPWriterKit/Views/ContentView.swift`

- [ ] **Step 1: Write `Sources/WPWriterKit/Views/Sidebar/PostListRow.swift`**

```swift
import SwiftUI

public struct PostListRow: View {
    let item: PostItem

    public init(item: PostItem) {
        self.item = item
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.title)
                .font(.body)
                .lineLimit(2)
            HStack(spacing: 6) {
                StatusBadge(status: item.statusBadge)
                if case .remote(let post) = item {
                    Text(formattedDate(post.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func formattedDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate]
        guard let date = formatter.date(from: iso) else { return iso }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

struct StatusBadge: View {
    let status: String

    var body: some View {
        Text(status)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    var color: Color {
        switch status {
        case "publish": return .green
        case "draft": return .orange
        case "future": return .blue
        case "local": return .purple
        default: return .secondary
        }
    }
}
```

- [ ] **Step 2: Write `Sources/WPWriterKit/Views/Sidebar/SidebarView.swift`**

```swift
import SwiftUI

public struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @State private var isLoading = false

    public init() {}

    public var body: some View {
        @Bindable var state = appState
        VStack(spacing: 0) {
            Picker("Section", selection: $state.selectedSection) {
                ForEach(SidebarSection.allCases, id: \.self) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            if appState.selectedSection != .media {
                SearchField(text: $state.searchText)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)

                List(appState.filteredItems, selection: $state.selectedItem) { item in
                    PostListRow(item: item)
                        .tag(item)
                }
                .listStyle(.sidebar)

                Divider()
                HStack {
                    Spacer()
                    Button {
                        createNewDraft()
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .buttonStyle(.plain)
                    .help("New Local Draft")
                    .padding(8)
                }
            } else {
                Text("Media")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 220)
        .task(id: appState.selectedSection) {
            await loadCurrentSection()
        }
    }

    private func createNewDraft() {
        // Implemented in Task 17 when AppServices is wired up
    }

    private func loadCurrentSection() async {
        // Implemented in Task 17
    }
}

struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search", text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(.quinary)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
```

- [ ] **Step 3: Update `Sources/WPWriterKit/Views/ContentView.swift`**

```swift
import SwiftUI

public struct ContentView: View {
    @Environment(AppState.self) private var appState

    public init() {}

    public var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            if appState.selectedSection == .media {
                MediaPickerView(mode: .browser)
            } else if let item = appState.selectedItem {
                PostEditorView(item: item)
            } else {
                EmptyEditorPlaceholder()
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 900, minHeight: 600)
    }
}

struct EmptyEditorPlaceholder: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)
            Text("Select a post or create a new draft")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 4: Add stub `PostEditorView` and `MediaPickerView` so it compiles**

`Sources/WPWriterKit/Views/Editor/PostEditorView.swift` (stub):
```swift
import SwiftUI

public struct PostEditorView: View {
    let item: PostItem

    public init(item: PostItem) {
        self.item = item
    }

    public var body: some View {
        Text("Editor: \(item.title)")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

`Sources/WPWriterKit/Views/Media/MediaPickerView.swift` (stub):
```swift
import SwiftUI

public enum MediaPickerMode { case browser, picker }

public struct MediaPickerView: View {
    let mode: MediaPickerMode

    public init(mode: MediaPickerMode) {
        self.mode = mode
    }

    public var body: some View {
        Text("Media Library")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 5: Verify compile**

```bash
swift build 2>&1
```
Expected: `Build complete!`

- [ ] **Step 6: Commit**

```bash
git add Sources/WPWriterKit/Views/
git commit -m "feat: two-column NavigationSplitView, sidebar with section picker and post list"
```

---

## Task 12: Tiptap Editor HTML

**Files:**
- Create: `Sources/WPWriterKit/Resources/editor.html`

Tiptap is loaded at runtime from the `esm.sh` CDN inside the WKWebView — no npm or download step needed. Internet is required for the editor to load, which is acceptable since the app requires internet for WordPress anyway.

- [ ] **Step 1: Create Resources directory**

```bash
mkdir -p Sources/WPWriterKit/Resources
```

- [ ] **Step 2: Write `Sources/WPWriterKit/Resources/editor.html`**

```html
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background: #ffffff;
      color: #1a1a1a;
      height: 100vh;
      display: flex;
      flex-direction: column;
      overflow: hidden;
    }
    body.dark { background: #1c1c1e; color: #f0f0f0; }

    /* ── Toolbar ─────────────────────────────────────── */
    #toolbar {
      display: flex;
      align-items: center;
      flex-wrap: wrap;
      gap: 2px;
      padding: 5px 10px;
      border-bottom: 1px solid #e0e0e0;
      background: inherit;
      flex-shrink: 0;
    }
    body.dark #toolbar { border-color: #3a3a3a; }

    #toolbar button, #toolbar select {
      font-family: inherit;
      font-size: 13px;
      border: 1px solid transparent;
      border-radius: 4px;
      padding: 3px 7px;
      cursor: pointer;
      background: transparent;
      color: inherit;
      transition: background 0.1s;
    }
    #toolbar button:hover { background: rgba(0,0,0,0.07); }
    body.dark #toolbar button:hover { background: rgba(255,255,255,0.1); }
    #toolbar button.active {
      background: rgba(0,122,255,0.12);
      color: #007aff;
      border-color: rgba(0,122,255,0.3);
    }
    #toolbar button:disabled { opacity: 0.35; cursor: default; }

    #heading-select {
      padding: 3px 5px;
      border-radius: 4px;
      border: 1px solid #ccc;
      background: transparent;
      color: inherit;
      font-size: 13px;
    }
    body.dark #heading-select { border-color: #555; }

    .tb-sep {
      width: 1px;
      height: 18px;
      background: #d0d0d0;
      margin: 0 4px;
      flex-shrink: 0;
    }
    body.dark .tb-sep { background: #444; }

    /* ── Editor area ─────────────────────────────────── */
    #editor-wrap {
      flex: 1;
      overflow-y: auto;
      padding: 32px 24px;
    }

    .ProseMirror {
      max-width: 720px;
      margin: 0 auto;
      min-height: 100%;
      outline: none;
      font-size: 16px;
      line-height: 1.75;
      caret-color: #007aff;
    }
    .ProseMirror p { margin: 0 0 0.8em; }
    .ProseMirror h1 { font-size: 2em;   font-weight: 700; margin: 1em 0 0.4em; }
    .ProseMirror h2 { font-size: 1.5em; font-weight: 600; margin: 0.9em 0 0.35em; }
    .ProseMirror h3 { font-size: 1.25em;font-weight: 600; margin: 0.8em 0 0.3em; }
    .ProseMirror blockquote {
      border-left: 3px solid #ccc;
      margin: 0.8em 0;
      padding-left: 1em;
      color: #666;
      font-style: italic;
    }
    body.dark .ProseMirror blockquote { border-color: #555; color: #aaa; }
    .ProseMirror code {
      background: rgba(0,0,0,0.07);
      border-radius: 3px;
      padding: 1px 4px;
      font-family: "SF Mono", monospace;
      font-size: 0.88em;
    }
    body.dark .ProseMirror code { background: rgba(255,255,255,0.1); }
    .ProseMirror pre {
      background: #f5f5f5;
      border-radius: 6px;
      padding: 12px 16px;
      overflow-x: auto;
      margin: 0.8em 0;
    }
    body.dark .ProseMirror pre { background: #2a2a2a; }
    .ProseMirror pre code { background: none; padding: 0; }
    .ProseMirror ul, .ProseMirror ol { padding-left: 1.5em; margin: 0.5em 0; }
    .ProseMirror li { margin: 0.2em 0; }
    .ProseMirror img { max-width: 100%; border-radius: 4px; }

    /* Task list */
    .ProseMirror ul[data-type="taskList"] { list-style: none; padding-left: 0.5em; }
    .ProseMirror ul[data-type="taskList"] li {
      display: flex; align-items: flex-start; gap: 8px;
    }
    .ProseMirror ul[data-type="taskList"] li > label { margin-top: 2px; }
    .ProseMirror ul[data-type="taskList"] li[data-checked="true"] > div {
      text-decoration: line-through; color: #888;
    }

    /* Tables */
    .ProseMirror table {
      border-collapse: collapse;
      width: 100%;
      margin: 1em 0;
    }
    .ProseMirror th, .ProseMirror td {
      border: 1px solid #ccc;
      padding: 6px 10px;
      text-align: left;
      vertical-align: top;
      min-width: 60px;
    }
    body.dark .ProseMirror th,
    body.dark .ProseMirror td { border-color: #555; }
    .ProseMirror th { background: #f5f5f5; font-weight: 600; }
    body.dark .ProseMirror th { background: #2a2a2a; }
    .ProseMirror .selectedCell { background: rgba(0,122,255,0.08); }

    /* Placeholder */
    .ProseMirror p.is-editor-empty:first-child::before {
      content: attr(data-placeholder);
      color: #aaa;
      pointer-events: none;
      float: left;
      height: 0;
    }
  </style>
</head>
<body>
  <div id="toolbar">
    <select id="heading-select" title="Heading">
      <option value="0">Paragraph</option>
      <option value="1">Heading 1</option>
      <option value="2">Heading 2</option>
      <option value="3">Heading 3</option>
    </select>
    <span class="tb-sep"></span>
    <button data-cmd="bold"      title="Bold (⌘B)"><b>B</b></button>
    <button data-cmd="italic"    title="Italic (⌘I)"><i>I</i></button>
    <button data-cmd="underline" title="Underline (⌘U)"><u>U</u></button>
    <button data-cmd="strike"    title="Strikethrough"><s>S</s></button>
    <button data-cmd="code"      title="Inline code" style="font-family:monospace">`</button>
    <span class="tb-sep"></span>
    <button data-cmd="blockquote" title="Blockquote">&ldquo;</button>
    <button data-cmd="codeBlock"  title="Code block" style="font-family:monospace">{}</button>
    <span class="tb-sep"></span>
    <button data-cmd="bulletList"  title="Bullet list">&#8226; List</button>
    <button data-cmd="orderedList" title="Ordered list">1. List</button>
    <button data-cmd="taskList"    title="Task list">&#9745; Tasks</button>
    <span class="tb-sep"></span>
    <button data-cmd="insertTable" title="Insert 3×3 table">&#8862; Table</button>
    <span id="table-controls" style="display:none">
      <button data-cmd="addRowAfter"    title="Add row below">+Row</button>
      <button data-cmd="addColumnAfter" title="Add column right">+Col</button>
      <button data-cmd="deleteRow"      title="Delete row">&minus;Row</button>
      <button data-cmd="deleteColumn"   title="Delete column">&minus;Col</button>
      <button data-cmd="deleteTable"    title="Delete table">&#10005; Table</button>
    </span>
    <span class="tb-sep"></span>
    <button data-cmd="link"  title="Insert / remove link">&#128279; Link</button>
    <button data-cmd="image" title="Insert image from media library">&#128444; Image</button>
    <span class="tb-sep"></span>
    <button data-cmd="undo" title="Undo (⌘Z)">&#8617; Undo</button>
    <button data-cmd="redo" title="Redo (⌘⇧Z)">&#8618; Redo</button>
  </div>
  <div id="editor-wrap"><div id="editor"></div></div>

  <script type="module">
    import { Editor }   from 'https://esm.sh/@tiptap/core@2'
    import StarterKit   from 'https://esm.sh/@tiptap/starter-kit@2'
    import Underline    from 'https://esm.sh/@tiptap/extension-underline@2'
    import Table        from 'https://esm.sh/@tiptap/extension-table@2'
    import TableRow     from 'https://esm.sh/@tiptap/extension-table-row@2'
    import TableCell    from 'https://esm.sh/@tiptap/extension-table-cell@2'
    import TableHeader  from 'https://esm.sh/@tiptap/extension-table-header@2'
    import Image        from 'https://esm.sh/@tiptap/extension-image@2'
    import Link         from 'https://esm.sh/@tiptap/extension-link@2'
    import TaskList     from 'https://esm.sh/@tiptap/extension-task-list@2'
    import TaskItem     from 'https://esm.sh/@tiptap/extension-task-item@2'
    import Placeholder  from 'https://esm.sh/@tiptap/extension-placeholder@2'

    const editor = new Editor({
      element: document.getElementById('editor'),
      extensions: [
        StarterKit,
        Underline,
        Table.configure({ resizable: false }),
        TableRow,
        TableHeader,
        TableCell,
        Image.configure({ inline: false }),
        Link.configure({ openOnClick: false }),
        TaskList,
        TaskItem.configure({ nested: true }),
        Placeholder.configure({ placeholder: 'Start writing…' }),
      ],
      content: '',
      onTransaction: () => updateToolbar(),
      onCreate: () => {
        updateToolbar()
        if (window.webkit?.messageHandlers?.editorReady) {
          window.webkit.messageHandlers.editorReady.postMessage('ready')
        }
      },
    })

    // ── Toolbar commands ───────────────────────────────
    const COMMANDS = {
      bold:          () => editor.chain().focus().toggleBold().run(),
      italic:        () => editor.chain().focus().toggleItalic().run(),
      underline:     () => editor.chain().focus().toggleUnderline().run(),
      strike:        () => editor.chain().focus().toggleStrike().run(),
      code:          () => editor.chain().focus().toggleCode().run(),
      blockquote:    () => editor.chain().focus().toggleBlockquote().run(),
      codeBlock:     () => editor.chain().focus().toggleCodeBlock().run(),
      bulletList:    () => editor.chain().focus().toggleBulletList().run(),
      orderedList:   () => editor.chain().focus().toggleOrderedList().run(),
      taskList:      () => editor.chain().focus().toggleTaskList().run(),
      insertTable:   () => editor.chain().focus().insertTable({ rows: 3, cols: 3, withHeaderRow: true }).run(),
      addRowAfter:   () => editor.chain().focus().addRowAfter().run(),
      addColumnAfter:() => editor.chain().focus().addColumnAfter().run(),
      deleteRow:     () => editor.chain().focus().deleteRow().run(),
      deleteColumn:  () => editor.chain().focus().deleteColumn().run(),
      deleteTable:   () => editor.chain().focus().deleteTable().run(),
      undo:          () => editor.chain().focus().undo().run(),
      redo:          () => editor.chain().focus().redo().run(),
      link: () => {
        const prev = editor.getAttributes('link').href || ''
        const url  = prompt('URL (leave empty to remove):', prev)
        if (url === null) return
        if (url === '') { editor.chain().focus().unsetLink().run() }
        else { editor.chain().focus().setLink({ href: url }).run() }
      },
      image: () => {
        if (window.webkit?.messageHandlers?.insertImageAtIndex) {
          window.webkit.messageHandlers.insertImageAtIndex.postMessage(0)
        }
      },
    }

    document.querySelectorAll('[data-cmd]').forEach(btn => {
      btn.addEventListener('mousedown', e => {
        e.preventDefault()  // prevent focus loss before command runs
        COMMANDS[btn.dataset.cmd]?.()
      })
    })

    document.getElementById('heading-select').addEventListener('change', e => {
      const level = parseInt(e.target.value)
      if (level === 0) editor.chain().focus().setParagraph().run()
      else editor.chain().focus().toggleHeading({ level }).run()
    })

    // ── Active-state updates ───────────────────────────
    const TOGGLE_CMDS = ['bold','italic','underline','strike','code',
                         'blockquote','codeBlock','bulletList','orderedList','taskList','link']

    function updateToolbar() {
      TOGGLE_CMDS.forEach(cmd => {
        const btn = document.querySelector(`[data-cmd="${cmd}"]`)
        if (btn) btn.classList.toggle('active', editor.isActive(cmd))
      })
      // Heading select
      const sel = document.getElementById('heading-select')
      sel.value = '0'
      for (let i = 1; i <= 3; i++) {
        if (editor.isActive('heading', { level: i })) { sel.value = String(i); break }
      }
      // Table controls
      const inTable = editor.isActive('table')
      document.getElementById('table-controls').style.display = inTable ? 'contents' : 'none'
      // Undo / Redo
      document.querySelector('[data-cmd="undo"]').disabled = !editor.can().undo()
      document.querySelector('[data-cmd="redo"]').disabled = !editor.can().redo()
    }

    // ── Content change → Swift ─────────────────────────
    let debounce
    editor.on('update', () => {
      clearTimeout(debounce)
      debounce = setTimeout(() => {
        if (window.webkit?.messageHandlers?.contentChanged) {
          window.webkit.messageHandlers.contentChanged.postMessage(editor.getHTML())
        }
      }, 500)
    })

    // ── Swift → JS bridge (globals) ───────────────────
    window.setContent = html => {
      editor.commands.setContent(html || '', false)
    }
    window.getContent = () => editor.getHTML()
    window.setDarkMode = dark => document.body.classList.toggle('dark', dark)
    window.focusEditor = () => editor.commands.focus()
    window.insertImageAt = (_index, url) => {
      editor.chain().focus().setImage({ src: url }).run()
    }
  </script>
</body>
</html>
```

- [ ] **Step 3: Verify compile**

```bash
swift build 2>&1
```
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Sources/WPWriterKit/Resources/editor.html
git commit -m "feat: Tiptap 2.x editor with tables, task lists, dark mode and Swift bridge"
```

---

## Task 13: EditorView & Coordinator

**Files:**
- Create: `Sources/WPWriterKit/Views/Editor/EditorCoordinator.swift`
- Create: `Sources/WPWriterKit/Views/Editor/EditorView.swift`

- [ ] **Step 1: Write `Sources/WPWriterKit/Views/Editor/EditorCoordinator.swift`**

```swift
import WebKit

public final class EditorCoordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    var isReady: Bool = false
    var pendingHTML: String?
    var onContentChange: (String) -> Void
    var onReady: () -> Void
    weak var webView: WKWebView?

    var onInsertImageAt: ((Int) -> Void)?

    init(onContentChange: @escaping (String) -> Void, onReady: @escaping () -> Void) {
        self.onContentChange = onContentChange
        self.onReady = onReady
    }

    // WKScriptMessageHandler
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "contentChanged":
            if let html = message.body as? String {
                DispatchQueue.main.async { self.onContentChange(html) }
            }
        case "editorReady":
            DispatchQueue.main.async {
                self.isReady = true
                if let html = self.pendingHTML {
                    self.setContent(html)
                    self.pendingHTML = nil
                }
                self.onReady()
            }
        case "insertImageAtIndex":
            if let index = message.body as? Int {
                DispatchQueue.main.async { self.onInsertImageAt?(index) }
            }
        default:
            break
        }
    }

    func insertImage(url: String, at index: Int) {
        guard let wv = webView else { return }
        let escaped = url.replacingOccurrences(of: "\"", with: "\\\"")
        wv.evaluateJavaScript("insertImageAt(\(index), \"\(escaped)\")", completionHandler: nil)
    }

    // WKNavigationDelegate
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        applyColorScheme()
    }

    func setContent(_ html: String) {
        guard let wv = webView else { return }
        if isReady {
            let escaped = html
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "`", with: "\\`")
            wv.evaluateJavaScript("setContent(`\(escaped)`)", completionHandler: nil)
        } else {
            pendingHTML = html
        }
    }

    func applyColorScheme() {
        guard let wv = webView else { return }
        let isDark = wv.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        wv.evaluateJavaScript("setDarkMode(\(isDark))", completionHandler: nil)
    }
}
```

- [ ] **Step 2: Write `Sources/WPWriterKit/Views/Editor/EditorView.swift`**

```swift
import SwiftUI
import WebKit

public struct EditorView: NSViewRepresentable {
    @Binding var html: String
    var onContentChange: (String) -> Void
    var onInsertImageAt: ((Int) -> Void)?

    public init(html: Binding<String>, onContentChange: @escaping (String) -> Void, onInsertImageAt: ((Int) -> Void)? = nil) {
        self._html = html
        self.onContentChange = onContentChange
        self.onInsertImageAt = onInsertImageAt
    }

    public func makeCoordinator() -> EditorCoordinator {
        EditorCoordinator(onContentChange: onContentChange, onReady: {})
    }

    public func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "contentChanged")
        config.userContentController.add(context.coordinator, name: "editorReady")
        config.userContentController.add(context.coordinator, name: "insertImageAtIndex")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.onInsertImageAt = onInsertImageAt
        loadEditorHTML(in: webView)
        return webView
    }

    public func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.setContent(html)
    }

    private func loadEditorHTML(in webView: WKWebView) {
        guard let htmlURL = Bundle.main.url(forResource: "editor", withExtension: "html") else {
            return
        }
        let resourceDir = htmlURL.deletingLastPathComponent()
        webView.loadFileURL(htmlURL, allowingReadAccessTo: resourceDir)
    }
}
```

- [ ] **Step 3: Add notification name to `Sources/WPWriterKit/Views/Editor/EditorCoordinator.swift`**

Append after the `EditorCoordinator` class:

```swift
extension Notification.Name {
    static let insertMediaURL = Notification.Name("WPWriter.insertMediaURL")
}
```

Also add an observer in `EditorCoordinator.init` and a handler:

```swift
    init(onContentChange: @escaping (String) -> Void, onReady: @escaping () -> Void) {
        self.onContentChange = onContentChange
        self.onReady = onReady
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInsertMedia(_:)),
            name: .insertMediaURL,
            object: nil
        )
    }

    @objc private func handleInsertMedia(_ note: Notification) {
        guard let url = note.userInfo?["url"] as? String,
              let index = note.userInfo?["index"] as? Int else { return }
        insertImage(url: url, at: index)
    }
```

- [ ] **Step 4: Verify compile**

```bash
swift build 2>&1
```
Expected: `Build complete!`

- [ ] **Step 5: Commit**

```bash
git add Sources/WPWriterKit/Views/Editor/EditorCoordinator.swift Sources/WPWriterKit/Views/Editor/EditorView.swift
git commit -m "feat: WKWebView Quill editor with Swift JS bridge and image insertion"
```

---

## Task 14: Post Settings Panel

**Files:**
- Create: `Sources/WPWriterKit/Views/Settings/PostSettingsPanel.swift`

- [ ] **Step 1: Write `Sources/WPWriterKit/Views/Settings/PostSettingsPanel.swift`**

```swift
import SwiftUI

public struct PostSettings: Equatable {
    public var status: String = "draft"
    public var publishDate: Date? = nil
    public var categoryIDs: Set<Int> = []
    public var tagIDs: Set<Int> = []
    public var featuredMediaID: Int = 0
    public var excerpt: String = ""

    public init() {}
}

public struct PostSettingsPanel: View {
    @Binding var settings: PostSettings
    let categories: [WPCategory]
    let tags: [WPTag]

    public init(settings: Binding<PostSettings>, categories: [WPCategory], tags: [WPTag]) {
        self._settings = settings
        self.categories = categories
        self.tags = tags
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                statusSection
                publishDateSection
                categoriesSection
                tagsSection
                excerptSection
            }
            .padding(16)
        }
        .frame(width: 260)
        .background(.windowBackground)
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Status", systemImage: "circle.fill")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Picker("Status", selection: $settings.status) {
                Text("Draft").tag("draft")
                Text("Published").tag("publish")
                Text("Scheduled").tag("future")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var publishDateSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Publish Date", systemImage: "calendar")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Toggle("Schedule", isOn: Binding(
                get: { settings.publishDate != nil },
                set: { settings.publishDate = $0 ? Date().addingTimeInterval(3600) : nil }
            ))
            .toggleStyle(.switch)
            if let date = Binding($settings.publishDate) {
                DatePicker("", selection: date, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
            }
        }
    }

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Categories", systemImage: "folder")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            if categories.isEmpty {
                Text("No categories").font(.caption).foregroundStyle(.tertiary)
            } else {
                ForEach(categories) { cat in
                    Toggle(cat.name, isOn: Binding(
                        get: { settings.categoryIDs.contains(cat.id) },
                        set: { checked in
                            if checked { settings.categoryIDs.insert(cat.id) }
                            else { settings.categoryIDs.remove(cat.id) }
                        }
                    ))
                    .toggleStyle(.checkbox)
                }
            }
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Tags", systemImage: "tag")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            if tags.isEmpty {
                Text("No tags").font(.caption).foregroundStyle(.tertiary)
            } else {
                ForEach(tags) { tag in
                    Toggle(tag.name, isOn: Binding(
                        get: { settings.tagIDs.contains(tag.id) },
                        set: { checked in
                            if checked { settings.tagIDs.insert(tag.id) }
                            else { settings.tagIDs.remove(tag.id) }
                        }
                    ))
                    .toggleStyle(.checkbox)
                }
            }
        }
    }

    private var excerptSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Excerpt", systemImage: "text.alignleft")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            TextEditor(text: $settings.excerpt)
                .frame(height: 70)
                .font(.body)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(.separator, lineWidth: 1)
                )
        }
    }
}
```

- [ ] **Step 2: Verify compile**

```bash
swift build 2>&1
```
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/WPWriterKit/Views/Settings/PostSettingsPanel.swift
git commit -m "feat: post settings panel (status, date, categories, tags, excerpt)"
```

---

## Task 15: Post Editor View (Toolbar + Autosave)

**Files:**
- Modify: `Sources/WPWriterKit/Views/Editor/PostEditorView.swift`

- [ ] **Step 1: Rewrite `Sources/WPWriterKit/Views/Editor/PostEditorView.swift`**

```swift
import SwiftUI

public struct PostEditorView: View {
    @Environment(AppState.self) private var appState
    let item: PostItem

    @State private var title: String = ""
    @State private var htmlContent: String = ""
    @State private var settings = PostSettings()
    @State private var isSettingsOpen: Bool = false
    @State private var isSaving: Bool = false
    @State private var saveError: String?
    @State private var conflictAlert: ConflictInfo?
    @State private var autosaveTask: Task<Void, Never>?
    @State private var lastSavedServerModified: String = ""
    @State private var imageInsertIndex: Int? = nil   // non-nil → media picker sheet open

    public init(item: PostItem) {
        self.item = item
    }

    public var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                toolbar
                Divider()
                titleField
                Divider()
                EditorView(
                    html: $htmlContent,
                    onContentChange: { newHTML in
                        htmlContent = newHTML
                        scheduleAutosave()
                    },
                    onInsertImageAt: { index in
                        imageInsertIndex = index
                    }
                )
                .sheet(isPresented: Binding(
                    get: { imageInsertIndex != nil },
                    set: { if !$0 { imageInsertIndex = nil } }
                )) {
                    if let idx = imageInsertIndex {
                        MediaPickerView(mode: .picker) { selected in
                            // find WKWebView coordinator and insert image
                            NotificationCenter.default.post(
                                name: .insertMediaURL,
                                object: nil,
                                userInfo: ["url": selected.sourceURL, "index": idx]
                            )
                            imageInsertIndex = nil
                        }
                        .environment(appState)
                        .frame(minWidth: 600, minHeight: 400)
                    }
                }
            }

            if isSettingsOpen {
                Divider()
                PostSettingsPanel(
                    settings: $settings,
                    categories: appState.categories,
                    tags: appState.tags
                )
                .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isSettingsOpen)
        .alert("Conflict Detected", isPresented: Binding(
            get: { conflictAlert != nil },
            set: { if !$0 { conflictAlert = nil } }
        )) {
            if let info = conflictAlert {
                Button("Keep Local") { saveToWordPress(force: true) }
                Button("Use Server") { loadFromServer(postID: info.postID) }
                Button("Cancel", role: .cancel) {}
            }
        } message: {
            Text("This post was modified on the server since you last fetched it.")
        }
        .task(id: item.id) { await loadItem() }
        .onDisappear { autosaveTask?.cancel() }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            if let error = saveError {
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(.red)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
            Spacer()
            Button("Save Draft") { Task { await saveDraft() } }
                .disabled(isSaving)
            Button("Preview") { Task { await openPreview() } }
                .disabled(isSaving || !isRemote)
            Button(publishButtonTitle) { Task { await publish() } }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving)
            Divider().frame(height: 20)
            Button {
                withAnimation { isSettingsOpen.toggle() }
            } label: {
                Image(systemName: "sidebar.right")
            }
            .help("Post Settings")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var titleField: some View {
        TextField("Title", text: $title)
            .font(.system(size: 22, weight: .semibold))
            .textFieldStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .onChange(of: title) { scheduleAutosave() }
    }

    private var publishButtonTitle: String {
        switch item {
        case .remote(let p): return p.status == "publish" ? "Update" : "Publish"
        case .local: return "Publish"
        }
    }

    private var isRemote: Bool {
        if case .remote = item { return true }
        return false
    }

    // MARK: - Load

    private func loadItem() async {
        switch item {
        case .remote(let post):
            title = post.title.rendered
            htmlContent = post.content.raw ?? post.content.rendered
            lastSavedServerModified = post.modified
            settings.status = post.status
            settings.categoryIDs = Set(post.categories)
            settings.tagIDs = Set(post.tags)
            settings.featuredMediaID = post.featuredMedia
        case .local(let draft):
            title = draft.title
            htmlContent = draft.content
            settings.excerpt = draft.excerpt
        }
    }

    // MARK: - Autosave

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task {
            try? await Task.sleep(for: .seconds(30))
            if !Task.isCancelled { await performAutosave() }
        }
    }

    private func performAutosave() async {
        guard let db = try? AppDatabase.production() else { return }
        switch item {
        case .remote(let post):
            let store = AutosaveStore(db: db)
            try? store.save(postID: post.id, title: title, content: htmlContent, serverModified: lastSavedServerModified)
        case .local(let draft):
            let store = DraftStore(db: db)
            try? store.update(id: draft.id, title: title, content: htmlContent, excerpt: settings.excerpt)
        }
    }

    // MARK: - Save / Publish

    private func saveDraft() async {
        await save(status: "draft")
    }

    private func publish() async {
        await save(status: settings.status == "future" ? "future" : "publish")
    }

    private func save(status: String, force: Bool = false) async {
        guard let creds = appState.credentials else { return }
        isSaving = true
        saveError = nil
        defer { isSaving = false }

        let client = WordPressClient(credentials: creds)
        let payload = PostPayload(
            title: title,
            content: htmlContent,
            excerpt: settings.excerpt,
            status: status,
            date: settings.publishDate.map { ISO8601DateFormatter().string(from: $0) },
            featuredMedia: settings.featuredMediaID > 0 ? settings.featuredMediaID : nil,
            categories: Array(settings.categoryIDs),
            tags: Array(settings.tagIDs)
        )

        do {
            switch item {
            case .remote(let post):
                if !force {
                    let current = try await client.fetchPost(id: post.id)
                    if current.modified != lastSavedServerModified {
                        conflictAlert = ConflictInfo(postID: post.id)
                        return
                    }
                }
                let updated = try await client.updatePost(id: post.id, payload: payload)
                lastSavedServerModified = updated.modified
            case .local(let draft):
                let created = try await client.createPost(payload)
                let db = try AppDatabase.production()
                try DraftStore(db: db).delete(id: draft.id)
                lastSavedServerModified = created.modified
            }
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func saveToWordPress(force: Bool) {
        Task { await save(status: settings.status, force: true) }
    }

    private func loadFromServer(postID: Int) {
        Task {
            guard let creds = appState.credentials else { return }
            let client = WordPressClient(credentials: creds)
            if let post = try? await client.fetchPost(id: postID) {
                title = post.title.rendered
                htmlContent = post.content.raw ?? post.content.rendered
                lastSavedServerModified = post.modified
            }
        }
    }

    private func openPreview() async {
        guard let creds = appState.credentials,
              case .remote(let post) = item else { return }
        let client = WordPressClient(credentials: creds)
        let payload = PostPayload(title: title, content: htmlContent, excerpt: settings.excerpt, status: post.status)
        if let autosave = try? await client.createAutosave(postID: post.id, payload: payload),
           let url = URL(string: autosave.link + "?preview=true") {
            NSWorkspace.shared.open(url)
        }
    }
}

private struct ConflictInfo {
    let postID: Int
}
```

- [ ] **Step 2: Verify compile**

```bash
swift build 2>&1
```
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/WPWriterKit/Views/Editor/PostEditorView.swift
git commit -m "feat: post editor with toolbar, autosave, conflict detection, publish/update"
```

---

## Task 16: Media Picker

**Files:**
- Modify: `Sources/WPWriterKit/Views/Media/MediaPickerView.swift`

- [ ] **Step 1: Rewrite `Sources/WPWriterKit/Views/Media/MediaPickerView.swift`**

```swift
import SwiftUI

public struct MediaPickerView: View {
    let mode: MediaPickerMode
    var onSelect: ((WPMedia) -> Void)?

    @Environment(AppState.self) private var appState
    @State private var mediaItems: [WPMedia] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var isUploading = false

    public init(mode: MediaPickerMode, onSelect: ((WPMedia) -> Void)? = nil) {
        self.mode = mode
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if isLoading {
                ProgressView("Loading media…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                VStack(spacing: 8) {
                    Text(error).foregroundStyle(.secondary)
                    Button("Retry") { Task { await loadMedia() } }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if mediaItems.isEmpty {
                Text("No media uploaded yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                mediaGrid
            }
        }
        .task { await loadMedia() }
    }

    private var toolbar: some View {
        HStack {
            Text("Media Library")
                .font(.headline)
            Spacer()
            Button("Upload…") { uploadFromDisk() }
                .disabled(isUploading)
            if isUploading {
                ProgressView().scaleEffect(0.7)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var mediaGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 8) {
                ForEach(mediaItems.filter { $0.mediaType == "image" }) { media in
                    MediaThumbnail(media: media)
                        .onTapGesture {
                            if let handler = onSelect { handler(media) }
                        }
                }
            }
            .padding(12)
        }
    }

    private func loadMedia() async {
        guard let creds = appState.credentials else { return }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            mediaItems = try await WordPressClient(credentials: creds).fetchMedia()
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func uploadFromDisk() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .pdf, .movie]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let creds = appState.credentials else { return }
        isUploading = true
        Task {
            defer { isUploading = false }
            do {
                let data = try Data(contentsOf: url)
                let mime = mimeType(for: url)
                let uploaded = try await WordPressClient(credentials: creds)
                    .uploadMedia(data: data, filename: url.lastPathComponent, mimeType: mime)
                mediaItems.insert(uploaded, at: 0)
            } catch {
                // silently show nothing — production would surface this
            }
        }
    }

    private func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "pdf": return "application/pdf"
        default: return "application/octet-stream"
        }
    }
}

struct MediaThumbnail: View {
    let media: WPMedia

    var body: some View {
        AsyncImage(url: URL(string: media.sourceURL)) { phase in
            switch phase {
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fill)
            case .failure, .empty:
                Rectangle().fill(.quaternary)
                    .overlay(Image(systemName: "photo").foregroundStyle(.tertiary))
            @unknown default:
                Rectangle().fill(.quaternary)
            }
        }
        .frame(width: 120, height: 90)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6).stroke(.separator, lineWidth: 0.5)
        )
    }
}
```

- [ ] **Step 2: Verify compile**

```bash
swift build 2>&1
```
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/WPWriterKit/Views/Media/MediaPickerView.swift
git commit -m "feat: media picker with grid view and file upload"
```

---

## Task 17: App Service Container & Sidebar Wiring

**Files:**
- Create: `Sources/WPWriterKit/App/AppServices.swift`
- Modify: `Sources/WPWriterKit/Views/Sidebar/SidebarView.swift`
- Modify: `Sources/WPWriterKit/App/WPWriterApp.swift`

- [ ] **Step 1: Write `Sources/WPWriterKit/App/AppServices.swift`**

```swift
import Foundation

@Observable
public final class AppServices {
    public let database: AppDatabase
    public let draftStore: DraftStore
    public let autosaveStore: AutosaveStore
    public let taxonomyCache: TaxonomyCache

    public init() {
        let db = (try? AppDatabase.production()) ?? (try! AppDatabase.inMemory())
        self.database = db
        self.draftStore = DraftStore(db: db)
        self.autosaveStore = AutosaveStore(db: db)
        self.taxonomyCache = TaxonomyCache(db: db)
    }
}
```

- [ ] **Step 2: Update `Sources/WPWriterKit/Views/Sidebar/SidebarView.swift` to load real data**

Replace the stub `createNewDraft()` and `loadCurrentSection()` methods with:

```swift
    // Replace stub implementations with these:

    @Environment(AppServices.self) private var services

    private func createNewDraft() {
        guard let id = try? services.draftStore.create(
            title: "Untitled",
            content: "",
            excerpt: ""
        ) else { return }
        if let updated = try? services.draftStore.fetchAll(),
           let newDraft = updated.first(where: { $0.id == id }) {
            appState.localDrafts = updated
            appState.selectedSection = .localDrafts
            appState.selectedItem = .local(newDraft)
        }
    }

    private func loadCurrentSection() async {
        guard let creds = appState.credentials else { return }
        appState.isLoadingList = true
        defer { appState.isLoadingList = false }

        let client = WordPressClient(credentials: creds)
        do {
            switch appState.selectedSection {
            case .posts:
                appState.posts = try await client.fetchPosts()
            case .pages:
                appState.pages = try await client.fetchPages()
            case .localDrafts:
                appState.localDrafts = (try? services.draftStore.fetchAll()) ?? []
            case .media:
                break
            }
            await loadTaxonomiesIfNeeded(client: client)
        } catch {
            appState.listError = error.localizedDescription
        }
    }

    private func loadTaxonomiesIfNeeded(client: WordPressClient) async {
        if (try? services.taxonomyCache.isCategoryStale()) != false {
            if let cats = try? await client.fetchCategories() {
                try? services.taxonomyCache.saveCategories(cats)
                appState.categories = cats
            }
        } else {
            appState.categories = (try? services.taxonomyCache.loadCategories()) ?? []
        }
        if (try? services.taxonomyCache.isTagStale()) != false {
            if let tags = try? await client.fetchTags() {
                try? services.taxonomyCache.saveTags(tags)
                appState.tags = tags
            }
        } else {
            appState.tags = (try? services.taxonomyCache.loadTags()) ?? []
        }
    }
```

- [ ] **Step 3: Inject `AppServices` in `Sources/WPWriterKit/App/WPWriterApp.swift`**

Add `@State private var appServices = AppServices()` and `.environment(appServices)` to the WindowGroup:

```swift
public struct WPWriterApp: App {
    @State private var appState = AppState()
    @State private var appServices = AppServices()

    public init() {}

    public var body: some Scene {
        WindowGroup("WPWriter") {
            ContentView()
                .environment(appState)
                .environment(appServices)
                .onAppear {
                    appState.credentials = try? KeychainStore.load()
                    if appState.credentials == nil {
                        appState.isShowingPreferences = true
                    }
                }
                .sheet(isPresented: $appState.isShowingPreferences) {
                    PreferencesView { creds in
                        appState.credentials = creds
                        appState.isShowingPreferences = false
                    }
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            PreferencesView { creds in
                appState.credentials = creds
            }
        }
    }
}
```

- [ ] **Step 4: Verify compile**

```bash
swift build 2>&1
```
Expected: `Build complete!`

- [ ] **Step 5: Commit**

```bash
git add Sources/WPWriterKit/App/AppServices.swift Sources/WPWriterKit/Views/Sidebar/SidebarView.swift Sources/WPWriterKit/App/WPWriterApp.swift
git commit -m "feat: app services container, sidebar loads real posts and taxonomies"
```

---

## Task 18: Complete build.sh & App Bundle

**Files:**
- Modify: `build.sh`

- [ ] **Step 1: Run final test suite before packaging**

```bash
swift test 2>&1 | tail -20
```
Expected: all suites pass.

- [ ] **Step 2: Rewrite `build.sh` with full resource copying**

```bash
#!/usr/bin/env bash
set -euo pipefail

APP_NAME="WPWriter"
BUNDLE_ID="com.wpwriter.app"
MIN_MACOS="13.0"

echo "▶ Building $APP_NAME..."
swift build -c release 2>&1

BINARY=".build/release/$APP_NAME"
APP_BUNDLE="$APP_NAME.app"
APP_DIR="$APP_BUNDLE/Contents"
RESOURCES_DIR="$APP_DIR/Resources"

echo "▶ Assembling $APP_BUNDLE..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_DIR/MacOS"
mkdir -p "$RESOURCES_DIR"

# Binary
cp "$BINARY" "$APP_DIR/MacOS/$APP_NAME"
chmod +x "$APP_DIR/MacOS/$APP_NAME"

# Resources
cp "Sources/WPWriterKit/Resources/editor.html" "$RESOURCES_DIR/editor.html"

# Info.plist
cat > "$APP_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppTransportSecurity</key>
  <dict>
    <key>NSAllowsArbitraryLoads</key><true/>
  </dict>
</dict>
</plist>
EOF

echo "✓ Built: $APP_BUNDLE"
echo "  Run with: open $APP_BUNDLE"
echo "  Install:  cp -r $APP_BUNDLE /Applications/"
```

- [ ] **Step 3: Build the .app**

```bash
chmod +x build.sh
./build.sh
```
Expected: `✓ Built: WPWriter.app`

- [ ] **Step 4: Launch the app**

```bash
open WPWriter.app
```
Expected: WPWriter window opens. Preferences sheet appears asking for site URL and credentials.

- [ ] **Step 5: Commit**

```bash
git add build.sh
git commit -m "feat: complete build.sh — assembles WPWriter.app with resources and Info.plist"
```

---

## Task 19: .gitignore & Final Tidy

- [ ] **Step 1: Write `.gitignore`**

```
.build/
*.app/
*.o
*.d
.DS_Store
.swp
```

- [ ] **Step 2: Run full test suite one last time**

```bash
swift test 2>&1 | grep -E "Test Suite|passed|failed"
```
Expected: all suites pass, zero failures.

- [ ] **Step 3: Final commit**

```bash
git add .gitignore
git commit -m "chore: gitignore build artifacts"
```

---

## Summary

After Task 18 completes:

- `./build.sh` → produces `WPWriter.app`
- `open WPWriter.app` → opens the app
- On first launch: Preferences sheet to enter WordPress site URL + Application Password
- Two-column layout: content list (Posts / Pages / Local Drafts / Media) on left, Quill editor on right
- Save Draft / Preview / Publish/Update in toolbar
- Collapsible Post Settings drawer (categories, tags, status, date, excerpt)
- Media library browser with upload
- Conflict detection banner
- All offline drafts and autosaves stored in `~/Library/Application Support/WPWriter/drafts.db`
