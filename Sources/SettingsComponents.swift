import AppKit
import SwiftUI

struct SettingsSidebar: View {
    let model: LauncherModel
    let appIcon: NSImage
    @Binding var category: SettingsCategory
    @Binding var query: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(nsImage: appIcon).resizable().frame(width: 24, height: 24)
                    .accessibilityHidden(true)
                Text("Aplo").font(.system(size: model.preferences.textPoints(15), weight: .semibold))
            }.padding(.horizontal, 6)
            TextField(model.text("搜索设置"), text: $query).textFieldStyle(.roundedBorder)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(SettingsCategory.allCases, id: \.self) { section in
                        Button {
                            if model.recordingShortcut { model.cancelRecording() }
                            category = section
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: section.icon)
                                    .frame(width: 18)
                                    .foregroundStyle(section == category ? model.accentColor : .secondary)
                                Text(model.text(section.title))
                                    .fontWeight(section == category ? .semibold : .regular)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .font(.system(size: model.preferences.textPoints(13)))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(section == category ? model.accentColor.opacity(0.14) : .clear,
                                        in: RoundedRectangle(cornerRadius: 7))
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .accessibilityLabel(model.text(section.title) + " · " + model.text("设置"))
                            .accessibilityAddTraits(category == section ? .isSelected : [])
                    }
                }
            }.scrollIndicators(.automatic)
            Text(model.text("设置自动保存"))
                .font(.system(size: model.preferences.textPoints(10)))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
        }
        .padding(12)
        .frame(width: 196)
        .frame(maxHeight: .infinity)
        .background(.primary.opacity(0.025))
    }
}

struct SettingsGroup<Content: View>: View {
    let title: String
    let icon: String
    let model: LauncherModel
    let highlighted: Bool
    let enclosed: Bool
    let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(model.text(title), systemImage: icon)
                .font(.system(size: model.preferences.textPoints(14), weight: .semibold))
            Divider()
            content.font(.system(size: model.preferences.textPoints(12)))
        }
        .padding(enclosed ? 12 : 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(enclosed ? Color(nsColor: .controlBackgroundColor) : .clear,
                    in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(highlighted ? model.accentColor : .clear, lineWidth: 2))
        .id(title)
    }
}
