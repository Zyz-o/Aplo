#if SWIFT_PACKAGE
@testable import Aplo
#endif
import AppKit
import Foundation

#if !SWIFT_PACKAGE
@main
#endif
 struct ClassificationTests {
    @MainActor static func main() throws {
        var count = 0
        func expect(_ value: Bool, _ text: String) {
            precondition(value, text); count += 1; print("PASS: " + text)
        }
        func app(_ id: String, _ name: String, _ metadata: String? = nil, _ path: String = "/Applications/Test.app") -> InstalledApp {
            InstalledApp(id: id, name: name, url: URL(fileURLWithPath: path), bundleIdentifier: id, categoryIdentifier: metadata)
        }
        let apps = [app("test.editor", "Editor", "public.app-category.developer-tools"),
                    app("test.office", "Office", "public.app-category.productivity"),
                    app("com.tencent.xinWeChat", "微信"), app("test.unknown", "Unknown"),
                    app("com.apple.finder", "访达", nil, "/System/Library/CoreServices/Finder.app")]
        expect(AppClassifier.category(for: apps[0]) == .development, "developer metadata determines category")
        expect(AppClassifier.category(for: apps[1]) == .productivity, "productivity metadata determines category")
        expect(AppClassifier.category(for: apps[2]) == .communication, "known applications use a fallback rule")
        expect(AppClassifier.category(for: apps[3]) == .other, "unknown applications remain in Other")
        expect(AppClassifier.category(for: apps[4]) == .system, "uncategorized system apps remain visible")
        expect(AppClassifier.category(for: app("com.tencent.qq", "QQ", "public.app-category.developer-tools")) == .communication, "known communications apps override generic developer metadata")
        expect(AppClassifier.category(for: app("com.bytedance.douyin.desktop", "抖音", "public.app-category.developer-tools")) == .media, "known video apps override generic developer metadata")
        let appleDeveloper = app("com.apple.dt.Xcode", "Xcode", "public.app-category.developer-tools", "/Applications/Xcode.app")
        let systemMedia = app("com.apple.music", "Music", "public.app-category.music", "/System/Applications/Music.app")
        expect(!appleDeveloper.isSystemApplication && systemMedia.isSystemApplication, "system provenance depends on installation path rather than the Apple identifier prefix")
        expect(AppClassifier.category(for: systemMedia) == .system, "system applications stay in the final system category despite their content metadata")
        let orderedApps = [systemMedia, apps[0], apps[4], apps[1]]
        let map = Dictionary(uniqueKeysWithValues: orderedApps.map { ($0.id, $0) })
        let items = orderedApps.map { LayoutItem.app($0.id) }
        let ordered = AppClassifier.systemLast(items, appsByID: map)
        expect(ordered.map(\.appID) == [apps[0].id, apps[1].id, systemMedia.id, apps[4].id], "system-last presentation is a stable partition of existing manual order")
        expect(items.first?.appID == systemMedia.id, "system-last presentation does not mutate its source layout")
        let generated = AppClassifier.layout(for: apps)
        expect(generated.appIDs.count == apps.count && Set(generated.appIDs) == Set(apps.map(\.id)), "automatic folders contain each installed app exactly once")
        expect(generated.pages.last?.last?.id == "category:system", "the system folder follows every third-party category")
        expect(generated == AppClassifier.layout(for: apps), "automatic category identifiers are stable")
        let system = AppCatalog(roots: [], includeSystemApplications: true).scan()
        expect(system.contains(where: { $0.bundleIdentifier == "com.apple.finder" }), "Finder is discovered from its explicit system path")
        expect(system.contains(where: { $0.url.path.hasPrefix("/System/Applications/") }), "standalone system applications are discovered")
        expect(Set(system.map(\.id)).count == system.count, "system inventory has no duplicate identifiers")
        print("SYSTEM APP COUNT: \(system.count)")
        let domain = "local.aplo.category-test." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AploCategory-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for index in 0..<2 {
            let contents = root.appendingPathComponent("Apps/App\(index).app/Contents")
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            let data: [String: Any] = ["CFBundlePackageType":"APPL", "CFBundleIdentifier":"test.\(index)", "CFBundleName":"App \(index)", "LSApplicationCategoryType": index == 0 ? "public.app-category.productivity" : "public.app-category.games"]
            try PropertyListSerialization.data(fromPropertyList: data, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        }
        let store = LayoutStore(url: root.appendingPathComponent("layout.json"))
        let model = LauncherModel(catalog: AppCatalog(roots: [root.appendingPathComponent("Apps")], excludedRoots: []), store: store, defaults: defaults)
        model.refresh()
        expect(model.browsingLayout.folders.count == 2 && !model.canOrganize, "automatic mode presents categorized folders")
        model.updatePreferences { $0.automaticCategories = false }
        model.createFolder(containing: "test.0")
        let manual = model.layout
        let saved = try Data(contentsOf: store.url)
        model.updatePreferences { $0.automaticCategories = true }
        let after = try Data(contentsOf: store.url)
        expect(model.layout == manual && after == saved, "enabling categories does not overwrite the manual layout")
        model.updatePreferences { $0.automaticCategories = false }
        expect(model.browsingLayout == manual, "disabling categories restores the manual folders and order")
        model.updatePreferences { $0.automaticCategories = true }
        try model.restore(manual)
        expect(!model.preferences.automaticCategories && model.browsingLayout == manual, "restoring a layout makes its manual arrangement visible")
        model.closeFolder()
        let beforeFree = model.layout
        model.updatePreferences { $0.navigationStyle = .paged }
        model.chooseArrangement(.free)
        expect(model.isContinuousScrolling && model.visibleItems.count == model.containerItems.count, "free placement exposes the full canvas even when paging is the saved preference")
        model.setFreePosition("app:test.0", x: 0.3, y: 0.7)
        expect(model.layout.pages == beforeFree.pages && model.layout.freePositions?[model.freePositionKey("app:test.0")] == FreeIconPosition(x: 0.3, y: 0.7), "free placement leaves grid order and folders untouched")
        model.chooseArrangement(.grid)
        expect(model.layout.pages == beforeFree.pages && !model.usesFreePlacement, "switching back to grid restores the existing layout")
        let exportedFree = try LayoutStore.decode(model.backupData())
        expect(exportedFree.freePositions == model.layout.freePositions, "layout backup includes free-placement coordinates")
        let idsBeforeShuffle = model.layout.appIDs.sorted()
        let foldersBeforeShuffle = Set(model.layout.folders.map(\.id))
        model.shuffleLayout()
        expect(model.layout.appIDs.sorted() == idsBeforeShuffle && Set(model.layout.folders.map(\.id)) == foldersBeforeShuffle, "shuffle preserves every app and folder")
        expect(model.layout.freePositions?[model.freePositionKey("app:test.0")] != nil, "shuffle retains the independent free-placement coordinates")
        model.query = "App 0"
        expect(model.containerItems.count == 1, "cached container invalidates when search changes")
        model.query = ""
        expect(model.containerItems.count == model.layout.allItems.count, "clearing search restores the cached browsing container")
        print("All \(count) classification and system-discovery checks passed.")
    }
}
