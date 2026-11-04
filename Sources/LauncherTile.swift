import AppKit
import SwiftUI

private struct TileAppearanceKey: Equatable, Sendable {
    let iconSize: CGFloat
    let labelHeight: CGFloat
    let textScale: Double
    let showNames: Bool
    let font: String
    let weight: LauncherLabelWeight
    let color: LauncherLabelColor
    let colorHex: String
    let transparentLabels: Bool
    let vision: LauncherColorVision
    let magnify: Bool
    let animate: Bool
}
struct LauncherTile: View, Equatable {
    let model: LauncherModel
    @ObservedObject private var dragFeedback: TileDragFeedback
    let item: LayoutItem
    let selected: Bool
    let keyboardSelected: Bool
    let index: Int
    let displayName: String
    let accessibilityName: String
    private let appearance: TileAppearanceKey
    private let editing: Bool
    private let draggingID: String?
    private let freePlacement: Bool
    private let continuous: Bool
    let action: () -> Void
    init(model: LauncherModel, item: LayoutItem, index: Int, selected: Bool, action: @escaping () -> Void) {
        self.model = model; self.item = item; self.index = index; self.selected = selected; self.keyboardSelected = selected && model.keyboardSelectionActive; self.action = action
        self.displayName = model.name(for: item)
        self.accessibilityName = model.text((item.kind == .folder ? "打开文件夹 " : "打开 ") + displayName)
        self.editing = model.editing; self.draggingID = model.draggingID
        self.freePlacement = model.usesFreePlacement; self.continuous = model.isContinuousScrolling
        let p = model.preferences
        self.appearance = TileAppearanceKey(iconSize: min(p.iconPoints(fullscreen: model.isFullscreen), max(24, model.tileWidth - 18)), labelHeight: p.labelHeight, textScale: p.textScalePercent, showNames: p.showNames, font: p.labelFontFamily, weight: p.labelWeight, color: p.labelColor, colorHex: p.labelColorHex, transparentLabels: p.backgroundTransparency > 0.7, vision: p.colorVision, magnify: p.magnificationEnabled, animate: p.animationsEnabled)
        self.dragFeedback = model.dragFeedback(for: item.id)
    }
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.model === rhs.model && lhs.item == rhs.item && lhs.index == rhs.index && lhs.selected == rhs.selected && lhs.keyboardSelected == rhs.keyboardSelected && lhs.displayName == rhs.displayName && lhs.accessibilityName == rhs.accessibilityName && lhs.appearance == rhs.appearance && lhs.editing == rhs.editing && lhs.draggingID == rhs.draggingID && lhs.freePlacement == rhs.freePlacement && lhs.continuous == rhs.continuous
    }
    private var iconSize: CGFloat { appearance.iconSize }
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var clearBackdrop: Bool { model.preferences.backgroundTransparency > 0.7 && !reduceTransparency }
    @Environment(\.colorScheme) private var colorScheme
    /// Folder artwork outline: stronger in dark mode and stronger still when the
    /// system increase-contrast option is on.
    private var folderStroke: Color {
        model.accentColor.opacity(AploVisual.tileStroke(dark: colorScheme == .dark,
                                                        increaseContrast: AploAccessibility.increasesContrast))
    }
    private var previewChildren: [String]? {
        guard dragFeedback.isMergeTarget,
              let sourceID = model.draggingID else { return nil }
        let source = model.browsingLayout.allItems.first { $0.id == sourceID }
        let incoming = source.map { $0.kind == .folder ? $0.children : [$0.appID].compactMap { $0 } }
            ?? (sourceID.hasPrefix("app:") ? [String(sourceID.dropFirst(4))] : [])
        let current = item.kind == .folder ? item.children : [item.appID].compactMap { $0 }
        var seen = Set<String>()
        return (current + incoming).filter { seen.insert($0).inserted }
    }
    /// The 3×3 folder preview. Built from plain stacks so laying it out costs nothing
    /// more than fixed frames; a fixed-column grid would run its own layout each pass.
    @ViewBuilder private func folderPreview(_ ids: [String]) -> some View {
        let side = iconSize * 0.23
        let visible = Array(ids.prefix(9))
        let rows = max(1, (visible.count + 2) / 3)
        VStack(spacing: 2) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { column in
                        let index = row * 3 + column
                        if visible.indices.contains(index), let app = model.app(for: visible[index]) {
                            Image(nsImage: model.previewIcon(for: app, notifying: dragFeedback))
                                .resizable().interpolation(.high)
                                .frame(width: side, height: side)
                        } else {
                            Color.clear.frame(width: side, height: side)
                        }
                    }
                }
            }
        }.padding(4)
    }
    private var nativeIcon: NSImage? {
        guard item.kind == .app, previewChildren == nil, let id = item.appID, let app = model.app(for: id) else { return nil }
        return model.icon(for: app, notifying: dragFeedback)
    }
    private var iconIdentity: IconRenderIdentity {
        let ids = previewChildren ?? (item.kind == .folder ? item.children : [item.appID].compactMap { $0 })
        // One pass over the children: resolve the app and read the cached bitmap pointer
        // without scheduling raster work on each SwiftUI diff pass.
        var images: [ObjectIdentifier] = []
        images.reserveCapacity(min(ids.count, 9))
        for id in ids.prefix(9) {
            guard let app = model.app(for: id) else { continue }
            images.append(model.cachedIconIdentity(for: app))
        }
        return IconRenderIdentity(item: item, children: previewChildren,
                                  images: images,
                                  size: iconSize, colorVision: appearance.vision,
                                  badgePoints: 8 * appearance.textScale / 100, dark: colorScheme == .dark)
    }
    var body: some View {
        // Read the preference bundle once instead of copying the whole struct for every
        // modifier below; this body runs for every visible tile on every scroll frame.
        let p = appearance
        let continuous = model.isContinuousScrolling
        let dragging = model.draggingID
        return Button(action: action) {
            VStack(spacing: 4) {
                DockMagnifiedIcon(identity: iconIdentity, image: nativeIcon, enabled: p.magnify && !model.editing && dragging == nil && !reduceMotion,
                                  animated: p.animate && !reduceMotion,
                                  wiggling: editing && draggingID == nil && p.animate && !reduceMotion) {
                Group {
                if item.kind == .folder || previewChildren != nil {
                    ZStack {
                        RoundedRectangle(cornerRadius: AploVisual.tileRadius)
                            .fill(LinearGradient(colors: [model.accentColor.opacity(0.20), model.accentColor.opacity(0.075)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                        RoundedRectangle(cornerRadius: AploVisual.tileRadius).strokeBorder(folderStroke)
                        // Plain stacks instead of a fixed VGrid: the grid runs its own
                        // column layout on every pass, while three rows of fixed frames
                        // produce the identical 3×3 preview for a fraction of the cost.
                        folderPreview(previewChildren ?? item.children)
                    }.frame(width: iconSize, height: iconSize)
                        .scaleEffect(hovered && p.magnify && !model.editing && !reduceMotion ? 1.05 : 1)
                        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: hovered)
                        .overlay(alignment: .bottomTrailing) {
                            if previewChildren == nil { Text("\(item.children.count)").lineLimit(1).minimumScaleFactor(0.5).font(.system(size: 8 * p.textScale / 100, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 4).padding(.vertical, 2)
                                .frame(maxWidth: max(1, iconSize - 6))
                                .background(.regularMaterial, in: Capsule()).padding(3) }
                        }
                } else if let id = item.appID, let app = model.app(for: id) {
                    Image(nsImage: model.icon(for: app, notifying: dragFeedback)).resizable().interpolation(.high).frame(width: iconSize, height: iconSize)
                }
                }
                }.frame(width: iconSize, height: iconSize)
                    .opacity(dragging == item.id && !model.usesFreePlacement ? 0.25 : 1)
                Text(displayName).font(model.applicationLabelFont)
                    .foregroundStyle(model.applicationLabelColor)
                    .lineLimit(2).multilineTextAlignment(.center)
                    .padding(.horizontal, clearBackdrop ? 4 : 0)
                    // Skip the glyph shadow while a gesture or transition is animating;
                    // blurred text shadows are the most expensive per-tile layer effect.
                    .shadow(color: clearBackdrop && !continuous && !model.pageTransitionActive ? (p.color == .black ? .white.opacity(0.6) : .black.opacity(0.65)) : .clear, radius: 1, y: 1)
                    .frame(height: p.labelHeight, alignment: .top)
                    .opacity(p.showNames ? 1 : 0).accessibilityHidden(!p.showNames)
            }
            .padding(.top, 10).padding(.bottom, 4).frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .zIndex(hovered ? 1 : 0)
        .buttonStyle(LauncherPressStyle(animated: p.animate && !reduceMotion)).onHover { if dragging == nil && !model.editing {
            hovered = $0
            if $0 { model.hoveredAppID = item.appID }
            else if model.hoveredAppID == item.appID { model.hoveredAppID = nil }
        } }
        // The label already shows the name, so a tooltip only adds an AppKit tracking
        // area per tile. Keep it solely for the name-hidden mode where it still helps.
        .help(p.showNames ? "" : displayName)
        .animation(reduceMotion || continuous || !p.animate || dragging != nil ? nil : .easeOut(duration: 0.12), value: hovered)
        .overlay {
            if let indicator = dragFeedback.indicator {
                if indicator == .merge {
                    RoundedRectangle(cornerRadius: AploVisual.highlightRadius).strokeBorder(model.accentColor, lineWidth: 2)
                        .padding(3).allowsHitTesting(false)
                } else {
                    Capsule().fill(model.accentColor).frame(width: 3)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: indicator == .before ? .leading : .trailing)
                        .allowsHitTesting(false)
                }
            } else if keyboardSelected {
                RoundedRectangle(cornerRadius: AploVisual.highlightRadius).strokeBorder(model.accentColor.opacity(0.65), lineWidth: 1.5)
                    .padding(3).allowsHitTesting(false)
            }
        }
        .scaleEffect(keyboardSelected && p.animate && !reduceMotion ? 1.08 : 1)
        .shadow(color: keyboardSelected && p.animate && !reduceMotion ? model.accentColor.opacity(0.3) : .clear, radius: AploVisual.focusShadowRadius)
        .animation(.easeOut(duration: 0.15), value: keyboardSelected)
        .accessibilityLabel(accessibilityName)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct LauncherPressStyle: ButtonStyle {
    let animated: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && animated ? 0.92 : 1)
            .opacity(configuration.isPressed && animated ? 0.8 : 1)
            .animation(animated ? .interactiveSpring(response: 0.18, dampingFraction: 0.7) : nil, value: configuration.isPressed)
    }
}
