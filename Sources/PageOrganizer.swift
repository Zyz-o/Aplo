import SwiftUI
import UniformTypeIdentifiers

private let pageOrderType = UTType(exportedAs: "local.jianqi.layout-page")
struct PageOrganizer: View {
    @ObservedObject var model: LauncherModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(model.text("页面顺序")).font(.title2.bold())
                Spacer(); Button(model.text("完成")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
            Text(model.text("拖动整页调整顺序，也可使用箭头。只修改当前窗口模式的布局，支持撤销。"))
                .foregroundStyle(.secondary)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180))], spacing: 16) {
                    ForEach(Array(model.layout.pages.enumerated()), id: \.offset) { index, page in
                        VStack(spacing: 10) {
                            HStack {
                                Text(model.pageTitle(index)).font(.headline)
                                Spacer(); Text("\(page.count)").foregroundStyle(.secondary)
                            }
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                                ForEach(page.prefix(6)) { item in
                                    if let app = item.appID.flatMap({ model.app(for: $0) }) ?? item.children.first.flatMap({ model.app(for: $0) }) {
                                        PagePreviewIcon(model: model, app: app)
                                    } else { Image(systemName: "square.grid.2x2").frame(width: 36, height: 36) }
                                }
                            }.frame(height: 88)
                            HStack {
                                Button { model.movePage(identifiedBy: page.map(\.id), to: index - 1) } label: { Image(systemName: "arrow.left") }
                                    .disabled(index == 0).accessibilityLabel(model.text("向前移动页面"))
                                Spacer()
                                Button { model.movePage(identifiedBy: page.map(\.id), to: index + 1) } label: { Image(systemName: "arrow.right") }
                                    .disabled(index + 1 == model.layout.pages.count).accessibilityLabel(model.text("向后移动页面"))
                            }
                        }.padding(14).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
                            .onDrag {
                                let provider = NSItemProvider()
                                let data = (try? JSONEncoder().encode(page.map(\.id))) ?? Data()
                                provider.registerDataRepresentation(forTypeIdentifier: pageOrderType.identifier, visibility: .ownProcess) { completion in
                                    completion(data, nil); return nil
                                }
                                return provider
                            }
                            .onDrop(of: [pageOrderType], isTargeted: nil) { providers in
                                guard let provider = providers.first else { return false }
                                provider.loadDataRepresentation(forTypeIdentifier: pageOrderType.identifier) { data, _ in
                                    guard let data, data.count < 32768, let ids = try? JSONDecoder().decode([String].self, from: data) else { return }
                                    Task { @MainActor in model.movePage(identifiedBy: ids, to: index) }
                                }
                                return true
                            }
                    }
                }.padding(4)
            }
        }.padding(24).frame(minWidth: 600, idealWidth: 700, minHeight: 460, idealHeight: 540)
    }
}

private struct PagePreviewIcon: View {
    let model: LauncherModel
    let app: InstalledApp
    @ObservedObject private var feedback: TileDragFeedback
    init(model: LauncherModel, app: InstalledApp) {
        self.model = model; self.app = app; feedback = model.dragFeedback(for: "app:" + app.id)
    }
    var body: some View {
        Image(nsImage: model.icon(for: app, notifying: feedback)).resizable().interpolation(.high).frame(width: 36, height: 36)
    }
}
