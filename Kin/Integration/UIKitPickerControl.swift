#if DEBUG && KIN_UIKIT_COMPARISON && KIN_PICKER_LIFECYCLE_DIAGNOSTIC
import SwiftUI
import ContactsUI

/// Synthetic diagnostic only. Presents the system picker directly from UIKit.
struct UIKitPickerControl: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}

    @MainActor final class Controller: UIViewController, CNContactPickerDelegate {
        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .systemBackground
            let button = UIButton(type: .system)
            button.setTitle("UIKit control import", for: .normal)
            button.accessibilityIdentifier = "uikit-control-import"
            button.translatesAutoresizingMaskIntoConstraints = false
            button.addTarget(self, action: #selector(openPicker), for: .touchUpInside)
            view.addSubview(button)
            NSLayoutConstraint.activate([button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                                         button.centerYAnchor.constraint(equalTo: view.centerYAnchor)])
            PickerLifecycleProbe.record("container.didLoad", self)
        }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            PickerLifecycleProbe.record("container.didAppear", self)
        }
        @objc private func openPicker() {
            PickerLifecycleProbe.install()
            let picker = CNContactPickerViewController()
            picker.delegate = self
            picker.displayedPropertyKeys = [CNContactGivenNameKey, CNContactFamilyNameKey,
                CNContactBirthdayKey, CNContactNonGregorianBirthdayKey,
                CNContactThumbnailImageDataKey, CNContactImageDataKey]
            picker.modalPresentationStyle = .fullScreen
            PickerLifecycleProbe.record("picker.created", picker)
            PickerLifecycleProbe.record("container.beforePresent", self, peer: picker)
            present(picker, animated: true) { [weak self, weak picker] in
                PickerLifecycleProbe.record("container.presentCompletion", self, peer: picker)
            }
            PickerLifecycleProbe.record("container.afterPresent", self, peer: picker)
            for delay in [0.5, 2.0, 5.0, 9.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak picker] in
                    PickerLifecycleProbe.record("container.snapshot", self, peer: picker)
                }
            }
        }
        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            PickerLifecycleProbe.record("picker.didCancel", picker)
        }
    }
}
#endif
