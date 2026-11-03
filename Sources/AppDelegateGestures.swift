import AppKit
import Carbon
import SwiftUI
import QuartzCore
import UniformTypeIdentifiers

extension AppDelegate {
    func resetPageMotion() {
        pagingToken = UUID()
        gestureEndWork?.cancel()
        gestureEndWork = nil
        gestureStarted = false
        pageGesture = PageGesture()
        pendingPageTarget = nil
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction) { model.pageDragOffset = 0; model.pageTransitionActive = false }
    }

    func settlePageMotion(cancelled: Bool = false, explicitDelta: Int? = nil) {
        gestureEndWork?.cancel()
        gestureStarted = false
        let target = explicitDelta.map { min(max(0, model.pageIndex + $0), model.pageCount - 1) }
            ?? PageMotion.destination(distance: pageGesture.distance, page: model.pageIndex,
                                      count: model.pageCount, width: model.pageExtent, cancelled: cancelled, velocity: pageGesture.velocity)
        let direction = target - model.pageIndex
        let finalOffset = -CGFloat(direction) * model.pageExtent
        let token = UUID(); pagingToken = token
        model.pageTransitionActive = true
        pendingPageTarget = target
        let remaining = abs(finalOffset - model.pageDragOffset) / model.pageExtent
        let duration = preview && CommandLine.arguments.contains("--slow-page-animation") ? 2.0
            : min(0.36, max(0.24, 0.34 * Double(remaining)))
        let animated = model.preferences.animationsEnabled && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let finish: @MainActor @Sendable () -> Void = { [weak self] in
            guard let self, self.pagingToken == token else { return }
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) {
                self.model.goToPage(target)
                self.model.pageDragOffset = 0
                self.model.pageTransitionActive = false
            }
            self.pageGesture = PageGesture()
            self.pendingPageTarget = nil
        }
        if animated {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86, blendDuration: 0.05)) { model.pageDragOffset = finalOffset }
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05, execute: finish)
        } else { finish() }
    }

    func finishPendingPage() {
        if let target = pendingPageTarget {
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) { model.goToPage(target) }
        }
        resetPageMotion()
    }

    func configureGestures() {
        gestureMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .swipe]) { [weak self] event in
            guard let self else { return event }
            if event.type == .scrollWheel, event.window === self.panel {
                self.model.noteScrollInteraction()
            }
            // Keep precision vertical scrolling on AppKit's original event and momentum path.
            if event.type == .scrollWheel, event.hasPreciseScrollingDeltas,
               self.model.isContinuousScrolling, self.model.navigationDirection == .vertical { return event }
            if event.phase.contains(.began) { self.continuousScrollScaler.reset() }
            if self.panel.isKeyWindow, !self.model.showingSettings, !self.presentingSystemDialog,
               self.model.isContinuousScrolling, event.type == .scrollWheel,
               let source = event.cgEvent, let copy = self.continuousScrollScaler.adjusted(source, factor: self.model.preferences.gestureSensitivity) {
                return NSEvent(cgEvent: copy) ?? event
            }
            guard self.panel.isKeyWindow, !self.model.showingSettings,
                  !self.model.isContinuousScrolling, !self.model.usesFreePlacement,
                  self.model.preferences.swipeEnabled, self.model.draggingID == nil,
                  !self.presentingSystemDialog, self.model.pageCount > 1 else { return event }
            let preferences = self.model.preferences
            let horizontal = self.model.navigationDirection == .horizontal
            if event.type == .swipe {
                // The same trackpad gesture may also produce a swipe event after scroll-ended.
                guard !self.model.pageTransitionActive, !self.gestureStarted else { return nil }
                guard (horizontal ? abs(event.deltaX) >= abs(event.deltaY) : abs(event.deltaY) >= abs(event.deltaX)),
                      let delta = preferences.horizontalPageDelta(Double(horizontal ? event.deltaX : event.deltaY)) else { return event }
                self.resetPageMotion()
                self.model.pageMotion.axis = horizontal ? .horizontal : .vertical
                self.settlePageMotion(explicitDelta: delta)
                return nil
            }
            if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
                guard self.gestureStarted else { self.pageGesture = PageGesture(); return event }
                self.settlePageMotion(cancelled: event.phase.contains(.cancelled))
                return nil
            }
            // Some devices enter momentum without a separate finger-release event.
            if !event.momentumPhase.isEmpty {
                if self.gestureStarted { self.settlePageMotion() }
                return nil
            }
            let x = event.scrollingDeltaX, y = event.scrollingDeltaY
            guard x != 0 || y != 0 else { return event }
            if !event.hasPreciseScrollingDeltas {
                guard horizontal ? abs(x) >= abs(y) : abs(y) >= abs(x) else { return event }
                guard event.timestamp - self.lastDiscretePageTime > 0.14,
                      let delta = preferences.horizontalPageDelta(Double(horizontal ? x : y)) else { return nil }
                self.lastDiscretePageTime = event.timestamp
                self.finishPendingPage()
                self.model.pageMotion.axis = horizontal ? .horizontal : .vertical
                self.settlePageMotion(explicitDelta: delta)
                return nil
            }
            if event.phase.contains(.began) || (!self.gestureStarted && self.pendingPageTarget != nil) {
                // Complete the preceding page before accepting a rapid reverse gesture.
                self.finishPendingPage()
            }
            guard self.pageGesture.sample(x: x, y: y, time: event.timestamp,
                    verticalEnabled: true,
                    sensitivity: preferences.gestureSensitivity, reversed: preferences.reversePaging,
                    preferredAxis: horizontal ? .horizontal : .vertical) else { return event }
            let axis: PagePresentation.Axis = self.pageGesture.axis == .vertical ? .vertical : .horizontal
            if self.model.pageMotion.axis != axis { self.model.pageMotion.axis = axis }
            self.gestureStarted = true
            self.model.pageTransitionActive = true
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) {
                self.model.pageDragOffset = PageMotion.offset(distance: self.pageGesture.distance,
                    page: self.model.pageIndex, count: self.model.pageCount, width: self.model.pageExtent)
            }
            self.gestureEndWork?.cancel()
            // Devices without gesture phases get a short inactivity fallback, never momentum-length waiting.
            if event.phase.isEmpty {
                let work = DispatchWorkItem { [weak self] in self?.settlePageMotion() }
                self.gestureEndWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.045, execute: work)
            }
            return nil
        }
    }
}
