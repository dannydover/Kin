import XCTest

final class DesignFlowTests: XCTestCase {
    @MainActor func testFourChildPreviewAndEditSheet() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--kin-preview", "babies"]
        app.launch()
        defer { app.terminate() }

        let parent = app.staticTexts["Synthetic Parent"]
        XCTAssertTrue(parent.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Kin"].exists)
        let previews = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "child-preview-"))
        XCTAssertEqual(previews.count, 4)
        XCTAssertTrue(app.staticTexts["+2 more"].exists)
        let familySummary = "Synthetic Parent. Synthetic Unknown, Age unknown. Synthetic Newborn, Less than 1 month. Synthetic One Month, 1 month. Synthetic Eleven Months, 11 months. 2 more children"
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", familySummary)).firstMatch.isHittable)
        capture("Kin 2 index")

        parent.tap()
        let profile = app.navigationBars["Synthetic Parent"]
        XCTAssertTrue(profile.waitForExistence(timeout: 5))
        capture("Kin 2 profile")
        profile.buttons["Edit"].tap()
        let editor = app.navigationBars["Edit person"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["First name (optional)"].exists)
        capture("Kin 2 edit sheet")
        editor.buttons["Cancel"].tap()
        XCTAssertTrue(profile.waitForExistence(timeout: 5))
    }

    @MainActor func testAllPeopleCardsOpenFromTrailingEdgeAtBothTextSizes() {
        continueAfterFailure = false
        let app = XCUIApplication()
        let longName = "Synthetic Parent With A Long Compound Family Name"
        app.launchArguments = ["--kin-test-notebook", UUID().uuidString, "--kin-ui-fixture", "long-friend"]
        app.launch()
        defer { app.terminate() }

        let add = app.buttons["Add person"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()
        let name = app.textFields["First name (optional)"]
        name.tap(); name.typeText("Al")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Al"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["People"].tap()

        for large in [false, true] {
            if large {
                app.terminate()
                app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"]
                app.launch()
            }
            app.buttons["people-menu"].tap()
            app.buttons["All people"].tap()
            XCTAssertTrue(app.navigationBars["All people"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts[longName].exists)
            capture(large ? "All people cards - accessibility text" : "All people cards - standard text")

            for person in ["Al", longName] {
                let row = app.cells.containing(.staticText, identifier: person).firstMatch
                XCTAssertTrue(row.isHittable)
                let search = app.searchFields.firstMatch
                XCTAssertTrue(search.exists)
                let point = app.coordinate(withNormalizedOffset: .zero)
                    .withOffset(CGVector(dx: search.frame.maxX - 16, dy: row.frame.midY))
                point.tap()
                XCTAssertTrue(app.navigationBars[person].waitForExistence(timeout: 5))
                app.navigationBars.buttons["All people"].tap()
            }
        }
    }

    @MainActor func testFamilyIndexAlignmentFixturesAtMultipleTextSizes() {
        continueAfterFailure = false
        let app = XCUIApplication()
        defer { app.terminate() }
        let sizes = [
            ("UICTContentSizeCategoryL", "standard"),
            ("UICTContentSizeCategoryXXXL", "larger"),
            ("UICTContentSizeCategoryAccessibilityL", "accessibility")
        ]
        for (size, label) in sizes {
            app.launchArguments = ["--kin-preview", "index-alignment", "-UIPreferredContentSizeCategoryName", size]
            app.launch()
            let parent = app.staticTexts["Synthetic Index Parent"]
            XCTAssertTrue(parent.waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["Partner · Synthetic Partner"].exists)
            let familySummary = "Synthetic Index Parent. Partner: Synthetic Partner. Synthetic Avery, Approximately 5 years, Approximately Kindergarten. Synthetic Riley, Age unknown. Synthetic Sam, 6 years, 1st Grade"
            let familyCard = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@", familySummary)).firstMatch
            XCTAssertTrue(familyCard.isHittable)
            let previews = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH %@", "child-preview-"))
            XCTAssertEqual(previews.count, 3)
            let withGrade = previews.matching(NSPredicate(format: "label CONTAINS %@", "Kindergarten")).firstMatch
            let withoutGrade = previews.matching(NSPredicate(format: "label CONTAINS %@", "Synthetic Riley")).firstMatch
            let exactGrade = previews.matching(NSPredicate(format: "label CONTAINS %@", "Synthetic Sam")).firstMatch
            XCTAssertTrue(withGrade.exists)
            XCTAssertTrue(withoutGrade.exists)
            XCTAssertTrue(exactGrade.exists)
            XCTAssertTrue(withGrade.label.contains("Approximately Kindergarten"))
            XCTAssertFalse(withGrade.label.contains("~Kindergarten"))
            XCTAssertTrue(exactGrade.label.contains("1st Grade"))
            XCTAssertFalse(exactGrade.label.contains("Approximately"))
            XCTAssertFalse(exactGrade.label.contains("~1st Grade"))
            if label == "accessibility" {
                XCTAssertGreaterThan(withoutGrade.frame.minY, withGrade.frame.maxY)
            } else {
                XCTAssertEqual(withGrade.frame.minY, withoutGrade.frame.minY, accuracy: 2)
            }
            capture("Family index grades - " + label)
            if label == "standard" {
                familyCard.tap()
                XCTAssertTrue(app.navigationBars["Synthetic Index Parent"].waitForExistence(timeout: 5))
                app.staticTexts["Synthetic Avery"].tap()
                XCTAssertTrue(app.staticTexts["Approximately Kindergarten"].waitForExistence(timeout: 5))
                capture("Profile estimated school grade")
                app.navigationBars.buttons["Synthetic Index Parent"].tap()
                app.staticTexts["Synthetic Sam"].tap()
                XCTAssertTrue(app.staticTexts["1st Grade"].waitForExistence(timeout: 5))
                capture("Profile exact-birthday school grade")
            }
            app.terminate()
        }
    }

    @MainActor private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
