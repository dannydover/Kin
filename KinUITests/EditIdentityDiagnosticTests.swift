import XCTest

// Temporary synthetic-only diagnostic; never part of PR 33 required checks.
final class EditIdentityDiagnosticTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor func testBaselineBroadEditQuery() {
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
        let parentEdits = app.navigationBars["Synthetic Parent"].buttons.matching(
            NSPredicate(format: "label == %@ AND identifier BEGINSWITH %@", "Edit", "edit-person-"))
        XCTAssertEqual(parentEdits.count, 1)
        let parentEditID = parentEdits.element.identifier
        XCTAssertNotNil(UUID(uuidString: String(parentEditID.dropFirst("edit-person-".count))))
        addTeardownBlock { @MainActor in
            self.recordEditState(app, parentID: parentEditID, stage: "baseline teardown")
        }
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
        recordEditState(app, parentID: parentEditID, stage: "baseline editor outcome")
        app.textFields["First name (optional)"].tap()
        app.textFields["First name (optional)"].typeText("Canceled Name")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Child 2"].exists)
        app.navigationBars.buttons["Edit"].tap()
        if !app.textFields["First name (optional)"].waitForExistence(timeout: 5) {
            let shot = XCTAttachment(screenshot: app.screenshot()); shot.lifetime = .keepAlways; add(shot)
            XCTFail("Person editor did not open"); return
        }
        recordEditState(app, parentID: parentEditID, stage: "baseline editor outcome")
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
    @MainActor func testStrictChildIdentityCandidate() {
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
        let parentEdits = app.navigationBars["Synthetic Parent"].buttons.matching(
            NSPredicate(format: "label == %@ AND identifier BEGINSWITH %@", "Edit", "edit-person-"))
        XCTAssertEqual(parentEdits.count, 1)
        let parentEditID = parentEdits.element.identifier
        XCTAssertNotNil(UUID(uuidString: String(parentEditID.dropFirst("edit-person-".count))))
        addTeardownBlock { @MainActor in
            self.recordEditState(app, parentID: parentEditID, stage: "strict teardown")
        }
        app.buttons["Add child"].tap()
        app.buttons["Create new person"].tap()
        XCTAssertFalse(app.staticTexts["Name unknown"].exists)
        XCTAssertEqual(app.textFields["First name (optional)"].value as? String, "First name (optional)")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Child 2"].waitForExistence(timeout: 5))
        app.staticTexts["Child 2"].tap()
        let childBars = app.navigationBars.matching(identifier: "Child 2")
        XCTAssertEqual(childBars.count, 1)
        let childEdits = childBars.element.buttons.matching(NSPredicate(
            format: "label == %@ AND identifier BEGINSWITH %@ AND identifier != %@",
            "Edit", "edit-person-", parentEditID))
        XCTAssertEqual(childEdits.count, 1)
        let childEditID = childEdits.element.identifier
        XCTAssertNotNil(UUID(uuidString: String(childEditID.dropFirst("edit-person-".count))))
        let priorParentEdit = childBars.element.buttons.matching(identifier: parentEditID)
        XCTAssertLessThanOrEqual(priorParentEdit.count, 1)
        // Retained accessibility nodes may be ignored only when not actionable.
        XCTAssertFalse(priorParentEdit.count == 1 && priorParentEdit.element.isHittable)
        XCTAssertTrue(childEdits.element.isHittable)
        childEdits.element.tap()
        if !app.textFields["First name (optional)"].waitForExistence(timeout: 5) {
            let shot = XCTAttachment(screenshot: app.screenshot()); shot.lifetime = .keepAlways; add(shot)
            XCTFail("Person editor did not open"); return
        }
        recordEditState(app, parentID: parentEditID, stage: "strict editor outcome")
        XCTAssertEqual(app.textFields["First name (optional)"].value as? String, "First name (optional)")
        app.textFields["First name (optional)"].tap()
        app.textFields["First name (optional)"].typeText("Canceled Name")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Child 2"].exists)
        XCTAssertEqual(childBars.count, 1)
        let sameChildEdit = childBars.element.buttons.matching(identifier: childEditID)
        XCTAssertEqual(sameChildEdit.count, 1)
        XCTAssertLessThanOrEqual(priorParentEdit.count, 1)
        XCTAssertFalse(priorParentEdit.count == 1 && priorParentEdit.element.isHittable)
        XCTAssertTrue(sameChildEdit.element.isHittable)
        sameChildEdit.element.tap()
        if !app.textFields["First name (optional)"].waitForExistence(timeout: 5) {
            let shot = XCTAttachment(screenshot: app.screenshot()); shot.lifetime = .keepAlways; add(shot)
            XCTFail("Person editor did not open"); return
        }
        recordEditState(app, parentID: parentEditID, stage: "strict editor outcome")
        XCTAssertEqual(app.textFields["First name (optional)"].value as? String, "First name (optional)")
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
    @MainActor func testObserveInheritedParentAction() {
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
        let parentEdits = app.navigationBars["Synthetic Parent"].buttons.matching(
            NSPredicate(format: "label == %@ AND identifier BEGINSWITH %@", "Edit", "edit-person-"))
        XCTAssertEqual(parentEdits.count, 1)
        let parentEditID = parentEdits.element.identifier
        XCTAssertNotNil(UUID(uuidString: String(parentEditID.dropFirst("edit-person-".count))))
        app.buttons["Add child"].tap()
        app.buttons["Create new person"].tap()
        XCTAssertFalse(app.staticTexts["Name unknown"].exists)
        XCTAssertEqual(app.textFields["First name (optional)"].value as? String, "First name (optional)")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Child 2"].waitForExistence(timeout: 5))
        app.staticTexts["Child 2"].tap()
        recordEditState(app, parentID: parentEditID, stage: "observe entry")
        let deadline = Date().addingTimeInterval(5)
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in Date() >= deadline }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 6), .completed)
        recordEditState(app, parentID: parentEditID, stage: "observe settled")
        let parentAction = app.navigationBars["Child 2"].buttons.matching(identifier: parentEditID)
        XCTAssertLessThanOrEqual(parentAction.count, 1)
        if parentAction.count == 1 && parentAction.element.isHittable {
            parentAction.element.tap()
            let field = app.textFields["First name (optional)"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            let value = field.value as? String
            let outcome = value == "Synthetic Parent" ? "parent" : value == "First name (optional)" ? "unnamed child" : "other"
            print("KIN_EDIT_DIAGNOSTIC " + String(decoding: try! JSONSerialization.data(withJSONObject: ["stage": "parent action outcome", "editorIdentity": outcome]), as: UTF8.self))
            recordEditState(app, parentID: parentEditID, stage: "parent action editor")
            app.buttons["Cancel"].tap()
        }
        app.terminate()
    }
    @MainActor private func openAllPeople(_ app: XCUIApplication) {
        app.buttons["people-menu"].tap(); app.buttons["All people"].tap()
    }
    @MainActor private func recordEditState(_ app: XCUIApplication, parentID: String, stage: String) {
        let bars = app.navigationBars.matching(identifier: "Child 2")
        let global = app.navigationBars.buttons.matching(identifier: "Edit")
        var controls: [[String: Any]] = []
        if bars.count == 1 {
            for control in bars.element.buttons.matching(identifier: "Edit").allElementsBoundByIndex {
                controls.append(["id": control.identifier, "isParent": control.identifier == parentID,
                                 "hittable": control.isHittable, "frame": String(describing: control.frame)])
            }
        }
        let state: [String: Any] = ["stage": stage, "parentID": parentID,
                                  "childBarCount": bars.count, "globalEditCount": global.count,
                                  "controls": controls]
        let data = try! JSONSerialization.data(withJSONObject: state, options: [.sortedKeys])
        print("KIN_EDIT_DIAGNOSTIC " + String(decoding: data, as: UTF8.self))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Synthetic Edit diagnostic " + stage; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "Synthetic Edit diagnostic hierarchy " + stage; tree.lifetime = .keepAlways; add(tree)
    }
}
