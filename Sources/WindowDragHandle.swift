import AppKit
import SwiftUI

/// Only header space moves the window; grid and control gestures remain independent.
struct WindowDragHandle: NSViewRepresentable {
    let enabled: Bool
    func makeNSView(context: Context) -> HeaderDragView { HeaderDragView() }
    func updateNSView(_ view: HeaderDragView, context: Context) { view.enabled = enabled }
}

final class HeaderDragView: NSView {
    var enabled = true
    override var mouseDownCanMoveWindow: Bool { enabled }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { enabled ? super.hitTest(point) : nil }
    override func mouseDown(with event: NSEvent) {
        guard enabled, let window else { return }
        window.performDrag(with: event)
    }
}

struct WindowResizeHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> CornerResizeView { CornerResizeView() }
    func updateNSView(_ view: CornerResizeView, context: Context) {}
}
final class CornerResizeView: NSView {
    private var startPoint = NSPoint.zero
    private var startFrame = NSRect.zero
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        startPoint = window.convertPoint(toScreen: event.locationInWindow)
        startFrame = window.frame
        if CommandLine.arguments.contains("--diagnostics") { FileHandle.standardError.write(Data("[Aplo] resize start \(startFrame)\n".utf8)) }
    }
    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let point = window.convertPoint(toScreen: event.locationInWindow)
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? startFrame
        let width = min(max(window.minSize.width, startFrame.width + point.x - startPoint.x), max(1, visible.maxX - startFrame.minX - 16))
        let height = min(max(window.minSize.height, startFrame.height - point.y + startPoint.y), max(1, startFrame.maxY - visible.minY - 16))
        window.setFrame(NSRect(x: startFrame.minX, y: startFrame.maxY - height, width: width, height: height), display: true)
    }
}
