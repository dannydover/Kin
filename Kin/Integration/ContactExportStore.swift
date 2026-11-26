import Contacts
import Foundation

struct ContactExportAccount: Equatable {
    let id: String
    let title: String
}

struct ContactExportDestination: Identifiable {
    let id: String
    let account: ContactExportAccount
    let firstName: String
    let lastName: String
    let hints: String

    var name: String {
        let name = [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
        return name.isEmpty ? "Unnamed contact" : name
    }
    var distinguishingLabel: String { [name, account.title, hints].joined(separator: "\n") }
    var link: ContactExportLink { .linked(identifier: id, container: account.id) }
}

/// Kept in the review sheet only. Never persist values read from Contacts.
struct ContactExportCurrent {
    let destination: ContactExportDestination
    let birthday: DateComponents?
    let alternateBirthday: DateComponents?
    let photo: Data?
}

struct ContactExportPlan {
    enum Target { case create(ContactExportAccount), update(ContactExportCurrent) }
    let personID: UUID
    let expectedLink: ContactExportLink?
    let target: Target
    let fields: Set<ContactExportField>
    let values: ContactExportValues

    var account: ContactExportAccount {
        switch target { case .create(let account): account; case .update(let current): current.destination.account }
    }

    var isNew: Bool { if case .create = target { true } else { false } }
}

@MainActor struct ContactExportStore {
    private let contacts = CNContactStore()

    func requestAccess() async throws -> Bool {
        if CNContactStore.authorizationStatus(for: .contacts) == .notDetermined {
            _ = try await contacts.requestAccess(for: .contacts)
        }
        return hasAccess
    }

    var hasAccess: Bool {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        return status == .authorized || status == .limited
    }

    var isLimited: Bool { CNContactStore.authorizationStatus(for: .contacts) == .limited }

    private var identityKeys: [CNKeyDescriptor] {
        [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey, CNContactEmailAddressesKey] as [CNKeyDescriptor]
    }

    private func rawContacts(matching predicate: NSPredicate, keys: [CNKeyDescriptor]) throws -> [CNContact] {
        guard hasAccess else { throw ContactExportError.unavailable }
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.unifyResults = false
        request.predicate = predicate
        var values = [CNContact]()
        try contacts.enumerateContacts(with: request) { contact, _ in values.append(contact) }
        return values
    }

    private func account(_ container: CNContainer) -> ContactExportAccount {
        let title = switch container.type {
        case .local: "On this iPhone"
        case .exchange: "Exchange"
        case .cardDAV: "Synced account"
        case .unassigned: "Contacts account"
        @unknown default: "Contacts account"
        }
        let name = container.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return .init(id: container.identifier, title: name.isEmpty || name == title ? title : "\(name) (\(title))")
    }

    func defaultAccount() throws -> ContactExportAccount {
        guard hasAccess else { throw ContactExportError.unavailable }
        let identifier = contacts.defaultContainerIdentifier()
        guard !identifier.isEmpty,
              let container = try contacts.containers(matching: CNContainer.predicateForContainers(withIdentifiers: [identifier])).first
        else { throw ContactExportError.noAccount }
        return account(container)
    }

    private func destination(_ contact: CNContact) throws -> ContactExportDestination {
        let containers = try contacts.containers(matching: CNContainer.predicateForContainerOfContact(withIdentifier: contact.identifier))
        guard containers.count == 1, let container = containers.first else { throw ContactExportError.noAccount }
        let hints = (contact.emailAddresses.map { $0.value as String } + contact.phoneNumbers.map {
            let digits = $0.value.stringValue.filter(\.isNumber)
            return digits.isEmpty ? "" : "Phone ending in \(digits.suffix(4))"
        }).filter { !$0.isEmpty }.sorted().joined(separator: "\n")
        return .init(id: contact.identifier, account: account(container), firstName: contact.givenName,
                     lastName: contact.familyName, hints: hints)
    }

    func find(_ name: String) throws -> [ContactExportDestination] {
        let text = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        return try rawContacts(matching: CNContact.predicateForContacts(matchingName: text), keys: identityKeys)
            .map(destination).sorted { $0.distinguishingLabel.localizedStandardCompare($1.distinguishingLabel) == .orderedAscending }
    }

    func existing(_ identifier: String, fields: Set<ContactExportField>) throws -> ContactExportCurrent {
        try current(identifier, fields: fields).1
    }

    private func current(_ identifier: String, fields: Set<ContactExportField>) throws -> (CNContact, ContactExportCurrent) {
        var keys = identityKeys
        if fields.contains(.birthday) { keys += [CNContactBirthdayKey, CNContactNonGregorianBirthdayKey] as [CNKeyDescriptor] }
        if fields.contains(.photo) { keys.append(CNContactImageDataKey as CNKeyDescriptor) }
        let values = try rawContacts(matching: CNContact.predicateForContacts(withIdentifiers: [identifier]), keys: keys)
        guard values.count == 1, let contact = values.first, contact.identifier == identifier else {
            throw ContactExportError.unavailable
        }
        return (contact, .init(destination: try destination(contact),
                               birthday: fields.contains(.birthday) ? contact.birthday : nil,
                               alternateBirthday: fields.contains(.birthday) ? contact.nonGregorianBirthday : nil,
                               photo: fields.contains(.photo) ? contact.imageData : nil))
    }

    /// Fresh reads retain unselected fields. Compare the reviewed record before
    /// applying only the selected changes. Missing data never clears Contacts.
    func save(_ plan: ContactExportPlan) throws -> ContactExportLink {
        let request = CNSaveRequest()
        let mutable: CNMutableContact
        switch plan.target {
        case .create(let account):
            guard try defaultAccount() == account else { throw ContactExportError.reviewAgain }
            mutable = CNMutableContact()
            Self.apply(plan.values, to: mutable)
            request.add(mutable, toContainerWithIdentifier: account.id)
        case .update(let reviewed):
            let (contact, fresh) = try current(reviewed.destination.id, fields: plan.fields)
            guard fresh.destination.account == reviewed.destination.account,
                  fresh.destination.distinguishingLabel == reviewed.destination.distinguishingLabel,
                  fresh.birthday == reviewed.birthday, fresh.alternateBirthday == reviewed.alternateBirthday,
                  fresh.photo == reviewed.photo else { throw ContactExportError.reviewAgain }
            guard let editable = contact.mutableCopy() as? CNMutableContact else { throw ContactExportError.unavailable }
            mutable = editable
            Self.apply(plan.values, to: mutable)
            request.update(mutable)
        }
        try contacts.execute(request)
        guard !mutable.identifier.isEmpty else { throw ContactExportError.unknownResult }
        // The OS supplies the saved record identifier. If read-back is unavailable,
        // retain the create guard rather than assume the record was not written.
        if plan.isNew, (try? existing(mutable.identifier, fields: []).destination.account.id) != plan.account.id {
            throw ContactExportError.unknownResult
        }
        return .linked(identifier: mutable.identifier, container: plan.account.id)
    }

    static func apply(_ fields: ContactExportValues, to contact: CNMutableContact) {
        if !fields.firstName.isEmpty { contact.givenName = fields.firstName }
        if !fields.lastName.isEmpty { contact.familyName = fields.lastName }
        if let date = fields.birthday { contact.birthday = DateComponents(year: date.year, month: date.month, day: date.day) }
        if let photo = fields.photo { contact.imageData = photo }
    }
}
