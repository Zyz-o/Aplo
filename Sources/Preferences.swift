import Foundation
import CoreGraphics

enum LauncherAppearance: String, Codable, CaseIterable {
    case system, light, dark
    var title: String {
        switch self { case .system: return "跟随系统"; case .light: return "浅色"; case .dark: return "深色" }
    }
}

enum LauncherIconSize: String, Codable, CaseIterable {
    case small, medium, large
    var title: String {
        switch self { case .small: return "小"; case .medium: return "中"; case .large: return "大" }
    }
    func points(fullscreen: Bool) -> CGFloat {
        switch (self, fullscreen) {
        case (.small, false): return 60
        case (.medium, false): return 72
        case (.large, false): return 84
        case (.small, true): return 64
        case (.medium, true): return 78
        case (.large, true): return 92
        }
    }
}

enum LauncherBackground: String, Codable, CaseIterable {
    case glass, solid
    var title: String { self == .glass ? "通透玻璃" : "纯色" }
}

enum LauncherPagingDirection: String, Codable, CaseIterable {
    case horizontal, vertical
    var title: String { self == .horizontal ? "左右" : "上下" }
}

enum LauncherNavigationStyle: String, Codable, CaseIterable {
    case continuous, paged
    var title: String { self == .continuous ? "连续滚动" : "分页切换" }
}

enum LauncherDockVisibility: String, Codable, CaseIterable {
    case hidden, followWindow, visible
    var title: String { switch self { case .hidden: return "隐藏"; case .followWindow: return "跟随窗口"; case .visible: return "显示" } }
}
enum LauncherLanguage: String, Codable, CaseIterable {
    case system, chinese, traditional, english
    var title: String { switch self { case .system: return "跟随系统"; case .chinese: return "简体中文"; case .traditional: return "繁體中文"; case .english: return "English" } }
    var usesTraditionalChinese: Bool {
        self == .traditional || (self == .system && ["zh-Hant", "zh-TW", "zh-HK", "zh-MO"].contains(where: { (Locale.preferredLanguages.first ?? "").hasPrefix($0) }))
    }
    var localeIdentifier: String { isEnglish ? "en" : usesTraditionalChinese ? "zh-Hant" : "zh-Hans" }
    var isEnglish: Bool { self == .english || (self == .system && !(Locale.preferredLanguages.first ?? "en").hasPrefix("zh")) }
}
enum LauncherColorVision: String, Codable, CaseIterable {
    case standard, redGreen, blueYellow, monochrome
    var title: String { switch self { case .standard: return "标准"; case .redGreen: return "红绿色盲友好"; case .blueYellow: return "蓝黄色盲友好"; case .monochrome: return "单色高对比" } }
}

enum LauncherLabelWeight: String, Codable, CaseIterable {
    case light, regular, medium, semibold, bold
    var title: String { switch self { case .light: return "细体"; case .regular: return "常规"; case .medium: return "中等"; case .semibold: return "半粗体"; case .bold: return "粗体" } }
}
enum LauncherLabelColor: String, Codable, CaseIterable {
    case automatic, white, black, custom
    var title: String { switch self { case .automatic: return "自动"; case .white: return "白色"; case .black: return "黑色"; case .custom: return "自定义" } }
}
enum LauncherEntryLocation: String, Codable, CaseIterable {
    case dock, menuBar, both
    var title: String { switch self { case .dock: return "程序坞"; case .menuBar: return "顶部菜单栏"; case .both: return "两处都显示" } }
    var showsInDock: Bool { self != .menuBar }
    var showsInMenuBar: Bool { self != .dock }
}
enum LauncherToolbarPosition: String, Codable, CaseIterable {
    case top, bottom
    var title: String { self == .top ? "上方" : "下方" }
}
enum LauncherDismissStyle: String, Codable, CaseIterable {
    case outsideClick, escapeOnly
    var title: String { self == .outsideClick ? "点击外部收起" : "仅按 Esc 收起" }
}
enum LauncherArrangement: String, Codable, CaseIterable, Sendable {
    case grid, free
    var title: String { self == .grid ? "网格排列" : "自由放置" }
}
struct FreeIconPosition: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
}
struct LauncherPreferences: Codable, Equatable {
    var labelFontFamily = ""
    var labelWeight: LauncherLabelWeight = .regular
    var labelColor: LauncherLabelColor = .automatic
    var labelColorHex = "#FFFFFF"
    var entryLocation: LauncherEntryLocation = .both
    var toolbarPosition: LauncherToolbarPosition = .bottom
    var dismissStyle: LauncherDismissStyle = .outsideClick
    var pinToDesktop = false
    var magnificationEnabled = true
    var arrangement: LauncherArrangement = .grid
    var compactArrangement: LauncherArrangement? = nil
    var dockVisibility: LauncherDockVisibility = .followWindow
    var language: LauncherLanguage = .system
    var colorVision: LauncherColorVision = .standard
    var brandIconPercent = 100.0
    var brandNamePercent = 100.0
    var iconScalePercent = 100.0
    var textScalePercent = 100.0
    var systemAppsLast = true
    var backgroundStyle: LauncherBackground = .glass
    var backgroundTransparency = 0.60
    var appearance: LauncherAppearance = .system
    var iconSize: LauncherIconSize = .medium
    var showNames = true
    var swipeEnabled = true
    var reversePaging = false
    var verticalPaging = true // Retained only for compatibility with old saved preferences.
    var pagingDirection: LauncherPagingDirection = .horizontal
    var navigationStyle: LauncherNavigationStyle = .continuous
    var gestureSensitivity = 1.6
    var automaticCategories = true
    var animationsEnabled = true
    var windowShadowEnabled = true
    var soundEffectsEnabled = false
    var soundOpen = "Submarine"
    var soundClose = "Glass"
    var soundNavigation = "Tink"
    var soundVolume = 0.5

    init() {}
    private enum CodingKeys: String, CodingKey {
        case labelFontFamily, labelWeight, labelColor, labelColorHex
        case entryLocation, toolbarPosition, dismissStyle, pinToDesktop, magnificationEnabled
        case arrangement, compactArrangement
        case brandIconPercent, brandNamePercent
        case dockVisibility, language, colorVision, iconScalePercent, textScalePercent, systemAppsLast
        case backgroundStyle, appearance, iconSize, showNames, swipeEnabled, reversePaging, automaticCategories
        case verticalPaging, gestureSensitivity, backgroundTransparency, pagingDirection, navigationStyle
        case animationsEnabled, windowShadowEnabled, soundEffectsEnabled, soundOpen, soundClose, soundNavigation, soundVolume
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        labelFontFamily = String(((try? c.decode(String.self, forKey: .labelFontFamily)) ?? "").prefix(120))
        labelWeight = (try? c.decode(LauncherLabelWeight.self, forKey: .labelWeight)) ?? .regular
        labelColor = (try? c.decode(LauncherLabelColor.self, forKey: .labelColor)) ?? .automatic
        let hex = (try? c.decode(String.self, forKey: .labelColorHex)) ?? "#FFFFFF"
        labelColorHex = hex.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil ? hex.uppercased() : "#FFFFFF"
        entryLocation = (try? c.decode(LauncherEntryLocation.self, forKey: .entryLocation)) ?? .both
        toolbarPosition = (try? c.decode(LauncherToolbarPosition.self, forKey: .toolbarPosition)) ?? .bottom
        dismissStyle = (try? c.decode(LauncherDismissStyle.self, forKey: .dismissStyle)) ?? .outsideClick
        pinToDesktop = (try? c.decode(Bool.self, forKey: .pinToDesktop)) ?? false
        magnificationEnabled = (try? c.decode(Bool.self, forKey: .magnificationEnabled)) ?? true
        arrangement = (try? c.decode(LauncherArrangement.self, forKey: .arrangement)) ?? .grid
        compactArrangement = try? c.decode(LauncherArrangement.self, forKey: .compactArrangement)
        dockVisibility = (try? c.decode(LauncherDockVisibility.self, forKey: .dockVisibility)) ?? .followWindow
        language = (try? c.decode(LauncherLanguage.self, forKey: .language)) ?? .system
        colorVision = (try? c.decode(LauncherColorVision.self, forKey: .colorVision)) ?? .standard
        systemAppsLast = try c.decodeIfPresent(Bool.self, forKey: .systemAppsLast) ?? true
        backgroundStyle = try c.decodeIfPresent(LauncherBackground.self, forKey: .backgroundStyle) ?? .glass
        let transparency = try c.decodeIfPresent(Double.self, forKey: .backgroundTransparency) ?? 0.60
        backgroundTransparency = transparency.isFinite ? min(1, max(0, transparency)) : 0.60
        appearance = try c.decodeIfPresent(LauncherAppearance.self, forKey: .appearance) ?? .system
        iconSize = try c.decodeIfPresent(LauncherIconSize.self, forKey: .iconSize) ?? .medium
        let brandIcon = try c.decodeIfPresent(Double.self, forKey: .brandIconPercent) ?? 100
        let brandName = try c.decodeIfPresent(Double.self, forKey: .brandNamePercent) ?? 100
        brandIconPercent = brandIcon.isFinite ? min(150, max(50, brandIcon)) : 100
        brandNamePercent = brandName.isFinite ? min(160, max(70, brandName)) : 100
        let iconPercent = try c.decodeIfPresent(Double.self, forKey: .iconScalePercent) ?? Double(iconSize.points(fullscreen: false) / 72 * 100)
        let textPercent = try c.decodeIfPresent(Double.self, forKey: .textScalePercent) ?? 100
        iconScalePercent = iconPercent.isFinite ? min(150, max(50, iconPercent)) : 100
        textScalePercent = textPercent.isFinite ? min(140, max(80, textPercent)) : 100
        showNames = try c.decodeIfPresent(Bool.self, forKey: .showNames) ?? true
        swipeEnabled = try c.decodeIfPresent(Bool.self, forKey: .swipeEnabled) ?? true
        reversePaging = try c.decodeIfPresent(Bool.self, forKey: .reversePaging) ?? false
        verticalPaging = try c.decodeIfPresent(Bool.self, forKey: .verticalPaging) ?? true
        pagingDirection = try c.decodeIfPresent(LauncherPagingDirection.self, forKey: .pagingDirection) ?? .horizontal
        navigationStyle = try c.decodeIfPresent(LauncherNavigationStyle.self, forKey: .navigationStyle) ?? .continuous
        let sensitivity = try c.decodeIfPresent(Double.self, forKey: .gestureSensitivity) ?? 1.6
        gestureSensitivity = sensitivity.isFinite ? min(2.4, max(0.8, sensitivity)) : 1.6
        automaticCategories = try c.decodeIfPresent(Bool.self, forKey: .automaticCategories) ?? true
        animationsEnabled = try c.decodeIfPresent(Bool.self, forKey: .animationsEnabled) ?? true
        windowShadowEnabled = try c.decodeIfPresent(Bool.self, forKey: .windowShadowEnabled) ?? true
        soundEffectsEnabled = try c.decodeIfPresent(Bool.self, forKey: .soundEffectsEnabled) ?? false
        soundOpen = try c.decodeIfPresent(String.self, forKey: .soundOpen) ?? "Submarine"
        soundClose = try c.decodeIfPresent(String.self, forKey: .soundClose) ?? "Glass"
        soundNavigation = try c.decodeIfPresent(String.self, forKey: .soundNavigation) ?? "Tink"
        let volume = try c.decodeIfPresent(Double.self, forKey: .soundVolume) ?? 0.5
        soundVolume = volume.isFinite ? min(1, max(0, volume)) : 0.5
    }

    var brandIconPoints: CGFloat { 44 * CGFloat(brandIconPercent / 100) }
    var brandNamePoints: CGFloat { 20 * CGFloat(brandNamePercent / 100) }
    func iconPoints(fullscreen: Bool) -> CGFloat { (fullscreen ? 78 : 72) * CGFloat(iconScalePercent / 100) }
    func textPoints(_ base: CGFloat) -> CGFloat { base * CGFloat(textScalePercent / 100) }
    var labelHeight: CGFloat { ceil(textPoints(36)) }
    func horizontalPageDelta(_ delta: Double) -> Int? {
        guard swipeEnabled, delta.isFinite, delta != 0 else { return nil }
        let direction = delta < 0 ? 1 : -1
        return reversePaging ? -direction : direction
    }
}

struct PreferencesStore {
    let defaults: UserDefaults
    private let key = "aplo.preferences.v1"
    func load() -> LauncherPreferences {
        guard let data = defaults.data(forKey: key),
              let preferences = try? JSONDecoder().decode(LauncherPreferences.self, from: data) else {
            return LauncherPreferences()
        }
        return preferences
    }
    func save(_ preferences: LauncherPreferences) {
        if let data = try? JSONEncoder().encode(preferences) { defaults.set(data, forKey: key) }
    }
}

/// Point-based geometry stays sharp on Retina and fits smaller external displays.
enum LauncherGeometry {
    static let compactSize = CGSize(width: 960, height: 660)
    static func compactFrame(in visibleFrame: CGRect) -> CGRect {
        let availableWidth = max(0, visibleFrame.width - 32)
        let availableHeight = max(0, visibleFrame.height - 32)
        let scale = min(1, availableWidth / compactSize.width, availableHeight / compactSize.height)
        let size = CGSize(width: floor(compactSize.width * scale), height: floor(compactSize.height * scale))
        return CGRect(x: visibleFrame.midX - size.width / 2, y: visibleFrame.midY - size.height / 2,
                      width: size.width, height: size.height)
    }
    static func horizontalSlots(itemCount: Int, rows: Int = 3, columns: Int = 6) -> [Int] {
        guard itemCount > 0 else { return [] }
        let rows = max(1, rows), columns = max(1, columns), blockSize = columns * rows
        return (0..<((itemCount + blockSize - 1) / blockSize)).flatMap { block in
            let occupiedColumns = min(columns, itemCount - block * blockSize)
            return (0..<occupiedColumns).flatMap { column in
                (0..<rows).map { block * blockSize + $0 * columns + column }
            }
        }
    }
    static func horizontalNeighbor(index: Int, offset: Int, itemCount: Int, rows: Int = 3, columns: Int = 6) -> Int {
        let rows = max(1, rows), columns = max(1, columns), blockSize = rows * columns
        let block = index / blockSize, row = (index % blockSize) / columns, column = index % columns
        let targetRow = row + (abs(offset) == columns ? offset / columns : 0)
        let targetColumn = block * columns + column + (abs(offset) == 1 ? offset : 0)
        guard (0..<rows).contains(targetRow), targetColumn >= 0 else { return index }
        let target = (targetColumn / columns) * blockSize + targetRow * columns + targetColumn % columns
        return (0..<itemCount).contains(target) ? target : index
    }
    static let gridSpacing: CGFloat = 8
    static func gridWidth(displayWidth: CGFloat, fullscreen: Bool) -> CGFloat {
        fullscreen ? max(1, displayWidth - 80) : max(1, min(displayWidth - 48, 768))
    }
    static func columnCount(displayWidth: CGFloat, fullscreen: Bool) -> Int {
        fullscreen ? max(6, Int(gridWidth(displayWidth: displayWidth, fullscreen: true) / 128)) : 6
    }
    static func tileWidth(displayWidth: CGFloat, fullscreen: Bool) -> CGFloat {
        let columns = CGFloat(columnCount(displayWidth: displayWidth, fullscreen: fullscreen))
        return max(1, (gridWidth(displayWidth: displayWidth, fullscreen: fullscreen) - (columns - 1) * gridSpacing) / columns)
    }
}


struct CompactWindowPlacementStore {
    let defaults: UserDefaults
    private let key = "aplo.windowPositions.v1"
    struct Anchor: Codable { let x: Double; let y: Double; var width: Double? = nil; var height: Double? = nil }
    private var positions: [String: Anchor] {
        guard let data = defaults.data(forKey: key), let value = try? JSONDecoder().decode([String: Anchor].self, from: data) else { return [:] }
        return value
    }
    func frame(in visible: CGRect, screenID: String) -> CGRect {
        let centered = LauncherGeometry.compactFrame(in: visible)
        guard let anchor = positions[screenID], anchor.x.isFinite, anchor.y.isFinite else { return centered }
        let safe = visible.insetBy(dx: 16, dy: 16)
        let size = Self.clamped(CGRect(x: safe.minX, y: safe.minY, width: anchor.width ?? centered.width, height: anchor.height ?? centered.height), in: visible).size
        return CGRect(x: safe.minX + max(0, safe.width - size.width) * min(1, max(0, anchor.x)),
                      y: safe.minY + max(0, safe.height - size.height) * min(1, max(0, anchor.y)),
                      width: size.width, height: size.height)
    }
    static func clamped(_ frame: CGRect, in visible: CGRect) -> CGRect {
        let safe = visible.insetBy(dx: 16, dy: 16)
        let size = CGSize(width: min(safe.width, max(720, frame.width.isFinite ? frame.width : 960)), height: min(safe.height, max(520, frame.height.isFinite ? frame.height : 660)))
        return CGRect(x: min(max(frame.minX, safe.minX), safe.maxX - size.width),
                      y: min(max(frame.minY, safe.minY), safe.maxY - size.height), width: size.width, height: size.height)
    }
    func save(frame: CGRect, in visible: CGRect, screenID: String) {
        let frame = Self.clamped(frame, in: visible), safe = visible.insetBy(dx: 16, dy: 16)
        let travelX = safe.width - frame.width, travelY = safe.height - frame.height
        var value = positions
        value[screenID] = Anchor(x: travelX > 0 ? Double((frame.minX - safe.minX) / travelX) : 0.5,
                                 y: travelY > 0 ? Double((frame.minY - safe.minY) / travelY) : 0.5, width: frame.width, height: frame.height)
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }
    func reset(screenID: String) {
        var value = positions; value.removeValue(forKey: screenID)
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }
}

/// Normalized top-left coordinates survive resizing and stay inside the canvas.
enum FreePlacementGeometry {
    static func origin(position: FreeIconPosition?, fallback: CGPoint, canvas: CGSize, tile: CGSize) -> CGPoint {
        let limitX = max(0, canvas.width - tile.width), limitY = max(0, canvas.height - tile.height)
        let point = position.map { CGPoint(x: CGFloat($0.x) * limitX, y: CGFloat($0.y) * limitY) } ?? fallback
        return CGPoint(x: min(limitX, max(0, point.x)), y: min(limitY, max(0, point.y)))
    }
    static func normalized(origin: CGPoint, canvas: CGSize, tile: CGSize) -> FreeIconPosition {
        let clamped = self.origin(position: nil, fallback: origin, canvas: canvas, tile: tile)
        return FreeIconPosition(x: Double(clamped.x / max(1, canvas.width - tile.width)),
                                y: Double(clamped.y / max(1, canvas.height - tile.height)))
    }
}

// Compact support: adjacent icons grow continuously, with no change to hit targets.
enum DockMagnificationCurve {
    static func scale(dx: CGFloat, dy: CGFloat, size: CGSize) -> CGFloat {
        guard size.width > 0, size.height > 0 else { return 1 }
        let distance = hypot(dx / (size.width * 3), dy / (size.height * 1.3))
        guard distance < 1 else { return 1 }
        let influence = cos(distance * .pi / 2)
        return 1 + 0.38 * influence * influence
    }
}
