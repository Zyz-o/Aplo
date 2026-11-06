import AppKit
import SwiftUI

/// A scaled sample of the launcher grid, based on the selected window mode.
struct LayoutLivePreview: View {
    let model: LauncherModel
    @State private var fullscreen: Bool

    init(model: LauncherModel) {
        self.model = model
        _fullscreen = State(initialValue: model.isFullscreen)
    }

    var body: some View {
        let preferences = model.preferences
        let displayWidth = fullscreen == model.isFullscreen ? model.displayWidth
            : (fullscreen ? NSScreen.main?.frame.width ?? model.displayWidth : LauncherGeometry.compactSize.width)
        let gridWidth = LauncherGeometry.gridWidth(displayWidth: displayWidth, fullscreen: fullscreen)
        let configuredColumns = fullscreen ? preferences.fullscreenGridColumns : preferences.compactGridColumns
        let columns = configuredColumns == 0
            ? LauncherGeometry.columnCount(displayWidth: displayWidth, fullscreen: fullscreen) : configuredColumns
        let configuredRows = fullscreen ? preferences.fullscreenGridRows : preferences.compactGridRows
        let spacing = LauncherGeometry.gridSpacing
        let tileWidth = max(1, (gridWidth - CGFloat(columns - 1) * spacing) / CGFloat(columns))
        let iconSize = min(preferences.iconPoints(fullscreen: fullscreen), max(24, tileWidth - 18))
        let samples = Array(model.apps.prefix(columns * (configuredRows == 1 ? 1 : 2)))
        let sampleRows = max(1, (samples.count + columns - 1) / columns)
        let labelHeight = preferences.labelHeight
        let rowHeight = iconSize + labelHeight + 18
        let gridHeight = CGFloat(sampleRows) * (rowHeight + spacing) - spacing

        VStack(alignment: .leading, spacing: 8) {
            Picker(model.text("布局预览"), selection: $fullscreen) {
                Text(model.text("小窗口")).tag(false)
                Text(model.text("全屏")).tag(true)
            }.pickerStyle(.segmented)
            Text(model.text("列数") + " \(columns)")
                .font(.caption).foregroundStyle(.secondary)
            if samples.isEmpty {
                Text(model.text("没有找到已安装的应用")).font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 48)
            } else {
                GeometryReader { geometry in
                    let scale = min(0.72, max(0, geometry.size.width - 16) / gridWidth,
                                    max(0, geometry.size.height - 16) / gridHeight)
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(tileWidth), spacing: spacing), count: columns),
                              alignment: .leading, spacing: spacing) {
                        ForEach(samples) { app in
                            VStack(spacing: 4) {
                                PreviewAppIcon(model: model, app: app)
                                    .frame(width: iconSize, height: iconSize)
                                if preferences.showNames {
                                    Text(app.name).font(model.applicationLabelFont)
                                        .lineLimit(2).multilineTextAlignment(.center)
                                        .frame(height: labelHeight, alignment: .top)
                                }
                            }.frame(width: tileWidth, height: rowHeight, alignment: .top)
                        }
                    }
                    .frame(width: gridWidth)
                    .scaleEffect(scale, anchor: .topLeading)
                    .offset(x: (geometry.size.width - gridWidth * scale) / 2, y: 8)
                }
                .frame(height: min(155, gridHeight * 0.72) + 16)
                .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)
            }
        }
    }
}
