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
        XCTAssertFalse(app.staticTexts["Name unknown"].exists)
        XCTAssertEqual(app.textFields["First name (optional)"].value as? String, "First name (optional)")
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
        XCTAssertEqual(app.cells.count, 1) // Child is a preview inside the parent row, not another index entry.
        openAllPeople(app)
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
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Synthetic B"].waitForExistence(timeout: 5))
        // The edit action must open only the relationship editor, not navigate.
        app.buttons["Edit relationship with Synthetic B"].tap()
        XCTAssertTrue(app.navigationBars["Edit relationship"].waitForExistence(timeout: 5))
        app.buttons["Remove relationship"].tap()
        let unlinkWarning = app.alerts["Remove relationship?"]
        XCTAssertTrue(unlinkWarning.buttons["Cancel"].isHittable); unlinkWarning.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Edit relationship"].exists)
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
        openAllPeople(app)
        XCTAssertTrue(app.staticTexts["Synthetic B"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Synthetic A"].exists)
    }
    @MainActor func testNewPartnerDefaultsCurrentAndSelectionRemainsUnsaved() {
        let app = XCUIApplication(); app.launchArguments = ["--kin-test-notebook", UUID().uuidString]
        app.launch(); addPerson(app, name: "Synthetic A"); addPerson(app, name: "Synthetic B")
        app.staticTexts["Synthetic A"].tap(); app.buttons["Add partner"].tap()
        XCTAssertTrue(app.buttons["Partner status, Current"].exists)
        app.buttons["Synthetic B"].tap()
        XCTAssertTrue(app.navigationBars["Add relationship"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Partner status, Current"].exists)
        capture(app, "New existing-person partner draft defaults Current")
        app.navigationBars["Add relationship"].buttons["Cancel"].tap()
        app.navigationBars["Add partner"].buttons["Cancel"].tap()
        XCTAssertFalse(app.buttons["Edit relationship with Synthetic B"].exists)
        app.buttons["Add partner"].tap(); app.buttons["Synthetic B"].tap()
        app.buttons["Partner status, Current"].tap()
        XCTAssertTrue(app.buttons["Unknown"].exists); app.buttons["Former"].tap()
        app.buttons["Save"].tap(); app.buttons["Edit relationship with Synthetic B"].tap()
        XCTAssertTrue(app.buttons["Partner status, Former"].exists)
        capture(app, "Existing Former relationship and red Remove relationship")
        app.buttons["Cancel"].tap()
        app.buttons["Add partner"].tap()
        XCTAssertTrue(app.buttons["Partner status, Current"].exists)
        app.buttons["Create new person"].tap(); app.buttons["Save"].tap()
        app.buttons["Edit relationship with Partner 3"].tap()
        XCTAssertTrue(app.buttons["Partner status, Current"].exists)
        app.buttons["Cancel"].tap()
        app.buttons["Add partner"].tap(); app.buttons["Partner status, Current"].tap(); app.buttons["Unknown"].tap()
        app.buttons["Create new person"].tap(); app.buttons["Save"].tap()
        app.buttons["Edit relationship with Partner 4"].tap()
        XCTAssertTrue(app.buttons["Partner status, Unknown"].exists)
        app.buttons["Cancel"].tap(); app.terminate(); app.launch()
        app.staticTexts["Synthetic A"].tap(); app.buttons["Edit relationship with Synthetic B"].tap()
        XCTAssertTrue(app.buttons["Partner status, Former"].exists)
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
        app.buttons["Save"].tap()
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
        app.navigationBars.buttons["Kin"].tap()
        let previews = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "child-preview-"))
        XCTAssertEqual(previews.count, 2)
        XCTAssertEqual(Set(previews.allElementsBoundByIndex.map(\.identifier)).count, 1)
        capture(app, "Family context index with one child shared by two parents")
        app.terminate(); app.launch(); openAllPeople(app)
        XCTAssertTrue(app.staticTexts["Synthetic Shared Child"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts.matching(identifier: "Synthetic Shared Child").count,1)
        let index = XCTAttachment(screenshot: app.screenshot()); index.name = "All people with one shared child identity"; index.lifetime = .keepAlways; add(index)
    }
    @MainActor func testAllPeopleOpensProfilesAndReturnsToSameIndex() {
        let app = XCUIApplication(); app.launchArguments = ["--kin-test-notebook", UUID().uuidString]
        app.launch(); addPerson(app, name: "Synthetic Listed")
        app.staticTexts["Synthetic Listed"].tap(); app.buttons["Add child"].tap()
        app.buttons["Create new person"].tap()
        app.textFields["First name (optional)"].tap(); app.textFields["First name (optional)"].typeText("Synthetic Unlisted")
        app.buttons["Save"].tap(); app.navigationBars.buttons["Kin"].tap()
        openAllPeople(app)
        for name in ["Synthetic Unlisted", "Synthetic Listed", "Synthetic Unlisted"] {
            app.staticTexts[name].tap()
            XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["Edit"].exists)
            XCTAssertTrue(app.staticTexts["Gender: Unknown"].exists)
            capture(app, "All people opens selected profile " + name)
            app.navigationBars.buttons["All people"].tap()
            XCTAssertTrue(app.navigationBars["All people"].exists)
        }
        app.searchFields.firstMatch.tap(); app.searchFields.firstMatch.typeText("Unlisted")
        app.staticTexts["Synthetic Unlisted"].tap()
        XCTAssertTrue(app.navigationBars["Synthetic Unlisted"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["All people"].tap()
        // Active native search hides the title and toolbar; verify its filtered root.
        XCTAssertTrue(app.searchFields.firstMatch.exists)
        XCTAssertFalse(app.buttons["Edit"].exists)
        XCTAssertTrue(app.staticTexts["Synthetic Unlisted"].exists)
        XCTAssertFalse(app.staticTexts["Synthetic Listed"].exists)
        if app.buttons["Cancel"].exists { app.buttons["Cancel"].tap() }
        else { app.buttons["close"].tap() }
        XCTAssertTrue(app.navigationBars["All people"].exists)
        XCTAssertTrue(app.buttons["people-menu"].exists)
    }
    @MainActor func testIllustratedEmptyStateMenuAndSearchRecovery() {
        let app = XCUIApplication(); app.launchArguments = ["--kin-test-notebook", UUID().uuidString]
        app.launch()
        XCTAssertTrue(app.staticTexts["Keep your people close."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Add your first person"].isHittable)
        XCTAssertFalse(app.buttons["All people (including unlisted)"].exists)
        capture(app, "After illustrated empty notebook")
        app.buttons["people-menu"].tap(); capture(app, "Your people All people About menu")
        app.buttons["About"].tap(); XCTAssertTrue(app.navigationBars["About Kin"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        addPerson(app, name: "Synthetic Visible")
        app.staticTexts["Synthetic Visible"].tap(); app.navigationBars.buttons["Edit"].tap()
        app.switches["Friend"].switches.firstMatch.tap(); app.buttons["Save"].tap()
        app.navigationBars.buttons["Kin"].tap()
        XCTAssertTrue(app.staticTexts["Your people is empty"].waitForExistence(timeout: 5))
        capture(app, "Unlisted people remain recoverable")
        openAllPeople(app); XCTAssertTrue(app.staticTexts["Synthetic Visible"].waitForExistence(timeout: 5))
        app.searchFields.firstMatch.tap(); app.searchFields.firstMatch.typeText("NoSuchSyntheticPerson")
        XCTAssertTrue(app.staticTexts["No matches"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Keep your people close."].exists)
        capture(app, "Search with no matches")
        if app.buttons["Cancel"].exists { app.buttons["Cancel"].tap() } else { app.buttons["close"].tap() }
        app.buttons["people-menu"].tap(); app.buttons["Your people"].tap()
        XCTAssertTrue(app.staticTexts["Your people is empty"].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        XCTAssertTrue(app.navigationBars["Kin"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Your people is empty"].exists)
    }
    @MainActor func testBlankNameEditsCancelAndLaterNamingPreserveEntry() {
        let app = XCUIApplication(); app.launchArguments = ["--kin-test-notebook", UUID().uuidString]
        app.launch(); addPerson(app, name: "Synthetic Named")
        app.staticTexts["Synthetic Named"].tap(); app.navigationBars.buttons["Edit"].tap()
        XCTAssertFalse(app.staticTexts["Name unknown"].exists)
        let first = app.textFields["First name (optional)"]
        first.tap(); first.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Synthetic Named".count) + "   ")
        app.buttons["Cancel"].tap(); XCTAssertTrue(app.navigationBars["Synthetic Named"].exists)
        app.navigationBars.buttons["Edit"].tap(); first.tap()
        first.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Synthetic Named".count) + "   ")
        app.buttons["Save"].tap(); XCTAssertTrue(app.navigationBars["Person 1"].waitForExistence(timeout: 5))
        app.terminate(); app.launch(); app.staticTexts["Person 1"].tap(); app.navigationBars.buttons["Edit"].tap()
        first.tap(); first.typeText("Synthetic Renamed"); app.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Synthetic Renamed"].waitForExistence(timeout: 5))
    }
    @MainActor func testEmptyStateAtLargestDynamicType() {
        let app = XCUIApplication(); app.launchArguments = ["--kin-test-notebook", UUID().uuidString, "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch(); XCTAssertTrue(app.buttons["people-menu"].isHittable); XCTAssertTrue(app.buttons["Add person"].isHittable)
        capture(app, "Largest Dynamic Type illustrated empty state")
        app.swipeUp(); app.swipeUp(); capture(app, "Largest Dynamic Type first person action")
        XCTAssertTrue(app.buttons["Add your first person"].isHittable)
        app.buttons["Add your first person"].tap(); XCTAssertTrue(app.navigationBars["Add person"].waitForExistence(timeout: 5))
    }
    @MainActor func testFormSurfacesAndDestructiveControls() {
        let app = XCUIApplication(); app.launchArguments = ["--kin-test-notebook", UUID().uuidString]
        app.launch(); addPerson(app, name: "Synthetic Example")
        app.staticTexts["Synthetic Example"].tap(); capture(app, "Profile grouped surfaces")
        app.swipeUp(); XCTAssertTrue(app.buttons["Delete person"].isHittable)
        capture(app, "Red delete person")
        app.buttons["Delete person"].tap(); capture(app, "Delete person confirmation")
        let deletion = app.alerts["Delete Synthetic Example?"]
        XCTAssertTrue(deletion.buttons["Cancel"].isHittable); deletion.buttons["Cancel"].tap()
        app.navigationBars.buttons["Edit"].tap()
        XCTAssertTrue(app.textFields["Last name (optional)"].isHittable)
        capture(app, "Editor adaptive row fill and placeholders")
        app.textFields["Last name (optional)"].tap(); capture(app, "Focused optional name field")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Synthetic Example"].waitForExistence(timeout: 5))
    }
    @MainActor func testYoungProfileHidesPartnerAndChildSectionsButUnknownAgeDoesNot() {
        let app = XCUIApplication(); app.launchArguments = ["--kin-test-notebook", UUID().uuidString]
        app.launch(); addPerson(app, name: "Synthetic Young")
        app.staticTexts["Synthetic Young"].tap(); app.navigationBars.buttons["Edit"].tap(); app.swipeUp()
        app.buttons["Birth information, Unknown"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["Estimated age"].tap()
        app.textFields["Estimated age in years"].tap(); app.textFields["Estimated age in years"].typeText("3")
        app.buttons["Done"].tap()
        app.buttons["Save"].tap()
        XCTAssertFalse(app.buttons["Add partner"].exists); XCTAssertFalse(app.buttons["Add child"].exists)
        XCTAssertFalse(app.staticTexts["Partners"].exists); XCTAssertFalse(app.staticTexts["Children"].exists)
        XCTAssertTrue(app.staticTexts["Parents"].exists)
        capture(app, "Under sixteen profile keeps Parents and hides family add controls")
        app.navigationBars.buttons["Edit"].tap(); app.swipeUp()
        app.buttons["Birth information, Estimated age"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["Unknown"].tap(); app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["Add partner"].waitForExistence(timeout: 5)); XCTAssertTrue(app.buttons["Add child"].exists)
    }
    @MainActor func testDirectEstimatedAgeEntryValidationAndCancel() {
        let app = XCUIApplication(); app.launchArguments = ["--kin-test-notebook", UUID().uuidString]
        app.launch(); addPerson(app, name: "Synthetic Older")
        app.staticTexts["Synthetic Older"].tap(); app.navigationBars.buttons["Edit"].tap(); app.swipeUp()
        app.buttons["Birth information, Unknown"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap(); app.buttons["Estimated age"].tap()
        XCTAssertFalse(app.buttons["Save"].isEnabled)
        let age = app.textFields["Estimated age in years"]
        age.tap(); age.typeText("80"); app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Save"].isEnabled); capture(app, "Direct estimated age eighty")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Estimated 80 as of")).firstMatch.waitForExistence(timeout: 5))
        app.navigationBars.buttons["Edit"].tap(); app.swipeUp()
        age.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.5)).tap()
        age.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2))
        XCTAssertTrue((age.value as? String) == "" || (age.value as? String) == "0–120")
        XCTAssertFalse(app.buttons["Save"].isEnabled)
        age.typeText("121"); XCTAssertFalse(app.buttons["Save"].isEnabled); capture(app, "Invalid estimated age range feedback")
        age.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3) + "0")
        XCTAssertTrue(app.buttons["Save"].isEnabled)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Estimated 80 as of")).firstMatch.waitForExistence(timeout: 5))
    }
    @MainActor func testEstimatedAgeEntryAtLargestDynamicType() {
        let app = XCUIApplication(); app.launchArguments = ["--kin-test-notebook", UUID().uuidString]
        app.launch(); addEstimatedAdult(app, name: "Synthetic Large Age")
        app.terminate(); app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]; app.launch()
        app.staticTexts["Synthetic Large Age"].tap(); app.navigationBars.buttons["Edit"].tap()
        let age = app.textFields["Estimated age in years"]
        reveal(age, in: app); age.tap(); age.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2) + "80")
        capture(app, "Largest Dynamic Type age keypad")
        XCTAssertTrue(app.buttons["Done"].isHittable); app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Save"].isEnabled); XCTAssertEqual(age.value as? String, "80")
        capture(app, "Largest Dynamic Type direct age field")
        app.buttons["Cancel"].tap()
    }
    @MainActor func testPhotoRemovalAlertHasVisibleCancelAndPreservesSavedPhoto() throws {
        let app = XCUIApplication(); app.launchArguments = ["--kin-test-notebook", UUID().uuidString]
        app.launch(); addEstimatedAdult(app, name: "Synthetic Photo")
        app.navigationBars.buttons["Edit"].tap(); app.swipeUp(); app.buttons["Add photo"].tap()
        XCTAssertTrue(app.navigationBars["Photos"].waitForExistence(timeout: 15))
        let fixture = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        guard fixture.waitForExistence(timeout: 10) else { throw XCTSkip("Seed an isolated simulator with a synthetic Photos image for this picker regression.") }
        // iOS 26 exposes a grid image with a valid frame but marks it non-hittable.
        // Tap the observed image center rather than asking XCTest to infer a hit target.
        fixture.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap(); XCTAssertTrue(app.buttons["Change photo"].waitForExistence(timeout: 10))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: app.buttons["Save"])
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed); app.buttons["Save"].tap()
        app.navigationBars.buttons["Edit"].tap(); app.swipeUp()
        app.buttons["Birth information, Estimated age"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["Unknown"].tap(); app.buttons["Save"].tap()
        let warning = app.alerts["Remove the existing photo?"]
        XCTAssertTrue(warning.waitForExistence(timeout: 5)); XCTAssertTrue(warning.buttons["Cancel"].isHittable)
        capture(app, "Photo removal warning with visible Cancel")
        warning.buttons["Cancel"].tap(); app.navigationBars["Edit person"].buttons["Cancel"].tap()
        app.terminate(); app.launch(); app.staticTexts["Synthetic Photo"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Estimated 80 as of")).firstMatch.exists)
        app.navigationBars.buttons["Edit"].tap(); app.swipeUp()
        XCTAssertTrue(app.buttons["Change photo"].exists)
        capture(app, "Visible Cancel preserves saved photo and age after relaunch")
    }
    @MainActor private func addEstimatedAdult(_ app: XCUIApplication, name: String) {
        addPerson(app, name: name); app.staticTexts[name].tap(); app.navigationBars.buttons["Edit"].tap(); app.swipeUp()
        app.buttons["Birth information, Unknown"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap(); app.buttons["Estimated age"].tap()
        app.textFields["Estimated age in years"].tap(); app.textFields["Estimated age in years"].typeText("80")
        app.buttons["Done"].tap(); app.buttons["Save"].tap()
    }
    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 {
            if element.exists {
                let frame = element.frame
                if frame.minY >= 145 && frame.maxY <= app.frame.maxY - 100 { return }
                if frame.height > 0 && frame.minY < 145 { app.swipeDown(); continue }
            }
            app.swipeUp()
        }
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    @MainActor private func openAllPeople(_ app: XCUIApplication) {
        app.buttons["people-menu"].tap(); app.buttons["All people"].tap()
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
