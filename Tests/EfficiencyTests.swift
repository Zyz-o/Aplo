#if SWIFT_PACKAGE
import XCTest
@testable import Aplo

final class EfficiencyTests: XCTestCase {
    func testIconRasterMatchesRetinaScaleAndMagnification() {
        XCTAssertEqual(IconRaster.pixelSize(points: 60, scale: 2), 192)
        XCTAssertEqual(IconRaster.pixelSize(points: 117, scale: 2), 384)
        XCTAssertEqual(IconRaster.pixelSize(points: 117, scale: 3), 512)
    }
    func testBoundedArithmeticAndNoEvaluationOfCode() {
        XCTAssertEqual(Arithmetic.evaluate("2+3*4"), 14)
        XCTAssertEqual(Arithmetic.evaluate("(2+3)×4"), 20)
        XCTAssertEqual(Arithmetic.evaluate("-2^2"), -4)
        XCTAssertEqual(Arithmetic.evaluate("2^3^2"), 512)
        XCTAssertEqual(Arithmetic.evaluate("7%4"), 3)
        for invalid in ["1/0", "0%0", "2^9999", "1..2", "2(3)", "$(touch /tmp/no)", "sin(1)", String(repeating: "(", count: 40) + "1" + String(repeating: ")", count: 40), String(repeating: "1+", count: 150)] {
            XCTAssertNil(Arithmetic.evaluate(invalid), invalid)
        }
    }
    func testInlineCommandsAreParsedWithoutRunningThem() {
        XCTAssertEqual(InlineResult.parse("= 2 + 2"), .calculation("4"))
        XCTAssertEqual(InlineResult.parse("2÷4"), .calculation("0.5"))
        XCTAssertEqual(InlineResult.parse(" /sleep "), .command(.sleep))
        XCTAssertEqual(InlineResult.parse("trash"), .command(.trash))
        XCTAssertEqual(InlineResult.parse("LOCK"), .command(.lock))
        for query in ["Chrome", "C++", "sleep now", "trash; rm -rf", "123", "=1/0"] { XCTAssertNil(InlineResult.parse(query)) }
    }
    func testAutoHideMigrationPreservesOldChoice() throws {
        let escape = try JSONDecoder().decode(LauncherPreferences.self, from: Data(#"{"dismissStyle":"escapeOnly"}"#.utf8))
        XCTAssertFalse(escape.launchAutoHide)
        let original = LauncherPreferences()
        XCTAssertTrue(original.launchAutoHide)
        var changed = escape; changed.launchAutoHide = true
        XCTAssertEqual(try JSONDecoder().decode(LauncherPreferences.self, from: JSONEncoder().encode(changed)), changed)
    }
    func testLocalizedReleaseSummaryHasSeparateDeveloperDetails() {
        let notes = ReleaseNote.parse("# 3.14.0 — date\n\n- Developer details\n\n<!-- summary-zh -->\n修复与改进\n")
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes.first?.summary(language: .chinese), "修复与改进")
        XCTAssertEqual(notes.first?.developerDetails, "- Developer details")
    }
    @MainActor func testDirectoryWatcherRefreshesAndStops() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var notifications = 0
        let watcher = ApplicationWatcher(paths: [root.path]) { notifications += 1 }
        defer { watcher.stop() }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Added.app"), withIntermediateDirectories: true)
        for _ in 0..<150 {
            if notifications > 0 { break }
            try await Task.sleep(for: .milliseconds(40))
        }
        XCTAssertGreaterThan(notifications, 0)
        watcher.stop()
        let stoppedCount = notifications
        try Data("test".utf8).write(to: root.appendingPathComponent("AfterStop.app"))
        try await Task.sleep(for: .milliseconds(1200))
        XCTAssertEqual(notifications, stoppedCount)
    }
    func testBlankBundleNameDoesNotCrash() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let contents = root.appendingPathComponent("   .app/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info = ["CFBundlePackageType": "APPL", "CFBundleIdentifier": "test.blank", "CFBundleName": "  ", "CFBundleDisplayName": "\n"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
        let apps = AppCatalog(roots: [root], excludedRoots: []).snapshot().apps
        XCTAssertEqual(apps.first?.name, "test.blank")
    }
}
#endif
