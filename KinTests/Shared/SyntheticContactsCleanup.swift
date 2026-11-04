import Foundation
import CoreGraphics

/// Shared by test targets only. Callers supply the identifiers and operations;
/// this primitive has no Contacts access and never discovers unrelated items.
public enum SyntheticContactsCleanupError: Error, Equatable {
    case invalidIdentifiers
    case remainingOwnedContacts
    case cleanupFailed
    case creationUncertain
}

public func verifyOwnedFixtureCleanup<Item>(
    _ items: [Item], identifier: (Item) -> String,
    remove: ([Item]) throws -> Void,
    remainingIdentifiers: ([String]) throws -> [String], creationUncertain: Bool = false
) throws {
    if items.isEmpty {
        if creationUncertain { throw SyntheticContactsCleanupError.creationUncertain }
        return
    }
    let ids = items.map(identifier)
    guard ids.allSatisfy({ !$0.isEmpty }), Set(ids).count == ids.count else {
        throw SyntheticContactsCleanupError.invalidIdentifiers
    }
    try remove(items)
    // The adapter must query only the identifiers owned by this test.
    guard try remainingIdentifiers(ids).isEmpty else {
        throw SyntheticContactsCleanupError.remainingOwnedContacts
    }
    if creationUncertain { throw SyntheticContactsCleanupError.creationUncertain }
}

// Shared native picker test policy; no production target includes this file.
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

