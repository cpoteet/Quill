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
