import XCTest

final class PickerUITests: XCTestCase {
    @MainActor func testRepeatedNativeSelectionReturnsToPresenter() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        for _ in 0..<3 {
            let open = app.buttons["standalone-picker-open"]
            XCTAssertTrue(open.waitForExistence(timeout: 10))
            open.tap()
            XCTAssertTrue(app.navigationBars["Contacts"].waitForExistence(timeout: 30))
            let contact = app.cells["John Appleseed"]
            XCTAssertTrue(contact.waitForExistence(timeout: 10))
            contact.tap()
            XCTAssertTrue(app.navigationBars["Contacts"].waitForNonExistence(timeout: 10))
            XCTAssertTrue(open.isHittable)
        }
    }
}
