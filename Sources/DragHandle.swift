import AppKit
import SwiftUI

// Native destinations keep the drag payload valid even if SwiftUI rebuilds a page.
struct NativePageDropTarget: NSViewRepresentable {
    let model: LauncherModel
    let page: Int
    func makeNSView(context: Context) -> PageDropView { PageDropView() }
    func updateNSView(_ view: PageDropView, context: Context) {
        view.model = model
        view.page = page
    }
}

final class PageDropView: NSView {
    weak var model: LauncherModel?
    var page = 0
    private let payloadType = NSPasteboard.PasteboardType(launcherDragType.identifier)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([payloadType])
    }
    required init?(coder: NSCoder) { nil }
    override func mouseUp(with event: NSEvent) { model?.goToPage(page) }
    private func source(_ sender: NSDraggingInfo) -> String? {
        guard model?.canOrganize == true,
              let value = sender.draggingPasteboard.string(forType: payloadType),
              value.utf8.count < 4096 else { return nil }
        return value
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard source(sender) != nil else { return [] }
        model?.dropHint = "松开移至第 \(page + 1) 页"
        return .move
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { model?.dropHint = nil }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { source(sender) != nil }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let source = source(sender), let model else { return false }
        model.drop(source, toPage: page)
        return true
    }
}

struct NativeDragHandle: NSViewRepresentable {
    let model: LauncherModel
    let item: LayoutItem
    let click: () -> Void
    func makeNSView(context: Context) -> DragSourceView { DragSourceView() }
    func updateNSView(_ view: DragSourceView, context: Context) {
        view.model = model
        view.iconSize = min(model.preferences.iconPoints(fullscreen: model.isFullscreen), max(24, model.tileWidth - 18))
        view.itemID = item.id
        view.click = click
        view.resolveIconResources = { [weak model] in
            guard let model else { return (nil, []) }
            if let appID = item.appID, let app = model.app(for: appID) {
                return (model.icon(for: app), [])
            }
            return (nil, item.children.prefix(9).compactMap { model.app(for: $0) }.map { model.icon(for: $0) })
        }
    }
}

class DragSourceView: NSView, NSDraggingSource {
    weak var model: LauncherModel?
    var itemID = ""
    var icon: NSImage?
    var folderImages: [NSImage] = []
    var resolveIconResources: (() -> (NSImage?, [NSImage]))?
    func refreshIconResources() {
        guard let resolveIconResources else { return }
        (icon, folderImages) = resolveIconResources()
    }
    var iconSize: CGFloat = 50
    var click: (() -> Void)?
    private var start: NSPoint?
    private var didDrag = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        if let type = NSApp.currentEvent?.type, type == .rightMouseDown || type == .rightMouseUp { return nil }
        return super.hitTest(point)
    }
    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        didDrag = false
    }
    override func mouseDragged(with event: NSEvent) {
        guard !didDrag, let start, let model, model.canBeginIconDrag else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - start.x, point.y - start.y) >= 3 else { return }
        didDrag = true
        model.beginInteractiveDrag(itemID)
        // Read the latest asynchronous result at drag start; the hit-test overlay
        // may still hold a placeholder from its previous SwiftUI update.
        refreshIconResources()
        let items = model.dragItems(startingAt: itemID)
        let draggingItems = items.enumerated().map { index, item -> NSDraggingItem in
            let pasteboard = NSPasteboardItem()
            pasteboard.setString(item.id, forType: NSPasteboard.PasteboardType(launcherDragType.identifier))
            let app = item.appID.flatMap { model.app(for: $0) }
            if let app { pasteboard.setString(app.url.absoluteString, forType: .fileURL) }
            let draggingItem = NSDraggingItem(pasteboardWriter: pasteboard)
            let offset = CGFloat(min(index, 4)) * 5
            let frame = NSRect(x: point.x - iconSize / 2 + offset, y: point.y - iconSize / 2 - offset, width: iconSize, height: iconSize)
            draggingItem.setDraggingFrame(frame, contents: app.map { model.icon(for: $0) } ?? icon ?? Self.folderThumbnail(folderImages))
            return draggingItem
        }
        guard !draggingItems.isEmpty else { model.endDrag(); return }
        beginDraggingSession(with: draggingItems, event: event, source: self)
    }

    static func folderThumbnail(_ images: [NSImage]) -> NSImage {
        NSImage(size: NSSize(width: 384, height: 384), flipped: false) { rect in
            NSColor(white: 0.72, alpha: 0.35).setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), xRadius: 64, yRadius: 64).fill()
            NSGraphicsContext.current?.imageInterpolation = .high
            for (index, image) in images.enumerated() {
                let x = 38 + CGFloat(index % 3) * 106
                let y = 258 - CGFloat(index / 3) * 106
                image.draw(in: NSRect(x: x, y: y, width: 88, height: 88), from: .zero, operation: .sourceOver, fraction: 1)
            }
            return true
        }
    }
    override func mouseUp(with event: NSEvent) {
        if !didDrag { click?() }
        start = nil
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        if context == .withinApplication { return .move }
        guard let model, model.dragItems(startingAt: itemID).allSatisfy({ $0.kind == .app }) else { return [] }
        return .copy
    }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        if CommandLine.arguments.contains("--diagnostics") {
            FileHandle.standardError.write(Data(("[Aplo] drag ended operation=\(operation.rawValue)\n").utf8))
        }
        let model = model
        DispatchQueue.main.async { model?.endDrag() }
        start = nil
        didDrag = false
    }
}
