import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension LauncherModel {
    var accentColor: Color {
        let mode = preferences.colorVision
        return Color(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            switch mode {
            case .standard: return dark ? NSColor(srgbRed: 0.39, green: 0.83, blue: 0.75, alpha: 1) : NSColor(srgbRed: 0.08, green: 0.43, blue: 0.40, alpha: 1)
            case .redGreen: return dark ? NSColor(srgbRed: 0.50, green: 0.75, blue: 1, alpha: 1) : NSColor(srgbRed: 0.05, green: 0.32, blue: 0.75, alpha: 1)
            case .blueYellow: return dark ? NSColor(srgbRed: 1, green: 0.65, blue: 0.80, alpha: 1) : NSColor(srgbRed: 0.65, green: 0.15, blue: 0.35, alpha: 1)
            case .monochrome: return dark ? .white : .black
            }
        })
    }
}

let launcherDragType = UTType(exportedAs: "local.jianqi.layout-item")

struct LauncherView: View {
    @ObservedObject var model: LauncherModel
    let launch: (InstalledApp) -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var clearBackdrop: Bool { model.preferences.backgroundTransparency > 0.7 && !reduceTransparency }
    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: LauncherGeometry.gridSpacing), count: model.columnCount) }

    var body: some View {
        Group {
            if model.showingSettings { SettingsView(model: model).frame(maxWidth: 1000, maxHeight: 720)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.primary.opacity(0.10))) }
            else { launcherContent }
        }
        .padding(model.showingSettings ? (model.isFullscreen ? 24 : 0) : LauncherGeometry.contentInset(fullscreen: model.isFullscreen))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
              WindowDragHandle(enabled: !model.isFullscreen)
              if model.preferences.backgroundStyle == .glass && !reduceTransparency {
                VisualEffectBackground()
                Color(nsColor: .windowBackgroundColor).opacity(1 - model.preferences.backgroundTransparency)
                LinearGradient(colors: [model.accentColor.opacity(scheme == .dark ? 0.035 : 0.025), .clear],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [model.accentColor.opacity(0.025), .clear],
                               center: .topLeading, startRadius: 0, endRadius: 340)
              } else { Color(nsColor: .windowBackgroundColor) }
            }.opacity(reduceTransparency ? 1 : 1 - model.preferences.backgroundTransparency)
        }
        .background { MagnificationSurface(enabled: model.preferences.magnificationEnabled && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) }
        .clipShape(RoundedRectangle(cornerRadius: model.isFullscreen ? 0 : LauncherGeometry.compactCornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: model.isFullscreen ? 0 : LauncherGeometry.compactCornerRadius, style: .continuous).strokeBorder(.primary.opacity(0.10)))
        .overlay(alignment: .bottomTrailing) {
            if !model.isFullscreen {
                WindowResizeHandle().frame(width: LauncherGeometry.resizeHandleSize, height: LauncherGeometry.resizeHandleSize)
                    .background {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 10)).foregroundStyle(.white)
                            .frame(width: 24, height: 24).background(.black.opacity(0.5), in: Circle())
                            .allowsHitTesting(false)
                    }
                    .padding(3).help(model.text("拖动右下角调整窗口大小"))
            }
        }
        .overlay(alignment: .topLeading) {
            if model.preferences.showFrameStats {
                FrameStatsOverlay(active: true)
                    .frame(width: 196, height: 24)
                    .padding(10)
                    .allowsHitTesting(false)
            }
        }
        .sheet(isPresented: $model.showingPageOrganizer) { PageOrganizer(model: model) }
        .sheet(item: $model.inspectingApp) { app in ApplicationInspector(model: model, app: app) }
        .tint(model.accentColor)
        .environment(\.locale, Locale(identifier: model.preferences.language.localeIdentifier))
    }

    private var launcherContent: some View {
        VStack(spacing: 0) {
            header.frame(maxWidth: model.gridWidth).padding(.bottom, 16)
            if model.preferences.toolbarPosition == .top { toolbar.padding(.bottom, 12) }
            MessageBanner(model: model)
            if let result = model.inlineResult { InlineResultView(model: model, result: result) }
            if model.isSearching && model.inlineResult == nil { SearchCategoryBar(model: model).padding(.bottom, 12) }
            frequentRow
            if model.usesFreePlacement { freeContent }
            else if model.visibleItems.isEmpty {
                LauncherEmptyState(model: model)
            } else if model.isContinuousScrolling {
                if usesNativeVerticalGrid {
                    NativeVerticalComparison(model: model, launch: launch)
                } else { continuousContent }
            } else {
                GeometryReader { geometry in
                    PageStrip(motion: model.pageMotion, size: geometry.size) {
                        ZStack(alignment: .topLeading) { pageFrames(size: geometry.size) }
                            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                    }
                        .onAppear { model.pageHeight = geometry.size.height }
                        .onChange(of: geometry.size) { model.pageHeight = $0.height }
                }.clipped()
            }
            if !model.isContinuousScrolling && !model.usesFreePlacement {
                PageInteractionLock(motion: model.pageMotion) { pagination }
                    .padding(.top, model.isFullscreen ? 16 : 4)
            }
            if model.preferences.toolbarPosition == .bottom { toolbar.padding(.top, 8) }
        }
    }

    private var arrangementControls: some View {
        HStack(spacing: 8) {
                    Menu {
                        ForEach(LauncherArrangement.allCases, id: \.self) { mode in
                            Button { model.chooseArrangement(mode) } label: {
                                Label(model.text(mode.title), systemImage: !model.preferences.automaticCategories && model.activeArrangement == mode ? "checkmark" : "square.grid.2x2")
                            }
                        }
                        Divider()
                        Button(model.text("下载应用优先")) { model.organizeDownloadedFirst() }
                        Button(model.text("按名称排序")) { model.sortByName() }
                        Button(model.text("随机打乱")) { model.shuffleLayout() }
                        Divider()
                        Button(model.text(model.multiSelectionActive ? "结束多选" : "多选应用")) { model.toggleMultiSelection() }.disabled(model.isSearching || model.importInProgress)
                        Button(model.text("页面顺序…")) { model.editing = true; model.showingPageOrganizer = true }
                            .disabled(model.preferences.automaticCategories || model.openFolderID != nil || model.customGridEnabled)
                        Divider()
                        Button(model.text(model.editing ? "完成整理" : "手动整理")) { model.toggleEditing() }
                    } label: {
                        Label(model.text("整理"), systemImage: "square.grid.2x2")
                            .font(.system(size: model.preferences.textPoints(12)))
                    }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel(model.text("整理应用"))
                    if model.multiSelectionActive {
                        Text("\(model.selectedItemIDs.count)").monospacedDigit()
                        Menu {
                            Button(model.text("合并所选应用")) { model.createFolderFromSelection() }.disabled(model.selectedAppIDs.count < 2 || model.openFolderID != nil)
                            ForEach(model.layout.folders.filter { $0.id != model.openFolderID }) { folder in
                                Button(model.name(for: folder)) { model.moveSelection(toFolder: folder.id) }
                            }
                            if model.openFolderID != nil { Button(model.text("移出文件夹")) { model.moveSelection(toFolder: nil) } }
                        } label: { Image(systemName: "square.on.square") }
                        .menuStyle(.borderlessButton).fixedSize().accessibilityLabel(model.text("批量移动或合并"))
                        .disabled(model.selectedItemIDs.isEmpty)
                        .help(model.text("批量移动或合并"))
                    }
                    if model.editing {
                        Button(model.text("完成")) { model.toggleEditing() }.buttonStyle(.plain)
                    }
        }
    }

    private var toolbar: some View {
        ZStack {
                HStack {
                    HStack(spacing: 8) {
                        Button {
                            model.searchExpanded.toggle()
                            if model.searchExpanded { model.focusGeneration += 1 } else { model.query = "" }
                        } label: { Image(systemName: model.searchExpanded ? "xmark" : "magnifyingglass").frame(width: 34, height: 34) }
                            .buttonStyle(.plain).accessibilityLabel(model.text("搜索应用"))
                        if model.searchExpanded { search.frame(maxWidth: 290) }
                        else { Text(model.text("\(model.visibleApplicationCount) 个应用")) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Spacer(minLength: 48)
                    arrangementControls.frame(maxWidth: .infinity, alignment: .trailing)
                        .help(model.text(model.canOrganize ? model.dropDescription : "方向键选择   ↵ 打开   esc 返回"))
                }.font(.system(size: model.preferences.textPoints(11))).foregroundStyle(clearBackdrop ? Color.white : Color.secondary)
                Button { model.openSettings() } label: {
                    Image(systemName: "gearshape").font(.system(size: 17, weight: .medium))
                        .frame(width: 40, height: 36)
                        .foregroundStyle(.white)
                        .background(Color.black.opacity(0.66), in: Capsule())
                        .overlay(Capsule().strokeBorder(.white.opacity(0.55)))
                        .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                }.buttonStyle(.plain)
                    .help(model.text("设置与备份"))
                    .accessibilityLabel(model.text("设置与备份"))
            }.frame(maxWidth: model.gridWidth).frame(height: LauncherGeometry.toolbarHeight)

    }

    private var freeContent: some View {
        GeometryReader { viewport in
            let vertical = model.navigationDirection == .vertical
            let tileWidth = model.tileWidth
            let tileHeight = model.displayedIconSize + model.preferences.labelHeight + 18
            let rows = model.fittedRows(height: viewport.size.height, tileHeight: tileHeight)
            let count = model.containerItems.count
            let canvas = CGSize(width: vertical ? model.gridWidth : max(viewport.size.width, CGFloat((count + rows - 1) / rows) * (tileWidth + LauncherGeometry.gridSpacing)),
                                height: vertical ? max(viewport.size.height, CGFloat((count + model.columnCount - 1) / model.columnCount) * (tileHeight + LauncherGeometry.gridSpacing)) : viewport.size.height)
            let tileSize = CGSize(width: tileWidth, height: tileHeight)
            let entries = Array(model.containerItems.enumerated()).map { index, item in
                    let column = vertical ? index % model.columnCount : index / rows
                    let row = vertical ? index / model.columnCount : index % rows
                    let fallback = CGPoint(x: CGFloat(column) * (tileWidth + LauncherGeometry.gridSpacing), y: CGFloat(row) * (tileHeight + LauncherGeometry.gridSpacing))
                    let origin = FreePlacementGeometry.origin(position: model.layout.freePositions?[model.freePositionKey(item.id)], fallback: fallback, canvas: canvas, tile: tileSize)
                    return FreeCanvasEntry(item: item, index: index, origin: origin)
                }
            ScrollView(vertical ? .vertical : .horizontal) {
                CulledFreeCanvas(entries: entries, canvas: canvas, viewport: viewport.size, tileSize: tileSize, draggedID: model.draggingID,
                    selectedID: model.keyboardSelectionActive ? model.selectedItem?.id : nil, revealGeneration: model.keyboardNavigationGeneration,
                    begin: { model.beginFreeDrag($0) }, end: { model.endDrag() },
                    save: { id, point in model.setFreePosition(id, x: point.x, y: point.y) }) { entry in tile(entry.item, index: entry.index) }
                    .allowsHitTesting(!model.importInProgress)
            }.coordinateSpace(name: "free-viewport")
            .id("free-\(model.isFullscreen)-\(model.openFolderID ?? "root")-\(model.navigationDirection)")
            .onAppear { model.horizontalRowCount = rows; model.updateFreeFrames(Dictionary(uniqueKeysWithValues: entries.map { ($0.id, CGRect(origin: $0.origin, size: tileSize)) })) }
            .onChange(of: entries) { entries in model.updateFreeFrames(Dictionary(uniqueKeysWithValues: entries.map { ($0.id, CGRect(origin: $0.origin, size: tileSize)) })) }
            .onChange(of: rows) { model.horizontalRowCount = $0 }
        }
    }

    private var continuousContent: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                let vertical = model.navigationDirection == .vertical
                let tileHeight = model.displayedIconSize + model.preferences.labelHeight + 18
                let rows = model.fittedRows(height: geometry.size.height, tileHeight: tileHeight)
                ScrollView(vertical ? .vertical : .horizontal) {
                    if vertical {
                        verticalSections(tileHeight: tileHeight)
                    } else {
                        horizontalGrid(tileHeight: tileHeight, rows: rows)
                    }
                }
                .onAppear { model.horizontalRowCount = rows }
                .onChange(of: rows) { model.horizontalRowCount = $0 }
                .onChange(of: model.selectedIndex) { index in
                    guard model.containerItems.indices.contains(index) else { return }
                    proxy.scrollTo(vertical ? verticalRowAnchor(for: index) : model.containerItems[index].id)
                }
                .onChange(of: model.query) { _ in
                    if let first = model.containerItems.first { proxy.scrollTo(vertical ? verticalRowAnchor(for: 0) : first.id, anchor: .topLeading) }
                }
                .id("\(model.isFullscreen)-\(model.navigationDirection)-\(model.openFolderID ?? "continuous-root")")
            }
        }
    }

    private func verticalRowAnchor(for index: Int) -> String {
        let items = model.containerItems
        guard items.indices.contains(index) else { return "" }
        return "row:" + items[index / model.columnCount * model.columnCount].id
    }

    private func verticalSections(tileHeight: CGFloat) -> some View {
        let items = model.containerItems
        let columns = model.columnCount
        let count = items.count
        let rowCount = (count + columns - 1) / columns
        return LazyVStack(alignment: .leading, spacing: LauncherGeometry.gridSpacing) {
            ForEach(0..<rowCount, id: \.self) { row in
                let start = row * columns
                let end = min(count, start + columns)
                HStack(spacing: LauncherGeometry.gridSpacing) {
                    ForEach(start..<end, id: \.self) { index in
                        tile(items[index], index: index)
                            .frame(width: model.tileWidth, height: tileHeight)
                    }
                }
                .frame(height: tileHeight)
                .id("row:" + items[start].id)
            }
        }.frame(width: model.gridWidth).frame(maxWidth: .infinity).padding(.vertical, 4)
    }

    private var usesNativeVerticalGrid: Bool {
        CommandLine.arguments.contains("--native-scroll-comparison") &&
        model.isFullscreen && model.isContinuousScrolling && model.navigationDirection == .vertical &&
        !model.initialDiscoveryPending && !model.isSearching && !model.usesFreePlacement &&
        model.openFolderID == nil
    }

    @ViewBuilder private var frequentRow: some View {
        if model.openFolderID == nil && !model.isSearching && (!model.editing || usesNativeVerticalGrid) {
            let recent = model.recentApplications
            if !recent.isEmpty {
                VStack(spacing: 8) {
                    HStack(spacing: LauncherGeometry.gridSpacing) {
                        ForEach(recent, id: \.id) { app in
                            LauncherTile(model: model, item: .app(app.id), index: -1, selected: false) { launch(app) }
                                .equatable().frame(width: model.tileWidth)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .contain).accessibilityLabel(model.text("最近使用"))
                    Divider()
                }.frame(width: model.gridWidth).frame(maxWidth: .infinity).padding(.bottom, 8)
            }
        }
    }

    private func horizontalGrid(tileHeight: CGFloat, rows: Int) -> some View {
        // Read the container once: containerItems is a computed property and the slot
        // list is rebuilt on every SwiftUI pass, which allocated per frame while scrolling.
        let items = model.containerItems
        let slots = LauncherGeometry.horizontalSlots(itemCount: items.count, rows: rows, columns: model.columnCount)
        return LazyHGrid(rows: Array(repeating: GridItem(.fixed(tileHeight), spacing: LauncherGeometry.gridSpacing), count: rows), spacing: LauncherGeometry.gridSpacing) {
            ForEach(slots, id: \.self) { index in
                if items.indices.contains(index) {
                    let item = items[index]
                    tile(item, index: index)
                        .frame(width: model.tileWidth, height: tileHeight)
                        .id(item.id)
                } else {
                    Color.clear.frame(width: model.tileWidth, height: tileHeight)
                        .accessibilityHidden(true)
                }
            }
        }.frame(height: tileHeight * CGFloat(rows) + CGFloat(rows - 1) * LauncherGeometry.gridSpacing)
            .padding(.vertical, 4).frame(maxHeight: .infinity, alignment: .top)
    }

    private func pageFrames(size: CGSize) -> some View {
        let current = model.pageIndex
        let pages = ((current - 1)...(current + 1)).filter { $0 >= 0 && $0 < model.pageCount }
        return ForEach(pages, id: \.self) { page in
            let origin = PageMotion.origin(relativePage: page - current, size: size,
                                           vertical: model.navigationDirection == .vertical)
            pageContent(page, interactive: page == current)
                .frame(width: size.width, height: size.height)
                .offset(x: origin.x, y: origin.y)
                .allowsHitTesting(page == current)
                .accessibilityHidden(page != current)
        }
    }

    @ViewBuilder private func pageContent(_ page: Int, interactive: Bool) -> some View {
        let pageItems = model.items(onPage: page)
        if interactive {
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVGrid(columns: columns, spacing: LauncherGeometry.gridSpacing) {
                        ForEach(Array(pageItems.enumerated()), id: \.element.id) { index, item in
                            tile(item, index: index, interactive: true).id(item.id)
                        }
                    }.frame(width: model.gridWidth).frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .padding(.top, 4)
                .onReceive(model.$selectedIndex) { index in
                    guard page == model.pageIndex, !model.pageTransitionActive, model.draggingID == nil,
                          model.visibleItems.indices.contains(index) else { return }
                    // Rapid arrow-key navigation lands on the final selection; the anchor is
                    // animated so intermediate steps do not queue conflicting scroll offsets.
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(model.visibleItems[index].id, anchor: .center)
                    }
                }
            }
        } else {
            // Off-screen neighbour pages only require a static grid representation:
            // no ScrollViewReader, no keyboard selection observers, no drag handles.
            ScrollView(.vertical) {
                LazyVGrid(columns: columns, spacing: LauncherGeometry.gridSpacing) {
                    ForEach(Array(pageItems.enumerated()), id: \.element.id) { index, item in
                        tile(item, index: index, interactive: false).id(item.id)
                    }
                }.frame(width: model.gridWidth).frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .padding(.top, 4)
        }
    }

    private var header: some View {
        ZStack {
            WindowDragHandle(enabled: !model.isFullscreen)
            VStack(spacing: 4) {
                Text("Aplo").font(.system(size: model.preferences.brandNamePoints, weight: .semibold))
                    .padding(.horizontal, clearBackdrop ? 7 : 0)
                    .foregroundStyle(clearBackdrop ? Color.white : Color.primary)

                Text(model.text(model.isContinuousScrolling ? "\(model.visibleApplicationCount) 个应用 · 连续滚动" : "\(model.visibleApplicationCount) 个应用 · \(model.pageCount) 页"))
                    .font(.system(size: model.preferences.textPoints(11))).foregroundStyle(.secondary)
            }.allowsHitTesting(false)
            HStack(alignment: .top) {
                if let folder = model.openFolder, !model.isSearching {
                    HStack(spacing: 8) {
                        Button { model.closeFolder() } label: { Image(systemName: "chevron.left").frame(width: 28, height: LauncherGeometry.smallControlHeight) }
                            .buttonStyle(.plain).accessibilityLabel(model.text("返回全部应用"))
                        if model.renamingFolderID != nil {
                            NativeInput(text: $model.folderNameDraft, placeholder: "文件夹名称", focusGeneration: 0,
                                identifier: "folder-title", language: model.preferences.language, textScale: model.preferences.textScalePercent / 100)
                                .frame(width: 170, height: 30)
                        } else {
                            Button { model.beginRename(folder) } label: {
                                Text(model.name(for: folder)).font(.system(size: model.preferences.textPoints(13), weight: .medium)).lineLimit(2)
                            }.buttonStyle(.plain).disabled(model.preferences.automaticCategories)
                                .accessibilityLabel(model.text(model.preferences.automaticCategories ? "分类名称" : "重命名文件夹"))
                        }
                    }.frame(maxWidth: 230, alignment: .leading)
                }
                Spacer()
                HStack(spacing: 8) {
                    Button { model.onMinimize?() } label: {
                        Image(systemName: "minus").frame(width: 28, height: 30)
                    }.buttonStyle(.plain).accessibilityLabel(model.text("最小化"))
                    Button { model.onDisplayModeRequested?() } label: {
                        Image(systemName: model.isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: model.preferences.textPoints(14))).frame(width: 30, height: 30)
                    }.buttonStyle(.plain).disabled(model.draggingID != nil)
                        .help(model.text("切换全屏 / 小面板 · ⌃⌘F"))
                        .accessibilityLabel(model.text(model.isFullscreen ? "切换小面板" : "切换全屏"))

                }.padding(.horizontal, clearBackdrop ? 4 : 0)

                    .foregroundStyle(clearBackdrop ? Color.white : Color.secondary)
            }.frame(maxHeight: .infinity, alignment: .top).padding(.top, 3)
        }.frame(height: max(44, model.preferences.brandNamePoints * 1.3 + model.preferences.textPoints(11) * 1.3 + 8))
            .help(model.isFullscreen ? model.text("切换小面板") : model.text("拖动顶部移动窗口"))
    }

    private var search: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: model.preferences.textPoints(15), weight: .medium)).foregroundStyle(model.accentColor)
            NativeInput(text: $model.query, placeholder: "搜索应用、拼音或首字母…",
                        focusGeneration: model.focusGeneration,
                        identifier: "app-search", requestsFocus: model.searchExpanded && model.renamingFolderID == nil, language: model.preferences.language, textScale: model.preferences.textScalePercent / 100).frame(height: model.preferences.textPoints(24))
            if !model.query.isEmpty {
                Button { model.query = ""; model.focusGeneration += 1 } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }.buttonStyle(.plain).accessibilityLabel(model.text("清空搜索"))
            }
        }
        .padding(.horizontal, 13).padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(model.accentColor.opacity(0.22)))
    }

    @ViewBuilder private func tile(_ item: LayoutItem, index: Int, interactive: Bool = true) -> some View {
        LauncherTile(model: model, item: item, index: index, selected: model.selectedIndex == index) {
            if model.multiSelectionActive && item.kind == .app { model.toggleItemSelection(item); return }
            model.select(index)
            if item.kind == .folder { model.open(item) }
            else if !model.editing, let id = item.appID, let app = model.app(for: id) { launch(app) }
        }
        .equatable()
        .overlay {
            // Neighbour pages are excluded from hit testing, so their drag handle can
            // never fire. Skipping it avoids creating an AppKit view per off-screen tile.
            if interactive && model.canBeginIconDrag {
                NativeDragHandle(model: model, item: item) {
                    if model.multiSelectionActive && item.kind == .app { model.toggleItemSelection(item); return }
                    model.select(index)
                    if item.kind == .folder { model.open(item) }
                    else if !model.editing, let id = item.appID, let app = model.app(for: id) { launch(app) }
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if model.multiSelectionActive, model.selectedItemIDs.contains(item.id) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.white, model.accentColor)
                    .padding(4).allowsHitTesting(false)
            }
        }
        .modifier(TileDropModifier(model: model, target: item, width: model.tileWidth, enabled: interactive))
        .modifier(TileContextMenuModifier(model: model, item: item, enabled: interactive))
    }

    private var visiblePageRange: Range<Int> {
        let start = min(max(0, model.pageIndex - 3), max(0, model.pageCount - 7))
        return start..<min(model.pageCount, start + 7)
    }

    private var pagination: some View {
        HStack(spacing: 10) {
            Button { model.changePage(by: -1) } label: { Image(systemName: model.navigationDirection == .vertical ? "chevron.up" : "chevron.left").frame(width: 20, height: 22) }
                .buttonStyle(.plain).disabled(model.pageIndex == 0).accessibilityLabel(model.text("上一页"))
            if model.pageCount > 0 {
                ForEach(visiblePageRange, id: \.self) { page in
                    Button { model.requestPage(page) } label: {
                        Capsule().fill(page == model.pageIndex ? model.accentColor : Color.primary.opacity(0.20))
                            .frame(width: page == model.pageIndex ? 14 : 6, height: 6).frame(width: 28, height: 24).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel(model.pageTitle(page))
                        .accessibilityAddTraits(page == model.pageIndex ? .isSelected : [])
                        .overlay { if model.canOrganize { NativePageDropTarget(model: model, page: page) } }
                }
            }
            if model.pageCount > 7 {
                Text("\(model.pageIndex + 1)/\(model.pageCount)").font(.system(size: model.preferences.textPoints(10), design: .monospaced)).foregroundStyle(.secondary)
            }
            Button { model.changePage(by: 1) } label: { Image(systemName: model.navigationDirection == .vertical ? "chevron.down" : "chevron.right").frame(width: 20, height: 22) }
                .buttonStyle(.plain).disabled(model.pageIndex == model.pageCount - 1).accessibilityLabel(model.text("下一页"))
            if model.canOrganize {
                if model.openFolderID == nil && !model.customGridEnabled {
                    Text(model.text("新一页")).font(.system(size: model.preferences.textPoints(10))).foregroundStyle(.secondary)
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(.primary.opacity(0.05), in: Capsule())
                        .overlay { NativePageDropTarget(model: model, page: model.browsingLayout.pages.count) }
                } else if model.openFolderID != nil {
                    Text(model.text("拖到此处移出文件夹")).font(.system(size: model.preferences.textPoints(10))).foregroundStyle(.secondary)
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(.primary.opacity(0.05), in: Capsule())
                        .overlay { NativePageDropTarget(model: model, page: model.rootDisplayPages.count - 1) }
                }
            }
        }.foregroundStyle(.secondary).frame(maxWidth: .infinity).frame(height: 24)

    }
}

private struct TileAppearanceKey: Equatable, Sendable {
    let iconSize: CGFloat
    let labelHeight: CGFloat
    let textScale: Double
    let showNames: Bool
    let font: String
    let weight: LauncherLabelWeight
    let color: LauncherLabelColor
    let colorHex: String
    let transparentLabels: Bool
    let vision: LauncherColorVision
    let magnify: Bool
    let animate: Bool
}
struct LauncherTile: View, Equatable {
    let model: LauncherModel
    @ObservedObject private var dragFeedback: TileDragFeedback
    let item: LayoutItem
    let selected: Bool
    let keyboardSelected: Bool
    let index: Int
    let displayName: String
    let accessibilityName: String
    private let appearance: TileAppearanceKey
    private let editing: Bool
    private let draggingID: String?
    private let freePlacement: Bool
    private let continuous: Bool
    let action: () -> Void
    init(model: LauncherModel, item: LayoutItem, index: Int, selected: Bool, action: @escaping () -> Void) {
        self.model = model; self.item = item; self.index = index; self.selected = selected; self.keyboardSelected = selected && model.keyboardSelectionActive; self.action = action
        self.displayName = model.name(for: item)
        self.accessibilityName = model.text((item.kind == .folder ? "打开文件夹 " : "打开 ") + displayName)
        self.editing = model.editing; self.draggingID = model.draggingID
        self.freePlacement = model.usesFreePlacement; self.continuous = model.isContinuousScrolling
        let p = model.preferences
        self.appearance = TileAppearanceKey(iconSize: min(p.iconPoints(fullscreen: model.isFullscreen), max(24, model.tileWidth - 18)), labelHeight: p.labelHeight, textScale: p.textScalePercent, showNames: p.showNames, font: p.labelFontFamily, weight: p.labelWeight, color: p.labelColor, colorHex: p.labelColorHex, transparentLabels: p.backgroundTransparency > 0.7, vision: p.colorVision, magnify: p.magnificationEnabled, animate: p.animationsEnabled)
        self.dragFeedback = model.dragFeedback(for: item.id)
    }
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.model === rhs.model && lhs.item == rhs.item && lhs.index == rhs.index && lhs.selected == rhs.selected && lhs.keyboardSelected == rhs.keyboardSelected && lhs.displayName == rhs.displayName && lhs.accessibilityName == rhs.accessibilityName && lhs.appearance == rhs.appearance && lhs.editing == rhs.editing && lhs.draggingID == rhs.draggingID && lhs.freePlacement == rhs.freePlacement && lhs.continuous == rhs.continuous
    }
    private var iconSize: CGFloat { appearance.iconSize }
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var clearBackdrop: Bool { model.preferences.backgroundTransparency > 0.7 && !reduceTransparency }
    @Environment(\.colorScheme) private var colorScheme
    private var previewChildren: [String]? {
        guard dragFeedback.isMergeTarget,
              let sourceID = model.draggingID else { return nil }
        let source = model.browsingLayout.allItems.first { $0.id == sourceID }
        let incoming = source.map { $0.kind == .folder ? $0.children : [$0.appID].compactMap { $0 } }
            ?? (sourceID.hasPrefix("app:") ? [String(sourceID.dropFirst(4))] : [])
        let current = item.kind == .folder ? item.children : [item.appID].compactMap { $0 }
        var seen = Set<String>()
        return (current + incoming).filter { seen.insert($0).inserted }
    }
    /// The 3×3 folder preview. Built from plain stacks so laying it out costs nothing
    /// more than fixed frames; a fixed-column grid would run its own layout each pass.
    @ViewBuilder private func folderPreview(_ ids: [String]) -> some View {
        let side = iconSize * 0.23
        let visible = Array(ids.prefix(9))
        let rows = max(1, (visible.count + 2) / 3)
        VStack(spacing: 2) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { column in
                        let index = row * 3 + column
                        if visible.indices.contains(index), let app = model.app(for: visible[index]) {
                            Image(nsImage: model.previewIcon(for: app, notifying: dragFeedback))
                                .resizable().interpolation(.high)
                                .frame(width: side, height: side)
                        } else {
                            Color.clear.frame(width: side, height: side)
                        }
                    }
                }
            }
        }.padding(4)
    }
    private var nativeIcon: NSImage? {
        guard item.kind == .app, previewChildren == nil, let id = item.appID, let app = model.app(for: id) else { return nil }
        return model.icon(for: app, notifying: dragFeedback)
    }
    private var iconIdentity: IconRenderIdentity {
        let ids = previewChildren ?? (item.kind == .folder ? item.children : [item.appID].compactMap { $0 })
        // One pass over the children: resolve the app and read the cached bitmap pointer
        // without scheduling raster work on each SwiftUI diff pass.
        var images: [ObjectIdentifier] = []
        images.reserveCapacity(min(ids.count, 9))
        for id in ids.prefix(9) {
            guard let app = model.app(for: id) else { continue }
            images.append(model.cachedIconIdentity(for: app))
        }
        return IconRenderIdentity(item: item, children: previewChildren,
                                  images: images,
                                  size: iconSize, colorVision: appearance.vision,
                                  badgePoints: 8 * appearance.textScale / 100, dark: colorScheme == .dark)
    }
    var body: some View {
        // Read the preference bundle once instead of copying the whole struct for every
        // modifier below; this body runs for every visible tile on every scroll frame.
        let p = appearance
        let continuous = model.isContinuousScrolling
        let dragging = model.draggingID
        return Button(action: action) {
            VStack(spacing: 4) {
                DockMagnifiedIcon(identity: iconIdentity, image: nativeIcon, enabled: p.magnify && !model.editing && dragging == nil && !reduceMotion,
                                  animated: p.animate && !reduceMotion,
                                  wiggling: editing && draggingID == nil && p.animate && !reduceMotion) {
                Group {
                if item.kind == .folder || previewChildren != nil {
                    ZStack {
                        RoundedRectangle(cornerRadius: 13)
                            .fill(LinearGradient(colors: [model.accentColor.opacity(0.20), model.accentColor.opacity(0.075)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                        RoundedRectangle(cornerRadius: 13).strokeBorder(model.accentColor.opacity(0.15))
                        // Plain stacks instead of a fixed VGrid: the grid runs its own
                        // column layout on every pass, while three rows of fixed frames
                        // produce the identical 3×3 preview for a fraction of the cost.
                        folderPreview(previewChildren ?? item.children)
                    }.frame(width: iconSize, height: iconSize)
                        .overlay(alignment: .bottomTrailing) {
                            if previewChildren == nil { Text("\(item.children.count)").lineLimit(1).minimumScaleFactor(0.5).font(.system(size: 8 * p.textScale / 100, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 4).padding(.vertical, 2)
                                .frame(maxWidth: max(1, iconSize - 6))
                                .background(.regularMaterial, in: Capsule()).padding(3) }
                        }
                } else if let id = item.appID, let app = model.app(for: id) {
                    Image(nsImage: model.icon(for: app, notifying: dragFeedback)).resizable().interpolation(.high).frame(width: iconSize, height: iconSize)
                }
                }
                }.frame(width: iconSize, height: iconSize)
                    .opacity(dragging == item.id && !model.usesFreePlacement ? 0.25 : 1)
                Text(displayName).font(model.applicationLabelFont)
                    .foregroundStyle(model.applicationLabelColor)
                    .lineLimit(2).multilineTextAlignment(.center)
                    .padding(.horizontal, clearBackdrop ? 4 : 0)
                    // Skip the glyph shadow while a gesture or transition is animating;
                    // blurred text shadows are the most expensive per-tile layer effect.
                    .shadow(color: clearBackdrop && !continuous && !model.pageTransitionActive ? (p.color == .black ? .white.opacity(0.6) : .black.opacity(0.65)) : .clear, radius: 1, y: 1)
                    .frame(height: p.labelHeight, alignment: .top)
                    .opacity(p.showNames ? 1 : 0).accessibilityHidden(!p.showNames)
            }
            .padding(.top, 10).padding(.bottom, 4).frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .zIndex(hovered ? 1 : 0)
        .buttonStyle(LauncherPressStyle(animated: p.animate && !reduceMotion)).onHover { if dragging == nil && !model.editing {
            hovered = $0
            if $0 { model.hoveredAppID = item.appID }
            else if model.hoveredAppID == item.appID { model.hoveredAppID = nil }
        } }
        // The label already shows the name, so a tooltip only adds an AppKit tracking
        // area per tile. Keep it solely for the name-hidden mode where it still helps.
        .help(p.showNames ? "" : displayName)
        .animation(reduceMotion || continuous || !p.animate || dragging != nil ? nil : .easeOut(duration: 0.12), value: hovered)
        .overlay {
            if keyboardSelected {
                RoundedRectangle(cornerRadius: 14).strokeBorder(model.accentColor.opacity(0.65), lineWidth: 1.5)
                    .padding(3).allowsHitTesting(false)
            }
        }
        .accessibilityLabel(accessibilityName)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct TileDropModifier: ViewModifier {
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

private struct TileContextMenuModifier: ViewModifier {
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
                Button(model.text("移至废纸篓…"), role: .destructive) { model.onTrashApplication?(app) }
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
        return .center
    }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard validateDrop(info: info) else { return DropProposal(operation: .forbidden) }
        let p = position(info)
        let hint: String
        if p == .center && model.openFolderID == nil {
            hint = target.kind == .folder ? "松开移入文件夹" : "松开组成文件夹"
        } else { hint = p == .after ? "松开放在后面" : "松开放在前面" }
        model.updateDropTarget(target.id, hint: hint)
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

struct MessageBanner: View {
    @ObservedObject var model: LauncherModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
      Group {
        if let message = model.message {
            HStack(spacing: 5) {
                if model.importInProgress { ProgressView().controlSize(.small) }
                else { Image(systemName: "info.circle") }
                Text(message.localized(language: model.preferences.language)).lineLimit(2)
                Spacer(minLength: 0)
                if model.importInProgress {
                    Button(model.text("取消导入")) { model.onCancelImport?() }.buttonStyle(.plain)
                } else { Button { model.message = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).accessibilityLabel(model.text("关闭提示")) }
            }.font(.system(size: model.preferences.textPoints(11))).foregroundStyle(.primary)
                .padding(9).background(model.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                .padding(.bottom, 6)
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
        }
      }.animation(model.preferences.animationsEnabled && !reduceMotion ? .easeInOut(duration: LauncherGeometry.messageTransitionDuration) : nil, value: model.message)

    }
}

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

final class LauncherTextField: NSTextField {
    var pendingFocus: (@MainActor @Sendable () -> Void)?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in self?.pendingFocus?() }
    }
}

struct NativeInput: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let focusGeneration: Int
    let identifier: String
    var requestsFocus = true
    var language: LauncherLanguage = .system
    var textScale = 1.0
    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }
    func makeNSView(context: Context) -> NSTextField {
        let field = LauncherTextField(string: text)
        field.placeholderString = AppStrings.text(placeholder, language: language)
        field.font = NSFont.systemFont(ofSize: (identifier == "folder-title" ? 17 : 15) * textScale)
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = context.coordinator
        field.identifier = NSUserInterfaceItemIdentifier(identifier)
        field.setAccessibilityLabel(AppStrings.text(identifier == "folder-title" ? "文件夹名称" : "搜索应用", language: language))
        return field
    }
    func updateNSView(_ field: NSTextField, context: Context) {
        field.font = NSFont.systemFont(ofSize: (identifier == "folder-title" ? 17 : 15) * textScale)
        field.placeholderString = AppStrings.text(placeholder, language: language)
        field.setAccessibilityLabel(AppStrings.text(identifier == "folder-title" ? "文件夹名称" : "搜索应用", language: language))
        context.coordinator.text = $text
        if field.stringValue != text { field.stringValue = text }
        if requestsFocus && context.coordinator.generation != focusGeneration {
            let coordinator = context.coordinator
            let expectedGeneration = focusGeneration
            let selectAll = identifier == "folder-title"
            let focus: @MainActor @Sendable () -> Void = { [weak field, weak coordinator] in
                guard let field, let coordinator, coordinator.generation != expectedGeneration,
                      let window = field.window, window.isVisible else { return }
                guard window.makeFirstResponder(field) else { return }
                coordinator.generation = expectedGeneration
                (field as? LauncherTextField)?.pendingFocus = nil
                if let editor = field.currentEditor() {
                    (editor as? NSTextView)?.allowsUndo = true
                    editor.selectedRange = selectAll ? NSRange(location: 0, length: field.stringValue.utf16.count)
                        : NSRange(location: field.stringValue.utf16.count, length: 0)
                }
            }
            (field as? LauncherTextField)?.pendingFocus = focus
            DispatchQueue.main.async(execute: focus)
        } else if !requestsFocus {
            (field as? LauncherTextField)?.pendingFocus = nil
        }
    }
    @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var generation: Int?
        init(text: Binding<String>) { self.text = text }
        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSTextField { text.wrappedValue = field.stringValue }
        }
    }
}


private struct PageStrip<Content: View>: View {
    @ObservedObject var motion: PagePresentation
    let size: CGSize
    let content: Content
    init(motion: PagePresentation, size: CGSize, @ViewBuilder content: () -> Content) {
        self.motion = motion; self.size = size; self.content = content()
    }
    var body: some View {
        // Rasterize the page strip once, then translate the finished layer. Applying the
        // group before the offset keeps the drag a GPU transform instead of re-rendering
        // every tile's shadows and materials on each frame of the gesture.
        content.compositingGroup()
            .offset(x: motion.axis == .horizontal ? motion.offset : 0,
                    y: motion.axis == .vertical ? motion.offset : 0)
            .allowsHitTesting(!motion.active)
    }
}

private struct PageInteractionLock<Content: View>: View {
    @ObservedObject var motion: PagePresentation
    let content: Content
    init(motion: PagePresentation, @ViewBuilder content: () -> Content) {
        self.motion = motion; self.content = content()
    }
    var body: some View { content.disabled(motion.active).allowsHitTesting(!motion.active) }
}


private struct FreeCanvasEntry: Identifiable, Equatable {
    let item: LayoutItem
    let index: Int
    let origin: CGPoint
    var id: String { item.id }
}
/// AppKit scroll bounds notifications also work when SwiftUI does not re-evaluate geometry during native scrolling.
private final class CanvasScrollObservation: @unchecked Sendable {
    let token: NSObjectProtocol
    init(_ token: NSObjectProtocol) { self.token = token }
    deinit { NotificationCenter.default.removeObserver(token) }
}
private struct CanvasViewportMonitor: NSViewRepresentable {
    let tileSize: CGSize
    let revealRect: CGRect?
    let revealGeneration: Int
    let changed: (CGRect) -> Void
    func makeNSView(context: Context) -> CanvasViewportView { CanvasViewportView() }
    func updateNSView(_ view: CanvasViewportView, context: Context) {
        view.changed = changed; view.tileSize = tileSize
        if view.revealGeneration != revealGeneration {
            view.revealGeneration = revealGeneration
            if let revealRect { DispatchQueue.main.async { [weak view] in _ = view?.scrollToVisible(revealRect.insetBy(dx: -8, dy: -8)) } }
        }
    }
}
private final class CanvasViewportView: NSView {
    var revealGeneration = -1
    var tileSize = CGSize(width: 100, height: 100)
    private var gate = CanvasViewportGate()
    var changed: ((CGRect) -> Void)?
    private weak var clip: NSClipView?
    private var observation: CanvasScrollObservation?
    private var scheduled = false
    private var latest = CGRect.zero
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { observation = nil; clip = nil; gate = CanvasViewportGate() }
        else { DispatchQueue.main.async { [weak self] in self?.attach() } }
    }
    override func layout() { super.layout(); attach(); sample() }
    private func attach() {
        guard window != nil, let scroll = enclosingScrollView else { return }
        if clip !== scroll.contentView {
            observation = nil; clip = scroll.contentView
            scroll.contentView.postsBoundsChangedNotifications = true
            let token = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
                object: scroll.contentView, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.sample() }
            }
            observation = CanvasScrollObservation(token)
        }
        sample()
    }
    private func sample() {
        guard let clip else { return }
        latest = convert(clip.bounds, from: clip)
        guard !scheduled else { return }
        scheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.scheduled = false
            if self.window != nil, self.gate.shouldPublish(self.latest, tile: self.tileSize) { self.changed?(self.latest) }
        }
    }
}

private struct CulledFreeCanvas<Content: View>: View {
    let entries: [FreeCanvasEntry]
    let canvas: CGSize
    let viewport: CGSize
    let tileSize: CGSize
    let draggedID: String?
    let selectedID: String?
    let revealGeneration: Int
    let begin: (String) -> Void
    let end: () -> Void
    let save: (String, FreeIconPosition) -> Void
    @ViewBuilder let content: (FreeCanvasEntry) -> Content
    @State private var visibleViewport: CGRect?
    var body: some View {
        let visible = visibleViewport?.insetBy(dx: -tileSize.width * 2, dy: -tileSize.height * 2)
        ZStack(alignment: .topLeading) {
            ForEach(entries.filter { entry in entry.id == draggedID || entry.id == selectedID || (visible.map { CGRect(origin: entry.origin, size: tileSize).intersects($0) } ?? true) }) { entry in
                FreePlacementTile(origin: entry.origin, canvas: canvas, size: tileSize,
                    begin: { begin(entry.id) }, end: end, save: { save(entry.id, $0) }) { content(entry) }
            }
        }.frame(width: canvas.width, height: canvas.height, alignment: .topLeading)
            .background(CanvasViewportMonitor(tileSize: tileSize, revealRect: entries.first { $0.id == selectedID }.map { CGRect(origin: $0.origin, size: tileSize) }, revealGeneration: revealGeneration) { rect in if visibleViewport != rect { visibleViewport = rect } })
            .frame(maxWidth: .infinity)
    }
}

private struct FreePlacementTile<Content: View>: View {
    let origin: CGPoint
    let canvas: CGSize
    let size: CGSize
    let begin: () -> Void
    let end: () -> Void
    let save: (FreeIconPosition) -> Void
    @ViewBuilder var content: () -> Content
    @GestureState private var translation = CGSize.zero
    @State private var interacting = false
    var body: some View {
        content().frame(width: size.width, height: size.height)
            .offset(x: origin.x + translation.width, y: origin.y + translation.height)
            .zIndex(translation == .zero ? 0 : 1)
            .highPriorityGesture(DragGesture(minimumDistance: 4)
                .updating($translation) { value, state, _ in
                    let point = FreePlacementGeometry.origin(position: nil,
                        fallback: CGPoint(x: origin.x + value.translation.width, y: origin.y + value.translation.height), canvas: canvas, tile: size)
                    state = CGSize(width: point.x - origin.x, height: point.y - origin.y)
                }
                .onChanged { _ in if !interacting { interacting = true; begin() } }
                .onEnded { value in
                    save(FreePlacementGeometry.normalized(origin: CGPoint(x: origin.x + value.translation.width, y: origin.y + value.translation.height), canvas: canvas, tile: size))
                    interacting = false; end()
                })
            .onChange(of: translation == .zero) { reset in
                if reset && interacting { interacting = false; end() }
            }
            .onDisappear { if interacting { interacting = false; end() } }
    }
}

private struct LauncherPressStyle: ButtonStyle {
    let animated: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed && animated ? 0.95 : 1)
            .animation(animated ? .interactiveSpring(response: 0.18, dampingFraction: 0.85) : nil, value: configuration.isPressed)
    }
}
