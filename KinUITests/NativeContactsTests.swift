import XCTest
import Contacts
import UIKit

/// Fixtures are created by the test runner only. Kin still uses the selection-only
/// system picker and never requests address-book access itself.
final class NativeContactsTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testSyntheticCardResolutionFailsClosedForMissingAndAmbiguousMatches() {
        XCTAssertEqual(syntheticCardResolution(0), .absent)
        XCTAssertEqual(syntheticCardResolution(1), .unique)
        XCTAssertEqual(syntheticCardResolution(2), .ambiguous)
        XCTAssertEqual(syntheticCardResolution(20), .ambiguous)
    }

    func testNativeContactRevealRequiresUniqueMovementAndStableVisibleTarget() {
        let deadline = NativeContactRevealDeadline(start: 100, timeout: 10)
        XCTAssertEqual(deadline.remaining(now: 103), 7)
        XCTAssertEqual(deadline.remaining(now: 110), 0)
        XCTAssertEqual(deadline.remaining(now: 111), 0)
        var policy = NativeContactRevealPolicy()
        let offscreen = CGRect(x: 20, y: 900, width: 200, height: 50)
        let moved = CGRect(x: 20, y: 800, width: 200, height: 50)
        let visible = CGRect(x: 20, y: 300, width: 200, height: 50)
        func observe(_ count: Int, _ visibleCount: Int, _ frame: CGRect?, _ sole: CGRect?, _ now: TimeInterval) -> NativeContactRevealDecision {
            policy.observe(candidateCount: count, visibleCount: visibleCount, visibleFrame: frame,
                           soleFrame: sole, lowerBound: 700, now: now)
        }
        XCTAssertEqual(observe(0, 0, nil, nil, 0), .wait)
        XCTAssertEqual(observe(2, 0, nil, nil, 0), .wait)
        XCTAssertEqual(observe(1, 0, nil, offscreen, 0), .scrollUp)
        policy.didScroll(from: offscreen)
        XCTAssertEqual(observe(1, 0, nil, offscreen, 0.1), .wait, "Do not repeat a drag without observed movement")
        XCTAssertEqual(observe(1, 0, nil, moved, 0.2), .scrollUp)
        XCTAssertEqual(observe(1, 1, visible, visible, 0.3), .wait)
        XCTAssertEqual(observe(1, 1, visible, visible, 1.2), .wait)
        XCTAssertEqual(observe(1, 1, visible, visible, 1.4), .select)
        XCTAssertEqual(observe(2, 2, nil, nil, 1.5), .wait)
        for _ in 1..<16 { policy.didScroll(from: offscreen) }
        XCTAssertEqual(policy.scrolls, 16)
        XCTAssertEqual(observe(1, 0, nil, moved, 2), .wait, "Keep the existing reveal limit")
    }

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
        var creationUncertain = false
        // XCTest runs teardown even when the test records an earlier failure;
        // a cleanup error is reported separately instead of being discarded.
        addTeardownBlock { try cleanupOwnedSyntheticContacts(created, store: contacts, scope: .nativeFull, creationUncertain: creationUncertain) }
        for (name,birthYear,_) in fixtures {
            let contact = CNMutableContact(); contact.givenName = name
            contact.birthday = DateComponents(year: birthYear,month: 1,day: 2)
            contact.imageData = image
            let request = CNSaveRequest(); request.add(contact,toContainerWithIdentifier: nil)
            creationUncertain = true
            try contacts.execute(request); created.append(contact)
            creationUncertain = false
        }
        let app = XCUIApplication(); app.launchArguments = ["--kin-test-notebook",UUID().uuidString]
        app.launch(); defer { app.terminate() }
        for (name,birthYear,isAdult) in fixtures {
            app.buttons["Add person"].tap(); app.buttons["Import from Contacts"].tap()
            XCTAssertTrue(waitForNativeContactsPicker(app))
            let search = try requireNativeContactsSearch(app)
            search.tap()
            // The out-of-process picker may own the keyboard outside app.keyboards.
            // Its exact search result remains mandatory after typing.
            try requireNativeContactsSearch(app).typeText(name)
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
