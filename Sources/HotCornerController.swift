import AppKit

/// Mouse-only monitors require no Accessibility permission. No timer runs while disabled.
@MainActor final class HotCornerController {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var pending: DispatchWorkItem?
    private var entered = false
    private var corner = "off"
    private var action: (() -> Void)?
    func configure(corner: String, action: @escaping () -> Void) {
        stop(); self.corner = corner; self.action = action
        guard corner != "off" else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            MainActor.assumeIsolated { self?.sample() }; return event
        }
    }
    static func contains(_ point: NSPoint, screen: NSRect, corner: String) -> Bool {
        let left = corner.hasSuffix("Left"), top = corner.hasPrefix("top")
        guard ["topLeft", "topRight", "bottomLeft", "bottomRight"].contains(corner) else { return false }
        let origin = NSPoint(x: left ? screen.minX : screen.maxX - 4, y: top ? screen.maxY - 4 : screen.minY)
        return NSRect(origin: origin, size: NSSize(width: 4, height: 4)).contains(point)
    }
    private func inside() -> Bool {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.contains { Self.contains(point, screen: $0.frame, corner: corner) }
    }
    private func sample() {
        guard inside() else { entered = false; pending?.cancel(); pending = nil; return }
        guard !entered else { return }
        entered = true
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.entered, self.inside() else { return }
            self.action?()
        }
        pending = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }
    func stop() {
        pending?.cancel(); pending = nil; entered = false
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil; localMonitor = nil; action = nil
    }
}
