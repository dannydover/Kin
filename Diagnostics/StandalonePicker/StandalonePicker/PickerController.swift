import UIKit
import ContactsUI

@MainActor
final class PickerController: UIViewController, CNContactPickerDelegate {
    private func record(_ event: String, picker: CNContactPickerViewController? = nil) {
        let state: [String: Any] = ["event": event, "wall": Date().timeIntervalSince1970,
            "uptime": ProcessInfo.processInfo.systemUptime,
            "presenterWindow": isViewLoaded && view.window != nil,
            "pickerLoaded": picker?.isViewLoaded ?? false,
            "pickerWindow": picker?.viewIfLoaded?.window != nil]
        if let bytes = try? JSONSerialization.data(withJSONObject: state, options: [.sortedKeys]),
           let text = String(data: bytes, encoding: .utf8) { NSLog("STANDALONE_PICKER %@", text) }
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let button = UIButton(type: .system)
        button.setTitle("Open synthetic Contacts picker", for: .normal)
        button.accessibilityIdentifier = "standalone-picker-open"
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(openPicker), for: .touchUpInside)
        view.addSubview(button)
        NSLayoutConstraint.activate([button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                                     button.centerYAnchor.constraint(equalTo: view.centerYAnchor)])
        record("presenter.didLoad")
    }
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); record("presenter.didAppear") }
    @objc private func openPicker() {
        let picker = CNContactPickerViewController()
        picker.delegate = self
        picker.displayedPropertyKeys = [CNContactGivenNameKey, CNContactFamilyNameKey,
            CNContactBirthdayKey, CNContactNonGregorianBirthdayKey,
            CNContactThumbnailImageDataKey, CNContactImageDataKey]
        picker.modalPresentationStyle = .fullScreen
        record("present.before", picker: picker)
        present(picker, animated: true) { [weak self, weak picker] in self?.record("present.complete", picker: picker) }
        record("present.after", picker: picker)
        for delay in [0.5, 2.0, 5.0, 9.0, 14.0, 18.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak picker] in
                self?.record("present.snapshot", picker: picker)
            }
        }
    }
    func contactPickerDidCancel(_ picker: CNContactPickerViewController) { record("picker.cancel", picker: picker) }
}
