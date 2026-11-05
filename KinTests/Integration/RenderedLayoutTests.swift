import SwiftUI
import UIKit
import Testing
@testable import Kin

@Suite("Rendered person-row layout") @MainActor struct RenderedLayoutTests {
    @Test("Person row renders at standard and largest text sizes")
    func personRowAtTwoTextSizes() throws {
        let person = Person(firstName: "Synthetic Alexandra Montgomery Example")
        let today = CivilDate(year: 2026, month: 10, day: 23).pickerDate
        func render(_ size: DynamicTypeSize) throws -> UIImage {
            let row = PersonRow(person: person, today: today)
                .dynamicTypeSize(size)
                .frame(width: 320)
            let renderer = ImageRenderer(content: row)
            renderer.proposedSize = ProposedViewSize(width: 320, height: nil)
            return try #require(renderer.uiImage)
        }
        let standard = try render(.large)
        let largest = try render(.accessibility5)
        #expect(standard.size.width == 320 && largest.size.width == 320)
        #expect(standard.size.height > 0 && largest.size.height >= standard.size.height)
        #expect(standard.pngData() != nil && largest.pngData() != nil)
    }
}
