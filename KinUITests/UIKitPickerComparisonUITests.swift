import XCTest

final class UIKitPickerComparisonUITests: XCTestCase {
    @MainActor func testDirectUIKitPickerShowsSyntheticContact() {
        let app = XCUIApplication()
        app.launchArguments = ["--kin-uikit-control"]
        app.launch()
        XCTAssertTrue(app.buttons["uikit-control-import"].waitForExistence(timeout: 10))
        app.buttons["uikit-control-import"].tap()
        XCTAssertTrue(app.navigationBars["Contacts"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.cells["John Appleseed"].waitForExistence(timeout: 10))
    }
}
