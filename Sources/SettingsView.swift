import AppKit
import SwiftUI

private enum SettingsCategory: String, CaseIterable {
    case general, appearance, shortcuts, sound, hidden, backup, updates, about
    var title: String {
        switch self {
        case .general: return "通用"
        case .appearance: return "外观"
        case .shortcuts: return "快捷键"
        case .sound: return "声音"
        case .hidden: return "隐藏应用"
        case .backup: return "备份"
        case .updates: return "更新内容"
        case .about: return "关于"
        }
    }
    var icon: String {
        switch self {
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
    var color: Color {
        switch self {
        case .general: return .blue
        case .appearance: return .purple
        case .shortcuts: return .cyan
        case .sound: return .orange
        case .hidden: return .indigo
        case .backup: return .green
        case .updates: return .teal
        case .about: return .gray
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
    private var sidebarWidth: CGFloat {
        let font = NSFont.systemFont(ofSize: model.preferences.textPoints(13), weight: .semibold)
        let longest = SettingsCategory.allCases.map { (model.text($0.title) as NSString).size(withAttributes: [.font: font]).width }.max() ?? 100
        return max(190, min(300, ceil(longest) + 122))
    }
    private var matchingCategories: [SettingsCategory] {
        let keywords: [SettingsCategory: String] = [
            .general: "显示 窗口 语言 分类 排列 程序坞 桌面 收起 display window language categories dock launch hide",
            .appearance: "主题 背景 透明度 字体 颜色 图标 大小 动画 appearance background transparency font color icon size animation",
            .shortcuts: "快捷键 热角 文件夹 滚动 翻页 灵敏度 F4 keyboard shortcut hot corner folder scroll sensitivity",
            .sound: "声音 音效 音量 sound volume", .hidden: "隐藏 应用 hidden apps",
            .backup: "备份 恢复 导入 历史 backup restore import history", .updates: "更新 内容 update release", .about: "关于 版本 许可 about license version"]
        return SettingsCategory.allCases.filter { settingsQuery.isEmpty || (model.text($0.title) + " " + (keywords[$0] ?? "")).localizedCaseInsensitiveContains(settingsQuery) }
    }
    init(model: LauncherModel) {
        self.model = model
        _category = State(initialValue: SettingsCategory(rawValue: model.lastSettingsCategory) ?? .general)
    }
    private var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "3.14.1" }
    private var appIcon: NSImage {
        Bundle.main.url(forResource: "AppIcon", withExtension: "icns").flatMap { NSImage(contentsOf: $0) }
            ?? NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: nil)!
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(model.text(category.title)).font(.system(size: model.preferences.textPoints(24), weight: .semibold)).allowsHitTesting(false)
                    Spacer()
                    if [.general, .appearance, .shortcuts, .sound].contains(category) {
                        Button(model.text("恢复本页默认")) { resettingPage = true }.controlSize(.small)
                    }
                    Button { model.closeSettings() } label: {
                        Image(systemName: "xmark").font(.system(size: model.preferences.textPoints(14), weight: .medium))
                            .frame(width: 32, height: 32)
                            .background(.primary.opacity(0.05), in: Circle())
                    }.buttonStyle(.plain).accessibilityLabel(model.text("关闭设置"))
                }.background { WindowDragHandle(enabled: !model.isFullscreen) }
                MessageBanner(model: model)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) { detail }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 8)
                }.scrollIndicators(.hidden).id(category)
            }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity)
        }.background(.ultraThinMaterial)
            .onChange(of: category) { model.lastSettingsCategory = $0.rawValue }
            .confirmationDialog(model.text("恢复本页默认"), isPresented: $resettingPage) {
                Button(model.text("恢复本页默认")) { resetPage() }
                Button(model.text("取消"), role: .cancel) {}
            } message: { Text(model.text(resetDetails) + "\n" + model.text("保留自定义呼出快捷键、个人布局、隐藏应用和备份。")) }
            .sheet(isPresented: $scalePreview, onDismiss: { model.presentingAppearancePreview = false }) {
                ScalePreview(model: model)
            }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(nsImage: appIcon).resizable().frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Aplo").font(.system(size: model.preferences.textPoints(20), weight: .semibold))
                    Text(model.text("版本 \(version)")).font(.system(size: model.preferences.textPoints(11))).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 6).padding(.top, 8).padding(.bottom, 6)
            TextField(model.text("搜索设置"), text: $settingsQuery).textFieldStyle(.roundedBorder)
            ScrollView {
              VStack(spacing: 5) {
                ForEach(matchingCategories, id: \.self) { section in
                    Button {
                        if model.recordingShortcut { model.cancelRecording() }
                        category = section
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: section.icon).font(.system(size: model.preferences.textPoints(14), weight: .semibold))
                                .foregroundStyle(model.preferences.colorVision == .standard ? Color.white : Color(nsColor: .windowBackgroundColor)).frame(width: 28, height: 28)
                                .background((model.preferences.colorVision == .standard ? section.color : model.accentColor).gradient, in: RoundedRectangle(cornerRadius: 8))
                            Text(model.text(section.title)).lineLimit(1).fixedSize(horizontal: true, vertical: false).layoutPriority(1).font(.system(size: model.preferences.textPoints(13), weight: category == section ? .semibold : .regular))
                            Spacer(minLength: 0)
                        }.padding(.horizontal, 10).padding(.vertical, 9)
                            .background(category == section ? model.accentColor.opacity(0.16) : .clear,
                                        in: RoundedRectangle(cornerRadius: 10))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel(model.text(section.title + "设置"))
                        .accessibilityAddTraits(category == section ? .isSelected : [])
                }
              }
              if matchingCategories.isEmpty { Text(model.text("没有匹配的设置")).foregroundStyle(.secondary).padding(.top, 12) }
            }.scrollIndicators(.hidden)
            Spacer(minLength: 0)
            Text(model.text("设置自动保存")).font(.system(size: model.preferences.textPoints(11))).foregroundStyle(.tertiary).padding(.horizontal, 10)
        }.padding(14).frame(width: sidebarWidth).frame(maxHeight: .infinity)
            .background(.primary.opacity(0.025))
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
                HStack {
                    Text(model.text("语言")); Spacer()
                    Picker(model.text("语言"), selection: preference(\.language)) {
                        ForEach(LauncherLanguage.allCases, id: \.self) { Text(model.text($0.title)).tag($0) }
                    }.labelsHidden().frame(width: 180)
                }
            }
            card("自动分类", icon: "square.grid.3x3") {
                switchRow("自动分类应用", key: \.automaticCategories)
                note("全屏和小窗口分别保存手动布局。关闭自动分类后可整理当前模式，另一模式不受影响。")
                note("按应用分类信息与规则生成分类文件夹。关闭后恢复手动排列；分类结果可能需要按个人习惯调整。")
                note("手动网格排列下可直接拖动图标，拖到另一图标中心松手可组成文件夹。三指拖移需在系统辅助功能中开启。")
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
            card("应用列表", icon: "square.grid.2x2") {
                HStack {
                    Text(model.text("已发现 \(model.apps.count) 个应用"))
                    Spacer()
                    Button(model.text("刷新列表")) { model.requestRefresh(resetSearch: false) }
                }
                switchRow("系统应用排在最后", key: \.systemAppsLast)
                note("下载应用优先显示在前，系统应用排在末尾；保留手动布局与文件夹。")
            }
        case .appearance:
            AppearanceLivePreview(model: model)
            card("主题", icon: "circle.lefthalf.filled") {
                Picker(model.text("外观主题"), selection: preference(\.appearance)) {
                    ForEach(LauncherAppearance.allCases, id: \.self) { Text(model.text($0.title)).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().accessibilityLabel(model.text("外观主题"))
            }
            card("背景", icon: "rectangle.on.rectangle") {
                Picker(model.text("背景样式"), selection: preference(\.backgroundStyle)) {
                    ForEach(LauncherBackground.allCases, id: \.self) { Text(model.text($0.title)).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().accessibilityLabel(model.text("背景样式"))
                Group {
                    HStack {
                        Text(model.text("背景透明度"))
                        Slider(value: preference(\.backgroundTransparency), in: 0...1, step: 0.05)
                            .frame(maxWidth: 240).accessibilityLabel(model.text("背景透明度"))
                        Text("\(Int((model.preferences.backgroundTransparency * 100).rounded()))%")
                            .monospacedDigit().frame(width: 45)
                    }
                    note("纯色与玻璃均支持 0–100% 透明度，设置按钮保持独立对比度。系统开启减少透明度时使用不透明背景。")
                }
            }
            card("文字与图标", icon: "textformat.size") {
                HStack {
                    Text(model.text("图标大小")); Spacer(); Text("\(Int(model.preferences.iconScalePercent.rounded()))%")
                }
                HStack {
                    Text(model.text("文字大小")); Spacer(); Text("\(Int(model.preferences.textScalePercent.rounded()))%")
                }
                Button(model.text("调整大小与对比…")) { model.presentingAppearancePreview = true; scalePreview = true }
                switchRow("显示应用名称", key: \.showNames)
            }
            card("应用名称样式", icon: "textformat") {
                Picker(model.text("字体"), selection: preference(\.labelFontFamily)) {
                    Text(model.text("系统字体")).tag("")
                    ForEach(ApplicationFontCatalog.families, id: \.self) { Text($0).tag($0) }
                }
                Picker(model.text("字重"), selection: preference(\.labelWeight)) {
                    ForEach(LauncherLabelWeight.allCases, id: \.self) { Text(model.text($0.title)).tag($0) }
                }
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
                Text(model.text("应用名称预览：Aplo 軟體"))
                    .font(model.applicationLabelFont).foregroundStyle(model.applicationLabelColor)
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .background(Color.gray.opacity(0.3), in: RoundedRectangle(cornerRadius: 9))
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
            card("外观与行为", icon: "sparkles") {
                switchRow("图标悬停放大", key: \.magnificationEnabled)
                switchRow("界面动画", key: \.animationsEnabled)
                note("开启时显示面板淡入与悬停过渡，遵循系统减少动态效果设置。")
                Divider()
                switchRow("窗口阴影", key: \.windowShadowEnabled)
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
                HStack {
                    Text(model.text("停留角落呼出")); Spacer()
                    Picker(model.text("停留角落呼出"), selection: preference(\.hotCorner)) {
                        Text(model.text("不启用")).tag("off")
                        Text(model.text("左上角")).tag("topLeft"); Text(model.text("右上角")).tag("topRight")
                        Text(model.text("左下角")).tag("bottomLeft"); Text(model.text("右下角")).tag("bottomRight")
                    }.labelsHidden().frame(maxWidth: 220)
                }
                note("鼠标在角落停留片刻后打开。默认关闭；若系统热角使用同一角落，建议选择其他位置。")
            }
            card("文件夹浏览", icon: "square.grid.3x3") {
                HStack {
                    Text(model.text("文件夹浏览方式")); Spacer()
                    Picker(model.text("文件夹浏览方式"), selection: preference(\.folderNavigation)) {
                        Text(model.text("跟随主界面")).tag("inherit")
                        Text(model.text("纵向连续滚动")).tag("continuous")
                        Text(model.text("分页切换")).tag("paged")
                    }.labelsHidden().frame(maxWidth: 250)
                }
                note("仅改变文件夹内的浏览方式，不改变主界面或应用顺序。")
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
                HStack {
                    Text(model.text("滑动灵敏度"))
                    Slider(value: preference(\.gestureSensitivity), in: 0.8...2.4, step: 0.1)
                        .frame(maxWidth: 220).accessibilityLabel(model.text("滑动灵敏度"))
                    Text(String(format: "%.1f×", model.preferences.gestureSensitivity))
                        .monospacedDigit().frame(width: 45)
                }.disabled(!model.preferences.swipeEnabled && !model.isContinuousScrolling)
                switchRow("反向翻页", key: \.reversePaging)
                    .disabled(!model.preferences.swipeEnabled || model.isContinuousScrolling)
                note("连续滚动与分页都使用滑动灵敏度倍率。连续滚动保留系统惯性，可停在任意位置；反向和滑动开关仅用于分页模式。")
            }
            card("键盘操作", icon: "arrow.left.arrow.right") {
                note(model.isContinuousScrolling
                     ? "方向键选择 · 回车打开 · Tab / Shift＋Tab 跳转一组应用\n⌃⌘F 切换显示方式 · Esc 逐层返回或收起"
                     : "方向键选择 · 回车打开 · Tab / Shift＋Tab 翻页\n⌃⌘F 切换显示方式 · Esc 逐层返回或收起")
            }
        case .sound:
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
        case .hidden:
            card("管理隐藏应用", icon: "eye.slash") { HiddenApplicationsView(model: model) }
        case .backup:
            card("备份历史", icon: "clock.arrow.circlepath") { BackupHistoryView(model: model) }
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
            card("软件更新", icon: "arrow.down.circle") { UpdateCheckView(model: model, version: version) }
            ForEach(ReleaseNote.bundled) { entry in
                card(entry.title, icon: "sparkles") {
                    Text(.init(entry.summary(language: model.preferences.language))).font(.system(size: model.preferences.textPoints(13)))
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    DisclosureGroup(model.text("开发者详细记录（英文）")) {
                        Text(.init(entry.developerDetails)).font(.system(size: model.preferences.textPoints(11))).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
            }
        case .about:
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
        }
    }

    private var resetDetails: String {
        switch category {
        case .general: return "重置入口、工具栏、收起方式、窗口固定、启动后收起、程序坞、语言、网格和系统应用排序。"
        case .appearance: return "重置字体、颜色、大小、背景、主题、名称显示、辅助配色、放大、动画和阴影。"
        case .shortcuts: return "重置 F4、热角、文件夹浏览方式、滚动方向、分页开关、反向翻页和灵敏度。"
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
                p.language = defaults.language; p.systemAppsLast = defaults.systemAppsLast
                p.compactGridColumns = 0; p.fullscreenGridColumns = 0; p.compactGridRows = 0; p.fullscreenGridRows = 0
            case .appearance:
                p.labelFontFamily = defaults.labelFontFamily; p.labelWeight = defaults.labelWeight
                p.labelColor = defaults.labelColor; p.labelColorHex = defaults.labelColorHex
                p.iconScalePercent = defaults.iconScalePercent; p.textScalePercent = defaults.textScalePercent
                p.backgroundStyle = defaults.backgroundStyle; p.backgroundTransparency = defaults.backgroundTransparency
                p.appearance = defaults.appearance; p.showNames = defaults.showNames
                p.brandNamePercent = defaults.brandNamePercent; p.colorVision = defaults.colorVision
                p.magnificationEnabled = defaults.magnificationEnabled; p.animationsEnabled = defaults.animationsEnabled
                p.windowShadowEnabled = defaults.windowShadowEnabled
            case .shortcuts:
                p.f4ShortcutEnabled = defaults.f4ShortcutEnabled; p.hotCorner = "off"; p.folderNavigation = "inherit"
                p.swipeEnabled = defaults.swipeEnabled; p.reversePaging = defaults.reversePaging
                p.pagingDirection = defaults.pagingDirection; p.navigationStyle = defaults.navigationStyle
                p.gestureSensitivity = defaults.gestureSensitivity
            case .sound:
                p.soundEffectsEnabled = defaults.soundEffectsEnabled; p.soundOpen = defaults.soundOpen
                p.soundClose = defaults.soundClose; p.soundNavigation = defaults.soundNavigation
                p.soundVolume = defaults.soundVolume
            default: break
            }
        }
    }

    private func gridControls(_ title: String, columns: WritableKeyPath<LauncherPreferences, Int>, rows: WritableKeyPath<LauncherPreferences, Int>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.text(title)).fontWeight(.medium)
            HStack {
                Picker(model.text("列数"), selection: preference(columns)) {
                    Text(model.text("自动")).tag(0)
                    ForEach(2...12, id: \.self) { Text(String($0)).tag($0) }
                }
                Picker(model.text("横向／分页行数"), selection: preference(rows)) {
                    Text(model.text("自动")).tag(0)
                    ForEach(1...8, id: \.self) { Text(String($0)).tag($0) }
                }
            }
        }
    }

    private func soundRow(_ title: String, key: WritableKeyPath<LauncherPreferences, String>) -> some View {
        HStack {
            Text(model.text(title))
            Spacer()
            Picker(model.text(title), selection: preference(key)) {
                Text(model.text("无")).tag("")
                ForEach(SoundManager.systemSoundOptions) { Text($0.displayName).tag($0.id) }
            }.labelsHidden().frame(width: 140).accessibilityLabel(model.text(title + "音效"))
            Button(model.text("试听")) { SoundManager.shared.preview(systemSoundNamed: model.preferences[keyPath: key]) }
                .disabled(model.preferences[keyPath: key].isEmpty).accessibilityLabel(model.text("试听" + title))
        }
    }

    private func switchRow(_ title: String, key: WritableKeyPath<LauncherPreferences, Bool>) -> some View {
        HStack {
            Text(model.text(title))
            Spacer()
            Toggle(model.text(title), isOn: preference(key)).labelsHidden().toggleStyle(.switch).accessibilityLabel(model.text(title))
        }
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
    private func card<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Label(model.text(title), systemImage: icon).font(.system(size: model.preferences.textPoints(14), weight: .semibold))
            content().font(.system(size: model.preferences.textPoints(12)))
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.065)))
    }
}
