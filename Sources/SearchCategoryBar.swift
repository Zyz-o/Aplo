import SwiftUI

struct SearchCategoryBar: View {
    @ObservedObject var model: LauncherModel
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 7) {
                chip(model.text("全部"), category: nil)
                ForEach(model.availableSearchCategories, id: \.self) { category in
                    chip(model.text(category.title) + " · \(model.count(for: category))", category: category)
                }
            }.padding(.vertical, 3)
        }.scrollIndicators(.hidden).frame(maxWidth: model.gridWidth)
    }
    private func chip(_ title: String, category: AppCategory?) -> some View {
        Button { model.selectSearchCategory(category) } label: {
            HStack(spacing: 5) {
                if model.searchCategory == category { Image(systemName: "checkmark").font(.caption) }
                Text(title).font(.system(size: model.preferences.textPoints(11), weight: model.searchCategory == category ? .semibold : .regular)).lineLimit(1)
            }.padding(.horizontal, 12).padding(.vertical, 7)
                .background(model.searchCategory == category ? model.accentColor.opacity(0.20) : .primary.opacity(0.055), in: Capsule())
        }.buttonStyle(.plain).accessibilityAddTraits(model.searchCategory == category ? .isSelected : [])
    }
}
