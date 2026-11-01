#if SWIFT_PACKAGE
@testable import Aplo
#endif
import Foundation
import CoreGraphics

#if !SWIFT_PACKAGE
@main
#endif
 struct PreferencesTests {
    static func main() throws {
        let domain = "local.aplo.preferences-test." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = PreferencesStore(defaults: defaults)
        func expect(_ condition: Bool, _ description: String) {
            precondition(condition, description)
            print("PASS: \(description)")
        }
        let initial = store.load()
        expect(initial == LauncherPreferences(), "first launch uses system appearance, medium icons and normal paging")
        expect(initial.horizontalPageDelta(-45) == 1 && initial.horizontalPageDelta(45) == -1, "normal horizontal gestures follow the existing direction")
        var changed = initial
        changed.appearance = .dark
        changed.iconSize = .large
        changed.showNames = false
        changed.reversePaging = true
        expect(changed.horizontalPageDelta(-45) == -1 && changed.horizontalPageDelta(45) == 1, "reverse paging changes both horizontal directions")
        store.save(changed)
        let reopened = PreferencesStore(defaults: UserDefaults(suiteName: domain)!).load()
        expect(reopened == changed, "appearance, icon size, names and reverse direction persist across instances")
        changed.swipeEnabled = false
        expect(changed.horizontalPageDelta(-45) == nil && changed.horizontalPageDelta(45) == nil, "disabled gestures cannot change pages")
        store.save(changed)
        expect(!store.load().swipeEnabled && store.load().reversePaging, "disabling gestures preserves the user's reverse preference")
        expect(initial.horizontalPageDelta(0) == nil && initial.horizontalPageDelta(.nan) == nil, "stationary or invalid gesture input does not flip pages")
        defaults.set(Data("invalid".utf8), forKey: "aplo.preferences.v1")
        expect(store.load() == initial, "invalid preference data falls back to usable defaults")
        let otherDomain = domain + ".isolated"
        let other = UserDefaults(suiteName: otherDomain)!
        defer { other.removePersistentDomain(forName: otherDomain) }
        expect(PreferencesStore(defaults: other).load() == initial, "test suites do not share preferences")
        let legacy = Data(#"{"appearance":"light","iconSize":"small","showNames":false,"swipeEnabled":true,"reversePaging":true}"#.utf8)
        defaults.set(legacy, forKey: "aplo.preferences.v1")
        let migrated = store.load()
        expect(migrated.appearance == .light && migrated.iconSize == .small && !migrated.showNames && migrated.reversePaging, "legacy preferences retain every existing choice")
        expect(migrated.automaticCategories && !migrated.soundEffectsEnabled, "new options receive defaults without resetting legacy choices")
        var audio = migrated; audio.soundEffectsEnabled = true; audio.soundOpen = "Pop"; audio.soundVolume = 0.25
        store.save(audio)
        expect(store.load().soundOpen == "Pop" && store.load().soundVolume == 0.25 && store.load().soundEffectsEnabled, "sound selections and volume persist")
        let screen = CGRect(x: 0, y: 38, width: 1512, height: 900)
        let compact = LauncherGeometry.compactFrame(in: screen)
        expect(compact.size == CGSize(width: 960, height: 660), "compact launcher uses the larger preferred size")
        expect(compact.midX == screen.midX && compact.midY == screen.midY, "compact launcher remains centered in the available screen")
        let smallScreen = CGRect(x: -800, y: 40, width: 800, height: 580)
        let fitted = LauncherGeometry.compactFrame(in: smallScreen)
        expect(smallScreen.insetBy(dx: 16, dy: 16).contains(fitted), "compact window fits a small external screen with a margin")
        expect(LauncherGeometry.tileWidth(displayWidth: 960, fullscreen: false) > LauncherGeometry.tileWidth(displayWidth: 640, fullscreen: false), "drag targeting follows the actual enlarged grid width")
        let fullColumns = LauncherGeometry.columnCount(displayWidth: 1512, fullscreen: true)
        expect(fullColumns == 11, "fullscreen adds columns to retain compact icon spacing across the display")
        expect(abs(LauncherGeometry.tileWidth(displayWidth: 1512, fullscreen: true) * CGFloat(fullColumns) + CGFloat(fullColumns - 1) * LauncherGeometry.gridSpacing - 1448) < 0.001, "fullscreen drag targets span the available display width")
        expect(LauncherGeometry.gridWidth(displayWidth: 2560, fullscreen: true) == 2496, "large external displays do not inherit the compact width cap")
        expect(LauncherGeometry.columnCount(displayWidth: 960, fullscreen: false) == 6, "compact mode retains the regular six-column grid")
        let wideSlots = LauncherGeometry.horizontalSlots(itemCount: 102, rows: 5, columns: 11).filter { $0 < 102 }
        expect(Set(wideSlots).count == 102 && wideSlots.count == 102, "wide horizontal grids include each application exactly once")
        expect(LauncherGeometry.horizontalNeighbor(index: 10, offset: 1, itemCount: 102, rows: 5, columns: 11) == 55, "wide horizontal navigation crosses the actual column boundary")
        expect(migrated.verticalPaging && migrated.gestureSensitivity == 1.6, "old preferences receive responsive gestures without losing existing choices")
        var gestures = migrated; gestures.verticalPaging = false; gestures.gestureSensitivity = 2.1
        store.save(gestures)
        expect(!store.load().verticalPaging && store.load().gestureSensitivity == 2.1, "vertical gesture choice and sensitivity persist")
        defaults.set(Data(#"{"gestureSensitivity":99}"#.utf8), forKey: "aplo.preferences.v1")
        expect(store.load().gestureSensitivity == 2.4, "invalid saved sensitivity is clamped to a usable range")
        expect(migrated.backgroundTransparency == 0.60, "old preferences receive desktop-adaptive glass without losing appearance choices")
        var glass = migrated; glass.backgroundTransparency = 0.75
        store.save(glass)
        expect(store.load().backgroundTransparency == 0.75, "background transparency persists across restarts")
        defaults.set(Data(#"{"backgroundTransparency":2}"#.utf8), forKey: "aplo.preferences.v1")
        expect(store.load().backgroundTransparency == 1, "transparency is clamped at fully transparent")
        expect(LauncherGeometry.gridWidth(displayWidth: 960, fullscreen: false) == 768, "compact columns use a centered narrower grid")
        expect(migrated.pagingDirection == .horizontal, "legacy preferences retain the original horizontal navigation option")
        var direction = migrated; direction.pagingDirection = .vertical
        store.save(direction)
        expect(store.load().pagingDirection == .vertical, "vertical page direction persists across restarts")
        direction.pagingDirection = .horizontal; store.save(direction)
        expect(store.load().pagingDirection == .horizontal, "horizontal direction can be selected again without resetting layout")
        expect(migrated.navigationStyle == .continuous, "existing preferences receive the requested continuous browsing default")
        var browsing = migrated; browsing.navigationStyle = .paged
        store.save(browsing)
        expect(store.load().navigationStyle == .paged, "paged browsing remains selectable and persists")
        browsing.navigationStyle = .continuous; browsing.pagingDirection = .vertical
        store.save(browsing)
        expect(store.load().navigationStyle == .continuous && store.load().pagingDirection == .vertical, "browsing behavior and axis persist independently")
        let slots = LauncherGeometry.horizontalSlots(itemCount: 40)
        expect(Array(slots.prefix(6)) == [0, 6, 12, 1, 7, 13], "horizontal scrolling retains familiar row-major application placement")
        expect(Set(slots.filter { $0 < 40 }) == Set(0..<40), "horizontal continuous grid includes every app exactly once including the last partial block")
        expect(LauncherGeometry.horizontalNeighbor(index: 5, offset: 1, itemCount: 40) == 18 && LauncherGeometry.horizontalNeighbor(index: 18, offset: -1, itemCount: 40) == 5, "horizontal keyboard neighbors match the displayed column geometry")
        expect(abs(migrated.iconPoints(fullscreen: false) - 60) < 0.001 && migrated.textScalePercent == 100, "old small icon preference migrates to a matching percentage")
        var accessibility = migrated
        accessibility.language = .english; accessibility.colorVision = .redGreen
        accessibility.dockVisibility = .visible; accessibility.iconScalePercent = 125; accessibility.textScalePercent = 120
        store.save(accessibility)
        expect(store.load() == accessibility, "language, color vision, Dock and percentage settings survive restart")
        expect(accessibility.iconPoints(fullscreen: false) == 90 && abs(accessibility.textPoints(14) - 16.8) < 0.001, "icon and text percentages scale independently")
        defaults.set(Data(#"{"iconScalePercent":999,"textScalePercent":1,"language":"future","appearance":"light"}"#.utf8), forKey: "aplo.preferences.v1")
        expect(store.load().iconScalePercent == 150 && store.load().textScalePercent == 80, "saved scale values are bounded to usable ranges")
        expect(store.load().language == .system && store.load().appearance == .light, "unknown new language values do not discard older preferences")
        expect(AppStrings.text("显示程序坞", language: .english) == "Show Dock", "Dock control has an English translation")
        expect(AppStrings.text("102 个应用 · 连续滚动", language: .english) == "102 apps · Continuous scrolling", "dynamic app counts and browsing headers translate together")
        expect(AppStrings.text("大小对比", language: .english) == "Size Comparison" && AppStrings.text("大小对比", language: .chinese) == "大小对比", "preview language can switch in both directions")
        expect(LauncherGeometry.horizontalNeighbor(index: 5, offset: 1, itemCount: 40, rows: 2) == 12, "large icon horizontal grids retain correct keyboard neighbors with fewer rows")
        expect(Set(LauncherGeometry.horizontalSlots(itemCount: 40, rows: 2).filter { $0 < 40 }) == Set(0..<40), "adaptive horizontal rows still expose all applications exactly once")
        expect(migrated.brandIconPercent == 100 && migrated.brandNamePercent == 100, "existing preferences receive independent header size defaults")
        var header = migrated; header.brandIconPercent = 125; header.brandNamePercent = 150
        store.save(header)
        expect(store.load().brandIconPoints == 55 && store.load().brandNamePoints == 30, "header icon and name percentages persist independently")
        expect(store.load().iconScalePercent == migrated.iconScalePercent && store.load().textScalePercent == migrated.textScalePercent, "header scaling does not change the application grid scales")
        let positions = CompactWindowPlacementStore(defaults: other)
        let visible = CGRect(x: -1800, y: 38, width: 1800, height: 1000)
        let moved = CGRect(x: -1600, y: 160, width: 960, height: 660)
        positions.save(frame: moved, in: visible, screenID: "display-a")
        let restoredPosition = positions.frame(in: visible, screenID: "display-a")
        expect(abs(restoredPosition.minX - moved.minX) < 0.001 && abs(restoredPosition.minY - moved.minY) < 0.001, "dragged compact position round-trips on a screen with a negative origin")
        expect(positions.frame(in: visible, screenID: "display-b") == LauncherGeometry.compactFrame(in: visible), "a different display starts centered without overwriting its neighbor")
        let smaller = CGRect(x: 0, y: 20, width: 850, height: 650)
        expect(smaller.insetBy(dx: 16, dy: 16).contains(positions.frame(in: smaller, screenID: "display-a")), "restored positions remain reachable after a smaller screen configuration")
        positions.reset(screenID: "display-a")
        expect(positions.frame(in: visible, screenID: "display-a") == LauncherGeometry.compactFrame(in: visible), "reset position restores centering")
        expect(visible.insetBy(dx: 16, dy: 16).contains(CompactWindowPlacementStore.clamped(CGRect(x: -9999, y: -9999, width: 960, height: 660), in: visible)), "off-screen dragged origins are clamped when restoring")
        let freeCanvas = CGSize(width: 800, height: 1200), freeTile = CGSize(width: 120, height: 140)
        let normalized = FreePlacementGeometry.normalized(origin: CGPoint(x: 340, y: 530), canvas: freeCanvas, tile: freeTile)
        expect(normalized == FreeIconPosition(x: 0.5, y: 0.5), "free positions are normalized independently of canvas size")
        let restoredFree = FreePlacementGeometry.origin(position: normalized, fallback: .zero, canvas: CGSize(width: 1000, height: 800), tile: freeTile)
        expect(restoredFree == CGPoint(x: 440, y: 330), "free positions stay proportional after resizing")
        expect(FreePlacementGeometry.normalized(origin: CGPoint(x: -200, y: 5000), canvas: freeCanvas, tile: freeTile) == FreeIconPosition(x: 0, y: 1), "free dragging is bounded inside the scrollable canvas")
        expect(FreePlacementGeometry.normalized(origin: .zero, canvas: .zero, tile: freeTile) == FreeIconPosition(x: 0, y: 0), "small canvases avoid invalid position coordinates")
        var freePreferences = LauncherPreferences()
        freePreferences.arrangement = .free
        let freeRestored = try JSONDecoder().decode(LauncherPreferences.self, from: JSONEncoder().encode(freePreferences))
        expect(freeRestored == freePreferences, "free arrangement round-trips without affecting other preferences")
        let legacyFree = try JSONDecoder().decode(LauncherPreferences.self, from: Data("{}".utf8))
        expect(legacyFree.arrangement == .grid, "legacy preferences preserve the original grid mode")
        let resized = CGRect(x: visible.minX + 40, y: visible.minY + 40, width: 1100, height: 780)
        positions.save(frame: resized, in: visible, screenID: "resized")
        expect(positions.frame(in: visible, screenID: "resized").size == resized.size, "user-resized window dimensions persist per display")
        let smallWindow = CompactWindowPlacementStore.clamped(CGRect(x: 0, y: 0, width: 100, height: 100), in: visible)
        expect(smallWindow.width == 720 && smallWindow.height == 520, "custom resizing respects usable minimum dimensions")
        var desktop = LauncherPreferences()
        desktop.toolbarPosition = .top; desktop.dismissStyle = .escapeOnly; desktop.pinToDesktop = true
        desktop.backgroundStyle = .solid; desktop.backgroundTransparency = 1; desktop.magnificationEnabled = false
        store.save(desktop)
        expect(store.load() == desktop, "desktop pinning, dismissal, toolbar and fully transparent solid style persist")
        expect(legacyFree.toolbarPosition == .bottom && legacyFree.dismissStyle == .outsideClick && !legacyFree.pinToDesktop, "old preferences retain automatic dismissal and bottom controls")
        expect(legacyFree.entryLocation == .both, "old preferences retain Dock and menu-bar entries")
        for location in LauncherEntryLocation.allCases {
            var entry = LauncherPreferences(); entry.entryLocation = location; store.save(entry)
            expect(store.load().entryLocation == location, "entry location persists: " + location.rawValue)
            expect(location.showsInDock || location.showsInMenuBar, "at least one access point remains: " + location.rawValue)
        }
        expect(!LauncherEntryLocation.menuBar.showsInDock && !LauncherEntryLocation.dock.showsInMenuBar, "exclusive entry choices hide only the unselected access point")
        expect(legacyFree.labelFontFamily.isEmpty && legacyFree.labelWeight == .regular && legacyFree.labelColor == .automatic, "old preferences receive regular transparent application labels")
        var labels = LauncherPreferences(); labels.labelFontFamily = "Songti SC"; labels.labelWeight = .light; labels.labelColor = .custom; labels.labelColorHex = "#12aB34"; labels.language = .traditional
        store.save(labels)
        let savedLabels = store.load()
        expect(savedLabels.labelFontFamily == "Songti SC" && savedLabels.labelWeight == .light && savedLabels.labelColorHex == "#12AB34", "font family, weight and custom RGB color persist")
        expect(savedLabels.language.usesTraditionalChinese && savedLabels.language.localeIdentifier == "zh-Hant", "Traditional Chinese is independent of font family")
        expect(AppStrings.text("应用设置", language: .traditional) == "應用設置", "Traditional Chinese converts interface text using the system transform")
        defaults.set(Data(#"{"labelColorHex":"invalid"}"#.utf8), forKey: "aplo.preferences.v1")
        expect(store.load().labelColorHex == "#FFFFFF", "invalid custom label colors safely fall back")
        let icon = CGSize(width: 72, height: 72)
        expect(abs(DockMagnificationCurve.scale(dx: 0, dy: 0, size: icon) - 1.38) < 0.0001, "the pointed icon reaches the configured magnification peak")
        expect(DockMagnificationCurve.scale(dx: 36, dy: 0, size: icon) == 1 && DockMagnificationCurve.scale(dx: 45, dy: 0, size: icon) == 1, "icon boundaries and gaps never magnify neighbors")
        expect(DockMagnificationCurve.scale(dx: 220, dy: 0, size: icon) == 1 && DockMagnificationCurve.scale(dx: 0, dy: 150, size: icon) == 1, "distant icons and separate rows retain their normal scale")
        expect(DockMagnificationCurve.scale(dx: -18, dy: 0, size: icon) == DockMagnificationCurve.scale(dx: 18, dy: 0, size: icon), "magnification is symmetric when moving left or right")
        print("All 78 preference, compatibility and window geometry checks passed.")
    }
}
