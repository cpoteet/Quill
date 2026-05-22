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
