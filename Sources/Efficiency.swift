import AppKit
import SwiftUI

/// No expression evaluator, shell expansion or side effects while the user types.
enum InlineResult: Equatable {
    case calculation(String)
    case command(SystemCommand)
    static func parse(_ text: String) -> InlineResult? {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let command = SystemCommand(rawValue: input.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))) { return .command(command) }
        let explicit = input.hasPrefix("=")
        let expression = explicit ? String(input.dropFirst()) : input
        guard explicit || (expression.contains(where: { "+-*/×÷^%".contains($0) }) && expression.contains(where: \.isNumber)),
              let value = Arithmetic.evaluate(expression) else { return nil }
        return .calculation(value.formatted(.number.locale(Locale(identifier: "en_US_POSIX")).grouping(.never).precision(.significantDigits(1...14))))
    }
}
enum SystemCommand: String, CaseIterable, Sendable {
    case lock, sleep, trash
    var title: String {
        switch self { case .lock: "锁屏"; case .sleep: "休眠"; case .trash: "清空本机废纸篓" }
    }
    var explanation: String {
        switch self {
        case .lock: "锁定当前登录会话。若系统没有受支持的锁屏工具，请按 Control＋Command＋Q。"
        case .sleep: "让这台 Mac 进入休眠；正在进行的任务可能暂停。"
        case .trash: "永久删除当前用户 ~/.Trash 内的全部项目，无法撤销。不处理外置磁盘废纸篓。"
        }
    }
    static let lockTool = "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession"
    var available: Bool { self != .lock || FileManager.default.isExecutableFile(atPath: Self.lockTool) }
}

enum Arithmetic {
    static func evaluate(_ source: String) -> Double? {
        guard source.count <= 256 else { return nil }
        var parser = Parser(characters: Array(source.replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "÷", with: "/").filter { !$0.isWhitespace }))
        guard let result = parser.expression(), parser.index == parser.characters.count, result.isFinite else { return nil }
        return result == 0 ? 0 : result
    }
    private struct Parser {
        let characters: [Character]
        var index = 0
        var depth = 0
        mutating func take(_ character: Character) -> Bool {
            guard index < characters.count, characters[index] == character else { return false }
            index += 1; return true
        }
        mutating func expression() -> Double? {
            guard var value = term() else { return nil }
            while index < characters.count {
                if take("+") { guard let right = term() else { return nil }; value += right }
                else if take("-") { guard let right = term() else { return nil }; value -= right }
                else { break }
            }
            return value.isFinite ? value : nil
        }
        mutating func term() -> Double? {
            guard var value = unary() else { return nil }
            while index < characters.count {
                if take("*") { guard let right = unary() else { return nil }; value *= right }
                else if take("/") { guard let right = unary(), right != 0 else { return nil }; value /= right }
                else if take("%") { guard let right = unary(), right != 0 else { return nil }; value = value.truncatingRemainder(dividingBy: right) }
                else { break }
            }
            return value.isFinite ? value : nil
        }
        mutating func unary() -> Double? {
            depth += 1; defer { depth -= 1 }
            guard depth <= 32 else { return nil }
            if take("+") { return unary() }
            if take("-") { return unary().map { -$0 } }
            guard var value = primary() else { return nil }
            if take("^") { guard let exponent = unary() else { return nil }; value = pow(value, exponent) }
            return value.isFinite ? value : nil
        }
        mutating func primary() -> Double? {
            if take("(") { guard let value = expression(), take(")") else { return nil }; return value }
            let start = index
            while index < characters.count, characters[index].isNumber || characters[index] == "." { index += 1 }
            guard index > start else { return nil }
            return Double(String(characters[start..<index]))
        }
    }
}

struct ApplicationDetails: Sendable {
    var version: String
    var architecture: String
    var bytes: Int64
    var sizeIncomplete: Bool
    static func read(_ app: InstalledApp) throws -> ApplicationDetails {
        try Task.checkCancellation()
        let plist = app.url.appendingPathComponent("Contents/Info.plist")
        let handle = try FileHandle(forReadingFrom: plist); defer { try? handle.close() }
        let data = try handle.read(upToCount: 4_000_001) ?? Data()
        guard data.count <= 4_000_000,
              let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { throw CocoaError(.fileReadCorruptFile) }
        let version = info["CFBundleShortVersionString"] as? String ?? info["CFBundleVersion"] as? String ?? "—"
        var architecture = "—"
        if let executable = info["CFBundleExecutable"] as? String, executable == URL(fileURLWithPath: executable).lastPathComponent {
            let binary = app.url.appendingPathComponent("Contents/MacOS").appendingPathComponent(executable)
            if FileManager.default.isExecutableFile(atPath: binary.path) {
                // lipo reads Mach-O headers only. Arguments are passed directly, never through a shell.
                let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/lipo")
                process.arguments = ["-archs", binary.path]
                let output = Pipe(); process.standardOutput = output; process.standardError = FileHandle.nullDevice
                try process.run()
                let data = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
                if process.terminationStatus == 0 { architecture = String(decoding: data.prefix(4096), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) }
            }
        }
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        var complete = true, bytes: Int64 = 0, count = 0
        let started = ProcessInfo.processInfo.systemUptime
        if let files = FileManager.default.enumerator(at: app.url, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, _ in complete = false; return false }) {
            while let file = files.nextObject() as? URL {
                try Task.checkCancellation(); count += 1
                if count > 200_000 || ProcessInfo.processInfo.systemUptime - started > 3 { complete = false; break }
                do {
                    let values = try file.resourceValues(forKeys: keys)
                    if values.isSymbolicLink == true { files.skipDescendants(); continue }
                    if values.isRegularFile == true {
                        let sum = bytes.addingReportingOverflow(Int64(values.fileSize ?? 0))
                        if sum.overflow { complete = false; break }; bytes = sum.partialValue
                    }
                } catch { complete = false }
            }
        } else { complete = false }
        return ApplicationDetails(version: version, architecture: architecture, bytes: bytes, sizeIncomplete: !complete)
    }
}

struct ApplicationInspector: View {
    let model: LauncherModel
    let app: InstalledApp
    @Environment(\.dismiss) private var dismiss
    @State private var details: ApplicationDetails?
    @State private var failure: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                PreviewAppIcon(model: model, app: app).frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) { Text(app.name).font(.title2.bold()); Text(model.text("应用速览")).foregroundStyle(.secondary) }
            }
            if let details {
                LabeledContent(model.text("版本"), value: details.version)
                LabeledContent(model.text("架构"), value: details.architecture)
                LabeledContent(model.text("体积"), value: (details.sizeIncomplete ? "≥ " : "") + ByteCountFormatter.string(fromByteCount: details.bytes, countStyle: .file))
                Text(model.text("体积为应用包内文件大小之和，不包含个人数据；符号链接不重复计算。"))
                    .font(.caption).foregroundStyle(.secondary)
            } else if let failure { Text(failure).foregroundStyle(.secondary) }
            else { ProgressView() }
            Text(app.url.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            HStack { Button(model.text("在访达中显示")) { NSWorkspace.shared.activateFileViewerSelecting([app.url]) }; Spacer(); Button(model.text("关闭")) { dismiss() }.keyboardShortcut(.cancelAction) }
        }.padding(24).frame(width: 480, alignment: .leading)
        .task(id: app.id) {
            let worker = Task.detached(priority: .utility) { try ApplicationDetails.read(app) }
            do { details = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() }) }
            catch is CancellationError {} catch { failure = error.localizedDescription }
        }
    }
}

struct InlineResultView: View {
    let model: LauncherModel
    let result: InlineResult
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.title2).foregroundStyle(model.accentColor)
            VStack(alignment: .leading, spacing: 4) {
                switch result {
                case .calculation(let value): Text("= " + value).font(.title2.monospacedDigit()); Text(model.text("回车或点击拷贝结果")).font(.caption).foregroundStyle(.secondary)
                case .command(let command): Text(model.text(command.title)).font(.headline); Text(model.text(command.explanation)).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(model.text(buttonTitle)) { model.performInlineResult(result) }
        }.padding(16).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14)).padding(.bottom, 12)
    }
    private var symbol: String { if case .calculation = result { return "equal.square" }; return "terminal" }
    private var buttonTitle: String { if case .calculation = result { return "拷贝结果" }; return "继续…" }
}

enum ConfirmedSystemActions {
    static func run(_ command: SystemCommand) throws {
        guard command.available else { throw CocoaError(.featureUnsupported) }
        if command == .trash {
            let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash", isDirectory: true)
            let attributes = try FileManager.default.attributesOfItem(atPath: trash.path)
            guard attributes[.type] as? FileAttributeType == .typeDirectory,
                  (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else { throw CocoaError(.fileWriteNoPermission) }
            for item in try FileManager.default.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil) {
                try FileManager.default.removeItem(at: item)
            }
        } else {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: command == .lock ? SystemCommand.lockTool : "/usr/bin/pmset")
            process.arguments = command == .lock ? ["-suspend"] : ["sleepnow"]
            process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
            try process.run(); process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw CocoaError(.featureUnsupported) }
        }
    }
}
