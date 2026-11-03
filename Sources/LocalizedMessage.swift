import Foundation

/// Store a translatable template separately from names, counts and system error details.
/// Rendering follows the current language, including notifications already on screen.
struct LocalizedMessage: Equatable, Sendable, ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
    enum Argument: Equatable, Sendable {
        case text(String)
        case shortcut(ShortcutBinding)
        func render(language: LauncherLanguage) -> String {
            switch self {
            case .text(let value): value
            case .shortcut(let value): value.localizedDisplayName(language: language)
            }
        }
    }
    enum Presentation: Equatable, Sendable { case persistent, notice }
    private(set) var presentation: Presentation = .persistent
    static func notice(_ value: LocalizedMessage) -> LocalizedMessage { var copy = value; copy.presentation = .notice; return copy }
    let template: String
    let arguments: [Argument]
    init(_ source: String) { template = source; arguments = [] }
    private init(template: String, arguments: [Argument]) { self.template = template; self.arguments = arguments }
    static func verbatim(_ value: String) -> LocalizedMessage { LocalizedMessage(template: "%@", arguments: [.text(value)]) }
    init(stringLiteral value: String) { self.init(value) }
    init(stringInterpolation: StringInterpolation) {
        template = stringInterpolation.template; arguments = stringInterpolation.arguments
    }
    struct StringInterpolation: StringInterpolationProtocol {
        var template = ""
        var arguments: [Argument] = []
        init(literalCapacity: Int, interpolationCount: Int) {
            template.reserveCapacity(literalCapacity); arguments.reserveCapacity(interpolationCount)
        }
        mutating func appendLiteral(_ literal: String) { template += literal }
        mutating func appendInterpolation<T: CustomStringConvertible>(_ value: T) {
            template += "%@"; arguments.append(.text(value.description))
        }
        mutating func appendInterpolation(_ value: ShortcutBinding) {
            template += "%@"; arguments.append(.shortcut(value))
        }
    }
    func localized(language: LauncherLanguage) -> String {
        let translated = AppStrings.text(template, language: language)
        guard !arguments.isEmpty else { return translated }
        let parts = translated.components(separatedBy: "%@")
        // Translation entries are developer-owned; never interpret parameters as format strings.
        guard parts.count == arguments.count + 1 else { return template }
        var result = parts[0]
        for (index, argument) in arguments.enumerated() {
            result += argument.render(language: language) + parts[index + 1]
        }
        return result
    }
}
