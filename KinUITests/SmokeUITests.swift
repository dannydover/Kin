import XCTest

/// Essential app journeys on an isolated simulator; no system picker or real data.
final class SmokeUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor func testRelationshipEditPersistsAfterRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["--kin-test-notebook", UUID().uuidString, "--kin-ui-fixture", "partner-friends"]
        addTeardownBlock { app.terminate() }
        app.launch()
        XCTAssertTrue(app.staticTexts["Synthetic A"].waitForExistence(timeout: 10))
        app.staticTexts["Synthetic A"].tap()
        XCTAssertTrue(app.buttons["Add partner"].waitForExistence(timeout: 5))
        app.buttons["Add partner"].tap()
        app.buttons["Link an existing person"].tap()
        XCTAssertTrue(app.navigationBars["Choose a person"].waitForExistence(timeout: 5))
        let choices = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "existing-person-", "Synthetic B"))
        XCTAssertTrue(choices.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(choices.count, 1)
        let choice = choices.element
        XCTAssertTrue(choice.isHittable)
        choice.tap()
        XCTAssertTrue(app.navigationBars["Add relationship"].waitForExistence(timeout: 5))
        app.buttons["Save"].tap()
        let edit = app.buttons["Edit relationship with Synthetic B"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        XCTAssertTrue(app.buttons["Partner status, Current"].waitForExistence(timeout: 5))
        app.buttons["Partner status, Current"].tap()
        app.buttons["Former"].tap()
        app.buttons["Save"].tap()
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["Synthetic A"].waitForExistence(timeout: 10))
        app.staticTexts["Synthetic A"].tap()
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        XCTAssertTrue(app.buttons["Partner status, Former"].waitForExistence(timeout: 5))
    }
}
