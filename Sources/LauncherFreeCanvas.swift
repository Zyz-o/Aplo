import AppKit
import SwiftUI

struct FreeCanvasEntry: Identifiable, Equatable {
    let item: LayoutItem
    let index: Int
    let origin: CGPoint
    var id: String { item.id }
}
/// AppKit scroll bounds notifications also work when SwiftUI does not re-evaluate geometry during native scrolling.
private final class CanvasScrollObservation: @unchecked Sendable {
    let token: NSObjectProtocol
    init(_ token: NSObjectProtocol) { self.token = token }
    deinit { NotificationCenter.default.removeObserver(token) }
}
struct CanvasViewportMonitor: NSViewRepresentable {
    let tileSize: CGSize
    let revealRect: CGRect?
    let revealGeneration: Int
    let changed: (CGRect) -> Void
    func makeNSView(context: Context) -> CanvasViewportView { CanvasViewportView() }
    func updateNSView(_ view: CanvasViewportView, context: Context) {
        view.changed = changed; view.tileSize = tileSize
        if view.revealGeneration != revealGeneration {
            view.revealGeneration = revealGeneration
            if let revealRect { DispatchQueue.main.async { [weak view] in _ = view?.scrollToVisible(revealRect.insetBy(dx: -8, dy: -8)) } }
        }
    }
}
final class CanvasViewportView: NSView {
    var revealGeneration = -1
    var tileSize = CGSize(width: 100, height: 100)
    private var gate = CanvasViewportGate()
    var changed: ((CGRect) -> Void)?
    private weak var clip: NSClipView?
    private var observation: CanvasScrollObservation?
    private var scheduled = false
    private var latest = CGRect.zero
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { observation = nil; clip = nil; gate = CanvasViewportGate() }
        else { DispatchQueue.main.async { [weak self] in self?.attach() } }
    }
    override func layout() { super.layout(); attach(); sample() }
    private func attach() {
        guard window != nil, let scroll = enclosingScrollView else { return }
        if clip !== scroll.contentView {
            observation = nil; clip = scroll.contentView
            scroll.contentView.postsBoundsChangedNotifications = true
            let token = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
                object: scroll.contentView, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.sample() }
            }
            observation = CanvasScrollObservation(token)
        }
        sample()
    }
    private func sample() {
        guard let clip else { return }
        latest = convert(clip.bounds, from: clip)
        guard !scheduled else { return }
        scheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.scheduled = false
            if self.window != nil, self.gate.shouldPublish(self.latest, tile: self.tileSize) { self.changed?(self.latest) }
        }
    }
}

struct CulledFreeCanvas<Content: View>: View {
    let entries: [FreeCanvasEntry]
    let canvas: CGSize
    let viewport: CGSize
    let tileSize: CGSize
    let draggedID: String?
    let selectedID: String?
    let revealGeneration: Int
    let begin: (String) -> Void
    let end: () -> Void
    let save: (String, FreeIconPosition) -> Void
    @ViewBuilder let content: (FreeCanvasEntry) -> Content
    @State private var visibleViewport: CGRect?
    var body: some View {
        let visible = visibleViewport?.insetBy(dx: -tileSize.width * 2, dy: -tileSize.height * 2)
        ZStack(alignment: .topLeading) {
            ForEach(entries.filter { entry in entry.id == draggedID || entry.id == selectedID || (visible.map { CGRect(origin: entry.origin, size: tileSize).intersects($0) } ?? true) }) { entry in
                FreePlacementTile(origin: entry.origin, canvas: canvas, size: tileSize,
                    begin: { begin(entry.id) }, end: end, save: { save(entry.id, $0) }) { content(entry) }
            }
        }.frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
            .background(CanvasViewportMonitor(tileSize: tileSize, revealRect: entries.first { $0.id == selectedID }.map { CGRect(origin: $0.origin, size: tileSize) }, revealGeneration: revealGeneration) { rect in if visibleViewport != rect { visibleViewport = rect } })
            .frame(maxWidth: .infinity)
    }
}

private struct FreePlacementTile<Content: View>: View {
    let origin: CGPoint
    let canvas: CGSize
    let size: CGSize
    let begin: () -> Void
    let end: () -> Void
    let save: (FreeIconPosition) -> Void
    @ViewBuilder var content: () -> Content
    @GestureState private var translation = CGSize.zero
    @State private var interacting = false
    var body: some View {
        content().frame(width: size.width, height: size.height)
            .offset(x: origin.x + translation.width, y: origin.y + translation.height)
            .zIndex(translation == .zero ? 0 : 1)
            .highPriorityGesture(DragGesture(minimumDistance: 4)
                .updating($translation) { value, state, _ in
                    let point = FreePlacementGeometry.origin(position: nil,
                        fallback: CGPoint(x: origin.x + value.translation.width, y: origin.y + value.translation.height), canvas: canvas, tile: size)
                    state = CGSize(width: point.x - origin.x, height: point.y - origin.y)
                }
                .onChanged { _ in if !interacting { interacting = true; begin() } }
                .onEnded { value in
                    save(FreePlacementGeometry.normalized(origin: CGPoint(x: origin.x + value.translation.width, y: origin.y + value.translation.height), canvas: canvas, tile: size))
                    interacting = false; end()
                })
            .onChange(of: translation == .zero) { reset in
                if reset && interacting { interacting = false; end() }
            }
            .onDisappear { if interacting { interacting = false; end() } }
    }
}
