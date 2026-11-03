import AppKit
import Combine
import SwiftUI

/// Opt-in A/B grid. Editing and search continue to use the full launcher grid.
struct NativeVerticalComparison: NSViewRepresentable {
    @ObservedObject var model: LauncherModel
    let launch: (InstalledApp) -> Void
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let grid = context.coordinator.grid
        grid.collectionViewLayout = context.coordinator.layout
        grid.backgroundColors = [.clear]
        grid.dataSource = context.coordinator
        grid.delegate = context.coordinator
        grid.isSelectable = true
        grid.autoresizingMask = [.width]
        grid.register(ComparisonCell.self, forItemWithIdentifier: Coordinator.reuse)
        scroll.documentView = grid
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let c = context.coordinator
        c.model = model
        c.launch = launch
        let items = model.containerItems
        let size = NSSize(width: model.tileWidth, height: model.displayedIconSize + model.preferences.labelHeight + 18)
        let padding = max(0, (model.pageWidth - model.gridWidth) / 2)
        let inset = NSEdgeInsets(top: 4, left: padding, bottom: 4, right: padding)
        let changed = c.items != items || c.apps != model.apps || c.preferences != model.preferences || c.layout.itemSize != size
        if changed {
            c.items = items
            c.apps = model.apps
            c.preferences = model.preferences
            c.layout.itemSize = size
            c.layout.sectionInset = inset
            c.layout.minimumInteritemSpacing = LauncherGeometry.gridSpacing
            c.layout.minimumLineSpacing = LauncherGeometry.gridSpacing
            c.grid.reloadData()
        }
        let selected = model.selectedIndex
        if c.selected != selected {
            c.selected = selected
            if model.keyboardSelectionActive, items.indices.contains(selected) {
                c.grid.scrollToItems(at: [IndexPath(item: selected, section: 0)], scrollPosition: .nearestVerticalEdge)
            }
        }
    }

    @MainActor final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
        static let reuse = NSUserInterfaceItemIdentifier("AploComparisonCell")
        let grid = NSCollectionView()
        let layout = NSCollectionViewFlowLayout()
        weak var model: LauncherModel?
        var launch: ((InstalledApp) -> Void)?
        var items: [LayoutItem] = []
        var apps: [InstalledApp] = []
        var preferences: LauncherPreferences?
        var selected = -1
        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { items.count }
        func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
            let cell = collectionView.makeItem(withIdentifier: Self.reuse, for: indexPath)
            if let model, let cell = cell as? ComparisonCell, items.indices.contains(indexPath.item) {
                cell.bind(model: model, item: items[indexPath.item])
            }
            return cell
        }
        func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
            guard let index = indexPaths.first?.item, items.indices.contains(index), let model else { return }
            collectionView.deselectItems(at: indexPaths)
            let item = items[index]
            model.select(index)
            if item.kind == .folder { model.open(item) }
            else if let id = item.appID, let app = model.app(for: id) { launch?(app) }
        }
    }
}

@MainActor private final class ComparisonCell: NSCollectionViewItem {
    private let icon = NSImageView()
    private let caption = NSTextField(labelWithString: "")
    private var updates: AnyCancellable?
    override func loadView() {
        view = NSView()
        icon.imageScaling = .scaleProportionallyUpOrDown
        caption.alignment = .center
        caption.lineBreakMode = .byTruncatingTail
        caption.maximumNumberOfLines = 1
        view.addSubview(icon)
        view.addSubview(caption)
    }
    override func prepareForReuse() {
        super.prepareForReuse()
        updates = nil
        icon.image = nil
    }
    func bind(model: LauncherModel, item: LayoutItem) {
        _ = view
        updates = nil
        let side = model.displayedIconSize
        let width = model.tileWidth
        let height = side + model.preferences.labelHeight + 18
        icon.frame = NSRect(x: (width - side) / 2, y: height - side - 5, width: side, height: side)
        caption.frame = NSRect(x: 2, y: 4, width: max(1, width - 4), height: model.preferences.labelHeight)
        caption.font = .systemFont(ofSize: model.preferences.textPoints(12), weight: .medium)
        caption.stringValue = model.name(for: item)
        caption.isHidden = !model.preferences.showNames
        view.setAccessibilityLabel(caption.stringValue)
        if let id = item.appID, let app = model.app(for: id) {
            let feedback = model.dragFeedback(for: item.id)
            icon.image = model.icon(for: app, notifying: feedback)
            updates = feedback.objectWillChange.sink { [weak self, weak model] _ in
                self?.icon.image = model?.icon(for: app)
            }
        } else {
            icon.image = NSImage(systemSymbolName: "square.grid.3x3.fill", accessibilityDescription: nil)
        }
    }
}
