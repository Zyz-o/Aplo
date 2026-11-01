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
        model.createFolder(containing: "test.39"); model.finishRename(cancel: true); model.closeFolder()
        let original = model.layout
        model.setAppHidden("test.39", hidden: true)
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
}
#endif
