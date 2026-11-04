import AppKit
import Carbon
import SwiftUI
import QuartzCore
import UniformTypeIdentifiers

extension AppDelegate {
    @objc func undoOrganizationAction(_ sender: Any?) {
        if editingText { textUndoManager?.undo() } else { model.undoOrganization() }
    }

    @objc func redoOrganizationAction(_ sender: Any?) {
        if editingText { textUndoManager?.redo() } else { model.redoOrganization() }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(undoOrganizationAction) { return editingText ? (textUndoManager?.canUndo ?? false) : (model.canUndoOrganization && !model.importInProgress && model.draggingID == nil) }
        if item.action == #selector(redoOrganizationAction) { return editingText ? (textUndoManager?.canRedo ?? false) : (model.canRedoOrganization && !model.importInProgress && model.draggingID == nil) }
        return true
    }

    func configureKeyboard() {
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
                let labels: [Int: String] = [kVK_Space: "Space", kVK_Return: "Return", kVK_ANSI_KeypadEnter: "Return", kVK_F4: "F4", kVK_Tab: "Tab",
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
                if self.model.multiSelectionActive, let item = self.model.selectedItem { self.model.toggleItemSelection(item) }
                else { self.model.inspectSelection() }
                return nil
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

    func registerHotKey() {
        // Experimental comparison builds must not steal the global shortcut from the
        // main Aplo instance that is already running.
        if CommandLine.arguments.contains("--native-scroll-comparison") {
            trace("hotkey registration skipped for experimental build")
            return
        }
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
        registerAlternateHotKey()
    }

    func register(_ shortcut: ShortcutBinding) -> OSStatus {
        let identifier = EventHotKeyID(signature: 0x4A514C52, id: 1)
        return RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, identifier,
            GetApplicationEventTarget(), UInt32(kEventHotKeyExclusive), &hotKey)
    }

    func registerAlternateHotKey() {
        if let alternateHotKey { UnregisterEventHotKey(alternateHotKey); self.alternateHotKey = nil }
        model.f4ShortcutAvailable = true
        guard model.preferences.f4ShortcutEnabled, !model.recordingShortcut, hotKeyHandler != nil else { return }
        let status = RegisterEventHotKey(UInt32(kVK_F4), 0, EventHotKeyID(signature: 0x4A514C52, id: 2),
            GetApplicationEventTarget(), UInt32(kEventHotKeyExclusive), &alternateHotKey)
        model.f4ShortcutAvailable = status == noErr
        if status != noErr { model.message = "F4 已被占用，请继续使用原快捷键或菜单栏入口。" }
    }

    func unregisterHotKey() {
        if let alternateHotKey { UnregisterEventHotKey(alternateHotKey); self.alternateHotKey = nil }
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
    }

    func updateShortcutLabels() {
        statusItem.button?.toolTip = "Aplo · \(model.shortcutLabel)"
        statusItem.menu?.items.first(where: { $0.action == nil && $0.title.hasPrefix(model.text("快捷键：")) })?.title =
            model.text("快捷键：\(model.shortcutLabel)")
    }

    func restoreHotKey() {
        if hotKey == nil { model.shortcutAvailable = register(model.layout.shortcut) == noErr }
        registerAlternateHotKey(); updateShortcutLabels()
    }

    func changeShortcut(_ shortcut: ShortcutBinding) -> Bool {
        guard shortcut.isValid else { model.message = "快捷键格式无效。"; restoreHotKey(); return false }
        let old = model.layout.shortcut
        unregisterHotKey()
        if register(shortcut) == noErr {
            if model.saveShortcut(shortcut) {
                model.shortcutAvailable = true
                model.message = .notice("快捷键已设为 \(shortcut)。")
                registerAlternateHotKey(); updateShortcutLabels()
                return true
            }
            unregisterHotKey()
        } else { model.message = "快捷键已被其他应用占用，保留原设置。请换一个组合。" }
        model.shortcutAvailable = register(old) == noErr
        registerAlternateHotKey(); updateShortcutLabels()
        return false
    }

    func showHotKeyWarning() {
        model.shortcutAvailable = false
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.model.message = "快捷键可能已被其他应用占用，请从菜单栏打开面板。"
            self.statusItem.button?.toolTip = "Aplo · 快捷键不可用，请点击菜单栏图标"
            self.showPanel(preservingMessage: true)
        }
    }
}
