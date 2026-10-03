import ContactsUI
import ImageIO
import UIKit
import Testing
@testable import Kin

@Suite("Partner contact import") @MainActor struct PartnerContactImportTests {
    private func syntheticPhoto() throws -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1600, height: 800), format: format).image { context in
            UIColor.systemOrange.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1600, height: 800))
        }
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(image.cgImage), [kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 0, kCGImagePropertyGPSLongitude: 0]] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    @Test("Partner import populates only draft names and a bounded metadata-free photo")
    func fieldsAndPhotoMatchFriendImport() throws {
        let snapshot = ContactSnapshot(firstName: "Synthetic", lastName: "Partner", photo: try syntheticPhoto())
        var partner = Partner(firstName: "Before", lastName: "Draft", gender: .female, isCurrent: false)
        let id = partner.id
        var friend = Friend(firstName: "Before", lastName: "Draft", notes: "Fictional note")
        ContactImport.apply(snapshot, to: &friend)
        ContactImport.apply(snapshot, to: &partner)
        #expect(partner.firstName == friend.firstName && partner.lastName == friend.lastName)
        #expect(partner.photo == friend.photo)
        #expect(partner.id == id && partner.gender == .female && !partner.isCurrent)
        #expect(friend.notes == "Fictional note")
        let photo = try #require(partner.photo)
        let image = try #require(UIImage(data: photo)?.cgImage)
        #expect(image.width == 640 && image.height == 320)
        let source = try #require(CGImageSourceCreateWithData(photo as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyGPSDictionary] == nil)
    }

    @Test("Selection waits for dismissal and explicit Save, preserving replacement and child links")
    func reviewThenExplicitSave() throws {
        let store = try KinStore(inMemory: true); defer { try? store.close() }
        let old = Partner(firstName: "Mira", lastName: "Vale")
        let child = Child(firstName: "Ari", lastName: "Vale", birthday: .exact(CivilDate(year: 2020, month: 1, day: 1)), partnerID: old.id)
        let family = Friend(firstName: "Rowan", lastName: "Vale", partners: [old], children: [child])
        try store.saveFriend(family)
        var draft = Partner(firstName: "", lastName: "Vale")
        let pickerView = ContactPicker(onSelect: { ContactImport.apply($0, to: &draft) }, onCancel: {})
        let coordinator = pickerView.makeCoordinator(); let picker = CNContactPickerViewController()
        let contact = CNMutableContact(); contact.givenName = "Synthetic"; contact.familyName = "Partner"
        coordinator.contactPicker(picker, didSelect: contact)
        #expect(draft.firstName.isEmpty)
        coordinator.pickerDidDismiss()
        coordinator.contactPickerDidCancel(picker); coordinator.pickerDidDismiss()
        #expect(draft.firstName == "Synthetic")
        #expect(store.friends.first?.partners == [old])
        #expect(throws: (any Error).self) { try store.savePartner(draft, friendID: family.id) }
        #expect(store.friends.first?.partners == [old])
        try store.savePartner(draft, friendID: family.id, replaceCurrent: true)
        #expect(store.friends.first?.currentPartner?.id == draft.id)
        #expect(store.friends.first?.children.first?.partnerID == old.id)
        #expect(store.friends.first?.partners.first(where: { $0.id == old.id })?.isCurrent == false)
    }

    @Test("Cancel, teardown, reopen and repeated events cannot overwrite the partner draft")
    func cancelledAndRepeatedImports() {
        var draft = Partner(firstName: "Review", lastName: "Draft", isCurrent: false)
        let original = draft
        var deliveries = 0
        let view = ContactPicker(onSelect: { ContactImport.apply($0, to: &draft); deliveries += 1 }, onCancel: {})
        let picker = CNContactPickerViewController()
        let contact = CNMutableContact(); contact.givenName = "Synthetic"; contact.familyName = "Partner"
        let cancelled = view.makeCoordinator()
        cancelled.contactPickerDidCancel(picker); cancelled.contactPicker(picker, didSelect: contact); cancelled.pickerDidDismiss()
        #expect(draft == original && deliveries == 0)
        let stale = view.makeCoordinator()
        stale.contactPicker(picker, didSelect: contact); stale.invalidate(); stale.pickerDidDismiss()
        #expect(draft == original && deliveries == 0)
        let reopened = view.makeCoordinator()
        reopened.contactPicker(picker, didSelect: contact); reopened.contactPicker(picker, didSelect: contact)
        reopened.pickerDidDismiss(); reopened.pickerDidDismiss(); reopened.contactPickerDidCancel(picker)
        #expect(deliveries == 1 && draft.firstName == "Synthetic")
        #expect(draft.id == original.id && !draft.isCurrent)
    }

    @Test("Missing or unreadable contact photos match friend behavior and empty names cannot save")
    func absentPhotoAndInvalidName() throws {
        let store = try KinStore(inMemory: true); defer { try? store.close() }
        let family = Friend(firstName: "Rowan", lastName: "Vale"); try store.saveFriend(family)
        for photo in [Optional<Data>.none, Data([1, 2, 3])] {
            var partner = Partner(firstName: "Before", lastName: "Draft", photo: Data([9]))
            var friend = Friend(firstName: "Before", lastName: "Draft", photo: Data([9]))
            let snapshot = ContactSnapshot(firstName: "", lastName: "Partner", photo: photo)
            ContactImport.apply(snapshot, to: &partner); ContactImport.apply(snapshot, to: &friend)
            #expect(partner.photo == nil && friend.photo == nil)
            #expect(throws: (any Error).self) { try store.savePartner(partner, friendID: family.id) }
        }
        #expect(store.friends.first?.partners.isEmpty == true)
    }
}
