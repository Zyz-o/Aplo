#if SWIFT_PACKAGE
@testable import Aplo
#endif
import Foundation

#if !SWIFT_PACKAGE
@main
#endif
 struct SearchTests {
    @MainActor static func main() {
        let apps = ["微信", "Google Chrome", "Weixin Tools", "WPS Office", "百度网盘"].enumerated().map {
            InstalledApp(id: "test.\($0.offset)", name: $0.element,
                         url: URL(fileURLWithPath: "/tmp/\($0.offset).app"), bundleIdentifier: nil)
        }
        let search = IntegratedSearch()
        search.update(apps)
        func expect(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            print("PASS: \(message)")
        }
        func names(_ query: String) -> [String] { search.matching(apps, query: query).map(\.name) }
        expect(names("微信").first == "微信", "Chinese original name matches")
        expect(names("weixin").contains("微信"), "full pinyin finds WeChat")
        expect(names("wx").contains("微信"), "pinyin initials find WeChat")
        expect(names("bdwp").contains("百度网盘"), "four-character pinyin initials match")
        expect(names("gc").first == "Google Chrome", "English initials find Chrome")
        expect(names("gchr").first == "Google Chrome", "non-contiguous letters find Chrome")
        expect(names("CHROME").first == "Google Chrome", "English matches ignore case")
        expect(names("Weixin").first == "Weixin Tools", "original names rank above transliterations")
        expect(names(" ") == apps.map(\.name), "empty search retains inventory order")
        expect(names("zzzzzz").isEmpty, "unmatched query returns no application")
        search.update(Array(apps.dropFirst()))
        expect(!search.matching(apps, query: "wx").contains(where: { $0.name == "微信" }), "removed names leave the search index")
        expect(names("百度網盤").contains("百度网盘"), "Traditional query finds a Simplified application name")
        let traditionalApp = InstalledApp(id: "traditional", name: "備忘錄", url: URL(fileURLWithPath: "/tmp/Traditional.app"), bundleIdentifier: nil)
        search.update([traditionalApp])
        expect(search.matching([traditionalApp], query: "备忘录").first?.id == "traditional", "Simplified query finds a Traditional application name")
        let nativeApp = InstalledApp(id: "activity", name: "活动监视器", url: URL(fileURLWithPath: "/tmp/Activity Monitor.app"), bundleIdentifier: "com.apple.ActivityMonitor", searchAliases: ["Activity Monitor"])
        search.update([nativeApp])
        expect(search.matching([nativeApp], query: "Activity Monitor").first?.id == "activity", "English original names find translated system applications")
        expect(search.matching([nativeApp], query: "huodong").first?.id == "activity", "translated system application names support pinyin search")
        expect(search.matching([nativeApp], query: "活动").count == 1, "localized-name and alias matches do not duplicate an application")
        print("All 16 integrated LaunchNext search checks passed.")
    }
}
