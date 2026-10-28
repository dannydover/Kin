import XCTest
import UIKit
import Vision

final class NextVersionUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor private func replace(_ field: XCUIElement, with text: String) {
        let prior = field.value as? String ?? ""
        field.tap(); field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue,count: prior.count) + text)
    }
    @MainActor func testOfflineAutomaticGenderManualUnspecifiedAndSavedEditPreservation() {
        let app = XCUIApplication(); app.launchArguments = ["--kin-test-notebook",UUID().uuidString]
        app.launch(); defer { app.terminate() }
        XCTAssertTrue(app.buttons["Add person"].waitForExistence(timeout: 10)); app.buttons["Add person"].tap()
        let first = app.textFields["First name (optional)"]
        first.tap(); first.typeText("Michael")
        let gender = app.buttons["gender-choice"]
        XCTAssertEqual(gender.value as? String,"Male")
        replace(first,with: "Samantha"); XCTAssertEqual(gender.value as? String,"Female")
        replace(first,with: "Synthetic Unmatched Fixture"); XCTAssertEqual(gender.value as? String,"Unspecified")
        gender.tap(); app.buttons["Unspecified"].tap()
        replace(first,with: "Chris"); XCTAssertEqual(gender.value as? String,"Unspecified")
        gender.tap(); app.buttons["Other"].tap()
        replace(first,with: "Mike"); XCTAssertEqual(gender.value as? String,"Other")
        capture(app,"Offline default manually overridden - synthetic")
        app.buttons["Save"].tap(); XCTAssertTrue(app.navigationBars["Mike"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Gender: Other"].exists)
        app.navigationBars.buttons["Edit"].tap()
        replace(first,with: "Michael"); XCTAssertEqual(gender.value as? String,"Other")
        app.buttons["Cancel"].tap(); XCTAssertTrue(app.navigationBars["Mike"].exists)
    }
    @MainActor func testPeopleFilterAndGenderControlsAtLargestTextWithUnfilteredAudit() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--kin-test-notebook",UUID().uuidString,"-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL","-UIAccessibilityBoldTextEnabled","YES"]
        app.launch(); defer { app.terminate() }
        XCTAssertTrue(app.buttons["Add person"].waitForExistence(timeout: 10))
        let filter = app.buttons["category-filter"]
        XCTAssertTrue(filter.isHittable); XCTAssertGreaterThanOrEqual(filter.frame.height,44)
        capture(app,"People category filter largest text - synthetic")
        try app.performAccessibilityAudit(for: [.contrast,.hitRegion,.textClipped,.trait]) { issue in
            print("People audit: \(issue.compactDescription); \(issue.detailedDescription); element=\(issue.element?.label ?? "unresolved")")
            return false
        }
        app.buttons["Add person"].tap()
        let gender = app.buttons["gender-choice"]
        let nameHeader = app.staticTexts.matching(NSPredicate(format: "label ==[c] %@","Name")).firstMatch
        let top = app.navigationBars["Add person"].frame.maxY + 12
        let bottom = app.frame.maxY - 20
        var fullyRevealed = false
        for _ in 0..<12 {
            let headerFrame = nameHeader.exists ? nameHeader.frame : CGRect.null
            let genderFrame = gender.exists ? gender.frame : CGRect.null
            if !headerFrame.isNull && !genderFrame.isNull && gender.isHittable && headerFrame.minY >= top && genderFrame.maxY <= bottom {
                fullyRevealed = true; break
            }
            let up = genderFrame.isNull || genderFrame.maxY > bottom
            let distance = headerFrame.isNull || genderFrame.isNull ? 100
                : min((bottom - top) * 0.6,max(44,up ? genderFrame.maxY - bottom + 12 : top - headerFrame.minY + 12))
            let middle = (top + bottom) / 2
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.midX,dy: middle + (up ? distance / 2 : -distance / 2)))
            let end = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.midX,dy: middle + (up ? -distance / 2 : distance / 2)))
            start.press(forDuration: 0.05,thenDragTo: end,withVelocity: .slow,thenHoldForDuration: 0.15)
        }
        XCTAssertTrue(fullyRevealed,"Reveal the complete Name heading and Gender row outside native toolbar material")
        let geometry = XCTAttachment(string: "Name=\(nameHeader.frame) Gender=\(gender.frame) top=\(top) bottom=\(bottom)")
        geometry.name = "Synthetic gender audit exposed bounds"; geometry.lifetime = .keepAlways; add(geometry)
        XCTAssertTrue(gender.isHittable); XCTAssertGreaterThanOrEqual(gender.frame.height,44)
        capture(app,"Gender choice largest text - synthetic")
        try app.performAccessibilityAudit(for: [.contrast,.hitRegion,.textClipped,.trait]) { issue in
            print("Gender audit: \(issue.compactDescription); \(issue.detailedDescription); element=\(issue.element?.label ?? "unresolved")")
            return false
        }
        gender.tap(); app.buttons["Unspecified"].tap()
        app.buttons["Cancel"].tap(); XCTAssertTrue(app.navigationBars["People"].exists)
    }
    @MainActor func testEditConnectionFollowsPhotoAtStandardText() { verifyEditorOrder(large: false) }
    @MainActor func testEditConnectionFollowsPhotoAtLargestText() { verifyEditorOrder(large: true) }
    @MainActor private func verifyEditorOrder(large: Bool) {
        let app = XCUIApplication()
        app.launchArguments = ["--kin-preview","relationships"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch(); defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Synthetic Source"].waitForExistence(timeout: 10))
        app.staticTexts["Synthetic Source"].tap(); app.navigationBars.buttons["Edit"].tap()
        XCTAssertTrue(app.navigationBars["Edit person"].waitForExistence(timeout: 5))
        let photo = app.staticTexts.matching(NSPredicate(format: "label ==[c] %@","Photo")).firstMatch
        let connection = app.staticTexts.matching(NSPredicate(format: "label ==[c] %@","Your connection")).firstMatch
        var sawPhoto = false, sawConnection = false
        for _ in 0..<20 {
            if photo.isHittable { sawPhoto = true }
            if connection.isHittable {
                XCTAssertTrue(sawPhoto,"Photo must be encountered before Your connection in visual and accessibility reading order")
                sawConnection = true
                capture(app,large ? "Connection below Photo largest - synthetic" : "Connection below Photo standard - synthetic")
                break
            }
            app.swipeUp()
        }
        XCTAssertTrue(sawPhoto && sawConnection)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Synthetic Source"].exists)
    }

    @MainActor func testEditorCancelBackgroundContainsLabelAtStandardText() { verifyCancelBackground(large: false) }
    @MainActor func testEditorCancelBackgroundContainsLabelAtLargestText() { verifyCancelBackground(large: true) }
    @MainActor private func verifyCancelBackground(large: Bool) {
        let app = XCUIApplication()
        let personName = large ? "Synthetic Cancel Large" : "Synthetic Cancel Standard"
        app.launchArguments = ["--kin-test-notebook",UUID().uuidString]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch(); defer { app.terminate() }
        XCTAssertTrue(app.buttons["Add person"].waitForExistence(timeout: 10))
        app.buttons["Add person"].tap()
        let first = app.textFields["First name (optional)"]
        first.tap(); first.typeText(personName); app.buttons["Save"].tap()
        XCTAssertTrue(app.navigationBars[personName].waitForExistence(timeout: 5))
        app.navigationBars[personName].buttons["Edit"].tap()
        let bar = app.navigationBars["Edit person"]
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        let cancel = bar.buttons["Cancel"], save = bar.buttons["Save"]
        // Native toolbar text caps its Dynamic Type size independently of
        // form body text. Measure the rendered word instead of guessing a font.
        app.swipeUp() // Show the toolbar background over scrolled content.
        var priorCancel = CGRect.null, priorSave = CGRect.null
        var stableSince = Date()
        let toolbarReady = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard cancel.exists && save.exists && cancel.isHittable && save.isHittable else { return false }
            let currentCancel = cancel.frame, currentSave = save.frame
            if currentCancel != priorCancel || currentSave != priorSave {
                priorCancel = currentCancel; priorSave = currentSave; stableSince = Date(); return false
            }
            return Date().timeIntervalSince(stableSince) >= 1
        },object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [toolbarReady],timeout: 8),.completed,"Measure settled native toolbar geometry")
        capture(app,large ? "Editor Cancel largest text - synthetic" : "Editor Cancel standard - synthetic")
        XCTAssertGreaterThanOrEqual(cancel.frame.width,44)
        XCTAssertGreaterThanOrEqual(cancel.frame.height,44)
        let measuredScreenshot = app.screenshot()
        let measuredAttachment = XCTAttachment(screenshot: measuredScreenshot)
        measuredAttachment.name = "Exact Cancel measurement pixels - synthetic"; measuredAttachment.lifetime = .keepAlways; add(measuredAttachment)
        guard let image = measuredScreenshot.image.cgImage else { XCTFail("Missing synthetic screenshot"); return }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false
        do { try VNImageRequestHandler(cgImage: image,options: [:]).perform([request]) }
        catch { XCTFail("Could not measure rendered Cancel text"); return }
        let words = (request.results ?? []).filter { $0.topCandidates(1).first?.string == "Cancel" }
            .map { observation in
                let box = observation.boundingBox, screen = app.frame
                return CGRect(x: screen.minX + box.minX * screen.width,
                    y: screen.minY + (1 - box.maxY) * screen.height,
                    width: box.width * screen.width,height: box.height * screen.height)
            }.filter { $0.intersects(cancel.frame) }
        XCTAssertEqual(words.count,1,"Require one rendered Cancel title at the actual button")
        guard let recognizedWord = words.first else { return }
        // Vision's line box can overshoot the actual glyphs on iOS 26. Keep
        // recognition as the semantic guard, then measure the visible light ink
        // on Cancel's opaque dark background, including outside its hit frame.
        let width = image.width, height = image.height, screen = app.frame
        let scaleX = CGFloat(width) / screen.width, scaleY = CGFloat(height) / screen.height
        var pixels = [UInt8](repeating: 0,count: width * height * 4)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress,width: width,height: height,bitsPerComponent: 8,
                bytesPerRow: width * 4,space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
            else { return false }
            context.draw(image,in: CGRect(x: 0,y: 0,width: width,height: height))
            return true
        }
        guard rendered else { XCTFail("Cannot measure synthetic Cancel ink"); return }
        let region = cancel.frame.insetBy(dx: -12,dy: 0).intersection(
            CGRect(x: screen.minX,y: recognizedWord.minY - 2,width: screen.width,height: recognizedWord.height + 4))
            .intersection(screen)
        var left = width, right = -1, topPixel = height, bottomPixel = -1
        for y in max(0,Int((region.minY - screen.minY) * scaleY))..<min(height,Int(ceil((region.maxY - screen.minY) * scaleY))) {
            for x in max(0,Int((region.minX - screen.minX) * scaleX))..<min(width,Int(ceil((region.maxX - screen.minX) * scaleX))) {
                let offset = (y * width + x) * 4
                if min(pixels[offset],pixels[offset + 1],pixels[offset + 2]) >= 180 {
                    left = min(left,x); right = max(right,x); topPixel = min(topPixel,y); bottomPixel = max(bottomPixel,y)
                }
            }
        }
        XCTAssertGreaterThanOrEqual(right,left,"Require visible Cancel glyphs in the recognized word region")
        guard right >= left else { return }
        let word = CGRect(x: screen.minX + CGFloat(left) / scaleX,y: screen.minY + CGFloat(topPixel) / scaleY,
            width: CGFloat(right - left + 1) / scaleX,height: CGFloat(bottomPixel - topPixel + 1) / scaleY)
        let geometry = XCTAttachment(string: "Application=\(app.frame) Cancel=\(cancel.frame) Save=\(save.frame) OCR=\(recognizedWord) ink=\(word) pixels=\(image.width)x\(image.height)")
        geometry.name = "Synthetic Cancel pixel and accessibility geometry"; geometry.lifetime = .keepAlways; add(geometry)
        // Vision bounds and pixel rasterization may round by two physical
        // pixels. Preserve an eight-point inset requirement within that tolerance.
        let pixelTolerance = 2 * app.frame.width / CGFloat(image.width)
        XCTAssertLessThanOrEqual(cancel.frame.minX - pixelTolerance,word.minX - 8)
        XCTAssertGreaterThanOrEqual(cancel.frame.maxX + pixelTolerance,word.maxX + 8)
        XCTAssertTrue(cancel.frame.contains(word))
        XCTAssertFalse(cancel.frame.intersects(save.frame))
        XCTAssertTrue(cancel.isHittable && save.isHittable)
        cancel.tap()
        XCTAssertTrue(app.navigationBars[personName].waitForExistence(timeout: 5))
    }

    @MainActor func testFeatureReferencesReadAsOneSentenceAtStandardText() { verifyFeatureReferences(large: false) }
    @MainActor func testFeatureReferencesReadAsOneSentenceAtLargestText() { verifyFeatureReferences(large: true) }
    @MainActor private func verifyFeatureReferences(large: Bool) {
        let app = XCUIApplication()
        app.launchArguments = ["--kin-preview","relationships"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch(); defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Synthetic Source"].waitForExistence(timeout: 10))
        app.staticTexts["Synthetic Source"].tap()
        let addChild = app.buttons["Add child"]
        for _ in 0..<12 { if addChild.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(addChild.isHittable)
        addChild.tap()
        let guidance = app.staticTexts["linked-person-guidance"]
        XCTAssertTrue(guidance.waitForExistence(timeout: 5))
        let expected = "After saving, find this person in linked profiles or on the All people screen. To also show them on your main list, turn on the Show on main list setting."
        XCTAssertEqual(guidance.label,expected,"Styled references must keep one plain accessibility reading order")
        XCTAssertFalse(guidance.label.contains("**")); XCTAssertFalse(guidance.label.contains("<b>"))
        for _ in 0..<12 {
            if guidance.isHittable && guidance.frame.minY >= app.navigationBars["Add child"].frame.maxY && guidance.frame.maxY < app.frame.maxY - 32 { break }
            app.swipeUp()
        }
        XCTAssertTrue(guidance.isHittable)
        XCTAssertLessThanOrEqual(guidance.frame.maxY,app.frame.maxY - 32)
        capture(app,large ? "Semibold feature references largest - synthetic" : "Semibold feature references standard - synthetic")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Synthetic Source"].waitForExistence(timeout: 5))
    }

}
