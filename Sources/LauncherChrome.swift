import AppKit
import SwiftUI

struct MessageBanner: View {
    @ObservedObject var model: LauncherModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
      Group {
        if let message = model.message {
            HStack(spacing: 5) {
                if model.importInProgress { ProgressView().controlSize(.small) }
                else { Image(systemName: "info.circle") }
                Text(message.localized(language: model.preferences.language)).lineLimit(2)
                Spacer(minLength: 0)
                if model.importInProgress {
                    Button(model.text("取消导入")) { model.onCancelImport?() }.buttonStyle(.plain)
                } else { Button { model.message = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).accessibilityLabel(model.text("关闭提示")) }
            }.font(.system(size: model.preferences.textPoints(11))).foregroundStyle(.primary)
                .padding(9).background(model.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                .padding(.bottom, 6)
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
        }
      }.animation(model.preferences.animationsEnabled && !reduceMotion ? .easeInOut(duration: LauncherGeometry.messageTransitionDuration) : nil, value: model.message)

    }
}

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

final class LauncherTextField: NSTextField {
    var pendingFocus: (@MainActor @Sendable () -> Void)?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in self?.pendingFocus?() }
    }
}

struct NativeInput: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let focusGeneration: Int
    let identifier: String
    var requestsFocus = true
    var language: LauncherLanguage = .system
    var textScale = 1.0
    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }
    func makeNSView(context: Context) -> NSTextField {
        let field = LauncherTextField(string: text)
        field.placeholderString = AppStrings.text(placeholder, language: language)
        field.font = NSFont.systemFont(ofSize: (identifier == "folder-title" ? 17 : 15) * textScale)
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = context.coordinator
        field.identifier = NSUserInterfaceItemIdentifier(identifier)
        field.setAccessibilityLabel(AppStrings.text(identifier == "folder-title" ? "文件夹名称" : "搜索应用", language: language))
        return field
    }
    func updateNSView(_ field: NSTextField, context: Context) {
        field.font = NSFont.systemFont(ofSize: (identifier == "folder-title" ? 17 : 15) * textScale)
        field.placeholderString = AppStrings.text(placeholder, language: language)
        field.setAccessibilityLabel(AppStrings.text(identifier == "folder-title" ? "文件夹名称" : "搜索应用", language: language))
        context.coordinator.text = $text
        if field.stringValue != text { field.stringValue = text }
        if requestsFocus && context.coordinator.generation != focusGeneration {
            let coordinator = context.coordinator
            let expectedGeneration = focusGeneration
            let selectAll = identifier == "folder-title"
            let focus: @MainActor @Sendable () -> Void = { [weak field, weak coordinator] in
                guard let field, let coordinator, coordinator.generation != expectedGeneration,
                      let window = field.window, window.isVisible else { return }
                guard window.makeFirstResponder(field) else { return }
                coordinator.generation = expectedGeneration
                (field as? LauncherTextField)?.pendingFocus = nil
                if let editor = field.currentEditor() {
                    (editor as? NSTextView)?.allowsUndo = true
                    editor.selectedRange = selectAll ? NSRange(location: 0, length: field.stringValue.utf16.count)
                        : NSRange(location: field.stringValue.utf16.count, length: 0)
                }
            }
            (field as? LauncherTextField)?.pendingFocus = focus
            DispatchQueue.main.async(execute: focus)
        } else if !requestsFocus {
            (field as? LauncherTextField)?.pendingFocus = nil
        }
    }
    @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var generation: Int?
        init(text: Binding<String>) { self.text = text }
        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSTextField { text.wrappedValue = field.stringValue }
        }
    }
}


struct PageStrip<Content: View>: View {
    @ObservedObject var motion: PagePresentation
    let size: CGSize
    let content: Content
    init(motion: PagePresentation, size: CGSize, @ViewBuilder content: () -> Content) {
        self.motion = motion; self.size = size; self.content = content()
    }
    var body: some View {
        // Rasterize the page strip once, then translate the finished layer. Applying the
        // group before the offset keeps the drag a GPU transform instead of re-rendering
        // every tile's shadows and materials on each frame of the gesture.
        content.compositingGroup()
            .offset(x: motion.axis == .horizontal ? motion.offset : 0,
                    y: motion.axis == .vertical ? motion.offset : 0)
            .allowsHitTesting(!motion.active)
    }
}

struct PageInteractionLock<Content: View>: View {
    @ObservedObject var motion: PagePresentation
    let content: Content
    init(motion: PagePresentation, @ViewBuilder content: () -> Content) {
        self.motion = motion; self.content = content()
    }
    var body: some View { content.disabled(motion.active).allowsHitTesting(!motion.active) }
}
