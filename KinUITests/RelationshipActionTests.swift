import XCTest

/// In-memory synthetic profiles only; never opens saved phone data or Contacts.
final class RelationshipActionTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor func testRelationshipActionsAtStandardSize() throws { try verify(large: false) }
    @MainActor func testRelationshipActionsAtLargestSize() throws { try verify(large: true) }

    @MainActor func testSharedActionAuditAtStandardSize() throws { try audit(large: false) }
    @MainActor func testSharedActionAuditAtLargestSize() throws { try audit(large: true) }
    @MainActor private func audit(large: Bool) throws {
        let app = XCUIApplication(); defer { app.terminate() }
        app.launchArguments = ["--kin-preview","relationship-action-control"]
        app.launchArguments += ["-UIPreferredContentSizeCategoryName",large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL","-UIAccessibilityBoldTextEnabled",large ? "YES" : "NO"]
        app.launch()
        let action = app.buttons["Edit relationship with Synthetic Example"]
        XCTAssertTrue(action.waitForExistence(timeout: 10))
        XCTAssertTrue(action.isHittable)
        XCTAssertGreaterThanOrEqual(action.frame.height,44)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = large ? "Shared control largest - synthetic" : "Shared control standard - synthetic"
        image.lifetime = .keepAlways; add(image)
        // No audit issues are filtered or marked as expected failures. Retain
        // native clipping diagnostics alongside real-profile layout assertions.
        try app.performAccessibilityAudit(for: [.contrast,.hitRegion,.textClipped,.trait]) { issue in
            print("Shared action audit: \(issue.compactDescription); \(issue.detailedDescription); element=\(issue.element?.label ?? "unresolved")")
            return false
        }
    }

    @MainActor private func verify(large: Bool) throws {
        let app = XCUIApplication()
        app.launchArguments = ["--kin-preview","relationship-actions"]
        app.launchArguments += ["-UIPreferredContentSizeCategoryName",large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL","-UIAccessibilityBoldTextEnabled",large ? "YES" : "NO"]
        app.launch(); defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Synthetic Source"].waitForExistence(timeout: 10))
        app.staticTexts["Synthetic Source"].tap()
        let fixtures = [("Synthetic Casey Example","Partner status, Former"),
                        ("Synthetic Blair Example","Adoptive"),
                        ("Synthetic Alex Example","Step")]
        for (index,fixture) in fixtures.enumerated() {
            let action = app.buttons["Edit relationship with " + fixture.0]
            for _ in 0..<18 {
                if action.exists && action.frame.minY >= 125 && action.frame.maxY <= app.frame.maxY - 65 && action.isHittable { break }
                let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5,dy: 0.72))
                origin.press(forDuration: 0.05,thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5,dy: 0.52)))
            }
            XCTAssertTrue(action.isHittable)
            XCTAssertGreaterThanOrEqual(action.frame.height,44)
            XCTAssertGreaterThanOrEqual(action.frame.width,44)
            XCTAssertGreaterThanOrEqual(action.frame.minX,0)
            XCTAssertLessThanOrEqual(action.frame.maxX,app.frame.maxX)
            if large { XCTAssertGreaterThan(action.frame.height,44) }
            let addTitle = ["Add partner","Add child","Add parent"][index]
            let addAction = app.buttons[addTitle]
            XCTAssertTrue(addAction.exists)
            XCTAssertGreaterThanOrEqual(addAction.frame.height,44)
            XCTAssertGreaterThanOrEqual(addAction.frame.width,44)
            if !large && index == 1 { XCTAssertTrue(addAction.isHittable, "Preview shows both related actions together") }
            #if targetEnvironment(simulator)
            if index == 1 {
                XCTAssertTrue(app.launchArguments.contains("relationship-actions"))
                let image = XCTAttachment(screenshot: app.screenshot())
                image.name = large ? "Edit relationship button - largest text - synthetic" : "Edit relationship button - standard - synthetic"
                image.lifetime = .keepAlways; add(image)

            }
            #endif
            action.tap()
            XCTAssertTrue(app.navigationBars["Edit relationship"].waitForExistence(timeout: 5))
            if index == 0 { XCTAssertTrue(app.buttons[fixture.1].exists) }
            else {
                XCTAssertTrue(app.buttons["relationship-details"].label.contains(fixture.1))
                let parent = app.descendants(matching: .any).matching(identifier: "relationship-parent").firstMatch
                let child = app.descendants(matching: .any).matching(identifier: "relationship-child").firstMatch
                XCTAssertTrue(parent.label.contains(index == 1 ? "Synthetic Source" : fixture.0))
                XCTAssertTrue(child.label.contains(index == 1 ? fixture.0 : "Synthetic Source"))
            }
            app.navigationBars["Edit relationship"].buttons["Cancel"].tap()
            XCTAssertTrue(app.navigationBars["Synthetic Source"].waitForExistence(timeout: 5))
            XCTAssertTrue(action.exists, "Cancel preserves the same relationship action")
            for _ in 0..<20 {
                let visible = addAction.exists
                let frame = visible ? addAction.frame : .null
                if visible && addAction.isHittable && frame.minY >= 125 && frame.maxY <= app.frame.maxY - 65 { break }
                let movingUp = !visible || frame.maxY > app.frame.maxY - 65
                let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5,dy: movingUp ? 0.70 : 0.40))
                let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5,dy: 0.55))
                start.press(forDuration: 0.1,thenDragTo: end)
            }
            XCTAssertTrue(addAction.isHittable)
            addAction.tap()
            XCTAssertTrue(app.navigationBars[addTitle].waitForExistence(timeout: 5))
            app.navigationBars[addTitle].buttons["Cancel"].tap()
            XCTAssertTrue(app.navigationBars["Synthetic Source"].waitForExistence(timeout: 5))
        }
        app.navigationBars.buttons["People"].tap()
        app.buttons["people-menu"].tap(); app.buttons["Delete all people"].tap()
        XCTAssertTrue(app.navigationBars["Delete all people"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["5 people saved in this notebook."].exists,
                      "Opening and canceling relationship edits changes no people, including unlisted records")
        let scope = app.staticTexts.matching(NSPredicate(format: "label == %@","Delete every person saved in this Kin notebook, including people not shown in your list, and all their relationships, notes and photos.")).firstMatch
        XCTAssertTrue(scope.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@","outside your main list")).firstMatch.exists)
        #if targetEnvironment(simulator)
        if !large {
            let image = XCTAttachment(screenshot: app.screenshot())
            image.name = "Delete scope sentence case - synthetic"; image.lifetime = .keepAlways; add(image)
        }
        #endif
        app.navigationBars["Delete all people"].buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["People"].waitForExistence(timeout: 5))
    }
}
