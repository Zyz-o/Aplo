import AppKit
import SwiftUI

/// Centralised visual constants so radii, stroke weights and shadow levels stay
/// consistent across the launcher instead of drifting between call sites.
enum AploVisual {
    /// Icon tiles (apps, folders).
    static let tileRadius: CGFloat = 13
    /// Focus and merge rings sit slightly outside the tile artwork.
    static let highlightRadius: CGFloat = 14
    /// Search field and other inline panels.
    static let panelRadius: CGFloat = 13
    /// Floating windows and sheets.
    static let windowRadius: CGFloat = 20

    /// Outline around a tile. Dark mode needs more contrast than light mode, and the
    /// system "Increase contrast" accessibility option needs more still.
    static func tileStroke(dark: Bool, increaseContrast: Bool) -> Double {
        if increaseContrast { return dark ? 0.60 : 0.50 }
        return dark ? 0.28 : 0.15
    }

    /// Outline around interactive chrome such as the search field.
    static func panelStroke(dark: Bool, increaseContrast: Bool, active: Bool) -> Double {
        if increaseContrast { return active ? 0.85 : 0.55 }
        return active ? 0.60 : (dark ? 0.32 : 0.22)
    }

    /// Shadow applied to a hovered tile, never during scrolling.
    static let hoverShadowRadius: CGFloat = 4
    /// Glow around the keyboard selection.
    static let focusShadowRadius: CGFloat = 12
}

/// Reads accessibility display options once and refreshes them when the user changes
/// them in System Settings, instead of querying AppKit for every tile on every frame.
@MainActor
enum AploAccessibility {
    private static var cachedContrast: Bool?
    private static var observing = false

    static var increasesContrast: Bool {
        if let cachedContrast { return cachedContrast }
        let value = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        cachedContrast = value
        if !observing {
            observing = true
            NotificationCenter.default.addObserver(
                forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                object: nil, queue: .main
            ) { _ in
                MainActor.assumeIsolated { cachedContrast = nil }
            }
        }
        return value
    }
}
