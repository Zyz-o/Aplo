import Carbon
import Foundation

struct ShortcutBinding: Codable, Equatable, Sendable {
    var keyCode: UInt32
    var modifiers: UInt32
    var keyName: String
    static let standard = ShortcutBinding(keyCode: 49, modifiers: UInt32(controlKey | optionKey), keyName: "空格")
    var displayName: String {
        [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")]
            .filter { modifiers & UInt32($0.0) != 0 }.map(\.1).joined() + keyName
    }
    var isValid: Bool {
        let allowed = UInt32(controlKey | optionKey | shiftKey | cmdKey)
        return keyCode < 128 && ![54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(keyCode)
            && modifiers & ~allowed == 0 && modifiers & UInt32(controlKey | optionKey | cmdKey) != 0
            && !keyName.isEmpty && keyName.count <= 20
    }
}

struct LayoutItem: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable { case app, folder }
    var id: String
    var kind: Kind
    var appID: String?
    var title: String?
    var children: [String]

    static func app(_ id: String) -> LayoutItem {
        LayoutItem(id: "app:" + id, kind: .app, appID: id, children: [])
    }
    static func folder(_ title: String = "新建文件夹", children: [String]) -> LayoutItem {
        LayoutItem(id: "folder:" + UUID().uuidString, kind: .folder, title: title, children: children)
    }
}

/// A nonrecursive snapshot keeps both display modes in the same atomic backup.
struct DisplayLayoutProfile: Codable, Equatable, Sendable {
    var pages: [[LayoutItem]]
    var freePositions: [String: FreeIconPosition]?
}

struct BackupPresentation: Codable, Equatable, Sendable {
    var fullscreen: LauncherArrangement
    var compact: LauncherArrangement
}

struct LauncherLayout: Codable, Equatable, Sendable {
    static let pageSize = 18
    var backupPresentation: BackupPresentation? = nil
    var otherDisplayLayout: DisplayLayoutProfile? = nil
    var activeLayoutIsFullscreen: Bool? = nil
    var freePositions: [String: FreeIconPosition]? = nil
    var version = 1
    var pages: [[LayoutItem]] = [[]]
    var shortcut: ShortcutBinding = .standard

    var allItems: [LayoutItem] { pages.flatMap { $0 } }
    var folders: [LayoutItem] { allItems.filter { $0.kind == .folder } }
    var appIDs: [String] { allItems.flatMap { $0.kind == .app ? [$0.appID].compactMap { $0 } : $0.children } }

    func removedAppIDs(from previous: LauncherLayout) -> Set<String> {
        func profiles(_ value: LauncherLayout) -> [Bool: Set<String>] {
            let active = value.activeLayoutIsFullscreen ?? false
            var result = [active: Set(value.appIDs)]
            if let other = value.otherDisplayLayout {
                result[!active] = Set(other.pages.flatMap { $0 }.flatMap { $0.kind == .app ? [$0.appID].compactMap { $0 } : $0.children })
            }
            return result
        }
        let current = profiles(self)
        return profiles(previous).reduce(into: Set<String>()) { removed, pair in
            removed.formUnion(pair.value.subtracting(current[pair.key] ?? []))
        }
    }

    var displayProfile: DisplayLayoutProfile { DisplayLayoutProfile(pages: pages, freePositions: freePositions) }
    mutating func prepareDisplayMode(fullscreen: Bool) {
        if let active = activeLayoutIsFullscreen {
            guard active != fullscreen else { return }
            let outgoing = displayProfile
            if let incoming = otherDisplayLayout {
                pages = incoming.pages; freePositions = incoming.freePositions
            } else { freePositions = nil }
            otherDisplayLayout = outgoing
        } else {
            // Legacy data is always the user's full-screen layout, including free positions.
            let original = displayProfile
            if fullscreen {
                otherDisplayLayout = DisplayLayoutProfile(pages: pages, freePositions: nil)
            } else {
                freePositions = nil
                otherDisplayLayout = original
            }
        }
        activeLayoutIsFullscreen = fullscreen
    }

    mutating func reconcile(with installedIDs: [String], preservingMissing: Bool = false) {
        if let profile = otherDisplayLayout {
            var other = LauncherLayout(freePositions: profile.freePositions, pages: profile.pages)
            other.reconcile(with: installedIDs, preservingMissing: preservingMissing)
            otherDisplayLayout = other.displayProfile
        }
        let installed = Set(installedIDs).union(preservingMissing ? appIDs : [])
        var seen = Set<String>()
        var seenFolders = Set<String>()
        var normalized: [[LayoutItem]] = []
        for page in pages {
            var items: [LayoutItem] = []
            for var item in page {
                if item.kind == .app {
                    guard let id = item.appID, installed.contains(id), seen.insert(id).inserted else { continue }
                    item = .app(id)
                } else {
                    guard seenFolders.insert(item.id).inserted else { continue }
                    item.children = item.children.filter { installed.contains($0) && seen.insert($0).inserted }
                    guard !item.children.isEmpty else { continue }
                    let name = (item.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    item.title = name.isEmpty ? "新建文件夹" : String(name.prefix(40))
                    item.appID = nil
                }
                items.append(item)
            }
            for start in stride(from: 0, to: items.count, by: Self.pageSize) {
                normalized.append(Array(items[start..<min(start + Self.pageSize, items.count)]))
            }
        }
        if normalized.isEmpty { normalized = [[]] }
        for id in installedIDs where seen.insert(id).inserted {
            if normalized[normalized.count - 1].count >= Self.pageSize { normalized.append([]) }
            normalized[normalized.count - 1].append(.app(id))
        }
        pages = normalized
        if !shortcut.isValid { shortcut = .standard }
    }

    mutating func remove(_ itemID: String) -> LayoutItem? {
        for pageIndex in pages.indices {
            if let index = pages[pageIndex].firstIndex(where: { $0.id == itemID }) {
                return pages[pageIndex].remove(at: index)
            }
            for index in pages[pageIndex].indices where pages[pageIndex][index].kind == .folder {
                if let childIndex = pages[pageIndex][index].children.firstIndex(where: { "app:" + $0 == itemID }) {
                    return .app(pages[pageIndex][index].children.remove(at: childIndex))
                }
            }
        }
        return nil
    }

    func validated() throws -> LauncherLayout {
        if let profile = otherDisplayLayout {
            _ = try LauncherLayout(freePositions: profile.freePositions, pages: profile.pages).validated()
        }
        if let positions = freePositions {
            guard positions.count <= 30_000, positions.allSatisfy({ $0.key.count < 8192 && $0.value.x.isFinite && $0.value.y.isFinite && (0...1).contains($0.value.x) && (0...1).contains($0.value.y) }) else { throw LayoutError.invalidBackup }
        }
        guard version == 1, shortcut.isValid, pages.count <= 500, allItems.count <= 10_000,
              allItems.allSatisfy({ item in
                  item.id.count <= 2048 && item.children.count <= 10_000
                    && (item.kind == .app ? item.appID != nil && item.children.isEmpty : item.id.hasPrefix("folder:") && item.appID == nil)
              }) else { throw LayoutError.invalidBackup }
        return self
    }
}

enum LayoutError: LocalizedError {
    case invalidBackup, tooLarge, invalidLegacy, noMatchingApps, inventoryUnavailable, database(String)
    var errorDescription: String? {
        switch self {
        case .inventoryUnavailable: return "应用扫描尚未完成或部分应用暂时无法读取，布局未改变。请稍后刷新重试。"
        case .invalidBackup: return "备份格式无效或版本不受支持，现有布局未改变。"
        case .tooLarge: return "文件过大，无法作为布局文件导入。"
        case .invalidLegacy: return "不是支持的旧版 Launchpad 数据库，现有布局未改变。"
        case .noMatchingApps: return "旧布局里没有匹配到本机已安装的软件，现有布局未改变。"
        case .database(let detail): return "无法读取旧布局：\(detail)"
        }
    }
}

struct LayoutStore: Sendable {
    static let maximumBytes = 5_000_000
    let url: URL
    static var standard: LayoutStore {
        LayoutStore(url: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/简启/layout.json"))
    }
    func load() throws -> LauncherLayout? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Self.read(url)
    }
    static func read(_ url: URL) throws -> LauncherLayout {
        let resolved = url.resolvingSymlinksInPath()
        let metadata = try resolved.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard metadata.isRegularFile == true else { throw LayoutError.invalidBackup }
        guard (metadata.fileSize ?? 0) <= maximumBytes else { throw LayoutError.tooLarge }
        let handle = try FileHandle(forReadingFrom: resolved)
        defer { try? handle.close() }
        var data = Data()
        while let chunk = try handle.read(upToCount: min(65_536, maximumBytes + 1 - data.count)), !chunk.isEmpty {
            try Task.checkCancellation()
            guard data.count + chunk.count <= maximumBytes else { throw LayoutError.tooLarge }
            data.append(chunk)
        }
        return try decode(data)
    }
    static func decode(_ data: Data) throws -> LauncherLayout {
        guard data.count <= maximumBytes else { throw LayoutError.tooLarge }
        do { return try JSONDecoder().decode(LauncherLayout.self, from: data).validated() }
        catch let error as LayoutError { throw error }
        catch { throw LayoutError.invalidBackup }
    }
    static func encode(_ layout: LauncherLayout, prettyPrinted: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        let data = try encoder.encode(layout)
        guard data.count <= maximumBytes else { throw LayoutError.tooLarge }
        return data
    }
    func save(_ layout: LauncherLayout) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encode(layout, prettyPrinted: false).write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    @discardableResult
    func archiveCurrent() throws -> URL? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let directory = url.deletingLastPathComponent().appendingPathComponent("Backups")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let date = DateFormatter()
        date.dateFormat = "yyyyMMdd-HHmmss"
        let target = directory.appendingPathComponent("Aplo-\(date.string(from: Date()))-\(UUID().uuidString.prefix(6)).json")
        try FileManager.default.copyItem(at: url, to: target)
        return target
    }
}
