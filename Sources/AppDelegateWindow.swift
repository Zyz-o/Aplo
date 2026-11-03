import AppKit
import Carbon
import SwiftUI
import QuartzCore
import UniformTypeIdentifiers

extension AppDelegate {
    func configurePanel() {
        panel = LauncherPanel(contentRect: NSRect(origin: .zero, size: LauncherGeometry.compactSize), styleMask: [.borderless, .resizable, .miniaturizable], backing: .buffered, defer: false)
        panel.title = model.text("Aplo")
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.isMovable = true
        panel.minSize = NSSize(width: 720, height: 520)
        panel.isMovableByWindowBackground = true
        panel.acceptsMouseMovedEvents = true
        panel.level = model.preferences.pinToDesktop ? .normal : .floating
        panel.hidesOnDeactivate = !preview && model.preferences.dismissStyle == .outsideClick
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = model.preferences.windowShadowEnabled
        panel.collectionBehavior = model.preferences.pinToDesktop ? [.fullScreenAuxiliary] : [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.delegate = self
        let hosting = NSHostingView(rootView: LauncherView(model: model) { [weak self] app in self?.launch(app) })
        hosting.sizingOptions = []
        panel.contentView = hosting
    }

    func applyEntryVisibility() {
        statusItem.isVisible = model.preferences.entryLocation.showsInMenuBar
        let target: NSApplication.ActivationPolicy = model.preferences.entryLocation.showsInDock ? .regular : .accessory
        guard NSApp.activationPolicy() != target else { return }
        // Changing Dock participation may briefly deactivate the app. Preserve Settings.
        updatingEntryVisibility = true
        let wasVisible = panel.isVisible && !panel.isMiniaturized
        panel.hidesOnDeactivate = false
        NSApp.setActivationPolicy(target)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if wasVisible {
                self.panel.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
            self.updatingEntryVisibility = false
            self.panel.hidesOnDeactivate = !self.preview && self.model.preferences.dismissStyle == .outsideClick && !self.model.presentingAppearancePreview
        }
    }

    func applyAppearance() {
        if CommandLine.arguments.contains("--appearance-dark") { panel.appearance = NSAppearance(named: .darkAqua); return }
        if CommandLine.arguments.contains("--appearance-light") { panel.appearance = NSAppearance(named: .aqua); return }
        switch model.preferences.appearance {
        case .system: panel.appearance = nil
        case .light: panel.appearance = NSAppearance(named: .aqua)
        case .dark: panel.appearance = NSAppearance(named: .darkAqua)
        }
    }

    @objc func toggleDisplayMode() {
        guard !presentingSystemDialog, !model.recordingShortcut, model.draggingID == nil, !model.importInProgress else { return }
        saveCompactPosition()
        resetPageMotion()
        model.isFullscreen.toggle()
        runtimeDefaults.set(model.isFullscreen, forKey: "fullscreenMode")
        if !model.isFullscreen { restorePresentation() }
        if panel.isVisible {
            applyDisplayFrame(screen: panel.screen ?? NSScreen.main)
            updatePresentation()
            model.focusGeneration += 1
        } else { showPanel() }
    }

    func applyDisplayFrame(screen: NSScreen?) {
        guard let screen else { return }
        let frame: NSRect
        if model.isFullscreen { frame = model.preferences.dockVisibility == .visible ? screen.visibleFrame : screen.frame }
        else {
            let saved = placementStore.frame(in: screen.visibleFrame, screenID: screenIdentifier(screen))
            if panel.isVisible && panel.frame.width < screen.frame.width - 1,
               screen.frame.intersects(panel.frame) {
                frame = CompactWindowPlacementStore.clamped(panel.frame, in: screen.visibleFrame)
            } else { frame = saved }
        }
        if model.displayWidth != frame.width { model.displayWidth = frame.width }
        guard panel.frame != frame else { return }
        positionSaveWork?.cancel()
        applyingDisplayFrame = true
        panel.setFrame(frame, display: true)
        applyingDisplayFrame = false
    }

    func screenIdentifier(_ screen: NSScreen) -> String {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue ?? "main"
    }

    func saveCompactPosition() {
        guard !applyingDisplayFrame, !model.isFullscreen, panel.isVisible, let screen = panel.screen ?? NSScreen.main else { return }
        placementStore.save(frame: panel.frame, in: screen.visibleFrame, screenID: screenIdentifier(screen))
    }

    func windowDidMiniaturize(_ notification: Notification) { minimizingWindow = false; restorePresentation(); trace("miniaturized=\(panel.isMiniaturized)") }

    func windowDidDeminiaturize(_ notification: Notification) { panel.makeKeyAndOrderFront(nil); updatePresentation(); trace("deminiaturized") }

    func windowDidResize(_ notification: Notification) {
        guard !applyingDisplayFrame else { return }
        model.displayWidth = panel.frame.width
        windowDidMove(notification)
    }

    func windowDidEndLiveResize(_ notification: Notification) { saveCompactPosition() }

    func windowDidMove(_ notification: Notification) {
        guard !applyingDisplayFrame, !model.isFullscreen, panel.isVisible else { return }
        positionSaveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveCompactPosition() }
        positionSaveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    func updatePresentation() {
        guard panel.isVisible else { return }
        if previousPresentation == nil { previousPresentation = NSApp.presentationOptions }
        var options = previousPresentation ?? []
        switch model.preferences.dockVisibility {
        case .hidden:
            options.remove(.autoHideDock); options.insert(.hideDock)
        case .followWindow:
            if model.isFullscreen { options.formUnion([.autoHideDock, .autoHideMenuBar]) }
        case .visible:
            options.subtract([.hideDock, .autoHideDock, .hideMenuBar, .autoHideMenuBar])
        }
        NSApp.presentationOptions = options
    }

    func restorePresentation() {
        if let previousPresentation { NSApp.presentationOptions = previousPresentation; self.previousPresentation = nil }
    }

    func showPanel(preservingMessage: Bool = false) {
        trace("show visible=\(panel.isVisible) preserveMessage=\(preservingMessage)")
        let wasVisible = panel.isVisible && !panel.isMiniaturized
        if !panel.isVisible { previousApplication = NSWorkspace.shared.frontmostApplication }
        launchGeneration = UUID(); launchingApplication = false
        if !preservingMessage {
            model.message = model.shortcutAvailable ? nil : "快捷键可能已被其他应用占用，请从菜单栏打开面板。"
        }
        model.requestRefresh(minimumInterval: 20)
        let point = NSEvent.mouseLocation
        let pointerScreen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main
        let screen = model.preferences.pinToDesktop ? panel.screen ?? pointerScreen : pointerScreen
        applyDisplayFrame(screen: screen)
        let animateOpen = !wasVisible && model.preferences.animationsEnabled && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = animateOpen ? 0 : 1
        if panel.isMiniaturized { panel.deminiaturize(nil) }
        panel.makeKeyAndOrderFront(nil)
        if animateOpen {
            panel.contentView?.wantsLayer = true
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 0.97; scale.toValue = 1
            scale.duration = 0.2
            scale.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.contentView?.layer?.add(scale, forKey: "aplo.open")
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                panel.animator().alphaValue = 1
            }
        }
        if !wasVisible { SoundManager.shared.play(.launchpadOpen) }
        NSApp.activate(ignoringOtherApps: true)
        updatePresentation()
        model.focusGeneration += 1
    }

    func hidePanel(restorePrevious: Bool = false) {
        trace("hide visible=\(panel.isVisible) restore=\(restorePrevious)")
        resetPageMotion()
        let wasVisible = panel.isVisible
        saveCompactPosition()
        panel.orderOut(nil)
        if wasVisible { SoundManager.shared.play(.launchpadClose) }
        restorePresentation()
        if restorePrevious, let previousApplication, previousApplication.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApplication.activate()
        }
        previousApplication = nil
    }

    func windowDidResignKey(_ notification: Notification) {
        // App-owned auxiliary windows (font/color panels, pickers) keep the launcher open.
        guard !NSApp.isActive else { return }
        if !preview, !launchingApplication, model.preferences.dismissStyle == .outsideClick, !panel.isMiniaturized, !minimizingWindow, !updatingEntryVisibility, !presentingSystemDialog, !model.presentingAppearancePreview, panel.attachedSheet == nil, panel.isVisible { hidePanel() }
    }

    func applicationDidResignActive(_ notification: Notification) {
        DockMagnificationController.shared.reset()
        if !preview, !launchingApplication, model.preferences.dismissStyle == .outsideClick, !panel.isMiniaturized, !minimizingWindow, !updatingEntryVisibility, !presentingSystemDialog, !model.presentingAppearancePreview, panel.attachedSheet == nil { hidePanel() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        trace("reopen visible=\(panel.isVisible) flag=\(flag)")
        if !panel.isVisible || panel.isMiniaturized { showPanel() }
        else { panel.makeKeyAndOrderFront(nil) }
        return true
    }
}
