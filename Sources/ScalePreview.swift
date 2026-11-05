import AppKit
import SwiftUI

struct ScalePreview: View {
    @ObservedObject var model: LauncherModel
    @Environment(\.dismiss) private var dismiss
    @State private var iconPercent: Double
    @State private var textPercent: Double
    private let original: LauncherPreferences

    init(model: LauncherModel) {
        self.model = model
        original = model.preferences
        _iconPercent = State(initialValue: model.preferences.iconScalePercent)
        _textPercent = State(initialValue: model.preferences.textScalePercent)
    }
    private var proposed: LauncherPreferences {
        var value = original; value.iconScalePercent = iconPercent; value.textScalePercent = textPercent
        return value
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.text("大小对比")).font(.system(size: 22, weight: .semibold))
                    Text(model.text("图标 50–150% · 文字 80–140%")).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button(model.text("恢复 100%")) { iconPercent = 100; textPercent = 100 }
            }
            HStack(spacing: 16) {
                sample(title: "当前", preferences: original)
                sample(title: "调整后", preferences: proposed)
            }
            HStack {
                Text(model.text("图标大小")).frame(width: 80, alignment: .leading)
                Slider(value: $iconPercent, in: 50...150, step: 5).accessibilityLabel(model.text("图标大小"))
                Text("\(Int(iconPercent.rounded()))%").monospacedDigit().frame(width: 48)
            }
            HStack {
                Text(model.text("文字大小")).frame(width: 80, alignment: .leading)
                Slider(value: $textPercent, in: 80...140, step: 5).accessibilityLabel(model.text("文字大小"))
                Text("\(Int(textPercent.rounded()))%").monospacedDigit().frame(width: 48)
            }
            HStack {
                Spacer()
                Button(model.text("取消")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(model.text("应用更改")) {
                    model.updatePreferences { $0.iconScalePercent = iconPercent; $0.textScalePercent = textPercent }
                    dismiss()
                }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .foregroundStyle(Color(nsColor: .windowBackgroundColor))
            }
        }.font(.system(size: 13)).padding(26).frame(width: 740)
            .tint(model.accentColor)
    }
    private func sample(title: String, preferences: LauncherPreferences) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(model.text(title)).font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("\(Int(preferences.iconScalePercent.rounded()))% / \(Int(preferences.textScalePercent.rounded()))%")
                    .font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 16) {
                ForEach(Array(model.apps.prefix(2))) { app in
                    VStack(spacing: 5) {
                        PreviewAppIcon(model: model, app: app)
                            .frame(width: preferences.iconPoints(fullscreen: model.isFullscreen), height: preferences.iconPoints(fullscreen: model.isFullscreen))
                        Text(app.name).font(LauncherModel.applicationLabelFont(preferences))
                            .foregroundStyle(LauncherModel.applicationLabelColor(preferences))
                            .lineLimit(2).multilineTextAlignment(.center)
                    }.frame(maxWidth: .infinity)
                }
            }.frame(maxWidth: .infinity, minHeight: 200, alignment: .top)
        }.padding(16).frame(maxWidth: .infinity, alignment: .topLeading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.10)))
    }
}

struct PreviewAppIcon: View {
    let model: LauncherModel
    let app: InstalledApp
    @StateObject private var delivery = TileDragFeedback()
    var body: some View {
        Image(nsImage: model.icon(for: app, notifying: delivery)).resizable().interpolation(.high)
    }
}

struct AppearanceLivePreview: View {
    @ObservedObject var model: LauncherModel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        let preferences = model.preferences
        let iconSize = preferences.iconPoints(fullscreen: model.isFullscreen) * 0.72
        let clearBackdrop = preferences.backgroundTransparency > 0.7 && !reduceTransparency
        HStack(spacing: 10) {
            ForEach(Array(model.apps.prefix(3))) { app in
                VStack(spacing: 6) {
                    PreviewAppIcon(model: model, app: app)
                        .frame(width: iconSize, height: iconSize)
                    if preferences.showNames {
                        Text(app.name).font(model.applicationLabelFont).foregroundStyle(model.applicationLabelColor)
                            .lineLimit(1)
                            .shadow(color: clearBackdrop
                                    ? LauncherModel.applicationLabelShadow(color: preferences.labelColor, hex: preferences.labelColorHex) : .clear,
                                    radius: 1, y: 1)
                    }
                }.frame(maxWidth: .infinity)
            }
        }
        .padding(12).frame(maxWidth: .infinity, minHeight: 120)
        .background {
            ZStack {
                if preferences.backgroundStyle == .glass && !reduceTransparency { VisualEffectBackground() }
                Color(nsColor: .windowBackgroundColor)
                    .opacity(preferences.backgroundStyle == .glass && !reduceTransparency ? 1 - preferences.backgroundTransparency : 1)
            }.opacity(reduceTransparency ? 1 : 1 - preferences.backgroundTransparency)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(0.10)))
    }
}
