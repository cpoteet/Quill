import AppKit
import SwiftUI

struct MediaGalleryThumbnail: View {
    let media: WPMedia
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { content }
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Color.accentColor : Color(nsColor: .separatorColor),
                                lineWidth: isSelected ? 3 : 0.5)
                }
            Text(displayName)
                .font(.caption)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(4)
    }

    private var displayName: String {
        if !media.title.rendered.isEmpty { return media.title.decodedTitle }
        return URL(string: media.sourceURL)?.lastPathComponent ?? ""
    }

    @ViewBuilder
    private var content: some View {
        if media.mediaType == "image" {
            AsyncImage(url: URL(string: media.thumbnailURL)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure, .empty:
                    placeholder(symbol: "photo")
                @unknown default:
                    placeholder(symbol: "photo")
                }
            }
            .clipped()
        } else {
            placeholder(symbol: media.mimeType == "application/pdf" ? "doc.richtext.fill" : "doc.fill")
        }
    }

    private func placeholder(symbol: String) -> some View {
        Rectangle()
            .fill(.quaternary)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: 24))
                    .foregroundStyle(.tertiary)
            }
    }
}

final class MediaGalleryItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("MediaGalleryItem")

    private var media: WPMedia?
    private var host: NSHostingView<MediaGalleryThumbnail>?

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
    }

    override var isSelected: Bool {
        didSet { refresh() }
    }

    func configure(with media: WPMedia) {
        self.media = media
        refresh()
    }

    private func refresh() {
        guard let media else { return }
        let root = MediaGalleryThumbnail(media: media, isSelected: isSelected)
        if let host {
            host.rootView = root
            return
        }
        let newHost = NSHostingView(rootView: root)
        newHost.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(newHost)
        NSLayoutConstraint.activate([
            newHost.topAnchor.constraint(equalTo: view.topAnchor),
            newHost.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            newHost.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            newHost.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        host = newHost
    }
}

final class MediaCollectionView: NSCollectionView {
    var itemAt: ((NSPoint) -> WPMedia?)?
    var onContextMenu: ((WPMedia) -> NSMenu?)?
    var onActivate: ((WPMedia) -> Void)?
    var onSpace: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " ", event.modifierFlags.isDisjoint(with: [.command, .option, .control]) {
            onSpace?()
            return
        }
        super.keyDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        guard let media = itemAt?(point) else { return nil }
        if let indexPath = indexPathForItem(at: point) {
            selectionIndexPaths = [indexPath]
            delegate?.collectionView?(self, didSelectItemsAt: [indexPath])
        }
        return onContextMenu?(media)
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        guard event.clickCount == 2 else { return }
        let point = convert(event.locationInWindow, from: nil)
        if let media = itemAt?(point) { onActivate?(media) }
    }
}

enum MediaContextAction {
    case showDetails
    case copyURL
    case openInBrowser
    case delete
}

final class MediaMenuTarget: NSObject {
    var media: WPMedia?
    var handler: ((MediaContextAction, WPMedia) -> Void)?

    @objc func showDetails() { fire(.showDetails) }
    @objc func copyURL() { fire(.copyURL) }
    @objc func openInBrowser() { fire(.openInBrowser) }
    @objc func delete(_ sender: Any?) { fire(.delete) }

    private func fire(_ action: MediaContextAction) {
        guard let media else { return }
        handler?(action, media)
    }
}

struct MediaGalleryView: NSViewRepresentable {
    let items: [WPMedia]
    @Binding var selection: WPMedia?
    var onNeedMore: () -> Void
    var onActivate: (WPMedia) -> Void
    var onContextAction: (MediaContextAction, WPMedia) -> Void
    var onSpace: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 150, height: 172)
        layout.minimumInteritemSpacing = 10
        layout.minimumLineSpacing = 10
        layout.sectionInset = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

        let collectionView = MediaCollectionView()
        collectionView.collectionViewLayout = layout
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = false
        collectionView.allowsEmptySelection = true
        collectionView.backgroundColors = [.clear]
        collectionView.register(MediaGalleryItem.self,
                                forItemWithIdentifier: MediaGalleryItem.identifier)
        collectionView.dataSource = context.coordinator
        collectionView.delegate = context.coordinator
        collectionView.itemAt = { [weak collectionView] point in
            guard let collectionView,
                  let indexPath = collectionView.indexPathForItem(at: point) else { return nil }
            return context.coordinator.items[safe: indexPath.item]
        }
        collectionView.onActivate = { media in context.coordinator.parent.onActivate(media) }
        collectionView.onSpace = { context.coordinator.parent.onSpace() }
        context.coordinator.menuTarget.handler = { action, media in
            context.coordinator.parent.onContextAction(action, media)
        }
        collectionView.onContextMenu = { [weak coordinator = context.coordinator] media in
            guard let coordinator else { return nil }
            coordinator.menuTarget.media = media
            let menu = NSMenu()
            let detailsItem = NSMenuItem(title: "Show Details",
                                         action: #selector(MediaMenuTarget.showDetails),
                                         keyEquivalent: "")
            detailsItem.target = coordinator.menuTarget
            menu.addItem(detailsItem)
            menu.addItem(.separator())

            let copyItem = NSMenuItem(title: "Copy URL",
                                      action: #selector(MediaMenuTarget.copyURL),
                                      keyEquivalent: "")
            copyItem.target = coordinator.menuTarget
            menu.addItem(copyItem)

            if !media.link.isEmpty, URL(string: media.link) != nil {
                let openItem = NSMenuItem(title: "Open in Browser",
                                          action: #selector(MediaMenuTarget.openInBrowser),
                                          keyEquivalent: "")
                openItem.target = coordinator.menuTarget
                menu.addItem(openItem)
            }

            menu.addItem(.separator())
            let deleteItem = NSMenuItem(title: "Delete\u{2026}",
                                        action: #selector(MediaMenuTarget.delete(_:)),
                                        keyEquivalent: "")
            deleteItem.target = coordinator.menuTarget
            menu.addItem(deleteItem)
            return menu
        }

        let scrollView = NSScrollView()
        scrollView.documentView = collectionView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        context.coordinator.collectionView = collectionView
        context.coordinator.items = items
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.apply(items: items, selection: selection)
    }

    final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
        var parent: MediaGalleryView
        var items: [WPMedia] = []
        let menuTarget = MediaMenuTarget()
        weak var collectionView: MediaCollectionView?
        private var isApplyingSelection = false

        init(_ parent: MediaGalleryView) {
            self.parent = parent
        }

        func apply(items newItems: [WPMedia], selection: WPMedia?) {
            guard let collectionView else { return }
            let oldIDs = items.map(\.id)
            let newIDs = newItems.map(\.id)
            if oldIDs == newIDs {
                items = newItems
            } else if !oldIDs.isEmpty, newIDs.count > oldIDs.count, Array(newIDs.prefix(oldIDs.count)) == oldIDs {
                // Paging appends; inserting keeps the existing cells and their hosted thumbnails.
                let appended = (oldIDs.count..<newIDs.count).map { IndexPath(item: $0, section: 0) }
                items = newItems
                collectionView.animator().insertItems(at: Set(appended))
            } else {
                items = newItems
                collectionView.reloadData()
            }
            isApplyingSelection = true
            defer { isApplyingSelection = false }
            if let selection, let index = items.firstIndex(where: { $0.id == selection.id }) {
                let path = IndexPath(item: index, section: 0)
                if collectionView.selectionIndexPaths != [path] {
                    collectionView.selectionIndexPaths = [path]
                }
            } else if !collectionView.selectionIndexPaths.isEmpty {
                collectionView.deselectAll(nil)
            }
        }

        func collectionView(_ collectionView: NSCollectionView,
                            numberOfItemsInSection section: Int) -> Int {
            items.count
        }

        func collectionView(_ collectionView: NSCollectionView,
                            itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
            let item = collectionView.makeItem(withIdentifier: MediaGalleryItem.identifier,
                                               for: indexPath)
            if let galleryItem = item as? MediaGalleryItem, let media = items[safe: indexPath.item] {
                galleryItem.configure(with: media)
            }
            return item
        }

        // Paging trigger: the last cell coming on screen. Matches MediaPickerView and
        // GallerySheet, whose SwiftUI grids use .onAppear on their last cell.
        func collectionView(_ collectionView: NSCollectionView,
                            willDisplay item: NSCollectionViewItem,
                            forRepresentedObjectAt indexPath: IndexPath) {
            guard indexPath.item >= items.count - 1 else { return }
            parent.onNeedMore()
        }

        func collectionView(_ collectionView: NSCollectionView,
                            didSelectItemsAt indexPaths: Set<IndexPath>) {
            guard !isApplyingSelection, let first = indexPaths.first else { return }
            parent.selection = items[safe: first.item]
        }

        func collectionView(_ collectionView: NSCollectionView,
                            didDeselectItemsAt indexPaths: Set<IndexPath>) {
            guard !isApplyingSelection else { return }
            if collectionView.selectionIndexPaths.isEmpty { parent.selection = nil }
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
