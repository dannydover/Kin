import XCTest

final class PickerUITests: XCTestCase {
    @MainActor func testNativePickerShowsSyntheticContact() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["standalone-picker-open"].waitForExistence(timeout: 10))
        app.buttons["standalone-picker-open"].tap()
        XCTAssertTrue(app.navigationBars["Contacts"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.cells["John Appleseed"].waitForExistence(timeout: 10))
    }
}
