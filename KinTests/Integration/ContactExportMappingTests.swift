import Contacts
import Foundation
import Testing
@testable import Kin

@Suite("Contacts export field mapping") @MainActor struct ContactExportMappingTests {
    @Test("Selected values preserve leap days while leaving unselected contact data intact")
    func appliedChanges() {
        let contact = CNMutableContact()
        contact.givenName = "Original"
        contact.familyName = "Preserved"
        contact.organizationName = "Synthetic organization"
        let email = ["synthetic", "example.com"].joined(separator: "@")
        contact.emailAddresses = [CNLabeledValue(label: CNLabelWork, value: email as NSString)]
        contact.birthday = DateComponents(month: 9, day: 4)
        ContactExportStore.apply(.init(firstName: "New", birthday: CivilDate(year: 2000, month: 2, day: 29)), to: contact)
        #expect(contact.givenName == "New")
        #expect(contact.familyName == "Preserved")
        #expect(contact.birthday == DateComponents(year: 2000, month: 2, day: 29))
        #expect(contact.organizationName == "Synthetic organization")
        #expect(contact.emailAddresses.first?.value as String? == email)
        ContactExportStore.apply(.init(lastName: "New surname"), to: contact)
        #expect(contact.birthday == DateComponents(year: 2000, month: 2, day: 29))
    }
}
