import AppKit
import Carbon
import SwiftUI
import QuartzCore
import UniformTypeIdentifiers

private enum PreparedLayoutImport: Sendable {
    case backup(LauncherLayout)
    case legacy(LegacyImportResult)
}

extension AppDelegate {
    func beginDialog() {
        if model.recordingShortcut { model.cancelRecording() }
        presentingSystemDialog = true
        panel.hidesOnDeactivate = false
    }

    func endDialog() {
        presentingSystemDialog = false
        panel.hidesOnDeactivate = !preview && model.preferences.dismissStyle == .outsideClick
        interactionWindow.makeKeyAndOrderFront(nil)
    }

    func confirmSystemCommand(_ command: SystemCommand) {
        guard !presentingSystemDialog, interactionWindow.attachedSheet == nil else { return }
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
        alert.beginSheetModal(for: interactionWindow) { [weak self] response in
            guard let self else { return }
            self.endDialog()
            guard response == .alertSecondButtonReturn, command.available else { return }
            Task {
                do {
                    try await Task.detached(priority: .utility) { try ConfirmedSystemActions.run(command) }.value
                    self.model.message = command == .trash ? .notice("本机废纸篓已清空。") : nil
                } catch { self.model.message = "操作未完成：\(error.localizedDescription)" }
            }
        }
    }

    func confirmTrashApplication(_ app: InstalledApp) {
        guard !presentingSystemDialog, interactionWindow.attachedSheet == nil, !app.isSystemApplication,
              app.bundleIdentifier != AppCatalog.ownBundleIdentifier else { return }
        let alert = NSAlert(); alert.messageText = model.text("移至废纸篓…")
        alert.informativeText = "“\(app.name)”\n" + model.text("仅移动应用包，不删除个人数据。原分组与位置会按应用扫描结果更新。")
        alert.alertStyle = .warning
        let cancel = alert.addButton(withTitle: model.text("取消")); cancel.keyEquivalent = "\r"
        let remove = alert.addButton(withTitle: model.text("移至废纸篓")); remove.keyEquivalent = ""; remove.hasDestructiveAction = true
        beginDialog()
        alert.beginSheetModal(for: interactionWindow) { [weak self] response in
            guard let self else { return }; self.endDialog()
            guard response == .alertSecondButtonReturn else { return }
            Task {
                do {
                    try await Task.detached(priority: .utility) { try FileManager.default.trashItem(at: app.url, resultingItemURL: nil) }.value
                    self.model.requestRefresh(resetSearch: false); self.model.message = .notice("应用已移至废纸篓。")
                } catch { self.model.message = "操作未完成：\(error.localizedDescription)" }
            }
        }
    }

    func exportBackup() {
        let dialog = NSSavePanel()
        dialog.title = model.text("导出 Aplo 布局")
        dialog.nameFieldStringValue = model.preferences.language.isEnglish ? "Aplo-layout.json" : "Aplo布局.json"
        dialog.allowedContentTypes = [.json]
        beginDialog()
        dialog.beginSheetModal(for: interactionWindow) { [weak self] response in
            guard let self else { return }
            defer { self.endDialog() }
            guard response == .OK, let url = dialog.url else { return }
            do { try self.model.backupData().write(to: url, options: .atomic); self.model.message = .notice("布局备份已导出。") }
            catch { self.model.message = "导出失败：\(error.localizedDescription)" }
        }
    }

    func restoreBackup() {
        let dialog = NSOpenPanel()
        dialog.title = model.text("恢复 Aplo 布局")
        dialog.allowedContentTypes = [.json]
        dialog.canChooseDirectories = false
        dialog.allowsMultipleSelection = false
        beginDialog()
        dialog.beginSheetModal(for: interactionWindow) { [weak self] response in
            guard let self else { return }
            defer { self.endDialog() }
            guard response == .OK, let url = dialog.url else { return }
            self.startImport(url, legacy: false)
        }
    }

    func importLegacy() {
        let dialog = NSOpenPanel()
        dialog.title = model.text("选择旧版 Launchpad 数据库或备份")
        dialog.message = model.text("支持 db、.db、.lmy 和含旧数据库的 .zip。单独选择 db 时，请保留同目录的 db-wal / db-shm。")
        dialog.canChooseDirectories = false
        dialog.allowsMultipleSelection = false
        beginDialog()
        dialog.beginSheetModal(for: interactionWindow) { [weak self] response in
            guard let self else { return }
            defer { self.endDialog() }
            guard response == .OK, let url = dialog.url else { return }
            self.startImport(url, legacy: true)
        }
    }

    func importNative() {
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

    func startImport(_ url: URL, legacy: Bool) {
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
                        if self.changeShortcut(candidate.shortcut) { self.model.message = .notice("布局和快捷键已恢复，原布局已自动备份。") }
                        else { self.model.message = "布局已恢复；备份快捷键不可用，保留当前快捷键。原布局已自动备份。" }
                    } else { self.model.message = .notice("布局已恢复，原布局已自动备份。") }
                case .legacy(let result):
                    try self.model.restore(result.layout)
                    self.model.message = .notice("已导入 \(result.matchedCount) 个应用，跳过 \(result.skippedCount) 个未安装项目；原布局已备份。")
                }
            } catch is CancellationError { self.model.message = "导入已取消，现有布局未改变。" }
            catch { self.model.message = .verbatim(error.localizedDescription) }
        }
    }
}
