#if SWIFT_PACKAGE
import XCTest
@testable import Aplo

@MainActor final class InventorySafetyTests: XCTestCase {
    func testColdPartialScanThenOrganizePreservesBothProfiles() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let apps = root.appendingPathComponent("Apps")
        try fm.createDirectory(at: apps, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let domain = "local.aplo.inventory-safety." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        var preferences = LauncherPreferences(); preferences.automaticCategories = false
        PreferencesStore(defaults: defaults).save(preferences)
        func metadata(_ id: String) throws -> URL {
            let contents = apps.appendingPathComponent(id + ".app/Contents")
            try fm.createDirectory(at: contents, withIntermediateDirectories: true)
            let info = contents.appendingPathComponent("Info.plist")
            try PropertyListSerialization.data(fromPropertyList: ["CFBundlePackageType": "APPL", "CFBundleIdentifier": id, "CFBundleName": id], format: .binary, options: 0).write(to: info)
            return info
        }
        _ = try metadata("a"); let missing = try metadata("b"); _ = try metadata("c")
        let folder = LayoutItem.folder("Keep my folder", children: ["b"])
        let positions = ["root:horizontal:app:b": FreeIconPosition(x: 0.7, y: 0.4)]
        let inactive = DisplayLayoutProfile(pages: [[.app("c"), folder, .app("a")]], freePositions: positions)
        let original = LauncherLayout(otherDisplayLayout: inactive, activeLayoutIsFullscreen: false, freePositions: positions, pages: [[folder, .app("a"), .app("c")]])
        let store = LayoutStore(url: root.appendingPathComponent("Data/layout.json"))
        try store.save(original)
        try fm.removeItem(at: missing)
        let catalog = AppCatalog(roots: [apps], excludedRoots: [])
        XCTAssertFalse(catalog.snapshot().isComplete)
        let model = LauncherModel(catalog: catalog, store: store, defaults: defaults)
        model.refresh(resetSearch: false)
        XCTAssertFalse(model.apps.contains { $0.id == "b" })
        model.createFolder(containing: "a")
        XCTAssertEqual(model.layout.folders.first { $0.id == folder.id }, folder)
        XCTAssertEqual(model.layout.otherDisplayLayout, inactive)
        XCTAssertEqual(model.layout.freePositions, positions)
        XCTAssertEqual(try store.load(), model.layout)
        let backups = try fm.contentsOfDirectory(at: root.appendingPathComponent("Data/Backups"), includingPropertiesForKeys: nil)
        XCTAssertTrue(try backups.contains { try LayoutStore.read($0) == original })
        _ = try metadata("b")
        let reopened = LauncherModel(catalog: catalog, store: store, defaults: defaults)
        reopened.refresh(resetSearch: false)
        XCTAssertEqual(reopened.layout.folders.first { $0.id == folder.id }, folder)
        XCTAssertEqual(reopened.layout.otherDisplayLayout, inactive)
    }
    func testBackupFailureBlocksPartialInventoryEdits() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let app = root.appendingPathComponent("Apps/a.app/Contents")
        try fm.createDirectory(at: app, withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("Apps/b.app"), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundlePackageType": "APPL", "CFBundleIdentifier": "a"], format: .binary, options: 0).write(to: app.appendingPathComponent("Info.plist"))
        let domain = "local.aplo.backup-failure." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let profile = DisplayLayoutProfile(pages: [[.app("a"), .folder("Keep", children: ["b"])]], freePositions: nil)
        let original = LauncherLayout(otherDisplayLayout: profile, activeLayoutIsFullscreen: false, pages: profile.pages)
        let store = LayoutStore(url: root.appendingPathComponent("Data/layout.json"))
        try store.save(original)
        // A regular file where the backup directory should be forces a deterministic archive failure.
        try Data("blocked".utf8).write(to: root.appendingPathComponent("Data/Backups"))
        let before = try Data(contentsOf: store.url)
        let model = LauncherModel(catalog: AppCatalog(roots: [root.appendingPathComponent("Apps")], excludedRoots: []), store: store, defaults: defaults)
        model.refresh(resetSearch: false)
        model.createFolder(containing: "a")
        XCTAssertEqual(model.layout, original)
        XCTAssertEqual(try Data(contentsOf: store.url), before)
    }

    func testRemovalGuardChecksEachDisplayProfile() {
        let profile = DisplayLayoutProfile(pages: [[.app("a"), .app("b")]], freePositions: nil)
        let original = LauncherLayout(otherDisplayLayout: profile, activeLayoutIsFullscreen: false, pages: profile.pages)
        var candidate = original
        candidate.pages = [[.app("a")]]
        XCTAssertEqual(candidate.removedAppIDs(from: original), ["b"])
        candidate = original
        candidate.prepareDisplayMode(fullscreen: true)
        XCTAssertTrue(candidate.removedAppIDs(from: original).isEmpty)
    }

    nonisolated private static func prepareOffMain(_ apps: [InstalledApp]) -> (PreparedSearchIndex, Bool) {
        (IntegratedSearch.prepare(apps, reusing: [:]), Thread.isMainThread)
    }

    func testBackgroundSearchPreparationPreservesRanking() async {
        let apps = [InstalledApp(id: "wx", name: "微信", url: URL(fileURLWithPath: "/wx.app"), bundleIdentifier: nil, searchAliases: ["WeChat"]),
                    InstalledApp(id: "memo", name: "備忘錄", url: URL(fileURLWithPath: "/memo.app"), bundleIdentifier: nil, searchAliases: ["Notes"])]
        let synchronous = IntegratedSearch(); synchronous.update(apps)
        let (prepared, ranOnMainThread) = await Task.detached {
            Self.prepareOffMain(apps)
        }.value
        XCTAssertFalse(ranOnMainThread)
        let background = IntegratedSearch(); background.install(prepared)
        for query in ["wx", "微信", "wechat", "备忘录", "備忘錄", "notes", "zzzzz", ""] {
            XCTAssertEqual(background.matching(apps, query: query).map(\.id), synchronous.matching(apps, query: query).map(\.id))
        }
    }

}
#endif
