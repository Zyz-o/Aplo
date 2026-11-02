#if SWIFT_PACKAGE
import XCTest
import Carbon
@testable import Aplo

final class LocalizationTests: XCTestCase {
    func testInterpolatedMessagesUseEnglishTemplatesAndKeepPayloads() {
        let detail = "系统错误 %@；文件夹名称不能为空。"
        let app = "无法打开 中文 App %@"
        let cases: [(LocalizedMessage, String)] = [
            ("已导入 \(12) 个应用，跳过 \(3) 个未安装项目；原布局已备份。", "Imported 12 apps; skipped 3 missing items. The previous layout was backed up."),
            ("无法保存布局：\(detail)", "Unable to save layout: " + detail),
            ("操作未完成：\(detail)", "Operation not completed: " + detail),
            ("导出失败：\(detail)", "Export failed: " + detail),
            ("“\(app)”已被移动或卸载，列表已刷新。", "“" + app + "” was moved or removed. The app list was refreshed."),
            ("无法打开“\(app)”，请检查应用是否完整或有权限运行。", "Unable to open “" + app + "”. Check the app is complete and permitted to run.")
        ]
        XCTAssertEqual(LocalizedMessage.verbatim(detail).localized(language: .english), detail)
        for (message, expected) in cases { XCTAssertEqual(message.localized(language: .english), expected) }
    }
    func testExistingNotificationFollowsLanguageChangesWithoutTranslatingAppName() {
        let app = "应用 軟體 %@"
        let message: LocalizedMessage = "无法打开“\(app)”，请检查应用是否完整或有权限运行。"
        XCTAssertEqual(message.localized(language: .chinese), "无法打开“" + app + "”，请检查应用是否完整或有权限运行。")
        XCTAssertEqual(message.localized(language: .traditional), "無法打開“" + app + "”，請檢查應用是否完整或有權限運行。")
        XCTAssertTrue(message.localized(language: .english).contains(app))
        let empty: LocalizedMessage = "文件夹名称不能为空。"
        XCTAssertEqual(empty.localized(language: .english), "Folder name cannot be empty.")
    }
    func testRecordedAndLegacyShortcutsRenderUsingCurrentLanguage() throws {
        for name in ["空格", "Space"] {
            let shortcut = ShortcutBinding(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey), keyName: name)
            let original = try JSONEncoder().encode(shortcut)
            XCTAssertEqual(shortcut.localizedDisplayName(language: .english), "⌃⌥Space")
            XCTAssertEqual(shortcut.localizedDisplayName(language: .chinese), "⌃⌥空格")
            XCTAssertEqual(try JSONEncoder().encode(shortcut), original)
            let message: LocalizedMessage = "快捷键已设为 \(shortcut)。"
            XCTAssertEqual(message.localized(language: .english), "Shortcut set to ⌃⌥Space.")
            XCTAssertEqual(message.localized(language: .chinese), "快捷键已设为 ⌃⌥空格。")
        }
        let enter = ShortcutBinding(keyCode: UInt32(kVK_Return), modifiers: UInt32(cmdKey), keyName: "回车")
        XCTAssertEqual(enter.localizedDisplayName(language: .english), "⌘Return")
    }
}
#endif
