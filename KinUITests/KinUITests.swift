import XCTest
import Contacts
import UIKit

final class KinUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
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
            XCTAssertTrue(app.navigationBars["Contacts"].waitForExistence(timeout: 10))
            guard app.cells["John Appleseed"].waitForExistence(timeout: 5) else {
                app.navigationBars["Contacts"].buttons["Cancel"].tap()
                throw XCTSkip("Use an isolated simulator with the standard synthetic Contacts sample card.")
            }
            app.cells["John Appleseed"].tap()
            XCTAssertTrue(app.navigationBars["Contact birth information"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "contact-current-draft").firstMatch.exists)
            for role in ["Person","Parent","Child","Partner"] { XCTAssertFalse(app.staticTexts[role + " 0"].exists) }
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "contact-selected-contact").firstMatch.label.contains("John Appleseed"))
            if route == "Add parent" { capture(app,"New unnamed parent import review has no temporary identity") }
            app.navigationBars["Contact birth information"].buttons["Cancel"].tap()
            XCTAssertEqual(app.textFields["First name (optional)"].value as? String,"First name (optional)")
            app.navigationBars["Add person"].buttons["Cancel"].tap()
            if route != "Add person" {
                app.navigationBars[route].buttons["Cancel"].tap(); app.navigationBars.buttons["Kin"].tap()
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
        app.staticTexts["Synthetic Parent"].tap(); app.buttons["Add child"].tap(); app.buttons["Synthetic Child"].tap()
        assertParentRoles(app,parent: "Synthetic Parent",child: "Synthetic Child")
        capture(app,"Add child clearly labels parent and child")
        app.buttons["Save"].tap(); app.buttons["Edit relationship with Synthetic Child"].tap()
        assertParentRoles(app,parent: "Synthetic Parent",child: "Synthetic Child")
        app.navigationBars["Edit relationship"].buttons["Cancel"].tap()
        app.staticTexts["Synthetic Child"].tap()
        app.buttons["Edit relationship with Synthetic Parent"].tap()
        assertParentRoles(app,parent: "Synthetic Parent",child: "Synthetic Child")
        app.navigationBars["Edit relationship"].buttons["Cancel"].tap()
        reveal(app.buttons["Add parent"],in: app); app.buttons["Add parent"].tap(); app.buttons["Synthetic Partner"].tap()
        assertParentRoles(app,parent: "Synthetic Partner",child: "Synthetic Child")
        capture(app,"Add parent clearly labels selected parent and current child")
        app.navigationBars["Add relationship"].buttons["Cancel"].tap(); app.navigationBars["Add parent"].buttons["Cancel"].tap()
        app.navigationBars.buttons["Synthetic Parent"].tap()
        app.buttons["Add partner"].tap(); app.buttons["Synthetic Partner"].tap()
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
        let choice = app.buttons[child]; reveal(choice,in: app); choice.tap()
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
    @MainActor func testAddParentsForYoungPersonReuseCreateNavigateAndUnlink() throws {
        let app = XCUIApplication(); app.launchArguments = ["--kin-test-notebook", UUID().uuidString]
        app.launch(); addPerson(app,name: "Synthetic Young"); addPerson(app,name: "Synthetic Existing Parent")
        app.staticTexts["Synthetic Young"].tap(); app.navigationBars.buttons["Edit"].tap()
        let birth = app.buttons["Birth information, Unknown"]
        reveal(birth,in: app); birth.tap(); app.buttons["Estimated age"].tap()
        chooseAge(app,value: 3); app.buttons["Save"].tap()
        XCTAssertFalse(app.buttons["Add child"].exists); XCTAssertFalse(app.buttons["Add partner"].exists)
        app.buttons["Add parent"].tap()
        XCTAssertTrue(app.buttons["Parent relationship, Unspecified"].exists)
        XCTAssertFalse(app.buttons["Synthetic Young"].exists)
        app.buttons["Synthetic Existing Parent"].tap()
        try cancelRelationshipDraft(app, parent: "Synthetic Existing Parent", child: "Synthetic Young")
        app.navigationBars["Add parent"].buttons["Cancel"].tap()
        XCTAssertFalse(app.buttons["Edit relationship with Synthetic Existing Parent"].exists)
        app.buttons["Add parent"].tap(); app.buttons["Parent relationship, Unspecified"].tap(); app.buttons["Biological"].tap()
        app.buttons["Synthetic Existing Parent"].tap(); app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Biological parent"].waitForExistence(timeout: 5))
        // Re-selecting a linked person must reject the duplicate without changing either person.
        app.buttons["Add parent"].tap(); app.buttons["Synthetic Existing Parent"].tap(); app.buttons["Save"].tap()
        XCTAssertTrue(app.alerts["Couldn’t finish"].waitForExistence(timeout: 5)); app.alerts.buttons["OK"].tap()
        try cancelRelationshipDraft(app, parent: "Synthetic Existing Parent", child: "Synthetic Young"); app.navigationBars["Add parent"].buttons["Cancel"].tap()
        app.staticTexts["Synthetic Existing Parent"].tap()
        XCTAssertTrue(app.navigationBars["Synthetic Existing Parent"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Synthetic Young"].exists)
        // The reverse link would create a cycle and must also fail visibly.
        reveal(app.buttons["Add parent"],in: app); app.buttons["Add parent"].tap()
        app.cells.buttons["Synthetic Young"].tap(); app.buttons["Save"].tap()
        XCTAssertTrue(app.alerts["Couldn’t finish"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts.staticTexts["This would make someone their own ancestor. Check the parent and child you selected."].exists)
        app.alerts.buttons["OK"].tap(); try cancelRelationshipDraft(app, parent: "Synthetic Young", child: "Synthetic Existing Parent"); app.navigationBars["Add parent"].buttons["Cancel"].tap()
        app.navigationBars.buttons["Synthetic Young"].tap()
        app.buttons["Add parent"].tap(); app.buttons["Parent relationship, Unspecified"].tap(); app.buttons["Step"].tap()
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
        app.navigationBars.buttons["Kin"].tap(); openAllPeople(app)
        XCTAssertTrue(app.staticTexts["Synthetic Existing Parent"].exists); XCTAssertTrue(app.staticTexts["Parent 3"].exists)
    }
    @MainActor func testAddParentUsesSharedContactsReviewAndKeepsNewParentUnlisted() throws {
        let app = XCUIApplication(); app.launchArguments = ["--kin-test-notebook", UUID().uuidString]
        app.launch(); addPerson(app,name: "Synthetic Child")
        app.staticTexts["Synthetic Child"].tap(); reveal(app.buttons["Add parent"],in: app); app.buttons["Add parent"].tap()
        app.buttons["Create new person"].tap()
        XCTAssertTrue(app.buttons["Save"].isEnabled)
        func selectSample() throws {
            app.buttons["Import from Contacts"].tap()
            XCTAssertTrue(app.navigationBars["Contacts"].waitForExistence(timeout: 10))
            guard app.cells["John Appleseed"].waitForExistence(timeout: 5) else {
                app.navigationBars["Contacts"].buttons["Cancel"].tap()
                throw XCTSkip("Use an isolated simulator with the standard synthetic Contacts sample card.")
            }
            app.cells["John Appleseed"].tap()
            XCTAssertTrue(app.navigationBars["Contact birth information"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "contact-current-draft").firstMatch.exists)
            XCTAssertFalse(app.staticTexts["Person 0"].exists)
        }
        try selectSample(); app.navigationBars["Contact birth information"].buttons["Cancel"].tap()
        XCTAssertEqual(app.textFields["First name (optional)"].value as? String,"First name (optional)")
        try selectSample(); reveal(app.buttons["Continue without importing photo"],in: app)
        app.buttons["Continue without importing photo"].tap(); app.navigationBars["Add person"].buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["John Appleseed"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Unspecified parent"].exists)
        app.staticTexts["John Appleseed"].tap()
        XCTAssertTrue(app.navigationBars["John Appleseed"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Synthetic Child"].exists)
        capture(app,"Imported parent links back to the original child")
        app.terminate(); app.launch()
        XCTAssertFalse(app.staticTexts["John Appleseed"].exists)
        app.staticTexts["Synthetic Child"].tap(); reveal(app.staticTexts["John Appleseed"],in: app)
        XCTAssertTrue(app.staticTexts["John Appleseed"].exists)
        app.navigationBars.buttons["Kin"].tap(); openAllPeople(app)
        XCTAssertEqual(app.staticTexts.matching(identifier: "John Appleseed").count,1)
    }
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
    @MainActor func testPrivacyPolicyIsFinalAboutSectionAtNormalAndLargestText() {
        let app = XCUIApplication()
        let token = UUID().uuidString
        for largest in [false,true] {
            app.launchArguments = ["--kin-test-notebook",token]
            if largest { app.launchArguments += ["-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"] }
            app.launch(); app.buttons["people-menu"].tap(); app.buttons["About"].tap()
            XCTAssertTrue(app.navigationBars["About Kin"].waitForExistence(timeout: 5))
            let policy = app.descendants(matching: .any).matching(identifier: "about-privacy-policy").firstMatch
            let developer = app.staticTexts["Made by an indie developer"]
            for _ in 0..<8 {
                if policy.isHittable { break }
                app.swipeUp()
            }
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
        reveal(age,in: app); age.tap()
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
            reveal(app.buttons["Import from Contacts"],in: app)
            app.buttons["Import from Contacts"].tap()
            XCTAssertTrue(app.navigationBars["Contacts"].waitForExistence(timeout: 10))
            let search = app.searchFields.firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText(contactName)
            let card = app.collectionViews["Search results"].cells[contactName].firstMatch
            XCTAssertTrue(card.waitForExistence(timeout: 5)); card.tap()
            XCTAssertTrue(app.navigationBars["Contact birth information"].waitForExistence(timeout: 10))
        }
        try selectSample()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "contact-current-draft").firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Synthetic Existing Draft"].exists)
        capture(app, "Contact missing birthday asks for birth information")
        let birthPicker = app.buttons["Birth information, Unknown"]
        reveal(birthPicker,in: app); birthPicker.tap()
        XCTAssertTrue(app.buttons["Exact birthday"].exists)
        XCTAssertTrue(app.buttons["Unknown"].exists); app.buttons["Unknown"].tap()
        app.navigationBars["Contact birth information"].buttons["Cancel"].tap()
        XCTAssertEqual(app.textFields["First name (optional)"].value as? String,"Synthetic Existing Draft")
        try selectSample()
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
        let picker = app.buttons["Birth information, Unknown"]
        reveal(picker,in: app); picker.tap(); app.buttons["Estimated age"].tap()
        chooseAge(app,value: 19,contact: true)
        capture(app, "Contact import accepts a confirmed estimated age")
        app.navigationBars["Contact birth information"].buttons["Import"].tap()
        app.navigationBars["Edit person"].buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars[contactName].waitForExistence(timeout: 5))
        app.terminate(); app.launch(); app.staticTexts[contactName].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@","Estimated 19 as of")).firstMatch.exists)
        #else
        throw XCTSkip("Synthetic Contacts fixture creation is restricted to isolated simulators.")
        #endif
    }
    @MainActor private func addEstimatedAdult(_ app: XCUIApplication, name: String) {
        addPerson(app, name: name); app.staticTexts[name].tap(); app.navigationBars.buttons["Edit"].tap(); app.swipeUp()
        app.buttons["Birth information, Unknown"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap(); app.buttons["Estimated age"].tap()
        XCTAssertFalse(app.buttons["Save"].isEnabled)
        chooseAge(app,value: 80); app.buttons["Save"].tap()
    }
    @MainActor private func chooseAge(_ app: XCUIApplication,value: Int,contact: Bool = false) {
        let button = app.buttons[(contact ? "contact-" : "") + "choose-estimated-age"]
        reveal(button,in: app); button.tap()
        XCTAssertTrue(app.pickerWheels.firstMatch.waitForExistence(timeout: 5))
        app.pickerWheels.firstMatch.adjust(toPickerWheelValue: String(value))
        capture(app,"Native age wheel selecting " + String(value))
        app.navigationBars["Age in years"].buttons["Done"].tap()
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
    @MainActor private func revealPrecisely(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<20 {
            let frame = element.frame
            if frame.minY >= 145 && frame.maxY <= app.frame.maxY - 100 { return }
            let movingUp = frame.maxY > app.frame.maxY - 100
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5,dy: movingUp ? 0.72 : 0.38))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5,dy: movingUp ? 0.52 : 0.58))
            start.press(forDuration: 0.05,thenDragTo: end)
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
