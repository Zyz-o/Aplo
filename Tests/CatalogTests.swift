#if SWIFT_PACKAGE
@testable import Aplo
#endif
import AppKit
import Foundation
import Combine

#if !SWIFT_PACKAGE
@main
#endif

struct CatalogTests {
    @MainActor
    static func main() async throws {
        let manager = FileManager.default
        let domain = "local.aplo.manual-test." + UUID().uuidString
        let testDefaults = UserDefaults(suiteName: domain)!
        defer { testDefaults.removePersistentDomain(forName: domain) }
        var manual = LauncherPreferences(); manual.automaticCategories = false; manual.navigationStyle = .paged
        PreferencesStore(defaults: testDefaults).save(manual)
        let base = manager.temporaryDirectory.appendingPathComponent("JianqiTests-" + UUID().uuidString, isDirectory: true)
        let user = base.appendingPathComponent("UserApplications", isDirectory: true)
        let shared = base.appendingPathComponent("Applications", isDirectory: true)
        let system = base.appendingPathComponent("System", isDirectory: true)
        try manager.createDirectory(at: user, withIntermediateDirectories: true)
        try manager.createDirectory(at: shared, withIntermediateDirectories: true)
        try manager.createDirectory(at: system, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: base) }

        func makeApp(_ root: URL, _ filename: String, _ identifier: String, name: String? = nil, extras: [String: Any] = [:]) throws -> URL {
            let app = root.appendingPathComponent(filename)
            let contents = app.appendingPathComponent("Contents")
            try manager.createDirectory(at: contents, withIntermediateDirectories: true)
            var info: [String: Any] = [
                "CFBundlePackageType": "APPL",
                "CFBundleIdentifier": identifier,
                "CFBundleName": filename.replacingOccurrences(of: ".app", with: "")
            ]
            if let name { info["CFBundleDisplayName"] = name }
            info.merge(extras) { _, new in new }
            let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            try data.write(to: contents.appendingPathComponent("Info.plist"))
            return app
        }
        func expect(_ condition: @autoclosure () -> Bool, _ description: String) {
            guard condition() else { fatalError("FAIL: " + description) }
            print("PASS: " + description)
        }

        let alpha = try makeApp(user, "Alpha.app", "test.alpha", name: "Alpha Search")
        _ = try makeApp(shared, "Duplicate.app", "test.alpha", name: "Duplicate")
        let nested = shared.appendingPathComponent("Tools")
        let menuApp = try makeApp(nested, "Magpie.app", "test.magpie", name: "Magpie", extras: ["LSUIElement": true])
        _ = try makeApp(menuApp.appendingPathComponent("Contents/Helpers"), "Internal.app", "test.internal")
        _ = try makeApp(shared, "Notes.app", "test.chinese", name: "中文笔记")
        _ = try makeApp(shared, ".Hidden.app", "test.hidden")
        _ = try makeApp(shared.appendingPathComponent(".HiddenFolder"), "Secret.app", "test.secret")
        _ = try makeApp(shared, "Background.app", "test.background", extras: ["LSBackgroundOnly": true])
        _ = try makeApp(shared, "BackgroundString.app", "test.background.string", extras: ["LSBackgroundOnly": "YES"])
        _ = try makeApp(shared, "Self.app", AppCatalog.ownBundleIdentifier)
        _ = try makeApp(shared, "Invalid.app", "test.invalid", extras: ["CFBundlePackageType": "BNDL"])
        let systemApp = try makeApp(system, "System.app", "test.system")
        try manager.createSymbolicLink(at: shared.appendingPathComponent("SystemLink.app"), withDestinationURL: systemApp)
        try manager.createSymbolicLink(at: shared.appendingPathComponent("Alias.app"), withDestinationURL: alpha)
        try manager.createSymbolicLink(at: shared.appendingPathComponent("Broken.app"), withDestinationURL: base.appendingPathComponent("Missing.app"))
        let catalog = AppCatalog(roots: [user, shared, base.appendingPathComponent("Unavailable")], excludedRoots: [system])
        let apps = catalog.scan()
        expect(apps.count == 3, "only eligible applications are included")
        expect(Set(apps.compactMap(\.bundleIdentifier)) == ["test.alpha", "test.magpie", "test.chinese"], "hidden, internal, background, self, system and invalid bundles are excluded")
        expect(apps.first(where: { $0.id == "test.alpha" })?.url.path == alpha.path, "user copy wins when identifiers repeat")
        expect(apps.contains(where: { $0.url.path == menuApp.path }), "menu-bar application is included")
        expect(apps.first(where: { $0.id == "test.alpha" })?.name == "Alpha Search", "display name is used")
        expect(AppCatalog.matching(apps, query: "  ALPHA  ").map(\.id) == ["test.alpha"], "English search ignores case and surrounding whitespace")
        expect(AppCatalog.matching(apps, query: "笔记").map(\.id) == ["test.chinese"], "Chinese partial-name search works")
        expect(AppCatalog.matching(apps, query: "no-match").isEmpty, "no-match query returns an empty list")
        expect(AppCatalog.matching(apps, query: " \n ").count == 3, "empty query shows all applications")

        let model = LauncherModel(catalog: catalog, store: LayoutStore(url: base.appendingPathComponent("layout.json")), defaults: testDefaults)
        model.refresh()
        model.moveSelection(by: -6)
        expect(model.selectedIndex == 0, "selection clamps at the beginning")
        model.moveSelection(by: 6)
        expect(model.selectedIndex == 2, "selection clamps at the last item")
        model.query = "Magpie"
        expect(model.selectedApp?.id == "test.magpie" && model.selectedIndex == 0, "filtering resets selection")
        model.query = "not installed"
        model.moveSelection(by: 1)
        expect(model.selectedApp == nil, "empty search has no launchable selection")
        model.refresh()
        expect(model.query.isEmpty && model.results.count == 3, "opening resets search")
        let later = try makeApp(shared, "Later.app", "test.later")
        model.refresh()
        expect(model.apps.contains(where: { $0.id == "test.later" }), "new installations appear on refresh")
        model.query = "Later"
        try manager.removeItem(at: later)
        model.refresh(resetSearch: false)
        expect(model.query == "Later" && model.results.isEmpty, "removed apps disappear while an error refresh preserves the query")
        model.refresh()
        expect(model.apps.count == 3, "refresh does not leave stale applications")

        let localized = try makeApp(shared, "Localized.app", "test.localized", name: "English Name")
        let localizationFolder = localized.appendingPathComponent("Contents/Resources/zh-Hans.lproj")
        try manager.createDirectory(at: localizationFolder, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleDisplayName": "本地化应用"], format: .xml, options: 0)
            .write(to: localizationFolder.appendingPathComponent("InfoPlist.strings"))
        let chineseCatalog = AppCatalog(roots: [shared], excludedRoots: [system], preferredLanguages: ["zh-Hans-CN"])
        expect(chineseCatalog.scan().first(where: { $0.id == "test.localized" })?.name == "本地化应用", "names follow the user's language even in an unlocalized host process")

        let modern = try makeApp(shared, "Modern.app", "test.modern", name: "Activity Monitor")
        let modernResources = modern.appendingPathComponent("Contents/Resources")
        try manager.createDirectory(at: modernResources, withIntermediateDirectories: true)
        let table = ["en": ["CFBundleDisplayName": "Activity Monitor"],
                     "zh_CN": ["CFBundleName": "通用名称"],
                     "zh_CN~mac": ["CFBundleDisplayName": "活动监视器"],
                     "zh_TW": ["CFBundleDisplayName": "活動監視器"]]
        try PropertyListSerialization.data(fromPropertyList: table, format: .binary, options: 0)
            .write(to: modernResources.appendingPathComponent("InfoPlist.loctable"))
        let nativeChinese = chineseCatalog.scan().first { $0.id == "test.modern" }!
        expect(nativeChinese.name == "活动监视器", "modern Apple localization tables provide the native macOS Chinese name")
        expect(nativeChinese.searchAliases.contains("Activity Monitor"), "translated applications retain their original English name as a search alias")
        expect(chineseCatalog.scan(preferredLanguages: ["zh-Hant"]).first { $0.id == "test.modern" }?.name == "活動監視器", "traditional Chinese selects the matching Apple table language")
        expect(chineseCatalog.scan(preferredLanguages: ["en"]).first { $0.id == "test.modern" }?.name == "Activity Monitor", "explicit English selection retains English system application names")
        model.updatePreferences { $0.language = .chinese }
        await model.waitForCatalogRefresh()
        expect(model.apps.first { $0.id == "test.modern" }?.name == "活动监视器", "changing application language refreshes native names in the background")
        model.query = "Activity Monitor"
        expect(model.selectedApp?.id == "test.modern", "English search still finds a system app displaying its Chinese name")
        model.query = ""
        let wrapper = base.appendingPathComponent("Wrapped.app")
        let inner = wrapper.appendingPathComponent("Wrapper/Portable.app")
        try manager.createDirectory(at: inner, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundlePackageType": "APPL", "CFBundleIdentifier": "test.wrapped", "CFBundleDisplayName": "封装应用"], format: .binary, options: 0).write(to: inner.appendingPathComponent("Info.plist"))
        try manager.createSymbolicLink(atPath: wrapper.appendingPathComponent("WrappedBundle").path, withDestinationPath: "Wrapper/Portable.app")
        let wrappedSnapshot = AppCatalog(roots: [wrapper], excludedRoots: []).snapshot()
        expect(wrappedSnapshot.isComplete && wrappedSnapshot.apps.first?.id == "test.wrapped", "Apple iPhone/iPad wrappers are recognized without marking discovery incomplete")
        expect(wrappedSnapshot.apps.first?.name == "封装应用" && wrappedSnapshot.apps.first?.url.path == wrapper.resolvingSymlinksInPath().standardizedFileURL.path, "wrapped apps retain their native display name and launchable outer bundle URL")
        let live = AppCatalog().scan()
        print("LIVE APPS (\(live.count)): " + live.map(\.name).joined(separator: ", "))
        if manager.fileExists(atPath: "/Applications/magpie.app") {
            expect(live.contains(where: { $0.url.lastPathComponent.lowercased() == "magpie.app" }), "installed Magpie is discoverable")
        }
        expect(!live.contains(where: { $0.url.path.hasPrefix("/System/") }), "live catalog excludes the system directory")
        // UI refresh returns the cached inventory immediately while filesystem work runs off-main.
        let countBeforeAsync = model.apps.count
        let asyncApp = try makeApp(shared, "Async.app", "test.async")
        model.requestRefresh()
        expect(model.apps.count == countBeforeAsync, "requesting a UI refresh returns the cached inventory immediately")
        model.query = "Async"
        await model.waitForCatalogRefresh()
        expect(model.selectedApp?.id == "test.async" && model.query == "Async", "background scan completion preserves a query entered while scanning")
        model.query = ""
        var unchangedNotifications = 0
        let unchangedSubscription = model.objectWillChange.sink { unchangedNotifications += 1 }
        model.requestRefresh(resetSearch: false)
        await model.waitForCatalogRefresh()
        expect(unchangedNotifications == 0, "an unchanged background inventory does not invalidate the grid")
        unchangedSubscription.cancel()
        try manager.removeItem(at: asyncApp)
        model.requestRefresh(resetSearch: false)
        model.requestRefresh(resetSearch: false)
        await model.waitForCatalogRefresh()
        expect(!model.apps.contains { $0.id == "test.async" }, "the newest background scan removes uninstalled apps after superseding an earlier request")
        let dragApp = try makeApp(shared, "DuringDrag.app", "test.during-drag")
        model.beginInteractiveDrag("app:test.alpha")
        model.requestRefresh(resetSearch: false)
        // End the session before accepting its result; no drag identity is changed by the scan.
        expect(model.draggingID == "app:test.alpha", "a background refresh request preserves the active native drag source")
        model.endDrag()
        await model.waitForCatalogRefresh()
        expect(model.apps.contains { $0.id == "test.during-drag" }, "deferred inventory changes are applied after drag completion")
        try manager.removeItem(at: dragApp)
        print("All catalog and selection tests passed.")
    }
}
