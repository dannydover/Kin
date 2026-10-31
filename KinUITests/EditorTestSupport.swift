import XCTest

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
