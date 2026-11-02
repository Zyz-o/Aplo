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

private enum PreparedLayoutImport: Sendable {
    case backup(LauncherLayout)
    case legacy(LegacyImportResult)
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
    private let placementStore: CompactWindowPlacementStore = {
        if let index = CommandLine.arguments.firstIndex(of: "--layout-file"), CommandLine.arguments.indices.contains(index + 1) {
            let name = URL(fileURLWithPath: CommandLine.arguments[index + 1]).lastPathComponent
            return CompactWindowPlacementStore(defaults: UserDefaults(suiteName: "local.aplo.qa." + name)!)
        }
        return CompactWindowPlacementStore(defaults: .standard)
    }()
    private var applyingDisplayFrame = false
    private var positionSaveWork: DispatchWorkItem?
    private var panel: LauncherPanel!
    private var statusItem: NSStatusItem!
    private var keyMonitor: Any?
    private var gestureMonitor: Any?
    private var hotKey: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var previousApplication: NSRunningApplication?
    private var previousPresentation: NSApplication.PresentationOptions?
    private var presentingSystemDialog = false
    private var importTask: Task<Void, Never>?
    private var importControl: LegacyReadControl?
    private var terminationSignal: DispatchSourceSignal?
    private var applicationWatcher: ApplicationWatcher?
    private var minimizingWindow = false
    private var updatingEntryVisibility = false
    private var pageGesture = PageGesture()
    private var continuousScrollScaler = ContinuousScrollSensitivity()
    private var pendingPageTarget: Int?
    private var lastDiscretePageTime: TimeInterval = 0
    private var gestureStarted = false
    private var pagingToken = UUID()
    private var gestureEndWork: DispatchWorkItem?
    private let preview = CommandLine.arguments.contains("--preview")
    private var runtimeDefaults: UserDefaults {
        if let index = CommandLine.arguments.firstIndex(of: "--layout-file"), CommandLine.arguments.indices.contains(index + 1) {
            let name = URL(fileURLWithPath: CommandLine.arguments[index + 1]).lastPathComponent
            return UserDefaults(suiteName: "local.aplo.qa." + name)!
        }
        return .standard
    }

    private func trace(_ message: String) {
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
        applyAppearance()
        model.requestRefresh(resetSearch: false, minimumInterval: 20)
        applicationWatcher = ApplicationWatcher(paths: AppCatalog(includeSystemApplications: true).roots.map(\.path)) { [weak self] in
            self?.model.requestRefresh(resetSearch: false)
        }
        if preview || CommandLine.arguments.contains("--show") { showPanel() }
    }

    private func configurePanel() {
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

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "Aplo")
            button.image?.isTemplate = true
            button.toolTip = "Aplo · \(model.shortcutDisplayName)"
        }
        updateStatusMenu()
    }
    private func applyEntryVisibility() {
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
    private func updateStatusMenu() {
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

    private func configureMainMenu() {
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

    private var editingText: Bool {
        (model.searchExpanded || model.renamingFolderID != nil || model.showingSettings) && panel.firstResponder is NSTextView
    }
    private var textUndoManager: UndoManager? {
        guard editingText,
              let editor = panel.firstResponder as? NSTextView else { return nil }
        return editor.undoManager
    }
    @objc private func undoOrganizationAction(_ sender: Any?) {
        if editingText { textUndoManager?.undo() } else { model.undoOrganization() }
    }
    @objc private func redoOrganizationAction(_ sender: Any?) {
        if editingText { textUndoManager?.redo() } else { model.redoOrganization() }
    }
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(undoOrganizationAction) { return editingText ? (textUndoManager?.canUndo ?? false) : (model.canUndoOrganization && !model.importInProgress && model.draggingID == nil) }
        if item.action == #selector(redoOrganizationAction) { return editingText ? (textUndoManager?.canRedo ?? false) : (model.canRedoOrganization && !model.importInProgress && model.draggingID == nil) }
        return true
    }

    private func configureKeyboard() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { [weak self] event in
            guard let self, self.panel.isVisible, self.panel.isKeyWindow, NSApp.modalWindow == nil,
                  !self.presentingSystemDialog, self.panel.attachedSheet == nil else { return event }
            if self.model.presentingAppearancePreview { return event }
            if event.type == .leftMouseDown { self.model.keyboardSelectionActive = false; return event }
            if self.model.draggingID != nil { return event } // Let AppKit finish or cancel its native drag session.
            if self.model.pageTransitionActive { self.resetPageMotion() }
            if self.model.recordingShortcut {
                if Int(event.keyCode) == kVK_Escape { self.model.cancelRecording(); return nil }
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                var modifiers: UInt32 = 0
                if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
                if flags.contains(.control) { modifiers |= UInt32(controlKey) }
                if flags.contains(.option) { modifiers |= UInt32(optionKey) }
                if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
                let labels: [Int: String] = [kVK_Space: "Space", kVK_Return: "Return", kVK_ANSI_KeypadEnter: "Return", kVK_Tab: "Tab",
                    kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓"]
                let name = labels[Int(event.keyCode)] ?? event.charactersIgnoringModifiers?.uppercased() ?? ""
                let shortcut = ShortcutBinding(keyCode: UInt32(event.keyCode), modifiers: modifiers, keyName: name)
                if shortcut.isValid { self.model.acceptShortcut(shortcut) }
                else { self.model.message = "请同时按住 ⌘、⌃ 或 ⌥，再按一个普通按键。" }
                return nil
            }
            // Let the input method finish composition before treating a key as navigation.
            if let editor = self.panel.firstResponder as? NSTextView, editor.hasMarkedText() { return event }
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if Int(event.keyCode) == kVK_ANSI_F && modifiers.intersection([.command, .control, .option, .shift]) == [.command, .control] {
                self.toggleDisplayMode()
                return nil
            }
            guard !modifiers.contains(.command), !modifiers.contains(.control), !modifiers.contains(.option) else { return event }
            if self.model.renamingFolderID != nil {
                if Int(event.keyCode) == kVK_Escape { self.model.finishRename(cancel: true); return nil }
                if Int(event.keyCode) == kVK_Return { self.model.finishRename(); return nil }
                return event
            }
            if self.model.showingSettings {
                if Int(event.keyCode) == kVK_Escape { self.model.closeSettings(); return nil }
                return event
            }
            if Int(event.keyCode) == kVK_Space, !self.model.searchExpanded {
                self.model.inspectSelection(); return nil
            }
            switch Int(event.keyCode) {
            case kVK_Escape:
                if self.model.searchExpanded { self.model.query = ""; self.model.searchExpanded = false }
                else if self.model.openFolderID != nil { self.model.closeFolder() }
                else if self.model.editing { self.model.toggleEditing() }
                else { self.hidePanel(restorePrevious: true) }
            case kVK_Return, kVK_ANSI_KeypadEnter:
                if let result = self.model.inlineResult { self.model.performInlineResult(result) }
                else if let item = self.model.selectedItem, item.kind == .folder { self.model.open(item) }
                else if !self.model.editing, let app = self.model.selectedApp { self.launch(app) }
            case kVK_LeftArrow: self.model.moveSelection(by: -1)
            case kVK_RightArrow: self.model.moveSelection(by: 1)
            case kVK_UpArrow: self.model.moveSelection(by: -self.model.columnCount)
            case kVK_DownArrow: self.model.moveSelection(by: self.model.columnCount)
            case kVK_Tab: self.model.changePage(by: modifiers.contains(.shift) ? -1 : 1)
            case kVK_PageUp: self.model.changePage(by: -1)
            case kVK_PageDown: self.model.changePage(by: 1)
            default:
                if !self.model.searchExpanded, let text = event.characters, !text.isEmpty,
                   text.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) {
                    self.model.searchExpanded = true
                    self.model.query += text
                    self.model.focusGeneration += 1
                    return nil
                }
                return event
            }
            return nil
        }
    }

    private func applyAppearance() {
        if CommandLine.arguments.contains("--appearance-dark") { panel.appearance = NSAppearance(named: .darkAqua); return }
        if CommandLine.arguments.contains("--appearance-light") { panel.appearance = NSAppearance(named: .aqua); return }
        switch model.preferences.appearance {
        case .system: panel.appearance = nil
        case .light: panel.appearance = NSAppearance(named: .aqua)
        case .dark: panel.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private func resetPageMotion() {
        pagingToken = UUID()
        gestureEndWork?.cancel()
        gestureEndWork = nil
        gestureStarted = false
        pageGesture = PageGesture()
        pendingPageTarget = nil
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction) { model.pageDragOffset = 0; model.pageTransitionActive = false }
    }

    private func settlePageMotion(cancelled: Bool = false, explicitDelta: Int? = nil) {
        gestureEndWork?.cancel()
        gestureStarted = false
        let target = explicitDelta.map { min(max(0, model.pageIndex + $0), model.pageCount - 1) }
            ?? PageMotion.destination(distance: pageGesture.distance, page: model.pageIndex,
                                      count: model.pageCount, width: model.pageExtent, cancelled: cancelled, velocity: pageGesture.velocity)
        let direction = target - model.pageIndex
        let finalOffset = -CGFloat(direction) * model.pageExtent
        let token = UUID(); pagingToken = token
        model.pageTransitionActive = true
        pendingPageTarget = target
        let remaining = abs(finalOffset - model.pageDragOffset) / model.pageExtent
        let duration = preview && CommandLine.arguments.contains("--slow-page-animation") ? 2.0
            : min(0.18, max(0.10, 0.18 * Double(remaining)))
        let animated = model.preferences.animationsEnabled && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let finish: @MainActor @Sendable () -> Void = { [weak self] in
            guard let self, self.pagingToken == token else { return }
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) {
                self.model.goToPage(target)
                self.model.pageDragOffset = 0
                self.model.pageTransitionActive = false
            }
            self.pageGesture = PageGesture()
            self.pendingPageTarget = nil
        }
        if animated {
            withAnimation(.easeOut(duration: duration)) { model.pageDragOffset = finalOffset }
            DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: finish)
        } else { finish() }
    }

    private func finishPendingPage() {
        if let target = pendingPageTarget {
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) { model.goToPage(target) }
        }
        resetPageMotion()
    }

    private func configureGestures() {
        gestureMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .swipe]) { [weak self] event in
            guard let self else { return event }
            if event.type == .scrollWheel, event.window === self.panel {
                self.model.noteScrollInteraction()
            }
            if event.phase.contains(.began) { self.continuousScrollScaler.reset() }
            if self.panel.isKeyWindow, !self.model.showingSettings, !self.presentingSystemDialog,
               self.model.isContinuousScrolling, event.type == .scrollWheel,
               let source = event.cgEvent, let copy = self.continuousScrollScaler.adjusted(source, factor: self.model.preferences.gestureSensitivity) {
                return NSEvent(cgEvent: copy) ?? event
            }
            guard self.panel.isKeyWindow, !self.model.showingSettings,
                  !self.model.isContinuousScrolling, !self.model.usesFreePlacement,
                  self.model.preferences.swipeEnabled, self.model.draggingID == nil,
                  !self.presentingSystemDialog, self.model.pageCount > 1 else { return event }
            let preferences = self.model.preferences
            let horizontal = preferences.pagingDirection == .horizontal
            if event.type == .swipe {
                // The same trackpad gesture may also produce a swipe event after scroll-ended.
                guard !self.model.pageTransitionActive, !self.gestureStarted else { return nil }
                guard (horizontal ? abs(event.deltaX) >= abs(event.deltaY) : abs(event.deltaY) >= abs(event.deltaX)),
                      let delta = preferences.horizontalPageDelta(Double(horizontal ? event.deltaX : event.deltaY)) else { return event }
                self.resetPageMotion()
                self.model.pageMotion.axis = horizontal ? .horizontal : .vertical
                self.settlePageMotion(explicitDelta: delta)
                return nil
            }
            if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
                guard self.gestureStarted else { self.pageGesture = PageGesture(); return event }
                self.settlePageMotion(cancelled: event.phase.contains(.cancelled))
                return nil
            }
            // Some devices enter momentum without a separate finger-release event.
            if !event.momentumPhase.isEmpty {
                if self.gestureStarted { self.settlePageMotion() }
                return nil
            }
            let x = event.scrollingDeltaX, y = event.scrollingDeltaY
            guard x != 0 || y != 0 else { return event }
            if !event.hasPreciseScrollingDeltas {
                guard horizontal ? abs(x) >= abs(y) : abs(y) >= abs(x) else { return event }
                guard event.timestamp - self.lastDiscretePageTime > 0.14,
                      let delta = preferences.horizontalPageDelta(Double(horizontal ? x : y)) else { return nil }
                self.lastDiscretePageTime = event.timestamp
                self.finishPendingPage()
                self.model.pageMotion.axis = horizontal ? .horizontal : .vertical
                self.settlePageMotion(explicitDelta: delta)
                return nil
            }
            if event.phase.contains(.began) || (!self.gestureStarted && self.pendingPageTarget != nil) {
                // Complete the preceding page before accepting a rapid reverse gesture.
                self.finishPendingPage()
            }
            guard self.pageGesture.sample(x: x, y: y, time: event.timestamp,
                    verticalEnabled: true,
                    sensitivity: preferences.gestureSensitivity, reversed: preferences.reversePaging,
                    preferredAxis: horizontal ? .horizontal : .vertical) else { return event }
            let axis: PagePresentation.Axis = self.pageGesture.axis == .vertical ? .vertical : .horizontal
            if self.model.pageMotion.axis != axis { self.model.pageMotion.axis = axis }
            self.gestureStarted = true
            self.model.pageTransitionActive = true
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) {
                self.model.pageDragOffset = PageMotion.offset(distance: self.pageGesture.distance,
                    page: self.model.pageIndex, count: self.model.pageCount, width: self.model.pageExtent)
            }
            self.gestureEndWork?.cancel()
            // Devices without gesture phases get a short inactivity fallback, never momentum-length waiting.
            if event.phase.isEmpty {
                let work = DispatchWorkItem { [weak self] in self?.settlePageMotion() }
                self.gestureEndWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.045, execute: work)
            }
            return nil
        }
    }

    private func configureActions() {
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
            if abs(delta) == 1 { self.settlePageMotion(explicitDelta: delta) }
            else { self.model.goToPage(target) }
        }
        model.onPreferencesChanged = { [weak self] changes in
            guard let self else { return }
            if changes.contains(.appearance) { self.applyAppearance() }
            if changes.contains(.navigation) {
                self.resetPageMotion()
                self.model.pageMotion.axis = self.model.preferences.pagingDirection == .vertical ? .vertical : .horizontal
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

    private func registerHotKey() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated {
                Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue().togglePanel()
            }
            return noErr
        }, 1, &type, context, &hotKeyHandler)
        guard handlerStatus == noErr else { showHotKeyWarning(); return }
        let status = register(model.layout.shortcut)
        trace("hotkey registration status=\(status)")
        if status != noErr { showHotKeyWarning() }
    }

    private func register(_ shortcut: ShortcutBinding) -> OSStatus {
        let identifier = EventHotKeyID(signature: 0x4A514C52, id: 1)
        return RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, identifier,
            GetApplicationEventTarget(), UInt32(kEventHotKeyExclusive), &hotKey)
    }
    private func unregisterHotKey() {
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
    }
    private func updateShortcutLabels() {
        statusItem.button?.toolTip = "Aplo · \(model.shortcutLabel)"
        statusItem.menu?.items.first(where: { $0.action == nil && $0.title.hasPrefix(model.text("快捷键：")) })?.title =
            model.text("快捷键：\(model.shortcutLabel)")
    }
    private func restoreHotKey() {
        if hotKey == nil { model.shortcutAvailable = register(model.layout.shortcut) == noErr }
        updateShortcutLabels()
    }
    private func changeShortcut(_ shortcut: ShortcutBinding) -> Bool {
        guard shortcut.isValid else { model.message = "快捷键格式无效。"; restoreHotKey(); return false }
        let old = model.layout.shortcut
        unregisterHotKey()
        if register(shortcut) == noErr {
            if model.saveShortcut(shortcut) {
                model.shortcutAvailable = true
                model.message = "快捷键已设为 \(shortcut)。"
                updateShortcutLabels()
                return true
            }
            unregisterHotKey()
        } else { model.message = "快捷键已被其他应用占用，保留原设置。请换一个组合。" }
        model.shortcutAvailable = register(old) == noErr
        updateShortcutLabels()
        return false
    }

    private func showHotKeyWarning() {
        model.shortcutAvailable = false
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.model.message = "快捷键可能已被其他应用占用，请从菜单栏打开面板。"
            self.statusItem.button?.toolTip = "Aplo · 快捷键不可用，请点击菜单栏图标"
            self.showPanel(preservingMessage: true)
        }
    }

    @objc private func openFromMenu() { showPanel() }
    @objc private func refreshApplications() { model.requestRefresh(resetSearch: false) }
    @objc private func openSettingsFromMenu() { showPanel(); model.openSettings() }
    @objc private func quitApplication() { NSApp.terminate(nil) }

    func togglePanel() {
        if presentingSystemDialog || model.recordingShortcut { return }
        if panel.isVisible && !panel.isMiniaturized { hidePanel(restorePrevious: true) } else { showPanel() }
    }

    @objc private func toggleDisplayMode() {
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

    private func applyDisplayFrame(screen: NSScreen?) {
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

    private func screenIdentifier(_ screen: NSScreen) -> String {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue ?? "main"
    }
    private func saveCompactPosition() {
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

    private func updatePresentation() {
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

    private func restorePresentation() {
        if let previousPresentation { NSApp.presentationOptions = previousPresentation; self.previousPresentation = nil }
    }

    private func showPanel(preservingMessage: Bool = false) {
        trace("show visible=\(panel.isVisible) preserveMessage=\(preservingMessage)")
        let wasVisible = panel.isVisible && !panel.isMiniaturized
        if !panel.isVisible { previousApplication = NSWorkspace.shared.frontmostApplication }
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

    private func hidePanel(restorePrevious: Bool = false) {
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
        if !preview, model.preferences.dismissStyle == .outsideClick, !panel.isMiniaturized, !minimizingWindow, !updatingEntryVisibility, !presentingSystemDialog, !model.presentingAppearancePreview, panel.attachedSheet == nil, panel.isVisible { hidePanel() }
    }

    func applicationDidResignActive(_ notification: Notification) {
        DockMagnificationController.shared.reset()
        if !preview, model.preferences.dismissStyle == .outsideClick, !panel.isMiniaturized, !minimizingWindow, !updatingEntryVisibility, !presentingSystemDialog, !model.presentingAppearancePreview, panel.attachedSheet == nil { hidePanel() }
    }

    private func beginDialog() {
        if model.recordingShortcut { model.cancelRecording() }
        presentingSystemDialog = true
        panel.hidesOnDeactivate = false
    }
    private func endDialog() {
        presentingSystemDialog = false
        panel.hidesOnDeactivate = !preview && model.preferences.dismissStyle == .outsideClick
        panel.makeKeyAndOrderFront(nil)
    }
    private func confirmSystemCommand(_ command: SystemCommand) {
        guard !presentingSystemDialog, panel.attachedSheet == nil else { return }
        let alert = NSAlert(); alert.messageText = model.text(command.title)
        alert.informativeText = model.text(command.available ? command.explanation : "当前系统没有可用的锁屏工具。请按 Control＋Command＋Q 锁屏；Aplo 不会代为关闭显示器。")
        alert.alertStyle = command == .trash ? .warning : .informational
        // Cancellation is the default; an accidental Return must never empty Trash or sleep.
        let cancel = alert.addButton(withTitle: model.text("取消")); cancel.keyEquivalent = "\r"
        if command.available {
            let action = alert.addButton(withTitle: model.text(command.title)); action.keyEquivalent = ""
            action.hasDestructiveAction = command == .trash
        }
        beginDialog()
        alert.beginSheetModal(for: panel) { [weak self] response in
            guard let self else { return }
            self.endDialog()
            guard response == .alertSecondButtonReturn, command.available else { return }
            Task {
                do {
                    try await Task.detached(priority: .utility) { try ConfirmedSystemActions.run(command) }.value
                    self.model.message = command == .trash ? "本机废纸篓已清空。" : nil
                } catch { self.model.message = "操作未完成：\(error.localizedDescription)" }
            }
        }
    }

    private func confirmTrashApplication(_ app: InstalledApp) {
        guard !presentingSystemDialog, panel.attachedSheet == nil, !app.isSystemApplication,
              app.bundleIdentifier != AppCatalog.ownBundleIdentifier else { return }
        let alert = NSAlert(); alert.messageText = model.text("移至废纸篓…")
        alert.informativeText = "“\(app.name)”\n" + model.text("仅移动应用包，不删除个人数据。原分组与位置会按应用扫描结果更新。")
        alert.alertStyle = .warning
        let cancel = alert.addButton(withTitle: model.text("取消")); cancel.keyEquivalent = "\r"
        let remove = alert.addButton(withTitle: model.text("移至废纸篓")); remove.keyEquivalent = ""; remove.hasDestructiveAction = true
        beginDialog()
        alert.beginSheetModal(for: panel) { [weak self] response in
            guard let self else { return }; self.endDialog()
            guard response == .alertSecondButtonReturn else { return }
            Task {
                do {
                    try await Task.detached(priority: .utility) { try FileManager.default.trashItem(at: app.url, resultingItemURL: nil) }.value
                    self.model.requestRefresh(resetSearch: false); self.model.message = "应用已移至废纸篓。"
                } catch { self.model.message = "操作未完成：\(error.localizedDescription)" }
            }
        }
    }

    private func exportBackup() {
        let dialog = NSSavePanel()
        dialog.title = model.text("导出 Aplo 布局")
        dialog.nameFieldStringValue = model.preferences.language.isEnglish ? "Aplo-layout.json" : "Aplo布局.json"
        dialog.allowedContentTypes = [.json]
        beginDialog()
        dialog.beginSheetModal(for: panel) { [weak self] response in
            guard let self else { return }
            defer { self.endDialog() }
            guard response == .OK, let url = dialog.url else { return }
            do { try self.model.backupData().write(to: url, options: .atomic); self.model.message = "布局备份已导出。" }
            catch { self.model.message = "导出失败：\(error.localizedDescription)" }
        }
    }
    private func restoreBackup() {
        let dialog = NSOpenPanel()
        dialog.title = model.text("恢复 Aplo 布局")
        dialog.allowedContentTypes = [.json]
        dialog.canChooseDirectories = false
        dialog.allowsMultipleSelection = false
        beginDialog()
        dialog.beginSheetModal(for: panel) { [weak self] response in
            guard let self else { return }
            defer { self.endDialog() }
            guard response == .OK, let url = dialog.url else { return }
            self.startImport(url, legacy: false)
        }
    }
    private func importLegacy() {
        let dialog = NSOpenPanel()
        dialog.title = model.text("选择旧版 Launchpad 数据库或备份")
        dialog.message = model.text("支持 db、.db、.lmy 和含旧数据库的 .zip。单独选择 db 时，请保留同目录的 db-wal / db-shm。")
        dialog.canChooseDirectories = false
        dialog.allowsMultipleSelection = false
        beginDialog()
        dialog.beginSheetModal(for: panel) { [weak self] response in
            guard let self else { return }
            defer { self.endDialog() }
            guard response == .OK, let url = dialog.url else { return }
            self.startImport(url, legacy: true)
        }
    }
    private func importNative() {
        let candidates = LegacySources.discover()
        guard !candidates.isEmpty else {
            model.message = "没有找到本机旧布局。可选择旧电脑的数据库或备份；默认预设不能恢复你的个人排列。"
            return
        }
        guard candidates.count == 1 else {
            model.message = "找到多个旧数据库，请在文件选择框中指定要导入的文件。"
            importLegacy()
            return
        }
        startImport(candidates[0], legacy: true)
    }
    private func startImport(_ url: URL, legacy: Bool) {
        guard !model.importInProgress else { return }
        let control = LegacyReadControl()
        importControl = control
        model.importInProgress = true
        model.message = "正在读取备份，可取消；完成前不会覆盖现有布局。"
        importTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.model.importInProgress = false; self.importTask = nil; self.importControl = nil }
            do {
                try await self.model.ensureInventoryForImport()
                try Task.checkCancellation()
                let apps = self.model.apps
                let worker = Task.detached(priority: .userInitiated) { () throws -> PreparedLayoutImport in
                    try control.check()
                    if legacy { return .legacy(try LegacySources.read(url, apps: apps, control: control)) }
                    return .backup(try LayoutStore.read(url))
                }
                let prepared = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel(); control.cancel() })
                try Task.checkCancellation()
                switch prepared {
                case .backup(let candidate):
                    try self.model.restore(candidate)
                    if candidate.shortcut != self.model.layout.shortcut {
                        if self.changeShortcut(candidate.shortcut) { self.model.message = "布局和快捷键已恢复，原布局已自动备份。" }
                        else { self.model.message = "布局已恢复；备份快捷键不可用，保留当前快捷键。原布局已自动备份。" }
                    } else { self.model.message = "布局已恢复，原布局已自动备份。" }
                case .legacy(let result):
                    try self.model.restore(result.layout)
                    self.model.message = "已导入 \(result.matchedCount) 个应用，跳过 \(result.skippedCount) 个未安装项目；原布局已备份。"
                }
            } catch is CancellationError { self.model.message = "导入已取消，现有布局未改变。" }
            catch { self.model.message = .verbatim(error.localizedDescription) }
        }
    }

    private func launch(_ app: InstalledApp) {
        trace("launch \(app.url.path)")
        guard FileManager.default.fileExists(atPath: app.url.path) else {
            model.requestRefresh(resetSearch: false)
            model.message = "“\(app.name)”已被移动或卸载，列表已刷新。"
            return
        }
        if model.preferences.launchAutoHide { hidePanel() }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: app.url, configuration: configuration) { [weak self] _, error in
            if CommandLine.arguments.contains("--diagnostics") {
                FileHandle.standardError.write(Data(("[Aplo] launch result: \(String(describing: error))\n").utf8))
            }
            guard error != nil else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.model.message = "无法打开“\(app.name)”，请检查应用是否完整或有权限运行。"
                self.showPanel(preservingMessage: true)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        trace("reopen visible=\(panel.isVisible) flag=\(flag)")
        if !panel.isVisible || panel.isMiniaturized { showPanel() }
        else { panel.makeKeyAndOrderFront(nil) }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        trace("terminate flushing preferences")
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
