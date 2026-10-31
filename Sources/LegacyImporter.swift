import Foundation
import SQLite3

struct LegacyImportResult: Sendable {
    var layout: LauncherLayout
    var matchedCount: Int
    var skippedCount: Int
}

/// Shared between the UI cancellation handler and bounded background file/process reads.
final class LegacyReadControl: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var process: Process?
    private let deadline: Date
    init(timeout: TimeInterval = 30) { deadline = Date().addingTimeInterval(timeout) }
    var remaining: TimeInterval { max(0, deadline.timeIntervalSinceNow) }
    var shouldStop: Bool {
        lock.lock(); let value = cancelled; lock.unlock()
        return value || remaining <= 0
    }
    func check() throws {
        try Task.checkCancellation()
        lock.lock(); let value = cancelled; lock.unlock()
        if value { throw CancellationError() }
        if remaining <= 0 { throw LayoutError.database("读取超时，现有布局未改变。") }
    }
    func attach(_ value: Process) {
        lock.lock(); process = value; let stop = cancelled; lock.unlock()
        if (stop || remaining <= 0) && value.isRunning { value.terminate() }
    }
    func detach() { lock.lock(); process = nil; lock.unlock() }
    func cancel() {
        lock.lock(); cancelled = true; let value = process; lock.unlock()
        if let value, value.isRunning { value.terminate() }
    }
    func terminateIfExpired() {
        lock.lock(); let value = process; lock.unlock()
        if remaining <= 0, let value, value.isRunning { value.terminate() }
    }
}

enum LegacyImporter {
    // Read-only support for the historical items/apps/groups Launchpad schema.
    // The source database is never migrated or rewritten.
    static func read(_ url: URL, apps: [InstalledApp], control: LegacyReadControl = LegacyReadControl()) throws -> LegacyImportResult {
        try control.check()
        let size = (try url.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
        guard size <= 50_000_000 else { throw LayoutError.tooLarge }
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK,
              let database else {
            if let database { sqlite3_close(database) }
            throw LayoutError.database("文件无法打开或没有读取权限。")
        }
        defer { sqlite3_progress_handler(database, 0, nil, nil); sqlite3_close(database) }
        sqlite3_progress_handler(database, 1000, { context in
            guard let context else { return 0 }
            return Unmanaged<LegacyReadControl>.fromOpaque(context).takeUnretainedValue().shouldStop ? 1 : 0
        }, Unmanaged.passUnretained(control).toOpaque())
        sqlite3_busy_timeout(database, 500)
        sqlite3_exec(database, "PRAGMA query_only=ON; PRAGMA trusted_schema=OFF;", nil, nil, nil)
        var tables: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('items','apps','groups')", -1, &tables, nil) == SQLITE_OK,
              let tables else { throw LayoutError.invalidLegacy }
        var tableNames = Set<String>()
        while sqlite3_step(tables) == SQLITE_ROW {
            if let value = sqlite3_column_text(tables, 0) { tableNames.insert(String(cString: value)) }
        }
        sqlite3_finalize(tables)
        try control.check()
        guard tableNames == ["items", "apps", "groups"] else { throw LayoutError.invalidLegacy }

        struct Row {
            let id: Int64
            let parent: Int64
            let order: Int64
            let type: Int
            let uuid: String
            let bundle: String?
            let folderTitle: String?
        }
        let sql = """
            SELECT i.rowid, i.parent_id, i.ordering, i.type, i.uuid, a.bundleid, g.title
            FROM items i LEFT JOIN apps a ON a.item_id=i.rowid
            LEFT JOIN groups g ON g.item_id=i.rowid
            ORDER BY i.parent_id, i.ordering, i.rowid LIMIT 100001
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw LayoutError.invalidLegacy }
        defer { sqlite3_finalize(statement) }
        var rows: [Row] = []
        func string(_ column: Int32) -> String? {
            guard let text = sqlite3_column_text(statement, column) else { return nil }
            return String(cString: text)
        }
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            rows.append(Row(id: sqlite3_column_int64(statement, 0), parent: sqlite3_column_int64(statement, 1),
                            order: sqlite3_column_int64(statement, 2), type: Int(sqlite3_column_int(statement, 3)),
                            uuid: string(4) ?? "", bundle: string(5), folderTitle: string(6)))
            status = sqlite3_step(statement)
        }
        try control.check()
        guard status == SQLITE_DONE else { throw LayoutError.database("数据库不完整或被其他程序占用。") }
        guard rows.count <= 100_000, let root = rows.first(where: { $0.uuid == "ROOTPAGE" }) else {
            throw LayoutError.invalidLegacy
        }
        let children = Dictionary(grouping: rows, by: \.parent)
        let installed = Dictionary(apps.compactMap { app in app.bundleIdentifier.map { ($0, app.id) } },
                                   uniquingKeysWith: { first, _ in first })
        var used = Set<String>()
        var skipped = 0

        func descendants(_ row: Row, visited: Set<Int64> = []) -> [String] {
            guard visited.count < 12, !visited.contains(row.id) else { return [] }
            if let bundle = row.bundle {
                guard let id = installed[bundle], used.insert(id).inserted else {
                    if installed[bundle] == nil { skipped += 1 }
                    return []
                }
                return [id]
            }
            var visited = visited
            visited.insert(row.id)
            return (children[row.id] ?? []).flatMap { descendants($0, visited: visited) }
        }
        func item(_ row: Row) -> LayoutItem? {
            if row.bundle != nil {
                return descendants(row).first.map { .app($0) }
            }
            guard row.type == 2, let title = row.folderTitle else { return nil }
            let members = descendants(row)
            return members.isEmpty ? nil : .folder(title, children: members)
        }
        let pages = (children[root.id] ?? []).filter { $0.type == 3 && !$0.uuid.hasPrefix("HOLDINGPAGE") }
        guard !pages.isEmpty else { throw LayoutError.invalidLegacy }
        var layout = LauncherLayout(pages: pages.map { page in (children[page.id] ?? []).compactMap(item) })
        guard !used.isEmpty else { throw LayoutError.noMatchingApps }
        try control.check()
        let matched = used.count
        layout.reconcile(with: apps.map(\.id))
        return LegacyImportResult(layout: layout, matchedCount: matched, skippedCount: skipped)
    }
}
