import XCTest
import Contacts
import UIKit

/// Fixtures are created by the test runner only. Kin still uses the selection-only
/// system picker and never requests address-book access itself.
final class NativeContactsTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor func testNativeFullBirthdayAndPhotoImportForAdultAndMinor() throws {
        #if targetEnvironment(simulator)
        let contacts = CNContactStore()
        try XCTUnwrap(CNContactStore.authorizationStatus(for: .contacts) == .authorized ? true : nil,
                      "Grant Contacts access only to the isolated simulator UI test runner before running this native fixture test.")
        let image = UIGraphicsImageRenderer(size: CGSize(width: 64,height: 64)).image { context in
            UIColor.systemTeal.setFill(); context.fill(CGRect(x: 0,y: 0,width: 64,height: 64))
        }.pngData()!
        let year = Calendar(identifier: .gregorian).component(.year, from: Date())
        let suffix = String(UUID().uuidString.prefix(8))
        let fixtures = [("Kin Synthetic Adult " + suffix,year - 30,true),
                        ("Kin Synthetic Minor " + suffix,year - 8,false)]
        var created: [CNMutableContact] = []
        defer {
            let request = CNSaveRequest()
            for contact in created { request.delete(contact) }
            try? contacts.execute(request)
        }
        for (name,birthYear,_) in fixtures {
            let contact = CNMutableContact(); contact.givenName = name
            contact.birthday = DateComponents(year: birthYear,month: 1,day: 2)
            contact.imageData = image
            let request = CNSaveRequest(); request.add(contact,toContainerWithIdentifier: nil)
            try contacts.execute(request); created.append(contact)
        }
        let app = XCUIApplication(); app.launchArguments = ["--kin-test-notebook",UUID().uuidString]
        app.launch(); defer { app.terminate() }
        for (name,birthYear,isAdult) in fixtures {
            app.buttons["Add person"].tap(); app.buttons["Import from Contacts"].tap()
            XCTAssertTrue(app.navigationBars["Contacts"].waitForExistence(timeout: 10))
            let search = app.searchFields.firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText(name)
            let card = app.collectionViews["Search results"].cells[name].firstMatch
            XCTAssertTrue(card.waitForExistence(timeout: 10)); card.tap()
            XCTAssertTrue(app.navigationBars["Contact birth information"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["This contact has a birthday with a year."].exists)
            XCTAssertTrue(app.buttons["Birth information, Exact birthday"].exists)
            app.navigationBars["Contact birth information"].buttons["Import"].tap()
            XCTAssertEqual(app.textFields["First name (optional)"].value as? String,name)
            app.switches["Friend"].switches.firstMatch.tap()
            app.swipeUp()
            let expectedPhoto = app.buttons[isAdult ? "Change photo" : "Add photo"]
            if isAdult { XCTAssertTrue(expectedPhoto.waitForExistence(timeout: 5)) }
            else {
                XCTAssertFalse(app.buttons["Change photo"].exists)
                XCTAssertFalse(app.buttons["Add photo"].exists)
            }
            let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Native selected Contact birthday and age-gated photo"; shot.lifetime = .keepAlways; add(shot)
            app.navigationBars["Add person"].buttons["Save"].tap()
            XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 5)); app.staticTexts[name].tap()
            let birthday = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@",String(birthYear))).firstMatch
            XCTAssertTrue(birthday.waitForExistence(timeout: 5))
            app.terminate(); app.launch(); app.staticTexts[name].tap()
            XCTAssertTrue(birthday.waitForExistence(timeout: 5))
            app.navigationBars.buttons["Edit"].tap(); app.swipeUp()
            XCTAssertEqual(app.buttons["Change photo"].exists,isAdult)
            app.navigationBars["Edit person"].buttons["Cancel"].tap(); app.navigationBars.buttons["Kin"].tap()
        }
        #else
        throw XCTSkip("Synthetic Contacts fixture creation is restricted to isolated simulators.")
        #endif
    }
}
