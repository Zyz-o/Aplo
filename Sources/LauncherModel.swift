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
    @Published var displayWidth: CGFloat = 960 {
        didSet { if oldValue != displayWidth { pageIndex = min(pageIndex, pageCount - 1); selectedIndex = min(selectedIndex, max(0, visibleItems.count - 1)) } }
    }
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
    var requestedColumns: Int { isFullscreen ? preferences.fullscreenGridColumns : preferences.compactGridColumns }
    var requestedRows: Int { isFullscreen ? preferences.fullscreenGridRows : preferences.compactGridRows }
    var customGridEnabled: Bool { requestedColumns != 0 || requestedRows != 0 }
    var columnCount: Int { requestedColumns == 0 ? LauncherGeometry.columnCount(displayWidth: displayWidth, fullscreen: isFullscreen) : min(12, max(2, requestedColumns)) }
    var tileWidth: CGFloat { max(1, (gridWidth - CGFloat(columnCount - 1) * LauncherGeometry.gridSpacing) / CGFloat(columnCount)) }
    var displayedIconSize: CGFloat { min(preferences.iconPoints(fullscreen: isFullscreen), max(24, tileWidth - 18)) }
    var displayPageCapacity: Int { customGridEnabled ? columnCount * max(1, requestedRows == 0 ? 3 : requestedRows) : LauncherLayout.pageSize }
    func fittedRows(height: CGFloat, tileHeight: CGFloat) -> Int {
        let fitting = max(1, Int((height + 2) / (tileHeight + LauncherGeometry.gridSpacing)))
        return min(fitting, requestedRows == 0 ? (isFullscreen ? 100 : 3) : requestedRows)
    }
    var rootDisplayPages: [[LayoutItem]] {
        let source = browsingLayout
        guard customGridEnabled else { return source.pages }
        let items = source.allItems, capacity = displayPageCapacity
        if let cachedDisplayPages, cachedDisplayPages.capacity == capacity { return cachedDisplayPages.pages }
        let pages = items.isEmpty ? [[]] : stride(from: 0, to: items.count, by: capacity).map { Array(items[$0..<min(items.count, $0 + capacity)]) }
        cachedDisplayPages = (capacity, pages); return pages
    }
    var gridWidth: CGFloat { LauncherGeometry.gridWidth(displayWidth: displayWidth, fullscreen: isFullscreen) }
    var onResetWindowPosition: (() -> Void)?
    var onDisplayModeRequested: (() -> Void)?
    var onMinimize: (() -> Void)?
    @Published var query = "" { didSet { if !isSearching { searchCategory = nil }; cachedContainerItems = nil; filter() } }
    @Published private(set) var initialDiscoveryPending = true
    @Published private(set) var apps: [InstalledApp] = []
    @Published private(set) var searchCategory: AppCategory?
    private var searchCategoryCounts: [AppCategory: Int] = [:]
    private var categoriesByID: [String: AppCategory] = [:]
    var availableSearchCategories: [AppCategory] { AppCategory.allCases.filter { searchCategoryCounts[$0, default: 0] > 0 } }
    func count(for category: AppCategory) -> Int { searchCategoryCounts[category, default: 0] }
    func selectSearchCategory(_ category: AppCategory?) { searchCategory = category; filter() }
    @Published private(set) var results: [InstalledApp] = [] { didSet { cachedContainerItems = nil } }
    @Published var keyboardSelectionActive = false
    @Published private(set) var keyboardNavigationGeneration = 0
    private var freeFrames: [String: CGRect] = [:]
    @Published private(set) var canUndoOrganization = false
    @Published private(set) var canRedoOrganization = false
    private var organizationEditDepth = 0
    private var replayingOrganization = false
    private var undoStates: [OrganizationState] = []
    private var redoStates: [OrganizationState] = []
    var onNavigate: (() -> Void)?
    var onPageRequested: ((Int) -> Void)?
    @Published private(set) var selectedIndex = 0 { didSet { if oldValue != selectedIndex { onNavigate?() } } }
    @Published private(set) var layout: LauncherLayout { didSet { cachedContainerItems = nil; cachedBrowsingLayout = nil } }
    @Published private(set) var pageIndex = 0 { didSet { if oldValue != pageIndex { onNavigate?() } } }
    @Published private(set) var openFolderID: String? { didSet { cachedContainerItems = nil; selectedItemIDs = []; pageMotion.axis = navigationDirection == .vertical ? .vertical : .horizontal } }
    var hoveredAppID: String?
    @Published var inspectingApp: InstalledApp?
    var onSystemCommand: ((SystemCommand) -> Void)?
    var onTrashApplication: ((InstalledApp) -> Void)?
    var inlineResult: InlineResult? { InlineResult.parse(query) }
    func performInlineResult(_ result: InlineResult) {
        switch result {
        case .calculation(let value):
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string)
            message = .notice("计算结果已拷贝。")
        case .command(let command): onSystemCommand?(command)
        }
    }
    func inspectSelection() {
        guard draggingID == nil, !editing else { return }
        inspectingApp = (!keyboardSelectionActive ? hoveredAppID.flatMap { app(for: $0) } : nil) ?? selectedApp
    }
    @Published var message: LocalizedMessage? { didSet { scheduleMessageDismissal() } }
    private var messageDismissal: Task<Void, Never>?
    var noticeDuration: Duration = .seconds(4)
    private func scheduleMessageDismissal() {
        messageDismissal?.cancel(); messageDismissal = nil
        guard let message, message.presentation == .notice else { return }
        let delay = noticeDuration
        messageDismissal = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard let self, self.message == message, !self.importInProgress else { return }
            self.message = nil
        }
    }
    var lastSettingsCategory: String {
        get { preferencesStore.defaults.string(forKey: "aplo.lastSettingsCategory.v1") ?? "general" }
        set { preferencesStore.defaults.set(newValue, forKey: "aplo.lastSettingsCategory.v1") }
    }
    @Published var focusGeneration = 0
    @Published var shortcutAvailable = true
    @Published var f4ShortcutAvailable = true
    @Published var editing = false { didSet { if !editing { multiSelectionActive = false; selectedItemIDs = [] } } }
    @Published var multiSelectionActive = false
    @Published private(set) var selectedItemIDs: Set<String> = []
    @Published var showingPageOrganizer = false
    var onSettingsVisibilityChanged: (() -> Void)?
    var onPreferencesChanged: ((PreferenceChanges) -> Void)?
    @Published private(set) var preferences: LauncherPreferences { didSet {
        cachedContainerItems = nil
        if oldValue.hiddenAppIDs != preferences.hiddenAppIDs || oldValue.automaticCategories != preferences.automaticCategories { cachedBrowsingLayout = nil }
    } }
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
    private let icons: NSCache<NSString, CachedApplicationIcon> = {
        let cache = NSCache<NSString, CachedApplicationIcon>()
        cache.countLimit = 160; cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()
    private let iconQueue: OperationQueue = {
        let queue = OperationQueue(); queue.name = "Aplo.IconPrefetch"
        queue.maxConcurrentOperationCount = 1; queue.qualityOfService = .utility
        return queue
    }()
    private var iconJobs: [String: BlockOperation] = [:]
    private var iconTokens: [String: UUID] = [:]
    private var iconWaiters: [String: [ObjectIdentifier: WeakTileFeedback]] = [:]
    private static let pendingIcon = NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil)!
    // Native scrolling owns the frame budget; no published changes per event.
    private var scrollBusyUntil: TimeInterval = 0
    func noteScrollInteraction() { scrollBusyUntil = ProcessInfo.processInfo.systemUptime + 0.15 }
    private var scrollInteractionActive: Bool { ProcessInfo.processInfo.systemUptime < scrollBusyUntil }
    private var catalogRefresh: Task<Void, Never>?
    private var refreshGeneration: UInt64 = 0
    private var lastCompletedScan: TimeInterval?
    private var refreshInFlight = false
    private var hasTrustedInventory = false
    private var archivedUntrustedLayout = false
    private var completedRefreshGeneration: UInt64 = 0
    @Published var importInProgress = false
    var onCancelImport: (() -> Void)?
    var onRestoreHistory: ((URL) -> Void)?
    private var iconVersions: [String: [Date]] = [:]
    private var lookup: [String: InstalledApp] = [:]
    private var startupMessage: String?
    private var canWriteLayout = true
    private var categorizedLayout = LauncherLayout() { didSet { cachedContainerItems = nil; cachedBrowsingLayout = nil } }
    private var cachedBrowsingLayout: LauncherLayout? { didSet { cachedDisplayPages = nil } }
    private var cachedDisplayPages: (capacity: Int, pages: [[LayoutItem]])?
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
        pageMotion.axis = navigationDirection == .vertical ? .vertical : .horizontal
    }

    private func switchLayoutMode(from previousMode: Bool) {
        var updated = layout
        updated.prepareDisplayMode(fullscreen: isFullscreen)
        if !commit(updated, recordUndo: false) {
            switchingDisplayMode = true
            isFullscreen = previousMode
            switchingDisplayMode = false
            return
        }
        editing = false; endDrag(); openFolderID = nil; renamingFolderID = nil
        query = ""; pageIndex = 0; selectedIndex = 0; focusGeneration += 1
        pageMotion.active = false; pageMotion.offset = 0
    }

    var visibleApplicationCount: Int { apps.filter { !preferences.hiddenAppIDs.contains($0.id) }.count }
    var isSearching: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var browsingLayout: LauncherLayout {
        if let cachedBrowsingLayout { return cachedBrowsingLayout }
        var visible = preferences.automaticCategories ? categorizedLayout : layout
        let hidden = preferences.hiddenAppIDs
        guard !hidden.isEmpty else { cachedBrowsingLayout = visible; return visible }
        visible.pages = visible.pages.map { page in page.compactMap { item in
            if item.kind == .app { return item.appID.map { hidden.contains($0) } == true ? nil : item }
            var folder = item; folder.children.removeAll { hidden.contains($0) }
            return folder.children.isEmpty ? nil : folder
        } }.filter { !$0.isEmpty }
        if visible.pages.isEmpty { visible.pages = [[]] }
        cachedBrowsingLayout = visible
        return visible
    }
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
        if !isSearching && openFolder == nil { return max(1, rootDisplayPages.count) }
        return max(1, (containerItems.count + displayPageCapacity - 1) / displayPageCapacity)
    }
    var navigationDirection: LauncherPagingDirection { openFolderID != nil && preferences.folderNavigation == "continuous" ? .vertical : preferences.pagingDirection }
    var isContinuousScrolling: Bool {
        if openFolderID != nil && preferences.folderNavigation != "inherit" { return preferences.folderNavigation == "continuous" }
        return preferences.navigationStyle == .continuous || usesFreePlacement
    }
    var visibleItems: [LayoutItem] { isContinuousScrolling ? containerItems : items(onPage: pageIndex) }
    func items(onPage page: Int) -> [LayoutItem] {
        guard page >= 0 else { return [] }
        if !isSearching && openFolder == nil {
            return rootDisplayPages.indices.contains(page) ? rootDisplayPages[page] : []
        }
        let items = containerItems
        let start = page * displayPageCapacity
        guard start < items.count else { return [] }
        return Array(items[start..<min(start + displayPageCapacity, items.count)])
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
    var canOrganize: Bool { !importInProgress && !preferences.automaticCategories && editing && !isSearching && !showingSettings }
    var shortcutDisplayName: String { layout.shortcut.localizedDisplayName(language: preferences.language) }
    var shortcutLabel: String { shortcutAvailable ? shortcutDisplayName : text("菜单栏打开") }
    var dropDescription: String { if usesFreePlacement { return "拖动图标自由放置 · 整理菜单可返回网格" }; return dropHint ?? (openFolder == nil ? "拖到图标中心分组，边缘排序" : "拖放排序 · 右键可移出文件夹") }

    func updatePreferences(_ change: (inout LauncherPreferences) -> Void) {
        var updated = preferences
        change(&updated)
        if updated.pinToDesktop && !preferences.pinToDesktop { updated.dismissStyle = .escapeOnly }
        guard updated != preferences else { return }
        let organizationChanged = updated.hiddenAppIDs != preferences.hiddenAppIDs || updated.arrangement != preferences.arrangement || updated.compactArrangement != preferences.compactArrangement || updated.automaticCategories != preferences.automaticCategories
        let previousOrganization = organizationChanged ? organizationState : nil
        let hiddenChanged = updated.hiddenAppIDs != preferences.hiddenAppIDs
        let orderingChanged = updated.systemAppsLast != preferences.systemAppsLast
        let navigationChanged = PreferenceChanges(from: preferences, to: updated).contains(.navigation)
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
        if hiddenChanged {
            if openFolderID != nil && openFolder == nil { openFolderID = nil }
            filter()
        }
        if categoryChanged { openFolderID = nil; renamingFolderID = nil; folderNameDraft = ""; editing = false; query = ""; focusGeneration += 1 }
        if let previousOrganization { recordOrganizationEdit(previousOrganization) }
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
        let pixelSize = IconRaster.pixelSize(points: preferences.iconPoints(fullscreen: isFullscreen),
                                             scale: max(2, NSScreen.main?.backingScaleFactor ?? 2))
        let cached = icons.object(forKey: path as NSString)
        if let cached, cached.pixels >= pixelSize { return cached.image }
        let placeholder = cached?.image ?? Self.pendingIcon
        if let feedback { iconWaiters[path, default: [:]][ObjectIdentifier(feedback)] = WeakTileFeedback(feedback) }
        if let job = iconJobs[path] {
            if !prewarm { job.queuePriority = .veryHigh }
            return placeholder
        }
        let token = UUID(); iconTokens[path] = token
        let job = BlockOperation { [weak self] in
            let delivery = autoreleasepool {
                let image = IconRaster.load(path: path, pixels: pixelSize)
                return IconDelivery(image: image)
            }
            Task { @MainActor [weak self] in
                guard let self, self.iconTokens[path] == token else { return }
                self.icons.setObject(CachedApplicationIcon(image: delivery.image, pixels: pixelSize), forKey: path as NSString, cost: pixelSize * pixelSize * 4)
                self.iconJobs.removeValue(forKey: path); self.iconTokens.removeValue(forKey: path)
                let waiters = self.iconWaiters.removeValue(forKey: path)?.values ?? Dictionary<ObjectIdentifier, WeakTileFeedback>().values
                for waiter in waiters { waiter.value?.objectWillChange.send() }
            }
        }
        job.queuePriority = prewarm ? .low : .veryHigh
        iconJobs[path] = job; iconQueue.addOperation(job)
        return placeholder
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
        let previousApps = apps
        let previousEntries = searchIndex.entries
        let scan = Task.detached(priority: .userInitiated) {
            let snapshot = catalog.snapshot(preferredLanguages: namingLanguages)
            let inventory = snapshot.inventory(retaining: previousApps)
            let prepared = inventory == previousApps ? nil : IntegratedSearch.prepare(inventory, reusing: previousEntries)
            return (snapshot, prepared)
        }
        catalogRefresh = Task { @MainActor [weak self] in
            let (snapshot, preparedIndex) = await withTaskCancellationHandler(operation: { await scan.value }, onCancel: { scan.cancel() })
            guard !Task.isCancelled, let self, self.refreshGeneration == generation else { return }
            // A completed scan must not replace drag sources or rebuild an animating page.
            while self.draggingID != nil || self.pageTransitionActive || self.scrollInteractionActive {
                try? await Task.sleep(for: .milliseconds(16))
                guard !Task.isCancelled, self.refreshGeneration == generation else { return }
            }
            self.applySnapshot(snapshot, resetSearch: false, preparedIndex: preparedIndex)
            self.completedRefreshGeneration = generation
            self.refreshInFlight = false
            self.lastCompletedScan = ProcessInfo.processInfo.systemUptime
        }
        return true
    }
    func waitForCatalogRefresh() async { await catalogRefresh?.value }
    private func resetBrowsingState() {
        keyboardSelectionActive = false
        searchExpanded = false; openFolderID = nil; renamingFolderID = nil
        editing = false; showingSettings = false; query = ""
        focusGeneration += 1
    }
    private func applySnapshot(_ snapshot: CatalogSnapshot, resetSearch: Bool, preparedIndex: PreparedSearchIndex? = nil) {
        if initialDiscoveryPending { initialDiscoveryPending = false }
        if snapshot.isComplete { archivedUntrustedLayout = false }
        hasTrustedInventory = snapshot.isComplete
        let inventory = snapshot.inventory(retaining: apps)
        if !snapshot.isComplete {
            let warning: LocalizedMessage = "部分应用暂时无法读取，已保留原布局；请稍后刷新重试。"
            if message != warning { message = warning }
        }
        let inventoryChanged = apps != inventory
        let imagesChanged = iconVersions != snapshot.iconVersions
        if inventoryChanged {
            clearOrganizationHistory()
            apps = inventory
            categorizedLayout = AppClassifier.layout(for: apps)
            categoriesByID = Dictionary(uniqueKeysWithValues: apps.map { ($0.id, AppClassifier.category(for: $0)) })
            if let preparedIndex { searchIndex.install(preparedIndex) }
            else { searchIndex.update(apps) }
            lookup = Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) })
            cachedContainerItems = nil
        }
        if imagesChanged {
            iconQueue.cancelAllOperations(); iconJobs.removeAll(); iconTokens.removeAll()
            iconWaiters = iconWaiters.filter { snapshot.iconVersions[$0.key] != nil }
            for path in iconVersions.keys where snapshot.iconVersions[path] != iconVersions[path] { icons.removeObject(forKey: path as NSString) }
            iconVersions = snapshot.iconVersions
            for feedback in tileFeedback.values { feedback.objectWillChange.send() }
            // Same-path application updates still invalidate visible native icon identities.
            if !inventoryChanged { objectWillChange.send() }

        }
        var updated = layout
        updated.reconcile(with: apps.map(\.id), preservingMissing: !hasTrustedInventory)
        if updated != layout || !FileManager.default.fileExists(atPath: store.url.path) {
            _ = commit(updated, recordUndo: false)
        }
        if openFolderID != nil && openFolder == nil { openFolderID = nil }
        if resetSearch { resetBrowsingState() }
        else if inventoryChanged { filter() }
        if let startupMessage { message = LocalizedMessage(startupMessage); self.startupMessage = nil }
        pruneTileFeedback()
    }

    private func pruneTileFeedback() {
        let other = layout.otherDisplayLayout?.pages.flatMap { $0 }.map(\.id) ?? []
        let valid = Set(layout.allItems.map(\.id) + other + categorizedLayout.allItems.map(\.id) + apps.map { "app:" + $0.id })
        tileFeedback = tileFeedback.filter { valid.contains($0.key) || $0.key == draggingID }
        iconWaiters = iconWaiters.mapValues { $0.filter { $0.value.value != nil } }
    }

    private func filter() {
        let matches = searchIndex.matching(apps.filter { !preferences.hiddenAppIDs.contains($0.id) }, query: query)
        searchCategoryCounts = [:]
        for app in matches { searchCategoryCounts[categoriesByID[app.id] ?? .other, default: 0] += 1 }
        results = searchCategory.map { category in matches.filter { categoriesByID[$0.id] == category } } ?? matches
        pageIndex = 0
        selectedIndex = 0
        draggingID = nil
        clearDropTarget()
    }

    func select(_ index: Int) {
        keyboardSelectionActive = false
        if visibleItems.indices.contains(index) { selectedIndex = index }
    }
    func moveSelection(by offset: Int) {
        guard !containerItems.isEmpty else { return }
        keyboardSelectionActive = true
        defer { keyboardNavigationGeneration &+= 1 }
        if usesFreePlacement, abs(offset) == 1 || abs(offset) == columnCount {
            let frames = containerItems.map { freeFrames[$0.id] ?? .zero }
            let direction = abs(offset) == 1 ? CGPoint(x: offset > 0 ? 1 : -1, y: 0) : CGPoint(x: 0, y: offset > 0 ? 1 : -1)
            selectedIndex = SpatialNavigation.neighbor(from: selectedIndex, frames: frames, direction: direction)
            return
        }
        if isContinuousScrolling {
            if navigationDirection == .horizontal && (abs(offset) == 1 || abs(offset) == columnCount) {
                selectedIndex = LauncherGeometry.horizontalNeighbor(index: selectedIndex, offset: offset, itemCount: containerItems.count, rows: horizontalRowCount, columns: columnCount)
            } else { selectedIndex = min(max(0, selectedIndex + offset), containerItems.count - 1) }
            return
        }
        if !isSearching && openFolder == nil {
            let before = rootDisplayPages.prefix(pageIndex).reduce(0) { $0 + $1.count }
            var target = min(max(before + selectedIndex + offset, 0), containerItems.count - 1)
            for (index, page) in rootDisplayPages.enumerated() {
                if target < page.count { pageIndex = index; selectedIndex = target; return }
                target -= page.count
            }
        } else {
            let target = min(max(pageIndex * displayPageCapacity + selectedIndex + offset, 0), containerItems.count - 1)
            pageIndex = target / displayPageCapacity
            selectedIndex = target % displayPageCapacity
        }
    }
    func requestPage(_ page: Int) {
        let target = min(max(0, page), pageCount - 1)
        if let onPageRequested { onPageRequested(target) }
        else { goToPage(target) }
    }
    func changePage(by delta: Int) {
        if isContinuousScrolling { moveSelection(by: delta * displayPageCapacity) }
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
    var usesFreePlacement: Bool { openFolderID == nil && activeArrangement == .free && !preferences.automaticCategories && !isSearching }
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
        withOrganizationEdit {
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
        guard let page = updated.pages.firstIndex(where: { $0.contains { $0.appID == appID && $0.kind == .app } }),
              let index = updated.pages[page].firstIndex(where: { $0.appID == appID && $0.kind == .app }) else { return }
        let folder = LayoutItem.folder(children: [appID])
        updated.pages[page][index] = folder
        // Move both directional coordinates with the replacement, leaving all other icons alone.
        if let positions = updated.freePositions {
            for (key, value) in positions where key.hasPrefix("root:") && key.hasSuffix(":app:" + appID) {
                updated.freePositions?[String(key.dropLast(("app:" + appID).count)) + folder.id] = value
                updated.freePositions?.removeValue(forKey: key)
            }
        }
        guard commit(updated) else { return }
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
        if multiSelectionActive && selectedItemIDs.contains(sourceID) && selectedItemIDs.count > 1 {
            dropSelection(onto: targetID, position: position); return
        }
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
                if source.kind == .app {
                    guard let appID = source.appID else { endDrag(); return }
                    updated.pages[page][index].children.append(appID)
                } else { updated.pages[page][index].children += source.children }
            } else if position == .center && source.kind == .app && target.kind == .app {
                guard let targetID = target.appID, let sourceID = source.appID else { endDrag(); return }
                updated.pages[page][index] = .folder(children: [targetID, sourceID])
            } else {
                updated.pages[page].insert(source, at: index + (position == .after ? 1 : 0))
            }
            _ = commitReconciled(updated)
            endDrag()
            return
        }
    }
    func drop(_ sourceID: String, toPage requestedPage: Int) {
        guard canOrganize, requestedPage >= 0 else { return }
        if multiSelectionActive && selectedItemIDs.contains(sourceID) && selectedItemIDs.count > 1 {
            moveSelection(toPage: requestedPage); return
        }
        if customGridEnabled {
            guard rootDisplayPages.indices.contains(requestedPage),
                  let anchor = rootDisplayPages[requestedPage].last(where: { $0.id != sourceID }) else { endDrag(); return }
            var updated = layout
            guard let source = updated.remove(sourceID) else { endDrag(); return }
            for page in updated.pages.indices {
                if let index = updated.pages[page].firstIndex(where: { $0.id == anchor.id }) {
                    updated.pages[page].insert(source, at: index + 1)
                    if commitReconciled(updated) { goToPage(requestedPage) }
                    endDrag(); return
                }
            }
            endDrag(); return
        }
        guard requestedPage <= layout.pages.count else { return }
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
        return commit(updated, recordUndo: false)
    }
    func resetShortcut() { _ = onShortcutRequested?(.standard) }

    func backupData() throws -> Data {
        var backup = layout
        backup.backupPresentation = BackupPresentation(hiddenAppIDs: preferences.hiddenAppIDs, fullscreen: preferences.arrangement, compact: preferences.compactArrangement ?? .grid)
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
        try withOrganizationEdit {
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
                    if let hidden = presentation.hiddenAppIDs { $0.hiddenAppIDs = hidden }
                    $0.arrangement = presentation.fullscreen
                    $0.compactArrangement = presentation.compact
                }
            }
            openFolderID = nil
            query = ""
        }
    }
    @discardableResult
    private func commitReconciled(_ candidate: LauncherLayout) -> Bool {
        var candidate = candidate
        candidate.reconcile(with: apps.map(\.id), preservingMissing: !hasTrustedInventory)
        let succeeded = commit(candidate)
        if openFolderID != nil && openFolder == nil { openFolderID = nil }
        pageIndex = min(pageIndex, pageCount - 1)
        selectedIndex = min(selectedIndex, max(0, visibleItems.count - 1))
        return succeeded
    }
    @discardableResult
    private func commit(_ candidate: LauncherLayout, recordUndo: Bool = true) -> Bool {
        guard canWriteLayout else { message = "原布局文件尚未安全备份，已停止覆盖写入。"; return false }
        let previous = organizationState
        let removedIDs = candidate.removedAppIDs(from: layout)
        guard hasTrustedInventory || removedIDs.isEmpty else {
            message = "部分应用暂时无法读取，已暂停可能移除应用的布局操作。"; return false
        }
        do {
            // Guard every write path, including organization after a partial cold-start scan.
            if !removedIDs.isEmpty || (!hasTrustedInventory && !archivedUntrustedLayout) {
                _ = try store.archiveCurrent()
                if !hasTrustedInventory { archivedUntrustedLayout = true }
            }
            try store.save(candidate); layout = candidate; pruneTileFeedback()
            if recordUndo { recordOrganizationEdit(previous) }
            return true
        }
        catch { message = "无法保存布局：\(error.localizedDescription)"; return false }
    }
}


extension LauncherModel {
    func updateFreeFrames(_ frames: [String: CGRect]) { freeFrames = frames }
    private var organizationState: OrganizationState { OrganizationState(layout: layout, hiddenAppIDs: preferences.hiddenAppIDs, arrangement: preferences.arrangement, compactArrangement: preferences.compactArrangement, automaticCategories: preferences.automaticCategories) }
    private func withOrganizationEdit(_ action: () throws -> Void) rethrows {
        let before = organizationState
        organizationEditDepth += 1
        defer { organizationEditDepth -= 1; recordOrganizationEdit(before) }
        try action()
    }
    private func clearOrganizationHistory() {
        undoStates.removeAll(); redoStates.removeAll()
        canUndoOrganization = false; canRedoOrganization = false
    }
    private func recordOrganizationEdit(_ previous: OrganizationState) {
        guard !replayingOrganization, organizationEditDepth == 0, previous != organizationState else { return }
        undoStates.append(previous)
        if undoStates.count > 50 { undoStates.removeFirst() }
        redoStates.removeAll(); canUndoOrganization = true; canRedoOrganization = false
    }
    func setAppHidden(_ id: String, hidden: Bool) {
        guard !importInProgress else { return }
        updatePreferences { if hidden { $0.hiddenAppIDs.insert(id) } else { $0.hiddenAppIDs.remove(id) } }
    }
    func showAllApplications() {
        guard !importInProgress else { return }
        updatePreferences { $0.hiddenAppIDs.removeAll() }
    }
    func undoOrganization() { applyOrganizationHistory(redo: false) }
    func redoOrganization() { applyOrganizationHistory(redo: true) }
    private func applyOrganizationHistory(redo: Bool) {
        guard !importInProgress, draggingID == nil, var target = (redo ? redoStates.last : undoStates.last) else { return }
        let current = organizationState
        target.layout.prepareDisplayMode(fullscreen: isFullscreen)
        guard commit(target.layout, recordUndo: false) else { return }
        replayingOrganization = true
        updatePreferences {
            $0.hiddenAppIDs = target.hiddenAppIDs
            $0.arrangement = target.arrangement; $0.compactArrangement = target.compactArrangement
            $0.automaticCategories = target.automaticCategories
        }
        replayingOrganization = false
        if redo { redoStates.removeLast(); undoStates.append(current) }
        else { undoStates.removeLast(); redoStates.append(current) }
        canUndoOrganization = !undoStates.isEmpty; canRedoOrganization = !redoStates.isEmpty
        endDrag(); renamingFolderID = nil; openFolderID = nil; query = ""
    }
}


extension LauncherModel {
    var selectedAppIDs: [String] { containerItems.filter { selectedItemIDs.contains($0.id) }.compactMap(\.appID) }
    func toggleMultiSelection() {
        guard !isSearching, !showingSettings, !importInProgress else { return }
        if !multiSelectionActive {
            chooseArrangement(.grid); editing = true; multiSelectionActive = true
        } else { multiSelectionActive = false }
        selectedItemIDs = []
    }
    func toggleItemSelection(_ item: LayoutItem) {
        guard multiSelectionActive, item.kind == .app else { return }
        if !selectedItemIDs.insert(item.id).inserted { selectedItemIDs.remove(item.id) }
    }
    func dragItems(startingAt id: String) -> [LayoutItem] {
        if multiSelectionActive, selectedItemIDs.contains(id) { return containerItems.filter { selectedItemIDs.contains($0.id) } }
        return containerItems.filter { $0.id == id }
    }
    func createFolderFromSelection() {
        let ids = selectedAppIDs
        guard canOrganize, ids.count > 1 else { return }
        var updated = layout
        let selected = Set(ids.map { "app:" + $0 })
        // Replace the first selected root slot, before removing the remaining apps.
        guard let page = updated.pages.firstIndex(where: { $0.contains { selected.contains($0.id) } }),
              let slot = updated.pages[page].firstIndex(where: { selected.contains($0.id) }) else { return }
        let anchorID = updated.pages[page][slot].id
        for id in ids where "app:" + id != anchorID { _ = updated.remove("app:" + id) }
        guard let anchor = updated.pages[page].firstIndex(where: { $0.id == anchorID }) else { return }
        let folder = LayoutItem.folder(children: ids)
        updated.pages[page][anchor] = folder
        if commitReconciled(updated) { selectedItemIDs = []; beginRename(folder) }
    }
    func moveSelection(toFolder folderID: String?) {
        let ids = selectedAppIDs
        guard canOrganize, !ids.isEmpty else { return }
        var updated = layout
        if let folderID {
            guard folderID != openFolderID, updated.folders.contains(where: { $0.id == folderID }) else { return }
            for id in ids { _ = updated.remove("app:" + id) }
            for page in updated.pages.indices {
                if let slot = updated.pages[page].firstIndex(where: { $0.id == folderID }) { updated.pages[page][slot].children += ids }
            }
        } else {
            for id in ids { _ = updated.remove("app:" + id) }
            updated.pages[updated.pages.count - 1] += ids.map { .app($0) }
        }
        if commitReconciled(updated) { selectedItemIDs = [] }; endDrag()
    }
    func dropSelection(onto targetID: String, position: ItemDropPosition) {
        let ids = selectedAppIDs
        guard canOrganize, !ids.isEmpty, !selectedItemIDs.contains(targetID) else { endDrag(); return }
        var updated = layout
        for id in ids { _ = updated.remove("app:" + id) }
        if let folderID = openFolderID {
            for page in updated.pages.indices {
                if let slot = updated.pages[page].firstIndex(where: { $0.id == folderID }),
                   let target = updated.pages[page][slot].children.firstIndex(where: { "app:" + $0 == targetID }) {
                    updated.pages[page][slot].children.insert(contentsOf: ids, at: target + (position == .after ? 1 : 0))
                    if commitReconciled(updated) { selectedItemIDs = [] }; endDrag(); return
                }
            }
        } else {
            for page in updated.pages.indices {
                guard let slot = updated.pages[page].firstIndex(where: { $0.id == targetID }) else { continue }
                let target = updated.pages[page][slot]
                if position == .center {
                    if target.kind == .folder { updated.pages[page][slot].children += ids }
                    else if let id = target.appID { updated.pages[page][slot] = .folder(children: [id] + ids) }
                } else { updated.pages[page].insert(contentsOf: ids.map { .app($0) }, at: slot + (position == .after ? 1 : 0)) }
                if commitReconciled(updated) { selectedItemIDs = [] }; endDrag(); return
            }
        }
        endDrag()
    }
    func moveSelection(toPage page: Int) {
        let ids = selectedAppIDs
        guard canOrganize, !ids.isEmpty, page >= 0 else { return }
        var updated = layout
        if customGridEnabled {
            guard rootDisplayPages.indices.contains(page), let anchor = rootDisplayPages[page].last(where: { !selectedItemIDs.contains($0.id) }) else { endDrag(); return }
            for id in ids { _ = updated.remove("app:" + id) }
            for p in updated.pages.indices {
                if let slot = updated.pages[p].firstIndex(where: { $0.id == anchor.id }) { updated.pages[p].insert(contentsOf: ids.map { .app($0) }, at: slot + 1); break }
            }
        } else {
            guard page <= updated.pages.count else { return }
            for id in ids { _ = updated.remove("app:" + id) }
            if page == updated.pages.count { updated.pages.append([]) }
            let slot = min(updated.pages[page].count, max(0, LauncherLayout.pageSize - ids.count))
            updated.pages[page].insert(contentsOf: ids.map { .app($0) }, at: slot)
        }
        if commitReconciled(updated) { selectedItemIDs = []; goToPage(min(page, pageCount - 1)) }; endDrag()
    }
    func pageTitle(_ index: Int) -> String { LocalizedMessage("第 \(index + 1) 页").localized(language: preferences.language) }
    var canReorderPages: Bool { canOrganize && openFolderID == nil && !customGridEnabled }
    func movePage(identifiedBy ids: [String], to target: Int) {
        guard canReorderPages, !ids.isEmpty, layout.pages.indices.contains(target),
              let source = layout.pages.firstIndex(where: { $0.map(\.id) == ids }), source != target else { return }
        var updated = layout
        let page = updated.pages.remove(at: source); updated.pages.insert(page, at: target)
        if commit(updated) { pageIndex = target; selectedIndex = 0 }
    }
}
