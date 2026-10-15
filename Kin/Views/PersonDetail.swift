import SwiftUI

private enum DetailSheet: String, Identifiable {
    case edit, child, partner
    var id: String { rawValue }
}
struct PersonDetail: View {
    let store: KinStore
    let personID: UUID
    let today: Date
    @State private var sheet: DetailSheet?
    @State private var parentEdit: ParentLink?
    @State private var partnerEdit: PartnerLink?
    @State private var deleting = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Group {
            if let person = store.people.first(where: { $0.id == personID }) {
                profile(person)
            } else { ContentUnavailableView("Person unavailable", systemImage: "person.crop.circle.badge.questionmark") }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { sheet = .edit }.accessibilityIdentifier("edit-person-" + personID.uuidString)
            }
        }
        .sheet(item: $sheet) { route in
            NavigationStack {
                if let person = store.people.first(where: { $0.id == personID }) {
                    switch route {
                    case .edit: PersonEditor(store: store, person: person)
                    case .child: AddRelationshipView(store: store, sourceID: personID, child: true)
                    case .partner: AddRelationshipView(store: store, sourceID: personID, child: false)
                    }
                }
            }
        }
        .sheet(item: $parentEdit) { link in NavigationStack { RelationshipEditor(store: store, parent: link) } }
        .sheet(item: $partnerEdit) { link in NavigationStack { RelationshipEditor(store: store, partner: link) } }
        .kinError($error).notebookAvailability(store)
    }
    private func profile(_ person: Person) -> some View {
        List {
            Section {
                PersonRow(person: person, today: today)
                if let grade = AgeRules(calendar: .current).grade(for: person.birthday, on: today) { Text("Approximate school grade: \(grade)") }
                Text("Gender: \(person.gender.rawValue.capitalized)")
                Text(person.connections.isEmpty ? "Unlisted · available in All people" : "Your connection: " + person.connections.map { $0.rawValue.capitalized }.sorted().joined(separator: ", "))
                if case .exact(let date) = person.birthday { Text("Birthday: \(date.formatted())") }
                if case .estimated(let age, let reference) = person.birthday {
                    Text("Estimated \(age) as of \(reference.formatted())")
                }
            }
            if !person.notes.isEmpty { Section("Notes") { Text(person.notes) } }
            Section("Partners") {
                ForEach(store.partnerLinks.filter { $0.firstID == personID || $0.secondID == personID }) { link in
                    relationshipRow(link.other(than: personID), subtitle: "\(link.status.rawValue.capitalized) partner") { partnerEdit = link }
                }
                Button("Add partner") { sheet = .partner }
            }
            Section("Children") {
                ForEach(store.parentLinks.filter { $0.parentID == personID }) { link in
                    relationshipRow(link.childID, subtitle: "\(link.parentage.rawValue.capitalized) parentage") { parentEdit = link }
                }
                Button("Add child") { sheet = .child }
            }
            Section("Parents") {
                ForEach(store.parentLinks.filter { $0.childID == personID }) { link in
                    relationshipRow(link.parentID, subtitle: "\(link.parentage.rawValue.capitalized) parent") { parentEdit = link }
                }
            }
            Section {
                Button("Delete person", role: .destructive) { deleting = true }
            }
        }.kinForm().navigationTitle(person.displayName).navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Delete \(person.displayName)?", isPresented: $deleting, titleVisibility: .visible) {
                Button("Delete person", role: .destructive) {
                    do { try store.deletePerson(personID); dismiss() } catch { self.error = error.localizedDescription }
                }.accessibilityIdentifier("confirm-delete-person")
            } message: { Text("Removes this person, their photo, notes, and incident relationships. Other people stay in Kin and remain available in All people.") }
    }
    @ViewBuilder private func relationshipRow(_ id: UUID, subtitle: String, edit: @escaping () -> Void) -> some View {
        if let person = store.people.first(where: { $0.id == id }) {
            VStack(alignment: .leading, spacing: 8) {
                NavigationLink(value: id) { PersonRow(person: person, today: today) }.buttonStyle(.plain)
                Text(subtitle).font(.caption).foregroundStyle(KinTheme.secondary)
                Button("Edit relationship", action: edit).buttonStyle(.borderless).font(.subheadline).frame(minHeight: 44, alignment: .leading).accessibilityLabel("Edit relationship with \(person.displayName)")
            }
        }
    }
}
struct AddRelationshipView: View {
    let store: KinStore
    let sourceID: UUID
    let child: Bool
    @State private var query = ""
    @State private var parentage: Parentage = .unspecified
    @State private var status: PartnerStatus = .unknown
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    private var relationship: NewRelationship { child ? .child(of: sourceID, parentage: parentage) : .partner(of: sourceID, status: status) }
    var body: some View {
        List {
            Section { relationshipPickers(child: child, parentage: $parentage, status: $status) }
            Section {
                NavigationLink("Create new person") { PersonEditor(store: store, relationship: relationship, onSaved: { dismiss() }) }
            } footer: { Text("New child and partner entries start unlisted. Their profile lets you add a connection at any time.") }
            Section("Link an existing person") {
                ForEach(PeopleIndex.results(store.people, query: query, includeUnlisted: true).filter { $0.id != sourceID }) { person in
                    Button { link(person.id) } label: { Text(person.displayName).frame(minHeight: 44) }
                }
            }
        }.kinForm().navigationTitle(child ? "Add child" : "Add partner").searchable(text: $query, prompt: "Find an existing person")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .kinError($error).notebookAvailability(store)
    }
    private func link(_ id: UUID) {
        do {
            if child { try store.saveParentLink(ParentLink(parentID: sourceID, childID: id, parentage: parentage)) }
            else { try store.savePartnerLink(PartnerLink(firstID: sourceID, secondID: id, status: status)) }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
struct RelationshipEditor: View {
    let store: KinStore
    private let parent: ParentLink?
    private let partner: PartnerLink?
    @State private var parentage: Parentage
    @State private var status: PartnerStatus
    @State private var removing = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    init(store: KinStore, parent: ParentLink? = nil, partner: PartnerLink? = nil) {
        self.store = store; self.parent = parent; self.partner = partner
        _parentage = State(initialValue: parent?.parentage ?? .unspecified)
        _status = State(initialValue: partner?.status ?? .unknown)
    }
    var body: some View {
        Form {
            relationshipPickers(child: parent != nil, parentage: $parentage, status: $status)
            Button("Remove relationship", role: .destructive) { removing = true }
            Text("Removing a link preserves both people and their information.").font(.footnote)
        }.kinForm().navigationTitle("Edit relationship")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
            .confirmationDialog("Remove relationship?", isPresented: $removing, titleVisibility: .visible) {
                Button("Remove relationship", role: .destructive) {
                    do {
                        if let parent { try store.unlinkParent(parent.id) }
                        if let partner { try store.unlinkPartner(partner.id) }
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }.accessibilityIdentifier("confirm-unlink")
            } message: { Text("Both people remain available in All people.") }
            .kinError($error).notebookAvailability(store)
    }
    private func save() {
        do {
            if var parent {
                guard store.parentLinks.contains(parent) else { throw KinError.staleEdit }
                parent.parentage = parentage; try store.saveParentLink(parent)
            }
            if var partner {
                guard store.partnerLinks.contains(partner) else { throw KinError.staleEdit }
                partner.status = status; try store.savePartnerLink(partner)
            }
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
@ViewBuilder private func relationshipPickers(child: Bool, parentage: Binding<Parentage>, status: Binding<PartnerStatus>) -> some View {
    if child {
        Picker("Parentage", selection: parentage) { ForEach(Parentage.allCases) { Text($0.rawValue.capitalized).tag($0) } }
    } else {
        Picker("Partner status", selection: status) { ForEach(PartnerStatus.allCases) { Text($0.rawValue.capitalized).tag($0) } }
    }
}
