#if SWIFT_PACKAGE
@testable import Aplo
#endif
import AppKit
import Carbon
import Foundation
import Combine
import SQLite3

#if !SWIFT_PACKAGE
@main
#endif

struct LayoutTests {
    @MainActor
    static func main() async throws {
        let fm = FileManager.default
        let domain = "local.aplo.manual-test." + UUID().uuidString
        let testDefaults = UserDefaults(suiteName: domain)!
        defer { testDefaults.removePersistentDomain(forName: domain) }
        var manual = LauncherPreferences(); manual.automaticCategories = false; manual.navigationStyle = .paged
        PreferencesStore(defaults: testDefaults).save(manual)
        let base = fm.temporaryDirectory.appendingPathComponent("JianqiLayoutTests-" + UUID().uuidString)
        let appRoot = base.appendingPathComponent("Applications")
        try fm.createDirectory(at: appRoot, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }
        var checks = 0
        func expect(_ passed: @autoclosure () throws -> Bool, _ name: String) {
            guard (try? passed()) == true else { fatalError("FAIL: " + name) }
            checks += 1
            print("PASS: " + name)
        }
        for index in 0..<40 {
            let name = String(format: "App %02d", index)
            let contents = appRoot.appendingPathComponent(name + ".app/Contents")
            try fm.createDirectory(at: contents, withIntermediateDirectories: true)
            let info: [String: Any] = ["CFBundlePackageType": "APPL",
                "CFBundleIdentifier": String(format: "test.a%02d", index), "CFBundleName": name]
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
                .write(to: contents.appendingPathComponent("Info.plist"))
        }
        let catalog = AppCatalog(roots: [appRoot], excludedRoots: [])
        let store = LayoutStore(url: base.appendingPathComponent("State/layout.json"))
        let model = LauncherModel(catalog: catalog, store: store, defaults: testDefaults)
        model.refresh()
        var gridNotifications = 0
        let subscription = model.objectWillChange.sink { gridNotifications += 1 }
        for frame in 0..<120 { model.pageDragOffset = CGFloat(-frame); model.pageTransitionActive = true }
        expect(gridNotifications == 0, "120 gesture frames do not invalidate the app grid or search field")
        model.pageDragOffset = 0; model.pageTransitionActive = false
        model.pageHeight = 420
        model.pageMotion.axis = .vertical
        expect(model.pageExtent == 420, "vertical paging travels the viewport height rather than its width")
        model.pageMotion.axis = .horizontal
        expect(model.pageExtent == model.pageWidth, "horizontal paging retains the full viewport width")
        subscription.cancel()
        expect(model.pageCount == 3 && model.layout.pages.map(\.count) == [18, 18, 4], "applications are paginated into 18-item pages")
        expect(model.layout.appIDs.count == 40 && Set(model.layout.appIDs).count == 40, "each installed application occurs exactly once")
        model.moveSelection(by: 18)
        expect(model.pageIndex == 1 && model.selectedIndex == 0, "keyboard navigation crosses page boundaries")
        model.changePage(by: 20)
        expect(model.pageIndex == 2, "page navigation clamps at the last page")
        model.goToPage(0)
        let layoutBeforeScroll = try model.backupData()
        model.updatePreferences { $0.navigationStyle = .continuous; $0.pagingDirection = .vertical }
        expect(model.visibleItems.count == 40, "vertical continuous browsing exposes all applications without 18-item slicing")
        model.moveSelection(by: 26)
        expect(model.selectedIndex == 26 && model.selectedApp?.id == "test.a26", "continuous keyboard selection crosses former page boundaries")
        model.updatePreferences { $0.pagingDirection = .horizontal }
        model.select(5); model.moveSelection(by: 1)
        expect(model.selectedIndex == 18, "horizontal continuous keyboard selection crosses into the next six-column block")
        model.moveSelection(by: -1)
        expect(model.selectedIndex == 5, "horizontal continuous keyboard selection can return across the same boundary")
        model.updatePreferences { $0.navigationStyle = .paged }
        expect(model.visibleItems.count == 18 && model.pageIndex == 0, "paged browsing remains selectable with its original item slicing")
        expect(try model.backupData() == layoutBeforeScroll, "switching continuous axes and paging does not rewrite the saved layout")
        model.goToPage(0)
        expect(!model.editing && model.canBeginIconDrag, "manual grids accept native icon dragging without entering edit mode first")
        model.beginInteractiveDrag("app:test.a00")
        expect(model.editing && model.canOrganize && model.draggingID == "app:test.a00", "a real drag enters organization mode and enables folder destinations")
        var dragNotifications = 0
        let dragSubscription = model.objectWillChange.sink { dragNotifications += 1 }
        model.updateDropTarget("app:test.a05", hint: "松开组成文件夹", indicator: .merge)
        let initialDragNotifications = dragNotifications
        for _ in 0..<120 { model.updateDropTarget("app:test.a05", hint: "松开组成文件夹", indicator: .merge) }
        expect(dragNotifications == initialDragNotifications, "repeated movement over one folder target does not invalidate the grid")
        let unaffected = model.dragFeedback(for: "app:test.a39")
        var unaffectedNotifications = 0
        let unaffectedSubscription = unaffected.objectWillChange.sink { unaffectedNotifications += 1 }
        let notificationsBeforeSweep = dragNotifications
        for _ in 0..<20 {
            for index in 1..<30 { model.updateDropTarget(String(format: "app:test.a%02d", index), hint: "松开组成文件夹", indicator: .merge) }
        }
        expect(dragNotifications == notificationsBeforeSweep, "580 rapid destination changes do not invalidate the grid or app labels")
        expect(unaffectedNotifications == 0, "rapid dragging never invalidates untouched tile feedback")
        expect(model.dragFeedback(for: "app:test.a29").isMergeTarget && !model.dragFeedback(for: "app:test.a28").isMergeTarget, "only the current tile retains the merge preview")
        model.clearDropTarget("app:test.a28")
        expect(model.dropTargetID == "app:test.a29", "a stale destination exit cannot clear a newer drag target")
        model.updateDropTarget("app:test.a29", hint: "松开放在后面", indicator: .after)
        expect(model.dragFeedback(for: "app:test.a29").indicator == .after, "moving to the tile edge removes the merge preview without refreshing the grid")
        model.clearDropTarget()
        expect(model.dropTargetID == nil && model.dropHint == nil && dragNotifications == notificationsBeforeSweep, "clearing drag feedback does not publish a grid refresh")
        unaffectedSubscription.cancel()
        dragSubscription.cancel()
        model.drop("app:test.a00", onto: "app:test.a05", position: .after)
        expect(model.layout.pages[0][5].appID == "test.a00", "drop at an edge reorders applications")
        model.drop("app:test.a00", onto: "app:test.a01", position: .center)
        let folder = model.layout.folders.first!
        expect(folder.children == ["test.a01", "test.a00"], "drop on an application center creates a folder")
        expect(Set(model.layout.appIDs).count == 40, "grouping does not lose or duplicate applications")
        model.moveApp("test.a20", toFolder: folder.id)
        expect(model.layout.folders.first!.children.count == 3, "applications can move into an existing folder across pages")
        model.beginRename(model.layout.folders.first!)
        model.folderNameDraft = "工作工具"
        model.finishRename()
        expect(model.layout.folders.first!.title == "工作工具", "folder names persist")
        model.drop("app:test.a20", onto: "app:test.a01", position: .before)
        expect(model.openFolder?.children.first == "test.a20", "applications can be reordered inside a folder")
        model.query = "app 01"
        expect(model.selectedApp?.id == "test.a01", "global search finds applications inside folders")
        model.query = ""
        model.moveApp("test.a20", toFolder: nil)
        expect(!model.openFolder!.children.contains("test.a20") && model.layout.appIDs.contains("test.a20"), "moving out of a folder retains the application")
        model.closeFolder()
        model.drop("app:test.a39", toPage: model.layout.pages.count)
        expect(model.layout.pages.last?.first?.appID == "test.a39", "dropping on a new page creates that page")
        model.dissolve(folder.id)
        expect(model.layout.folders.isEmpty && Set(model.layout.appIDs).count == 40, "dissolving a folder retains every child")
        let saved = try store.load()!
        expect(saved == model.layout, "disk persistence round-trips the layout")
        let second = LauncherModel(catalog: catalog, store: store, defaults: testDefaults)
        second.refresh()
        expect(second.layout == model.layout, "reopening preserves the custom arrangement")

        let custom = ShortcutBinding(keyCode: 0, modifiers: UInt32(cmdKey | optionKey), keyName: "A")
        expect(custom.isValid && custom.displayName == "⌥⌘A", "custom hotkeys validate and display their modifiers")
        expect(!ShortcutBinding(keyCode: 49, modifiers: 0, keyName: "空格").isValid, "unmodified global hotkeys are rejected")
        expect(!ShortcutBinding(keyCode: 56, modifiers: UInt32(cmdKey), keyName: "Shift").isValid, "modifier-only hotkeys are rejected")
        expect(!ShortcutBinding(keyCode: 49, modifiers: UInt32(cmdKey) | 1, keyName: "空格").isValid, "unknown modifier flags are rejected")
        expect(model.saveShortcut(custom), "custom shortcuts persist")
        let data = try model.backupData()
        let exported = try LayoutStore.decode(data)
        expect(exported.pages == model.layout.pages && exported.shortcut == model.layout.shortcut && exported.backupPresentation != nil, "exported JSON includes layout, shortcut and arrangement choices")
        var invalid = model.layout
        invalid.version = 99
        let beforeInvalid = try Data(contentsOf: store.url)
        do { try model.restore(invalid); fatalError("unsupported version was accepted") } catch {}
        expect(try Data(contentsOf: store.url) == beforeInvalid, "invalid restore does not overwrite the current layout")
        let backupsBefore = (try? fm.contentsOfDirectory(atPath: store.url.deletingLastPathComponent().appendingPathComponent("Backups").path).count) ?? 0
        var restore = saved
        restore.pages = [[.folder("恢复文件夹", children: ["test.a00", "not.installed"]), .app("test.a02")]]
        try model.restore(restore)
        expect(model.layout.folders.first?.children == ["test.a00"], "restore filters out missing applications")
        expect(model.layout.appIDs.count == 40 && model.layout.shortcut == custom, "restore appends other installed applications and keeps the active hotkey until registration")
        let backupsAfter = try fm.contentsOfDirectory(atPath: store.url.deletingLastPathComponent().appendingPathComponent("Backups").path).count
        expect(backupsAfter == backupsBefore + 1, "restore automatically archives the previous layout")

        var messy = LauncherLayout(pages: [[.app("test.a00"), .app("test.a00"),
            .folder("重复", children: ["test.a00", "test.a01", "missing"]), .folder("空", children: [])]])
        messy.reconcile(with: ["test.a00", "test.a01", "test.a02"])
        expect(messy.appIDs == ["test.a00", "test.a01", "test.a02"] && messy.folders.count == 1,
               "reconciliation removes duplicates, empty folders and uninstalled entries")
        let corruptStore = LayoutStore(url: base.appendingPathComponent("Corrupt/layout.json"))
        try fm.createDirectory(at: corruptStore.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let corruptData = Data("broken json".utf8)
        try corruptData.write(to: corruptStore.url)
        let recovered = LauncherModel(catalog: catalog, store: corruptStore, defaults: testDefaults)
        recovered.refresh()
        let recoveryFiles = try fm.contentsOfDirectory(at: corruptStore.url.deletingLastPathComponent().appendingPathComponent("Backups"), includingPropertiesForKeys: nil)
        expect(try recoveryFiles.contains(where: { try Data(contentsOf: $0) == corruptData }), "corrupt layouts are preserved before recovery")
        expect(try corruptStore.load()?.appIDs.count == 40, "recovered layouts remain usable")

        let blockedParent = base.appendingPathComponent("blocked")
        try Data().write(to: blockedParent)
        let blocked = LauncherModel(catalog: catalog, store: LayoutStore(url: blockedParent.appendingPathComponent("layout.json")), defaults: testDefaults)
        blocked.refresh()
        let blockedLayout = blocked.layout
        blocked.createFolder(containing: "test.a00")
        expect(blocked.layout == blockedLayout && blocked.message != nil, "save failures cannot silently discard applications")

        let databaseURL = base.appendingPathComponent("legacy.db")
        var database: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK, let database else { fatalError("cannot create fixture") }
        let sql = """
        CREATE TABLE items (rowid INTEGER PRIMARY KEY, uuid TEXT, type INTEGER, parent_id INTEGER, ordering INTEGER);
        CREATE TABLE apps (item_id INTEGER PRIMARY KEY, bundleid TEXT);
        CREATE TABLE groups (item_id INTEGER PRIMARY KEY, title TEXT);
        INSERT INTO items VALUES
        (1,'ROOTPAGE',1,0,0),(2,'PAGE',3,1,1),(3,'FOLDER',2,2,0),(4,'FPAGE',3,3,0),
        (5,'A',4,4,0),(6,'B',4,4,1),(7,'C',4,2,1),(8,'D',4,2,2),
        (9,'HOLDINGPAGE',3,1,0),(10,'HIDDEN',4,9,0);
        INSERT INTO apps VALUES (5,'test.a01'),(6,'test.a00'),(7,'test.a02'),(8,'not.installed'),(10,'test.a03');
        INSERT INTO groups VALUES (3,'旧工作');
        """
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { fatalError("fixture SQL failed") }
        sqlite3_close(database)
        let databaseBefore = try Data(contentsOf: databaseURL)
        let imported = try LegacyImporter.read(databaseURL, apps: model.apps)
        expect(imported.matchedCount == 3 && imported.skippedCount == 1, "legacy import counts matches and excludes holding pages")
        expect(imported.layout.pages[0][0].title == "旧工作" && imported.layout.pages[0][0].children == ["test.a01", "test.a00"],
               "legacy import preserves folder names and child ordering")
        expect(imported.layout.pages[0][1].appID == "test.a02" && imported.layout.appIDs.count == 40,
               "legacy import preserves root ordering and adds other installed apps")
        expect(try Data(contentsOf: databaseURL) == databaseBefore, "legacy source database remains byte-for-byte unchanged")
        let archiveRoot = base.appendingPathComponent("ArchiveInput")
        try fm.createDirectory(at: archiveRoot, withIntermediateDirectories: true)
        try fm.copyItem(at: databaseURL, to: archiveRoot.appendingPathComponent("db"))
        func zip(_ filename: String, entries: [String]) throws -> URL {
            let output = base.appendingPathComponent(filename)
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            task.currentDirectoryURL = archiveRoot
            task.arguments = ["-q", output.path] + entries
            try task.run()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else { fatalError("cannot create zip fixture") }
            return output
        }
        let zipURL = try zip("legacy.zip", entries: ["db"])
        let zipBefore = try Data(contentsOf: zipURL)
        let zipResult = try LegacySources.read(zipURL, apps: model.apps)
        expect(zipResult.matchedCount == 3 && zipResult.layout.folders.first?.title == "旧工作",
               "legacy ZIP archives import their database and folder layout")
        expect(try Data(contentsOf: zipURL) == zipBefore, "ZIP source archives remain unchanged")
        let lmyURL = base.appendingPathComponent("legacy.lmy")
        try fm.copyItem(at: zipURL, to: lmyURL)
        expect(try LegacySources.read(lmyURL, apps: model.apps).matchedCount == 3, "LMY archives are supported")
        try fm.copyItem(at: databaseURL, to: archiveRoot.appendingPathComponent("one.db"))
        try fm.copyItem(at: databaseURL, to: archiveRoot.appendingPathComponent("two.db"))
        let ambiguousZIP = try zip("ambiguous.zip", entries: ["one.db", "two.db"])
        do { _ = try LegacySources.read(ambiguousZIP, apps: model.apps); fatalError("ambiguous archive accepted") } catch {}
        expect(model.layout.appIDs.count == 40, "archives with multiple databases are rejected without changing the layout")
        let badZIP = base.appendingPathComponent("broken.zip")
        try Data("not zip".utf8).write(to: badZIP)
        do { _ = try LegacySources.read(badZIP, apps: model.apps); fatalError("invalid ZIP accepted") } catch {}
        expect(model.layout.appIDs.count == 40, "corrupt ZIP archives leave the current layout intact")
        expect(LegacySources.discover().allSatisfy { fm.fileExists(atPath: $0.path) },
               "automatic discovery only returns existing files")
        let malformedURL = base.appendingPathComponent("not-a-database")
        try Data("not sqlite".utf8).write(to: malformedURL)
        do { _ = try LegacyImporter.read(malformedURL, apps: model.apps); fatalError("invalid legacy file accepted") } catch {}
        expect(model.layout.appIDs.count == 40, "failed legacy imports do not change the current layout")
        let noApps = try? LegacyImporter.read(databaseURL, apps: [])
        expect(noApps == nil, "legacy import rejects zero matching applications")
        // Migrate legacy positions into full-screen while allowing an independent regular compact grid.
        let modeStore = LayoutStore(url: base.appendingPathComponent("Modes/layout.json"))
        var legacy = LauncherLayout(pages: [[.app("test.a03"), .app("test.a00"), .app("test.a01")]])
        legacy.freePositions = ["root:horizontal:app:test.a03": FreeIconPosition(x: 0.72, y: 0.31)]
        try modeStore.save(legacy)
        let modes = LauncherModel(catalog: catalog, store: modeStore, defaults: testDefaults)
        modes.refresh()
        expect(modes.layout.pages[0].first?.appID == "test.a03" && modes.layout.freePositions == nil, "legacy compact view retains ordering and starts with regular positions")
        modes.isFullscreen = true
        expect(modes.layout.freePositions == legacy.freePositions, "first full-screen view recovers all legacy free positions")
        modes.chooseArrangement(.grid)
        modes.drop("app:test.a03", onto: "app:test.a00", position: .center)
        modes.chooseArrangement(.free)
        modes.setFreePosition("app:test.a01", x: 0.9, y: 0.2)
        let fullProfile = modes.layout.displayProfile
        modes.isFullscreen = false
        expect(!modes.usesFreePlacement && modes.activeArrangement == .grid, "compact defaults to a regular grid independently of full-screen free placement")
        expect(modes.layout.folders.isEmpty, "full-screen grouping does not change compact folders")
        modes.beginInteractiveDrag("app:test.a00")
        modes.drop("app:test.a00", onto: "app:test.a01", position: .after)
        let compactProfile = modes.layout.displayProfile
        modes.isFullscreen = true
        expect(modes.layout.displayProfile == fullProfile && modes.usesFreePlacement, "returning to full-screen restores its order, folders, positions and arrangement")
        let combined = try LayoutStore.decode(modes.backupData())
        expect(combined.otherDisplayLayout == compactProfile && combined.displayProfile == fullProfile, "one atomic backup contains both display layouts")
        let restarted = LauncherModel(catalog: catalog, store: modeStore, defaults: testDefaults)
        restarted.refresh()
        expect(restarted.layout.displayProfile == compactProfile, "restart restores the independent compact ordering")
        restarted.isFullscreen = true
        expect(restarted.layout.displayProfile == fullProfile && restarted.usesFreePlacement, "restart retains the independently edited full-screen layout")
        var badProfile = combined
        badProfile.otherDisplayLayout?.freePositions = ["invalid": FreeIconPosition(x: .infinity, y: 0)]
        do { _ = try badProfile.validated(); fatalError("invalid inactive profile accepted") } catch {}
        expect(true, "invalid coordinates in an inactive profile are rejected before restore")
        var reconciled = combined
        reconciled.reconcile(with: ["test.a00", "test.a01"])
        expect(Set(reconciled.appIDs) == ["test.a00", "test.a01"] && Set(reconciled.otherDisplayLayout!.pages.flatMap { $0 }.flatMap { $0.kind == .app ? [$0.appID!]: $0.children }) == ["test.a00", "test.a01"], "installation reconciliation updates both profiles without duplicates")
        let blockedMode = blocked.isFullscreen
        blocked.isFullscreen.toggle()
        expect(blocked.isFullscreen == blockedMode && blocked.layout == blockedLayout, "a failed mode save preserves the current mode and layout")
        // Regressions from the 2026-10-19 review, isolated from real user data.
        let safetyRoot = base.appendingPathComponent("SafetyApplications")
        func safetyApp(_ id: String) throws -> URL {
            let url = safetyRoot.appendingPathComponent(id + ".app")
            try fm.createDirectory(at: url.appendingPathComponent("Contents"), withIntermediateDirectories: true)
            try PropertyListSerialization.data(fromPropertyList: ["CFBundlePackageType": "APPL", "CFBundleName": id, "CFBundleIdentifier": "safety." + id], format: .xml, options: 0)
                .write(to: url.appendingPathComponent("Contents/Info.plist"))
            return url
        }
        _ = try safetyApp("a")
        let temporaryApp = try safetyApp("b")
        let safetyCatalog = AppCatalog(roots: [safetyRoot], excludedRoots: [])
        let safetyStore = LayoutStore(url: base.appendingPathComponent("Safety/layout.json"))
        let safetyFixture = LauncherLayout(pages: [[.folder("Keep", children: ["safety.b", "safety.a"])]])
        try safetyStore.save(safetyFixture)
        let safety = LauncherModel(catalog: safetyCatalog, store: safetyStore, defaults: testDefaults)
        let coldBytes = try Data(contentsOf: safetyStore.url)
        do { try safety.restore(safetyFixture); fatalError("cold restore accepted") } catch LayoutError.inventoryUnavailable {}
        expect(try Data(contentsOf: safetyStore.url) == coldBytes, "restore before discovery refuses to overwrite any layout data")
        try await safety.ensureInventoryForImport()
        try safety.restore(safetyFixture)
        expect(safety.layout.folders.first?.children == ["safety.b", "safety.a"], "restore succeeds with original folders after trusted background discovery")
        let beforeIncomplete = try Data(contentsOf: safetyStore.url)
        let infoURL = temporaryApp.appendingPathComponent("Contents/Info.plist")
        let infoBytes = try Data(contentsOf: infoURL)
        try fm.removeItem(at: infoURL)
        expect(!safetyCatalog.snapshot().isComplete, "missing metadata marks a discovery snapshot incomplete")
        safety.refresh()
        expect(safety.layout.folders.first?.children == ["safety.b", "safety.a"] && safety.apps.count == 2, "temporarily unreadable applications keep their records and original folder membership")
        expect(try Data(contentsOf: safetyStore.url) == beforeIncomplete, "an incomplete scan cannot rewrite the persisted layout")
        do { try safety.restore(safetyFixture); fatalError("incomplete restore accepted") } catch LayoutError.inventoryUnavailable {}
        expect(try Data(contentsOf: safetyStore.url) == beforeIncomplete, "restore refuses an incomplete inventory without altering disk state")
        try infoBytes.write(to: infoURL)
        safety.refresh()
        expect(safety.layout.folders.first?.children == ["safety.b", "safety.a"], "metadata recovery restores normal discovery without changing folder order")
        safety.chooseArrangement(.free)
        safety.setFreePosition("app:safety.a", x: 0.7, y: 0.2)
        let freeBackup = try LayoutStore.decode(safety.backupData())
        safety.chooseArrangement(.grid)
        try safety.restore(freeBackup)
        expect(safety.usesFreePlacement && safety.layout.freePositions?.count == 1, "restoring a free layout restores both its coordinates and display arrangement")
        safety.chooseArrangement(.grid)
        var legacyBackup = freeBackup; legacyBackup.backupPresentation = nil
        try safety.restore(legacyBackup)
        expect(safety.activeArrangement == .grid, "legacy backups without arrangement metadata preserve the chosen presentation")
        let oversizeURL = base.appendingPathComponent("oversize.json")
        fm.createFile(atPath: oversizeURL.path, contents: nil)
        let oversizeFile = try FileHandle(forWritingTo: oversizeURL)
        try oversizeFile.truncate(atOffset: UInt64(LayoutStore.maximumBytes + 1)); try oversizeFile.close()
        do { _ = try LayoutStore.read(oversizeURL); fatalError("oversize file accepted") } catch LayoutError.tooLarge {}
        expect(true, "bounded backup reading rejects oversized regular files before decoding")
        let control = LegacyReadControl(); control.cancel()
        do { _ = try LegacySources.read(zipURL, apps: model.apps, control: control); fatalError("cancelled archive read accepted") } catch is CancellationError {}
        expect(true, "cancelled archive imports cannot begin extraction or change a layout")
        let timeoutControl = LegacyReadControl(timeout: 0)
        do { _ = try LegacyImporter.read(databaseURL, apps: model.apps, control: timeoutControl); fatalError("expired database read accepted") } catch LayoutError.database(_) {}
        expect(true, "expired database imports stop before parsing")
        let backupDirectory = safetyStore.url.deletingLastPathComponent().appendingPathComponent("Backups")
        let archivesBeforeRemoval = try fm.contentsOfDirectory(atPath: backupDirectory.path).count
        try fm.removeItem(at: temporaryApp)
        safety.refresh()
        expect(safety.layout.appIDs == ["safety.a"], "a complete scan still removes genuinely uninstalled applications")
        expect(try fm.contentsOfDirectory(atPath: backupDirectory.path).count == archivesBeforeRemoval + 1, "confirmed removals archive the previous layout before saving")
        safety.chooseArrangement(.free); safety.editing = false
        safety.beginFreeDrag("app:safety.a")
        expect(safety.draggingID == "app:safety.a", "direct free dragging uses the shared interaction protection without edit mode")
        _ = try safetyApp("c")
        safety.requestRefresh(resetSearch: false)
        try await Task.sleep(for: .milliseconds(40))
        expect(!safety.apps.contains { $0.id == "safety.c" } && safety.draggingID != nil, "background inventory changes wait while free dragging is active")
        safety.endDrag()
        await safety.waitForCatalogRefresh()
        expect(safety.apps.contains { $0.id == "safety.c" }, "queued discovery updates resume after free dragging ends")
        _ = try safetyApp("d")
        safety.noteScrollInteraction()
        safety.requestRefresh(resetSearch: false)
        try await Task.sleep(for: .milliseconds(70))
        expect(!safety.apps.contains { $0.id == "safety.d" }, "continuous scrolling defers inventory commits without publishing gesture state")
        await safety.waitForCatalogRefresh()
        expect(safety.apps.contains { $0.id == "safety.d" }, "inventory commits resume after continuous scrolling becomes idle")
        print("All \(checks) layout, backup, shortcut and importer checks passed.")
    }
}
