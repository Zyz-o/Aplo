#if SWIFT_PACKAGE
import XCTest
@testable import Aplo

@MainActor final class RegressionTests: XCTestCase {
    private final class WeakFeedbackReference {
        weak var value: TileDragFeedback?
        init(_ value: TileDragFeedback) { self.value = value }
    }
    func testCatalog() async throws { try await CatalogTests.main() }
    func testLayout() async throws { try await LayoutTests.main() }
    func testSearch() async { SearchTests.main() }
    func testPreferences() async throws { try PreferencesTests.main() }
    func testClassification() async throws { try ClassificationTests.main() }
    func testPageMotion() async { PageMotionTests.main() }

    private func fixture() -> (LauncherModel, UserDefaults, () -> Void) {
        let domain = "local.aplo.performance-tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = LauncherModel(catalog: AppCatalog(roots: [], excludedRoots: []), store: LayoutStore(url: root.appendingPathComponent("layout.json")), defaults: defaults)
        model.refresh()
        return (model, defaults, {
            model.flushPreferences(); defaults.removePersistentDomain(forName: domain)
            try? FileManager.default.removeItem(at: root)
        })
    }

    func testSliderDiffAndPersistence() async throws {
        let (model, defaults, cleanup) = fixture(); defer { cleanup() }
        var changes: [PreferenceChanges] = []
        model.onPreferencesChanged = { changes.append($0) }
        for i in 0..<100 { model.updatePreferences { $0.backgroundTransparency = 0.2 + Double(i) / 1000 } }
        XCTAssertEqual(changes.count, 100)
        XCTAssertTrue(changes.allSatisfy { $0 == .deferredSave })
        XCTAssertNil(defaults.data(forKey: "aplo.preferences.v1"))
        // Debounce is a minimum delay, not a scheduling deadline on busy CI runners.
        for _ in 0..<100 {
            if defaults.data(forKey: "aplo.preferences.v1") != nil { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(PreferencesStore(defaults: defaults).load(), model.preferences)
        model.updatePreferences { $0.textScalePercent = 123 }
        model.flushPreferences()
        XCTAssertEqual(PreferencesStore(defaults: defaults).load().textScalePercent, 123)
        model.updatePreferences { $0.language = .english }
        XCTAssertTrue(changes.last!.contains(.menus))
        XCTAssertFalse(changes.last!.contains(.frame))
    }

    func testTileEqualityAndActionIndex() async {
        let (model, _, cleanup) = fixture(); defer { cleanup() }
        let item = LayoutItem.app("sample")
        let original = LauncherTile(model: model, item: item, index: 0, selected: false, action: {})
        model.message = "Unrelated notification"
        XCTAssertEqual(original, LauncherTile(model: model, item: item, index: 0, selected: false, action: {}))
        XCTAssertNotEqual(original, LauncherTile(model: model, item: item, index: 1, selected: false, action: {}))
        XCTAssertNotEqual(original, LauncherTile(model: model, item: item, index: 0, selected: true, action: {}))
        model.updatePreferences { $0.backgroundTransparency = 0.4 }
        XCTAssertEqual(original, LauncherTile(model: model, item: item, index: 0, selected: false, action: {}))
        model.updatePreferences { $0.showNames.toggle() }
        XCTAssertNotEqual(original, LauncherTile(model: model, item: item, index: 0, selected: false, action: {}))
    }

    func testScanLimitAndFeedbackLifetime() async {
        let (model, _, cleanup) = fixture(); defer { cleanup() }
        XCTAssertFalse(model.requestRefresh(resetSearch: false, minimumInterval: 20))
        XCTAssertTrue(model.requestRefresh(resetSearch: false))
        await model.waitForCatalogRefresh()
        let orphan = WeakFeedbackReference(model.dragFeedback(for: "removed-folder"))
        XCTAssertNotNil(orphan.value)
        model.refresh()
        XCTAssertNil(orphan.value)
    }

    func testImportBypassesScanThrottle() async throws {
        let (baseModel, defaults, cleanup) = fixture(); defer { cleanup() }
        let root = baseModel.store.url.deletingLastPathComponent().appendingPathComponent("Apps")
        func install(_ name: String) throws {
            let contents = root.appendingPathComponent(name + ".app/Contents")
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            let info = ["CFBundlePackageType": "APPL", "CFBundleIdentifier": "test." + name, "CFBundleName": name]
            try PropertyListSerialization.data(fromPropertyList: info, format: .binary, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        }
        try install("first")
        let model = LauncherModel(catalog: AppCatalog(roots: [root], excludedRoots: []), store: baseModel.store, defaults: defaults)
        model.refresh()
        try install("second")
        XCTAssertFalse(model.requestRefresh(resetSearch: false, minimumInterval: 20))
        XCTAssertFalse(model.apps.contains { $0.id == "test.second" })
        try await model.ensureInventoryForImport()
        XCTAssertTrue(model.apps.contains { $0.id == "test.second" })
    }

    func testIconDeliveryDoesNotPublishModel() async throws {
        let (model, _, cleanup) = fixture(); defer { cleanup() }
        let feedback = model.dragFeedback(for: "app:sample")
        var modelChanges = 0; var tileChanges = 0
        let modelSubscription = model.objectWillChange.sink { modelChanges += 1 }
        let tileSubscription = feedback.objectWillChange.sink { tileChanges += 1 }
        let app = InstalledApp(id: "sample", name: "Sample", url: URL(fileURLWithPath: "/nonexistent-aplo-icon-test.app"), bundleIdentifier: "sample")
        let pending = model.icon(for: app, notifying: feedback)
        let source = DragSourceView()
        source.resolveIconResources = { (model.icon(for: app), []) }
        source.refreshIconResources()
        for _ in 0..<250 {
            if model.icon(for: app) !== pending { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(model.icon(for: app) === pending)
        XCTAssertEqual(modelChanges, 0)
        XCTAssertEqual(tileChanges, 1)
        source.refreshIconResources()
        XCTAssertTrue(source.icon === model.icon(for: app))
        XCTAssertFalse(source.icon === pending)
        withExtendedLifetime((modelSubscription, tileSubscription)) {}
    }
}
#endif
