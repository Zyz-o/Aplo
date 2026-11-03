import AppKit
import Carbon
import SwiftUI
import QuartzCore
import UniformTypeIdentifiers
import Darwin

final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    let model: LauncherModel = {
        if let index = CommandLine.arguments.firstIndex(of: "--layout-file"),
           CommandLine.arguments.indices.contains(index + 1) {
            let url = URL(fileURLWithPath: CommandLine.arguments[index + 1])
            let defaults = UserDefaults(suiteName: "local.aplo.qa." + url.lastPathComponent)!
            return LauncherModel(store: LayoutStore(url: url), defaults: defaults)
        }
        return LauncherModel()
    }()
    let placementStore: CompactWindowPlacementStore = {
        if let index = CommandLine.arguments.firstIndex(of: "--layout-file"), CommandLine.arguments.indices.contains(index + 1) {
            let name = URL(fileURLWithPath: CommandLine.arguments[index + 1]).lastPathComponent
            return CompactWindowPlacementStore(defaults: UserDefaults(suiteName: "local.aplo.qa." + name)!)
        }
        return CompactWindowPlacementStore(defaults: .standard)
    }()
    var applyingDisplayFrame = false
    var positionSaveWork: DispatchWorkItem?
    var panel: LauncherPanel!
    var statusItem: NSStatusItem!
    var keyMonitor: Any?
    var gestureMonitor: Any?
    var hotKey: EventHotKeyRef?
    var alternateHotKey: EventHotKeyRef?
    var hotKeyHandler: EventHandlerRef?
    var previousApplication: NSRunningApplication?
    var previousPresentation: NSApplication.PresentationOptions?
    var presentingSystemDialog = false
    var launchingApplication = false
    var launchGeneration = UUID()
    var launchAnimationFinished = false
    var launchOpenFinished = false
    let hotCornerController = HotCornerController()
    var importTask: Task<Void, Never>?
    var importControl: LegacyReadControl?
    var terminationSignal: DispatchSourceSignal?
    var applicationWatcher: ApplicationWatcher?
    var minimizingWindow = false
    var updatingEntryVisibility = false
    var pageGesture = PageGesture()
    var continuousScrollScaler = ContinuousScrollSensitivity()
    var pendingPageTarget: Int?
    var lastDiscretePageTime: TimeInterval = 0
    var gestureStarted = false
    var pendingDragOffset: CGFloat?
    var dragUpdateThrottled = false
    var pagingToken = UUID()
    var gestureEndWork: DispatchWorkItem?
    let preview = CommandLine.arguments.contains("--preview")
    var runtimeDefaults: UserDefaults {
        if let index = CommandLine.arguments.firstIndex(of: "--layout-file"), CommandLine.arguments.indices.contains(index + 1) {
            let name = URL(fileURLWithPath: CommandLine.arguments[index + 1]).lastPathComponent
            return UserDefaults(suiteName: "local.aplo.qa." + name)!
        }
        return .standard
    }

    func trace(_ message: String) {
        if CommandLine.arguments.contains("--diagnostics") {
            FileHandle.standardError.write(Data(("[Aplo] " + message + "\n").utf8))
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Local upgrades use SIGTERM. Route it through AppKit so debounced
        // preferences and the final window position are flushed before exit.
        signal(SIGTERM, SIG_IGN)
        let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        termination.setEventHandler { MainActor.assumeIsolated { NSApp.terminate(nil) } }
        termination.resume(); terminationSignal = termination
        NSApp.setActivationPolicy(model.preferences.entryLocation.showsInDock ? .regular : .accessory)
        trace("started")
        model.isFullscreen = runtimeDefaults.object(forKey: "fullscreenMode") as? Bool ?? true
        if CommandLine.arguments.contains("--compact") { model.isFullscreen = false }
        if CommandLine.arguments.contains("--fullscreen") { model.isFullscreen = true }
        configurePanel()
        configureStatusItem()
        applyEntryVisibility()
        configureMainMenu()
        configureKeyboard()
        configureGestures()
        configureActions()
        registerHotKey()
        configureHotCorner()
        applyAppearance()
        model.requestRefresh(resetSearch: false, minimumInterval: 20)
        applicationWatcher = ApplicationWatcher(paths: AppCatalog(includeSystemApplications: true).roots.map(\.path)) { [weak self] in
            self?.model.requestRefresh(resetSearch: false)
        }
        if preview || CommandLine.arguments.contains("--show") { showPanel() }
    }

    func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "Aplo")
            button.image?.isTemplate = true
            button.toolTip = "Aplo · \(model.shortcutDisplayName)"
        }
        updateStatusMenu()
    }
    func updateStatusMenu() {
        let menu = NSMenu()
        let open = NSMenuItem(title: model.text("打开面板"), action: #selector(openFromMenu), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        let refresh = NSMenuItem(title: model.text("刷新应用列表"), action: #selector(refreshApplications), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)
        let displayMode = NSMenuItem(title: model.text("切换全屏 / 小面板"), action: #selector(toggleDisplayMode), keyEquivalent: "f")
        displayMode.keyEquivalentModifierMask = [.control, .command]
        displayMode.target = self
        menu.addItem(displayMode)
        let shortcut = NSMenuItem(title: model.text("快捷键：\(model.shortcutDisplayName)"), action: nil, keyEquivalent: "")
        shortcut.isEnabled = false
        menu.addItem(shortcut)
        let settings = NSMenuItem(title: model.text("设置与备份…"), action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: model.text("退出 Aplo"), action: #selector(quitApplication), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
    }

    func configureMainMenu() {
        let menu = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu()
        let quit = NSMenuItem(title: model.text("退出 Aplo"), action: #selector(quitApplication), keyEquivalent: "q")
        quit.target = self
        applicationMenu.addItem(quit)
        let settings = NSMenuItem(title: model.text("设置与备份…"), action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        settings.target = self
        applicationMenu.insertItem(settings, at: 0)
        applicationItem.submenu = applicationMenu
        menu.addItem(applicationItem)
        let editItem = NSMenuItem(title: model.text("编辑"), action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: model.text("编辑"))
        let undo = NSMenuItem(title: model.text("撤销"), action: #selector(undoOrganizationAction), keyEquivalent: "z")
        undo.target = self; editMenu.addItem(undo)
        let redo = NSMenuItem(title: model.text("重做"), action: #selector(redoOrganizationAction), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]; redo.target = self; editMenu.addItem(redo)
        editMenu.addItem(.separator())
        for (title, action, key) in [
            ("剪切", #selector(NSText.cut(_:)), "x"),
            ("拷贝", #selector(NSText.copy(_:)), "c"),
            ("粘贴", #selector(NSText.paste(_:)), "v"),
            ("全选", #selector(NSText.selectAll(_:)), "a")
        ] {
            editMenu.addItem(NSMenuItem(title: model.text(title), action: action, keyEquivalent: key))
        }
        editItem.submenu = editMenu
        menu.addItem(editItem)
        NSApp.mainMenu = menu
    }

    var editingText: Bool {
        (model.searchExpanded || model.renamingFolderID != nil || model.showingSettings) && panel.firstResponder is NSTextView
    }
    var textUndoManager: UndoManager? {
        guard editingText,
              let editor = panel.firstResponder as? NSTextView else { return nil }
        return editor.undoManager
    }

    func configureActions() {
        SoundManager.shared.bind(appStore: model)
        model.onSystemCommand = { [weak self] command in self?.confirmSystemCommand(command) }
        model.onTrashApplication = { [weak self] app in self?.confirmTrashApplication(app) }
        model.onAppearancePreviewChanged = { [weak self] in
            guard let self else { return }
            self.panel.hidesOnDeactivate = !self.preview && !self.updatingEntryVisibility && self.model.preferences.dismissStyle == .outsideClick && !self.model.presentingAppearancePreview
            if !self.model.presentingAppearancePreview { self.panel.makeKeyAndOrderFront(nil) }
        }
        model.onRestoreHistory = { [weak self] url in self?.startImport(url, legacy: false) }
        model.onNavigate = { [weak self] in
            guard let self, self.panel.isVisible, !self.model.showingSettings, !self.model.isSearching else { return }
            SoundManager.shared.play(.navigation)
        }
        model.onSettingsVisibilityChanged = { [weak self] in
            guard let self, self.panel.isVisible else { return }
            self.resetPageMotion()
            self.applyDisplayFrame(screen: self.panel.screen ?? NSScreen.main)
        }
        model.onPageRequested = { [weak self] target in
            guard let self else { return }
            self.finishPendingPage()
            let delta = target - self.model.pageIndex
            guard delta != 0 else { return }
            // Only the current page and its neighbors are rendered.
            if abs(delta) == 1 { self.settlePageMotion(explicitDelta: delta) }
            else { self.model.goToPage(target) }
        }
        model.onPreferencesChanged = { [weak self] changes in
            guard let self else { return }
            if changes.contains(.appearance) { self.applyAppearance() }
            if changes.contains(.hotKeys) { self.registerAlternateHotKey(); self.configureHotCorner() }
            if changes.contains(.navigation) {
                self.resetPageMotion()
                self.model.pageMotion.axis = self.model.navigationDirection == .vertical ? .vertical : .horizontal
            }
            if changes.contains(.menus) {
                self.configureMainMenu()
                self.updateStatusMenu()
            }
            if changes.contains(.entry) { self.applyEntryVisibility() }
            if changes.contains(.window) {
                self.panel.hasShadow = self.model.preferences.windowShadowEnabled
                self.panel.hidesOnDeactivate = !self.preview && !self.updatingEntryVisibility && self.model.preferences.dismissStyle == .outsideClick && !self.model.presentingAppearancePreview
                self.panel.level = self.model.preferences.pinToDesktop ? .normal : .floating
                self.panel.collectionBehavior = self.model.preferences.pinToDesktop ? [.fullScreenAuxiliary] : [.moveToActiveSpace, .fullScreenAuxiliary]
                self.updatePresentation()
            }
            if changes.contains(.frame) { self.applyDisplayFrame(screen: self.panel.screen ?? NSScreen.main) }
        }
        model.onMinimize = { [weak self] in
            guard let self else { return }
            if self.model.isFullscreen { self.toggleDisplayMode() }
            self.saveCompactPosition()
            self.restorePresentation()
            self.minimizingWindow = true
            self.panel.miniaturize(nil)
            DispatchQueue.main.async { [weak self] in self?.minimizingWindow = false }
        }
        model.onShortcutRequested = { [weak self] shortcut in self?.changeShortcut(shortcut) ?? false }
        model.onRecordingChanged = { [weak self] recording in
            guard let self else { return }
            if recording { self.unregisterHotKey() }
            else { self.restoreHotKey() }
        }
        model.onCancelImport = { [weak self] in self?.importTask?.cancel(); self?.importControl?.cancel() }
        model.onExport = { [weak self] in self?.exportBackup() }
        model.onRestore = { [weak self] in self?.restoreBackup() }
        model.onResetWindowPosition = { [weak self] in
            guard let self, !self.model.isFullscreen, let screen = self.panel.screen ?? NSScreen.main else { return }
            self.positionSaveWork?.cancel()
            self.placementStore.reset(screenID: self.screenIdentifier(screen))
            let frame = LauncherGeometry.compactFrame(in: screen.visibleFrame)
            guard self.panel.frame != frame else { return }
            self.applyingDisplayFrame = true
            self.panel.setFrame(frame, display: true)
            self.applyingDisplayFrame = false
        }
        model.onDisplayModeRequested = { [weak self] in self?.toggleDisplayMode() }
        model.onLegacyImport = { [weak self] in self?.importLegacy() }
        model.onNativeImport = { [weak self] in self?.importNative() }
    }

    @objc func openFromMenu() { showPanel() }
    @objc func refreshApplications() { model.requestRefresh(resetSearch: false) }
    @objc func openSettingsFromMenu() { showPanel(); model.openSettings() }
    @objc func quitApplication() { NSApp.terminate(nil) }

    func togglePanel() {
        if presentingSystemDialog || model.recordingShortcut { return }
        if panel.isVisible && !panel.isMiniaturized { hidePanel(restorePrevious: true) } else { showPanel() }
    }

    func launch(_ app: InstalledApp) {
        trace("launch \(app.url.path)")
        guard FileManager.default.fileExists(atPath: app.url.path) else {
            model.requestRefresh(resetSearch: false)
            model.message = "“\(app.name)”已被移动或卸载，列表已刷新。"
            return
        }
        let generation = UUID(); launchGeneration = generation
        launchingApplication = true; launchAnimationFinished = false; launchOpenFinished = false; panel.hidesOnDeactivate = false
        let animate = model.preferences.animationsEnabled && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let effect = animate ? NativeLaunchEffect.show(image: model.icon(for: app), appID: app.id, in: panel) : false
        let duration = effect ? LauncherGeometry.launchEffectDuration : 0
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self, self.launchGeneration == generation else { return }
            if self.model.preferences.launchAutoHide { self.hidePanel() }
            self.launchAnimationFinished = true
            self.finishLaunchPresentation(generation)
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: app.url, configuration: configuration) { [weak self] _, error in
            if CommandLine.arguments.contains("--diagnostics") {
                FileHandle.standardError.write(Data(("[Aplo] launch result: \(String(describing: error))\n").utf8))
            }
            let failed = error != nil
            Task { @MainActor [weak self] in
                guard let self else { return }
                if !failed { self.model.recordRecentLaunch(app.id) }
                guard self.launchGeneration == generation else { return }
                if !failed { self.launchOpenFinished = true; self.finishLaunchPresentation(generation); return }
                self.launchGeneration = UUID(); self.launchingApplication = false
                self.model.message = "无法打开“\(app.name)”，请检查应用是否完整或有权限运行。"
                self.showPanel(preservingMessage: true)
            }
        }
    }

    func finishLaunchPresentation(_ generation: UUID) {
        guard launchGeneration == generation, launchAnimationFinished, launchOpenFinished else { return }
        launchingApplication = false
        panel.hidesOnDeactivate = !preview && model.preferences.dismissStyle == .outsideClick
    }
    func configureHotCorner() {
        hotCornerController.configure(corner: model.preferences.hotCorner) { [weak self] in
            guard let self, !self.panel.isVisible, !self.presentingSystemDialog, !self.model.recordingShortcut else { return }
            self.showPanel()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        trace("terminate flushing preferences")
        hotCornerController.stop()
        applicationWatcher?.stop(); applicationWatcher = nil
        model.flushPreferences()
        importTask?.cancel(); importControl?.cancel()
        saveCompactPosition()
        positionSaveWork?.cancel()
        restorePresentation()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let gestureMonitor { NSEvent.removeMonitor(gestureMonitor) }
        unregisterHotKey()
        if let hotKeyHandler { RemoveEventHandler(hotKeyHandler) }
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
