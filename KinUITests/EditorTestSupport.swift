import XCTest

/// Reveal the actual shared-editor control after deliberate section reordering.
/// Lazy form rows need bounded scrolling before hierarchy uniqueness assertions.
@MainActor func editorSwitchWrapper(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
    let element = app.switches[identifier]
    if #unavailable(iOS 27.0), app.keyboards.firstMatch.exists {
        // iOS26 keyboard geometry excludes its predictive bar. Finish text
        // entry using the captured native Return action before form scrolling.
        let finishEntry = app.keyboards.firstMatch.buttons["Return"]
        XCTAssertTrue(finishEntry.exists && finishEntry.isHittable)
        finishEntry.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
    }
    for _ in 0..<16 {
        if element.exists {
            let frame = element.frame
            if element.isHittable && frame.minY >= 140 && frame.maxY <= app.frame.maxY - 80 { return element }
            if frame.height > 0 && frame.minY < 140 { app.swipeDown(); continue }
        }
        app.swipeUp()
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
@MainActor func editorToggle(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
    editorSwitchWrapper(identifier, in: app).switches.firstMatch
}
