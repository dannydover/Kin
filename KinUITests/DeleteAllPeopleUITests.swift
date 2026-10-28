import XCTest

final class DeleteAllPeopleUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor private func open(_ app: XCUIApplication) {
        app.buttons["people-menu"].tap()
        let action = app.buttons["Delete all people"]
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        // Native menus can clip their final row at accessibility sizes while
        // XCTest still reports the entire row as hittable. Reveal it before tapping.
        let menu = app.collectionViews.containing(.button, identifier: "Delete all people")
        if action.frame.height > 100 {
            XCTAssertEqual(menu.count, 1)
            let bounds = app.otherElements.containing(.button, identifier: "Delete all people")
                .allElementsBoundByIndex.map(\.frame)
                .filter { $0.width >= action.frame.width && $0.width < app.frame.width && $0.height > 100 }
                .min { $0.height < $1.height }
            XCTAssertNotNil(bounds)
            guard let bounds else { return }
            for _ in 0..<4 {
                if bounds.contains(action.frame) { break }
                menu.element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
                    .press(forDuration: 0.1, thenDragTo: menu.element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)))
            }
            XCTAssertTrue(bounds.contains(action.frame), "The entire menu action must be visible before tapping")
        }
        XCTAssertTrue(action.isHittable)
        action.tap()
        XCTAssertTrue(app.navigationBars["Delete all people"].waitForExistence(timeout: 5))
    }
    @MainActor private func review(_ app: XCUIApplication) {
        let action = app.buttons["review-delete-all"]
        for _ in 0..<8 { if action.isHittable { break }; app.swipeUp() }
        action.tap(); XCTAssertTrue(app.alerts["Delete all people?"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts.buttons["Cancel"].isHittable)
    }
    @MainActor func testConfirmationCancelDismissInterruptionAndDeletionIncludeHiddenPeople() {
        let app = XCUIApplication(); app.launchArguments = ["--kin-test-notebook",UUID().uuidString]; app.launch()
        app.buttons["Add person"].tap()
        app.textFields["First name (optional)"].tap(); app.textFields["First name (optional)"].typeText("Synthetic Delete Source")
        app.buttons["Save"].tap(); XCTAssertTrue(app.navigationBars["Synthetic Delete Source"].waitForExistence(timeout: 5))
        app.buttons["Add child"].tap(); app.buttons["Create new person"].tap()
        app.textFields["First name (optional)"].tap(); app.textFields["First name (optional)"].typeText("Synthetic Hidden Child")
        app.buttons["Save"].tap(); XCTAssertTrue(app.buttons["Edit relationship with Synthetic Hidden Child"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["People"].tap(); XCTAssertEqual(app.cells.count,1)
        open(app); XCTAssertTrue(app.staticTexts["2 people saved in this notebook."].exists)
        #if targetEnvironment(simulator)
        XCTAssertTrue(app.launchArguments.contains("--kin-test-notebook"))
        let scope = XCTAttachment(screenshot: app.screenshot())
        scope.name = "Delete all people scope - synthetic"; scope.lifetime = .keepAlways; add(scope)
        #endif
        review(app)
        #if targetEnvironment(simulator)
        let confirmation = XCTAttachment(screenshot: app.screenshot())
        confirmation.name = "Delete all people confirmation - synthetic"; confirmation.lifetime = .keepAlways; add(confirmation)
        #endif
        XCTAssertTrue(app.alerts.staticTexts.matching(NSPredicate(format: "label CONTAINS %@","backups")).firstMatch.exists)
        app.alerts.buttons["Cancel"].tap(); app.navigationBars["Delete all people"].buttons["Cancel"].tap()
        XCTAssertEqual(app.cells.count,1)
        open(app)
        let handle = app.navigationBars["Delete all people"].coordinate(withNormalizedOffset: CGVector(dx: 0.5,dy: 0.5))
        handle.press(forDuration: 0.1,thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5,dy: 0.92)))
        XCTAssertTrue(app.navigationBars["Delete all people"].waitForNonExistence(timeout: 5)); XCTAssertEqual(app.cells.count,1)
        open(app); review(app); app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["Synthetic Delete Source"].waitForExistence(timeout: 5))
        app.buttons["people-menu"].tap(); app.buttons["All people"].tap(); XCTAssertEqual(app.cells.count,2)
        open(app); review(app)
        app.alerts.buttons.matching(identifier: "confirm-delete-all").allElementsBoundByIndex.last!.doubleTap()
        XCTAssertTrue(app.staticTexts["Keep your people close."].waitForExistence(timeout: 5))
        XCTAssertEqual(app.cells.count,0)
        app.terminate(); app.launch(); XCTAssertTrue(app.staticTexts["Keep your people close."].waitForExistence(timeout: 5))
        app.buttons["people-menu"].tap(); app.buttons["All people"].tap(); XCTAssertEqual(app.cells.count,0)
        app.terminate()
    }
    @MainActor func testEmptyDeletionAtLargestTextHasSafeDisabledActionAndCancel() {
        let app = XCUIApplication(); app.launchArguments = ["--kin-preview","empty","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch(); open(app)
        XCTAssertTrue(app.staticTexts["No people saved in this notebook."].exists)
        let action = app.buttons["review-delete-all"]
        for _ in 0..<10 { if action.exists { break }; app.swipeUp() }
        XCTAssertTrue(action.exists); XCTAssertFalse(action.isEnabled)
        XCTAssertTrue(app.navigationBars["Delete all people"].buttons["Cancel"].isHittable)
        app.navigationBars["Delete all people"].buttons["Cancel"].tap()
        XCTAssertFalse(app.alerts.firstMatch.exists); app.terminate()
    }
    @MainActor func testFailedDeletionRetainsPeopleAndNeverShowsSuccess() {
        let app = XCUIApplication(); app.launchArguments = ["--kin-preview","delete-failure"]; app.launch()
        XCTAssertTrue(app.staticTexts["Synthetic Source"].waitForExistence(timeout: 10))
        for _ in 0..<2 {
            open(app); review(app); app.alerts.buttons.matching(identifier: "confirm-delete-all").allElementsBoundByIndex.last!.tap()
            XCTAssertTrue(app.alerts["Couldn’t finish"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.alerts.staticTexts.matching(NSPredicate(format: "label CONTAINS %@","couldn’t confirm the deletion")).firstMatch.exists)
            app.alerts.buttons["OK"].tap()
            XCTAssertTrue(app.staticTexts["5 people saved in this notebook."].exists)
            app.navigationBars["Delete all people"].buttons["Cancel"].tap()
        }
        app.buttons["people-menu"].tap(); app.buttons["All people"].tap(); XCTAssertEqual(app.cells.count,5)
        app.terminate()
    }
}
