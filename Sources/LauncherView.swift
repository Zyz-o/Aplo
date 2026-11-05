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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var clearBackdrop: Bool { model.preferences.backgroundTransparency > 0.7 && !reduceTransparency }
    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: LauncherGeometry.gridSpacing), count: model.columnCount) }

    var body: some View {
        Group {
            if model.showingSettings { SettingsView(model: model).frame(maxWidth: 1000, maxHeight: 720)
                    .clipShape(RoundedRectangle(cornerRadius: AploVisual.windowRadius))
                    .overlay(RoundedRectangle(cornerRadius: AploVisual.windowRadius).strokeBorder(.primary.opacity(0.10))) }
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
            if model.preferences.showFrameStats && !model.showingSettings && model.inspectingApp == nil {
                FrameStatsOverlay(active: true)
                    .frame(width: 240, height: 24)
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
            header.frame(maxWidth: model.gridWidth).padding(.bottom, 10)
            if showsTopSearch {
                search.frame(maxWidth: 390).padding(.bottom, 12)
                    .opacity(model.editing ? 0.45 : 1)
                    .allowsHitTesting(!model.editing).accessibilityHidden(model.editing)
            }
            if model.preferences.toolbarPosition == .top { toolbar.padding(.bottom, 12) }
            MessageBanner(model: model)
            if let result = model.inlineResult { InlineResultView(model: model, result: result) }
            if model.isSearching && model.inlineResult == nil { SearchCategoryBar(model: model).padding(.bottom, 12) }
            frequentRow
            // Opening or closing a folder swaps the whole grid; a short cross-fade keeps
            // the change legible without animating dozens of tiles individually.
            Group {
                if model.usesFreePlacement { freeContent }
                else if model.visibleItems.isEmpty {
                    LauncherEmptyState(model: model)
                } else if model.isContinuousScrolling {
                    continuousContent
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
            }
            .id(model.openFolderID ?? "root")
            .transition(.opacity)
            .animation(model.preferences.animationsEnabled ? .easeInOut(duration: 0.15) : nil, value: model.openFolderID)
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
                        Button(model.text("页面顺序…")) { model.beginEditing(); model.showingPageOrganizer = true }
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

    private var showsTopSearch: Bool { model.isFullscreen && model.openFolderID == nil }

    private var toolbar: some View {
        ZStack {
                HStack {
                    HStack(spacing: 8) {
                        if !showsTopSearch && !model.editing {
                        Button {
                            model.searchExpanded.toggle()
                            if model.searchExpanded { model.focusGeneration += 1 } else { model.query = "" }
                        } label: { Image(systemName: model.searchExpanded ? "xmark" : "magnifyingglass").frame(width: 34, height: 34) }
                            .buttonStyle(.plain).accessibilityLabel(model.text("搜索应用"))
                        }
                        if model.editing {
                            Text(model.text(model.dropDescription)).lineLimit(1)
                        } else if model.searchExpanded && !showsTopSearch {
                            search.frame(maxWidth: 290)
                        } else {
                            Text(model.text("\(model.visibleApplicationCount) 个应用")).monospacedDigit()
                        }
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

    @ViewBuilder private var frequentRow: some View {
        // Keep drop targets stationary when a drag switches the grid into editing.
        let preserveGridPosition = model.isContinuousScrolling && !model.usesFreePlacement
        if model.openFolderID == nil && !model.isSearching && (!model.editing || preserveGridPosition) {
            let recent = model.recentApplications
            let minimumHeight = max(575, 390 + model.displayedIconSize + model.preferences.labelHeight)
            if !recent.isEmpty && (model.isFullscreen || model.displayHeight >= minimumHeight) {
                VStack(spacing: 8) {
                    HStack(spacing: LauncherGeometry.gridSpacing) {
                        ForEach(recent, id: \.id) { app in
                            LauncherTile(model: model, item: .app(app.id), index: -1, selected: false) { launch(app) }
                                .equatable().frame(width: model.tileWidth)
                                // Slightly desaturated so the pinned row reads as a
                                // shortcut strip rather than part of the main grid.
                                .saturation(0.9)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .contain).accessibilityLabel(model.text("最近使用"))
                    Divider()
                }.frame(width: model.gridWidth).frame(maxWidth: .infinity).padding(.bottom, 8)
                    .allowsHitTesting(!model.editing).accessibilityHidden(model.editing)
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
        }.frame(height: max(44, model.preferences.brandNamePoints * 1.3 + 8))
            .help(model.isFullscreen ? model.text("切换小面板") : model.text("拖动顶部移动窗口"))
    }

    private var search: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: model.preferences.textPoints(15), weight: .medium)).foregroundStyle(model.accentColor)
            NativeInput(text: $model.query, placeholder: "搜索应用、拼音或首字母…",
                        focusGeneration: model.focusGeneration,
                        identifier: "app-search", requestsFocus: model.searchExpanded && !model.editing && model.renamingFolderID == nil, language: model.preferences.language, textScale: model.preferences.textScalePercent / 100).frame(height: model.preferences.textPoints(24))
            if !model.query.isEmpty {
                Button { model.query = ""; model.focusGeneration += 1 } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }.buttonStyle(.plain).accessibilityLabel(model.text("清空搜索"))
            }
        }
        .padding(.horizontal, 13).padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AploVisual.panelRadius))
        .overlay(RoundedRectangle(cornerRadius: AploVisual.panelRadius)
            .strokeBorder(model.accentColor.opacity(AploVisual.panelStroke(dark: scheme == .dark,
                                                                         increaseContrast: AploAccessibility.increasesContrast,
                                                                         active: model.searchExpanded)),
                          lineWidth: model.searchExpanded ? 1.5 : 1))
        .shadow(color: model.searchExpanded ? model.accentColor.opacity(0.2) : .clear, radius: 8)
        .animation(.easeOut(duration: 0.18), value: model.searchExpanded)
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
                            // The active pill expands instead of jumping, so the eye can
                            // follow the page change without counting dots.
                            .frame(width: page == model.pageIndex ? 14 : 6, height: 6)
                            .animation(model.preferences.animationsEnabled && !reduceMotion
                                       ? .spring(response: 0.28, dampingFraction: 0.8) : nil,
                                       value: model.pageIndex)
                            .frame(width: 28, height: 24).contentShape(Rectangle())
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
