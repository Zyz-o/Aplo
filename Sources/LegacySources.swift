import Darwin
import Foundation

enum LegacySources {
    static func discover() -> [URL] {
        let length = confstr(_CS_DARWIN_USER_DIR, nil, 0)
        var candidates: [URL] = []
        if length > 0 && length < 16_384 {
            var buffer = [CChar](repeating: 0, count: length)
            _ = confstr(_CS_DARWIN_USER_DIR, &buffer, buffer.count)
            let directory = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            candidates.append(URL(fileURLWithPath: directory, isDirectory: true)
                .appendingPathComponent("com.apple.dock.launchpad/db/db"))
        }
        let oldDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Dock", isDirectory: true)
        let oldFiles = (try? FileManager.default.contentsOfDirectory(at: oldDirectory,
            includingPropertiesForKeys: [.isRegularFileKey])) ?? []
        candidates += oldFiles.filter { $0.pathExtension.lowercased() == "db" }
        var seen = Set<String>()
        return candidates.filter {
            FileManager.default.fileExists(atPath: $0.path)
                && seen.insert($0.resolvingSymlinksInPath().path).inserted
        }
    }

    static func read(_ url: URL, apps: [InstalledApp], control: LegacyReadControl = LegacyReadControl()) throws -> LegacyImportResult {
        try control.check()
        guard ["zip", "lmy"].contains(url.pathExtension.lowercased()) else {
            return try LegacyImporter.read(url, apps: apps, control: control)
        }
        let archiveSize = (try url.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
        guard archiveSize <= 100_000_000 else { throw LayoutError.tooLarge }
        let listing = try unzip(arguments: ["-Z1", url.path], maximumBytes: 1_000_000, control: control)
        guard let text = String(data: listing, encoding: .utf8) else { throw LayoutError.invalidLegacy }
        let entries = text.split(separator: "\n").map(String.init)
        guard entries.count <= 10_000 else { throw LayoutError.tooLarge }
        let databases = entries.filter { entry in
            let name = (entry as NSString).lastPathComponent
            return safeEntry(entry) && !entry.hasPrefix("__MACOSX/") && !name.hasPrefix("._")
                && (name == "db" || name.lowercased().hasSuffix(".db"))
        }
        let entry: String
        if databases.contains("db") { entry = "db" }
        else if databases.count == 1 { entry = databases[0] }
        else {
            throw LayoutError.database(databases.isEmpty
                ? "归档中没有旧版 db 数据库，请选择其他备份。"
                : "归档中有多个数据库，请先解压并选择要导入的 db 文件。")
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("JianqiLegacy-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = directory.appendingPathComponent("db")
        try unzip(arguments: ["-p", url.path, entry], maximumBytes: 50_000_000, control: control).write(to: database)
        // Extract only the selected database and its matching SQLite sidecars.
        // Archive paths are never used as output paths.
        for suffix in ["-wal", "-shm"] where entries.contains(entry + suffix) {
            try unzip(arguments: ["-p", url.path, entry + suffix], maximumBytes: 50_000_000, control: control)
                .write(to: directory.appendingPathComponent("db" + suffix))
        }
        return try LegacyImporter.read(database, apps: apps, control: control)
    }

    private static func safeEntry(_ entry: String) -> Bool {
        !entry.isEmpty && !entry.hasPrefix("/") && !entry.hasPrefix("-")
            && !entry.split(separator: "/").contains("..")
            && !entry.contains(where: { "*?[]\\\0\r".contains($0) })
            && !entry.hasSuffix("/")
    }

    private static func unzip(arguments: [String], maximumBytes: Int, control: LegacyReadControl) throws -> Data {
        try control.check()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle(forReadingAtPath: "/dev/null")
        do { try process.run() }
        catch { throw LayoutError.database("无法使用系统归档读取工具。") }
        control.attach(process)
        let timeout = DispatchWorkItem { control.terminateIfExpired() }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + control.remaining, execute: timeout)
        defer { timeout.cancel(); control.detach() }
        var result = Data()
        do {
            while let chunk = try output.fileHandleForReading.read(upToCount: 65_536), !chunk.isEmpty {
                try control.check()
                guard result.count + chunk.count <= maximumBytes else {
                    if process.isRunning { process.terminate() }
                    process.waitUntilExit()
                    throw LayoutError.tooLarge
                }
                result.append(chunk)
            }
        } catch {
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
            throw error
        }
        process.waitUntilExit()
        try control.check()
        guard process.terminationStatus == 0 else {
            throw LayoutError.database("归档损坏、加密或格式不受支持；请先解压后选择数据库。")
        }
        return result
    }
}
