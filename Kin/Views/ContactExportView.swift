import SwiftUI

struct ContactExportView: View {
    let store: KinStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var selected = Set<UUID>()
    @State private var pending: [UUID] = []
    @State private var results: [ResultRow] = []
    @State private var reviewing = false
    @State private var requesting = false
    @State private var access = false
    @State private var wasDenied = false
    @State private var error: String?
    private let contacts = ContactExportStore()

    struct ResultRow: Identifiable {
        let id: UUID
        let name: String
        let result: String
    }

    var body: some View {
        Form {
            if !reviewing { selection }
            else if let id = pending.first, let person = store.people.first(where: { $0.id == id }) {
                if access {
                    ContactExportPersonReview(person: person, store: store, contacts: contacts) { result in
                        finish(person: person, result: result)
                    }.id(id)
                } else {
                    Section {
                        Text("Kin needs Contacts access to identify the destination account and save only the changes you approve.")
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                        Button("Skip this person") { finish(person: person, result: "Skipped") }
                    } header: { KinSectionHeading(text: "Contacts access unavailable") }
                }
            } else if let id = pending.first {
                Section {
                    Text("This person is no longer in your notebook.")
                    Button("Continue") {
                        pending.removeFirst()
                        results.append(.init(id: id, name: "Removed person", result: "Skipped"))
                    }
                }
            } else {
                Section {
                    ForEach(results) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: row.name)
                            Text(verbatim: row.result).foregroundStyle(KinTheme.secondary)
                        }.accessibilityElement(children: .combine)
                    }
                } header: { KinSectionHeading(text: "Export results") }
            }
        }
        .kinForm()
        .navigationTitle("Export to Contacts").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if reviewing && pending.isEmpty {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            } else { SheetEditActions(cancel: { dismiss() }) }
        }
        .notebookAvailability(store)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { access = contacts.hasAccess }
        }
        .kinError($error)
    }

    private var selection: some View {
        Group {
            Section {
                Text("Choose the people you want to send to Apple Contacts. You’ll review the fields and account for each person before anything is saved.")
                Text("Contacts may sync to the destination account’s service and other devices. Kin doesn’t export notes, allergies, pets, relationships, or estimated ages.")
                    .foregroundStyle(KinTheme.secondary)
            }
            Section {
                ForEach(PeopleIndex.results(store.people, query: "", includeUnlisted: true)) { person in
                    Toggle(isOn: Binding(get: { selected.contains(person.id) }, set: {
                        if $0 { selected.insert(person.id) } else { selected.remove(person.id) }
                    })) { Text(verbatim: person.displayName) }
                }
            } header: { KinSectionHeading(text: "People to export") }
            Section {
                if wasDenied && !access {
                    Text("Allow Kin to access Contacts in Settings, then try again.")
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
                Button("Review selected people") {
                    requesting = true
                    Task { @MainActor in
                        defer { requesting = false }
                        do { access = try await contacts.requestAccess() }
                        catch { access = contacts.hasAccess }
                        guard access else { wasDenied = true; return }
                        pending = PeopleIndex.results(store.people, query: "", includeUnlisted: true)
                            .map(\.id).filter { selected.contains($0) }
                        reviewing = !pending.isEmpty
                    }
                }.disabled(requesting || selected.isEmpty)
            }
        }
    }

    private func finish(person: Person, result: String) {
        guard pending.first == person.id else { return }
        pending.removeFirst()
        results.append(.init(id: person.id, name: person.displayName, result: result))
    }
}

private struct ContactExportPersonReview: View {
    let person: Person
    let store: KinStore
    let contacts: ContactExportStore
    let onFinish: (String) -> Void
    @State private var fields: Set<ContactExportField> = [.firstName, .lastName]
    @State private var nameQuery = ""
    @State private var matches: [ContactExportDestination] = []
    @State private var searched = false
    @State private var plan: ContactExportPlan?
    @State private var error: String?
    @State private var busy = false
    @State private var result: String?
    private var values: ContactExportValues { .init(person: person, today: Date()) }
    private var selected: Set<ContactExportField> { fields.intersection(values.available) }

    var body: some View {
        if let result {
            Section {
                Text(verbatim: result)
                Button("Continue") { onFinish(result) }
            } header: { KinSectionHeading(text: person.displayName) }
        } else if let plan {
            preview(plan)
        } else {
            selection
        }
    }

    private var selection: some View {
        Group {
            Section {
                if values.available.isEmpty {
                    Text("There are no supported fields to export for this person.")
                }
                ForEach(ContactExportField.allCases.filter { values.available.contains($0) }) { field in
                    Toggle(field.title, isOn: Binding(get: { fields.contains(field) }, set: {
                        if $0 { fields.insert(field) } else { fields.remove(field) }
                    }))
                }
                if values.birthday == nil { Text("Birthday omitted: Kin only exports a known, exact birthday.").foregroundStyle(KinTheme.secondary) }
                if values.photo == nil { Text("No eligible photo to export.").foregroundStyle(KinTheme.secondary) }
            } header: { KinSectionHeading(text: person.displayName) }

            Section {
                if person.contactExportLink == nil {
                    Button("Review a new contact") { prepareNew() }
                        .disabled(selected.isEmpty || selected.isDisjoint(with: [.firstName, .lastName]))
                    if selected.isDisjoint(with: [.firstName, .lastName]) {
                        Text("Include a first or last name to create a contact.").foregroundStyle(KinTheme.secondary)
                    }
                } else if case .linked(let id, let container) = person.contactExportLink {
                    Button("Review the linked contact") { prepareExisting(id, expectedAccount: container) }
                        .disabled(selected.isEmpty)
                    Text("Kin won’t create a second contact for this person. If the linked contact changed or is unavailable, find and confirm an existing contact below.")
                        .foregroundStyle(KinTheme.secondary)
                } else {
                    Text("A previous save couldn’t be verified. Check Contacts, then find and confirm the existing contact below. Kin won’t create another copy.")
                        .foregroundStyle(KinTheme.secondary)
                }
            } header: { KinSectionHeading(text: "Choose where to save") }

            Section {
                Text("Choose the exact contact to update. Kin never matches people by name alone.")
                if contacts.isLimited {
                    Text("Only contacts shared with Kin are searchable. To see more, change Contacts access for Kin in Settings.")
                        .foregroundStyle(KinTheme.secondary)
                }
                TextField("Contact name", text: $nameQuery)
                    .onChange(of: nameQuery) { matches = []; searched = false }
                    .submitLabel(.search)
                    .onSubmit { search() }
                Button("Find existing contacts") { search() }
                    .disabled(selected.isEmpty || nameQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if searched && matches.isEmpty { Text("No accessible contacts match that search.") }
                ForEach(matches) { match in
                    let ambiguous = matches.filter { $0.distinguishingLabel == match.distinguishingLabel }.count > 1
                    Button {
                        prepareExisting(match.id, expectedAccount: match.account.id,
                                        expectedIdentity: match.distinguishingLabel)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: match.name)
                            Text(verbatim: match.account.title).foregroundStyle(KinTheme.secondary)
                            if !match.hints.isEmpty { Text(verbatim: match.hints).foregroundStyle(KinTheme.secondary) }
                            if ambiguous { Text("Can’t distinguish this from another match.").foregroundStyle(KinTheme.secondary) }
                        }.fixedSize(horizontal: false, vertical: true)
                    }.disabled(ambiguous || selected.isEmpty)
                }
            } header: { KinSectionHeading(text: "Update an existing contact") }
            Section { Button("Skip this person") { onFinish("Skipped") } }
        }.kinError($error)
    }

    private func preview(_ plan: ContactExportPlan) -> some View {
        Group {
            Section {
                if case .update(let current) = plan.target {
                    Text(verbatim: current.destination.name)
                    if !current.destination.hints.isEmpty { Text(verbatim: current.destination.hints) }
                    Text("Confirm this is the person you mean. Saving replaces only the fields shown below.")
                }
                Text("Account: \(plan.account.title)")
                Text("Contacts may sync these fields to this account’s service and other devices.")
                    .foregroundStyle(KinTheme.secondary)
            } header: { KinSectionHeading(text: plan.isNew ? "Review new contact" : "Review contact update") }
            Section {
                ForEach(ContactExportField.allCases.filter { plan.fields.contains($0) }) { field in
                    fieldPreview(field, plan: plan)
                }
            } header: { KinSectionHeading(text: "Fields to save") }
            Section {
                Button(plan.isNew ? "Confirm and create contact" : "Confirm and update contact") { save(plan) }
                    .disabled(busy)
                Button("Back to fields") { self.plan = nil }.disabled(busy)
                Button("Skip this person") { onFinish("Skipped") }.disabled(busy)
            }
        }.kinError($error)
    }

    private func fieldPreview(_ field: ContactExportField, plan: ContactExportPlan) -> some View {
        let old: ContactExportCurrent? = if case .update(let existing) = plan.target { existing } else { nil }
        return VStack(alignment: .leading, spacing: 8) {
            Text(field.title).font(.headline)
            if let old {
                if field == .photo {
                    if old.photo != plan.values.photo { photo(old.photo, title: "Current photo") }
                } else {
                    let before = oldText(field, old: old)
                    let after = newText(field, values: plan.values)
                    Text(before == after ? "Already matches" : "Current: \(before)")
                        .foregroundStyle(KinTheme.secondary)
                    if field == .birthday && old.alternateBirthday != nil {
                        Text("The existing non-Gregorian birthday will be kept.")
                            .foregroundStyle(KinTheme.secondary)
                    }
                }
            }
            if field == .photo {
                photo(plan.values.photo, title: old == nil ? "Photo to export" : "Selected photo")
            } else { Text("Selected: \(newText(field, values: plan.values))") }
        }.fixedSize(horizontal: false, vertical: true)
    }

    private func photo(_ data: Data?, title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: 160, maxHeight: 160)
                    .accessibilityHidden(true)
            } else { Text(data == nil ? "No photo" : "Photo preview unavailable") }
        }
    }

    private func newText(_ field: ContactExportField, values: ContactExportValues) -> String {
        switch field {
        case .firstName: values.firstName
        case .lastName: values.lastName
        case .birthday: values.birthday?.formatted() ?? "Not saved"
        case .photo: ""
        }
    }

    private func oldText(_ field: ContactExportField, old: ContactExportCurrent) -> String {
        switch field {
        case .firstName: return old.destination.firstName.isEmpty ? "Not saved" : old.destination.firstName
        case .lastName: return old.destination.lastName.isEmpty ? "Not saved" : old.destination.lastName
        case .birthday:
            guard let date = old.birthday, let month = date.month, let day = date.day else { return "Not saved" }
            if let year = date.year {
                let civil = CivilDate(year: year, month: month, day: day)
                if civil.isValid { return civil.formatted() }
            }
            return "Month \(month), day \(day) (no recorded year)"
        case .photo: return ""
        }
    }

    private func prepareNew() {
        do { plan = makePlan(.create(try contacts.defaultAccount())) }
        catch { self.error = error.localizedDescription }
    }

    private func prepareExisting(_ id: String, expectedAccount: String, expectedIdentity: String? = nil) {
        do {
            let current = try contacts.existing(id, fields: selected)
            guard current.destination.account.id == expectedAccount,
                  expectedIdentity == nil || current.destination.distinguishingLabel == expectedIdentity
            else { throw ContactExportError.reviewAgain }
            if store.people.contains(where: { $0.id != person.id && $0.contactExportLink == current.destination.link }) {
                throw ContactExportError.alreadyLinked
            }
            plan = makePlan(.update(current))
        } catch { self.error = error.localizedDescription }
    }

    private func makePlan(_ target: ContactExportPlan.Target) -> ContactExportPlan {
        .init(personID: person.id, expectedLink: person.contactExportLink, target: target,
              fields: selected, values: values.selected(selected))
    }

    private func search() {
        guard !selected.isEmpty else { return }
        do { matches = try contacts.find(nameQuery); searched = true }
        catch { self.error = error.localizedDescription }
    }

    private func save(_ plan: ContactExportPlan) {
        guard !busy, result == nil, !plan.fields.isEmpty else { return }
        busy = true
        defer { busy = false }
        var externalWriteStarted = false
        var saved = false
        do {
            let live = try store.person(plan.personID)
            guard live.contactExportLink == plan.expectedLink,
                  ContactExportValues(person: live, today: Date()).selected(plan.fields) == plan.values
            else { throw ContactExportError.reviewAgain }

            let expected: ContactExportLink?
            if plan.isNew {
                guard plan.expectedLink == nil, try contacts.defaultAccount() == plan.account else {
                    throw ContactExportError.reviewAgain
                }
                try store.recordContactExport(.pendingCreation, for: plan.personID, replacing: nil)
                expected = .pendingCreation
            } else {
                if case .update(let existing) = plan.target,
                   store.people.contains(where: { $0.id != plan.personID && $0.contactExportLink == existing.destination.link }) {
                    throw ContactExportError.alreadyLinked
                }
                expected = plan.expectedLink
            }
            _ = try store.person(plan.personID)
            externalWriteStarted = true
            let link = try contacts.save(plan)
            saved = true
            try store.recordContactExport(link, for: plan.personID, replacing: expected)
            result = plan.isNew ? "Created in Contacts" : "Updated in Contacts"
        } catch {
            if saved {
                result = "Saved in Contacts, but Kin couldn’t retain the link. Check Contacts before exporting again."
            } else if externalWriteStarted && plan.isNew {
                result = ContactExportError.unknownResult.localizedDescription
            } else {
                self.plan = nil
                self.error = (error as? ContactExportError)?.localizedDescription
                    ?? (error as? KinError)?.localizedDescription
                    ?? "Kin couldn’t finish saving this contact. Check the account and Contacts access, then review again."
            }
        }
    }
}
