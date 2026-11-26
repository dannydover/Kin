import XCTest

final class PetProfileUITests: XCTestCase {
    @MainActor
    func testProfilePetAddEditCancelRemoveAndRelaunch() throws {
        let app = XCUIApplication()
        let notebook = UUID().uuidString
        app.launchArguments = ["--kin-test-notebook", notebook, "--kin-ui-fixture", "named-friend"]
        app.launch()
        addTeardownBlock { app.terminate() }
        openProfile(app)

        tapVisible(app.buttons["add-pet"], in: app)
        let addBar = app.navigationBars["Add pet"]
        XCTAssertTrue(addBar.waitForExistence(timeout: 5))
        XCTAssertFalse(addBar.buttons["Save"].isEnabled)
        app.buttons["pet-species"].tap()
        XCTAssertTrue(app.buttons["Dog"].waitForExistence(timeout: 5))
        app.buttons["Dog"].tap()
        app.buttons["pet-age-information"].tap()
        XCTAssertTrue(app.buttons["Puppy"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Kitten"].exists)
        app.buttons["Puppy"].tap()
        enter("Biscuit", in: app.textFields["pet-name"])
        addBar.buttons["Save"].tap()
        requireDismissal(addBar, destination: app.navigationBars["Synthetic Named"].buttons["Edit"])
        let biscuit = pet("Biscuit", in: app)
        reveal(biscuit, in: app)
        XCTAssertTrue(biscuit.label.contains("Dog"))
        XCTAssertTrue(biscuit.label.contains("Puppy"))

        tapVisible(app.buttons["add-pet"], in: app)
        XCTAssertTrue(addBar.waitForExistence(timeout: 5))
        app.buttons["pet-species"].tap()
        XCTAssertTrue(app.buttons["Cat"].waitForExistence(timeout: 5))
        app.buttons["Cat"].tap()
        app.buttons["pet-age-information"].tap()
        XCTAssertTrue(app.buttons["Kitten"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Puppy"].exists)
        app.buttons["Exact birthday"].tap()
        let birthdayBar = app.navigationBars["Birthday"]
        XCTAssertTrue(birthdayBar.waitForExistence(timeout: 5))
        birthdayBar.buttons["Done"].tap()
        requireDismissal(birthdayBar, destination: app.textFields["pet-name"])
        enter("Cloud", in: app.textFields["pet-name"])
        addBar.buttons["Save"].tap()
        requireDismissal(addBar, destination: app.navigationBars["Synthetic Named"].buttons["Edit"])
        let cloud = pet("Cloud", in: app)
        reveal(cloud, in: app)
        XCTAssertTrue(cloud.label.contains("Cat"))
        XCTAssertTrue(cloud.label.contains("Birthday"))

        app.terminate()
        app.launchArguments = ["--kin-test-notebook", notebook]
        app.launch()
        openProfile(app)
        tapVisible(biscuit, in: app)
        let editBar = app.navigationBars["Edit pet"]
        XCTAssertTrue(editBar.waitForExistence(timeout: 5))
        app.buttons["pet-age-information"].tap()
        app.buttons["Elderly"].tap()
        editBar.buttons["Cancel"].tap()
        requireDismissal(editBar, destination: app.navigationBars["Synthetic Named"].buttons["Edit"])
        reveal(biscuit, in: app)
        XCTAssertTrue(biscuit.label.contains("Puppy"))

        tapVisible(biscuit, in: app)
        XCTAssertTrue(editBar.waitForExistence(timeout: 5))
        app.buttons["pet-age-information"].tap()
        app.buttons["Elderly"].tap()
        editBar.buttons["Save"].tap()
        requireDismissal(editBar, destination: app.navigationBars["Synthetic Named"].buttons["Edit"])
        reveal(biscuit, in: app)
        XCTAssertTrue(biscuit.label.contains("Elderly"))

        tapVisible(cloud, in: app)
        XCTAssertTrue(editBar.waitForExistence(timeout: 5))
        tapVisible(app.buttons["remove-pet"], in: app)
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Remove pet"].tap()
        requireDismissal(editBar, destination: app.navigationBars["Synthetic Named"].buttons["Edit"])
        reveal(biscuit, in: app)
        XCTAssertFalse(cloud.exists)
    }

    @MainActor
    private func openProfile(_ app: XCUIApplication) {
        let profile = app.staticTexts["Synthetic Named"]
        XCTAssertTrue(profile.waitForExistence(timeout: 5))
        profile.tap()
        XCTAssertTrue(app.navigationBars["Synthetic Named"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func enter(_ name: String, in field: XCUIElement) {
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(name)
    }

    @MainActor
    private func pet(_ name: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "pet-profile-row-", name)).firstMatch
    }

    @MainActor
    private func tapVisible(_ item: XCUIElement, in app: XCUIApplication) {
        reveal(item, in: app)
        item.tap()
    }

    @MainActor
    private func reveal(_ item: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<5 {
            if item.exists && item.isHittable { return }
            app.swipeUp()
        }
        for _ in 0..<5 {
            if item.exists && item.isHittable { return }
            app.swipeDown()
        }
        XCTAssertTrue(item.exists && item.isHittable)
    }
}
