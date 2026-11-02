import XCTest

/// The caller establishes this frame in the same coordinate space as the form.
func preciseFormFrameIsVisible(_ frame: CGRect, lowerBound: CGFloat, upperBound: CGFloat) -> Bool {
    frame.width > 0 && frame.height > 0 && frame.minY >= lowerBound && frame.maxY <= upperBound
}

enum NativeContactRevealDecision: Equatable {
    case wait, select, scrollUp, scrollDown
}

struct NativeContactRevealDeadline {
    private let end: TimeInterval
    init(start: TimeInterval, timeout: TimeInterval) { end = start + timeout }
    func remaining(now: TimeInterval) -> TimeInterval { max(0, end - now) }
}

/// Pure policy: a second reveal requires observed movement, and selection
/// requires one hittable target whose frame has settled for one second.
struct NativeContactRevealPolicy {
    private(set) var scrolls = 0
    private(set) var sawUnsettledFrame = false
    private var previousVisibleFrame: CGRect?
    private var stableSince: TimeInterval = 0
    private var lastScrolledFrame: CGRect?

    private func differs(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) > 0.5 || abs(a.minY - b.minY) > 0.5
            || abs(a.width - b.width) > 0.5 || abs(a.height - b.height) > 0.5
    }

    mutating func observe(candidateCount: Int, visibleCount: Int, visibleFrame: CGRect?,
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

    mutating func didScroll(from frame: CGRect) {
        lastScrolledFrame = frame
        scrolls += 1
    }
}

enum SyntheticCardResolution: Equatable {
    case absent, unique, ambiguous
}

func syntheticCardResolution(_ count: Int) -> SyntheticCardResolution {
    if count == 0 { return .absent }
    return count == 1 ? .unique : .ambiguous
}

/// Resolve one exact synthetic card; never select an arbitrary duplicate.
@MainActor func requireSyntheticContactCard(_ app: XCUIApplication, name: String) throws -> XCUIElement {
    let cards = app.cells.containing(.staticText, identifier: name)
    let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
        syntheticCardResolution(cards.count) != .absent
    }, object: nil)
    let outcome = XCTWaiter.wait(for: [ready], timeout: 5)
    let resolution = syntheticCardResolution(cards.count)
    guard outcome == .completed, resolution == .unique else {
        XCTFail("Expected exactly one synthetic Contacts card; none or multiple were found")
        throw SyntheticCardSelectionError.unavailable
    }
    let card = cards.element
    guard card.isHittable else {
        XCTFail("The unique synthetic Contacts card is not visible and hittable")
        throw SyntheticCardSelectionError.unavailable
    }
    return card
}

private enum SyntheticCardSelectionError: Error { case unavailable }

/// Require both sides of a dismissal before interacting with the destination.
/// A background screen may already exist while a sheet still owns the tap.
@MainActor func requireDismissal(_ source: XCUIElement, destination: XCUIElement,
                                 file: StaticString = #filePath, line: UInt = #line) {
    var lastSource: Bool?
    var lastDestination: Bool?
    var lastHittable: Bool?
    let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
        let sourceExists = source.exists
        lastSource = sourceExists; lastDestination = nil; lastHittable = nil
        guard !sourceExists else { return false }
        let destinationExists = destination.exists
        lastDestination = destinationExists
        guard destinationExists else { return false }
        let destinationHittable = destination.isHittable
        lastHittable = destinationHittable
        return destinationHittable
    }, object: nil)
    let result = XCTWaiter.wait(for: [ready], timeout: 5)
    if result != .completed {
        func text(_ value: Bool?) -> String { value.map(String.init) ?? "not observed" }
        let state = "sourceExists=\(text(lastSource)); destinationExists=\(text(lastDestination)); destinationHittable=\(text(lastHittable))"
        XCTContext.runActivity(named: "Screen dismissal readiness") { activity in
            let attachment = XCTAttachment(string: state)
            attachment.name = "Synthetic dismissal state"
            attachment.lifetime = .keepAlways
            activity.add(attachment)
        }
    }
    XCTAssertEqual(result, .completed, "Dismissed screen must close and destination must be usable", file: file, line: line)
}

/// Time only the system Contacts picker readiness check. The downstream
/// selection and import assertions still determine whether the flow works.
@MainActor func waitForNativeContactsPicker(_ app: XCUIApplication) -> Bool {
    let start = ProcessInfo.processInfo.systemUptime
    let ready = app.navigationBars["Contacts"].waitForExistence(timeout: 30)
    let elapsed = ProcessInfo.processInfo.systemUptime - start
    let measurement = String(format: "Contacts readiness wait: %.3f seconds; ready: %@", elapsed, ready ? "yes" : "no")
    print(measurement)
    XCTContext.runActivity(named: "Native Contacts readiness timing") { activity in
        let attachment = XCTAttachment(string: measurement)
        attachment.name = "Synthetic Contacts readiness timing"
        attachment.lifetime = .keepAlways
        activity.add(attachment)
    }
    return ready
}

/// Resolve the one hittable native search field before activating it. The
/// picker can retain offscreen search fields from an earlier presentation.
/// A unique visible field is a precondition, not proof of keyboard focus;
/// the caller must still perform typing and assert the exact search result.
@MainActor func requireNativeContactsSearch(_ app: XCUIApplication) throws -> XCUIElement {
    let searches = app.searchFields.matching(identifier: "Search")
    var chosen: XCUIElement?
    var lastCounts: (total: Int, inBounds: Int, hittable: Int)?
    let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
        let elements = searches.allElementsBoundByIndex
        var inBounds = 0
        let candidates = elements.filter {
            let frame = $0.frame
            guard frame.minY >= 62 && frame.maxY <= app.frame.maxY - 30 else { return false }
            inBounds += 1
            return $0.isHittable
        }
        lastCounts = (elements.count, inBounds, candidates.count)
        guard candidates.count == 1 else { return false }
        chosen = candidates[0]
        return true
    }, object: nil)
    let outcome = XCTWaiter.wait(for: [ready], timeout: 5)
    if outcome != .completed {
        // Fixed aggregate counts only; do not capture labels, contact data,
        // coordinates, or issue any additional accessibility queries on failure.
        let counts = lastCounts.map { "total=\($0.total); inBounds=\($0.inBounds); hittableInBounds=\($0.hittable)" } ?? "counts=unavailable"
        XCTContext.runActivity(named: "Synthetic Contacts search readiness") { activity in
            let attachment = XCTAttachment(string: counts)
            attachment.name = "Synthetic Contacts search aggregate state"
            attachment.lifetime = .keepAlways
            activity.add(attachment)
        }
    }
    XCTAssertEqual(outcome, .completed,
                   "Require one visible native Contacts search field")
    return try XCTUnwrap(chosen)
}

/// Preserve the immediate switch assertion while collecting a bounded,
/// synthetic-only follow-up state if it fails. Never tap the control again.
@MainActor func assertSwitchImmediatelyOn(_ element: XCUIElement, in app: XCUIApplication,
                                         file: StaticString = #filePath, line: UInt = #line) {
    let initial = element.value as? String
    if initial != "1" {
        let laterOn = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            element.value as? String == "1"
        }, object: nil)
        _ = XCTWaiter.wait(for: [laterOn], timeout: 5)
        let later = element.value as? String
        func state(_ value: String?) -> String {
            value == "1" ? "on" : value == "0" ? "off" : "unknown"
        }
        let description = "initial=\(state(initial)) later=\(state(later))"
        XCTContext.runActivity(named: "Synthetic switch failure observation") { activity in
            let attachment = XCTAttachment(string: description)
            attachment.name = "Synthetic switch immediate and later state"
            attachment.lifetime = .keepAlways
            activity.add(attachment)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Synthetic switch state after failed immediate assertion"
            screenshot.lifetime = .keepAlways
            activity.add(screenshot)
        }
    }
    XCTAssertEqual(initial, "1", file: file, line: line)
}

/// Reveal the actual shared-editor control after deliberate section reordering.
/// Lazy form rows need bounded scrolling before hierarchy uniqueness assertions.
@MainActor func editorSwitchWrapper(_ identifier: String, in app: XCUIApplication, scrollStep: CGFloat? = nil) -> XCUIElement {
    let element = app.switches[identifier]
    if #unavailable(iOS 27.0), app.keyboards.firstMatch.exists {
        // iOS26 keyboard geometry excludes its predictive bar. Finish text
        // entry using the captured native Return action before form scrolling.
        let finishEntry = app.keyboards.firstMatch.buttons["Return"]
        XCTAssertTrue(finishEntry.exists && finishEntry.isHittable)
        finishEntry.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
    }
    func scroll(up: Bool) {
        guard let scrollStep else {
            if up { app.swipeUp() } else { app.swipeDown() }
            return
        }
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5,dy: 0.55))
        let end = start.withOffset(CGVector(dx: 0,dy: up ? -scrollStep : scrollStep))
        start.press(forDuration: 0.05,thenDragTo: end)
    }
    for _ in 0..<16 {
        if element.exists {
            let frame = element.frame
            if element.isHittable && frame.minY >= 140 && frame.maxY <= app.frame.maxY - 80 { return element }
            if frame.height > 0 && frame.minY < 140 { scroll(up: false); continue }
        }
        scroll(up: true)
    }
    XCTContext.runActivity(named: "Synthetic editor reveal failure") { activity in
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "Synthetic editor hierarchy"; hierarchy.lifetime = .keepAlways; activity.add(hierarchy)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Synthetic editor reveal state"; screenshot.lifetime = .keepAlways; activity.add(screenshot)
    }
    XCTFail("Could not reveal editor switch: " + identifier)
    return element
}
@MainActor func editorToggle(_ identifier: String, in app: XCUIApplication, scrollStep: CGFloat? = nil) -> XCUIElement {
    editorSwitchWrapper(identifier, in: app, scrollStep: scrollStep).switches.firstMatch
}
