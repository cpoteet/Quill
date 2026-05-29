import SwiftUI

public struct QuillApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var appServices = AppServices()

    public init() {}

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
            CommandGroup(replacing: .newItem) {}
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
