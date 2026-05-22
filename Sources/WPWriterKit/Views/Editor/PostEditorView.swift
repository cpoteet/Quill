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
