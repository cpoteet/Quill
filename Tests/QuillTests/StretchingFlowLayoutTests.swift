import AppKit
import Testing
@testable import QuillKit

@MainActor @Suite struct StretchingFlowLayoutTests {
    private func layout(inWidth width: CGFloat) -> StretchingFlowLayout {
        let layout = StretchingFlowLayout()
        layout.minimumInteritemSpacing = 10
        layout.sectionInset = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        let collection = NSCollectionView(frame: NSRect(x: 0, y: 0, width: width, height: 400))
        collection.collectionViewLayout = layout
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: 400))
        scroll.hasVerticalScroller = false
        scroll.documentView = collection
        return layout
    }

    @Test func tilesFillTheRowAndKeepTheCaptionStrip() {
        for width in [300, 480, 700, 1024, 1500] as [CGFloat] {
            let layout = layout(inWidth: width)
            let tile = layout.tileSize
            let columns = ((width - 32 + 10) / (140 + 10)).rounded(.down)
            #expect(tile.width >= 140)
            #expect(tile.height == tile.width + 22)
            let used = columns * tile.width + (columns - 1) * 10
            #expect(width - 32 - used >= 0 && width - 32 - used < columns, "width \(width)")
        }
    }

    @Test func aNarrowViewStillGetsOneColumn() {
        let tile = layout(inWidth: 100).tileSize
        #expect(tile.width == 68)
    }

    @Test func withoutAScrollViewTheItemSizeIsUsed() {
        let layout = StretchingFlowLayout()
        layout.itemSize = NSSize(width: 150, height: 172)
        #expect(layout.tileSize == NSSize(width: 150, height: 172))
    }
}
