import Foundation
import CoreGraphics

@main struct PageMotionTests {
    static func main() {
        var checks = 0
        func expect(_ result: Bool, _ label: String) { precondition(result, label); checks += 1; print("PASS: " + label) }
        expect(PageMotion.offset(distance: -80, page: 1, count: 3, width: 600) == -80, "neighbor pages follow the horizontal displacement")
        expect(PageMotion.destination(distance: -140, page: 1, count: 3, width: 600) == 2, "sufficient leftward movement advances one page")
        expect(PageMotion.destination(distance: 140, page: 1, count: 3, width: 600) == 0, "sufficient rightward movement goes back one page")
        expect(PageMotion.destination(distance: -20, page: 1, count: 3, width: 600) == 1, "short movement snaps back to the current page")
        expect(PageMotion.destination(distance: -300, page: 1, count: 3, width: 600, cancelled: true) == 1, "cancelled gestures cannot change pages")
        expect(PageMotion.offset(distance: 100, page: 0, count: 3, width: 600) == 22, "the first-page boundary has reduced movement")
        expect(PageMotion.destination(distance: 300, page: 0, count: 3, width: 600) == 0, "the first page cannot slide into an empty page")
        expect(PageMotion.destination(distance: -300, page: 2, count: 3, width: 600) == 2, "the last page cannot slide into an empty page")
        expect(PageMotion.offset(distance: -900, page: 0, count: 3, width: 600) == -600, "movement is limited to an adjacent page")
        expect(PageMotion.destination(distance: -35, page: 1, count: 3, width: 912, velocity: -900) == 2, "short fast flick advances without waiting for a long drag")
        expect(PageMotion.destination(distance: -10, page: 1, count: 3, width: 912, velocity: -900) == 1, "tiny accidental flicks stay on the current page")
        expect(PageMotion.destination(distance: -65, page: 1, count: 3, width: 912) == 2, "slow gestures need less distance than the previous threshold")
        var horizontal = PageGesture()
        expect(horizontal.sample(x: -10, y: -3, time: 1, verticalEnabled: true, sensitivity: 1.6, reversed: false), "horizontal gesture starts immediately after axis selection")
        _ = horizontal.sample(x: -4, y: -30, time: 1.016, verticalEnabled: true, sensitivity: 1.6, reversed: false)
        expect(horizontal.axis == .horizontal && abs(horizontal.distance + 22.4) < 0.001, "diagonal motion cannot switch the locked axis")
        var vertical = PageGesture()
        _ = vertical.sample(x: 1, y: -30, time: 2, verticalEnabled: true, sensitivity: 1.6, reversed: false)
        expect(vertical.axis == .vertical && vertical.distance == -48, "upward gestures drive next-page movement with sensitivity")
        var disabled = PageGesture()
        expect(!disabled.sample(x: 1, y: -30, time: 2, verticalEnabled: false, sensitivity: 1.6, reversed: false), "disabled vertical paging leaves ordinary scrolling available")
        var reversed = PageGesture()
        _ = reversed.sample(x: 0, y: -30, time: 2, verticalEnabled: true, sensitivity: 1.6, reversed: true)
        expect(reversed.distance == 48, "reverse preference also applies to vertical gestures")
        _ = horizontal.sample(x: -3, y: 0, time: 3, verticalEnabled: true, sensitivity: 1.6, reversed: false)
        expect(horizontal.velocity == 0, "pausing clears stale flick velocity")
        var invalid = PageGesture()
        expect(!invalid.sample(x: .nan, y: 0, time: 1, verticalEnabled: true, sensitivity: 1.6, reversed: false), "invalid trackpad deltas cannot corrupt the page position")
        expect(PageMotion.offset(distance: -800, page: 1, count: 3, width: 420) == -420, "vertical page motion is bounded by its shorter viewport height")
        let size = CGSize(width: 912, height: 460)
        let above = PageMotion.origin(relativePage: -1, size: size, vertical: true)
        let current = PageMotion.origin(relativePage: 0, size: size, vertical: true)
        let below = PageMotion.origin(relativePage: 1, size: size, vertical: true)
        expect(above.y + size.height == current.y && current.y + size.height == below.y, "three vertical pages share exact edges without stack compression or gaps")
        let displacement: CGFloat = -size.height / 2
        expect(current.y + displacement + size.height == below.y + displacement, "current and next page remain joined halfway through an upward transition")
        expect(above.y - displacement + size.height == current.y - displacement, "previous and current page remain joined halfway through a downward transition")
        expect(PageMotion.origin(relativePage: 1, size: size, vertical: false) == CGPoint(x: 912, y: 0), "horizontal paging keeps the neighboring page to the right")
        var horizontalOnly = PageGesture()
        expect(!horizontalOnly.sample(x: 1, y: -30, time: 1, verticalEnabled: true, sensitivity: 1.6, reversed: false, preferredAxis: .horizontal), "horizontal mode does not silently switch into vertical paging")
        var verticalOnly = PageGesture()
        expect(!verticalOnly.sample(x: -30, y: 1, time: 1, verticalEnabled: true, sensitivity: 1.6, reversed: false, preferredAxis: .vertical), "vertical mode does not silently switch into horizontal paging")
        let scroll = CGEvent(source: nil)!
        scroll.type = .scrollWheel
        for field in ContinuousScrollSensitivity.deltaFields { scroll.setDoubleValueField(field, value: 10) }
        scroll.setIntegerValueField(.scrollWheelEventScrollPhase, value: 4)
        scroll.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 2)
        scroll.timestamp = 123456
        var scaler = ContinuousScrollSensitivity()
        let fast = scaler.adjusted(scroll, factor: 2.4)!
        expect(ContinuousScrollSensitivity.deltaFields.allSatisfy { fast.getDoubleValueField($0) == 24 }, "continuous sensitivity scales both axes and all native delta representations")
        expect(fast.getIntegerValueField(.scrollWheelEventScrollPhase) == 4 && fast.getIntegerValueField(.scrollWheelEventMomentumPhase) == 2 && fast.timestamp == scroll.timestamp, "continuous sensitivity retains native scroll phase, momentum and timestamp")
        expect(scroll.getDoubleValueField(.scrollWheelEventPointDeltaAxis1) == 10, "sensitivity does not mutate the original event")
        expect(scaler.adjusted(scroll, factor: .nan) == nil, "invalid sensitivity cannot create an invalid native scroll event")
        let fineScroll = CGEvent(source: nil)!
        fineScroll.type = .scrollWheel
        fineScroll.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: 1)
        fineScroll.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 1)
        let fineFixed = scaler.adjusted(fineScroll, factor: 0.8)!.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        expect(abs(fineFixed - 0.8) < 0.0001, "fixed-point scroll representations retain subpixel precision")
        scaler.reset()
        var pixels = 0.0
        for _ in 0..<10 { pixels += scaler.adjusted(fineScroll, factor: 0.8)!.getDoubleValueField(.scrollWheelEventPointDeltaAxis1) }
        expect(pixels == 8, "fractional low-speed scroll input accumulates without dropping sensitivity distance")
        fineScroll.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: -1)
        expect(scaler.adjusted(fineScroll, factor: 0.8)!.getDoubleValueField(.scrollWheelEventPointDeltaAxis1) == -1, "direction reversal responds immediately without stale fractional carry")
        fineScroll.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: 0)
        expect(scaler.adjusted(fineScroll, factor: 0.8)!.getDoubleValueField(.scrollWheelEventPointDeltaAxis1) == 0, "zero-delta phase events cannot create unwanted scroll motion")
        var viewportGate = CanvasViewportGate()
        let tile = CGSize(width: 100, height: 120)
        var publishedRect = CGRect.zero
        var updates = 0
        var covered = true
        for pixel in 0..<1200 {
            let rect = CGRect(x: 0, y: pixel, width: 900, height: 600)
            if viewportGate.shouldPublish(rect, tile: tile) { publishedRect = rect; updates += 1 }
            covered = covered && publishedRect.insetBy(dx: -tile.width * 2, dy: -tile.height * 2).contains(rect)
        }
        expect(covered && updates < 20, "pixel scrolling stays inside preloaded content without rebuilding each frame")
        expect(viewportGate.shouldPublish(CGRect(x: 5000, y: 9000, width: 900, height: 600), tile: tile), "large scroll jumps immediately refresh the visible canvas")
        expect(viewportGate.shouldPublish(CGRect(x: 5000, y: 9000, width: 1200, height: 800), tile: tile), "fullscreen resize immediately refreshes the visible canvas")
        expect(viewportGate.shouldPublish(CGRect(x: 4800, y: 9000, width: 1200, height: 800), tile: tile), "horizontal reverse scrolling refreshes before preload runs out")
        expect(!viewportGate.shouldPublish(.zero, tile: tile), "temporary empty viewports cannot replace valid preloaded content")
        expect(viewportGate.shouldPublish(CGRect(x: 4800, y: 9000, width: 1200, height: 800), tile: CGSize(width: 40, height: 60)), "icon resizing refreshes the preload window even when viewport size is unchanged")
        print("All \(checks) continuous-paging checks passed.")
    }
}
