import Foundation
import CoreGraphics

/// The canvas already renders two tiles beyond the viewport. Keep that window
/// stable across small scroll deltas instead of rebuilding SwiftUI every pixel.
struct CanvasViewportGate {
    private var published: CGRect?
    private var previousTile: CGSize?
    mutating func shouldPublish(_ rect: CGRect, tile: CGSize) -> Bool {
        guard !rect.isEmpty, rect.origin.x.isFinite, rect.origin.y.isFinite else { return false }
        if previousTile == tile, let previous = published, previous.size == rect.size,
           abs(previous.minX - rect.minX) < max(1, tile.width * 0.75),
           abs(previous.minY - rect.minY) < max(1, tile.height * 0.75) { return false }
        published = rect
        previousTile = tile
        return true
    }
}

enum PageMotion {
    static func origin(relativePage: Int, size: CGSize, vertical: Bool) -> CGPoint {
        vertical ? CGPoint(x: 0, y: CGFloat(relativePage) * size.height)
                 : CGPoint(x: CGFloat(relativePage) * size.width, y: 0)
    }
    static func offset(distance: CGFloat, page: Int, count: Int, width: CGFloat) -> CGFloat {
        let width = max(1, width)
        let bounded = min(width, max(-width, distance))
        if (page <= 0 && bounded > 0) || (page >= count - 1 && bounded < 0) { return bounded * 0.22 }
        return bounded
    }
    static func destination(distance: CGFloat, page: Int, count: Int, width: CGFloat, cancelled: Bool = false, velocity: CGFloat = 0) -> Int {
        guard !cancelled, count > 1, distance.isFinite, velocity.isFinite else { return page }
        // Short, quick flicks count; slow accidental movement does not.
        let projection = abs(distance) >= 14 ? min(240, max(-240, velocity)) * 0.12 : 0
        let projected = distance + projection
        guard abs(projected) >= min(64, max(36, width * 0.065)) else { return page }
        return min(max(0, page + (projected < 0 ? 1 : -1)), count - 1)
    }
}


/// Locks the dominant axis for an entire gesture, avoiding diagonal direction changes.
struct PageGesture {
    enum Axis { case horizontal, vertical }
    private(set) var axis: Axis?
    private(set) var distance: CGFloat = 0
    private(set) var velocity: CGFloat = 0
    private var pendingX: CGFloat = 0
    private var pendingY: CGFloat = 0
    private var previousTime: TimeInterval?

    mutating func sample(x: CGFloat, y: CGFloat, time: TimeInterval,
                         verticalEnabled: Bool, sensitivity: Double, reversed: Bool, preferredAxis: Axis? = nil) -> Bool {
        guard x.isFinite, y.isFinite, time.isFinite, sensitivity.isFinite else { return false }
        let gain = CGFloat(min(2.4, max(0.8, sensitivity))) * (reversed ? -1 : 1)
        var delta: CGFloat
        if axis == nil {
            pendingX += x; pendingY += y
            guard max(abs(pendingX), abs(pendingY)) >= 2 else { return false }
            axis = abs(pendingX) >= abs(pendingY) ? .horizontal : .vertical
            delta = axis == .horizontal ? pendingX : pendingY
        } else { delta = axis == .horizontal ? x : y }
        guard axis != .vertical || verticalEnabled else { return false }
        guard preferredAxis == nil || axis == preferredAxis else { return false }
        delta *= gain
        if let previousTime, time > previousTime {
            let elapsed = max(0.004, time - previousTime)
            // Stale velocity cannot turn a slow release into a flick.
            velocity = elapsed < 0.10 ? delta / CGFloat(elapsed) : 0
        }
        previousTime = time
        distance += delta
        return true
    }
}

/// Copy only scroll deltas; the native event's phase, momentum and timing stay intact.
struct ContinuousScrollSensitivity {
    private var residuals: [CGEventField: Double] = [:]
    private var signs: [CGEventField: Double] = [:]
    private var previousFactor: Double?
    mutating func reset() { residuals.removeAll(keepingCapacity: true); signs.removeAll(keepingCapacity: true) }
    static let deltaFields: [CGEventField] = [.scrollWheelEventDeltaAxis1, .scrollWheelEventDeltaAxis2,
        .scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis2,
        .scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2]
    mutating func adjusted(_ event: CGEvent, factor: Double) -> CGEvent? {
        guard factor.isFinite, factor > 0, let copy = event.copy() else { return nil }
        if previousFactor != factor { reset(); previousFactor = factor }
        for field in Self.deltaFields {
            let original = event.getDoubleValueField(field)
            guard original != 0 else { continue }
            if field == .scrollWheelEventFixedPtDeltaAxis1 || field == .scrollWheelEventFixedPtDeltaAxis2 {
                copy.setDoubleValueField(field, value: original * factor)
                continue
            }
            let sign = original.sign == .minus ? -1.0 : 1.0
            if signs[field] != sign { residuals[field] = 0; signs[field] = sign }
            let exact = original * factor + (residuals[field] ?? 0)
            let quantized = exact.rounded()
            residuals[field] = exact - quantized
            copy.setDoubleValueField(field, value: quantized)
        }
        return copy
    }
}
