import AppKit
import Combine
import SwiftUI

/// Opt-in A/B grid for fullscreen vertical browsing and organization.
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
        grid.isSelectable = false
        grid.owner = context.coordinator
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
        let grid = ComparisonGrid()
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
                let item = items[indexPath.item]
                cell.bind(model: model, item: item) { [weak self] in self?.activate(item) }
            }
            return cell
        }
        func activate(_ item: LayoutItem) {
            guard let model, let index = items.firstIndex(where: { $0.id == item.id }) else { return }
            if model.multiSelectionActive, item.kind == .app { model.toggleItemSelection(item); return }
            model.select(index)
            if item.kind == .folder { model.open(item) }
            else if !model.editing, let id = item.appID, let app = model.app(for: id) { launch?(app) }
        }

    }
}

@MainActor private final class ComparisonCell: NSCollectionViewItem {
    private let magnifier = MagnificationIconView()
    private let icon = NSImageView()
    private let drag = ComparisonDragTile()
    private let caption = NSTextField(labelWithString: "")
    private var updates: AnyCancellable?
    override func loadView() {
        view = NSView()
        icon.imageScaling = .scaleProportionallyUpOrDown
        caption.alignment = .center
        caption.lineBreakMode = .byTruncatingTail
        caption.maximumNumberOfLines = 1
        magnifier.wantsLayer = true
        magnifier.layer?.masksToBounds = false
        magnifier.addSubview(icon)
        view.addSubview(magnifier)
        view.addSubview(caption)
        view.addSubview(drag)
    }
    override func prepareForReuse() {
        super.prepareForReuse()
        updates = nil
        icon.image = nil
        drag.click = nil
        drag.resolveIconResources = nil
        magnifier.setScale(1, immediately: true)
    }
    func bind(model: LauncherModel, item: LayoutItem, activate: @escaping () -> Void) {
        _ = view
        updates = nil
        let side = model.displayedIconSize
        let width = model.tileWidth
        let height = side + model.preferences.labelHeight + 18
        magnifier.frame = NSRect(x: (width - side) / 2, y: height - side - 5, width: side, height: side)
        icon.frame = magnifier.bounds
        magnifier.applicationID = item.appID
        magnifier.enabled = model.preferences.magnificationEnabled && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        magnifier.animated = model.preferences.animationsEnabled
        drag.frame = NSRect(x: 0, y: 0, width: width, height: height)
        drag.model = model
        drag.itemID = item.id
        drag.iconSize = side
        drag.click = activate
        drag.resolveIconResources = { [weak model] in
            guard let model else { return (nil, []) }
            return (nil, item.children.prefix(9).compactMap { model.app(for: $0) }.map { model.icon(for: $0) })
        }
        caption.frame = NSRect(x: 2, y: 4, width: max(1, width - 4), height: model.preferences.labelHeight)
        caption.font = .systemFont(ofSize: model.preferences.textPoints(12), weight: .medium)
        caption.stringValue = model.name(for: item)
        caption.isHidden = !model.preferences.showNames
        view.setAccessibilityLabel(caption.stringValue)
        let feedback = model.dragFeedback(for: item.id)
        let apps = (item.appID.map { [$0] } ?? Array(item.children.prefix(9))).compactMap { model.app(for: $0) }
        let refresh: () -> Void = { [weak self, weak model, weak feedback] in
            guard let self, let model else { return }
            let images = apps.map { model.icon(for: $0, notifying: feedback) }
            self.icon.image = item.kind == .folder ? DragSourceView.folderThumbnail(images) : images.first
        }
        refresh()
        updates = feedback.objectWillChange.sink { _ in refresh() }
    }
}

@MainActor private final class ComparisonDragTile: DragSourceView {
    private let payloadType = NSPasteboard.PasteboardType(launcherDragType.identifier)
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([payloadType])
    }
    required init?(coder: NSCoder) { nil }
    private func source(_ sender: NSDraggingInfo) -> String? {
        guard let model, model.canOrganize, let source = model.draggingID, source != itemID,
              sender.draggingPasteboard.pasteboardItems?.contains(where: { $0.string(forType: payloadType) == source }) == true else { return nil }
        return source
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { source(sender) == nil ? [] : .move }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { source(sender) != nil }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let model, let source = source(sender) else { return false }
        let ratio = convert(sender.draggingLocation, from: nil).x / max(bounds.width, 1)
        model.drop(source, onto: itemID, position: ratio < 0.26 ? .before : ratio > 0.74 ? .after : .center)
        return true
    }
}

@MainActor final class ComparisonGrid: NSCollectionView {
    weak var owner: NativeVerticalComparison.Coordinator?
    private func target(at windowPoint: NSPoint) -> (LayoutItem, ItemDropPosition)? {
        let point = convert(windowPoint, from: nil)
        guard let owner, let path = indexPathForItem(at: point), owner.items.indices.contains(path.item),
              let frame = layoutAttributesForItem(at: path)?.frame else { return nil }
        let ratio = (point.x - frame.minX) / max(frame.width, 1)
        return (owner.items[path.item], ratio < 0.26 ? .before : ratio > 0.74 ? .after : .center)
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let (item, _) = target(at: event.locationInWindow), let model = owner?.model else { return nil }
        let menu = NSMenu()
        func add(_ title: String, to destination: NSMenu? = nil, action: @escaping () -> Void) {
            (destination ?? menu).addItem(ComparisonMenuItem(title: model.text(title), action: action))
        }
        let app = item.appID.flatMap { model.app(for: $0) }
        if let app { add("在访达中显示") { NSWorkspace.shared.activateFileViewerSelecting([app.url]) } }
        if model.preferences.automaticCategories {
            add("分类与排列设置") { model.openSettings() }
        } else if item.kind == .folder {
            add("重命名") { model.beginRename(item) }
            add("解散文件夹") { model.dissolve(item.id) }
        } else if let id = item.appID {
            add("新建文件夹") { model.createFolder(containing: id) }
            if !model.layout.folders.isEmpty {
                let entry = NSMenuItem(title: model.text("移入文件夹"), action: nil, keyEquivalent: "")
                let folders = NSMenu()
                for folder in model.layout.folders {
                    folders.addItem(ComparisonMenuItem(title: model.name(for: folder)) { model.moveApp(id, toFolder: folder.id) })
                }
                entry.submenu = folders
                menu.addItem(entry)
            }
        }
        if let app {
            menu.addItem(.separator())
            add("隐藏应用") { model.setAppHidden(app.id, hidden: true) }
            add("应用速览") { model.inspectingApp = app }
            add("显示包内容") { NSWorkspace.shared.open(app.url.appendingPathComponent("Contents", isDirectory: true)) }
            add("拷贝路径") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(app.url.path, forType: .string) }
            add("在终端中打开所在目录") {
                NSWorkspace.shared.open([app.url.deletingLastPathComponent()], withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"), configuration: NSWorkspace.OpenConfiguration())
            }
            if !app.isSystemApplication, app.bundleIdentifier != AppCatalog.ownBundleIdentifier {
                add("移至废纸篓…") { model.onTrashApplication?(app) }
            }
        }
        return menu
    }
}

@MainActor private final class ComparisonMenuItem: NSMenuItem {
    let handler: () -> Void
    init(title: String, action: @escaping () -> Void) {
        handler = action
        super.init(title: title, action: #selector(invoke), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError("Programmatic menu item") }
    @objc private func invoke() { handler() }
}
