import Foundation

@main struct SearchBenchmark {
    @MainActor static func main() throws {
        let synthetic = (0..<300).map { InstalledApp(id: "test.\($0)", name: "微信备忘录浏览器 \($0)", url: URL(fileURLWithPath: "/test\($0).app"), bundleIdentifier: nil, searchAliases: ["WeChat Notes Browser \($0)"]) }
        let live = AppCatalog(includeSystemApplications: true).scan()
        var report: [[String: Any]] = []
        var checksum = 0
        for (name, apps) in [("installed", live), ("synthetic", synthetic)] {
            var cold: [Double] = [], warm: [Double] = [], keys: [Double] = []
            for _ in 0..<5 {
                let index = IntegratedSearch()
                var start = ProcessInfo.processInfo.systemUptime
                index.update(apps)
                cold.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
                start = ProcessInfo.processInfo.systemUptime
                index.update(apps)
                warm.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
                for i in 0..<100 {
                    start = ProcessInfo.processInfo.systemUptime
                    checksum += index.matching(apps, query: ["wx", "chrome", "wechat", "微信", "备忘录", "Notes", "不存在", "浏览器"][i % 8]).count
                    keys.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
                }
            }
            func percentile(_ data: [Double], _ p: Double) -> Double { let d = data.sorted(); return d[min(d.count - 1, Int(Double(d.count - 1) * p))] }
            report.append(["dataset": name, "apps": apps.count, "indexColdMedianMs": percentile(cold, 0.5), "indexWarmMedianMs": percentile(warm, 0.5), "queryMedianMs": percentile(keys, 0.5), "queryP95Ms": percentile(keys, 0.95), "queryMaxMs": keys.max()!])
        }
        let json: [String: Any] = ["configuration": "swiftc -O; MainActor; 5 fresh indices, 500 queries per dataset", "measurements": report, "checksum": checksum]
        print(String(data: try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!)
    }
}
