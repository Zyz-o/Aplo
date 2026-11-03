import Foundation

enum AppCategory: String, CaseIterable {
    case productivity, communication, media, creative, development, internet, games, utilities, other, system
    var title: String {
        switch self {
        case .productivity: return "效率与办公"
        case .communication: return "社交与通讯"
        case .media: return "音乐与视频"
        case .creative: return "图像与设计"
        case .development: return "开发工具"
        case .internet: return "网络与浏览"
        case .games: return "游戏"
        case .utilities: return "实用工具"
        case .system: return "系统应用"
        case .other: return "其他"
        }
    }
}

enum AppClassifier {
    static func category(for app: InstalledApp) -> AppCategory {
        if app.isSystemApplication { return .system }
        let knownID = (app.bundleIdentifier ?? "").lowercased()
        // Several Electron applications declare generic developer metadata; correct known cases first.
        if ["com.bytedance.douyin", "com.bilibili.", "com.soda.music", "com.netease.163music", "com.lemon.lvpro"].contains(where: knownID.hasPrefix) { return .media }
        if knownID == "com.tencent.qq" || ["com.tencent.xinwechat", "com.tencent.foxmail", "com.apple.mail", "com.apple.facetime", "com.apple.ichat"].contains(where: knownID.hasPrefix) { return .communication }
        if ["com.apple.safari", "com.google.chrome", "org.mozilla.firefox", "io.github.clash-verge", "com.cpa.gui", "io.tailscale.", "com.tailscale."].contains(where: knownID.hasPrefix) { return .internet }
        if knownID.hasPrefix("com.anthropic.claude") { return .productivity }
        if ["com.baidu.baidunetdisk", "com.quark.clouddrive", "com.netease.uuremote"].contains(where: knownID.hasPrefix) { return .utilities }
        if let value = app.categoryIdentifier?.lowercased() {
            if value.contains("game") { return .games }
            if value.contains("developer") { return .development }
            if value.contains("social") { return .communication }
            if ["music", "video", "entertainment"].contains(where: value.contains) { return .media }
            if ["graphics", "photography", "design"].contains(where: value.contains) { return .creative }
            if ["productivity", "business", "education", "finance", "reference"].contains(where: value.contains) { return .productivity }
            if value.contains("utilities") { return .utilities }
        }
        let id = (app.bundleIdentifier ?? "").lowercased()
        let names = app.name.lowercased()
        if ["xcode", "vscode", "com.microsoft.vscode", "com.todesktop", "terminal", "scripteditor", "automator", "zcode"].contains(where: id.contains) { return .development }
        if ["safari", "chrome", "firefox", "browser", "clash", "easycliproxy"].contains(where: id.contains) { return .internet }
        if ["wechat", "xinwechat", "foxmail", "mail", "facetime", "ichat"].contains(where: id.contains) || id == "com.tencent.qq" { return .communication }
        if ["music", "bilibili", "douyin", "capcut", "jianying", "podcast", "quicktime", "tv"].contains(where: id.contains) { return .media }
        if ["photos", "preview", "imagecapture", "screenshot"].contains(where: id.contains) { return .creative }
        if ["notes", "reminders", "calendar", "wps", "pages", "numbers", "keynote", "chatgpt", "claude"].contains(where: id.contains) { return .productivity }
        if ["网盘", "远程", "cleaner", "magpie", "launchnext", "calculator"].contains(where: names.contains) { return .utilities }
        return .other
    }

    static func systemLast(_ items: [LayoutItem], appsByID: [String: InstalledApp]) -> [LayoutItem] {
        let isSystem: (LayoutItem) -> Bool = { item in
            if let id = item.appID { return appsByID[id]?.isSystemApplication == true }
            return !item.children.isEmpty && item.children.allSatisfy { appsByID[$0]?.isSystemApplication == true }
        }
        return items.filter { !isSystem($0) } + items.filter(isSystem)
    }

    static func layout(for apps: [InstalledApp]) -> LauncherLayout {
        let groups = Dictionary(grouping: apps, by: category)
        let folders = AppCategory.allCases.compactMap { category -> LayoutItem? in
            guard let members = groups[category], !members.isEmpty else { return nil }
            return LayoutItem(id: "category:" + category.rawValue, kind: .folder,
                              title: category.title, children: members.map(\.id))
        }
        return LauncherLayout(pages: [folders])
    }
}
