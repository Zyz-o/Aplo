#if SWIFT_PACKAGE
import XCTest
@testable import Aplo

@MainActor final class OrganizationTests: XCTestCase {
    private func fixture(count: Int = 40) throws -> (LauncherModel, UserDefaults, () -> Void) {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let apps = root.appendingPathComponent("Apps")
        try fm.createDirectory(at: apps, withIntermediateDirectories: true)
        for i in 0..<count {
            let contents = apps.appendingPathComponent("App\(i).app/Contents")
            try fm.createDirectory(at: contents, withIntermediateDirectories: true)
            try PropertyListSerialization.data(fromPropertyList: ["CFBundlePackageType": "APPL", "CFBundleIdentifier": String(format: "test.%02d", i), "CFBundleName": String(format: "App %02d", i)], format: .binary, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        }
        let domain = "local.aplo.organization-tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        var p = LauncherPreferences(); p.automaticCategories = false; p.systemAppsLast = false
        PreferencesStore(defaults: defaults).save(p)
        let model = LauncherModel(catalog: AppCatalog(roots: [apps], excludedRoots: []), store: LayoutStore(url: root.appendingPathComponent("Data/layout.json")), defaults: defaults)
        model.refresh(resetSearch: false)
        return (model, defaults, {
            model.flushPreferences(); defaults.removePersistentDomain(forName: domain)
            try? fm.removeItem(at: root)
        })
    }
    func testFolderReplacesOriginalSlotWithoutRepagination() throws {
        let (model, _, cleanup) = try fixture(); defer { cleanup() }
        model.setFreePosition("app:test.39", x: 0.7, y: 0.4)
        let before = model.layout
        model.goToPage(0)
        model.createFolder(containing: "test.39")
        let folder = try XCTUnwrap(model.layout.folders.first)
        XCTAssertEqual(model.layout.pages.map(\.count), [18, 18, 4])
        XCTAssertEqual(model.layout.pages[2][3], folder)
        XCTAssertEqual(folder.children, ["test.39"])
        XCTAssertEqual(model.layout.otherDisplayLayout, before.otherDisplayLayout)
        XCTAssertEqual(model.layout.freePositions?["root:horizontal:" + folder.id], FreeIconPosition(x: 0.7, y: 0.4))
        XCTAssertNil(model.layout.freePositions?["root:horizontal:app:test.39"])
        model.finishRename(cancel: true); model.closeFolder()
        model.undoOrganization()
        XCTAssertEqual(model.layout, before)
        model.redoOrganization()
        XCTAssertEqual(model.layout.pages[2][3].id, folder.id)
        model.dissolve(folder.id)
        XCTAssertEqual(model.layout.pages[2][3], .app("test.39"))
        model.undoOrganization()
        XCTAssertEqual(model.layout.pages[2][3].id, folder.id)
    }
    func testFreeDirectionUsesCoordinatesRatherThanColumnOrder() throws {
        let (model, _, cleanup) = try fixture(count: 3); defer { cleanup() }
        model.chooseArrangement(.free)
        model.updateFreeFrames([
            "app:test.00": CGRect(x: 0, y: 0, width: 80, height: 100),
            "app:test.01": CGRect(x: 0, y: 150, width: 80, height: 100),
            "app:test.02": CGRect(x: 180, y: 0, width: 80, height: 100)])
        model.select(0)
        XCTAssertFalse(model.keyboardSelectionActive)
        let generation = model.keyboardNavigationGeneration
        model.moveSelection(by: 1)
        XCTAssertEqual(model.selectedItem?.appID, "test.02")
        XCTAssertTrue(model.keyboardSelectionActive)
        XCTAssertGreaterThan(model.keyboardNavigationGeneration, generation)
        model.moveSelection(by: -1)
        XCTAssertEqual(model.selectedItem?.appID, "test.00")
        model.moveSelection(by: model.columnCount)
        XCTAssertEqual(model.selectedItem?.appID, "test.01")
        model.moveSelection(by: -model.columnCount)
        XCTAssertEqual(model.selectedItem?.appID, "test.00")
        model.select(0)
        XCTAssertFalse(model.keyboardSelectionActive)
    }
    func testHiddenAppsKeepLayoutAndSearchExclusionAndUndo() throws {
        let (model, defaults, cleanup) = try fixture(); defer { cleanup() }
        model.createFolder(containing: "test.39"); model.finishRename(cancel: true)
        let original = model.layout
        model.setAppHidden("test.39", hidden: true)
        XCTAssertNil(model.openFolderID, "Hiding the final child must leave the now-invisible folder's coordinate space")
        XCTAssertEqual(model.layout, original)
        XCTAssertFalse(model.containerItems.contains { $0.children.contains("test.39") })
        model.query = "App 39"
        XCTAssertTrue(model.results.isEmpty)
        model.query = ""
        XCTAssertTrue(PreferencesStore(defaults: defaults).load().hiddenAppIDs.contains("test.39"))
        XCTAssertEqual(try LayoutStore.decode(model.backupData()).backupPresentation?.hiddenAppIDs, ["test.39"])
        model.undoOrganization()
        XCTAssertTrue(model.preferences.hiddenAppIDs.isEmpty)
        XCTAssertEqual(model.layout, original)
        model.redoOrganization()
        XCTAssertTrue(model.preferences.hiddenAppIDs.contains("test.39"))
        model.setAppHidden("test.39", hidden: false)
        XCTAssertEqual(model.layout, original)
        XCTAssertTrue(model.containerItems.contains { $0.children.contains("test.39") })
    }
    func testNewEditInvalidatesRedoAndModeSwitchDoesNotBecomeUndoStep() throws {
        let (model, _, cleanup) = try fixture(); defer { cleanup() }
        XCTAssertFalse(model.canUndoOrganization)
        model.createFolder(containing: "test.39"); model.finishRename(cancel: true); model.closeFolder()
        model.isFullscreen = true
        model.undoOrganization()
        var compact = model.layout; compact.prepareDisplayMode(fullscreen: false)
        XCTAssertTrue(compact.folders.isEmpty)
        model.setAppHidden("test.00", hidden: true)
        XCTAssertFalse(model.canRedoOrganization)
    }
    func testMergeRenameAndRestoreAreReversibleTransactions() throws {
        let (model, _, cleanup) = try fixture(count: 3); defer { cleanup() }
        let original = model.layout
        model.editing = true
        model.drop("app:test.00", onto: "app:test.01", position: .center)
        let folder = try XCTUnwrap(model.layout.folders.first)
        XCTAssertEqual(folder.children, ["test.01", "test.00"])
        model.undoOrganization(); XCTAssertEqual(model.layout, original)
        model.redoOrganization(); XCTAssertEqual(model.layout.folders.first?.id, folder.id)
        model.beginRename(folder); model.folderNameDraft = "Tools"; model.finishRename()
        XCTAssertEqual(model.layout.folders.first?.title, "Tools")
        model.undoOrganization(); XCTAssertEqual(model.layout.folders.first?.title, folder.title)
        let beforeRestore = model.layout
        let beforeArrangement = model.activeArrangement
        var backup = original
        backup.backupPresentation = BackupPresentation(hiddenAppIDs: ["test.02"], fullscreen: .free, compact: .free)
        try model.restore(backup)
        XCTAssertEqual(model.activeArrangement, .free)
        XCTAssertTrue(model.preferences.hiddenAppIDs.contains("test.02"))
        model.undoOrganization()
        XCTAssertEqual(model.layout, beforeRestore)
        XCTAssertEqual(model.activeArrangement, beforeArrangement)
        XCTAssertTrue(model.preferences.hiddenAppIDs.isEmpty)
        model.redoOrganization()
        XCTAssertEqual(model.activeArrangement, .free)
        XCTAssertTrue(model.preferences.hiddenAppIDs.contains("test.02"))
    }

    func testHistoryPreservesManualBackupsAndParsesCurrentChangelog() throws {
        let (model, _, cleanup) = try fixture(); defer { cleanup() }
        let fm = FileManager.default
        for _ in 0..<25 { _ = try model.store.archiveCurrent() }
        try model.store.saveManualBackup(model.backupData())
        let history = try model.store.history()
        XCTAssertEqual(history.count, 26)
        XCTAssertEqual(history.filter(\.automatic).count, 25)
        let cleanupCandidates = try model.store.automaticHistoryToClean()
        XCTAssertEqual(cleanupCandidates.count, 5)
        XCTAssertTrue(cleanupCandidates.allSatisfy(\.automatic))
        let manual = try XCTUnwrap(history.first { !$0.automatic })
        XCTAssertFalse(cleanupCandidates.contains(manual))
        XCTAssertEqual(try LayoutStore.read(manual.url).pages, model.layout.pages)
        let symlink = manual.url.deletingLastPathComponent().appendingPathComponent("external.json")
        try fm.createSymbolicLink(at: symlink, withDestinationURL: manual.url)
        XCTAssertEqual(try model.store.history().count, 26)
        let notes = ReleaseNote.parse("# 3.13.0 — 2026-11-02\n\n- Current fixes\n\n# 3.12.2 — 2026-11-01\n\n- Previous fixes\n")
        XCTAssertEqual(notes.first?.title, "3.13.0 — 2026-11-02")
        XCTAssertEqual(notes.count, 2)
        XCTAssertTrue(notes.first?.body.contains("Current fixes") == true)
    }
    func testCustomGridReflowsWithoutRewritingStoredLayouts() throws {
        let (model, _, cleanup) = try fixture(); defer { cleanup() }
        let original = model.layout
        model.updatePreferences { $0.compactGridColumns = 4; $0.compactGridRows = 2; $0.navigationStyle = .paged }
        XCTAssertEqual(model.rootDisplayPages.map(\.count), [8,8,8,8,8])
        XCTAssertEqual(model.layout, original)
        model.goToPage(4); model.updatePreferences { $0.compactGridColumns = 12 }
        XCTAssertLessThan(model.pageIndex, model.pageCount)
        model.updatePreferences { $0.compactGridColumns = 0; $0.compactGridRows = 0 }
        XCTAssertEqual(model.rootDisplayPages, original.pages)
        XCTAssertEqual(model.layout, original)
    }
    func testBatchFolderPreservesAnchorAndUndoBothLayouts() throws {
        let (model, _, cleanup) = try fixture(); defer { cleanup() }
        let original = model.layout
        model.toggleMultiSelection()
        model.toggleItemSelection(.app("test.37")); model.toggleItemSelection(.app("test.39"))
        model.createFolderFromSelection()
        let folder = try XCTUnwrap(model.layout.folders.first)
        XCTAssertEqual(model.layout.pages[2][1].id, folder.id)
        XCTAssertEqual(folder.children, ["test.37", "test.39"])
        XCTAssertEqual(model.layout.otherDisplayLayout, original.otherDisplayLayout)
        XCTAssertEqual(model.layout.appIDs.sorted(), original.appIDs.sorted())
        model.finishRename(cancel: true); model.closeFolder(); model.undoOrganization()
        XCTAssertEqual(model.layout, original)
        model.redoOrganization(); XCTAssertEqual(model.layout.pages[2][1].id, folder.id)
    }
    func testBatchDropAndPageMoveAreSingleUndoTransactions() throws {
        let (model, _, cleanup) = try fixture(); defer { cleanup() }
        model.toggleMultiSelection()
        model.toggleItemSelection(.app("test.36")); model.toggleItemSelection(.app("test.39"))
        let before = model.layout
        model.beginInteractiveDrag("app:test.39")
        XCTAssertEqual(model.dragItems(startingAt: "app:test.39").count, 2)
        model.drop("app:test.39", onto: "app:test.37", position: .center)
        XCTAssertEqual(model.layout.folders.first?.children, ["test.37", "test.36", "test.39"])
        model.undoOrganization(); XCTAssertEqual(model.layout, before)
        model.editing = true
        let ids = model.layout.pages[2].map(\.id)
        model.movePage(identifiedBy: ids, to: 0)
        XCTAssertEqual(model.layout.pages[0].map(\.id), ids)
        XCTAssertEqual(model.layout.otherDisplayLayout, before.otherDisplayLayout)
        model.undoOrganization(); XCTAssertEqual(model.layout, before)
        model.movePage(identifiedBy: ["invalid"], to: 0)
        XCTAssertEqual(model.layout, before)
    }
    func testFolderNavigationDoesNotChangeRootPreferencesOrLayout() throws {
        let (model, _, cleanup) = try fixture(); defer { cleanup() }
        model.createFolder(containing: "test.39"); model.finishRename(cancel: true)
        let original = model.layout
        model.updatePreferences { $0.navigationStyle = .paged; $0.pagingDirection = .horizontal; $0.folderNavigation = "continuous" }
        XCTAssertTrue(model.isContinuousScrolling); XCTAssertEqual(model.navigationDirection, .vertical)
        model.closeFolder()
        XCTAssertFalse(model.isContinuousScrolling); XCTAssertEqual(model.navigationDirection, .horizontal)
        XCTAssertEqual(model.layout, original)
    }
    func testSearchCategoryAndHiddenCacheInvalidation() throws {
        let (model, _, cleanup) = try fixture(); defer { cleanup() }
        _ = model.browsingLayout
        model.setAppHidden("test.00", hidden: true)
        XCTAssertFalse(model.browsingLayout.appIDs.contains("test.00"))
        model.query = "App"
        let category = try XCTUnwrap(model.availableSearchCategories.first)
        model.selectSearchCategory(category)
        XCTAssertEqual(model.results.count, model.count(for: category))
        XCTAssertFalse(model.results.contains { $0.id == "test.00" })
        model.query = ""; XCTAssertNil(model.searchCategory)
        model.setAppHidden("test.00", hidden: false)
        XCTAssertTrue(model.browsingLayout.appIDs.contains("test.00"))
    }

    func testBatchMoveIntoFolderAndPageKeepsAllAppsAndIsUndoable() throws {
        let (model, _, cleanup) = try fixture(); defer { cleanup() }
        model.createFolder(containing: "test.00"); model.finishRename(cancel: true); model.closeFolder()
        let folderID = try XCTUnwrap(model.layout.folders.first?.id)
        let before = model.layout
        model.toggleMultiSelection()
        model.toggleItemSelection(.app("test.37")); model.toggleItemSelection(.app("test.39"))
        model.moveSelection(toFolder: folderID)
        XCTAssertEqual(model.layout.folders.first?.children, ["test.00", "test.37", "test.39"])
        XCTAssertEqual(model.layout.appIDs.sorted(), before.appIDs.sorted())
        model.undoOrganization(); XCTAssertEqual(model.layout, before)
        if !model.multiSelectionActive { model.toggleMultiSelection() }
        model.toggleItemSelection(.app("test.37")); model.toggleItemSelection(.app("test.39"))
        model.moveSelection(toPage: 0)
        XCTAssertEqual(model.layout.appIDs.sorted(), before.appIDs.sorted())
        XCTAssertTrue(model.layout.pages[0].contains(.app("test.37")))
        model.undoOrganization(); XCTAssertEqual(model.layout, before)
    }

    func testOrganizeDownloadedFirstAndSortByNameAreUndoable() throws {
        let (model, _, cleanup) = try fixture(); defer { cleanup() }
        let before = model.layout
        model.shuffleLayout()
        XCTAssertNotEqual(model.layout.allItems, before.allItems)
        model.sortByName()
        XCTAssertEqual(model.layout.appIDs, before.appIDs)
        model.organizeDownloadedFirst()
        XCTAssertEqual(model.layout.appIDs, before.appIDs)
        model.undoOrganization()
        model.undoOrganization()
        model.undoOrganization()
        XCTAssertEqual(model.layout, before)
    }

}
#endif
