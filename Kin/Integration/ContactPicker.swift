import SwiftUI
import ContactsUI

@MainActor struct ContactSnapshot {
    var firstName: String
    var lastName: String
    var birthInformation: ContactBirthInformation = .missing
    // The selected card is retained only for this import. Reading image properties
    // is delayed until a confirmed birthday establishes safe photo eligibility.
    private var loadPhoto: () -> Data? = { nil }

    init(firstName: String, lastName: String, birthInformation: ContactBirthInformation = .missing, loadPhoto: @escaping () -> Data? = { nil }) {
        self.firstName = firstName; self.lastName = lastName
        self.birthInformation = birthInformation; self.loadPhoto = loadPhoto
    }
    func photo(for birthday: Birthday, today: Date, calendar: Calendar) -> Data? {
        guard AgeRules(calendar: calendar).allowsPhoto(birthday, on: today) else { return nil }
        return loadPhoto()
    }
    init(contact: CNContact, today: Date = Date(), timeZone: TimeZone = .current) {
        firstName = contact.isKeyAvailable(CNContactGivenNameKey) ? contact.givenName : ""
        lastName = contact.isKeyAvailable(CNContactFamilyNameKey) ? contact.familyName : ""
        let hasBirthday = contact.isKeyAvailable(CNContactBirthdayKey)
        let hasAlternateBirthday = contact.isKeyAvailable(CNContactNonGregorianBirthdayKey)
        let resolved = ContactBirthInformation.resolve(
            gregorian: hasBirthday ? contact.birthday : nil,
            alternate: hasAlternateBirthday ? contact.nonGregorianBirthday : nil,
            today: CivilDate(today, timeZone: timeZone))
        // An omitted picker field does not establish that the card has no birthday.
        birthInformation = resolved == .missing && !(hasBirthday && hasAlternateBirthday) ? .unavailable : resolved
        loadPhoto = {
            // Picker payloads can include image bytes without the availability flag,
            // or only the full-size image. This closure still runs after the age gate.
            if contact.isKeyAvailable(CNContactThumbnailImageDataKey), let data = contact.thumbnailImageData { return data }
            return contact.isKeyAvailable(CNContactImageDataKey) ? contact.imageData : nil
        }
    }
}

/// UIKit owns the system picker's dismissal. SwiftUI owns only the inert container.
struct ContactPicker: UIViewControllerRepresentable {
    var onSelect: (ContactSnapshot) -> Void
    var onCancel: () -> Void
    @MainActor static func makePicker(delegate: CNContactPickerDelegate) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = delegate
        picker.displayedPropertyKeys = [CNContactGivenNameKey, CNContactFamilyNameKey,
            CNContactBirthdayKey, CNContactNonGregorianBirthdayKey,
            CNContactThumbnailImageDataKey, CNContactImageDataKey]
        return picker
    }
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIViewController(context: Context) -> Container {
        Container(coordinator: context.coordinator)
    }
    func updateUIViewController(_ controller: Container, context: Context) {
        context.coordinator.parent = self
    }
    static func dismantleUIViewController(_ controller: Container, coordinator: Coordinator) {
        coordinator.invalidate()
    }

    @MainActor final class Container: UIViewController {
        private let coordinator: Coordinator
        private var hasPresented = false
        init(coordinator: Coordinator) {
            self.coordinator = coordinator
            super.init(nibName: nil, bundle: nil)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .systemBackground
        }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            if !hasPresented {
                hasPresented = true
                let picker = ContactPicker.makePicker(delegate: coordinator)
                // A full-screen child returns appearance callbacks to this container
                // only after its automatic dismissal transition completes.
                picker.modalPresentationStyle = .fullScreen
                present(picker, animated: true)
            } else if presentedViewController == nil {
                coordinator.pickerDidDismiss()
            }
        }
    }

    @MainActor final class Coordinator: NSObject, @preconcurrency CNContactPickerDelegate {
        var parent: ContactPicker
        private enum Outcome { case selected(ContactSnapshot), cancelled }
        private var outcome: Outcome?
        private var finished = false
        init(parent: ContactPicker) { self.parent = parent }
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            guard outcome == nil, !finished else { return }
            outcome = .selected(ContactSnapshot(contact: contact))
        }
        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            guard outcome == nil, !finished else { return }
            outcome = .cancelled
        }
        func pickerDidDismiss() {
            guard !finished else { return }
            finished = true
            switch outcome {
            case .selected(let snapshot): parent.onSelect(snapshot)
            case .cancelled, nil: parent.onCancel()
            }
            outcome = nil
        }
        func invalidate() { finished = true; outcome = nil }
    }
}
