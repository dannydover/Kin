import XCTest

/// Only synthetic in-memory notebooks are used here. No Contacts or physical data.
final class RelationshipChooserTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor private func launch(_ app: XCUIApplication, large: Bool = false) {
        app.launchArguments = ["--kin-preview","relationships"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.staticTexts["Synthetic Source"].waitForExistence(timeout: 10))
    }
    @MainActor private func reveal(_ item: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<10 { if item.isHittable { return }; app.swipeUp() }
    }
    @MainActor private func options(_ app: XCUIApplication, route: String) {
        app.staticTexts["Synthetic Source"].tap()
        reveal(app.buttons[route],in: app); app.buttons[route].tap()
        XCTAssertTrue(app.navigationBars[route].waitForExistence(timeout: 5))
    }
    @MainActor private func chooser(_ app: XCUIApplication) {
        app.buttons["Link an existing person"].tap()
        XCTAssertTrue(app.navigationBars["Choose a person"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.searchFields["Find an existing person"].exists)
    }
    @MainActor private func back(_ app: XCUIApplication, to title: String) {
        let bar = app.navigationBars["Choose a person"]
        let action = bar.buttons[title].exists ? bar.buttons[title] : bar.buttons["Back"]
        action.tap(); XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
    }
    @MainActor func testParentChildPartnerShowDetailsLastAndVisiblePeopleNeedNoSearch() {
        let app = XCUIApplication()
        for route in ["Add parent","Add child","Add partner"] {
            launch(app); options(app,route: route)
            let link = app.buttons["Link an existing person"]
            let details = route == "Add partner" ? app.buttons["Partner status, Current"] : app.buttons["relationship-details"]
            XCTAssertTrue(details.exists)
            XCTAssertGreaterThan(details.frame.minY,link.frame.minY)
            XCTAssertTrue(app.searchFields.allElementsBoundByIndex.filter(\.isHittable).isEmpty)
            chooser(app)
            XCTAssertFalse(app.keyboards.firstMatch.exists)
            let person = app.buttons["Synthetic Blair Example"]
            XCTAssertTrue(person.isHittable)
            let identity = String(person.identifier.dropFirst("existing-person-".count))
            XCTAssertNotNil(UUID(uuidString: identity))
            person.doubleTap()
            XCTAssertTrue(app.navigationBars["Add relationship"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.navigationBars.matching(identifier: "Add relationship").count,1)
            app.navigationBars["Add relationship"].buttons["Save"].doubleTap()
            XCTAssertTrue(app.buttons["Edit relationship with Synthetic Blair Example"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.buttons.matching(identifier: "Edit relationship with Synthetic Blair Example").count,1)
            app.staticTexts["Synthetic Blair Example"].tap()
            XCTAssertTrue(app.buttons["edit-person-" + identity].exists)
            app.terminate()
        }
    }
    @MainActor func testSearchDuplicatesBackCancelAndRepeatedSelectionPreserveIdentityAndDetails() {
        let app = XCUIApplication(); launch(app); options(app,route: "Add child")
        app.buttons["relationship-details"].tap(); app.buttons["Parent relationship, Unspecified"].tap(); app.buttons["Step"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@","Relationship details (optional)")).firstMatch.tap()
        chooser(app)
        let choices = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@","Synthetic Alex Example"))
        XCTAssertEqual(choices.count,2)
        XCTAssertTrue(choices.element(boundBy: 0).label.contains("Notebook reference 2"))
        XCTAssertTrue(choices.element(boundBy: 1).label.contains("Notebook reference 3"))
        let identity = choices.element(boundBy: 1).identifier
        let search = app.searchFields["Find an existing person"]
        search.tap(); search.typeText("No matching synthetic person")
        XCTAssertTrue(app.staticTexts["No matches"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@","existing-person-")).count,0)
        search.buttons["Clear text"].tap()
        XCTAssertEqual(choices.count,2)
        app.buttons[identity].doubleTap()
        XCTAssertTrue(app.navigationBars["Add relationship"].waitForExistence(timeout: 5))
        let child = app.descendants(matching: .any).matching(identifier: "relationship-child").firstMatch
        XCTAssertTrue(child.label.contains("Notebook reference 3"))
        app.navigationBars["Add relationship"].buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Choose a person"].waitForExistence(timeout: 5))
        back(app,to: "Add child")
        XCTAssertTrue(app.buttons["relationship-details"].label.contains("Step"))
        app.navigationBars["Add child"].buttons["Cancel"].tap()
        XCTAssertFalse(app.buttons["Edit relationship with Synthetic Alex Example"].exists)
        app.buttons["Add child"].tap(); chooser(app); app.buttons[identity].tap()
        app.navigationBars["Add relationship"].buttons["Save"].doubleTap()
        XCTAssertTrue(app.buttons["Edit relationship with Synthetic Alex Example"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "Edit relationship with Synthetic Alex Example").count,1)
        app.staticTexts["Synthetic Alex Example"].tap()
        XCTAssertTrue(app.buttons["edit-person-" + String(identity.dropFirst("existing-person-".count))].exists)
        app.navigationBars.buttons["Synthetic Source"].tap(); app.navigationBars.buttons["People"].tap()
        app.buttons["people-menu"].tap(); app.buttons["All people"].tap()
        XCTAssertEqual(app.cells.count,5)
        app.terminate()
    }
    @MainActor func testEmptyChooserAndPartnerDetailsSurviveBackAndCancel() {
        let app = XCUIApplication()
        app.launchArguments = ["--kin-preview","relationships-empty"]; app.launch()
        XCTAssertTrue(app.staticTexts["Synthetic Source"].waitForExistence(timeout: 10))
        options(app,route: "Add partner")
        app.buttons["Partner status, Current"].tap(); app.buttons["Former"].tap()
        chooser(app)
        XCTAssertTrue(app.staticTexts["No other people yet"].exists)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@","existing-person-")).count,0)
        back(app,to: "Add partner")
        XCTAssertTrue(app.buttons["Partner status, Former"].exists)
        app.navigationBars["Add partner"].buttons["Cancel"].tap()
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@","Edit relationship with")).firstMatch.exists)
        app.terminate()
    }
    @MainActor func testSyntheticRelationshipReviewScreenshots() throws {
        #if targetEnvironment(simulator)
        let app = XCUIApplication(); launch(app); options(app,route: "Add child")
        func capture(_ name: String) {
            XCTAssertTrue(app.launchArguments.contains("relationships"))
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        }
        capture("01 Add child options - synthetic")
        chooser(app); XCTAssertTrue(app.buttons["Synthetic Blair Example"].isHittable)
        capture("02 Visible people and search - synthetic")
        let search = app.searchFields["Find an existing person"]; search.tap(); search.typeText("No matching synthetic person")
        XCTAssertTrue(app.staticTexts["No matches"].waitForExistence(timeout: 5))
        capture("03 No search results - synthetic")
        app.terminate(); launch(app,large: true); options(app,route: "Add child")
        reveal(app.buttons["Link an existing person"],in: app); chooser(app)
        capture("04 Chooser accessibility size - synthetic")
        app.terminate()
        #else
        throw XCTSkip("Synthetic screenshot capture is restricted to a test simulator.")
        #endif
    }
}
