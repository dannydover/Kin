import XCTest

final class KinUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor func testSharedEditorUnlistedRecoveryCancelAndRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["--kin-test-notebook", UUID().uuidString]
        app.launch()
        app.buttons["Add person"].tap()
        XCTAssertFalse(app.buttons["Save"].isEnabled)
        app.textFields["First name (optional)"].tap()
        app.textFields["First name (optional)"].typeText("Synthetic Parent")
        app.switches["Friend"].switches.firstMatch.tap()
        XCTAssertTrue(app.buttons["Save"].isEnabled)
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Synthetic Parent"].waitForExistence(timeout: 5))
        app.staticTexts["Synthetic Parent"].tap()
        app.buttons["Add child"].tap()
        app.buttons["Create new person"].tap()
        XCTAssertTrue(app.staticTexts["Name unknown"].exists)
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Child 2"].waitForExistence(timeout: 5))
        app.staticTexts["Child 2"].tap()
        app.navigationBars.buttons["Edit"].tap()
        if !app.textFields["First name (optional)"].waitForExistence(timeout: 5) {
            let shot = XCTAttachment(screenshot: app.screenshot()); shot.lifetime = .keepAlways; add(shot)
            XCTFail("Person editor did not open"); return
        }
        app.textFields["First name (optional)"].tap()
        app.textFields["First name (optional)"].typeText("Canceled Name")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Child 2"].exists)
        app.navigationBars.buttons["Edit"].tap()
        if !app.textFields["First name (optional)"].waitForExistence(timeout: 5) {
            let shot = XCTAttachment(screenshot: app.screenshot()); shot.lifetime = .keepAlways; add(shot)
            XCTFail("Person editor did not open"); return
        }
        app.textFields["First name (optional)"].tap()
        app.textFields["First name (optional)"].typeText("Synthetic Child")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Synthetic Child"].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["Synthetic Parent"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Synthetic Child"].exists)
        app.buttons["All people (including unlisted)"].tap()
        XCTAssertTrue(app.staticTexts["Synthetic Child"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Canceled Name"].exists)
    }
    @MainActor func testReuseExistingPartnerUnlinkAndDeletePreservesOtherPerson() {
        let app = XCUIApplication()
        app.launchArguments = ["--kin-test-notebook", UUID().uuidString]
        app.launch()
        addPerson(app, name: "Synthetic A")
        addPerson(app, name: "Synthetic B")
        app.staticTexts["Synthetic A"].tap()
        app.buttons["Add partner"].tap()
        app.buttons["Synthetic B"].tap()
        XCTAssertTrue(app.staticTexts["Synthetic B"].waitForExistence(timeout: 5))
        // The edit action must open only the relationship editor, not navigate.
        app.buttons["Edit relationship with Synthetic B"].tap()
        XCTAssertTrue(app.navigationBars["Edit relationship"].waitForExistence(timeout: 5))
        app.buttons["Remove relationship"].tap()
        app.buttons.matching(identifier: "confirm-unlink").allElementsBoundByIndex.last!.tap()
        XCTAssertTrue(app.navigationBars["Synthetic A"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Synthetic B"].exists)
        app.swipeUp()
        app.buttons["Delete person"].tap()
        app.buttons.matching(identifier: "confirm-delete-person").allElementsBoundByIndex.last!.tap()
        XCTAssertTrue(app.staticTexts["Synthetic B"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Synthetic A"].exists)
        app.terminate(); app.launch()
        app.buttons["All people (including unlisted)"].tap()
        XCTAssertTrue(app.staticTexts["Synthetic B"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Synthetic A"].exists)
    }
    @MainActor func testSharedChildReuseAndRenameAcrossBothParents() {
        let app = XCUIApplication()
        app.launchArguments = ["--kin-test-notebook", UUID().uuidString]
        app.launch()
        addPerson(app,name: "Synthetic Parent A"); addPerson(app,name: "Synthetic Parent B")
        app.staticTexts["Synthetic Parent A"].tap()
        app.buttons["Add child"].tap(); app.buttons["Create new person"].tap(); app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Child 3"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["Kin"].tap()
        app.staticTexts["Synthetic Parent B"].tap(); app.buttons["Add child"].tap()
        app.buttons["Child 3"].tap()
        XCTAssertTrue(app.staticTexts["Child 3"].waitForExistence(timeout: 5))
        app.staticTexts["Child 3"].tap()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Synthetic Parent A"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Synthetic Parent B"].exists)
        let shared = XCTAttachment(screenshot: app.screenshot()); shared.name = "Shared unnamed child with both parents"; shared.lifetime = .keepAlways; add(shared)
        app.navigationBars.buttons["Edit"].tap()
        app.textFields["First name (optional)"].tap(); app.textFields["First name (optional)"].typeText("Synthetic Shared Child")
        app.buttons["Save"].tap()
        app.navigationBars.buttons["Synthetic Parent B"].tap()
        XCTAssertTrue(app.staticTexts["Synthetic Shared Child"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["Kin"].tap(); app.staticTexts["Synthetic Parent A"].tap()
        XCTAssertTrue(app.staticTexts["Synthetic Shared Child"].waitForExistence(timeout: 5))
        app.terminate(); app.launch(); app.buttons["All people (including unlisted)"].tap()
        XCTAssertTrue(app.staticTexts["Synthetic Shared Child"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts.matching(identifier: "Synthetic Shared Child").count,1)
        let index = XCTAttachment(screenshot: app.screenshot()); index.name = "All people with one shared child identity"; index.lifetime = .keepAlways; add(index)
    }
    @MainActor private func addPerson(_ app: XCUIApplication, name: String) {
        app.buttons["Add person"].tap()
        app.textFields["First name (optional)"].tap()
        app.textFields["First name (optional)"].typeText(name)
        app.switches["Friend"].switches.firstMatch.tap()
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 5))
    }

}
