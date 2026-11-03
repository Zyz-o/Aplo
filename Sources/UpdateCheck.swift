import Foundation
import SwiftUI

enum UpdateCheck {
    struct Release: Decodable {
        struct Asset: Decodable { let name: String; let state: String }
        let tag_name: String
        let draft: Bool
        let prerelease: Bool
        let body: String?
        let assets: [Asset]
        var downloadPage: URL? {
            guard UpdateCheck.version(tag_name) != nil else { return nil }
            return URL(string: "https://github.com/Zyz-o/Aplo/releases/tag/" + tag_name)
        }
    }

    static func version(_ tag: String) -> [Int]? {
        let parts = (tag.hasPrefix("v") ? String(tag.dropFirst()) : tag).split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }) else { return nil }
        let values = parts.compactMap { Int($0) }
        return values.count == 3 ? values : nil
    }

    static func newest(in data: Data) throws -> Release {
        let releases = try JSONDecoder().decode([Release].self, from: data)
        guard let release = releases.compactMap({ release -> (Release, [Int])? in
            guard !release.draft, let number = version(release.tag_name),
                  release.assets.contains(where: { $0.state == "uploaded" && $0.name == "Aplo-\(number.map(String.init).joined(separator: ".") )-macOS-arm64.zip" }) else { return nil }
            return (release, number)
        }).max(by: { $0.1.lexicographicallyPrecedes($1.1) })?.0 else { throw URLError(.resourceUnavailable) }
        return release
    }

    static func fetch() async throws -> Release {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 20
        config.urlCache = nil
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/Zyz-o/Aplo/releases?per_page=30")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try newest(in: data)
    }
}

struct UpdateCheckView: View {
    let model: LauncherModel
    let version: String
    @State private var checking = false
    @State private var failed = false
    @State private var latest: UpdateCheck.Release?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button(model.text("检查更新")) { Task { await check() } }.disabled(checking)
                if checking { ProgressView().controlSize(.small) }
            }
            Text(model.text("仅在点击时联网，不会自动下载或安装。")).foregroundStyle(.secondary)
            if failed { Text(model.text("暂时无法检查更新，请稍后重试。")).foregroundStyle(.secondary) }
            if let latest, let remote = UpdateCheck.version(latest.tag_name), let local = UpdateCheck.version(version) {
                if local.lexicographicallyPrecedes(remote) {
                    HStack {
                        Text(model.text(latest.prerelease ? "发现新预览版" : "发现新版本") + " · " + latest.tag_name).fontWeight(.semibold)
                        Spacer()
                        if let url = latest.downloadPage { Link(model.text("前往 GitHub 下载"), destination: url) }
                    }
                    if let body = latest.body, !body.isEmpty {
                        let parts = body.components(separatedBy: "<!-- summary-zh -->")
                        Text(verbatim: String((model.preferences.language.isEnglish ? parts.first : parts.last)?.prefix(4500) ?? "")).textSelection(.enabled)
                    }
                } else { Text(model.text("当前没有可用的新版。")) }
            }
        }
    }
    private func check() async {
        guard !checking else { return }
        checking = true; failed = false; latest = nil
        defer { checking = false }
        do { latest = try await UpdateCheck.fetch() }
        catch { failed = true }
    }
}
