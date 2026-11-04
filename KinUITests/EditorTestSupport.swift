import XCTest

/// Resolve one exact synthetic card; never select an arbitrary duplicate.
@MainActor func requireSyntheticContactCard(_ app: XCUIApplication, name: String) throws -> XCUIElement {
    let cards = app.cells.containing(.staticText, identifier: name)
    let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
        syntheticCardResolution(cards.count) != .absent
    }, object: nil)
    let outcome = XCTWaiter.wait(for: [ready], timeout: 5)
    let resolution = syntheticCardResolution(cards.count)
    guard outcome == .completed, resolution == .unique else {
        let resolutionLabel: String
        switch resolution {
        case .absent: resolutionLabel = "absent"
        case .unique: resolutionLabel = "unique"
        case .ambiguous: resolutionLabel = "ambiguous"
        }
        let waiterLabel = outcome == .completed ? "completed" : "not-completed"
        XCTFail("Expected exactly one synthetic Contacts card; final resolution: \(resolutionLabel); waiter: \(waiterLabel)")
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
    var lastHittable: Bool?
    let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
        let sourceExists = source.exists
        lastSource = sourceExists; lastHittable = nil
        guard !sourceExists else { return false }
        // isHittable is false for a missing element, so a separate exists
        // query would repeat a synchronous accessibility lookup.
        let destinationHittable = destination.isHittable
        lastHittable = destinationHittable
        return destinationHittable
    }, object: nil)
    let result = XCTWaiter.wait(for: [ready], timeout: 5)
    if result != .completed {
        func text(_ value: Bool?) -> String { value.map(String.init) ?? "not observed" }
        let state = "sourceExists=\(text(lastSource)); destinationHittable=\(text(lastHittable))"
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
        // Bind each candidate to the observed accessibility element, not a changing result index.
        let elements = searches.allElementsBoundByAccessibilityElement
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


