import XCTest

final class IndexMembershipUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor private func launch(_ app: XCUIApplication) {
        app.launchArguments = ["--kin-test-notebook",UUID().uuidString]; app.launch()
        XCTAssertTrue(app.buttons["Add person"].waitForExistence(timeout: 10))
    }
    @MainActor private func inclusion(_ app: XCUIApplication) -> XCUIElement { editorToggle("index-inclusion", in: app) }
    @MainActor func testDirectSaveWithoutCategoryOpensProfileAndMembershipSurvivesCategoryEditsCancelAndRelaunch() {
        let app = XCUIApplication(); launch(app)
        app.buttons["Add person"].tap()
        let name = "Synthetic Direct"
        app.textFields["First name (optional)"].tap(); app.textFields["First name (optional)"].typeText(name)
        XCTAssertEqual(editorSwitchWrapper("Friend", in: app).value as? String,"0")
        XCTAssertTrue(app.buttons["Save"].isEnabled); app.buttons["Save"].doubleTap()
        XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["On main list"].exists)
        XCTAssertFalse(app.staticTexts["Not on main list · available on the All people screen"].exists)
        let editID = app.navigationBars[name].buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@","edit-person-")).firstMatch.identifier
        app.navigationBars.buttons["Edit"].tap()
        XCTAssertEqual(inclusion(app).value as? String,"1")
        editorToggle("Friend", in: app).tap(); app.buttons["Save"].tap()
        app.navigationBars.buttons["Edit"].tap(); editorToggle("Friend", in: app).tap()
        XCTAssertEqual(inclusion(app).value as? String,"1")
        app.buttons["Save"].tap(); app.navigationBars.buttons["People"].tap()
        XCTAssertEqual(app.cells.count,1); app.terminate(); app.launch()
        XCTAssertEqual(app.cells.count,1); app.staticTexts[name].tap()
        XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons[editID].waitForExistence(timeout: 5))
        app.navigationBars.buttons["Edit"].tap(); inclusion(app).tap(); app.buttons["Cancel"].tap()
        app.navigationBars.buttons["People"].tap(); XCTAssertTrue(app.staticTexts[name].exists)
        app.staticTexts[name].tap(); app.navigationBars.buttons["Edit"].tap(); inclusion(app).tap(); app.buttons["Save"].tap()
        app.navigationBars.buttons["People"].tap(); XCTAssertTrue(app.staticTexts["Your main list is empty"].exists)
        app.buttons["people-menu"].tap(); app.buttons["All people"].tap(); XCTAssertEqual(app.cells.count,1)
        app.staticTexts[name].tap(); app.navigationBars.buttons["Edit"].tap(); inclusion(app).tap(); app.buttons["Save"].tap()
        app.navigationBars.buttons["All people"].tap(); app.buttons["people-menu"].tap(); app.buttons["People"].tap()
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
        XCTAssertEqual(editorSwitchWrapper("Friend", in: app).value as? String,"0")
        app.buttons["Save"].doubleTap()
        XCTAssertTrue(app.buttons["Edit relationship with Synthetic Linked Child"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["People"].tap(); XCTAssertEqual(app.cells.count,1)
        app.buttons["people-menu"].tap(); app.buttons["All people"].tap(); XCTAssertEqual(app.cells.count,2)
        app.terminate(); app.launch(); XCTAssertEqual(app.cells.count,1)
        app.terminate()
    }
    @MainActor func testCategoryFilterCombinesSearchKeepsUncategorizedAndPreservesSelectionAfterCancel() {
        let app = XCUIApplication(); launch(app)
        XCTAssertTrue(app.navigationBars["People"].exists)
        for (name, category) in [("Synthetic Unlabeled", ""), ("Synthetic Friend", "Friend"), ("Synthetic Family", "Family")] {
            app.buttons["Add person"].tap()
            let first = app.textFields["First name (optional)"]
            first.tap(); first.typeText(name)
            if !category.isEmpty { editorToggle(category, in: app).tap() }
            app.buttons["Save"].tap()
            XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 5))
            app.navigationBars.buttons["People"].tap()
        }
        XCTAssertEqual(app.cells.count, 3)
        app.buttons["category-filter"].tap(); app.buttons["Friend"].tap()
        XCTAssertEqual(app.cells.count, 1)
        XCTAssertTrue(app.staticTexts["Synthetic Friend"].exists)
        let filtered = XCTAttachment(screenshot: app.screenshot())
        filtered.name = "People category filter standard - synthetic"; filtered.lifetime = .keepAlways; add(filtered)
        app.staticTexts["Synthetic Friend"].tap(); app.navigationBars.buttons["Edit"].tap()
        XCTAssertTrue(editorSwitchWrapper("index-inclusion", in: app).exists)
        XCTAssertEqual(editorSwitchWrapper("index-inclusion", in: app).label, "Show on main list")
        app.buttons["Cancel"].tap(); app.navigationBars.buttons["People"].tap()
        XCTAssertEqual(app.buttons["category-filter"].value as? String, "Friend")
        let search = app.searchFields.firstMatch
        search.tap(); search.typeText("Unlabeled")
        XCTAssertTrue(app.staticTexts["No matches"].exists)
        search.buttons["Clear text"].tap()
        app.buttons["category-filter"].tap(); app.buttons["Colleague"].tap()
        XCTAssertTrue(app.staticTexts["No people in this category"].exists)
        app.buttons["clear-search-and-filters"].tap()
        XCTAssertEqual(app.cells.count, 3)
        XCTAssertTrue(app.staticTexts["Synthetic Unlabeled"].exists)
        app.terminate()
    }

    @MainActor private func clearSearchFixture() -> XCUIApplication {
        let app = XCUIApplication(); launch(app)
        for (name, category) in [("Alex Morgan", ""), ("Jamie Patel", "Friend"), ("Robin Chen", "Family")] {
            app.buttons["Add person"].tap()
            let first = app.textFields["First name (optional)"]
            first.tap(); first.typeText(name)
            if !category.isEmpty { editorToggle(category,in: app).tap() }
            app.buttons["Save"].tap()
            XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 5))
            app.navigationBars.buttons["People"].tap()
            XCTAssertTrue(app.navigationBars["People"].waitForExistence(timeout: 5))
        }
        return app
    }

    @MainActor private func assertClearSearchRestored(_ app: XCUIApplication) {
        let clear = app.buttons["clear-search-and-filters"]
        // The failing trace had already restored these values before XCTest
        // waited on animation notifications at the next menu transition.
        // Gate the next transition on that exact functional outcome, within
        // the existing five-second bound. A first-match cell frame is not a
        // recovery invariant: CI showed the correct restored screen while
        // that additional geometry condition failed to settle.
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.navigationBars["People"].exists
                && app.buttons["category-filter"].value as? String == "All"
                && app.cells.count == 3 && app.staticTexts["Alex Morgan"].exists
                && !clear.exists
        },object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [restored],timeout: 5),.completed)
        XCTAssertTrue(app.navigationBars["People"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["category-filter"].value as? String,"All")
        XCTAssertEqual(app.cells.count,3)
        XCTAssertTrue(app.staticTexts["Alex Morgan"].exists,"Uncategorized listed person must remain visible")
        XCTAssertFalse(clear.exists)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
    }

    @MainActor private func assertClearSearchPreservedCategory(_ app: XCUIApplication) {
        app.staticTexts["Jamie Patel"].tap()
        XCTAssertTrue(app.navigationBars["Jamie Patel"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["Edit"].tap()
        XCTAssertEqual(editorSwitchWrapper("Friend",in: app).value as? String,"1")
        app.buttons["Cancel"].tap()
    }

    @MainActor func testClearSearchRestoresPeopleWithoutChangingRecords() {
        let app = clearSearchFixture(); defer { app.terminate() }
        let clear = app.buttons["clear-search-and-filters"]
        let search = app.searchFields.firstMatch
        search.tap(); search.typeText("NoSuchFictionalPerson")
        XCTAssertTrue(app.staticTexts["No matches"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Try another name, such as Alex Morgan. Tap Clear search and filters to return to the People screen."].exists)
        XCTAssertTrue(clear.isHittable); clear.tap(); assertClearSearchRestored(app)
        assertClearSearchPreservedCategory(app)
    }

    @MainActor func testClearEmptyCategoryRestoresPeopleWithoutChangingRecords() {
        let app = clearSearchFixture(); defer { app.terminate() }
        let clear = app.buttons["clear-search-and-filters"]
        app.buttons["category-filter"].tap(); app.buttons["Colleague"].tap()
        XCTAssertTrue(app.staticTexts["No people in this category"].exists)
        clear.tap(); assertClearSearchRestored(app)
        assertClearSearchPreservedCategory(app)
    }

    @MainActor func testClearCombinedSearchAndCategoryRepeatedlyPreservesPeople() {
        let app = clearSearchFixture(); defer { app.terminate() }
        let clear = app.buttons["clear-search-and-filters"]
        let search = app.searchFields.firstMatch
        for _ in 0..<2 {
            app.buttons["category-filter"].tap(); app.buttons["Friend"].tap()
            search.tap(); search.typeText("Alex Morgan")
            XCTAssertTrue(app.staticTexts["No matches"].exists)
            let image = XCTAttachment(screenshot: app.screenshot())
            image.name = "Clear search and filters - fictional people"; image.lifetime = .keepAlways; add(image)
            XCTAssertTrue(clear.isHittable); clear.tap(); assertClearSearchRestored(app)
        }
        assertClearSearchPreservedCategory(app)
    }

    @MainActor func testClearAllPeopleSearchRestoresPeopleWithoutChangingRecords() {
        let app = clearSearchFixture(); defer { app.terminate() }
        let clear = app.buttons["clear-search-and-filters"]
        let search = app.searchFields.firstMatch
        app.buttons["people-menu"].tap(); app.buttons["All people"].tap()
        XCTAssertTrue(app.navigationBars["All people"].waitForExistence(timeout: 5))
        search.tap(); search.typeText("NoSuchFictionalPerson")
        clear.tap(); assertClearSearchRestored(app)
        // Clearing display controls must not change a stored category.
        assertClearSearchPreservedCategory(app)
    }

    @MainActor func testClearSearchAndFiltersOnEmptyNotebookAtLargestText() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--kin-preview","empty","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch(); defer { app.terminate() }
        let clear = app.buttons["clear-search-and-filters"]
        app.searchFields.firstMatch.tap(); app.searchFields.firstMatch.typeText("Alex Morgan")
        XCTAssertTrue(app.staticTexts["No matches"].waitForExistence(timeout: 5))
        XCTAssertTrue(clear.isHittable); XCTAssertGreaterThanOrEqual(clear.frame.height,44)
        let content = app.scrollViews["filtered-empty-content"]
        let explanation = app.staticTexts["filtered-empty-explanation"]
        let diagnostic = XCTAttachment(string: app.debugDescription)
        diagnostic.name = "Synthetic largest search explanation hierarchy"; diagnostic.lifetime = .keepAlways; add(diagnostic)
        XCTAssertTrue(explanation.waitForExistence(timeout: 3))
        XCTAssertGreaterThan(explanation.frame.height,0)
        // A long paragraph may exceed the viewport. Its beginning and ending
        // must both be revealable while the reset action remains reachable.
        for ending in [false,true] {
            var revealed = false
            for _ in 0..<24 {
                // Native ScrollView accessibility bounds include obscured areas.
                // Measure the actual exposed strip between the filter and footer.
                let top = app.buttons["category-filter"].frame.maxY + 4
                let bottom = clear.frame.minY - 16
                let viewport = CGRect(x: content.frame.minX,y: top,width: content.frame.width,height: bottom - top)
                XCTAssertGreaterThan(viewport.height,44)
                let frame = explanation.frame
                let edge = ending ? frame.maxY : frame.minY
                if edge >= viewport.minY + (ending ? 44 : 0) && edge <= viewport.maxY - (ending ? 0 : 44) {
                    revealed = true; break
                }
                let up = edge > viewport.maxY - 44
                let distance = min(viewport.height * 0.7,max(24,up ? edge - viewport.maxY + 44 : viewport.minY - edge + 8))
                let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: viewport.midX,dy: viewport.midY + (up ? distance / 2 : -distance / 2)))
                let end = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: viewport.midX,dy: viewport.midY + (up ? -distance / 2 : distance / 2)))
                start.press(forDuration: 0.05,thenDragTo: end,withVelocity: .slow,thenHoldForDuration: 0.15)
            }
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = ending ? "Largest search explanation ending" : "Largest search explanation beginning"
            screenshot.lifetime = .keepAlways; add(screenshot)
            XCTAssertTrue(revealed,"Both ends of the explanation must be readable by scrolling")
        }
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "No matches clear action largest text - synthetic"; image.lifetime = .keepAlways; add(image)
        try app.performAccessibilityAudit(for: [.contrast,.hitRegion,.textClipped,.trait]) { _ in false }
        clear.tap()
        XCTAssertTrue(app.navigationBars["People"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Keep your people close."].exists)
        XCTAssertEqual(app.cells.count,0)
        XCTAssertFalse(clear.exists)
        app.buttons["category-filter"].tap(); app.buttons["Friend"].tap()
        XCTAssertTrue(clear.isHittable); clear.tap()
        XCTAssertTrue(app.staticTexts["Keep your people close."].exists)
        XCTAssertEqual(app.buttons["category-filter"].value as? String,"All")
        XCTAssertEqual(app.cells.count,0)
    }

}
