import AppKit
import SwiftUI

struct HiddenApplicationsView: View {
    @ObservedObject var model: LauncherModel
    @State private var query = ""
    @State private var onlyHidden = false
    private var applications: [(String, String)] {
        let missing = model.preferences.hiddenAppIDs.subtracting(model.apps.map(\.id)).sorted().map { ($0, $0) }
        return (model.apps.map { ($0.id, $0.name) } + missing).filter { (!onlyHidden || model.preferences.hiddenAppIDs.contains($0.0)) && (query.isEmpty || $0.1.localizedCaseInsensitiveContains(query)) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.text("隐藏仅影响显示和搜索，原分组及位置会保留。"))
                .font(.callout).foregroundStyle(.secondary)
            TextField(model.text("搜索应用"), text: $query).textFieldStyle(.roundedBorder)
            HStack {
                Text(model.text("隐藏应用") + "：\(model.preferences.hiddenAppIDs.count)").foregroundStyle(.secondary)
                Spacer()
                Toggle(model.text("仅看已隐藏"), isOn: $onlyHidden).toggleStyle(.checkbox)
                Button(model.text("显示全部应用")) { model.showAllApplications() }.disabled(model.preferences.hiddenAppIDs.isEmpty || model.importInProgress)
            }
            LazyVStack(spacing: 8) {
                ForEach(applications, id: \.0) { id, name in
                    HStack {
                        if let app = model.app(for: id) { PreviewAppIcon(model: model, app: app).frame(width: 28, height: 28) }
                        else { Image(systemName: "app.dashed").frame(width: 28, height: 28).foregroundStyle(.secondary) }
                        Text(name).lineLimit(1)
                        Spacer()
                        Button(model.text(model.preferences.hiddenAppIDs.contains(id) ? "显示应用" : "隐藏应用")) {
                            model.setAppHidden(id, hidden: !model.preferences.hiddenAppIDs.contains(id))
                        }.disabled(model.importInProgress)
                    }.padding(.vertical, 5)
                }
            }
        }
    }
}

struct BackupHistoryView: View {
    @ObservedObject var model: LauncherModel
    @State private var records: [LayoutBackupRecord] = []
    @State private var preview: LayoutBackupRecord?
    @State private var cleaning = false
    @State private var busy = false
    @State private var status = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button(model.text("保存快照")) { saveSnapshot() }
                Button(model.text("刷新列表")) { Task { await reload() } }
                Spacer()
                Button(model.text("清理旧自动备份")) { cleaning = true }
                    .disabled(records.filter(\.automatic).count <= 20)
            }.disabled(busy || model.importInProgress)
            Text(model.text("保留最近 20 份自动备份；手动快照不参与清理。旧备份移至废纸篓。"))
                .font(.callout).foregroundStyle(.secondary)
            if !status.isEmpty { Text(status).font(.callout).foregroundStyle(.secondary) }
            if records.isEmpty { Text(model.text("暂无备份历史")).foregroundStyle(.secondary) }
            LazyVStack(spacing: 10) {
                ForEach(records) { record in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack { Text(record.date, style: .date); Text(record.date, style: .time) }
                            Text(model.text(record.automatic ? "自动备份" : "手动备份") + " · " + ByteCountFormatter.string(fromByteCount: Int64(record.bytes), countStyle: .file))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(model.text("预览与恢复")) { preview = record }.disabled(model.importInProgress)
                    }
                }
            }
        }
        .task { await reload() }
        .onChange(of: model.importInProgress) { importing in if !importing { Task { await reload() } } }
        .sheet(item: $preview) { record in BackupPreviewView(model: model, record: record) }
        .confirmationDialog(model.text("清理旧自动备份"), isPresented: $cleaning) {
            Button(model.text("移至废纸篓"), role: .destructive) {
                busy = true
                let store = model.store
                Task {
                    do {
                        try await Task.detached(priority: .utility) {
                            for record in try store.automaticHistoryToClean() {
                                try Task.checkCancellation()
                                try FileManager.default.trashItem(at: record.url, resultingItemURL: nil)
                            }
                        }.value
                        status = model.text("旧自动备份已移至废纸篓。")
                    } catch { status = error.localizedDescription }
                    await reload(); busy = false
                }
            }
            Button(model.text("取消"), role: .cancel) {}
        }
    }
    private func reload() async {
        let store = model.store
        do { records = try await Task.detached(priority: .utility) { try store.history() }.value }
        catch { status = error.localizedDescription }
    }
    private func saveSnapshot() {
        busy = true
        Task {
            do {
                let data = try model.backupData(), store = model.store
                try await Task.detached(priority: .utility) { try store.saveManualBackup(data) }.value
                status = model.text("手动快照已保存。")
            } catch { status = error.localizedDescription }
            await reload(); busy = false
        }
    }
}

private struct BackupPreviewView: View {
    @ObservedObject var model: LauncherModel
    let record: LayoutBackupRecord
    @Environment(\.dismiss) private var dismiss
    @State private var layout: LauncherLayout?
    @State private var failure: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(model.text("备份预览")).font(.title2.bold())
            HStack { Text(record.date, style: .date); Text(record.date, style: .time) }
            Text(record.id).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            if let layout {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        profile(layout.displayProfile, title: model.text(layout.activeLayoutIsFullscreen == true ? "全屏布局" : "小窗口布局"))
                        if let other = layout.otherDisplayLayout {
                            profile(other, title: model.text(layout.activeLayoutIsFullscreen == true ? "小窗口布局" : "全屏布局"))
                        }
                    }
                }.frame(minHeight: 260, maxHeight: .infinity)
            } else if let failure { Text(failure).foregroundStyle(.secondary) }
            else { ProgressView() }
            Text(model.text("恢复前会自动备份当前布局；扫描不完整时不会覆盖。"))
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Button(model.text("取消")) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(model.text("恢复此备份")) { model.onRestoreHistory?(record.url); dismiss() }
                    .disabled(layout == nil || model.importInProgress || model.onRestoreHistory == nil)
            }
        }.padding(24).frame(minWidth: 520, idealWidth: 600, maxWidth: .infinity, minHeight: 500, idealHeight: 620, maxHeight: .infinity)
        .background(ResizableSheet(minimum: NSSize(width: 520, height: 500)))
        .overlay(alignment: .bottomTrailing) {
            WindowResizeHandle().frame(width: 22, height: 22)
                .background { Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 9)).foregroundStyle(.secondary).allowsHitTesting(false) }
                .padding(3).help(model.text("拖动右下角调整窗口大小"))
        }
        .task(id: record.id) {
            let file = record.url
            let read = Task.detached(priority: .utility) { try LayoutStore.read(file) }
            do {
                let value = try await withTaskCancellationHandler(operation: { try await read.value }, onCancel: { read.cancel() })
                try Task.checkCancellation(); layout = value
            } catch is CancellationError {} catch { failure = error.localizedDescription }
        }
    }
    private func profile(_ profile: DisplayLayoutProfile, title: String) -> some View {
        let items = profile.pages.flatMap { $0 }
        let folders = items.filter { $0.kind == .folder }
        let count = items.reduce(0) { $0 + ($1.kind == .folder ? $1.children.count : 1) }
        return VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text("\(count) " + model.text("个应用") + " · \(folders.count) " + model.text("个文件夹") + " · \(profile.pages.count) " + model.text("页"))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 5) {
                ForEach(Array(items.prefix(6))) { item in
                    if item.kind == .folder { Text("▦ " + (item.title ?? model.text("新建文件夹")) + " (\(item.children.count))").lineLimit(1) }
                    else { Text(model.app(for: item.appID ?? "")?.name ?? item.appID ?? item.id).lineLimit(1) }
                }
            }.font(.callout)
            if items.count > 6 { Text("…").foregroundStyle(.secondary) }
        }
    }
}

/// SwiftUI sheets inherit a fitted size unless their host explicitly permits resizing.
struct ResizableSheet: NSViewRepresentable {
    var minimum: NSSize
    func makeNSView(context: Context) -> NSView { let view = SheetResizeView(); view.minimum = minimum; return view }
    func updateNSView(_ view: NSView, context: Context) {}
}
private final class SheetResizeView: NSView {
    var minimum = NSSize(width: 520, height: 500)
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.styleMask.insert(.resizable)
        window?.contentMinSize = minimum
        window?.minSize = minimum
    }
}
