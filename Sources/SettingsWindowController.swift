import AppKit
import SwiftUI

/// Owns the settings window separately from the floating launcher and its placement.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let model: LauncherModel
    private let defaults: UserDefaults

    init(model: LauncherModel, defaults: UserDefaults) {
        self.model = model
        self.defaults = defaults
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 720),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        super.init(window: window)
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 780, height: 560)
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        let hosting = NSHostingView(rootView: SettingsView(model: model))
        hosting.sizingOptions = []
        window.contentView = hosting
        window.center()
        if let value = defaults.string(forKey: "aplo.settingsWindow.frame") {
            let saved = NSRectFromString(value)
            if saved.width >= window.minSize.width, saved.height >= window.minSize.height,
               let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(saved) }) {
                window.setFrame(CompactWindowPlacementStore.clamped(saved, in: screen.visibleFrame), display: false)
            }
        }
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func present(appearance: NSAppearance?) {
        guard let window else { return }
        window.title = "Aplo · " + model.text("设置")
        window.appearance = appearance
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender.attachedSheet == nil else { return false }
        model.closeSettings()
        return false
    }

    func windowDidResize(_ notification: Notification) { saveFrame() }
    func windowDidMove(_ notification: Notification) { saveFrame() }
    private func saveFrame() {
        if let window { defaults.set(NSStringFromRect(window.frame), forKey: "aplo.settingsWindow.frame") }
    }
}

extension AppDelegate {
    var interactionWindow: NSWindow { model.showingSettings ? (settingsController?.window ?? panel) : panel }

    func updateSettingsWindow() {
        if model.showingSettings {
            if settingsController == nil {
                settingsController = SettingsWindowController(model: model, defaults: runtimeDefaults)
            }
            hidePanel()
            settingsController?.present(appearance: panel.appearance)
        } else {
            settingsController?.window?.orderOut(nil)
        }
    }
}
