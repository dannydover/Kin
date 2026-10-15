import SwiftUI

private enum DetailSheet: String, Identifiable {
    case edit, parent, child, partner
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
                    case .parent: AddRelationshipView(store: store, sourceID: personID, kind: .parent)
                    case .child: AddRelationshipView(store: store, sourceID: personID, kind: .child)
                    case .partner: AddRelationshipView(store: store, sourceID: personID, kind: .partner)
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
            Group {
                Section {
                    PersonRow(person: person, today: today)
                    if let grade = AgeRules(calendar: .current).grade(for: person.birthday, on: today) { Text("Approximate school grade: \(grade)") }
                    Text("Gender: \(person.gender.rawValue.capitalized)")
                    Text(person.connections.isEmpty ? "Not in Your people · find in All people" : "Your connection: " + person.connections.map { $0.rawValue.capitalized }.sorted().joined(separator: ", "))
                    if case .exact(let date) = person.birthday { Text("Birthday: \(date.formatted())") }
                    if case .estimated(let age, let reference) = person.birthday {
                        Text("Estimated \(age) as of \(reference.formatted())")
                    }
                }
                if !person.notes.isEmpty { Section("Notes") { Text(person.notes) } }
                if AgeRules(calendar: .current).showsPartnerAndChildSections(for: person.birthday, on: today) {
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
                }
                Section("Parents") {
                    ForEach(store.parentLinks.filter { $0.childID == personID }) { link in
                        relationshipRow(link.parentID, subtitle: "\(link.parentage.rawValue.capitalized) parent") { parentEdit = link }
                    }
                    Button("Add parent") { sheet = .parent }
                }
                Section {
                    Button("Delete person", role: .destructive) { deleting = true }.kinDestructiveText()
                }
            }.listRowBackground(KinTheme.editableFormRow)
        }.kinForm().navigationTitle(person.displayName).navigationBarTitleDisplayMode(.inline)
            .alert("Delete \(person.displayName)?", isPresented: $deleting) {
                Button("Delete person", role: .destructive) {
                    do { try store.deletePerson(personID); dismiss() } catch { self.error = UserFacingError.message(error) }
                }.kinDestructiveText().accessibilityIdentifier("confirm-delete-person")
                Button("Cancel", role: .cancel) { }
            } message: { Text("Deletes this person’s details, photo, and relationships. Other people won’t be deleted. You can still find them in All people.") }
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
enum AddRelationshipKind {
    case parent, child, partner
    var title: String {
        switch self {
        case .parent: "Add parent"
        case .child: "Add child"
        case .partner: "Add partner"
        }
    }
}
struct AddRelationshipView: View {
    let store: KinStore
    let sourceID: UUID
    let kind: AddRelationshipKind
    @State private var query = ""
    @State private var parentage: Parentage = .unspecified
    @State private var status: PartnerStatus = .current
    @Environment(\.dismiss) private var dismiss
    private var relationship: NewRelationship {
        switch kind {
        case .parent: .parent(of: sourceID, parentage: parentage)
        case .child: .child(of: sourceID, parentage: parentage)
        case .partner: .partner(of: sourceID, status: status)
        }
    }
    var body: some View {
        List {
            Group {
                Section { relationshipPickers(child: kind != .partner, parentage: $parentage, status: $status) }
                Section {
                    NavigationLink("Create new person") { PersonEditor(store: store, relationship: relationship, onSaved: { dismiss() }) }
                } footer: { Text("New people added here don’t appear in Your people until you choose Friend, Family, or Colleague on their profile.") }
                Section("Link an existing person") {
                    ForEach(PeopleIndex.results(store.people, query: query, includeUnlisted: true).filter { $0.id != sourceID }) { person in
                        NavigationLink {
                            if kind != .partner {
                                RelationshipEditor(store: store, parent: ParentLink(parentID: kind == .parent ? person.id : sourceID, childID: kind == .parent ? sourceID : person.id, parentage: parentage), isNew: true, onSaved: { dismiss() })
                            } else {
                                RelationshipEditor(store: store, partner: PartnerLink(firstID: sourceID, secondID: person.id, status: status), isNew: true, onSaved: { dismiss() })
                            }
                        } label: { Text(person.displayName).frame(minHeight: 44) }
                    }
                }
            }.listRowBackground(KinTheme.editableFormRow)
        }.kinForm().navigationTitle(kind.title).searchable(text: $query, prompt: "Find an existing person")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .notebookAvailability(store)
    }
}

struct RelationshipEditor: View {
    let store: KinStore
    @State private var parent: ParentLink?
    @State private var partner: PartnerLink?
    private let isNew: Bool
    private let onSaved: (() -> Void)?
    @State private var parentage: Parentage
    @State private var status: PartnerStatus
    @State private var removing = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    init(store: KinStore, parent: ParentLink? = nil, partner: PartnerLink? = nil, isNew: Bool = false, onSaved: (() -> Void)? = nil) {
        self.store = store; self.isNew = isNew; self.onSaved = onSaved
        _parent = State(initialValue: parent); _partner = State(initialValue: partner)
        _parentage = State(initialValue: parent?.parentage ?? .unspecified)
        _status = State(initialValue: partner?.status ?? .unknown)
    }
    var body: some View {
        Form {
            Group {
                if isNew {
                    let ids = parent.map { [$0.parentID, $0.childID] } ?? partner.map { [$0.firstID, $0.secondID] } ?? []
                    ForEach(ids, id: \.self) { id in
                        if let person = store.people.first(where: { $0.id == id }) { Text(person.displayName) }
                    }
                }
                relationshipPickers(child: parent != nil, parentage: $parentage, status: $status)
                if isNew {
                    Text("Save to add this relationship.").font(.footnote)
                } else {
                    Button("Remove relationship", role: .destructive) { removing = true }.kinDestructiveText()
                    Text("Removes only this relationship. Both people and their details stay.").font(.footnote)
                }
            }.listRowBackground(KinTheme.editableFormRow)
        }.kinForm().navigationTitle(isNew ? "Add relationship" : "Edit relationship")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
            .alert("Remove relationship?", isPresented: $removing) {
                Button("Remove relationship", role: .destructive) {
                    do {
                        if let parent { try store.unlinkParent(parent.id) }
                        if let partner { try store.unlinkPartner(partner.id) }
                        dismiss()
                    } catch { self.error = UserFacingError.message(error) }
                }.kinDestructiveText().accessibilityIdentifier("confirm-unlink")
                Button("Cancel", role: .cancel) { }
            } message: { Text("Both people remain available in All people.") }
            .kinError($error).notebookAvailability(store)
    }
    private func save() {
        do {
            if var parent {
                guard isNew || store.parentLinks.contains(parent) else { throw KinError.staleEdit }
                parent.parentage = parentage; try store.saveParentLink(parent)
            }
            if var partner {
                guard isNew || store.partnerLinks.contains(partner) else { throw KinError.staleEdit }
                partner.status = status; try store.savePartnerLink(partner)
            }
            if let onSaved { onSaved() } else { dismiss() }
        } catch { self.error = UserFacingError.message(error) }
    }
}
@ViewBuilder private func relationshipPickers(child: Bool, parentage: Binding<Parentage>, status: Binding<PartnerStatus>) -> some View {
    if child {
        Picker("Parent relationship", selection: parentage) { ForEach(Parentage.allCases) { Text($0.rawValue.capitalized).tag($0) } }
    } else {
        Picker("Partner status", selection: status) { ForEach(PartnerStatus.allCases) { Text($0.rawValue.capitalized).tag($0) } }
    }
}
