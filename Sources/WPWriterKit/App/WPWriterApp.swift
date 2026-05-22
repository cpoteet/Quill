import SwiftUI

public struct WPWriterApp: App {
    @StateObject private var appState = AppState()

    public init() {}

    public var body: some Scene {
        WindowGroup("WPWriter") {
            ContentView()
                .environmentObject(appState)
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
            .environmentObject(appState)
        }
    }
}
