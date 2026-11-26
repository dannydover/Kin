import XCTest

final class ChildAllergyUITests: XCTestCase {
    @MainActor func testChildAllergiesStayWithCorrectChildThroughEditCancelAndReopen() {
        continueAfterFailure = false
        let app = XCUIApplication()
        let parent = "Synthetic Named"
        let child = "Synthetic Allergy Child"
        let sibling = "Synthetic Other Child"
        let first = "Peanuts, sesame"
        let revised = "Tree nuts, soy"
        app.launchArguments = ["--kin-test-notebook", UUID().uuidString, "--kin-ui-fixture", "named-friend"]
        app.launch()
        addTeardownBlock { app.terminate() }
        openParent(app, name: parent)
        createChild(app, name: child, allergies: first)
        createChild(app, name: sibling, allergies: nil)

        let firstText = app.staticTexts["Allergies: " + first]
        reveal(firstText, in: app)
        let childRow = app.cells.containing(.staticText, identifier: child).firstMatch
        XCTAssertTrue(childRow.staticTexts["Allergies: " + first].exists)
        reveal(app.staticTexts[sibling], in: app)
        XCTAssertFalse(app.cells.containing(.staticText, identifier: sibling)
            .firstMatch.staticTexts["Allergies: " + first].exists)

        openChild(app, name: child)
        XCTAssertTrue(app.staticTexts[first].exists)
        app.navigationBars.buttons["Edit"].tap()
        let clear = app.buttons["clear-person-allergies"]
        reveal(clear, in: app); clear.tap()
        app.navigationBars.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts[first].waitForExistence(timeout: 5))

        app.navigationBars.buttons["Edit"].tap()
        reveal(clear, in: app); clear.tap()
        let input = allergyInput(in: app)
        reveal(input, in: app); input.tap(); input.typeText(revised)
        app.navigationBars.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts[revised].waitForExistence(timeout: 5))

        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        openParent(app, name: parent)
        reveal(app.staticTexts["Allergies: " + revised], in: app)
        XCTAssertFalse(app.staticTexts["Allergies: " + first].exists)
        openChild(app, name: child)
        reveal(app.staticTexts[revised], in: app)
        app.navigationBars.buttons["Edit"].tap()
        reveal(clear, in: app); clear.tap()
        app.navigationBars.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars[child].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts[revised].exists)
        XCTAssertFalse(app.staticTexts["Allergies"].exists)
    }

    @MainActor private func openParent(_ app: XCUIApplication, name: String) {
        let item = app.staticTexts[name]
        XCTAssertTrue(item.waitForExistence(timeout: 10))
        item.tap()
        XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 5))
    }

    @MainActor private func openChild(_ app: XCUIApplication, name: String) {
        let item = app.staticTexts[name]
        reveal(item, in: app); item.tap()
        XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 5))
    }

    @MainActor private func createChild(_ app: XCUIApplication, name: String, allergies: String?) {
        let add = app.buttons["Add child"]
        reveal(add, in: app); add.tap()
        let create = app.buttons["Create new person"]
        XCTAssertTrue(create.waitForExistence(timeout: 5)); create.tap()
        let first = app.textFields["First name (optional)"]
        reveal(first, in: app); first.tap(); first.typeText(name)
        if let allergies {
            let finish = app.keyboards.buttons["Return"]
            if finish.exists && finish.isHittable { finish.tap() }
            let input = allergyInput(in: app)
            reveal(input, in: app); input.tap(); input.typeText(allergies)
        }
        let save = app.navigationBars["Add person"].buttons["Save"]
        XCTAssertTrue(save.isEnabled); save.tap()
        XCTAssertTrue(app.navigationBars["Add person"].waitForNonExistence(timeout: 5))
    }

    @MainActor private func allergyInput(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "person-allergies-input").firstMatch
    }

    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 {
            if element.exists, element.isHittable,
               element.frame.midY > 115, element.frame.midY < app.frame.maxY - 55 { return }
            if element.exists, element.frame.height > 0, element.frame.midY <= 115 {
                app.swipeDown(velocity: .slow)
            } else {
                app.swipeUp(velocity: .slow)
            }
        }
        XCTFail("Could not reveal " + element.debugDescription)
    }
}
