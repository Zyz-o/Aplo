import AppKit
import SwiftUI

struct TileDropModifier: ViewModifier {
    let model: LauncherModel
    let target: LayoutItem
    let width: CGFloat
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled {
            content.onDrop(of: [launcherDragType], delegate: TileDropDelegate(model: model, target: target, width: width))
        } else {
            content
        }
    }
}

struct TileContextMenuModifier: ViewModifier {
    let model: LauncherModel
    let item: LayoutItem
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled {
            content.contextMenu {
                TileContextMenu(model: model, item: item)
            }
        } else {
            content
        }
    }
}

private struct TileContextMenu: View {
    let model: LauncherModel
    let item: LayoutItem
    var body: some View {
        if model.preferences.automaticCategories {
            if let appID = item.appID, let app = model.app(for: appID) {
                Button(model.text("在访达中显示")) { NSWorkspace.shared.activateFileViewerSelecting([app.url]) }
            }
            Button(model.text("分类与排列设置")) { model.openSettings() }
        } else if item.kind == .folder {
            Button(model.text("重命名")) { model.beginRename(item) }
            Button(model.text("解散文件夹")) { model.dissolve(item.id) }
        } else if let appID = item.appID {
            if let app = model.app(for: appID) {
                Button(model.text("在访达中显示")) { NSWorkspace.shared.activateFileViewerSelecting([app.url]) }
                Divider()
            }
            if model.layout.folders.contains(where: { $0.children.contains(appID) }) {
                Button(model.text("移出文件夹")) { model.moveApp(appID, toFolder: nil) }
            } else {
                Button(model.text("新建文件夹")) { model.createFolder(containing: appID) }
            }
            if !model.layout.folders.isEmpty {
                Menu(model.text("移入文件夹")) {
                    ForEach(model.layout.folders.filter { $0.id != model.openFolderID }) { folder in
                        Button(model.name(for: folder)) { model.moveApp(appID, toFolder: folder.id) }
                    }
                }
            }
        }
        if let appID = item.appID {
            Divider()
            Button(model.text("隐藏应用")) { model.setAppHidden(appID, hidden: true) }
            if let app = model.app(for: appID) {
                Divider()
                Button(model.text("应用速览")) { model.inspectingApp = app }
                Button(model.text("显示包内容")) { NSWorkspace.shared.open(app.url.appendingPathComponent("Contents", isDirectory: true)) }
                Button(model.text("拷贝路径")) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(app.url.path, forType: .string) }
                Button(model.text("在终端中打开所在目录")) {
                    NSWorkspace.shared.open([app.url.deletingLastPathComponent()], withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"), configuration: NSWorkspace.OpenConfiguration())
                }
                Button(model.text(model.preferences.uninstallerPath.isEmpty ? "移至废纸篓…" : "使用卸载工具…"), role: .destructive) { model.onTrashApplication?(app) }
                    .disabled(app.isSystemApplication || app.bundleIdentifier == AppCatalog.ownBundleIdentifier)
            }
        }
    }
}

private struct TileDropDelegate: DropDelegate {
    let model: LauncherModel
    let target: LayoutItem
    let width: CGFloat
    func validateDrop(info: DropInfo) -> Bool {
        model.canOrganize && !model.usesFreePlacement && model.draggingID != target.id
            && info.hasItemsConforming(to: [launcherDragType])
    }
    private func position(_ info: DropInfo) -> ItemDropPosition {
        if info.location.x < width * 0.26 { return .before }
        if info.location.x > width * 0.74 { return .after }
        if model.openFolderID == nil, target.kind == .folder || model.draggingID?.hasPrefix("app:") == true { return .center }
        return info.location.x < width / 2 ? .before : .after
    }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard validateDrop(info: info) else { return DropProposal(operation: .forbidden) }
        let p = position(info)
        let hint: String
        if p == .center && model.openFolderID == nil {
            hint = target.kind == .folder ? "松开移入文件夹" : "松开组成文件夹"
        } else { hint = p == .after ? "松开放在后面" : "松开放在前面" }
        model.updateDropTarget(target.id, hint: hint, indicator: p == .center ? .merge : p == .before ? .before : .after)
        return DropProposal(operation: .move)
    }
    func dropExited(info: DropInfo) {
        model.clearDropTarget(target.id)
    }
    func performDrop(info: DropInfo) -> Bool {
        guard validateDrop(info: info) else { return false }
        let position = position(info)
        if let source = model.draggingID { model.drop(source, onto: target.id, position: position) }
        else if let provider = info.itemProviders(for: [launcherDragType]).first {
            let model = model
            let target = target.id
            provider.loadDataRepresentation(forTypeIdentifier: launcherDragType.identifier) { data, _ in
                guard let data, data.count < 4096, let source = String(data: data, encoding: .utf8) else { return }
                Task { @MainActor in model.drop(source, onto: target, position: position) }
            }
        } else { return false }
        return true
    }
}
