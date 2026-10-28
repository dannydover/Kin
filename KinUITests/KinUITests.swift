import XCTest
import Contacts
import UIKit

final class KinUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        let status = CNContactStore.authorizationStatus(for: .contacts)
        let label: String
        switch status {
        case .notDetermined: label = "notDetermined"
        case .restricted: label = "restricted"
        case .denied: label = "denied"
        case .authorized: label = "authorized"
        case .limited: label = "limited"
        @unknown default: label = "unknown"
        }
        print("KIN_CI_AUTH \(label)")
    }
    @MainActor func testNormalColdLaunchOpensNotebookAndPreservesSavedPerson() throws {
        #if targetEnvironment(simulator)
        // Run only in a fresh isolated simulator: exercise the normal notebook,
        // with no preview/test-store arguments, including in Release builds.
        let app = XCUIApplication()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons["Add person"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["Notebook locked"].exists)
        let name = "Synthetic Cold Launch " + String(UUID().uuidString.prefix(8))
        addPerson(app, name: name)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["Notebook locked"].exists)
        app.staticTexts[name].tap()
        XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 5))
        app.terminate()
        #else
        throw XCTSkip("Normal notebook startup regression requires an isolated simulator.")
        #endif
    }
    @MainActor func testUnnamedDraftContactsReviewOmitsTemporaryIdentityInEveryCreationFlow() throws {
        let app = XCUIApplication(); app.launchArguments = ["--kin-test-notebook", UUID().uuidString]
        app.launch(); addPerson(app,name: "Synthetic Source")
        for route in ["Add person","Add child","Add partner","Add parent"] {
            if route == "Add person" { app.buttons[route].tap() }
            else {
                app.staticTexts["Synthetic Source"].tap(); reveal(app.buttons[route],in: app); app.buttons[route].tap()
                app.buttons["Create new person"].tap()
            }
            app.buttons["Import from Contacts"].tap()
            XCTAssertTrue(waitForNativeContactsPicker(app))
            guard app.cells["John Appleseed"].waitForExistence(timeout: 5) else {
                app.navigationBars["Contacts"].buttons["Cancel"].tap()
                throw XCTSkip("Use an isolated simulator with the standard synthetic Contacts sample card.")
            }
            app.cells["John Appleseed"].tap()
            XCTAssertTrue(app.navigationBars["Contact birth information"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.staticTexts["contact-current-draft"].exists)
            for role in ["Person","Parent","Child","Partner"] { XCTAssertFalse(app.staticTexts[role + " 0"].exists) }
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "contact-selected-contact").firstMatch.label.contains("John Appleseed"))
            if route == "Add parent" { capture(app,"New unnamed parent import review has no temporary identity") }
            app.buttons["contact-cancel"].tap()
            XCTAssertEqual(app.textFields["First name (optional)"].value as? String,"First name")
            app.navigationBars["Add person"].buttons["Cancel"].tap()
            if route != "Add person" {
                app.navigationBars[route].buttons["Cancel"].tap(); app.navigationBars.buttons["People"].tap()
            }
        }
        openAllPeople(app); XCTAssertEqual(app.cells.count,1)
        app.staticTexts["Synthetic Source"].tap(); reveal(app.buttons["Add parent"],in: app); app.buttons["Add parent"].tap()
        app.buttons["Create new person"].tap(); app.buttons["Save"].tap()
        // Review/cancel never creates an identity or consumes the next saved reference.
        XCTAssertTrue(app.staticTexts["Parent 2"].waitForExistence(timeout: 5))
    }
    @MainActor func testRelationshipRoleLabelsFromBothDirectionsAndForPartners() {
        let app = XCUIApplication(); app.launchArguments = ["--kin-test-notebook", UUID().uuidString]
        app.launch(); addPerson(app,name: "Synthetic Parent"); addPerson(app,name: "Synthetic Child"); addPerson(app,name: "Synthetic Partner")
        app.staticTexts["Synthetic Parent"].tap(); app.buttons["Add child"].tap(); chooseExistingPerson(app,name: "Synthetic Child")
        assertParentRoles(app,parent: "Synthetic Parent",child: "Synthetic Child")
        capture(app,"Add child clearly labels parent and child")
        app.buttons["Save"].tap(); app.buttons["Edit relationship with Synthetic Child"].tap()
        assertParentRoles(app,parent: "Synthetic Parent",child: "Synthetic Child")
        app.navigationBars["Edit relationship"].buttons["Cancel"].tap()
        app.staticTexts["Synthetic Child"].tap()
        app.buttons["Edit relationship with Synthetic Parent"].tap()
        assertParentRoles(app,parent: "Synthetic Parent",child: "Synthetic Child")
        app.navigationBars["Edit relationship"].buttons["Cancel"].tap()
        reveal(app.buttons["Add parent"],in: app); app.buttons["Add parent"].tap(); chooseExistingPerson(app,name: "Synthetic Partner")
        assertParentRoles(app,parent: "Synthetic Partner",child: "Synthetic Child")
        capture(app,"Add parent clearly labels selected parent and current child")
        app.navigationBars["Add relationship"].buttons["Cancel"].tap(); backToRelationshipOptions(app,title: "Add parent"); app.navigationBars["Add parent"].buttons["Cancel"].tap()
        app.navigationBars.buttons["Synthetic Parent"].tap()
        app.buttons["Add partner"].tap(); chooseExistingPerson(app,name: "Synthetic Partner")
        assertPartnerRoles(app,names: ["Synthetic Parent","Synthetic Partner"])
        capture(app,"Partner labels are symmetric")
        app.buttons["Save"].tap(); app.buttons["Edit relationship with Synthetic Partner"].tap()
        assertPartnerRoles(app,names: ["Synthetic Parent","Synthetic Partner"])
        app.navigationBars["Edit relationship"].buttons["Cancel"].tap()
        app.staticTexts["Synthetic Partner"].tap(); app.buttons["Edit relationship with Synthetic Parent"].tap()
        assertPartnerRoles(app,names: ["Synthetic Parent","Synthetic Partner"])
    }
    @MainActor func testRelationshipRoleLabelsWrapLongNamesAtLargestDynamicType() {
        let app = XCUIApplication(); app.launchArguments = ["--kin-test-notebook", UUID().uuidString]
        let parent = "Alexandria Synthetic Parent With A Long Family Name"
        let child = "Christopher Synthetic Child With A Long Family Name"
        app.launch(); addPerson(app,name: parent); addPerson(app,name: child)
        app.terminate(); app.launchArguments += ["-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"]; app.launch()
        app.staticTexts[parent].tap(); reveal(app.buttons["Add child"],in: app); app.buttons["Add child"].tap()
        chooseExistingPerson(app,name: child)
        for (role,name) in [("Parent",parent),("Child",child)] {
            let row = app.descendants(matching: .any).matching(identifier: "relationship-" + role.lowercased()).firstMatch
            revealPrecisely(row,in: app)
            XCTAssertEqual(row.label,role + ": " + name)
            XCTAssertTrue(row.isHittable)
            XCTAssertGreaterThan(row.frame.height,100)
            XCTAssertGreaterThanOrEqual(row.frame.minY,145)
            XCTAssertLessThanOrEqual(row.frame.maxY,app.frame.maxY - 100)
            capture(app,"Largest Dynamic Type complete long " + role + " name and role")
        }
        XCTAssertTrue(app.navigationBars["Add relationship"].buttons["Save"].isHittable)
        XCTAssertTrue(app.navigationBars["Add relationship"].buttons["Cancel"].isHittable)
        app.navigationBars["Add relationship"].buttons["Cancel"].tap()
        backToRelationshipOptions(app,title: "Add child")
        app.navigationBars["Add child"].buttons["Cancel"].tap()
        XCTAssertFalse(app.buttons["Edit relationship with " + child].exists)
    }
    @MainActor private func cancelRelationshipDraft(_ app: XCUIApplication, parent: String, child: String) throws {
        assertParentRoles(app, parent: parent, child: child)
        let bar = app.navigationBars["Add relationship"]
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        let matches = bar.buttons.matching(identifier: "Cancel")
        // Navigation transitions can temporarily expose both cancellation items.
        // Never choose arbitrarily if more than one remains actionable.
        let unique = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            matches.allElementsBoundByIndex.filter { $0.isHittable }.count == 1
        }, object: bar)
        let result = XCTWaiter.wait(for: [unique], timeout: 10)
        let actionable = matches.allElementsBoundByIndex.filter { $0.isHittable }
        guard result == .completed && actionable.count == 1 else {
            capture(app, "Relationship cancellation did not settle uniquely")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Ambiguous relationship Cancel hierarchy"
            hierarchy.lifetime = .keepAlways; add(hierarchy)
            XCTFail("Expected exactly one hittable Cancel in Add relationship; found \(actionable.count).")
            throw NSError(domain: "KinUITests.RelationshipCancel", code: 1)
        }
        actionable[0].tap()
        backToRelationshipOptions(app,title: "Add parent")
        XCTAssertTrue(app.navigationBars["Add parent"].waitForExistence(timeout: 5))
    }
    @MainActor private func assertParentRoles(_ app: XCUIApplication,parent: String,child: String) {
        let parentRow = app.descendants(matching: .any).matching(identifier: "relationship-parent").firstMatch
        let childRow = app.descendants(matching: .any).matching(identifier: "relationship-child").firstMatch
        XCTAssertTrue(parentRow.waitForExistence(timeout: 5)); XCTAssertTrue(childRow.exists)
        XCTAssertEqual(parentRow.label,"Parent: " + parent); XCTAssertEqual(childRow.label,"Child: " + child)
        XCTAssertLessThan(parentRow.frame.minY,childRow.frame.minY)
    }
    @MainActor private func assertPartnerRoles(_ app: XCUIApplication,names: Set<String>) {
        let first = app.descendants(matching: .any).matching(identifier: "relationship-partner-first").firstMatch
        let second = app.descendants(matching: .any).matching(identifier: "relationship-partner-second").firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5)); XCTAssertTrue(second.exists)
        XCTAssertEqual(Set([first.label,second.label]),Set(names.map { "Partner: " + $0 }))
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "relationship-parent").firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "relationship-child").firstMatch.exists)
    }
    // Separate complete scenarios keep the unchanged per-test runtime bound meaningful.
    @MainActor private func prepareYoungPersonAndExistingParent() -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--kin-test-notebook", UUID().uuidString]
        app.launch(); addPerson(app,name: "Synthetic Young"); addPerson(app,name: "Synthetic Existing Parent")
        app.staticTexts["Synthetic Young"].tap(); app.navigationBars.buttons["Edit"].tap()
        let birth = app.buttons["Birth information, Unknown"]
        reveal(birth,in: app); birth.tap(); app.buttons["Estimated age"].tap()
        chooseAge(app,value: 3); app.buttons["Save"].tap()
        XCTAssertFalse(app.buttons["Add child"].exists); XCTAssertFalse(app.buttons["Add partner"].exists)
        return app
    }
    @MainActor private func linkExistingBiologicalParent(_ app: XCUIApplication) {
        app.buttons["Add parent"].tap(); app.buttons["relationship-details"].tap(); app.buttons["Parent relationship, Unspecified"].tap(); app.buttons["Biological"].tap()
        chooseExistingPerson(app,name: "Synthetic Existing Parent"); app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Biological parent"].waitForExistence(timeout: 5))
    }
    @MainActor func testAddParentsReuseAndCancel() throws {
        let app = prepareYoungPersonAndExistingParent(); defer { app.terminate() }
        app.buttons["Add parent"].tap()
        XCTAssertTrue(app.buttons["relationship-details"].exists)
        XCTAssertFalse(app.buttons["Parent relationship, Unspecified"].exists)
        XCTAssertFalse(app.buttons["Synthetic Young"].exists)
        chooseExistingPerson(app,name: "Synthetic Existing Parent")
        try cancelRelationshipDraft(app, parent: "Synthetic Existing Parent", child: "Synthetic Young")
        app.navigationBars["Add parent"].buttons["Cancel"].tap()
        XCTAssertFalse(app.buttons["Edit relationship with Synthetic Existing Parent"].exists)
        app.buttons["Add parent"].tap(); app.buttons["relationship-details"].tap(); app.buttons["Parent relationship, Unspecified"].tap(); app.buttons["Biological"].tap()
        chooseExistingPerson(app,name: "Synthetic Existing Parent"); app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Biological parent"].waitForExistence(timeout: 5))
    }
    @MainActor func testAddParentsDuplicateRejectionPreservesBothPeople() throws {
        let app = prepareYoungPersonAndExistingParent(); defer { app.terminate() }
        linkExistingBiologicalParent(app)
        // Re-selecting a linked person must reject the duplicate without changing either person.
        app.buttons["Add parent"].tap(); chooseExistingPerson(app,name: "Synthetic Existing Parent"); app.buttons["Save"].tap()
        XCTAssertTrue(app.alerts["Couldn’t finish"].waitForExistence(timeout: 5)); app.alerts.buttons["OK"].tap()
        try cancelRelationshipDraft(app, parent: "Synthetic Existing Parent", child: "Synthetic Young"); app.navigationBars["Add parent"].buttons["Cancel"].tap()
    }
    @MainActor func testAddParentsReverseCycleRejectionAndDraftCancellation() throws {
        let app = prepareYoungPersonAndExistingParent(); defer { app.terminate() }
        linkExistingBiologicalParent(app)
        app.staticTexts["Synthetic Existing Parent"].tap()
        XCTAssertTrue(app.navigationBars["Synthetic Existing Parent"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Synthetic Young"].exists)
        // The reverse link would create a cycle and must also fail visibly.
        reveal(app.buttons["Add parent"],in: app); app.buttons["Add parent"].tap()
        chooseExistingPerson(app,name: "Synthetic Young"); app.buttons["Save"].tap()
        XCTAssertTrue(app.alerts["Couldn’t finish"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts.staticTexts["This would make someone their own ancestor. Check the parent and child you selected."].exists)
        app.alerts.buttons["OK"].tap(); try cancelRelationshipDraft(app, parent: "Synthetic Young", child: "Synthetic Existing Parent"); app.navigationBars["Add parent"].buttons["Cancel"].tap()
        app.navigationBars.buttons["Synthetic Young"].tap()
        XCTAssertTrue(app.navigationBars["Synthetic Young"].waitForExistence(timeout: 5))
    }
    @MainActor func testAddParentsCreatePersistNavigateAndUnlink() throws {
        let app = prepareYoungPersonAndExistingParent(); defer { app.terminate() }
        linkExistingBiologicalParent(app)
        app.buttons["Add parent"].tap(); app.buttons["relationship-details"].tap(); app.buttons["Parent relationship, Unspecified"].tap(); app.buttons["Step"].tap()
        app.buttons["Create new person"].tap(); app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Parent 3"].waitForExistence(timeout: 5)); XCTAssertTrue(app.staticTexts["Step parent"].exists)
        capture(app,"Young profile with two explicitly added parents")
        app.terminate(); app.launch()
        let youngRow = app.cells.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Synthetic Young"))
        XCTAssertEqual(youngRow.count,1); youngRow.element.tap()
        app.buttons["Edit relationship with Synthetic Existing Parent"].tap(); app.buttons["Remove relationship"].tap()
        app.alerts["Remove relationship?"].buttons["Cancel"].tap()
        app.buttons["Remove relationship"].tap(); app.buttons.matching(identifier: "confirm-unlink").allElementsBoundByIndex.last!.tap()
        XCTAssertFalse(app.buttons["Edit relationship with Synthetic Existing Parent"].exists)
        XCTAssertTrue(app.staticTexts["Parent 3"].exists)
        app.navigationBars.buttons["People"].tap(); openAllPeople(app)
        XCTAssertTrue(app.staticTexts["Synthetic Existing Parent"].exists); XCTAssertTrue(app.staticTexts["Parent 3"].exists)
    }
    @MainActor func testAddParentUsesSharedContactsReviewAndKeepsNewParentUnlisted() throws {
        let app = XCUIApplication(); app.launchArguments = ["--kin-test-notebook", UUID().uuidString]
        app.launch(); addPerson(app,name: "Synthetic Child")
        app.staticTexts["Synthetic Child"].tap(); reveal(app.buttons["Add parent"],in: app); app.buttons["Add parent"].tap()
        app.buttons["Create new person"].tap()
        XCTAssertTrue(app.buttons["Save"].isEnabled)
        app.buttons["gender-choice"].tap(); app.buttons["Unspecified"].tap()
        func selectSample() throws {
            app.buttons["Import from Contacts"].tap()
            XCTAssertTrue(waitForNativeContactsPicker(app))
            guard app.cells["John Appleseed"].waitForExistence(timeout: 5) else {
                app.navigationBars["Contacts"].buttons["Cancel"].tap()
                throw XCTSkip("Use an isolated simulator with the standard synthetic Contacts sample card.")
            }
            app.cells["John Appleseed"].tap()
            XCTAssertTrue(app.navigationBars["Contact birth information"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.staticTexts["contact-current-draft"].exists)
            XCTAssertFalse(app.staticTexts["Person 0"].exists)
            let gender = app.buttons["contact-gender-choice"]; reveal(gender,in: app)
            XCTAssertEqual(gender.value as? String,"Unspecified", "An explicit earlier draft choice survives import review")
        }
        try selectSample(); app.buttons["contact-cancel"].tap()
        XCTAssertEqual(app.buttons["gender-choice"].value as? String,"Unspecified")
        XCTAssertEqual(app.textFields["First name (optional)"].value as? String,"First name")
        try selectSample(); reveal(app.buttons["Import and Save without photo"],in: app)
        app.buttons["Import and Save without photo"].tap()
        XCTAssertTrue(app.staticTexts["John Appleseed"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Unspecified parent"].exists)
        app.staticTexts["John Appleseed"].tap()
        XCTAssertTrue(app.navigationBars["John Appleseed"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Gender: Unspecified"].exists)
        XCTAssertTrue(app.staticTexts["Synthetic Child"].exists)
        capture(app,"Imported parent links back to the original child")
        app.terminate(); app.launch()
        XCTAssertFalse(app.staticTexts["John Appleseed"].exists)
        app.staticTexts["Synthetic Child"].tap(); reveal(app.staticTexts["John Appleseed"],in: app)
        XCTAssertTrue(app.staticTexts["John Appleseed"].exists)
        app.navigationBars.buttons["People"].tap(); openAllPeople(app)
        XCTAssertEqual(app.staticTexts.matching(identifier: "John Appleseed").count,1)
    }
    @MainActor func testSharedEditorUnlistedRecoveryCancelAndRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["--kin-test-notebook", UUID().uuidString]
        app.launch()
        app.buttons["Add person"].tap()
        XCTAssertTrue(app.buttons["Save"].isEnabled)
        app.textFields["First name (optional)"].tap()
        app.textFields["First name (optional)"].typeText("Synthetic Parent")
        editorToggle("Friend", in: app).tap()
        XCTAssertTrue(app.buttons["Save"].isEnabled)
        app.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Synthetic Parent"].waitForExistence(timeout: 5))
        let parentEdits = app.navigationBars["Synthetic Parent"].buttons.matching(
            NSPredicate(format: "label == %@ AND identifier BEGINSWITH %@", "Edit", "edit-person-"))
        XCTAssertEqual(parentEdits.count, 1)
        let parentEditID = parentEdits.element.identifier
        XCTAssertNotNil(UUID(uuidString: String(parentEditID.dropFirst("edit-person-".count))))
        app.buttons["Add child"].tap()
        app.buttons["Create new person"].tap()
        XCTAssertFalse(app.staticTexts["Name unknown"].exists)
        XCTAssertEqual(app.textFields["First name (optional)"].value as? String, "First name")
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
            XCTFail("Person editor did not open"); return
        }
        XCTAssertEqual(app.textFields["First name (optional)"].value as? String, "First name")
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
            XCTFail("Person editor did not open"); return
        }
        XCTAssertEqual(app.textFields["First name (optional)"].value as? String, "First name")
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
        chooseExistingPerson(app,name: "Synthetic B")
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
        chooseExistingPerson(app,name: "Synthetic B")
        XCTAssertTrue(app.navigationBars["Add relationship"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Partner status, Current"].exists)
        capture(app, "New existing-person partner draft defaults Current")
        app.navigationBars["Add relationship"].buttons["Cancel"].tap()
        backToRelationshipOptions(app,title: "Add partner")
        app.navigationBars["Add partner"].buttons["Cancel"].tap()
        XCTAssertFalse(app.buttons["Edit relationship with Synthetic B"].exists)
        app.buttons["Add partner"].tap(); chooseExistingPerson(app,name: "Synthetic B")
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
        app.navigationBars.buttons["People"].tap()
        app.staticTexts["Synthetic Parent B"].tap(); app.buttons["Add child"].tap()
        chooseExistingPerson(app,name: "Child 3")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Child 3"].waitForExistence(timeout: 5))
        app.staticTexts["Child 3"].tap()
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["Synthetic Parent A"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Synthetic Parent B"].exists)
        app.navigationBars.buttons["Edit"].tap()
        app.textFields["First name (optional)"].tap(); app.textFields["First name (optional)"].typeText("Synthetic Shared Child")
        app.buttons["Save"].tap()
        app.navigationBars.buttons["Synthetic Parent B"].tap()
        XCTAssertTrue(app.staticTexts["Synthetic Shared Child"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["People"].tap(); app.staticTexts["Synthetic Parent A"].tap()
        XCTAssertTrue(app.staticTexts["Synthetic Shared Child"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["People"].tap()
        let previews = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "child-preview-"))
        XCTAssertEqual(previews.count, 2)
        XCTAssertEqual(Set(previews.allElementsBoundByIndex.map(\.identifier)).count, 1)
        capture(app, "Family context index with one child shared by two parents")
        app.terminate(); app.launch(); openAllPeople(app)
        XCTAssertTrue(app.staticTexts["Synthetic Shared Child"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts.matching(identifier: "Synthetic Shared Child").count,1)
    }
    @MainActor func testAllPeopleOpensProfilesAndReturnsToSameIndex() {
        let app = XCUIApplication(); app.launchArguments = ["--kin-test-notebook", UUID().uuidString]
        app.launch(); addPerson(app, name: "Synthetic Listed")
        app.staticTexts["Synthetic Listed"].tap(); app.buttons["Add child"].tap()
        app.buttons["Create new person"].tap()
        app.textFields["First name (optional)"].tap(); app.textFields["First name (optional)"].typeText("Synthetic Unlisted")
        app.buttons["Save"].tap(); app.navigationBars.buttons["People"].tap()
        openAllPeople(app)
        for name in ["Synthetic Unlisted", "Synthetic Listed", "Synthetic Unlisted"] {
            app.staticTexts[name].tap()
            XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["Edit"].exists)
            XCTAssertTrue(app.staticTexts["Gender: Unspecified"].exists)
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
    @MainActor func testPrivacyPolicyIsFinalAboutSectionAtNormalAndLargestText() {
        let app = XCUIApplication()
        let token = UUID().uuidString
        for largest in [false,true] {
            app.launchArguments = ["--kin-test-notebook",token]
            if largest { app.launchArguments += ["-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"] }
            app.launch(); app.buttons["people-menu"].tap(); app.buttons["About"].tap()
            XCTAssertTrue(app.navigationBars["About Kin"].waitForExistence(timeout: 5))
            // iOS 26 exposes SwiftUI Link through its legacy Button attribute;
            // iOS 27 exposes Link. Use the observed bounded native type on each.
            let policy: XCUIElement
            if #available(iOS 27, *) { policy = app.links["about-privacy-policy"] }
            else { policy = app.buttons["about-privacy-policy"] }
            let developer = app.staticTexts["Made by an indie developer"]
            let top = app.navigationBars["About Kin"].frame.maxY + 4
            let bottom = app.frame.maxY - 20
            for _ in 0..<12 {
                let frame = policy.frame
                if policy.isHittable && frame.minY >= top && frame.maxY <= bottom { break }
                let up = frame.maxY > bottom
                let distance = min((bottom - top) * 0.7,max(44,up ? frame.maxY - bottom + 8 : top - frame.minY + 8))
                let mid = (top + bottom) / 2
                let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.midX,dy: mid + (up ? distance / 2 : -distance / 2)))
                let end = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.midX,dy: mid + (up ? -distance / 2 : distance / 2)))
                start.press(forDuration: 0.05,thenDragTo: end,withVelocity: .slow,thenHoldForDuration: 0.15)
            }
            let geometry = XCTAttachment(string: "Privacy link=\(policy.frame) viewport=\(app.frame) top=\(top) requiredBottom=\(bottom)")
            geometry.name = "Synthetic Privacy Policy geometry"; geometry.lifetime = .keepAlways; add(geometry)
            capture(app,largest ? "About Privacy Policy geometry largest" : "About Privacy Policy geometry standard")
            XCTAssertTrue(policy.isHittable)
            XCTAssertLessThanOrEqual(policy.frame.maxY,app.frame.maxY - 20)
            XCTAssertTrue(developer.exists)
            XCTAssertLessThanOrEqual(developer.frame.maxY,policy.frame.minY)
            XCTAssertGreaterThanOrEqual(policy.frame.height,44)
            capture(app,largest ? "About final Privacy Policy at largest text" : "About final Privacy Policy")
            app.buttons["Done"].tap(); app.terminate()
        }
    }
    @MainActor func testIllustratedEmptyStateMenuAndSearchRecovery() {
        let app = XCUIApplication(); app.launchArguments = ["--kin-test-notebook", UUID().uuidString]
        app.launch()
        XCTAssertTrue(app.staticTexts["Keep your people close."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Add your first person"].isHittable)
        XCTAssertFalse(app.buttons["All people (including unlisted)"].exists)
        capture(app, "After illustrated empty notebook")
        app.buttons["people-menu"].tap(); capture(app, "People All people About menu")
        app.buttons["About"].tap(); XCTAssertTrue(app.navigationBars["About Kin"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        addPerson(app, name: "Synthetic Visible")
        app.staticTexts["Synthetic Visible"].tap(); app.navigationBars.buttons["Edit"].tap()
        editorToggle("Friend", in: app).tap()
        editorToggle("index-inclusion", in: app).tap(); app.buttons["Save"].tap()
        app.navigationBars.buttons["People"].tap()
        XCTAssertTrue(app.staticTexts["Your main list is empty"].waitForExistence(timeout: 5))
        capture(app, "Unlisted people remain recoverable")
        openAllPeople(app); XCTAssertTrue(app.staticTexts["Synthetic Visible"].waitForExistence(timeout: 5))
        app.searchFields.firstMatch.tap(); app.searchFields.firstMatch.typeText("NoSuchSyntheticPerson")
        XCTAssertTrue(app.staticTexts["No matches"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Keep your people close."].exists)
        capture(app, "Search with no matches")
        if app.buttons["Cancel"].exists { app.buttons["Cancel"].tap() } else { app.buttons["close"].tap() }
        app.buttons["people-menu"].tap(); app.buttons["People"].tap()
        XCTAssertTrue(app.staticTexts["Your main list is empty"].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        XCTAssertTrue(app.navigationBars["People"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Your main list is empty"].exists)
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
        app.staticTexts["Synthetic Young"].tap(); app.navigationBars.buttons["Edit"].tap()
        let initialBirthday = app.buttons["Birth information, Unknown"]
        reveal(initialBirthday, in: app); initialBirthday.tap()
        app.buttons["Estimated age"].tap()
        chooseAge(app,value: 3)
        app.buttons["Save"].tap()
        XCTAssertFalse(app.buttons["Add partner"].exists); XCTAssertFalse(app.buttons["Add child"].exists)
        XCTAssertFalse(app.staticTexts["Partners"].exists); XCTAssertFalse(app.staticTexts["Children"].exists)
        XCTAssertTrue(app.staticTexts["Parents"].exists)
        capture(app, "Under sixteen profile keeps Parents and hides family add controls")
        app.navigationBars.buttons["Edit"].tap()
        let birthday = app.buttons["Birth information, Estimated age"]
        reveal(birthday,in: app); birthday.tap()
        XCTAssertTrue(app.buttons["Unknown"].waitForExistence(timeout: 5))
        app.buttons["Unknown"].tap(); app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["Add partner"].waitForExistence(timeout: 5)); XCTAssertTrue(app.buttons["Add child"].exists)
    }
    @MainActor func testEstimatedAgeWheelBoundariesAndCancel() {
        let app = XCUIApplication(); app.launchArguments = ["--kin-test-notebook", UUID().uuidString]
        app.launch(); addEstimatedAdult(app,name: "Synthetic Older")
        app.navigationBars.buttons["Edit"].tap()
        let age = app.buttons["choose-estimated-age"]
        reveal(age,in: app); age.tap()
        app.pickerWheels.firstMatch.adjust(toPickerWheelValue: "120")
        app.navigationBars["Age in years"].buttons["Cancel"].tap()
        XCTAssertEqual(age.value as? String,"80")
        chooseAge(app,value: 120); app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@","Estimated 120 as of")).firstMatch.waitForExistence(timeout: 5))
        app.navigationBars.buttons["Edit"].tap(); chooseAge(app,value: 0)
        app.navigationBars["Edit person"].buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@","Estimated 120 as of")).firstMatch.exists)
        app.navigationBars.buttons["Edit"].tap(); chooseAge(app,value: 0); app.buttons["Save"].tap()
        app.terminate(); app.launch(); app.staticTexts["Synthetic Older"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@","Estimated 0 as of")).firstMatch.exists)
    }
    @MainActor func testEstimatedAgeWheelAtLargestDynamicType() {
        let app = XCUIApplication(); app.launchArguments = ["--kin-test-notebook", UUID().uuidString]
        app.launch(); addEstimatedAdult(app,name: "Synthetic Large Age")
        app.terminate(); app.launchArguments += ["-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"]; app.launch()
        app.staticTexts["Synthetic Large Age"].tap(); app.navigationBars.buttons["Edit"].tap()
        let age = app.buttons["choose-estimated-age"]
        reveal(age,in: app); revealPrecisely(age,in: app)
        XCTAssertTrue(age.isHittable)
        XCTAssertGreaterThanOrEqual(age.frame.minY,145)
        XCTAssertLessThanOrEqual(age.frame.maxY,app.frame.maxY - 100)
        // Avoid XCTest's large automatic scroll overshooting a dynamic-height row.
        age.coordinate(withNormalizedOffset: CGVector(dx: 0.5,dy: 0.5)).tap()
        XCTAssertTrue(app.navigationBars["Age in years"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.pickerWheels.firstMatch.waitForExistence(timeout: 5))
        app.pickerWheels.firstMatch.adjust(toPickerWheelValue: "120")
        capture(app,"Largest Dynamic Type native age wheel")
        XCTAssertTrue(app.navigationBars["Age in years"].buttons["Done"].isHittable)
        XCTAssertTrue(app.navigationBars["Age in years"].buttons["Cancel"].isHittable)
        app.navigationBars["Age in years"].buttons["Cancel"].tap()
        XCTAssertEqual(age.value as? String,"80")
        app.navigationBars["Edit person"].buttons["Cancel"].tap()
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
        app.navigationBars.buttons["Edit"].tap()
        let birthPicker = app.buttons["Birth information, Estimated age"]
        reveal(birthPicker, in: app); birthPicker.tap()
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
    @MainActor func testContactMissingBirthdayPromptCancellationAndEstimatedImport() throws {
        // Native Photos/Contacts interactions take longer on hosted simulators.
        executionTimeAllowance = 600
        #if targetEnvironment(simulator)
        let fixtureStore = CNContactStore()
        try XCTUnwrap(CNContactStore.authorizationStatus(for: .contacts) == .authorized ? true : nil,
                      "Grant Contacts access to the isolated UI test runner for synthetic fixtures.")
        let contactName = "Kin Synthetic No Birthday " + String(UUID().uuidString.prefix(8))
        let fixtureContact = CNMutableContact(); fixtureContact.givenName = contactName
        fixtureContact.imageData = UIGraphicsImageRenderer(size: CGSize(width: 64,height: 64)).image { context in
            UIColor.systemTeal.setFill(); context.fill(CGRect(x: 0,y: 0,width: 64,height: 64))
        }.pngData()
        let create = CNSaveRequest(); create.add(fixtureContact,toContainerWithIdentifier: nil)
        try fixtureStore.execute(create)
        defer {
            let remove = CNSaveRequest(); remove.delete(fixtureContact)
            try? fixtureStore.execute(remove)
        }
        let app = XCUIApplication(); app.launchArguments = ["--kin-test-notebook", UUID().uuidString]
        app.launch(); addEstimatedAdult(app, name: "Synthetic Existing Draft")
        app.navigationBars.buttons["Edit"].tap(); app.swipeUp(); app.buttons["Add photo"].tap()
        XCTAssertTrue(app.navigationBars["Photos"].waitForExistence(timeout: 15))
        let fixture = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        guard fixture.waitForExistence(timeout: 10) else { throw XCTSkip("Seed an isolated simulator with a synthetic Photos image.") }
        fixture.coordinate(withNormalizedOffset: CGVector(dx: 0.5,dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["Change photo"].waitForExistence(timeout: 10))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"),object: app.buttons["Save"])
        XCTAssertEqual(XCTWaiter.wait(for: [ready],timeout: 10),.completed); app.buttons["Save"].tap()
        app.navigationBars.buttons["Edit"].tap()
        func selectSample() throws {
            let editor = app.navigationBars["Edit person"]
            guard requireTestState(app, "Contacts import editor ready", {
                editor.exists && editor.isHittable
                    && !app.navigationBars["Photos"].exists
                    && !app.navigationBars["Contact birth information"].exists
            }) else { return }
            let importButton = app.buttons["Import from Contacts"]
            reveal(importButton, in: app, requireHittable: true)
            guard requireTestState(app, "Contacts import draft and button ready", {
                importButton.isHittable
                    && app.textFields["First name (optional)"].value as? String == "Synthetic Existing Draft"
            }) else { return }
            importButton.tap()
            let appeared = waitForNativeContactsPicker(app)
            if !appeared { recordTestState(app, stage: "Contacts picker did not appear") }
            XCTAssertTrue(appeared)
            let search = app.searchFields.firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText(contactName)
            let card = app.collectionViews["Search results"].cells[contactName].firstMatch
            XCTAssertTrue(card.waitForExistence(timeout: 5)); card.tap()
            XCTAssertTrue(app.navigationBars["Contact birth information"].waitForExistence(timeout: 10))
        }
        try selectSample()
        XCTAssertTrue(app.staticTexts["contact-current-draft"].exists)
        XCTAssertTrue(app.staticTexts["Synthetic Existing Draft"].exists)
        capture(app, "Contact missing birthday asks for birth information")
        let birthPicker = app.buttons["contact-birth-information"]
        reveal(birthPicker,in: app); birthPicker.tap()
        XCTAssertTrue(app.buttons["Exact birthday"].exists)
        XCTAssertTrue(app.buttons["Unknown"].exists); app.buttons["Unknown"].tap()
        app.buttons["contact-cancel"].tap()
        XCTAssertEqual(app.textFields["First name (optional)"].value as? String,"Synthetic Existing Draft")
        try selectSample()
        // Missing source data retains the saved estimate. Unknown is now a
        // deliberate reviewed edit, rather than an automatic import side effect.
        let retained = app.buttons["contact-birth-information"]
        reveal(retained,in: app); retained.tap(); app.buttons["Unknown"].tap()
        reveal(app.buttons["Continue without importing photo"],in: app)
        app.buttons["Continue without importing photo"].tap()
        XCTAssertEqual(app.textFields["First name (optional)"].value as? String,contactName)
        let unknownBirth = app.buttons["Birth information, Unknown"]
        reveal(unknownBirth,in: app); unknownBirth.tap(); app.buttons["Estimated age"].tap()
        XCTAssertFalse(app.buttons["Save"].isEnabled)
        chooseAge(app,value: 19)
        reveal(app.buttons["Add photo"],in: app)
        XCTAssertTrue(app.buttons["Add photo"].exists)
        XCTAssertFalse(app.buttons["Change photo"].exists)
        app.navigationBars["Edit person"].buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Synthetic Existing Draft"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@","Estimated 80 as of")).firstMatch.exists)
        app.navigationBars.buttons["Edit"].tap(); try selectSample()
        let picker = app.buttons["contact-birth-information"]
        reveal(picker,in: app); picker.tap(); app.buttons["Estimated age"].tap()
        chooseAge(app,value: 19,contact: true)
        capture(app, "Contact import accepts a confirmed estimated age")
        app.buttons["contact-import"].tap()
        app.navigationBars["Edit person"].buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars[contactName].waitForExistence(timeout: 5))
        app.terminate(); app.launch(); app.staticTexts[contactName].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@","Estimated 19 as of")).firstMatch.exists)
        #else
        throw XCTSkip("Synthetic Contacts fixture creation is restricted to isolated simulators.")
        #endif
    }
    @MainActor private func addEstimatedAdult(_ app: XCUIApplication, name: String) {
        addPerson(app, name: name); app.staticTexts[name].tap(); app.navigationBars.buttons["Edit"].tap()
        let birth = app.buttons["birth-information"]
        reveal(birth,in: app,requireHittable: true); birth.tap()
        XCTAssertTrue(app.buttons["Estimated age"].waitForExistence(timeout: 5))
        app.buttons["Estimated age"].tap()
        XCTAssertFalse(app.buttons["Save"].isEnabled)
        chooseAge(app,value: 80); app.buttons["Save"].tap()
    }
    @MainActor func testNewImportSavesReviewedNamesForEveryEntryPoint() throws {
        executionTimeAllowance = 600
        let app = XCUIApplication(); app.launchArguments = ["--kin-test-notebook", UUID().uuidString]
        app.launch(); addPerson(app,name: "Synthetic Import Source")
        let routes = ["Add person","Add parent","Add child","Add partner"]
        for (index,route) in routes.enumerated() {
            if index == 0 { app.buttons[route].tap() }
            else {
                app.staticTexts["Synthetic Import Source"].tap()
                reveal(app.buttons[route],in: app); app.buttons[route].tap()
                if index == 1 {
                    app.buttons["relationship-details"].tap()
                    app.buttons["Parent relationship, Unspecified"].tap(); app.buttons["Step"].tap()
                }
                app.buttons["Create new person"].tap()
            }
            app.buttons["Import from Contacts"].tap()
            XCTAssertTrue(waitForNativeContactsPicker(app))
            let card = app.cells["John Appleseed"]
            XCTAssertTrue(card.waitForExistence(timeout: 10), "Isolated simulator must have its standard synthetic contact")
            card.tap()
            XCTAssertTrue(app.navigationBars["Contact birth information"].waitForExistence(timeout: 10))
            if index == 0 { XCTAssertTrue(app.buttons["Import and Save"].isEnabled) }
            let first = app.textFields["Imported first name (optional)"]
            revealPrecisely(first,in: app); first.tap()
            first.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue,count: "John".count) + "Synthetic Saved \(index)")
            XCTAssertTrue(app.buttons["Import and Save"].isEnabled)
            app.buttons["contact-import"].tap()
            XCTAssertFalse(app.navigationBars["Contact birth information"].waitForExistence(timeout: 1))
            let name = "Synthetic Saved \(index) Appleseed"
            XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 10))
            XCTAssertFalse(app.navigationBars["Add person"].exists)
            if index == 0 {
                XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 5))
                app.navigationBars.buttons["Edit"].tap()
                XCTAssertEqual(editorSwitchWrapper("Friend", in: app).value as? String,"0")
                app.navigationBars["Edit person"].buttons["Cancel"].tap()
            }
            if index == 1 { XCTAssertTrue(app.staticTexts["Step parent"].exists) }
            app.terminate(); app.launch()
        }
        XCTAssertEqual(app.cells.count,2, "Only the source and direct import are listed")
        openAllPeople(app)
        for index in 0..<4 { XCTAssertTrue(app.staticTexts["Synthetic Saved \(index) Appleseed"].exists) }
        XCTAssertEqual(app.cells.count,5)
    }
    @MainActor func testChildSurnameIsEditableClearableAndNeverReapplied() {
        let app = XCUIApplication(); app.launchArguments = ["--kin-test-notebook", UUID().uuidString]
        app.launch(); app.buttons["Add person"].tap()
        app.textFields["First name (optional)"].tap(); app.textFields["First name (optional)"].typeText("Synthetic")
        app.textFields["Last name (optional)"].tap(); app.textFields["Last name (optional)"].typeText("Vale-Smith")
        editorToggle("Friend", in: app).tap(); app.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars["Synthetic Vale-Smith"].waitForExistence(timeout: 5)); reveal(app.buttons["Add child"],in: app); app.buttons["Add child"].tap()
        XCTAssertTrue(app.buttons["relationship-details"].exists)
        app.buttons["Create new person"].tap()
        let surname = app.textFields["Last name (optional)"]
        XCTAssertEqual(surname.value as? String,"Vale-Smith")
        surname.tap(); surname.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue,count: "Vale-Smith".count))
        app.buttons["gender-choice"].tap(); app.buttons["Female"].tap()
        XCTAssertEqual(surname.value as? String,"Last name")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Child 2"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Unspecified parentage"].exists)
        app.navigationBars.buttons["People"].tap()
        let unknown = app.staticTexts["Age unknown"].firstMatch
        XCTAssertTrue(unknown.exists)
        XCTAssertLessThan(unknown.frame.height,30)
        app.terminate(); app.launch()
        app.staticTexts["Synthetic Vale-Smith"].tap(); app.staticTexts["Child 2"].tap()
        let childProfile = app.navigationBars["Child 2"]
        XCTAssertTrue(childProfile.waitForExistence(timeout: 5))
        let editChild = childProfile.buttons["Edit"]
        XCTAssertTrue(editChild.waitForExistence(timeout: 5))
        XCTAssertTrue(editChild.isHittable)
        editChild.tap()
        XCTAssertEqual(surname.value as? String,"Last name")
    }
    @MainActor func testImportReviewRetainsFailedEditsAndAccessibilityHelpersWrap() throws {
        executionTimeAllowance = 600
        let app = XCUIApplication(); app.launchArguments = ["--kin-test-notebook", UUID().uuidString]
        app.launch(); app.buttons["Add person"].tap(); app.buttons["Import from Contacts"].tap()
        selectSettledNativeContact(app,name: "John Appleseed")
        XCTAssertTrue(app.navigationBars["Contact birth information"].waitForExistence(timeout: 10))
        let friends = app.switches.matching(identifier: "contact-connection-friend")
        XCTAssertEqual(friends.count,1)
        let friend = friends.element
        revealPrecisely(friend,in: app)
        var previousFriendFrame = CGRect.null
        var friendStableSince = Date()
        let friendReady = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard friend.exists && friend.isHittable else { return false }
            let frame = friend.frame
            guard frame.minY >= 145 && frame.maxY < app.buttons["contact-cancel"].frame.minY - 12 else { return false }
            if abs(frame.minY - previousFriendFrame.minY) > 0.5 || abs(frame.height - previousFriendFrame.height) > 0.5 {
                previousFriendFrame = frame; friendStableSince = Date(); return false
            }
            return Date().timeIntervalSince(friendStableSince) >= 1
        },object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [friendReady],timeout: 10),.completed)
        XCTAssertTrue(friend.isHittable)
        let friendFrame = friend.frame
        let diagnostics = XCTAttachment(string: app.debugDescription)
        diagnostics.name = "Synthetic Friend row and footer geometry"; diagnostics.lifetime = .keepAlways; add(diagnostics)
        let geometryImage = XCTAttachment(screenshot: app.screenshot())
        geometryImage.name = "Synthetic Friend row before guarded tap"; geometryImage.lifetime = .keepAlways; add(geometryImage)
        XCTAssertGreaterThanOrEqual(friendFrame.minY,145)
        XCTAssertLessThan(friendFrame.maxY,app.buttons["contact-cancel"].frame.minY - 12)
        XCTAssertEqual(friend.value as? String,"0")
        // Full-screen reveal swipes can overshoot and native switch auto-scroll
        // can hit the footer. Tap the settled uniquely identified visible row,
        // explicitly outside the persistent confirmation footer.
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: friendFrame.maxX - 35,dy: friendFrame.midY)).tap()
        XCTAssertEqual(friend.value as? String,"1")
        XCTAssertTrue(app.navigationBars["Contact birth information"].exists)
        verifyContactActionGeometry(app, largest: false)
        verifyContactLowerRowsReachable(app, largest: false)
        let first = app.textFields["Imported first name (optional)"]
        revealPrecisely(first,in: app); first.tap()
        first.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue,count: 4) + String(repeating: "x",count: 201))
        XCTAssertEqual(first.value as? String,String(repeating: "x",count: 201))
        XCTAssertTrue(app.buttons["Import and Save"].isEnabled)
        app.buttons["contact-import"].tap()
        XCTAssertTrue(app.alerts["Couldn’t finish"].waitForExistence(timeout: 5)); app.alerts.buttons["OK"].tap()
        reveal(first,in: app,requireHittable: true)
        XCTAssertEqual(first.value as? String,String(repeating: "x",count: 201))
        // The retained ASCII fixture is horizontally scrolled. Place the caret
        // at its visible trailing edge, then delete its complete known length.
        // Hardware Select All can instead leave a native edit menu open.
        first.coordinate(withNormalizedOffset: CGVector(dx: 1,dy: 0.5))
            .withOffset(CGVector(dx: -1,dy: 0)).tap()
        // Observe each bounded deletion chunk before issuing the next one.
        // A bulk key event can return before the field's accessibility value settles.
        for _ in 0..<8 {
            let current = first.value as? String ?? ""
            if current.isEmpty || current == first.placeholderValue { break }
            first.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue,count: min(current.count,32)))
            let shortened = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                let value = first.value as? String ?? ""
                return value.isEmpty || value == first.placeholderValue || value.count < current.count
            },object: nil)
            guard XCTWaiter.wait(for: [shortened],timeout: 5) == .completed else {
                XCTFail("Import review name did not shorten after the deletion chunk"); return
            }
        }
        let cleared = first.value as? String ?? ""
        guard cleared.isEmpty || cleared == first.placeholderValue else {
            XCTFail("Import review name was not fully cleared before replacement"); return
        }
        first.typeText("Synthetic Retry")
        let replacementReady = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            first.value as? String == "Synthetic Retry"
        },object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [replacementReady],timeout: 5),.completed)
        XCTAssertEqual(first.value as? String,"Synthetic Retry", "Verify replacement before retrying Save")
        app.buttons["contact-import"].doubleTap()
        XCTAssertTrue(app.navigationBars["Synthetic Retry Appleseed"].waitForExistence(timeout: 10))
        app.navigationBars.buttons["People"].tap()
        XCTAssertEqual(app.cells.count,1)
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL","-UIAccessibilityBoldTextEnabled","YES"]
        app.launch(); app.buttons["Add person"].tap(); app.buttons["Import from Contacts"].tap()
        selectSettledNativeContact(app,name: "John Appleseed")
        let reviewReady = app.navigationBars["Contact birth information"].waitForExistence(timeout: 10)
        if !reviewReady {
            #if targetEnvironment(simulator)
            XCTAssertTrue(app.launchArguments.contains("--kin-test-notebook"))
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Synthetic import accessibility failure"; screenshot.lifetime = .keepAlways; add(screenshot)
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Synthetic import accessibility hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
            #endif
        }
        XCTAssertTrue(reviewReady)
        verifyContactActionGeometry(app, largest: true)
        let reviewImage = XCTAttachment(screenshot: app.screenshot())
        reviewImage.name = "Contacts review largest text - synthetic"; reviewImage.lifetime = .keepAlways; add(reviewImage)
        try app.performAccessibilityAudit(for: [.contrast,.hitRegion,.textClipped,.trait]) { issue in
            print("Contacts review audit: \(issue.compactDescription); \(issue.detailedDescription); element=\(issue.element?.label ?? "unresolved")")
            return false
        }
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "contact-selected-contact").firstMatch.label.contains("John Appleseed"))
        for title in ["What changes","Before importing a photo"] {
            // Section footers can be exposed as Other rather than StaticText.
            let helper = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@",title)).firstMatch
            for _ in 0..<12 {
                if helper.exists && helper.frame.intersects(app.frame) { break }
                app.swipeUp()
            }
            XCTAssertTrue(helper.exists)
            XCTAssertLessThanOrEqual(helper.frame.width,app.frame.width)
            XCTAssertGreaterThan(helper.frame.height,30)
            XCTAssertTrue(helper.label.contains("Import and Save"))
        }
        verifyContactLowerRowsReachable(app, largest: true)
        app.buttons["contact-cancel"].tap()
        app.navigationBars["Add person"].buttons["Cancel"].tap()
        XCTAssertEqual(app.cells.count,1)
    }
    @MainActor func testCompactUnknownAgeWithLongNamesAtStandardAndAccessibilitySizes() {
        let app = XCUIApplication(); app.launchArguments = ["--kin-test-notebook", UUID().uuidString]
        let parent = "Synthetic Parent With A Long Compound Family Name"
        let child = "Synthetic Child With A Long Compound Family Name"
        app.launch(); addPerson(app,name: parent)
        app.staticTexts[parent].tap(); reveal(app.buttons["Add child"],in: app); app.buttons["Add child"].tap()
        app.buttons["Create new person"].tap()
        let first = app.textFields["First name (optional)"]; first.tap(); first.typeText(child)
        app.buttons["Save"].tap(); app.navigationBars.buttons["People"].tap()
        let status = app.staticTexts["Age unknown"].firstMatch
        XCTAssertTrue(status.exists)
        XCTAssertLessThan(status.frame.height,30)
        XCTAssertGreaterThan(status.frame.width,60)
        XCTAssertLessThanOrEqual(status.frame.maxX,app.frame.maxX)
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch(); reveal(status,in: app)
        XCTAssertTrue(status.exists)
        XCTAssertLessThanOrEqual(status.frame.width,app.frame.width)
        XCTAssertGreaterThan(status.frame.height,25)
        XCTAssertTrue(app.staticTexts[parent].exists)
    }
    @MainActor func testBabyMonthLabelsFitIndexAndDetail() {
        let app = XCUIApplication(); app.launchArguments = ["--kin-preview","babies"]
        app.launch()
        for label in ["Age unknown","Less than 1 month","1 month"] {
            let age = app.staticTexts[label].firstMatch
            XCTAssertTrue(age.waitForExistence(timeout: 5))
            XCTAssertGreaterThanOrEqual(age.frame.minX,0)
            XCTAssertLessThanOrEqual(age.frame.maxX,app.frame.maxX)
            if label == "Age unknown" { XCTAssertLessThan(age.frame.height,30) }
        }
        app.staticTexts["Synthetic Parent"].tap()
        for label in ["Less than 1 month","1 month","11 months","1 year"] {
            // Lazy relationship rows can disappear above the viewport. Restart at
            // the top before finding each label rather than assuming fetch order.
            for _ in 0..<5 { app.swipeDown() }
            let age = app.staticTexts[label].firstMatch
            reveal(age,in: app)
            XCTAssertTrue(age.exists)
        }
        XCTAssertFalse(app.staticTexts["12 months"].exists)
        XCTAssertFalse(app.staticTexts["23 months"].exists)
        app.terminate()
    }
    @MainActor private func selectSettledNativeContact(_ app: XCUIApplication,name: String) {
        XCTAssertTrue(waitForNativeContactsPicker(app))
        // Enumerate indexed native candidates: a relaunch can briefly expose
        // two picker trees, and a multi-match frame query is ambiguous.
        func targets() -> [XCUIElement] {
            app.otherElements.matching(identifier: "ContactsListView").allElementsBoundByIndex.flatMap { list in
                list.cells.matching(identifier: name).allElementsBoundByIndex.flatMap { cell in
                    cell.staticTexts.matching(identifier: name).allElementsBoundByIndex
                }
            }
        }
        func finite(_ target: XCUIElement) -> Bool {
            guard target.exists else { return false }
            let f = target.frame
            return f.minX.isFinite && f.minY.isFinite && f.width > 0 && f.height > 0
        }
        var chosen: XCUIElement?
        var previousFrame = CGRect.null
        var stableSince = Date()
        var scrolls = 0
        let stable = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let candidates = targets().filter(finite)
            let visible = candidates.filter {
                $0.isHittable && $0.frame.minY >= 145 && $0.frame.maxY <= app.frame.maxY - 100
            }
            if visible.count == 1 {
                let target = visible[0], frame = target.frame
                if abs(frame.minX - previousFrame.minX) > 0.5 || abs(frame.minY - previousFrame.minY) > 0.5
                    || abs(frame.width - previousFrame.width) > 0.5 || abs(frame.height - previousFrame.height) > 0.5 {
                    previousFrame = frame; stableSince = Date(); return false
                }
                guard Date().timeIntervalSince(stableSince) >= 1 else { return false }
                chosen = target; return true
            }
            previousFrame = .null; stableSince = Date()
            // Reveal only a unique finite candidate. The largest-text native
            // privacy guidance can place it below the viewport. Never pick an
            // arbitrary duplicate or change the native banner/permissions.
            if visible.isEmpty && candidates.count == 1 && scrolls < 16 {
                let frame = candidates[0].frame
                let up = frame.maxY > app.frame.maxY - 100
                let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5,dy: up ? 0.72 : 0.38))
                let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5,dy: up ? 0.42 : 0.65))
                start.press(forDuration: 0.05,thenDragTo: end); scrolls += 1
            }
            return false
        },object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [stable],timeout: 45),.completed,
                       "Require one stable hittable native contact after bounded reveal")
        guard let largeContactName = chosen else { return }
        XCTAssertTrue(largeContactName.isHittable)
        XCTAssertGreaterThanOrEqual(largeContactName.frame.minY,145)
        XCTAssertLessThanOrEqual(largeContactName.frame.maxY,app.frame.maxY - 100)
        #if targetEnvironment(simulator)
        let targetImage = XCTAttachment(screenshot: app.screenshot())
        targetImage.name = "Synthetic native Contacts target before selection"; targetImage.lifetime = .keepAlways; add(targetImage)
        #endif
        let targetFrame = largeContactName.frame
        print("Synthetic native Contacts target frame: \(targetFrame)")
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: targetFrame.midX,dy: targetFrame.midY)).tap()
    }
    @MainActor private func chooseExistingPerson(_ app: XCUIApplication,name: String) {
        app.buttons["Link an existing person"].tap()
        XCTAssertTrue(app.navigationBars["Choose a person"].waitForExistence(timeout: 5))
        let choice = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@","existing-person-",name)).firstMatch
        reveal(choice,in: app,requireHittable: true); choice.tap()
        XCTAssertTrue(app.navigationBars["Add relationship"].waitForExistence(timeout: 5))
    }
    @MainActor private func backToRelationshipOptions(_ app: XCUIApplication,title: String) {
        let chooser = app.navigationBars["Choose a person"]
        XCTAssertTrue(chooser.waitForExistence(timeout: 5))
        let back = chooser.buttons[title].exists ? chooser.buttons[title] : chooser.buttons["Back"]
        back.tap()
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
    }
    @MainActor private func chooseAge(_ app: XCUIApplication,value: Int,contact: Bool = false) {
        let button = app.buttons[(contact ? "contact-" : "") + "choose-estimated-age"]
        reveal(button,in: app); button.tap()
        XCTAssertTrue(app.pickerWheels.firstMatch.waitForExistence(timeout: 5))
        app.pickerWheels.firstMatch.adjust(toPickerWheelValue: String(value))
        capture(app,"Native age wheel selecting " + String(value))
        app.navigationBars["Age in years"].buttons["Done"].tap()
    }
    @MainActor private func verifyContactActionGeometry(_ app: XCUIApplication, largest: Bool) {
        let cancel = app.buttons["contact-cancel"], confirm = app.buttons["contact-import"]
        XCTAssertTrue(cancel.isHittable && confirm.isHittable)
        for button in [cancel,confirm] {
            XCTAssertGreaterThanOrEqual(button.frame.height,44)
            XCTAssertGreaterThanOrEqual(button.frame.width,44)
            XCTAssertGreaterThanOrEqual(button.frame.minX,app.frame.minX)
            XCTAssertLessThanOrEqual(button.frame.maxX,app.frame.maxX)
            XCTAssertLessThanOrEqual(button.frame.maxY,app.frame.maxY)
            XCTAssertTrue(["Cancel","Import and Save"].contains(button.label), "Full action label remains accessible; SwiftUI exposes it on the Button itself")
        }
        XCTAssertFalse(cancel.frame.intersects(confirm.frame))
        let bar = app.navigationBars["Contact birth information"]
        XCTAssertGreaterThanOrEqual(cancel.frame.minY,bar.frame.maxY)
        if largest {
            XCTAssertLessThanOrEqual(cancel.frame.maxY,confirm.frame.minY)
            XCTAssertGreaterThanOrEqual(confirm.frame.width,app.frame.width - 34)
            XCTAssertEqual(cancel.frame.width,confirm.frame.width,accuracy: 1)
        } else {
            XCTAssertLessThanOrEqual(cancel.frame.maxX,confirm.frame.minX)
            XCTAssertGreaterThanOrEqual(confirm.frame.width,140)
        }
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = largest ? "Responsive Contacts actions largest - synthetic" : "Responsive Contacts actions standard - synthetic"
        image.lifetime = .keepAlways; add(image)
    }
    @MainActor private func verifyContactLowerRowsReachable(_ app: XCUIApplication, largest: Bool) {
        let selected = app.descendants(matching: .any).matching(identifier: "contact-selected-contact").firstMatch
        let date = app.descendants(matching: .any).matching(identifier: "contact-exact-birthday").firstMatch
        let rows = [(selected,false), (app.buttons["contact-birth-information"],true), (date,true), (app.buttons["Import and Save without photo"],true)]
        let top = max(CGFloat(145),app.navigationBars["Contact birth information"].frame.maxY + 4)
        for (index,pair) in rows.enumerated() {
            let element = pair.0
            var revealed = false
            for _ in 0..<40 {
                let bottom = app.buttons["contact-cancel"].frame.minY - 20
                let span = bottom - top
                XCTAssertGreaterThan(span,80)
                var up = index != 0, distance = span * 0.8
                if element.exists {
                    let frame = element.frame
                    if frame.minY >= top && frame.maxY <= bottom {
                        XCTAssertLessThanOrEqual(frame.height,span)
                        if pair.1 { XCTAssertTrue(element.isHittable) }
                        revealed = true; break
                    }
                    up = frame.maxY > bottom
                    // A very short drag can be swallowed by the native Form's pan threshold.
                    distance = min(span * 0.8,max(44,up ? frame.maxY - bottom + 8 : top - frame.minY + 8))
                }
                // Keep the gesture entirely in the scrollable form, never on its fixed actions.
                let mid = (top + bottom) / 2
                let startY = mid + (up ? distance / 2 : -distance / 2)
                let endY = mid + (up ? -distance / 2 : distance / 2)
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5,dy: startY / app.frame.height))
                    .press(forDuration: 0.05,thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5,dy: endY / app.frame.height)),withVelocity: .slow,thenHoldForDuration: 0.15)
            }
            if !revealed {
                let diagnostic = XCTAttachment(string: "row=\(index) frame=\(element.frame) top=\(top) footer=\(app.buttons["contact-cancel"].frame)\n" + app.debugDescription)
                diagnostic.name = "Synthetic lower-row reachability failure"; diagnostic.lifetime = .keepAlways; add(diagnostic)
                let image = XCTAttachment(screenshot: app.screenshot())
                image.name = "Synthetic lower-row failure"; image.lifetime = .keepAlways; add(image)
            }
            XCTAssertTrue(revealed,"Every lower review row must scroll fully clear of the fixed footer")
        }
        XCTAssertTrue(app.buttons["contact-cancel"].isHittable && app.buttons["contact-import"].isHittable)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = largest ? "Lowest review row clear of footer largest - synthetic" : "Lowest review row clear of footer standard - synthetic"
        image.lifetime = .keepAlways; add(image)
    }
    @MainActor private func formContentBottom(_ app: XCUIApplication) -> CGFloat {
        let cancel = app.buttons["contact-cancel"]
        return cancel.exists ? min(cancel.frame.minY - 12,app.frame.maxY - 100) : app.frame.maxY - 100
    }
    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication, requireHittable: Bool = false) {
        for _ in 0..<12 {
            if element.exists {
                let frame = element.frame
                if frame.minY >= 145 && frame.maxY <= formContentBottom(app)
                    && (!requireHittable || element.isHittable) { return }
                if frame.height > 0 && frame.minY < 145 { app.swipeDown(); continue }
            }
            app.swipeUp()
        }
    }
    @MainActor private func revealPrecisely(_ element: XCUIElement, in app: XCUIApplication) {
        for step in 0..<20 {
            guard element.exists else {
                if step < 10 { app.swipeDown() } else { app.swipeUp() }
                continue
            }
            let frame = element.frame
            if frame.minY >= 145 && frame.maxY <= formContentBottom(app) { return }
            let movingUp = frame.maxY > formContentBottom(app)
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5,dy: movingUp ? 0.72 : 0.38))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5,dy: movingUp ? 0.52 : 0.58))
            start.press(forDuration: 0.05,thenDragTo: end)
        }
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        // Layout assertions provide review evidence without retaining screenshots.
        XCTAssertTrue(app.exists, name)
    }
    @MainActor private func openAllPeople(_ app: XCUIApplication) {
        app.buttons["people-menu"].tap(); app.buttons["All people"].tap()
    }
    @MainActor private func addPerson(_ app: XCUIApplication, name: String) {
        let add = app.buttons.matching(identifier: "Add person")
        guard requireTestState(app, "Add person action ready", {
            add.count == 1 && add.element.isHittable
        }) else { return }
        add.element.tap()
        let editor = app.navigationBars["Add person"]
        let firstName = app.textFields["First name (optional)"]
        guard requireTestState(app, "New person editor ready", {
            editor.exists && editor.isHittable && firstName.isHittable
        }) else { return }
        firstName.tap(); firstName.typeText(name)
        guard requireTestState(app, "New person name entered", {
            firstName.value as? String == name
        }) else { return }
        _ = editorToggle("Friend", in: app)
        let friends = app.switches.matching(identifier: "Friend")
        guard requireTestState(app, "Single named Friend control available", {
            friends.count == 1
        }) else { return }
        let controls = friends.element.switches
        guard requireTestState(app, "Friend control unique and initially off", {
            friends.count == 1 && controls.count == 1
                && friends.element.value as? String == "0"
                && controls.element.value as? String == "0"
        }) else { return }
        // The labeled accessibility wrapper spans the row; its nested switch
        // is the demonstrated action target. Let XCTest scroll it into view.
        func recordFriendStage(_ stage: String) {
            func state(_ value: String?) -> String { value == "0" ? "off" : value == "1" ? "on" : "unknown" }
            print("KIN_CI_FRIEND \(stage) keyboard=\(app.keyboards.firstMatch.exists) wrapper=\(state(friends.element.value as? String)) control=\(state(controls.element.value as? String)) hittable=\(controls.element.isHittable)")
        }
        // Finish editing before interacting with the switch so the form has a
        // settled layout; continue to verify the switch and saved profile below.
        let keyboard = app.keyboards.firstMatch
        if keyboard.exists {
            let returnKey = keyboard.buttons["Return"]
            guard requireTestState(app, "Name keyboard Return ready", {
                returnKey.exists && returnKey.isHittable
            }) else { return }
            returnKey.tap()
            guard requireTestState(app, "Name keyboard dismissed", {
                !keyboard.exists
            }) else { return }
        }
        recordFriendStage("before")
        controls.element.tap()
        recordFriendStage("after")
        let save = editor.buttons.matching(identifier: "Save")
        guard requireTestState(app, "Friend on and Save enabled", {
            friends.count == 1 && controls.count == 1
                && friends.element.value as? String == "1" && controls.element.value as? String == "1"
                && friends.element.isHittable && controls.element.isHittable && save.count == 1
                && save.element.isEnabled && save.element.isHittable
        }) else { return }
        save.element.tap()
        guard requireTestState(app, "Direct save opens saved profile", {
            app.navigationBars[name].exists && !editor.exists
        }) else { return }
        app.navigationBars.buttons["People"].tap()
        // Use the original five-second outcome bound for both dismissal and row.
        guard requireTestState(app, "Saved person returned to exact index row", {
            !editor.exists && app.staticTexts[name].exists
                && app.cells.containing(.staticText, identifier: name).count == 1
        }) else { return }
        XCTAssertTrue(app.staticTexts[name].exists)
    }
    @MainActor private func requireTestState(_ app: XCUIApplication, _ stage: String,
                                             _ condition: @escaping () -> Bool,
                                             file: StaticString = #filePath, line: UInt = #line) -> Bool {
        if condition() { return true }
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        let ready = XCTWaiter.wait(for: [expected], timeout: 5) == .completed
        if !ready {
            recordTestState(app, stage: stage)
            XCTFail("UI precondition failed: " + stage, file: file, line: line)
        }
        return ready
    }
    @MainActor private func recordTestState(_ app: XCUIApplication, stage: String) {
        // Fixed control-state flags only: no names, field contents, contact data,
        // screenshots, store paths, or full accessibility hierarchy.
        let saves = app.buttons.matching(identifier: "Save")
        _ = editorToggle("Friend", in: app)
        let friends = app.switches.matching(identifier: "Friend")
        let value = friends.count == 1 ? friends.element.value as? String : nil
        let friendState = value == "0" ? "off" : value == "1" ? "on" : "unavailable"
        let flags = "stage=\(stage); addEditor=\(app.navigationBars["Add person"].exists); "
            + "editEditor=\(app.navigationBars["Edit person"].exists); "
            + "photos=\(app.navigationBars["Photos"].exists); contacts=\(app.navigationBars["Contacts"].exists); "
            + "birthReview=\(app.navigationBars["Contact birth information"].exists); "
            + "friendUnique=\(friends.count == 1); friend=\(friendState); "
            + "friendHittable=\(friends.count == 1 && friends.element.isHittable); saveUnique=\(saves.count == 1); "
            + "saveEnabled=\(saves.count == 1 && saves.element.isEnabled); alert=\(app.alerts.count > 0)"
        let state = XCTAttachment(string: flags)
        state.name = "Bounded UI control state"; state.lifetime = .keepAlways; add(state)
        print("Kin UI state: " + flags)
    }

}
