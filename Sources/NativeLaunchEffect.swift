import AppKit
import QuartzCore

/// A single temporary native layer; opening the app never waits for the animation.
@MainActor enum NativeLaunchEffect {
    @discardableResult static func show(image: NSImage, appID: String, in window: NSWindow) -> Bool {
        guard let content = window.contentView,
              let frame = DockMagnificationController.shared.sourceFrame(appID: appID, in: window) else { return false }
        let ghost = LaunchGhost(frame: frame)
        ghost.image = image; ghost.imageScaling = .scaleProportionallyUpOrDown
        ghost.wantsLayer = true
        content.addSubview(ghost)
        guard let layer = ghost.layer else { ghost.removeFromSuperview(); return false }
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.position = CGPoint(x: frame.midX, y: frame.midY)
        let grow = CABasicAnimation(keyPath: "transform.scale"); grow.fromValue = 1; grow.toValue = 1.9
        let fade = CABasicAnimation(keyPath: "opacity"); fade.fromValue = 1; fade.toValue = 0
        let group = CAAnimationGroup(); group.animations = [grow, fade]
        group.duration = LauncherGeometry.launchEffectDuration
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        group.fillMode = .forwards; group.isRemovedOnCompletion = false
        layer.add(group, forKey: "aplo.launch")
        DispatchQueue.main.asyncAfter(deadline: .now() + LauncherGeometry.launchEffectDuration) { ghost.removeFromSuperview() }
        return true
    }
}
private final class LaunchGhost: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
