import AppKit
import Foundation

/// Uses the same unscaled tile rectangles as the free canvas, including custom positions.
enum SpatialNavigation {
    static func neighbor(from index: Int, frames: [CGRect], direction: CGPoint) -> Int {
        guard frames.indices.contains(index) else { return index }
        let origin = CGPoint(x: frames[index].midX, y: frames[index].midY)
        return frames.indices.filter { $0 != index }.compactMap { candidate -> (Int, CGFloat)? in
            let dx = frames[candidate].midX - origin.x, dy = frames[candidate].midY - origin.y
            let forward = dx * direction.x + dy * direction.y
            guard forward > 0.5 else { return nil }
            let cross = abs(dx * direction.y - dy * direction.x)
            return (candidate, hypot(dx, dy) * (1 + cross / forward))
        }.min { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 < $1.1 }?.0 ?? index
    }
}

struct OrganizationState: Equatable {
    var layout: LauncherLayout
    var hiddenAppIDs: Set<String>
    var arrangement: LauncherArrangement
    var compactArrangement: LauncherArrangement?
    var automaticCategories: Bool
}

struct LayoutBackupRecord: Identifiable, Equatable, Sendable {
    let url: URL
    let date: Date
    let bytes: Int
    var id: String { url.lastPathComponent }
    var automatic: Bool {
        id.range(of: #"^Aplo-(?:[0-9]{8}-[0-9]{6}-[A-Fa-f0-9]{6}|before-upgrade-[A-Fa-f0-9]{12})\.json$"#, options: .regularExpression) != nil
    }
}

extension LayoutStore {
    func history() throws -> [LayoutBackupRecord] {
        let directory = url.deletingLastPathComponent().appendingPathComponent("Backups")
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let timestamp = DateFormatter()
        timestamp.locale = Locale(identifier: "en_US_POSIX")
        timestamp.dateFormat = "yyyyMMdd-HHmmss"
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey, .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
            .filter { $0.pathExtension.lowercased() == "json" }.compactMap { file in
                let values = try file.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey, .fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else { return nil }
                // copyItem preserves the layout's mtime; the archive filename records capture time.
                let captured = file.lastPathComponent.range(of: #"^Aplo-[0-9]{8}-[0-9]{6}-"#, options: .regularExpression) == nil
                    ? nil : timestamp.date(from: String(file.lastPathComponent.dropFirst(5).prefix(15)))
                return LayoutBackupRecord(url: file, date: captured ?? values.creationDate ?? values.contentModificationDate ?? .distantPast, bytes: values.fileSize ?? 0)
            }.sorted { $0.date == $1.date ? $0.id > $1.id : $0.date > $1.date }
    }
    func saveManualBackup(_ data: Data) throws {
        _ = try Self.decode(data)
        let directory = url.deletingLastPathComponent().appendingPathComponent("Backups")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent("Aplo-manual-" + UUID().uuidString + ".json")
        try data.write(to: target, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
    }
    func automaticHistoryToClean(keeping count: Int = 20) throws -> [LayoutBackupRecord] {
        Array(try history().filter(\.automatic).dropFirst(max(1, count)))
    }
}

struct ReleaseNote: Identifiable, Sendable {
    let title: String
    let body: String
    var id: String { title }
    static func parse(_ text: String) -> [ReleaseNote] {
        text.components(separatedBy: "\n# ").enumerated().compactMap { index, section in
            let section = index == 0 && section.hasPrefix("# ") ? String(section.dropFirst(2)) : section
            guard let newline = section.firstIndex(of: "\n") else { return nil }
            let title = String(section[..<newline]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard title.first?.isNumber == true else { return nil }
            return ReleaseNote(title: title, body: String(section[newline...]).trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
    static let bundled: [ReleaseNote] = {
        guard let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"), let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return parse(text)
    }()
}
