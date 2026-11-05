import SwiftUI

struct LauncherEmptyState: View {
    @ObservedObject var model: LauncherModel
    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(model.accentColor.opacity(0.10)).frame(width: 76, height: 76)
                if model.initialDiscoveryPending { ProgressView() }
                else { Image(systemName: model.inlineResult != nil ? "equal" : "magnifyingglass").font(.system(size: 28, weight: .light)).foregroundStyle(model.accentColor) }
            }
            Text(model.text(model.initialDiscoveryPending ? "正在查找应用…" : model.inlineResult != nil ? "结果显示在上方" : model.isSearching ? "没有匹配的应用" : "没有找到已安装的应用"))
                .font(.system(size: model.preferences.textPoints(17), weight: .semibold))
            if !model.initialDiscoveryPending && model.inlineResult == nil {
                if model.searchCategory != nil {
                    Button(model.text("清除分类筛选")) { model.selectSearchCategory(nil) }
                }
                Text(model.text(model.isSearching ? "换个名称、拼音或首字母试试。" : "安装应用后会自动出现，也可以手动刷新。"))
                    .font(.system(size: model.preferences.textPoints(12))).foregroundStyle(.secondary).multilineTextAlignment(.center)
                HStack(spacing: 8) {
                    example("= 2+3", title: "算式")
                    example("sleep", title: "休眠")
                    example("lock", title: "锁屏")
                }
                Text(model.text("系统指令执行前需要确认；锁屏可使用 ⌃⌘Q。"))
                    .font(.caption).foregroundStyle(.secondary)
                if !model.isSearching { Button(model.text("刷新列表")) { model.requestRefresh(resetSearch: false) } }
            }
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private func example(_ query: String, title: String) -> some View {
        Button { model.searchExpanded = true; model.query = query; model.focusGeneration += 1 } label: {
            VStack(spacing: 4) { Text(query).font(.system(.callout, design: .monospaced)); Text(model.text(title)).font(.caption).foregroundStyle(.secondary) }
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain)
    }
}
