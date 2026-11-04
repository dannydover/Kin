import Foundation
import CoreGraphics

/// The caller establishes this frame in the same coordinate space as the form.
public func preciseFormFrameIsVisible(_ frame: CGRect, lowerBound: CGFloat, upperBound: CGFloat) -> Bool {
    frame.width > 0 && frame.height > 0 && frame.minY >= lowerBound && frame.maxY <= upperBound
}

public enum NativeContactRevealDecision: Equatable {
    case wait, select, scrollUp, scrollDown
}

public struct NativeContactRevealDeadline {
    private let end: TimeInterval
    public init(start: TimeInterval, timeout: TimeInterval) { end = start + timeout }
    public func remaining(now: TimeInterval) -> TimeInterval { max(0, end - now) }
}

/// Pure policy: a second reveal requires observed movement, and selection
/// requires one hittable target whose frame has settled for one second.
public struct NativeContactRevealPolicy {
    public init() {}
    public private(set) var scrolls = 0
    public private(set) var sawUnsettledFrame = false
    private var previousVisibleFrame: CGRect?
    private var stableSince: TimeInterval = 0
    private var lastScrolledFrame: CGRect?

    private func differs(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) > 0.5 || abs(a.minY - b.minY) > 0.5
            || abs(a.width - b.width) > 0.5 || abs(a.height - b.height) > 0.5
    }

    public mutating func observe(candidateCount: Int, visibleCount: Int, visibleFrame: CGRect?,
                          soleFrame: CGRect?, lowerBound: CGFloat, now: TimeInterval) -> NativeContactRevealDecision {
        if visibleCount == 1, let frame = visibleFrame {
            if previousVisibleFrame == nil || differs(frame, previousVisibleFrame!) {
                previousVisibleFrame = frame; stableSince = now; sawUnsettledFrame = true
                return .wait
            }
            if now - stableSince < 1 { sawUnsettledFrame = true; return .wait }
            return .select
        }
        previousVisibleFrame = nil
        guard visibleCount == 0, candidateCount == 1, let frame = soleFrame, scrolls < 16 else { return .wait }
        if let previous = lastScrolledFrame, !differs(frame, previous) { return .wait }
        return frame.maxY > lowerBound ? .scrollUp : .scrollDown
    }

    public mutating func didScroll(from frame: CGRect) {
        lastScrolledFrame = frame
        scrolls += 1
    }
}

public enum SyntheticCardResolution: Equatable {
    case absent, unique, ambiguous
}

public func syntheticCardResolution(_ count: Int) -> SyntheticCardResolution {
    if count == 0 { return .absent }
    return count == 1 ? .unique : .ambiguous
}

