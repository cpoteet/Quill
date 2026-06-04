import SwiftUI

public struct QuillApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var appServices = AppServices()

    private static var aboutWindow: NSWindow?

    public init() {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    static func showAboutWindow() {
        if aboutWindow == nil {
            let hosting = NSHostingController(rootView: AboutView())
            let window = NSWindow(contentViewController: hosting)
            window.title = "About Quill"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            aboutWindow = window
        }
        aboutWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public var body: some Scene {
        WindowGroup("Quill") {
            ContentView()
                .environmentObject(appState)
                .environmentObject(appServices)
                .tint(Color.wpAmber)
                .onAppear {
                    appState.credentials = try? KeychainStore.load()
                    if appState.credentials == nil {
                        appState.isShowingPreferences = true
                    }
                }
                .sheet(isPresented: $appState.isShowingPreferences) {
                    PreferencesView(posts: appState.posts, onSave: { creds in
                        appState.credentials = creds
                        appState.isShowingPreferences = false
                    }, onSaveAISettings: { settings in
                        appState.aiSettings = settings
                    })
                }
                .alert("Local Storage Unavailable", isPresented: $appServices.storageUnavailable) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("Quill couldn't open its local database, so drafts and autosaves won't be saved and will be lost when you quit. Check available disk space and the permissions on your Application Support folder.")
                }
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Quill") {
                    QuillApp.showAboutWindow()
                }
            }
            CommandGroup(replacing: .newItem) {
                Button("New Post") {
                    appState.createNewDraft(type: "post", draftStore: appServices.draftStore)
                }
                Button("New Page") {
                    appState.createNewDraft(type: "page", draftStore: appServices.draftStore)
                }
                Divider()
                Button("New Media…") {
                    appState.selectedSection = .media
                    appState.triggerMediaUpload = true
                }
            }
        }

        Settings {
            PreferencesView(posts: appState.posts, onSave: { creds in
                appState.credentials = creds
            }, onSaveAISettings: { settings in
                appState.aiSettings = settings
            })
        }
    }
}
