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
            if isAdult {
                let first = app.textFields["Imported first name (optional)"]
                first.tap(); first.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue,count: name.count) + "Michael")
                let gender = app.buttons["contact-gender-choice"]
                XCTAssertEqual(gender.value as? String,"Male")
                gender.tap(); app.buttons["Female"].tap()
                first.tap(); first.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue,count: 7) + name)
                XCTAssertEqual(gender.value as? String,"Female")
            }
            if app.keyboards.firstMatch.exists {
                let finishEntry = app.keyboards.firstMatch.buttons["Return"]
                XCTAssertTrue(finishEntry.exists && finishEntry.isHittable)
                finishEntry.tap()
                XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
            }
            // Full-screen swipes overshot this review row in both directions:
            // below the fixed import toolbar, then beneath the navigation bar.
            // Keep the same reveal bound and usable-frame check with shorter drags.
            let friend = editorToggle("contact-connection-friend", in: app, scrollStep: 120)
            XCTAssertTrue(friend.exists && friend.isHittable)
            friend.tap()
            XCTAssertEqual(editorSwitchWrapper("contact-connection-friend", in: app, scrollStep: 120).value as? String,"1")
            let preview = app.images["contact-photo-preview"]
            let emptyPreview = app.staticTexts["contact-photo-preview-empty"]
            let target = isAdult ? preview : emptyPreview
            for _ in 0..<8 { if target.isHittable { break }; app.swipeUp() }
            XCTAssertTrue(target.isHittable)
            XCTAssertEqual(preview.exists,isAdult)
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = isAdult ? "Eligible Contacts preview - synthetic" : "Ineligible Contacts preview - synthetic"
            attachment.lifetime = .keepAlways; add(attachment)
            let exactBirthday = app.buttons["Birth information, Exact birthday"]
            for _ in 0..<8 { if exactBirthday.exists { break }; app.swipeUp() }
            XCTAssertTrue(exactBirthday.exists)
            app.buttons["contact-import"].tap()
            XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 5))
            if isAdult { XCTAssertTrue(app.staticTexts["Gender: Female"].exists) }
            let birthday = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@",String(birthYear))).firstMatch
            XCTAssertTrue(birthday.waitForExistence(timeout: 5))
            app.terminate(); app.launch(); app.staticTexts[name].tap()
            XCTAssertTrue(birthday.waitForExistence(timeout: 5))
            app.navigationBars.buttons["Edit"].tap(); app.swipeUp()
            XCTAssertEqual(app.buttons["Change photo"].exists,isAdult)
            if !isAdult { XCTAssertFalse(app.buttons["Add photo"].exists) }
            app.navigationBars["Edit person"].buttons["Cancel"].tap(); app.navigationBars.buttons["People"].tap()
        }
        #else
        throw XCTSkip("Synthetic Contacts fixture creation is restricted to isolated simulators.")
        #endif
    }
}
