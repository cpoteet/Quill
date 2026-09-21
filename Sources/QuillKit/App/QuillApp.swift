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
            CommandGroup(after: .pasteboard) {
                Button("Paste as Markdown") {
                    appState.triggerPasteMarkdown = true
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])
                Button("Find…") {
                    appState.triggerFindBar = true
                }
                .keyboardShortcut("f", modifiers: .command)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    appState.triggerSave = true
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(appState.selectedItem == nil || appState.editorIsSaving)

                Button(appState.editorPublishTitle) {
                    appState.triggerPublish = true
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(appState.selectedItem == nil || appState.editorIsSaving)

                Divider()

                Button("Revert to Saved\u{2026}") {
                    appState.triggerRevert = true
                }
                .disabled(!appState.editorIsDirty || appState.selectedItem?.isRemote != true)

                Button("Preview in Browser") {
                    appState.triggerPreview = true
                }
                .disabled(appState.selectedItem?.isRemote != true || appState.editorIsSaving)
            }
            CommandGroup(after: .toolbar) {
                Button("Refresh") {
                    appState.triggerRefresh = true
                }
                .keyboardShortcut("r", modifiers: .command)
            }
            CommandGroup(replacing: .help) {
                Button("User Guide") {
                    NSWorkspace.shared.open(URL(string: "https://quill.siolon.com/docs.html")!)
                }
                Button("Changelog") {
                    NSWorkspace.shared.open(URL(string: "https://quill.siolon.com/changelog.html")!)
                }
            }
            CommandGroup(replacing: .newItem) {
                Button("New Post") {
                    appState.createNewDraft(type: "post", draftStore: appServices.draftStore)
                }
                .keyboardShortcut("n", modifiers: .command)
                Button("New Page") {
                    appState.createNewDraft(type: "page", draftStore: appServices.draftStore)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                Divider()
                Button("New Media") {
                    appState.selectedSection = .media
                    appState.triggerMediaUpload = true
                }
                .keyboardShortcut("n", modifiers: [.command, .option])
            }
        }

        Settings {
            PreferencesView(posts: appState.posts, credentials: appState.credentials, onSave: { creds in
                appState.credentials = creds
            }, onSaveAISettings: { settings in
                appState.aiSettings = settings
            })
        }
    }
}
