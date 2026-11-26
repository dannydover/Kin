import Contacts
import XCTest

final class ContactExportUITests: XCTestCase {
    @MainActor func testCreateOnceAndReviewTheSameContactOnRelaunch() throws {
        #if targetEnvironment(simulator)
        let contacts = CNContactStore()
        try XCTSkipUnless(CNContactStore.authorizationStatus(for: .contacts) == .authorized,
                          "Use an isolated synthetic-only simulator with Contacts access granted to the test runner and Kin.")
        let name = "Synthetic Kin Export " + UUID().uuidString
        func matching() throws -> [CNContact] {
            try contacts.unifiedContacts(matching: CNContact.predicateForContacts(matchingName: name),
                                         keysToFetch: [CNContactGivenNameKey as CNKeyDescriptor])
                .filter { $0.givenName == name }
        }
        XCTAssertTrue(try matching().isEmpty)
        addTeardownBlock {
            let request = CNSaveRequest()
            for contact in try matching() {
                if let mutable = contact.mutableCopy() as? CNMutableContact { request.delete(mutable) }
            }
            try contacts.execute(request)
            XCTAssertTrue(try matching().isEmpty)
        }
        let app = XCUIApplication()
        app.launchArguments = ["--kin-test-notebook", UUID().uuidString]
        app.launch()
        try tap(app.buttons["Add person"], in: app)
        let field = app.textFields["First name (optional)"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText(name)
        try tap(app.buttons["Save"], in: app)
        XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 10))
        try tap(app.navigationBars.buttons["People"], in: app)

        func selectPerson() throws {
            try tap(app.buttons["people-menu"], in: app)
            try tap(app.buttons["Export to Contacts"], in: app)
            try tap(app.switches[name], in: app)
            try tap(app.buttons["Review selected people"], in: app)
        }

        try selectPerson()
        try tap(app.buttons["Review a new contact"], in: app)
        XCTAssertTrue(try matching().isEmpty, "Preview must not create a contact")
        try tap(app.buttons["Back to fields"], in: app)
        XCTAssertTrue(try matching().isEmpty, "Backing out must not create a contact")
        try tap(app.buttons["Review a new contact"], in: app)
        try tap(app.buttons["Confirm and create contact"], in: app)
        XCTAssertTrue(app.staticTexts["Created in Contacts"].waitForExistence(timeout: 10))
        let created = try XCTUnwrap(matching().only)
        app.terminate()
        app.launch()
        try selectPerson()
        XCTAssertFalse(app.buttons["Review a new contact"].exists)
        try tap(app.buttons["Review the linked contact"], in: app)
        try tap(app.buttons["Confirm and update contact"], in: app)
        XCTAssertTrue(app.staticTexts["Updated in Contacts"].waitForExistence(timeout: 10))
        XCTAssertEqual(try matching().map(\.identifier), [created.identifier])
        #else
        throw XCTSkip("Native Contacts writes require an isolated synthetic-only simulator.")
        #endif
    }

    @MainActor private func tap(_ element: XCUIElement, in app: XCUIApplication,
                                file: StaticString = #filePath, line: UInt = #line) throws {
        for _ in 0..<5 where !element.isHittable { app.swipeUp() }
        guard element.waitForExistence(timeout: 5), element.isHittable else {
            XCTFail("Could not reach expected control: \(element)", file: file, line: line)
            throw CocoaError(.featureUnsupported)
        }
        element.tap()
    }
}

private extension Array {
    var only: Element? { count == 1 ? first : nil }
}
