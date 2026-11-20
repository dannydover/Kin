import XCTest
/// Fixed in-memory Contacts snapshots exercise existing-record review without system data.
final class ExistingContactPreservationUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor private func reveal(_ item: XCUIElement,in app: XCUIApplication) {
        for _ in 0..<18 {
            if item.exists && item.isHittable && item.frame.minY >= 130 && item.frame.maxY <= app.frame.maxY - 80 { return }
            let down = item.exists && item.frame.minY < 130
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5,dy: down ? 0.4 : 0.7))
                .press(forDuration: 0.1,thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5,dy: 0.55)))
        }
    }
    @MainActor func testSyntheticExistingBirthInformationSurvivesMissingAndYearlessContactsReview() throws {
        executionTimeAllowance = 600
        let fixtures = (0..<4).map { "Kin Synthetic Keep \($0)" }
        let app = XCUIApplication()
        app.launchArguments = ["--kin-preview","import-preservation","--kin-ui-preservation-contacts","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryL","-UIAccessibilityBoldTextEnabled","NO"]
        app.launch(); addTeardownBlock { app.terminate() }
        func select(_ name: String) throws {
            let action = app.buttons["Import from Contacts"]; reveal(action,in: app); action.tap()
            let index = try XCTUnwrap(fixtures.firstIndex(of: name))
            let card = app.buttons["synthetic-preservation-contact-\(index)"]
            XCTAssertTrue(card.waitForExistence(timeout: 10)); card.tap()
            XCTAssertTrue(app.navigationBars["Contact birth information"].waitForExistence(timeout: 10))
        }
        let originals = ["Synthetic Exact","Synthetic Estimate","Synthetic Unknown"]
        let kinds = ["Exact birthday","Estimated age","Unknown"]
        var identities: [String] = []
        for index in 0..<3 {
            XCTAssertTrue(app.staticTexts[originals[index]].waitForExistence(timeout: 10)); app.staticTexts[originals[index]].tap()
            let edit = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@","edit-person-")).firstMatch
            identities.append(edit.identifier); edit.tap()
            try select(fixtures[index])
            XCTAssertTrue(app.staticTexts["Details to apply"].exists)
            let kind = app.buttons["contact-birth-information"]
            XCTAssertTrue(kind.exists)
            XCTAssertTrue(kind.label.contains(kinds[index]))
            let current = app.staticTexts["Current Kin details"]
            reveal(current, in: app)
            XCTAssertTrue(current.exists)
            let preservation = app.staticTexts["contact-birth-preservation"]
            reveal(preservation, in: app)
            XCTAssertTrue(preservation.exists)
            if index < 2 {
                let photo = app.switches["contact-include-photo"].switches.firstMatch
                reveal(photo,in: app); XCTAssertEqual(photo.value as? String,"0")
            }
            if index == 0 {
                app.buttons["contact-cancel"].tap()
                requireDismissal(app.navigationBars["Contact birth information"], destination: app.navigationBars["Edit person"].buttons["Cancel"])
                XCTAssertEqual(app.textFields["First name (optional)"].value as? String,originals[index])
                try select(fixtures[index])
                let noPhoto = app.buttons["Continue without importing photo"]; reveal(noPhoto,in: app); noPhoto.tap()
            } else { app.buttons["contact-import"].tap() }
            XCTAssertTrue(app.navigationBars["Edit person"].waitForExistence(timeout: 5))
            let kept = app.buttons["birth-information"]; reveal(kept,in: app); XCTAssertTrue(kept.label.contains(kinds[index]))
            app.navigationBars["Edit person"].buttons["Save"].tap()
            XCTAssertTrue(app.navigationBars[fixtures[index]].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons[identities[index]].exists)
            app.navigationBars.buttons["People"].tap()
        }
        app.staticTexts[fixtures[0]].tap(); app.navigationBars.buttons["Edit"].tap()
        try select(fixtures[3])
        XCTAssertFalse(app.staticTexts["contact-birth-preservation"].exists)
        app.buttons["contact-import"].tap()
        app.navigationBars["Edit person"].buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars[fixtures[3]].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons[identities[0]].exists)
        XCTAssertTrue(app.staticTexts["Birthday"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "1995")).firstMatch.exists)
        app.navigationBars.buttons["People"].tap(); XCTAssertEqual(app.cells.count,3)
    }

    @MainActor func testNewContactReviewShowsAndSavesProposedDetails() {
        let app = XCUIApplication()
        app.launchArguments = ["--kin-test-notebook", UUID().uuidString, "--kin-ui-preservation-contacts"]
        app.launch()
        defer { app.terminate() }
        let review = app.navigationBars["Contact birth information"]
        let birth = app.buttons["contact-birth-information"]
        let date = app.descendants(matching: .any).matching(identifier: "contact-exact-birthday").firstMatch
        let first = app.textFields["Imported first name (optional)"]
        let last = app.textFields["Imported last name (optional)"]

        func select(_ fixture: Int) {
            app.buttons["Add person"].tap()
            app.buttons["Import from Contacts"].tap()
            app.buttons["synthetic-preservation-contact-\(fixture)"].tap()
            XCTAssertTrue(review.waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["Edit details to save"].exists)
            XCTAssertFalse(app.staticTexts["Current birth information"].exists)
            XCTAssertTrue(first.isHittable)
            XCTAssertTrue(last.isHittable)
            XCTAssertTrue(birth.isHittable)
        }

        XCTAssertTrue(app.buttons["Add person"].waitForExistence(timeout: 10))
        select(0)
        XCTAssertTrue(birth.label.contains("Unknown"))
        app.buttons["contact-cancel"].tap()
        XCTAssertTrue(review.waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.textFields["First name (optional)"].value as? String, "First name")
        app.navigationBars["Add person"].buttons["Cancel"].tap()

        select(1)
        XCTAssertTrue(birth.label.contains("Unknown"))
        XCTAssertFalse(date.exists)
        app.buttons["contact-import"].tap()
        XCTAssertTrue(app.navigationBars["Kin Synthetic Keep 1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Age unknown"].exists)
        XCTAssertFalse(app.staticTexts["Birthday"].exists)
        app.navigationBars.buttons["People"].tap()

        select(3)
        XCTAssertTrue(birth.label.contains("Exact birthday"))
        XCTAssertTrue(date.exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "New Contacts review with proposed full birthday"
        screenshot.lifetime = .keepAlways; add(screenshot)
        birth.tap()
        app.buttons["Unknown"].tap()
        XCTAssertFalse(date.exists)
        birth.tap()
        app.buttons["Exact birthday"].tap()
        XCTAssertTrue(date.exists)
        last.tap(); last.typeText("Edited")
        app.buttons["contact-import"].tap()
        XCTAssertTrue(app.navigationBars["Kin Synthetic Keep 3 Edited"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Birthday"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "1995")).firstMatch.exists)
    }
}
