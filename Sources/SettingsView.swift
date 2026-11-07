import AppKit
import SwiftUI

enum SettingsCategory: String, CaseIterable {
    case general, appearance, layout, shortcuts, sound, hidden, backup, updates, about
    static var allCases: [Self] { [.general, .appearance, .layout, .shortcuts, .hidden, .backup, .updates] }
    var title: String {
        switch self {
        case .layout: return "布局"
        case .general: return "通用"
        case .appearance: return "外观"
        case .shortcuts: return "操作"
        case .sound: return "声音"
        case .hidden: return "应用管理"
        case .backup: return "备份与恢复"
        case .updates: return "更新与关于"
        case .about: return "关于"
        }
    }
    var icon: String {
        switch self {
        case .layout: return "square.grid.3x3"
        case .general: return "gearshape"
        case .appearance: return "paintbrush"
        case .shortcuts: return "keyboard"
        case .sound: return "speaker.wave.2"
        case .hidden: return "eye.slash"
        case .backup: return "clock.arrow.circlepath"
        case .updates: return "sparkles"
        case .about: return "info.circle"
        }
    }

}

@MainActor private enum ApplicationFontCatalog {
    static let families = NSFontManager.shared.availableFontFamilies.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
}
struct SettingsView: View {
    @ObservedObject var model: LauncherModel
    @State private var category: SettingsCategory = .general
    @State private var legacyExpanded = false
    @State private var scalePreview = false
    @State private var settingsQuery = ""
    @State private var resettingPage = false
    @State private var highlightedSection: String?
    @State private var highlightTask: Task<Void, Never>?
    @State private var previewExpanded = true
    @State private var settingsWidth: CGFloat = 960
    private struct SearchResult {
        let title: String
        let category: SettingsCategory
        let section: String
    }
    private var searchResults: [SearchResult] {
        let query = settingsQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return [
            SearchResult(title: "显示方式", category: .general, section: "显示方式"),
            SearchResult(title: "固定在当前桌面", category: .general, section: "固定在当前桌面"),
            SearchResult(title: "启动后自动收起", category: .general, section: "启动后自动收起"),
            SearchResult(title: "程序坞与语言", category: .general, section: "程序坞与语言"),
            SearchResult(title: "背景与文字", category: .appearance, section: "背景与文字"),
            SearchResult(title: "背景透明度", category: .appearance, section: "背景透明度"),
            SearchResult(title: "显示应用名称", category: .appearance, section: "显示应用名称"),
            SearchResult(title: "主题", category: .appearance, section: "主题"),
            SearchResult(title: "应用名称样式", category: .appearance, section: "应用名称样式"),
            SearchResult(title: "顶部标识", category: .appearance, section: "顶部标识"),
            SearchResult(title: "色盲友好", category: .appearance, section: "色盲友好"),
            SearchResult(title: "大小", category: .layout, section: "大小"),
            SearchResult(title: "布局预览", category: .layout, section: "大小"),
            SearchResult(title: "调整大小与对比…", category: .layout, section: "大小"),
            SearchResult(title: "图标大小", category: .layout, section: "图标大小"),
            SearchResult(title: "文字大小", category: .layout, section: "文字大小"),
            SearchResult(title: "移动与排列", category: .layout, section: "移动与排列"),
            SearchResult(title: "网格密度", category: .layout, section: "网格密度"),
            SearchResult(title: "小窗口", category: .layout, section: "网格密度"),
            SearchResult(title: "全屏", category: .layout, section: "网格密度"),
            SearchResult(title: "呼出快捷键", category: .shortcuts, section: "呼出快捷键"),
            SearchResult(title: "F4 备选呼出键", category: .shortcuts, section: "F4 备选呼出键"),
            SearchResult(title: "启用 F4 呼出", category: .shortcuts, section: "启用 F4 呼出"),
            SearchResult(title: "屏幕热角", category: .shortcuts, section: "屏幕热角"),
            SearchResult(title: "浏览与滚动", category: .shortcuts, section: "浏览与滚动"),
            SearchResult(title: "启用滑动翻页", category: .shortcuts, section: "启用滑动翻页"),
            SearchResult(title: "反向翻页", category: .shortcuts, section: "反向翻页"),
            SearchResult(title: "文件夹浏览", category: .shortcuts, section: "文件夹浏览"),
            SearchResult(title: "外观与行为", category: .shortcuts, section: "外观与行为"),
            SearchResult(title: "图标悬停放大", category: .shortcuts, section: "图标悬停放大"),
            SearchResult(title: "界面动画", category: .shortcuts, section: "界面动画"),
            SearchResult(title: "整理时轻晃图标", category: .shortcuts, section: "整理时轻晃图标"),
            SearchResult(title: "窗口阴影", category: .shortcuts, section: "窗口阴影"),
            SearchResult(title: "界面音效", category: .shortcuts, section: "界面音效"),
            SearchResult(title: "启用音效", category: .shortcuts, section: "启用音效"),
            SearchResult(title: "选择音效", category: .shortcuts, section: "选择音效"),
            SearchResult(title: "键盘操作", category: .shortcuts, section: "键盘操作"),
            SearchResult(title: "卸载工具", category: .hidden, section: "卸载工具"),
            SearchResult(title: "自动分类", category: .hidden, section: "自动分类"),
            SearchResult(title: "自动分类应用", category: .hidden, section: "自动分类应用"),
            SearchResult(title: "应用列表", category: .hidden, section: "应用列表"),
            SearchResult(title: "系统应用排在最后", category: .hidden, section: "系统应用排在最后"),
            SearchResult(title: "管理隐藏应用", category: .hidden, section: "管理隐藏应用"),
            SearchResult(title: "备份历史", category: .backup, section: "备份历史"),
            SearchResult(title: "布局备份", category: .backup, section: "布局备份"),
            SearchResult(title: "旧版 Launchpad", category: .backup, section: "旧版 Launchpad"),
            SearchResult(title: "软件更新", category: .updates, section: "软件更新"),
            SearchResult(title: "Aplo", category: .updates, section: "Aplo"),
            SearchResult(title: "开源与许可", category: .updates, section: "开源与许可"),
        ].filter { ($0.title + " " + model.text($0.title)).localizedCaseInsensitiveContains(query) }
    }

    init(model: LauncherModel) {
        self.model = model
        _category = State(initialValue: Self.restoredCategory(model.lastSettingsCategory))
    }
    private static func restoredCategory(_ value: String) -> SettingsCategory {
        switch value {
        case "sound": return .shortcuts
        case "about": return .updates
        default: return SettingsCategory(rawValue: value) ?? .general
        }
    }

    private var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "3.14.1" }
    private var appIcon: NSImage {
        Bundle.main.url(forResource: "AppIcon", withExtension: "icns").flatMap { NSImage(contentsOf: $0) }
            ?? NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: nil)!
    }

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(model: model, appIcon: appIcon, category: $category, query: $settingsQuery)
            Divider()
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(model.text(category.title)).font(.system(size: model.preferences.textPoints(24), weight: .semibold)).allowsHitTesting(false)
                    Spacer()
                    if [.general, .appearance, .layout, .shortcuts].contains(category) {
                        Menu {
                            Button(model.text("恢复本页默认")) { resettingPage = true }
                        } label: { Image(systemName: "ellipsis.circle").font(.title3) }
                        .menuStyle(.borderlessButton).fixedSize()
                        .accessibilityLabel(model.text("页面操作"))
                    }
                    Button { model.closeSettings() } label: {
                        Image(systemName: "xmark").font(.system(size: model.preferences.textPoints(14), weight: .medium))
                            .frame(width: 32, height: 32)
                            .background(.primary.opacity(0.05), in: Circle())
                    }.buttonStyle(.plain).accessibilityLabel(model.text("关闭设置"))
                }
                MessageBanner(model: model)
                ScrollViewReader { reader in
                    HStack(alignment: .top, spacing: 18) {
                      VStack(spacing: 12) {
                        if !settingsQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(searchResults, id: \.title) { result in
                                        Button {
                                            category = result.category
                                            highlightedSection = result.section
                                            settingsQuery = ""
                                            highlightTask?.cancel()
                                            highlightTask = Task { @MainActor in
                                                await Task.yield()
                                                reader.scrollTo(result.section, anchor: .top)
                                                try? await Task.sleep(for: .seconds(2))
                                                if !Task.isCancelled { highlightedSection = nil }
                                            }
                                        } label: {
                                            HStack {
                                                Text(model.text(result.title))
                                                Spacer()
                                                Text(model.text(result.category.title)).foregroundStyle(.secondary)
                                                Image(systemName: "arrow.right")
                                            }.padding(10).contentShape(Rectangle())
                                        }.buttonStyle(.plain)
                                    }
                                    if searchResults.isEmpty { Text(model.text("没有匹配的设置")).padding(10) }
                                }
                            }.frame(maxHeight: 200)
                        }
                        if category == .appearance && settingsWidth < 1100 {
                            DisclosureGroup(model.text("实时预览"), isExpanded: $previewExpanded) {
                                AppearanceLivePreview(model: model)
                            }.font(.headline)
                        }
                        ScrollView {
                            VStack(alignment: .leading, spacing: 18) { detail }
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 8)
                        }.scrollIndicators(.automatic)
                      }
                      if category == .appearance && settingsWidth >= 1100 {
                          VStack(alignment: .leading, spacing: 10) {
                              Text(model.text("实时预览")).font(.headline)
                              AppearanceLivePreview(model: model)
                          }.frame(width: 300)
                      }
                    }
                }
            }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity)
        }.background(Color(nsColor: .windowBackgroundColor))
            .background {
                GeometryReader { geometry in
                    Color.clear.onAppear { settingsWidth = geometry.size.width }
                        .onChange(of: geometry.size.width) { settingsWidth = $0 }
                }
            }
            .environment(\.locale, Locale(identifier: model.preferences.language.localeIdentifier))
            .tint(model.accentColor)
            .onDisappear { highlightTask?.cancel() }
            .onChange(of: category) { model.lastSettingsCategory = $0.rawValue }
            .confirmationDialog(model.text("恢复本页默认"), isPresented: $resettingPage) {
                Button(model.text("恢复本页默认")) { resetPage() }
                Button(model.text("取消"), role: .cancel) {}
            } message: { Text(model.text(resetDetails) + "\n" + model.text("保留自定义呼出快捷键、个人布局、隐藏应用和备份。")) }
            .sheet(isPresented: $scalePreview, onDismiss: { model.presentingAppearancePreview = false }) {
                ScalePreview(model: model)
            }
    }

    @ViewBuilder private var detail: some View {
        switch category {
        case .general:
            card("显示方式", icon: "arrow.up.left.and.arrow.down.right") {
                HStack {
                    Text(model.text(model.isFullscreen ? "全屏启动台" : "居中小面板"))
                    Spacer()
                    Button(model.text(model.isFullscreen ? "切换小面板" : "切换全屏")) { model.onDisplayModeRequested?() }
                }
                note("⌃⌘F 随时切换。收起全屏面板后，菜单栏和 Dock 自动恢复。")
                Button(model.text("重置窗口位置")) { model.onResetWindowPosition?() }.disabled(model.isFullscreen)
                note("小窗口可拖动顶部移动，按屏幕记住位置。")
                note("拖动右下角调整窗口大小")
                switchRow("固定在当前桌面", key: \.pinToDesktop)
                Picker(model.text("收起方式"), selection: preference(\.dismissStyle)) {
                    ForEach(LauncherDismissStyle.allCases, id: \.self) { Text(model.text($0.title)).tag($0) }
                }
                switchRow("启动后自动收起", key: \.launchAutoHide)
                note("收起方式控制点击桌面时的行为；启动应用后是否保留窗口由独立开关控制。")
                Picker(model.text("工具栏位置"), selection: preference(\.toolbarPosition)) {
                    ForEach(LauncherToolbarPosition.allCases, id: \.self) { Text(model.text($0.title)).tag($0) }
                }.pickerStyle(.segmented)

            }
            card("程序坞与语言", icon: "menubar.dock.rectangle") {
                Picker(model.text("Aplo 入口位置"), selection: preference(\.entryLocation)) {
                    ForEach(LauncherEntryLocation.allCases, id: \.self) { Text(model.text($0.title)).tag($0) }
                }
                note("选择 Aplo 图标显示在底部程序坞、顶部菜单栏，或两处同时显示。至少保留一个入口，快捷键按原设置使用。")
                Divider()
                VStack(alignment: .leading, spacing: 7) {
                    Text(model.text("显示程序坞"))
                    Picker(model.text("显示程序坞"), selection: preference(\.dockVisibility)) {
                        ForEach(LauncherDockVisibility.allCases, id: \.self) { Text(model.text($0.title)).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: .infinity)
                }
                note("仅在面板打开时临时调整系统 Dock。跟随窗口：小窗保持系统状态，全屏自动隐藏；收起面板后恢复。显示模式仍遵循系统的自动隐藏偏好。")
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.text("语言"))
                    Picker(model.text("语言"), selection: preference(\.language)) {
                        ForEach(LauncherLanguage.allCases, id: \.self) { Text(model.text($0.title)).tag($0) }
                    }.labelsHidden().frame(maxWidth: .infinity)
                }
            }
        case .appearance:
            card("背景与文字", icon: "eye") {
                percentageRow("背景透明度", key: \.backgroundTransparency, range: 0...1, step: 0.05, multiplier: 100)

                Picker(model.text("背景样式"), selection: preference(\.backgroundStyle)) {
                    ForEach(LauncherBackground.allCases, id: \.self) { Text(model.text($0.title)).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().accessibilityLabel(model.text("背景样式"))
                Picker(model.text("文字颜色"), selection: preference(\.labelColor)) {
                    ForEach(LauncherLabelColor.allCases, id: \.self) { Text(model.text($0.title)).tag($0) }
                }
                if model.preferences.labelColor == .custom {
                    ColorPicker(model.text("自定义颜色"), selection: Binding(
                        get: { LauncherModel.color(hex: model.preferences.labelColorHex) },
                        set: { value in
                            guard let rgb = NSColor(value).usingColorSpace(.deviceRGB) else { return }
                            let hex = String(format: "#%02X%02X%02X", Int((rgb.redComponent * 255).rounded()), Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
                            model.updatePreferences { $0.labelColorHex = hex }
                        }), supportsOpacity: false)
                }
                switchRow("显示应用名称", key: \.showNames)
            }
            card("主题", icon: "circle.lefthalf.filled") {
                Picker(model.text("外观主题"), selection: preference(\.appearance)) {
                    ForEach(LauncherAppearance.allCases, id: \.self) { Text(model.text($0.title)).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().accessibilityLabel(model.text("外观主题"))
            }
            card("应用名称样式", icon: "textformat") {
                Picker(model.text("字体"), selection: preference(\.labelFontFamily)) {
                    Text(model.text("系统字体")).tag("")
                    ForEach(ApplicationFontCatalog.families, id: \.self) { Text($0).tag($0) }
                }
                Picker(model.text("字重"), selection: preference(\.labelWeight)) {
                    ForEach(LauncherLabelWeight.allCases, id: \.self) { Text(model.text($0.title)).tag($0) }
                }
                note("名称不带背景块。字体只影响应用与文件夹名称，繁体中文在通用的语言选项中选择。")
            }
            card("顶部标识", icon: "app.badge") {
                HStack {
                    Text(model.text("顶部名称大小"))
                    Slider(value: preference(\.brandNamePercent), in: 70...160, step: 5).accessibilityLabel(model.text("顶部名称大小"))
                    Text("\(Int(model.preferences.brandNamePercent))%").monospacedDigit().frame(width: 45)
                }
                note("仅调整顶部 Aplo 名称，不改变应用网格大小。")
            }
            card("色盲友好", icon: "eye") {
                Picker(model.text("界面配色"), selection: preference(\.colorVision)) {
                    ForEach(LauncherColorVision.allCases, id: \.self) { Text(model.text($0.title)).tag($0) }
                }.labelsHidden()
                note("调整界面强调色，选中状态同时使用边框与勾选标记。应用原始图标保持原色，避免影响辨认。")
            }
        case .layout:
            card("大小", icon: "textformat.size") {
                LayoutLivePreview(model: model)
                percentageRow("图标大小", key: \.iconScalePercent, range: 50...150, step: 5, multiplier: 1)
                percentageRow("文字大小", key: \.textScalePercent, range: 80...140, step: 5, multiplier: 1)
                Button(model.text("调整大小与对比…")) { model.presentingAppearancePreview = true; scalePreview = true }
            }
            card("移动与排列", icon: "hand.draw") {
                HStack {
                    ForEach(LauncherArrangement.allCases, id: \.self) { mode in
                        Button { model.chooseArrangement(mode) } label: {
                            Label(model.text(mode.title), systemImage: !model.preferences.automaticCategories && model.activeArrangement == mode ? "checkmark.circle.fill" : "circle")
                        }.buttonStyle(.bordered)
                    }
                }
                note("选择排列方式会关闭自动分类。网格中拖到边缘可调整顺序，拖到中心可合并；自由放置中直接拖到想要的位置，松手保存。全屏与小窗口各自记忆。")
            }
            card("网格密度", icon: "square.grid.3x3") {
                gridControls("小窗口", columns: \.compactGridColumns, rows: \.compactGridRows)
                Divider()
                gridControls("全屏", columns: \.fullscreenGridColumns, rows: \.fullscreenGridRows)
                note("自动沿用原布局密度。行数用于横向连续画布和分页；空间不足时允许滚动。自定义网格仅调整显示分页，不改写原布局。")
            }
        case .shortcuts:
            card("呼出快捷键", icon: "keyboard") {
                HStack {
                    Text(model.text(model.recordingShortcut ? "请按下新快捷键…" : model.shortcutDisplayName))
                        .font(.system(size: model.preferences.textPoints(16), weight: .medium, design: .monospaced))
                    Spacer()
                    Button(model.text(model.recordingShortcut ? "取消录制" : "录制快捷键")) {
                        if model.recordingShortcut { model.cancelRecording() } else { model.beginRecording() }
                    }
                    Button(model.text("恢复默认")) { model.resetShortcut() }.disabled(model.recordingShortcut)
                }
                note("至少包含 ⌘、⌃ 或 ⌥。Esc 取消录制，冲突时保留原快捷键。")
            }
            card("F4 备选呼出键", icon: "keyboard") {
                switchRow("启用 F4 呼出", key: \.f4ShortcutEnabled)
                if !model.f4ShortcutAvailable { note("F4 已被占用，请继续使用原快捷键或菜单栏入口。") }
                note("默认关闭，不修改系统键盘设置。部分键盘需要 Fn＋F4；带搜索图案的按键可能仍打开 Spotlight。")
            }
            card("屏幕热角", icon: "arrow.up.left.and.arrow.down.right") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.text("停留角落呼出"))
                    Picker(model.text("停留角落呼出"), selection: preference(\.hotCorner)) {
                        Text(model.text("不启用")).tag("off")
                        Text(model.text("左上角")).tag("topLeft"); Text(model.text("右上角")).tag("topRight")
                        Text(model.text("左下角")).tag("bottomLeft"); Text(model.text("右下角")).tag("bottomRight")
                    }.labelsHidden().frame(maxWidth: 220)
                }
                note("鼠标在角落停留片刻后打开。默认关闭；若系统热角使用同一角落，建议选择其他位置。")
            }
            card("浏览与滚动", icon: "hand.draw") {
                VStack(alignment: .leading, spacing: 7) {
                    Text(model.text("浏览方式"))
                    Picker(model.text("浏览方式"), selection: preference(\.navigationStyle)) {
                        ForEach(LauncherNavigationStyle.allCases, id: \.self) { Text(model.text($0.title)).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: .infinity).accessibilityLabel(model.text("浏览方式"))
                }
                switchRow("启用滑动翻页", key: \.swipeEnabled)
                    .disabled(model.isContinuousScrolling)
                Divider().padding(.vertical, 3)
                VStack(alignment: .leading, spacing: 7) {
                    Text(model.text("浏览方向"))
                    Picker(model.text("浏览方向"), selection: preference(\.pagingDirection)) {
                        ForEach(LauncherPagingDirection.allCases, id: \.self) { Text(model.text($0.title)).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: .infinity)
                        .accessibilityLabel(model.text("浏览方向"))
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(model.text("滑动灵敏度"))
                        Spacer()
                        Text(String(format: "%.1f×", model.preferences.gestureSensitivity)).monospacedDigit()
                    }
                    Slider(value: preference(\.gestureSensitivity), in: 0.8...2.4, step: 0.1)
                        .accessibilityLabel(model.text("滑动灵敏度"))
                }.disabled(!model.preferences.swipeEnabled && !model.isContinuousScrolling)
                switchRow("反向翻页", key: \.reversePaging)
                    .disabled(!model.preferences.swipeEnabled || model.isContinuousScrolling)
                note("连续滚动与分页都使用滑动灵敏度倍率。连续滚动保留系统惯性，可停在任意位置；反向和滑动开关仅用于分页模式。")
            }
            card("文件夹浏览", icon: "square.grid.3x3") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.text("文件夹浏览方式"))
                    Picker(model.text("文件夹浏览方式"), selection: preference(\.folderNavigation)) {
                        Text(model.text("跟随主界面")).tag("inherit")
                        Text(model.text("纵向连续滚动")).tag("continuous")
                        Text(model.text("分页切换")).tag("paged")
                    }.labelsHidden().frame(maxWidth: 250)
                }
                note("仅改变文件夹内的浏览方式，不改变主界面或应用顺序。")
            }
            card("外观与行为", icon: "sparkles") {
                switchRow("图标悬停放大", key: \.magnificationEnabled)
                switchRow("界面动画", key: \.animationsEnabled)
                switchRow("整理时轻晃图标", key: \.organizeWiggleEnabled)
                    .disabled(!model.preferences.animationsEnabled)
                note("开启时显示面板淡入与悬停过渡，遵循系统减少动态效果设置。")
                Divider()
                switchRow("窗口阴影", key: \.windowShadowEnabled)
            }
            card("界面音效", icon: "speaker.wave.2") {
                switchRow("启用音效", key: \.soundEffectsEnabled)
                HStack {
                    Text(model.text("音量"))
                    Slider(value: preference(\.soundVolume), in: 0...1).accessibilityLabel(model.text("音效音量"))
                    Text("\(Int(model.preferences.soundVolume * 100))%").monospacedDigit().frame(width: 36)
                }
                note("仅调整 Aplo 的音效音量，不改变系统音量。默认关闭，试听按钮始终可用。")
            }
            card("选择音效", icon: "music.note") {
                soundRow("打开面板", key: \.soundOpen)
                Divider()
                soundRow("收起面板", key: \.soundClose)
                Divider()
                soundRow("选择与翻页", key: \.soundNavigation)
                note("使用 macOS 系统音效；选择“无”可单独关闭某项。")
            }
            card("键盘操作", icon: "arrow.left.arrow.right") {
                note(model.isContinuousScrolling
                     ? "方向键选择 · 回车打开 · Tab / Shift＋Tab 跳转一组应用\n⌃⌘F 切换显示方式 · Esc 逐层返回或收起"
                     : "方向键选择 · 回车打开 · Tab / Shift＋Tab 翻页\n⌃⌘F 切换显示方式 · Esc 逐层返回或收起")
            }
        case .hidden:
            card("卸载工具", icon: "trash") {
                Text(model.preferences.uninstallerPath.isEmpty
                     ? model.text("系统废纸篓")
                     : URL(fileURLWithPath: model.preferences.uninstallerPath).deletingPathExtension().lastPathComponent)
                    .fontWeight(.medium)
                HStack {
                    Button(model.text("选择卸载工具…")) { model.onChooseUninstaller?() }
                    if !model.preferences.uninstallerPath.isEmpty {
                        Button(model.text("使用系统废纸篓")) { model.updatePreferences { $0.uninstallerPath = "" } }
                    }
                }
                note("右键卸载会将应用交给所选工具。工具须支持接收 .app 文件，卸载由工具确认。")
            }
            card("自动分类", icon: "square.grid.3x3") {
                switchRow("自动分类应用", key: \.automaticCategories)
                note("全屏和小窗口分别保存手动布局。关闭自动分类后可整理当前模式，另一模式不受影响。")
                note("按应用分类信息与规则生成分类文件夹。关闭后恢复手动排列；分类结果可能需要按个人习惯调整。")
                note("手动网格排列下可直接拖动图标，拖到另一图标中心松手可组成文件夹。三指拖移需在系统辅助功能中开启。")
            }
            card("应用列表", icon: "square.grid.2x2") {
                HStack {
                    Text(model.text("已发现 \(model.apps.count) 个应用"))
                    Spacer()
                    Button(model.text("刷新列表")) { model.requestRefresh(resetSearch: false) }
                }
                switchRow("系统应用排在最后", key: \.systemAppsLast)
                note("下载应用优先显示在前，系统应用排在末尾；网格分页与连续滚动都生效，保留手动布局与文件夹。")
            }
            card("管理隐藏应用", enclosed: true, icon: "eye.slash") { HiddenApplicationsView(model: model) }
        case .backup:
            card("备份历史", enclosed: true, icon: "clock.arrow.circlepath") { BackupHistoryView(model: model) }
            card("布局备份", icon: "externaldrive") {
                HStack(spacing: 12) {
                    Button(model.text("导出备份…")) { model.onExport?() }
                    Button(model.text("恢复备份…")) { model.onRestore?() }.disabled(model.importInProgress)
                }
                note("保存两套布局的顺序、文件夹、坐标、排列方式和呼出快捷键。恢复前自动备份，扫描完成后再提交；读取可取消。外观和翻页偏好单独保存。")
            }
            card("旧版 Launchpad", icon: "square.grid.3x3") {
                DisclosureGroup(model.text("导入旧布局"), isExpanded: $legacyExpanded) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Button(model.text("检测本机旧布局")) { model.onNativeImport?() }.disabled(model.importInProgress)
                            Button(model.text("选择旧备份…")) { model.onLegacyImport?() }.disabled(model.importInProgress)
                        }
                        note("支持旧数据库及含数据库的 .lmy / .zip。保留可匹配应用的顺序和文件夹，按每页 18 项重新分页；不修改源文件。没有旧数据就无法还原个人布局。")
                    }.padding(.top, 12)
                }
            }
        case .updates:
            card("软件更新", enclosed: true, icon: "arrow.down.circle") { UpdateCheckView(model: model, version: version) }
            card("Aplo", icon: "info.circle") {
                HStack(spacing: 14) {
                    Image(nsImage: appIcon).resizable().frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Aplo").font(.system(size: model.preferences.textPoints(20), weight: .semibold))
                        Text(model.text("版本 \(version)")).foregroundStyle(.secondary)
                        Text(model.text("搜索、整理，快速启动应用。")).foregroundStyle(.secondary)
                    }
                }
            }
            card("开源与许可", icon: "curlybraces") {
                note("搜索模块来自 LaunchNext，采用 GPL 第 3 版许可。对应源码随本版本提供。")
                HStack(spacing: 12) {
                    Button(model.text("许可证")) {
                        if let url = Bundle.main.url(forResource: "LICENSE", withExtension: nil) { NSWorkspace.shared.open(url) }
                    }
                    Button(model.text("本版本源码")) {
                        if let url = Bundle.main.url(forResource: "CorrespondingSource", withExtension: "zip") {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    }
                }
            }
            ForEach(ReleaseNote.bundled) { entry in
                card(entry.title, icon: "sparkles") {
                    Text(.init(entry.summary(language: model.preferences.language))).font(.system(size: model.preferences.textPoints(13)))
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    DisclosureGroup(model.text("开发者详细记录（英文）")) {
                        Text(.init(entry.developerDetails)).font(.system(size: model.preferences.textPoints(11))).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
            }
        case .sound, .about: EmptyView()
        }
    }

    private var resetDetails: String {
        switch category {
        case .general: return "重置入口、工具栏、收起方式、窗口固定、启动后收起、程序坞和语言。"
        case .layout: return "重置图标与文字大小、网格行列数。保留手动排列与文件夹。"
        case .appearance: return "重置字体、颜色、背景、主题、名称显示、辅助配色和阴影。"
        case .shortcuts: return "重置 F4、热角、文件夹浏览、滚动、放大、整理动画和音效。保留自定义呼出快捷键。"
        case .sound: return "重置音效开关、打开／关闭／导航音效和音量。"
        default: return ""
        }
    }

    private func resetPage() {
        let defaults = LauncherPreferences()
        model.updatePreferences { p in
            switch category {
            case .general:
                p.entryLocation = defaults.entryLocation; p.toolbarPosition = defaults.toolbarPosition
                p.dismissStyle = defaults.dismissStyle; p.pinToDesktop = defaults.pinToDesktop
                p.launchAutoHide = defaults.launchAutoHide; p.dockVisibility = defaults.dockVisibility
                p.language = defaults.language
            case .layout:
                p.iconScalePercent = defaults.iconScalePercent; p.textScalePercent = defaults.textScalePercent
                p.compactGridColumns = 0; p.fullscreenGridColumns = 0; p.compactGridRows = 0; p.fullscreenGridRows = 0
            case .appearance:
                p.labelFontFamily = defaults.labelFontFamily; p.labelWeight = defaults.labelWeight
                p.labelColor = defaults.labelColor; p.labelColorHex = defaults.labelColorHex
                p.backgroundStyle = defaults.backgroundStyle; p.backgroundTransparency = defaults.backgroundTransparency
                p.appearance = defaults.appearance; p.showNames = defaults.showNames
                p.brandNamePercent = defaults.brandNamePercent; p.colorVision = defaults.colorVision
                p.windowShadowEnabled = defaults.windowShadowEnabled
            case .shortcuts:
                p.magnificationEnabled = defaults.magnificationEnabled; p.animationsEnabled = defaults.animationsEnabled
                p.organizeWiggleEnabled = defaults.organizeWiggleEnabled
                p.f4ShortcutEnabled = defaults.f4ShortcutEnabled; p.hotCorner = "off"; p.folderNavigation = "inherit"
                p.swipeEnabled = defaults.swipeEnabled; p.reversePaging = defaults.reversePaging
                p.pagingDirection = defaults.pagingDirection; p.navigationStyle = defaults.navigationStyle
                p.gestureSensitivity = defaults.gestureSensitivity
                p.soundEffectsEnabled = defaults.soundEffectsEnabled; p.soundOpen = defaults.soundOpen
                p.soundClose = defaults.soundClose; p.soundNavigation = defaults.soundNavigation
                p.soundVolume = defaults.soundVolume
            default: break
            }
        }
    }

    private func percentageRow(_ title: String, key: WritableKeyPath<LauncherPreferences, Double>,
                               range: ClosedRange<Double>, step: Double, multiplier: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(model.text(title))
                Spacer()
                Text("\(Int((model.preferences[keyPath: key] * multiplier).rounded()))%")
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: preference(key), in: range, step: step)
                .accessibilityLabel(model.text(title))
        }.id(title).padding(4)
            .background(highlightedSection == title ? model.accentColor.opacity(0.14) : .clear,
                        in: RoundedRectangle(cornerRadius: 8))
    }

    private func gridControls(_ title: String, columns: WritableKeyPath<LauncherPreferences, Int>, rows: WritableKeyPath<LauncherPreferences, Int>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.text(title)).fontWeight(.medium)
            let columnPicker = Picker(model.text("列数"), selection: preference(columns)) {
                Text(model.text("自动")).tag(0)
                ForEach(2...12, id: \.self) { Text(String($0)).tag($0) }
            }
            let rowPicker = Picker(model.text("横向／分页行数"), selection: preference(rows)) {
                Text(model.text("自动")).tag(0)
                ForEach(1...8, id: \.self) { Text(String($0)).tag($0) }
            }
            ViewThatFits(in: .horizontal) {
                HStack { columnPicker; rowPicker }.fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 6) { columnPicker; rowPicker }
            }
        }
    }

    private func soundRow(_ title: String, key: WritableKeyPath<LauncherPreferences, String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.text(title))
            HStack {
                Picker(model.text(title), selection: preference(key)) {
                    Text(model.text("无")).tag("")
                    ForEach(SoundManager.systemSoundOptions) { Text($0.displayName).tag($0.id) }
                }.labelsHidden().frame(maxWidth: .infinity).accessibilityLabel(model.text(title + "音效"))
                Button(model.text("试听")) { SoundManager.shared.preview(systemSoundNamed: model.preferences[keyPath: key]) }
                    .disabled(model.preferences[keyPath: key].isEmpty).accessibilityLabel(model.text("试听" + title))
            }
        }
    }

    private func switchRow(_ title: String, key: WritableKeyPath<LauncherPreferences, Bool>) -> some View {
        VStack(spacing: 8) {
            Divider()
            HStack {
                Text(model.text(title)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                Toggle(model.text(title), isOn: preference(key)).labelsHidden().toggleStyle(.switch)
                    .accessibilityLabel(model.text(title)).fixedSize()
            }
        }.id(title).padding(4)
            .background(highlightedSection == title ? model.accentColor.opacity(0.14) : .clear,
                        in: RoundedRectangle(cornerRadius: 8))
    }

    private func preference<Value>(_ key: WritableKeyPath<LauncherPreferences, Value>) -> Binding<Value> {
        Binding(get: { model.preferences[keyPath: key] }, set: { value in model.updatePreferences { $0[keyPath: key] = value } })
    }
    private func note(_ text: String) -> some View {
        Group {
            if text.count > 44 {
                DisclosureGroup(model.text("了解更多")) {
                    Text(model.text(text)).fixedSize(horizontal: false, vertical: true)
                }
            } else { Text(model.text(text)).fixedSize(horizontal: false, vertical: true) }
        }.font(.system(size: model.preferences.textPoints(11))).foregroundStyle(.secondary)
    }
    private func card<Content: View>(_ title: String, enclosed: Bool = false, icon: String,
                                     @ViewBuilder content: () -> Content) -> some View {
        SettingsGroup(title: title, icon: icon, model: model, highlighted: highlightedSection == title,
                      enclosed: enclosed, content: content())
    }
}
