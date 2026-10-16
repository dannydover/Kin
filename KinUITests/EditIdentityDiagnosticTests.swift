import XCTest
import Darwin

// Temporary synthetic-only diagnostic; never part of PR 33 required checks.
final class EditIdentityDiagnosticTests: XCTestCase {
    private var diagnosticProbe = "baseline"
    private var injectQueryFailure = false
    private var diagnosticOperation = "setup"
    private var diagnosticOperationLine: UInt = 0
    override func record(_ issue: XCTIssue) {
        // Save before XCTest aborts the current operation. Only the privacy filter
        // may publish this private runner-side record.
        let location = issue.sourceCodeContext.location
        let item: [String: Any] = ["probe": diagnosticProbe,
            "source": location?.fileURL.lastPathComponent ?? "unknown",
            "line": location?.lineNumber ?? 0,
            "operation": diagnosticOperation, "operationLine": diagnosticOperationLine,
            "message": issue.compactDescription,
            "detail": issue.detailedDescription ?? ""]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("KinEditDiagnostic", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: item).write(
                to: directory.appendingPathComponent(UUID().uuidString + ".issue.json"), options: .atomic)
        } catch { /* The bounded supervisor still reports an unsuccessful probe. */ }
        super.record(issue)
    }
    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor func testBaselineBroadEditQuery() {
        let probe = "baseline"
        diagnosticProbe = probe
        progress(probe, "started")
        let app = XCUIApplication()
        app.launchArguments = ["--kin-test-notebook", UUID().uuidString]
        progress(probe, "launch requested")
        app.launch()
        progress(probe, "launched")
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
            self.progress(probe, "teardown requested")
            self.recordEditState(app, parentID: parentEditID, stage: "baseline teardown")
        }
        app.buttons["Add child"].tap()
        app.buttons["Create new person"].tap()
        XCTAssertFalse(app.staticTexts["Name unknown"].exists)
        XCTAssertEqual(app.textFields["First name (optional)"].value as? String, "First name (optional)")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Child 2"].waitForExistence(timeout: 5))
        progress(probe, "child navigation requested")
        app.staticTexts["Child 2"].tap()
        progress(probe, "child navigation completed")
        progress(probe, "edit requested")
        markOperation("baseline broad Edit tap")
        app.navigationBars.buttons["Edit"].tap()
        progress(probe, "edit dispatched")
        if !app.textFields["First name (optional)"].waitForExistence(timeout: 5) {
            let shot = XCTAttachment(screenshot: app.screenshot()); shot.lifetime = .keepAlways; add(shot)
            XCTFail("Person editor did not open"); return
        }
        recordEditState(app, parentID: parentEditID, stage: "baseline editor outcome")
        app.textFields["First name (optional)"].tap()
        app.textFields["First name (optional)"].typeText("Canceled Name")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Child 2"].exists)
        progress(probe, "edit requested")
        markOperation("baseline broad Edit tap")
        app.navigationBars.buttons["Edit"].tap()
        progress(probe, "edit dispatched")
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
        progress(probe, "completed")
    }
    @MainActor func testStrictChildIdentityCandidate() {
        let probe = "strict"
        diagnosticProbe = probe
        progress(probe, "started")
        let app = XCUIApplication()
        app.launchArguments = ["--kin-test-notebook", UUID().uuidString]
        progress(probe, "launch requested")
        app.launch()
        progress(probe, "launched")
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
            self.progress(probe, "teardown requested")
            self.recordEditState(app, parentID: parentEditID, stage: "strict teardown")
        }
        app.buttons["Add child"].tap()
        app.buttons["Create new person"].tap()
        XCTAssertFalse(app.staticTexts["Name unknown"].exists)
        XCTAssertEqual(app.textFields["First name (optional)"].value as? String, "First name (optional)")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Child 2"].waitForExistence(timeout: 5))
        progress(probe, "child navigation requested")
        app.staticTexts["Child 2"].tap()
        progress(probe, "child navigation completed")
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
        progress(probe, "edit requested")
        childEdits.element.tap()
        progress(probe, "edit dispatched")
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
        progress(probe, "edit requested")
        sameChildEdit.element.tap()
        progress(probe, "edit dispatched")
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
        progress(probe, "completed")
    }
    @MainActor func testObserveInheritedParentAction() {
        let probe = "observe"
        diagnosticProbe = probe
        progress(probe, "started")
        let app = XCUIApplication()
        app.launchArguments = ["--kin-test-notebook", UUID().uuidString]
        progress(probe, "launch requested")
        app.launch()
        progress(probe, "launched")
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
        progress(probe, "child navigation requested")
        app.staticTexts["Child 2"].tap()
        progress(probe, "child navigation completed")
        // Capture independently before any per-control resolution can fail.
        recordEntrySnapshot(app, parentID: parentEditID)
        if injectQueryFailure {
            // Read-only ambiguous resolution exercises XCTest's real query error.
            let ambiguous = app.buttons.matching(NSPredicate(
                format: "label == %@ OR label == %@", "Add child", "Add partner"))
            XCTAssertEqual(ambiguous.count, 2)
            markOperation("injected ambiguous query")
            _ = ambiguous.element.identifier
            XCTFail("Synthetic injected ambiguity unexpectedly resolved")
            return
        }
        progress(probe, "control query requested")
        markOperation("observer entry controls")
        recordEditState(app, parentID: parentEditID, stage: "observe entry")
        let deadline = Date().addingTimeInterval(5)
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in Date() >= deadline }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 6), .completed)
        markOperation("observer settled controls")
        recordEditState(app, parentID: parentEditID, stage: "observe settled")
        let parentAction = app.navigationBars["Child 2"].buttons.matching(identifier: parentEditID)
        XCTAssertLessThanOrEqual(parentAction.count, 1)
        if parentAction.count == 1 && parentAction.element.isHittable {
            markOperation("parent action tap")
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
        progress(probe, "completed")
    }
    // Local failure-path validation only; never selected by the CI workflow.
    @MainActor func testInjectedQueryFailureRetention() {
        injectQueryFailure = true
        testObserveInheritedParentAction()
    }
    @MainActor private func recordEntrySnapshot(_ app: XCUIApplication, parentID: String) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("KinEditDiagnostic", isDirectory: true)
        let stem = UUID().uuidString
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // Commit the image first; a later hierarchy query must not erase it.
            markOperation("entry screenshot")
            try app.screenshot().pngRepresentation.write(to: directory.appendingPathComponent(stem + ".png"), options: .atomic)
            var capture: [String: Any] = ["captureStage": "observe entry", "parentID": parentID, "image": stem + ".png",
                "hierarchy": NSNull(), "label": "Synthetic Edit diagnostic observe entry snapshot"]
            let marker = directory.appendingPathComponent(stem + ".capture.json")
            try JSONSerialization.data(withJSONObject: capture).write(to: marker, options: .atomic)
            markOperation("entry hierarchy")
            try Data(app.debugDescription.utf8).write(to: directory.appendingPathComponent(stem + ".txt"), options: .atomic)
            capture["hierarchy"] = stem + ".txt"
            try JSONSerialization.data(withJSONObject: capture).write(to: marker, options: .atomic)
            progress("observe", "entry snapshot saved")
        } catch { progress("observe", "evidence write failed") }
    }
    @MainActor private func markOperation(_ operation: String, line: UInt = #line) {
        diagnosticOperation = operation
        diagnosticOperationLine = line
    }
    @MainActor private func openAllPeople(_ app: XCUIApplication) {
        app.buttons["people-menu"].tap(); app.buttons["All people"].tap()
    }
    @MainActor private func progress(_ probe: String, _ stage: String) {
        let data = try! JSONSerialization.data(withJSONObject: ["probe": probe, "stage": stage], options: [.sortedKeys])
        print("KIN_EDIT_PROGRESS " + String(decoding: data, as: UTF8.self)); fflush(nil)
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
        print("KIN_EDIT_DIAGNOSTIC " + String(decoding: data, as: UTF8.self)); fflush(nil)
        let screenshot = app.screenshot()
        let hierarchy = app.debugDescription
        // Atomic sidecars survive an unfinished result bundle. Synthetic simulator only.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("KinEditDiagnostic", isDirectory: true)
        let stem = UUID().uuidString
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try screenshot.pngRepresentation.write(to: directory.appendingPathComponent(stem + ".png"), options: .atomic)
            try Data(hierarchy.utf8).write(to: directory.appendingPathComponent(stem + ".txt"), options: .atomic)
            let metadata: [String: Any] = ["observation": state, "image": stem + ".png",
                                          "hierarchy": stem + ".txt", "label": "Synthetic Edit diagnostic " + stage]
            try JSONSerialization.data(withJSONObject: metadata).write(to: directory.appendingPathComponent(stem + ".json"), options: .atomic)
        } catch {
            progress(stage.hasPrefix("baseline") ? "baseline" : stage.hasPrefix("strict") ? "strict" : "observe", "evidence write failed")
        }
        let shot = XCTAttachment(screenshot: screenshot)
        shot.name = "Synthetic Edit diagnostic " + stage; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: hierarchy)
        tree.name = "Synthetic Edit diagnostic hierarchy " + stage; tree.lifetime = .keepAlways; add(tree)
    }
}
