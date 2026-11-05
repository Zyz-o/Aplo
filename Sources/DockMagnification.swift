import AppKit
import SwiftUI
import QuartzCore

/// Pointer motion updates only nearby icon layers, without publishing grid/model changes.
@MainActor final class DockMagnificationController {
    static let shared = DockMagnificationController()
    private struct Entry { weak var view: MagnificationIconView? }
    private var entries: [ObjectIdentifier: Entry] = [:]
    private var magnifiedView: MagnificationIconView?
    private weak var lastWindow: NSWindow?
    private var lastPoint: NSPoint?
    private var scrollMonitor: Any?
    private var scrollBusyUntil: CFTimeInterval = 0
    private var waitingForScrollEnd = false
    private var enabled = false
    private init() {}
    func setEnabled(_ value: Bool) {
        guard enabled != value else { return }
        enabled = value
        if !value {
            if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
            scrollMonitor = nil; reset(); return
        }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .mouseMoved]) { [weak self] event in
            if let window = event.window {
                if event.type == .scrollWheel { self?.scrolling(window: window, point: event.locationInWindow) }
                else { self?.schedule(window: window, point: event.locationInWindow) }
            }
            return event
        }
    }
    private weak var pendingWindow: NSWindow?
    private var pendingPoint = NSPoint.zero
    private var pendingFollowsLayout = false
    private var scheduled = false
    private func scrolling(window: NSWindow, point: NSPoint) {
        pendingWindow = window; pendingPoint = point
        scrollBusyUntil = CACurrentMediaTime() + 0.12
        guard !waitingForScrollEnd else { return }
        waitingForScrollEnd = true
        // Once per gesture, rather than geometry conversion and animation for
        // every visible icon on every wheel/momentum event.
        magnifiedView?.setScale(1, immediately: true)
        magnifiedView = nil
        // Tiles moved under a stationary pointer, so the cached hit test is stale.
        lastPoint = nil
        resumeAfterScroll()
    }
    private func resumeAfterScroll() {
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.001, scrollBusyUntil - CACurrentMediaTime())) { [weak self] in
            guard let self else { return }
            if CACurrentMediaTime() < self.scrollBusyUntil { self.resumeAfterScroll(); return }
            self.waitingForScrollEnd = false
            guard let window = self.pendingWindow else { return }
            self.schedule(window: window, point: window.mouseLocationOutsideOfEventStream)
        }
    }
    func schedule(window: NSWindow?, point: NSPoint, followsLayout: Bool = false) {
        guard enabled else { return }
        pendingWindow = window; pendingPoint = point; pendingFollowsLayout = followsLayout
        guard !waitingForScrollEnd else { return }
        guard !scheduled else { return }
        scheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.scheduled = false
            guard !self.waitingForScrollEnd else { return }
            guard let window = self.pendingWindow else { return }
            self.update(window: window, point: self.pendingFollowsLayout ? window.mouseLocationOutsideOfEventStream : self.pendingPoint)
        }
    }
    func register(_ view: MagnificationIconView) { entries[ObjectIdentifier(view)] = Entry(view: view) }
    func unregister(_ view: MagnificationIconView) {
        entries.removeValue(forKey: ObjectIdentifier(view))
        if magnifiedView === view { magnifiedView = nil }
    }
    func update(window: NSWindow?, point: NSPoint) {
        guard enabled else { return }
        // Trackpad and mouse streams repeat the same location; recomputing the whole
        // hit test for an unchanged pointer burned a full pass per event.
        if window === lastWindow, let lastPoint, lastPoint == point { return }
        lastWindow = window; lastPoint = point
        var target: MagnificationIconView?
        var targetScale: CGFloat = 1
        for entry in entries.values {
            guard let view = entry.view, view.window === window, window != nil,
                  view.enabled, !view.visibleRect.isEmpty else { continue }
            // Use unscaled layout bounds so magnification cannot expand its own hit area.
            let rect = view.convert(view.bounds, to: nil)
            guard rect.contains(point), view.visibleRect.contains(view.convert(point, from: nil)) else { continue }
            let scale = DockMagnificationCurve.scale(dx: point.x - rect.midX, dy: point.y - rect.midY, size: rect.size)
            if scale > targetScale { target = view; targetScale = scale }
        }
        // Only the icon that lost the pointer needs to shrink. Resetting every tile on
        // every mouse-move created one Core Animation transaction per visible icon.
        if let previous = magnifiedView, previous !== target {
            previous.setScale(1, immediately: true)
        }
        if magnifiedView !== target, let target, CommandLine.arguments.contains("--diagnostics") {
            let identifier = target.applicationID ?? "folder"
            let message = "[Aplo] hover magnified \(identifier) scale=\(targetScale)\n"
            FileHandle.standardError.write(Data(message.utf8))
        }
        magnifiedView = target
        if let target { target.setScale(targetScale) }
    }

    func sourceFrame(appID: String, in window: NSWindow) -> CGRect? {
        guard let content = window.contentView else { return nil }
        return entries.values.compactMap(\.view).first {
            $0.applicationID == appID && $0.window === window && !$0.visibleRect.isEmpty
        }.map { $0.convert($0.bounds, to: content) }
    }
    func reset() {
        pendingWindow = nil
        lastPoint = nil
        magnifiedView?.setScale(1)
        magnifiedView = nil
    }
}

class MagnificationIconView: NSView {
    var applicationID: String?
    /// Stable per-item seed for the jiggle phase. Deriving it from the view identity
    /// made the wobble restart with a new rhythm whenever tiles were rebuilt after a
    /// drop, which read as a sudden shake.
    var wiggleSeed = ""
    func setWiggling(_ value: Bool) {
        guard let layer else { return }
        if !value { layer.removeAnimation(forKey: "aplo.editWiggle"); return }
        guard layer.animation(forKey: "aplo.editWiggle") == nil else { return }
        let animation = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        animation.values = [-0.018, 0.018, -0.018]
        animation.duration = 0.30; animation.repeatCount = .infinity
        animation.beginTime = CACurrentMediaTime() + Double(abs((wiggleSeed.isEmpty ? applicationID : wiggleSeed)?.hashValue ?? 0) % 9) * 0.012
        layer.add(animation, forKey: "aplo.editWiggle")
    }
    var enabled = true { didSet { if !enabled { setScale(1) } } }
    var animated = true
    private var scale: CGFloat = 1
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { DockMagnificationController.shared.register(self) }
        else { DockMagnificationController.shared.unregister(self) }
    }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    func setScale(_ value: CGFloat, immediately: Bool = false) {
        guard abs(value - scale) > 0.002, let layer else { return }
        scale = value
        var target = CATransform3DMakeScale(value, value, 1)
        target.m41 = (0.5 - layer.anchorPoint.x) * bounds.width * (1 - value)
        target.m42 = (0.5 - layer.anchorPoint.y) * bounds.height * (1 - value)
        let previous = layer.presentation()?.transform ?? layer.transform
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer.transform = target; layer.zPosition = value > 1.01 ? 2 : 0
        CATransaction.commit()
        if animated && !immediately {
            let animation = CABasicAnimation(keyPath: "transform")
            animation.fromValue = NSValue(caTransform3D: previous)
            animation.toValue = NSValue(caTransform3D: target)
            animation.duration = 0.1
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(animation, forKey: "aplo.magnify")
        } else { layer.removeAnimation(forKey: "aplo.magnify") }
    }
}
final class MagnificationHost<Content: View>: MagnificationIconView {
    var identity: IconRenderIdentity?
    private let imageView = NSImageView()
    private var hosting: NSHostingView<Content>?
    init() {
        super.init(frame: .zero)
        wantsLayer = true; layer?.masksToBounds = false
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.isEditable = false
        addSubview(imageView)
    }
    required init?(coder: NSCoder) { nil }
    func updateContent(image: NSImage?, content: () -> Content) {
        if let image {
            hosting?.isHidden = true
            imageView.isHidden = false; imageView.image = image
        } else {
            imageView.isHidden = true
            if let hosting { hosting.rootView = content(); hosting.isHidden = false }
            else {
                let view = NSHostingView(rootView: content())
                view.sizingOptions = []; view.frame = bounds
                addSubview(view); hosting = view
            }
        }
    }
    override func layout() { super.layout(); imageView.frame = bounds; hosting?.frame = bounds }
}
struct IconRenderIdentity: Equatable {
    let item: LayoutItem
    let children: [String]?
    let images: [ObjectIdentifier]
    let size: CGFloat
    let colorVision: LauncherColorVision
    let badgePoints: CGFloat
    let dark: Bool
}
struct DockMagnifiedIcon<Content: View>: NSViewRepresentable {
    let identity: IconRenderIdentity
    let image: NSImage?
    let enabled: Bool
    let animated: Bool
    var wiggling = false
    @ViewBuilder let content: () -> Content
    func makeNSView(context: Context) -> MagnificationHost<Content> {
        let view = MagnificationHost<Content>()
        view.updateContent(image: image, content: content)
        view.identity = identity
        return view
    }
    func updateNSView(_ view: MagnificationHost<Content>, context: Context) {
        if view.identity != identity {
            view.updateContent(image: image, content: content)
            view.identity = identity
        }
        view.applicationID = identity.item.appID
        view.wiggleSeed = identity.item.id
        view.enabled = enabled; view.animated = animated; view.setWiggling(wiggling)
    }
}
struct MagnificationSurface: NSViewRepresentable {
    var enabled: Bool
    func makeNSView(context: Context) -> PointerSurface { PointerSurface() }
    func updateNSView(_ view: PointerSurface, context: Context) {
        DockMagnificationController.shared.setEnabled(enabled)
        if view.enabled != enabled { view.enabled = enabled; view.updateTrackingAreas() }
    }
}
final class PointerSurface: NSView {
    private var tracking: NSTrackingArea?
    var enabled = false
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }; tracking = nil
        guard enabled else { return }
        let value = NSTrackingArea(rect: .zero, options: [.inVisibleRect, .activeAlways, .mouseMoved, .mouseEnteredAndExited], owner: self, userInfo: nil)
        addTrackingArea(value); tracking = value
    }
    override func mouseMoved(with event: NSEvent) { DockMagnificationController.shared.schedule(window: window, point: event.locationInWindow) }
    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseExited(with event: NSEvent) { DockMagnificationController.shared.reset() }
}

@MainActor private enum LabelFontCache {
    private static var values: [String: Font] = [:]
    static func resolve(key: String, create: () -> Font) -> Font {
        if let value = values[key] { return value }
        let value = create()
        if values.count >= 128 { values.removeAll(keepingCapacity: true) }
        values[key] = value
        return value
    }
}

@MainActor extension LauncherModel {
    var applicationLabelFont: Font { Self.applicationLabelFont(preferences) }
    static func applicationLabelFont(_ preferences: LauncherPreferences) -> Font {
        let size = preferences.textPoints(14)
        return LabelFontCache.resolve(key: "\(preferences.labelFontFamily)|\(preferences.labelWeight)|\(size)") {
        let weight: Font.Weight
        let nativeWeight: Int
        switch preferences.labelWeight {
        case .light: weight = .light; nativeWeight = 3
        case .regular: weight = .regular; nativeWeight = 5
        case .medium: weight = .medium; nativeWeight = 6
        case .semibold: weight = .semibold; nativeWeight = 8
        case .bold: weight = .bold; nativeWeight = 9
        }
        if !preferences.labelFontFamily.isEmpty,
           let font = NSFontManager.shared.font(withFamily: preferences.labelFontFamily, traits: [], weight: nativeWeight, size: size) {
            return .custom(font.fontName, size: size)
        }
        return .system(size: size, weight: weight)
        }
    }
    var applicationLabelColor: Color { Self.applicationLabelColor(preferences) }
    static func applicationLabelColor(_ preferences: LauncherPreferences) -> Color {
        switch preferences.labelColor {
        case .automatic:
            return preferences.backgroundTransparency > 0.7 && !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? .white : .primary
        case .white: return .white
        case .black: return .black
        case .custom: return Self.color(hex: preferences.labelColorHex)
        }
    }
    static func color(hex: String) -> Color {
        let rgb = UInt64(hex.dropFirst(), radix: 16) ?? 0xFFFFFF
        return Color(red: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255)
    }
}
