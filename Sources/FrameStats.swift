import AppKit
import QuartzCore
import SwiftUI

/// Live frame statistics for judging scroll smoothness objectively.
///
/// The numbers come from the window's display link, so they reflect what the
/// compositor actually delivered. A steady 120 Hz trackpad scroll shows an
/// interval flat at ~8.3 ms; a dropped frame shows up as a spike and a miss.
struct FrameStatsOverlay: NSViewRepresentable {
    let active: Bool
    func makeNSView(context: Context) -> FrameStatsView { FrameStatsView() }
    func updateNSView(_ view: FrameStatsView, context: Context) { view.setActive(active) }
}

final class FrameStatsView: NSView {
    private let label = NSTextField(labelWithString: "—")
    /// `CADisplayLink` exists only on macOS 14+, so it is held type-erased.
    private var link: Any?
    private var previous: CFTimeInterval = 0
    private var baseline: CFTimeInterval = 0
    private var windowStart: CFTimeInterval = 0
    private var frames = 0
    private var drops = 0
    private var worst: CFTimeInterval = 0
    private var active = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.62).cgColor
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.lineBreakMode = .byClipping
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8)
        ])
    }
    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func setActive(_ value: Bool) {
        guard active != value else { return }
        active = value
        value ? start() : stop()
        isHidden = !value
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stop() } else if active { start() }
    }

    private func start() {
        guard window != nil else { return }
        reset()
        guard #available(macOS 14.0, *) else {
            label.stringValue = "帧率统计需要 macOS 14"
            return
        }
        guard link == nil else { return }
        let displayLink = displayLink(target: self, selector: #selector(tick(_:)))
        displayLink.add(to: .main, forMode: .common)
        link = displayLink
    }

    private func stop() {
        if #available(macOS 14.0, *), let current = link as? CADisplayLink {
            current.invalidate()
        }
        link = nil
        previous = 0
    }

    private func reset() {
        previous = 0; baseline = 0; windowStart = 0
        frames = 0; drops = 0; worst = 0
        label.stringValue = "—"
    }

    @available(macOS 14.0, *)
    @objc private func tick(_ displayLink: CADisplayLink) {
        let now = displayLink.timestamp
        guard previous > 0 else { previous = now; windowStart = now; return }
        let interval = now - previous
        previous = now
        guard interval > 0, interval < 1 else { return }
        // The fastest interval seen so far approximates the panel's native cadence.
        if baseline == 0 || interval < baseline { baseline = interval }
        frames += 1
        if interval > worst { worst = interval }
        if interval > baseline * 1.5 {
            drops += max(1, Int((interval / baseline).rounded()) - 1)
        }
        guard now - windowStart >= 0.5 else { return }
        let elapsed = now - windowStart
        let fps = Double(frames) / elapsed
        label.stringValue = String(format: "%.0f fps · 峰值 %.1f ms · 掉帧 %d", fps, worst * 1000, drops)
        label.textColor = drops == 0 ? .systemGreen : (drops < 6 ? .systemYellow : .systemRed)
        windowStart = now; frames = 0; drops = 0; worst = 0
    }
}
