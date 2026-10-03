import ContactsUI
import SwiftUI
import Testing
@testable import Kin

@Suite("Contact import lifecycle") @MainActor struct ContactPickerTests {
    private func controllerType<T: UIViewControllerRepresentable>(of view: T) -> UIViewController.Type { T.UIViewControllerType.self }

    @Test("System picker does not own the SwiftUI editor sheet")
    func pickerHasSeparatePresentationOwner() {
        let view = ContactPicker(onSelect: { _ in }, onCancel: {})
        #expect(controllerType(of: view) != CNContactPickerViewController.self)
    }

    @Test("Duplicate selection and trailing cancellation resolve only once")
    func selectionResolvesOnce() {
        var selected = [String](); var cancellations = 0
        let view = ContactPicker(onSelect: { selected.append($0.firstName) }, onCancel: { cancellations += 1 })
        let coordinator = view.makeCoordinator(); let picker = CNContactPickerViewController()
        let contact = CNMutableContact(); contact.givenName = "Synthetic"; contact.familyName = "Friend"
        coordinator.contactPicker(picker, didSelect: contact)
        coordinator.contactPicker(picker, didSelect: contact)
        coordinator.contactPickerDidCancel(picker)
        #expect(selected.isEmpty)
        coordinator.pickerDidDismiss()
        coordinator.pickerDidDismiss()
        #expect(selected == ["Synthetic"])
        #expect(cancellations == 0)
    }

    @Test("Cancelled import ignores late selection callbacks")
    func cancelledImportIgnoresLateSelection() {
        var selected = 0; var cancellations = 0
        let view = ContactPicker(onSelect: { _ in selected += 1 }, onCancel: { cancellations += 1 })
        let coordinator = view.makeCoordinator(); let picker = CNContactPickerViewController()
        coordinator.contactPickerDidCancel(picker)
        coordinator.contactPickerDidCancel(picker)
        coordinator.contactPicker(picker, didSelect: CNMutableContact())
        #expect(cancellations == 0)
        coordinator.pickerDidDismiss()
        coordinator.pickerDidDismiss()
        #expect(selected == 0)
        #expect(cancellations == 1)
    }

    @Test("Imported names remain an unsaved draft until explicit Save")
    func importRequiresExplicitSave() throws {
        let store = try KinStore(inMemory: true)
        defer { try? store.close() }
        var draft = Friend(firstName: "", lastName: "")
        let view = ContactPicker(onSelect: { snapshot in
            draft.firstName = snapshot.firstName; draft.lastName = snapshot.lastName
        }, onCancel: {})
        let coordinator = view.makeCoordinator()
        let contact = CNMutableContact(); contact.givenName = "Synthetic"; contact.familyName = "Friend"
        coordinator.contactPicker(CNContactPickerViewController(), didSelect: contact)
        #expect(draft.firstName.isEmpty)
        coordinator.pickerDidDismiss()
        #expect(draft.firstName == "Synthetic")
        #expect(store.friends.isEmpty)
        try store.saveFriend(draft)
        #expect(store.friends.count == 1)
    }

    @Test("Leaving a picker invalidates pending callbacks; a new import works")
    func teardownAndRepeatImport() {
        var selected = 0; var cancelled = 0
        let view = ContactPicker(onSelect: { _ in selected += 1 }, onCancel: { cancelled += 1 })
        let stale = view.makeCoordinator()
        let picker = CNContactPickerViewController()
        stale.contactPicker(picker, didSelect: CNMutableContact())
        stale.invalidate()
        stale.pickerDidDismiss()
        #expect(selected == 0 && cancelled == 0)
        let fresh = view.makeCoordinator()
        fresh.contactPicker(picker, didSelect: CNMutableContact())
        fresh.pickerDidDismiss()
        stale.contactPickerDidCancel(picker)
        #expect(selected == 1 && cancelled == 0)
    }
}
