import XCTest

final class IndexMembershipUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor private func launch(_ app: XCUIApplication) {
        app.launchArguments = ["--kin-test-notebook",UUID().uuidString]; app.launch()
        XCTAssertTrue(app.buttons["Add person"].waitForExistence(timeout: 10))
    }
    @MainActor private func inclusion(_ app: XCUIApplication) -> XCUIElement { app.switches["index-inclusion"].switches.firstMatch }
    @MainActor func testDirectSaveWithoutCategoryOpensProfileAndMembershipSurvivesCategoryEditsCancelAndRelaunch() {
        let app = XCUIApplication(); launch(app)
        app.buttons["Add person"].tap()
        let name = "Synthetic Direct"
        app.textFields["First name (optional)"].tap(); app.textFields["First name (optional)"].typeText(name)
        XCTAssertEqual(app.switches["Friend"].value as? String,"0")
        XCTAssertTrue(app.buttons["Save"].isEnabled); app.buttons["Save"].doubleTap()
        XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["In Your people"].exists)
        XCTAssertFalse(app.staticTexts["Not in Your people · find in All people"].exists)
        let editID = app.navigationBars[name].buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@","edit-person-")).firstMatch.identifier
        app.navigationBars.buttons["Edit"].tap()
        XCTAssertEqual(inclusion(app).value as? String,"1")
        app.switches["Friend"].switches.firstMatch.tap(); app.buttons["Save"].tap()
        app.navigationBars.buttons["Edit"].tap(); app.switches["Friend"].switches.firstMatch.tap()
        XCTAssertEqual(inclusion(app).value as? String,"1")
        app.buttons["Save"].tap(); app.navigationBars.buttons["Kin"].tap()
        XCTAssertEqual(app.cells.count,1); app.terminate(); app.launch()
        XCTAssertEqual(app.cells.count,1); app.staticTexts[name].tap(); XCTAssertTrue(app.buttons[editID].exists)
        app.navigationBars.buttons["Edit"].tap(); inclusion(app).tap(); app.buttons["Cancel"].tap()
        app.navigationBars.buttons["Kin"].tap(); XCTAssertTrue(app.staticTexts[name].exists)
        app.staticTexts[name].tap(); app.navigationBars.buttons["Edit"].tap(); inclusion(app).tap(); app.buttons["Save"].tap()
        app.navigationBars.buttons["Kin"].tap(); XCTAssertTrue(app.staticTexts["Your people is empty"].exists)
        app.buttons["people-menu"].tap(); app.buttons["All people"].tap(); XCTAssertEqual(app.cells.count,1)
        app.staticTexts[name].tap(); app.navigationBars.buttons["Edit"].tap(); inclusion(app).tap(); app.buttons["Save"].tap()
        app.navigationBars.buttons["All people"].tap(); app.buttons["people-menu"].tap(); app.buttons["Your people"].tap()
        XCTAssertEqual(app.cells.count,1); app.terminate()
    }
    @MainActor func testDirectFailedSaveAndCancelDoNotCreatePeopleAndLinkedCreationStaysUnlisted() {
        let app = XCUIApplication(); launch(app)
        app.buttons["Add person"].tap()
        let first = app.textFields["First name (optional)"]
        first.tap(); first.typeText(String(repeating: "x",count: 201)); app.buttons["Save"].tap()
        XCTAssertTrue(app.alerts["Couldn’t finish"].waitForExistence(timeout: 5)); app.alerts.buttons["OK"].tap()
        XCTAssertEqual(first.value as? String,String(repeating: "x",count: 201))
        app.buttons["Cancel"].tap(); XCTAssertTrue(app.staticTexts["Keep your people close."].exists)
        app.buttons["Add person"].tap(); first.tap(); first.typeText("Synthetic Source")
        app.buttons["Save"].doubleTap(); XCTAssertTrue(app.navigationBars["Synthetic Source"].waitForExistence(timeout: 5))
        app.buttons["Add child"].tap(); app.buttons["Create new person"].tap()
        first.tap(); first.typeText("Synthetic Linked Child")
        XCTAssertEqual(inclusion(app).value as? String,"0")
        XCTAssertEqual(app.switches["Friend"].value as? String,"0")
        app.buttons["Save"].doubleTap()
        XCTAssertTrue(app.buttons["Edit relationship with Synthetic Linked Child"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["Kin"].tap(); XCTAssertEqual(app.cells.count,1)
        app.buttons["people-menu"].tap(); app.buttons["All people"].tap(); XCTAssertEqual(app.cells.count,2)
        app.terminate(); app.launch(); XCTAssertEqual(app.cells.count,1)
        app.terminate()
    }
}
