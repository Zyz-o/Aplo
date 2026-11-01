import AppKit
import Foundation

// A worker owns and copies the native image before handing it to MainActor.
// No view or layer is accessed by the worker, and the delivered image is read-only.
private struct IconDelivery: @unchecked Sendable { let image: NSImage }
@MainActor private final class WeakTileFeedback {
    weak var value: TileDragFeedback?
    init(_ value: TileDragFeedback) { self.value = value }
}

enum ItemDropPosition: Sendable { case before, center, after }

@MainActor
final class PagePresentation: ObservableObject {
    enum Axis { case horizontal, vertical }
    @Published var axis: Axis = .horizontal
    @Published var offset: CGFloat = 0
    @Published var active = false
}

/// Drag destination changes invalidate only the tiles whose appearance actually changes.
@MainActor final class TileDragFeedback: ObservableObject {
    @Published private(set) var isMergeTarget = false
    func setMergeTarget(_ value: Bool) {
        if isMergeTarget != value { isMergeTarget = value }
    }
}

@MainActor
final class LauncherModel: ObservableObject {
    @Published var isFullscreen = false {
        didSet { if oldValue != isFullscreen && !switchingDisplayMode { switchLayoutMode(from: oldValue) } }
    }
    private var switchingDisplayMode = false
    @Published var displayWidth: CGFloat = 960
    // High-frequency input updates only the page strip, never the app grid or text field.
    let pageMotion = PagePresentation()
    var pageDragOffset: CGFloat {
        get { pageMotion.offset }
        set { if pageMotion.offset != newValue { pageMotion.offset = newValue } }
    }
    var pageTransitionActive: Bool {
        get { pageMotion.active }
        set { if pageMotion.active != newValue { pageMotion.active = newValue } }
    }
    @Published var horizontalRowCount = 3
    @Published var pageHeight: CGFloat = 400
    var pageWidth: CGFloat { max(1, displayWidth - 2 * LauncherGeometry.contentInset(fullscreen: isFullscreen)) }
    var pageExtent: CGFloat { pageMotion.axis == .vertical ? max(1, pageHeight) : pageWidth }
    var columnCount: Int { LauncherGeometry.columnCount(displayWidth: displayWidth, fullscreen: isFullscreen) }
    var gridWidth: CGFloat { LauncherGeometry.gridWidth(displayWidth: displayWidth, fullscreen: isFullscreen) }
    var onResetWindowPosition: (() -> Void)?
    var onDisplayModeRequested: (() -> Void)?
    var onMinimize: (() -> Void)?
    @Published var query = "" { didSet { cachedContainerItems = nil; filter() } }
    @Published private(set) var initialDiscoveryPending = true
    @Published private(set) var apps: [InstalledApp] = []
    @Published private(set) var results: [InstalledApp] = [] { didSet { cachedContainerItems = nil } }
    var onNavigate: (() -> Void)?
    var onPageRequested: ((Int) -> Void)?
    @Published private(set) var selectedIndex = 0 { didSet { if oldValue != selectedIndex { onNavigate?() } } }
    @Published private(set) var layout: LauncherLayout { didSet { cachedContainerItems = nil } }
    @Published private(set) var pageIndex = 0 { didSet { if oldValue != pageIndex { onNavigate?() } } }
    @Published private(set) var openFolderID: String? { didSet { cachedContainerItems = nil } }
    @Published var message: String?
    @Published var focusGeneration = 0
    @Published var shortcutAvailable = true
    @Published var editing = false
    var onSettingsVisibilityChanged: (() -> Void)?
    var onPreferencesChanged: ((PreferenceChanges) -> Void)?
    @Published private(set) var preferences: LauncherPreferences { didSet { cachedContainerItems = nil } }
    @Published var presentingAppearancePreview = false { didSet { onAppearancePreviewChanged?() } }
    var onAppearancePreviewChanged: (() -> Void)?
    @Published var searchExpanded = false
    @Published var showingSettings = false {
        didSet { if oldValue != showingSettings { onSettingsVisibilityChanged?() } }
    }
    @Published var recordingShortcut = false
    @Published var renamingFolderID: String?
    @Published var folderNameDraft = ""
    @Published var draggingID: String? {
        didSet {
            if CommandLine.arguments.contains("--diagnostics") {
                FileHandle.standardError.write(Data(("[Aplo] drag source=\(draggingID ?? "none")\n").utf8))
            }
        }
    }
    private(set) var dropTargetID: String?
    private var currentDropHint: String?
    var dropHint: String? {
        get { currentDropHint }
        set { setDropTarget(newValue == nil ? nil : dropTargetID, hint: newValue) }
    }
    private var tileFeedback: [String: TileDragFeedback] = [:]
    func dragFeedback(for id: String) -> TileDragFeedback {
        if let feedback = tileFeedback[id] { return feedback }
        let feedback = TileDragFeedback()
        tileFeedback[id] = feedback
        return feedback
    }
    var onShortcutRequested: ((ShortcutBinding) -> Bool)?
    var onRecordingChanged: ((Bool) -> Void)?
    var onExport: (() -> Void)?
    var onRestore: (() -> Void)?
    var onLegacyImport: (() -> Void)?
    var onNativeImport: (() -> Void)?
    private let preferencesStore: PreferencesStore
    private var pendingPreferencesSave: Task<Void, Never>?
    private var preferencesDirty = false
    private let searchIndex = IntegratedSearch()
    private let catalog: AppCatalog
    let store: LayoutStore
    private var icons: [String: NSImage] = [:]
    private let iconQueue: OperationQueue = {
        let queue = OperationQueue(); queue.name = "Aplo.IconPrefetch"
        queue.maxConcurrentOperationCount = 1; queue.qualityOfService = .utility
        return queue
    }()
    private var iconJobs: [String: BlockOperation] = [:]
    private var iconTokens: [String: UUID] = [:]
    private var iconWaiters: [String: [ObjectIdentifier: WeakTileFeedback]] = [:]
    private static let pendingIcon = NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)!
    private var iconWarmup: Task<Void, Never>?
    // Native scrolling owns the frame budget; no published changes per event.
    private var scrollBusyUntil: TimeInterval = 0
    func noteScrollInteraction() { scrollBusyUntil = ProcessInfo.processInfo.systemUptime + 0.15 }
    private var scrollInteractionActive: Bool { ProcessInfo.processInfo.systemUptime < scrollBusyUntil }
    private var catalogRefresh: Task<Void, Never>?
    private var refreshGeneration: UInt64 = 0
    private var lastCompletedScan: TimeInterval?
    private var refreshInFlight = false
    private var hasTrustedInventory = false
    private var completedRefreshGeneration: UInt64 = 0
    @Published var importInProgress = false
    var onCancelImport: (() -> Void)?
    private var iconVersions: [String: [Date]] = [:]
    private var lookup: [String: InstalledApp] = [:]
    private var startupMessage: String?
    private var canWriteLayout = true
    private var categorizedLayout = LauncherLayout() { didSet { cachedContainerItems = nil } }
    private var cachedContainerItems: [LayoutItem]?

    init(catalog: AppCatalog = AppCatalog(includeSystemApplications: true), store: LayoutStore = .standard, defaults: UserDefaults = .standard) {
        preferencesStore = PreferencesStore(defaults: defaults)
        preferences = preferencesStore.load()
        self.catalog = catalog
        self.store = store
        do { layout = try store.load() ?? LauncherLayout() }
        catch {
            layout = LauncherLayout()
            do {
                _ = try store.archiveCurrent()
                startupMessage = "布局文件无法读取，原文件已保留到 Backups；暂时使用默认排列。"
            } catch {
                canWriteLayout = false
                startupMessage = "布局无法读取，且无法备份原文件。请先检查布局文件的访问权限。"
            }
        }
        layout.prepareDisplayMode(fullscreen: isFullscreen)
        pageMotion.axis = preferences.pagingDirection == .vertical ? .vertical : .horizontal
    }

    private func switchLayoutMode(from previousMode: Bool) {
        var updated = layout
        updated.prepareDisplayMode(fullscreen: isFullscreen)
        if !commit(updated) {
            switchingDisplayMode = true
            isFullscreen = previousMode
            switchingDisplayMode = false
            return
        }
        editing = false; endDrag(); openFolderID = nil; renamingFolderID = nil
        query = ""; pageIndex = 0; selectedIndex = 0; focusGeneration += 1
        pageMotion.active = false; pageMotion.offset = 0
    }

    var isSearching: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var browsingLayout: LauncherLayout { preferences.automaticCategories ? categorizedLayout : layout }
    var openFolder: LayoutItem? { browsingLayout.folders.first { $0.id == openFolderID } }
    var containerItems: [LayoutItem] {
        if let cachedContainerItems { return cachedContainerItems }
        let items: [LayoutItem]
        if isSearching { items = results.map { .app($0.id) } }
        else {
            let source = openFolder.map { $0.children.map { LayoutItem.app($0) } } ?? browsingLayout.allItems
            items = isContinuousScrolling && preferences.systemAppsLast ? AppClassifier.systemLast(source, appsByID: lookup) : source
        }
        cachedContainerItems = items
        return items
    }
    var pageCount: Int {
        if !isSearching && openFolder == nil { return max(1, browsingLayout.pages.count) }
        return max(1, (containerItems.count + LauncherLayout.pageSize - 1) / LauncherLayout.pageSize)
    }
    var isContinuousScrolling: Bool { preferences.navigationStyle == .continuous || usesFreePlacement }
    var visibleItems: [LayoutItem] { isContinuousScrolling ? containerItems : items(onPage: pageIndex) }
    func items(onPage page: Int) -> [LayoutItem] {
        guard page >= 0 else { return [] }
        if !isSearching && openFolder == nil {
            return browsingLayout.pages.indices.contains(page) ? browsingLayout.pages[page] : []
        }
        let items = containerItems
        let start = page * LauncherLayout.pageSize
        guard start < items.count else { return [] }
        return Array(items[start..<min(start + LauncherLayout.pageSize, items.count)])
    }
    var selectedItem: LayoutItem? {
        visibleItems.indices.contains(selectedIndex) ? visibleItems[selectedIndex] : nil
    }
    var selectedApp: InstalledApp? { selectedItem?.appID.flatMap { lookup[$0] } }
    var canBeginIconDrag: Bool { !preferences.automaticCategories && !isSearching && !showingSettings && !usesFreePlacement && !importInProgress }
    func beginInteractiveDrag(_ id: String) {
        guard canBeginIconDrag else { return }
        editing = true
        draggingID = id
    }
    var canOrganize: Bool { !preferences.automaticCategories && editing && !isSearching && !showingSettings }
    var shortcutLabel: String { shortcutAvailable ? layout.shortcut.displayName : "菜单栏打开" }
    var dropDescription: String { if usesFreePlacement { return "拖动图标自由放置 · 整理菜单可返回网格" }; return dropHint ?? (openFolder == nil ? "拖到图标中心分组，边缘排序" : "拖放排序 · 右键可移出文件夹") }

    func updatePreferences(_ change: (inout LauncherPreferences) -> Void) {
        var updated = preferences
        change(&updated)
        if updated.pinToDesktop && !preferences.pinToDesktop { updated.dismissStyle = .escapeOnly }
        guard updated != preferences else { return }
        let orderingChanged = updated.systemAppsLast != preferences.systemAppsLast
        let navigationChanged = updated.navigationStyle != preferences.navigationStyle || updated.pagingDirection != preferences.pagingDirection
        let categoryChanged = updated.automaticCategories != preferences.automaticCategories
        let languageChanged = updated.language != preferences.language
        let changes = PreferenceChanges(from: preferences, to: updated)
        preferences = updated
        preferencesDirty = true
        pendingPreferencesSave?.cancel()
        if changes.contains(.deferredSave) {
            pendingPreferencesSave = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
                self?.flushPreferences()
            }
        } else { flushPreferences() }
        if navigationChanged || orderingChanged { pageIndex = 0; selectedIndex = 0 }
        if categoryChanged { openFolderID = nil; renamingFolderID = nil; folderNameDraft = ""; editing = false; query = ""; focusGeneration += 1 }
        onPreferencesChanged?(changes)
        if languageChanged { requestRefresh(resetSearch: false) }
    }

    func flushPreferences() {
        pendingPreferencesSave?.cancel(); pendingPreferencesSave = nil
        guard preferencesDirty else { return }
        preferencesStore.save(preferences); preferencesDirty = false
    }

    func text(_ source: String) -> String { AppStrings.text(source, language: preferences.language) }
    func app(for id: String) -> InstalledApp? { lookup[id] }
    func name(for item: LayoutItem) -> String {
        item.kind == .folder ? (item.id.hasPrefix("category:") ? text(item.title ?? "文件夹") : item.title ?? "文件夹") : item.appID.flatMap { lookup[$0]?.name }.map { preferences.language.usesTraditionalChinese ? text($0) : $0 } ?? text("应用")
    }
    func icon(for app: InstalledApp, notifying feedback: TileDragFeedback? = nil, prewarm: Bool = false) -> NSImage {
        let path = app.url.path
        if let image = icons[path] { return image }
        if let feedback { iconWaiters[path, default: [:]][ObjectIdentifier(feedback)] = WeakTileFeedback(feedback) }
        if let job = iconJobs[path] {
            if !prewarm { job.queuePriority = .veryHigh }
            return Self.pendingIcon
        }
        let token = UUID(); iconTokens[path] = token
        let job = BlockOperation { [weak self] in
            let delivery = autoreleasepool {
                let image = NSWorkspace.shared.icon(forFile: path)
                return IconDelivery(image: (image.copy() as? NSImage) ?? image)
            }
            Task { @MainActor [weak self] in
                guard let self, self.iconTokens[path] == token else { return }
                self.icons[path] = delivery.image
                self.iconJobs.removeValue(forKey: path); self.iconTokens.removeValue(forKey: path)
                let waiters = self.iconWaiters.removeValue(forKey: path)?.values ?? Dictionary<ObjectIdentifier, WeakTileFeedback>().values
                for waiter in waiters { waiter.value?.objectWillChange.send() }
            }
        }
        job.queuePriority = prewarm ? .low : .veryHigh
        iconJobs[path] = job; iconQueue.addOperation(job)
        return Self.pendingIcon
    }

    /// Synchronous entry retained for deterministic imports/tests. UI presentation uses requestRefresh.
    private var applicationNamingLanguages: [String]? {
        preferences.language == .system ? nil : [preferences.language.localeIdentifier]
    }
    func refresh(resetSearch: Bool = true) {
        refreshGeneration &+= 1
        catalogRefresh?.cancel()
        applySnapshot(catalog.snapshot(preferredLanguages: applicationNamingLanguages), resetSearch: resetSearch)
        completedRefreshGeneration = refreshGeneration
        refreshInFlight = false; lastCompletedScan = ProcessInfo.processInfo.systemUptime
    }
    @discardableResult
    func requestRefresh(resetSearch: Bool = true, minimumInterval: TimeInterval = 0) -> Bool {
        if resetSearch { resetBrowsingState() }
        if minimumInterval > 0 {
            if refreshInFlight { return false }
            if hasTrustedInventory, let lastCompletedScan, ProcessInfo.processInfo.systemUptime - lastCompletedScan < minimumInterval { return false }
        }
        refreshGeneration &+= 1
        refreshInFlight = true
        let generation = refreshGeneration
        catalogRefresh?.cancel()
        let catalog = catalog
        let namingLanguages = applicationNamingLanguages
        let scan = Task.detached(priority: .userInitiated) { catalog.snapshot(preferredLanguages: namingLanguages) }
        catalogRefresh = Task { @MainActor [weak self] in
            let snapshot = await withTaskCancellationHandler(operation: { await scan.value }, onCancel: { scan.cancel() })
            guard !Task.isCancelled, let self, self.refreshGeneration == generation else { return }
            // A completed scan must not replace drag sources or rebuild an animating page.
            while self.draggingID != nil || self.pageTransitionActive || self.scrollInteractionActive {
                try? await Task.sleep(for: .milliseconds(16))
                guard !Task.isCancelled, self.refreshGeneration == generation else { return }
            }
            self.applySnapshot(snapshot, resetSearch: false)
            self.completedRefreshGeneration = generation
            self.refreshInFlight = false
            self.lastCompletedScan = ProcessInfo.processInfo.systemUptime
        }
        return true
    }
    func waitForCatalogRefresh() async { await catalogRefresh?.value }
    private func resetBrowsingState() {
        searchExpanded = false; openFolderID = nil; renamingFolderID = nil
        editing = false; showingSettings = false; query = ""
        focusGeneration += 1
    }
    private func applySnapshot(_ snapshot: CatalogSnapshot, resetSearch: Bool) {
        if initialDiscoveryPending { initialDiscoveryPending = false }
        hasTrustedInventory = snapshot.isComplete
        let inventory: [InstalledApp]
        if snapshot.isComplete { inventory = snapshot.apps }
        else {
            let discovered = Set(snapshot.apps.map(\.id))
            inventory = (snapshot.apps + apps.filter { !discovered.contains($0.id) && FileManager.default.fileExists(atPath: $0.url.path) }).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            let warning = "部分应用暂时无法读取，已保留原布局；请稍后刷新重试。"
            if message != warning { message = warning }
        }
        let inventoryChanged = apps != inventory
        let imagesChanged = iconVersions != snapshot.iconVersions
        if inventoryChanged {
            apps = inventory
            categorizedLayout = AppClassifier.layout(for: apps)
            searchIndex.update(apps)
            lookup = Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) })
            cachedContainerItems = nil
        }
        if imagesChanged {
            iconQueue.cancelAllOperations(); iconJobs.removeAll(); iconTokens.removeAll()
            iconWaiters = iconWaiters.filter { snapshot.iconVersions[$0.key] != nil }
            icons = icons.filter { snapshot.iconVersions[$0.key] != nil && snapshot.iconVersions[$0.key] == iconVersions[$0.key] }
            iconVersions = snapshot.iconVersions
            for feedback in tileFeedback.values { feedback.objectWillChange.send() }
            // Same-path application updates still invalidate visible native icon identities.
            if !inventoryChanged { objectWillChange.send() }
            iconWarmup?.cancel()
            let inventory = apps.filter { icons[$0.url.path] == nil }
            iconWarmup = Task { @MainActor [weak self] in
                for app in inventory {
                    guard !Task.isCancelled, let self else { return }
                    while self.draggingID != nil || self.pageTransitionActive || self.scrollInteractionActive {
                        try? await Task.sleep(for: .milliseconds(16))
                        guard !Task.isCancelled else { return }
                    }
                    _ = self.icon(for: app, prewarm: true)
                    try? await Task.sleep(for: .milliseconds(8))
                }
            }
        }
        var updated = layout
        let originalIDs = Set(layout.appIDs + (layout.otherDisplayLayout?.pages.flatMap { $0 }.flatMap { $0.kind == .app ? [$0.appID].compactMap { $0 } : $0.children } ?? []))
        let retainedIDs = snapshot.isComplete ? apps.map(\.id) : Array(originalIDs.union(apps.map(\.id)))
        updated.reconcile(with: retainedIDs)
        if updated != layout || !FileManager.default.fileExists(atPath: store.url.path) {
            do {
                if !originalIDs.subtracting(retainedIDs).isEmpty { _ = try store.archiveCurrent() }
                if !commit(updated) { layout = updated }
            } catch { message = "无法备份原布局，已暂停移除失效项目。" }
        }
        if openFolderID != nil && openFolder == nil { openFolderID = nil }
        if resetSearch { resetBrowsingState() }
        else if inventoryChanged { filter() }
        if let startupMessage { message = startupMessage; self.startupMessage = nil }
        pruneTileFeedback()
    }

    private func pruneTileFeedback() {
        let other = layout.otherDisplayLayout?.pages.flatMap { $0 }.map(\.id) ?? []
        let valid = Set(layout.allItems.map(\.id) + other + categorizedLayout.allItems.map(\.id) + apps.map { "app:" + $0.id })
        tileFeedback = tileFeedback.filter { valid.contains($0.key) || $0.key == draggingID }
        iconWaiters = iconWaiters.mapValues { $0.filter { $0.value.value != nil } }
    }

    private func filter() {
        results = searchIndex.matching(apps, query: query)
        pageIndex = 0
        selectedIndex = 0
        draggingID = nil
        clearDropTarget()
    }

    func select(_ index: Int) {
        if visibleItems.indices.contains(index) { selectedIndex = index }
    }
    func moveSelection(by offset: Int) {
        guard !containerItems.isEmpty else { return }
        if isContinuousScrolling {
            if preferences.pagingDirection == .horizontal && (abs(offset) == 1 || abs(offset) == columnCount) {
                selectedIndex = LauncherGeometry.horizontalNeighbor(index: selectedIndex, offset: offset, itemCount: containerItems.count, rows: horizontalRowCount, columns: columnCount)
            } else { selectedIndex = min(max(0, selectedIndex + offset), containerItems.count - 1) }
            return
        }
        if !isSearching && openFolder == nil {
            let before = browsingLayout.pages.prefix(pageIndex).reduce(0) { $0 + $1.count }
            var target = min(max(before + selectedIndex + offset, 0), containerItems.count - 1)
            for (index, page) in browsingLayout.pages.enumerated() {
                if target < page.count { pageIndex = index; selectedIndex = target; return }
                target -= page.count
            }
        } else {
            let target = min(max(pageIndex * LauncherLayout.pageSize + selectedIndex + offset, 0), containerItems.count - 1)
            pageIndex = target / LauncherLayout.pageSize
            selectedIndex = target % LauncherLayout.pageSize
        }
    }
    func requestPage(_ page: Int) {
        let target = min(max(0, page), pageCount - 1)
        if let onPageRequested { onPageRequested(target) }
        else { goToPage(target) }
    }
    func changePage(by delta: Int) {
        if isContinuousScrolling { moveSelection(by: delta * LauncherLayout.pageSize) }
        else { requestPage(pageIndex + delta) }
    }
    func goToPage(_ page: Int) {
        pageIndex = min(max(page, 0), pageCount - 1)
        selectedIndex = 0
    }
    func open(_ folder: LayoutItem) {
        guard folder.kind == .folder else { return }
        openFolderID = folder.id
        query = ""
        focusGeneration += 1
    }
    func closeFolder() {
        renamingFolderID = nil
        openFolderID = nil
        query = ""
        focusGeneration += 1
    }
    var activeArrangement: LauncherArrangement { isFullscreen ? preferences.arrangement : preferences.compactArrangement ?? .grid }
    var usesFreePlacement: Bool { activeArrangement == .free && !preferences.automaticCategories && !isSearching }
    func chooseArrangement(_ arrangement: LauncherArrangement) {
        updatePreferences {
            if isFullscreen { $0.arrangement = arrangement } else { $0.compactArrangement = arrangement }
            $0.automaticCategories = false
        }
        editing = true
    }
    func freePositionKey(_ id: String) -> String {
        (openFolderID ?? "root") + ":" + preferences.pagingDirection.rawValue + ":" + id
    }
    func setFreePosition(_ id: String, x: Double, y: Double) {
        guard !importInProgress, x.isFinite, y.isFinite else { return }
        var updated = layout
        if updated.freePositions == nil { updated.freePositions = [:] }
        updated.freePositions?[freePositionKey(id)] = FreeIconPosition(x: min(1, max(0, x)), y: min(1, max(0, y)))
        _ = commit(updated)
    }
    func shuffleLayout() {
        do { _ = try store.archiveCurrent() }
        catch { message = "无法备份布局，未打乱排列。"; return }
        var updated = layout
        if let folderID = openFolderID, layout.folders.contains(where: { $0.id == folderID }) {
            for page in updated.pages.indices {
                if let index = updated.pages[page].firstIndex(where: { $0.id == folderID }) { updated.pages[page][index].children.shuffle() }
            }
        } else {
            let items = updated.allItems.shuffled()
            updated.pages = stride(from: 0, to: items.count, by: LauncherLayout.pageSize).map { Array(items[$0..<min($0 + LauncherLayout.pageSize, items.count)]) }
            if updated.pages.isEmpty { updated.pages = [[]] }
        }
        guard commit(updated) else { return }
        updatePreferences {
            if isFullscreen { $0.arrangement = .grid } else { $0.compactArrangement = .grid }
            $0.automaticCategories = false
        }
        pageIndex = 0; selectedIndex = 0
    }
    func toggleEditing() {
        guard !preferences.automaticCategories else { openSettings(); return }
        editing.toggle()
        if isSearching { query = "" }
        draggingID = nil
        clearDropTarget()
    }

    func beginRename(_ folder: LayoutItem) {
        open(folder)
        folderNameDraft = folder.title ?? ""
        renamingFolderID = folder.id
    }
    func finishRename(cancel: Bool = false) {
        guard let id = renamingFolderID else { return }
        if !cancel {
            let title = folderNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { message = "文件夹名称不能为空。"; return }
            var updated = layout
            for page in updated.pages.indices {
                if let index = updated.pages[page].firstIndex(where: { $0.id == id }) {
                    updated.pages[page][index].title = String(title.prefix(40))
                }
            }
            guard commit(updated) else { return }
        }
        renamingFolderID = nil
        focusGeneration += 1
    }

    func createFolder(containing appID: String) {
        var updated = layout
        guard let node = updated.remove("app:" + appID), let id = node.appID else { return }
        let folder = LayoutItem.folder(children: [id])
        updated.pages[min(pageIndex, updated.pages.count - 1)].append(folder)
        guard commitReconciled(updated) else { return }
        editing = true
        beginRename(folder)
    }
    func dissolve(_ folderID: String) {
        var updated = layout
        for page in updated.pages.indices {
            if let index = updated.pages[page].firstIndex(where: { $0.id == folderID }) {
                let children = updated.pages[page][index].children
                updated.pages[page].replaceSubrange(index...index, with: children.map { .app($0) })
                if commitReconciled(updated), openFolderID == folderID { closeFolder() }
                return
            }
        }
    }
    func moveApp(_ appID: String, toFolder folderID: String?) {
        var updated = layout
        guard let node = updated.remove("app:" + appID) else { return }
        if let folderID {
            var found = false
            for page in updated.pages.indices {
                if let index = updated.pages[page].firstIndex(where: { $0.id == folderID }) {
                    updated.pages[page][index].children.append(appID)
                    found = true
                }
            }
            guard found else { return }
        } else { updated.pages[updated.pages.count - 1].append(node) }
        _ = commitReconciled(updated)
    }

    func drop(_ sourceID: String, onto targetID: String, position: ItemDropPosition) {
        guard sourceID != targetID, canOrganize else { return }
        var updated = layout
        guard let source = updated.remove(sourceID) else { return }
        if let folderID = openFolderID {
            guard let appID = source.appID else { return }
            for page in updated.pages.indices {
                if let index = updated.pages[page].firstIndex(where: { $0.id == folderID }),
                   let target = updated.pages[page][index].children.firstIndex(where: { "app:" + $0 == targetID }) {
                    updated.pages[page][index].children.insert(appID, at: target + (position == .after ? 1 : 0))
                    _ = commitReconciled(updated)
                    endDrag()
                    return
                }
            }
            return
        }
        for page in updated.pages.indices {
            guard let index = updated.pages[page].firstIndex(where: { $0.id == targetID }) else { continue }
            let target = updated.pages[page][index]
            if position == .center && target.kind == .folder {
                updated.pages[page][index].children += source.kind == .app ? [source.appID!]
                    : source.children
            } else if position == .center && source.kind == .app && target.kind == .app {
                updated.pages[page][index] = .folder(children: [target.appID!, source.appID!])
            } else {
                updated.pages[page].insert(source, at: index + (position == .after ? 1 : 0))
            }
            _ = commitReconciled(updated)
            endDrag()
            return
        }
    }
    func drop(_ sourceID: String, toPage requestedPage: Int) {
        guard canOrganize, requestedPage >= 0, requestedPage <= layout.pages.count else { return }
        var updated = layout
        guard let source = updated.remove(sourceID) else { return }
        if requestedPage == updated.pages.count { updated.pages.append([]) }
        updated.pages[requestedPage].append(source)
        if commitReconciled(updated) { goToPage(min(requestedPage, pageCount - 1)) }
        endDrag()
    }
    private func setDropTarget(_ id: String?, hint: String?) {
        guard dropTargetID != id || currentDropHint != hint else { return }
        let previous = dropTargetID
        dropTargetID = id; currentDropHint = hint
        if let previous, previous != id { tileFeedback[previous]?.setMergeTarget(false) }
        if let id { dragFeedback(for: id).setMergeTarget(hint?.contains("文件夹") == true) }
    }
    func updateDropTarget(_ id: String, hint: String) { setDropTarget(id, hint: hint) }
    func clearDropTarget(_ expectedID: String? = nil) {
        guard expectedID == nil || dropTargetID == expectedID else { return }
        setDropTarget(nil, hint: nil)
    }
    func endDrag() { clearDropTarget(); draggingID = nil }

    func openSettings() {
        finishRename()
        guard renamingFolderID == nil else { return }
        editing = false
        endDrag()
        showingSettings = true
    }
    func closeSettings() {
        if recordingShortcut { cancelRecording() }
        showingSettings = false
        focusGeneration += 1
    }
    func beginRecording() { recordingShortcut = true; onRecordingChanged?(true) }
    func cancelRecording() { recordingShortcut = false; onRecordingChanged?(false) }
    func acceptShortcut(_ shortcut: ShortcutBinding) {
        recordingShortcut = false
        _ = onShortcutRequested?(shortcut)
    }
    func saveShortcut(_ shortcut: ShortcutBinding) -> Bool {
        var updated = layout
        updated.shortcut = shortcut
        return commit(updated)
    }
    func resetShortcut() { _ = onShortcutRequested?(.standard) }

    func backupData() throws -> Data {
        var backup = layout
        backup.backupPresentation = BackupPresentation(fullscreen: preferences.arrangement, compact: preferences.compactArrangement ?? .grid)
        return try LayoutStore.encode(backup)
    }
    func ensureInventoryForImport() async throws {
        // Import matching must not use the panel-open throttle's stale inventory.
        requestRefresh(resetSearch: false)
        while completedRefreshGeneration < refreshGeneration {
            try await Task.sleep(for: .milliseconds(20))
        }
        try Task.checkCancellation()
        guard hasTrustedInventory else { throw LayoutError.inventoryUnavailable }
    }
    func beginFreeDrag(_ id: String) {
        guard usesFreePlacement, !showingSettings, !importInProgress else { return }
        draggingID = id
    }
    func restore(_ candidate: LauncherLayout) throws {
        guard hasTrustedInventory else { throw LayoutError.inventoryUnavailable }
        _ = try candidate.validated()
        _ = try store.archiveCurrent()
        var updated = candidate
        updated.prepareDisplayMode(fullscreen: isFullscreen)
        updated.shortcut = layout.shortcut
        updated.backupPresentation = nil
        updated.reconcile(with: apps.map(\.id))
        try store.save(updated)
        layout = updated
        updatePreferences {
            $0.automaticCategories = false
            if let presentation = candidate.backupPresentation {
                $0.arrangement = presentation.fullscreen
                $0.compactArrangement = presentation.compact
            }
        }
        openFolderID = nil
        query = ""
    }
    @discardableResult
    private func commitReconciled(_ candidate: LauncherLayout) -> Bool {
        var candidate = candidate
        candidate.reconcile(with: apps.map(\.id))
        let succeeded = commit(candidate)
        if openFolderID != nil && openFolder == nil { openFolderID = nil }
        pageIndex = min(pageIndex, pageCount - 1)
        selectedIndex = min(selectedIndex, max(0, visibleItems.count - 1))
        return succeeded
    }
    @discardableResult
    private func commit(_ candidate: LauncherLayout) -> Bool {
        guard canWriteLayout else { message = "原布局文件尚未安全备份，已停止覆盖写入。"; return false }
        do { try store.save(candidate); layout = candidate; pruneTileFeedback(); return true }
        catch { message = "无法保存布局：\(error.localizedDescription)"; return false }
    }
}
