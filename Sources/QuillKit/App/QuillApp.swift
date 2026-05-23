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
