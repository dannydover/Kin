import SwiftUI
import ContactsUI
#if DEBUG && KIN_PICKER_LIFECYCLE_DIAGNOSTIC
import ObjectiveC
#endif

@MainActor struct ContactSnapshot {
    let photoIdentity = UUID()
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
        #if DEBUG && KIN_PICKER_LIFECYCLE_DIAGNOSTIC
        PickerLifecycleProbe.install()
        #endif
        let picker = CNContactPickerViewController()
        #if DEBUG && KIN_PICKER_LIFECYCLE_DIAGNOSTIC
        PickerLifecycleProbe.record("picker.created", picker)
        #endif
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
        #if DEBUG && KIN_PICKER_LIFECYCLE_DIAGNOSTIC
        PickerLifecycleProbe.record("container.dismantle", controller)
        #endif
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
            #if DEBUG && KIN_PICKER_LIFECYCLE_DIAGNOSTIC
            PickerLifecycleProbe.record("container.didLoad", self)
            #endif
        }
        #if DEBUG && KIN_PICKER_LIFECYCLE_DIAGNOSTIC
        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            PickerLifecycleProbe.record("container.willAppear", self)
        }
        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            PickerLifecycleProbe.record("container.willDisappear", self)
        }
        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            PickerLifecycleProbe.record("container.didDisappear", self)
        }
        #endif
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            #if DEBUG && KIN_PICKER_LIFECYCLE_DIAGNOSTIC
            PickerLifecycleProbe.record("container.didAppear", self)
            #endif
            if !hasPresented {
                hasPresented = true
                let picker = ContactPicker.makePicker(delegate: coordinator)
                // A full-screen child returns appearance callbacks to this container
                // only after its automatic dismissal transition completes.
                picker.modalPresentationStyle = .fullScreen
                #if DEBUG && KIN_PICKER_LIFECYCLE_DIAGNOSTIC && KIN_PICKER_DEFER_DIAGNOSTIC
                presentAfterEnclosingTransition(picker)
                #else
                #if DEBUG && KIN_PICKER_LIFECYCLE_DIAGNOSTIC
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
                #else
                present(picker, animated: true)
                #endif
                #endif
            } else if presentedViewController == nil {
                coordinator.pickerDidDismiss()
            }
        }
        #if DEBUG && KIN_PICKER_LIFECYCLE_DIAGNOSTIC && KIN_PICKER_DEFER_DIAGNOSTIC
        private func presentAfterEnclosingTransition(_ picker: CNContactPickerViewController) {
            var issued = false
            let issue = { [weak self] in
                guard !issued else { return }
                guard let self, self.viewIfLoaded?.window != nil, !self.isBeingDismissed else {
                    PickerLifecycleProbe.record("variant.detached", self, peer: picker)
                    return
                }
                issued = true
                PickerLifecycleProbe.record("container.beforePresent", self, peer: picker)
                self.present(picker, animated: true) { [weak self, weak picker] in
                    PickerLifecycleProbe.record("container.presentCompletion", self, peer: picker)
                }
                PickerLifecycleProbe.record("container.afterPresent", self, peer: picker)
                for delay in [0.5, 2.0, 5.0, 9.0] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak picker] in
                        PickerLifecycleProbe.record("container.snapshot", self, peer: picker)
                    }
                }
            }
            guard let transition = transitionCoordinator else {
                PickerLifecycleProbe.record("variant.noCoordinator", self, peer: picker)
                issue()
                return
            }
            PickerLifecycleProbe.record("variant.waiting", self, peer: picker)
            let queued = transition.animate(alongsideTransition: nil) { [weak self] context in
                PickerLifecycleProbe.record(context.isCancelled ? "variant.cancelled" : "variant.enclosingCompleted", self, peer: picker)
                guard !context.isCancelled else { return }
                DispatchQueue.main.async {
                    PickerLifecycleProbe.record("variant.nextTurn", self, peer: picker)
                    issue()
                }
            }
            PickerLifecycleProbe.record(queued ? "variant.completionRegistered" : "variant.registrationRejected", self, peer: picker)
            if !queued {
                // UIKit may still invoke the completion when animation registration
                // returns false. Share the one-shot guard with this settled-state path.
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    if self.transitionCoordinator == nil {
                        PickerLifecycleProbe.record("variant.alreadySettled", self, peer: picker)
                        issue()
                    } else {
                        PickerLifecycleProbe.record("variant.stillWaiting", self, peer: picker)
                    }
                }
            }
        }
        #endif
    }

    @MainActor final class Coordinator: NSObject, @preconcurrency CNContactPickerDelegate {
        var parent: ContactPicker
        private enum Outcome { case selected(ContactSnapshot), cancelled }
        private var outcome: Outcome?
        private var finished = false
        init(parent: ContactPicker) { self.parent = parent }
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            #if DEBUG && KIN_PICKER_LIFECYCLE_DIAGNOSTIC
            PickerLifecycleProbe.record("picker.didSelect", picker)
            #endif
            guard outcome == nil, !finished else { return }
            outcome = .selected(ContactSnapshot(contact: contact))
        }
        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            #if DEBUG && KIN_PICKER_LIFECYCLE_DIAGNOSTIC
            PickerLifecycleProbe.record("picker.didCancel", picker)
            #endif
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

#if DEBUG && KIN_PICKER_LIFECYCLE_DIAGNOSTIC
/// Nonshipping callback logger. Original picker class/implementations and ordering
/// are preserved; wrappers only emit fixed state before/after forwarding callbacks.
@MainActor private enum PickerLifecycleProbe {
    private static var installed = false
    private static var nextID = 0
    private static var ids: [ObjectIdentifier: Int] = [:]
    private static func role(_ controller: UIViewController?) -> String {
        guard let controller else { return "none" }
        if controller is ContactPicker.Container { return "container" }
        if controller is CNContactPickerViewController { return "picker" }
        return "other"
    }
    private static func state(_ controller: UIViewController?) -> [String: Any] {
        guard let controller else { return ["role": "none"] }
        let key = ObjectIdentifier(controller)
        if ids[key] == nil { nextID += 1; ids[key] = nextID }
        return ["id": ids[key]!, "role": role(controller),
            "loaded": controller.isViewLoaded, "window": controller.viewIfLoaded?.window != nil,
            "beingPresented": controller.isBeingPresented, "beingDismissed": controller.isBeingDismissed,
            "presentedRole": role(controller.presentedViewController),
            "presenterRole": role(controller.presentingViewController),
            "transition": controller.transitionCoordinator != nil]
    }
    static func record(_ event: String, _ controller: UIViewController?, peer: UIViewController? = nil) {
        let payload: [String: Any] = ["event": event, "wall": Date().timeIntervalSince1970,
            "uptime": ProcessInfo.processInfo.systemUptime, "controller": state(controller), "peer": state(peer)]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let line = String(data: data, encoding: .utf8) else { return }
        NSLog("KIN_PICKER_LIFECYCLE %@", line)
    }
    static func install() {
        guard !installed else { return }
        installed = true
        let callbacks: [(Selector, String)] = [
            (#selector(UIViewController.viewWillAppear(_:)), "willAppear"),
            (#selector(UIViewController.viewDidAppear(_:)), "didAppear"),
            (#selector(UIViewController.viewWillDisappear(_:)), "willDisappear"),
            (#selector(UIViewController.viewDidDisappear(_:)), "didDisappear")]
        for (selector, event) in callbacks {
            guard let method = class_getInstanceMethod(CNContactPickerViewController.self, selector) else { continue }
            typealias Original = @convention(c) (UIViewController, Selector, Bool) -> Void
            let original = unsafeBitCast(method_getImplementation(method), to: Original.self)
            let block: @convention(block) (UIViewController, Bool) -> Void = { controller, animated in
                if Thread.isMainThread {
                    MainActor.assumeIsolated { record("picker." + event + ".enter", controller) }
                }
                original(controller, selector, animated)
                if Thread.isMainThread {
                    MainActor.assumeIsolated { record("picker." + event + ".exit", controller) }
                }
            }
            let implementation = imp_implementationWithBlock(block)
            if !class_addMethod(CNContactPickerViewController.self, selector, implementation, method_getTypeEncoding(method)) {
                class_replaceMethod(CNContactPickerViewController.self, selector, implementation, method_getTypeEncoding(method))
            }
        }
    }
}
#endif
