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
    @State private var petSheet: PetEditorRoute?
    @State private var deleting = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
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
        .sheet(item: $petSheet) { route in
            NavigationStack { PetEditor(store: store, personID: personID, original: route.pet) }
        }
        .kinError($error).notebookAvailability(store)
    }
    private func profile(_ person: Person) -> some View {
        List {
            Group {
                Section {
                    profileSummary(person)
                }
                if let allergies = person.recordedAllergies {
                    Section {
                        allergyHighlight(allergies)
                    } header: { KinSectionHeading(text: "Allergies") }
                }
                if AgeRules(calendar: .current).showsPartnerAndChildSections(for: person.birthday, on: today) {
                    Section {
                        ForEach(store.partnerLinks.filter { $0.firstID == personID || $0.secondID == personID }) { link in
                            relationshipRow(link.other(than: personID), subtitle: "\(link.status.rawValue.capitalized) partner") { partnerEdit = link }
                        }
                        RelationshipProfileAction(title: "Add partner", systemImage: "plus") { sheet = .partner }
                    } header: { KinSectionHeading(text: "Partners") }
                    Section {
                        ForEach(store.parentLinks.filter { $0.parentID == personID }) { link in
                            relationshipRow(link.childID, subtitle: "\(link.parentage.rawValue.capitalized) parentage", child: true) { parentEdit = link }
                        }
                        RelationshipProfileAction(title: "Add child", systemImage: "plus") { sheet = .child }
                    } header: { KinSectionHeading(text: "Children") }
                }
                Section {
                    ForEach(store.parentLinks.filter { $0.childID == personID }) { link in
                        relationshipRow(link.parentID, subtitle: "\(link.parentage.rawValue.capitalized) parent") { parentEdit = link }
                    }
                    RelationshipProfileAction(title: "Add parent", systemImage: "plus") { sheet = .parent }
                } header: { KinSectionHeading(text: "Parents") }
                PetProfileSection(pets: person.pets) { petSheet = $0 }
                if !person.notes.isEmpty {
                    Section { Text(person.notes) } header: { KinSectionHeading(text: "Notes") }
                }
                Section {
                    Button("Delete person", role: .destructive) { deleting = true }.kinDestructiveText()
                }
            }.listRowBackground(KinTheme.editableFormRow)
        }.listStyle(.insetGrouped).kinForm().navigationTitle(person.displayName).navigationBarTitleDisplayMode(.inline)
            .alert("Delete \(person.displayName)?", isPresented: $deleting) {
                Button("Delete person", role: .destructive) {
                    do { try store.deletePerson(personID); dismiss() } catch { self.error = UserFacingError.message(error) }
                }.kinDestructiveText().accessibilityIdentifier("confirm-delete-person")
                Button("Cancel", role: .cancel) { }
            } message: { Text("Deletes this person’s details, photo, pet records, and relationships. Other people won’t be deleted. Find them on the \(FeatureReference.allPeople) screen.") }
    }
    private func profileSummary(_ person: Person) -> some View {
        let rules = AgeRules(calendar: .current)
        let connections = person.connections.map { $0.rawValue.capitalized }.sorted()
        return VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .center, spacing: 12) {
                PersonAvatar(person: person, today: today)
                VStack(alignment: .leading, spacing: 3) {
                    KinTitle(text: person.displayName, size: 22)
                    Text(([rules.displayAge(for: person.birthday, on: today)] + connections).joined(separator: " · "))
                        .font(.subheadline).foregroundStyle(KinTheme.secondary)
                }
            }
            Rectangle().fill(KinTheme.divider).frame(height: 1).accessibilityHidden(true)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 20) {
                    profileGender(person).fixedSize()
                    profileVisibility(person).fixedSize()
                }
                VStack(alignment: .leading, spacing: 10) {
                    profileGender(person)
                    profileVisibility(person)
                }
            }
            if case .exact(let date) = person.birthday { profileFact("Birthday", value: Text(verbatim: date.formatted())) }
            if case .estimated(let age, let reference) = person.birthday {
                profileFact("Age estimate", value: Text(verbatim: "Estimated \(age) as of \(reference.formatted())"))
            }
            if let grade = rules.grade(for: person.birthday, on: today) {
                profileFact("School grade", value: SchoolGradeLabel(grade: grade))
            }
        }.padding(.vertical, 10)
    }
    private func profileGender(_ person: Person) -> some View {
        profileFact("Gender", value: Text(verbatim: person.gender.title))
    }
    private func profileVisibility(_ person: Person) -> some View {
        profileFact("Index visibility", value: person.isListed ? Text("On main list") :
                    Text("Not on main list · available on the \(FeatureReference.allPeople) screen"))
    }
    private func profileFact(_ label: String, value: some View) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(KinTheme.secondary)
            value.font(.subheadline)
        }.accessibilityElement(children: .contain)
    }
    private func allergyHighlight(_ value: String, labelInline: Bool = false) -> some View {
        Group {
            if labelInline { Text("Allergies: ").bold() + Text(verbatim: value) }
            else { Text(verbatim: value) }
        }
        .font(.subheadline).foregroundStyle(KinTheme.text)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func relationshipRow(_ id: UUID, subtitle: String, child: Bool = false, edit: @escaping () -> Void) -> some View {
        if let person = store.people.first(where: { $0.id == id }) {
            (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) :
                AnyLayout(HStackLayout(spacing: 8))) {
                NavigationLink(value: id) {
                    (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 7)) :
                        AnyLayout(HStackLayout(spacing: 10))) {
                        PersonAvatar(person: person, today: today, size: child ? 32 : 38, childCircle: child)
                            .frame(width: 38)
                        VStack(alignment: .leading, spacing: 2) {
                            KinTitle(text: person.displayName, size: 14)
                            Text(AgeRules(calendar: .current).displayAge(for: person.birthday, on: today))
                                .font(child ? .subheadline.weight(.semibold) : .caption)
                                .foregroundStyle(child ? KinTheme.text : KinTheme.secondary)
                            Text(subtitle).font(.caption).foregroundStyle(KinTheme.secondary)
                            if child, let allergies = person.recordedAllergies {
                                allergyHighlight(allergies, labelInline: true)
                            }
                        }
                    }.frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
                RelationshipEditAction(personName: person.displayName, action: edit)
            }.padding(.vertical, 3)
        }
    }
}
/// Profile actions share native tint, inset spacing and a restrained background.
struct RelationshipProfileAction: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            (Text(Image(systemName: systemImage)) + Text("  " + title))
                .lineLimit(nil).fixedSize(horizontal: false, vertical: true)
        }.accessibilityLabel(title)
            .buttonStyle(.bordered).buttonBorderShape(.roundedRectangle(radius: 10))
            .controlSize(.large)
            .tint(KinTheme.accent.opacity(0.25)).foregroundStyle(KinTheme.accent)
    }
}
struct RelationshipEditAction: View {
    let personName: String
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                RelationshipProfileAction(title: "Edit relationship", systemImage: "pencil", action: action)
            } else {
                Button(action: action) {
                    Image(systemName: "pencil").font(.body.weight(.medium))
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .foregroundStyle(KinTheme.accent)
            }
        }
        .accessibilityLabel("Edit relationship with \(personName)")
        .accessibilityHint("Opens relationship details.")
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
    @State private var parentage: Parentage = .unspecified
    @State private var status: PartnerStatus = .current
    @Environment(\.dismiss) private var dismiss
    @State private var otherParentID: UUID?

    init(store: KinStore, sourceID: UUID, kind: AddRelationshipKind) {
        self.store = store
        self.sourceID = sourceID
        self.kind = kind
        let partners = ExistingPersonChoices.currentPartners(of: sourceID, in: store.partnerLinks)
        _otherParentID = State(initialValue: partners.count == 1 ? partners.first : nil)
    }

    private var relationship: NewRelationship {
        switch kind {
        case .parent: .parent(of: sourceID, parentage: parentage)
        case .child: .child(of: sourceID, parentage: parentage, otherParentID: otherParentID)
        case .partner: .partner(of: sourceID, status: status)
        }
    }
    var body: some View {
        List {
            Group {
                if kind == .child {
                    Section {
                        Picker("Other parent", selection: $otherParentID) {
                            Text("No other parent").tag(nil as UUID?)
                            ForEach(ExistingPersonChoices.results(store.people, sourceID: sourceID, query: "")) { person in
                                Text(reviewName(person, in: store.people)).tag(Optional(person.id))
                            }
                        }.pickerStyle(.navigationLink)
                    } footer: {
                        Text("Choose another parent to link when you save. A new other-parent link has unspecified parentage.")
                    }
                }
                Section {
                    NavigationLink("Create new person") { PersonEditor(store: store, relationship: relationship, onSaved: { dismiss() }) }
                } footer: { FeatureHelp.newLinkedPerson.accessibilityIdentifier("linked-person-guidance") }
                Section {
                    NavigationLink("Link an existing person") {
                        ExistingPersonPicker(store: store,sourceID: sourceID,relationship: relationship,onSaved: { dismiss() })
                    }
                } footer: { Text("Choose someone already in your notebook. Nothing is linked until you save.") }
                Section { relationshipPickers(child: kind != .partner, parentage: $parentage, status: $status) }
            }.listRowBackground(KinTheme.editableFormRow)
        }.kinForm().navigationTitle(kind.title)
            .toolbar { SheetEditActions(cancel: { dismiss() }) }
            .notebookAvailability(store)
    }
}

private func reviewName(_ person: Person, in people: [Person]) -> String {
    ExistingPersonChoices.needsReference(for: person, in: people)
        ? "\(person.displayName) · Notebook reference \(person.reference)" : person.displayName
}

private func parentReviewRole(_ role: String, parentage: Parentage) -> String {
    parentage == .unspecified ? role : "\(role) (\(parentage.rawValue))"
}

struct ChildParentsReview: View {
    let relationship: NewRelationship?
    let people: [Person]

    var body: some View {
        if case .child(let sourceID, let parentage, let otherID) = relationship {
            Section("Parents") {
                LabeledContent(parentReviewRole("Parent", parentage: parentage), value: name(sourceID))
                    .accessibilityIdentifier("review-parent")
                LabeledContent("Other parent", value: otherID.map(name) ?? "None")
                    .accessibilityIdentifier("review-other-parent")
            }
        }
    }

    private func name(_ id: UUID) -> String {
        people.first(where: { $0.id == id }).map { reviewName($0, in: people) } ?? "Person unavailable"
    }
}

/// The source screen retains its optional details while this chooser owns search
/// and navigation only. Selecting never writes a person or relationship.
struct ExistingPersonPicker: View {
    let store: KinStore
    let sourceID: UUID
    let relationship: NewRelationship
    let onSaved: () -> Void
    @State private var query = ""
    @State private var searching = false
    @State private var selectedID: UUID?
    private var choices: [Person] {
        if case .child = relationship {
            return ExistingPersonChoices.children(store.people, sourceID: sourceID, query: query,
                                                  partners: store.partnerLinks, parents: store.parentLinks)
        }
        return ExistingPersonChoices.results(store.people, sourceID: sourceID, query: query)
    }
    var body: some View {
        List {
            if choices.isEmpty {
                ContentUnavailableView(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No other people yet" : "No matches",
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "Go back to create a new person." : "Try another name. Searching doesn’t add anyone or change relationships."))
                    .listRowBackground(KinTheme.background)
            } else {
                ForEach(choices) { person in
                    Button {
                        guard selectedID == nil else { return }
                        searching = false
                        selectedID = person.id
                    } label: {
                        VStack(alignment: .leading,spacing: 5) {
                            Text(person.displayName).foregroundStyle(KinTheme.text)
                            if ExistingPersonChoices.needsReference(for: person,in: choices) {
                                Text("Notebook reference \(person.reference) · " + AgeRules(calendar: .current).displayAge(for: person.birthday,on: Date()))
                                    .font(.caption).foregroundStyle(KinTheme.secondary)
                            }
                        }.fixedSize(horizontal: false,vertical: true)
                            .frame(maxWidth: .infinity,minHeight: 44,alignment: .leading)
                    }.disabled(selectedID != nil)
                        .accessibilityIdentifier("existing-person-" + person.id.uuidString)
                        .listRowBackground(KinTheme.editableFormRow)
                }
            }
        }.kinForm().navigationTitle("Choose a person").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query,isPresented: $searching,placement: .navigationBarDrawer(displayMode: .always),prompt: "Find an existing person")
            .navigationDestination(item: $selectedID) { id in
                switch relationship {
                case .parent(let childID,let parentage):
                    RelationshipEditor(store: store,parent: ParentLink(parentID: id,childID: childID,parentage: parentage),isNew: true,onSaved: onSaved).id(id)
                case .child(let parentID,let parentage,let otherID):
                    RelationshipEditor(store: store,parent: ParentLink(parentID: parentID,childID: id,parentage: parentage),otherParentID: otherID,isNew: true,onSaved: onSaved).id(id)
                case .partner(let otherID,let status):
                    RelationshipEditor(store: store,partner: PartnerLink(firstID: otherID,secondID: id,status: status),isNew: true,onSaved: onSaved).id(id)
                }
            }
            .notebookAvailability(store)
    }
}

struct RelationshipEditor: View {
    let store: KinStore
    @State private var parent: ParentLink?
    @State private var partner: PartnerLink?
    @State private var otherParent: ParentLink?
    private let isNew: Bool
    private let onSaved: (() -> Void)?
    @State private var parentage: Parentage
    @State private var status: PartnerStatus
    @State private var removing = false
    @State private var saved = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    init(store: KinStore, parent: ParentLink? = nil, partner: PartnerLink? = nil, otherParentID: UUID? = nil, isNew: Bool = false, onSaved: (() -> Void)? = nil) {
        self.store = store; self.isNew = isNew; self.onSaved = onSaved
        if let parent, let otherParentID {
            let existing = store.parentLinks.first { $0.parentID == otherParentID && $0.childID == parent.childID }
            _otherParent = State(initialValue: existing ?? ParentLink(parentID: otherParentID, childID: parent.childID))
        }
        _parent = State(initialValue: parent); _partner = State(initialValue: partner)
        _parentage = State(initialValue: parent?.parentage ?? .unspecified)
        _status = State(initialValue: partner?.status ?? .unknown)
    }
    var body: some View {
        Form {
            Group {
                if let parent {
                    personRoleRow(parent.parentID, role: "Parent", identifier: "relationship-parent")
                    if let otherParent {
                        personRoleRow(otherParent.parentID, role: parentReviewRole("Other parent", parentage: otherParent.parentage), identifier: "relationship-other-parent")
                    }
                    personRoleRow(parent.childID, role: "Child", identifier: "relationship-child")
                } else if let partner {
                    personRoleRow(partner.firstID, role: "Partner", identifier: "relationship-partner-first")
                    personRoleRow(partner.secondID, role: "Partner", identifier: "relationship-partner-second")
                }
                relationshipPickers(child: parent != nil, parentage: $parentage, status: $status)
                if isNew {
                    Text("Tap \(FeatureReference.save) to add this relationship.").font(.footnote)
                } else {
                    Button("Remove relationship", role: .destructive) { removing = true }.kinDestructiveText()
                    Text("Removes only this relationship. Both people and their details stay.").font(.footnote)
                }
            }.listRowBackground(KinTheme.editableFormRow)
        }.kinForm().navigationTitle(isNew ? "Add relationship" : "Edit relationship")
            .toolbar {
                SheetEditActions(cancel: { dismiss() }, confirm: { save() }, confirmDisabled: saved)
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
            } message: { Text("Both people remain available on the \(FeatureReference.allPeople) screen.") }
            .kinError($error).notebookAvailability(store)
    }
    @ViewBuilder private func personRoleRow(_ id: UUID, role: String, identifier: String) -> some View {
        if let person = store.people.first(where: { $0.id == id }) {
            VStack(alignment: .leading, spacing: 4) {
                Text(role).font(.caption).foregroundStyle(KinTheme.secondary)
                Text(person.displayName).fixedSize(horizontal: false, vertical: true)
                if ExistingPersonChoices.needsReference(for: person,in: store.people) {
                    Text("Notebook reference \(person.reference)").font(.caption).foregroundStyle(KinTheme.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(role): \(person.displayName)" + (ExistingPersonChoices.needsReference(for: person,in: store.people) ? ", Notebook reference \(person.reference)" : ""))
            .accessibilityIdentifier(identifier)
        }
    }
    private func save() {
        guard !saved else { return }
        do {
            if var parent {
                guard isNew || store.parentLinks.contains(parent) else { throw KinError.staleEdit }
                parent.parentage = parentage
                if isNew { try store.addChild(parent, other: otherParent) }
                else { try store.saveParentLink(parent) }
            }
            if var partner {
                guard isNew || store.partnerLinks.contains(partner) else { throw KinError.staleEdit }
                partner.status = status; try store.savePartnerLink(partner)
            }
            saved = true
            if let onSaved { onSaved() } else { dismiss() }
        } catch { self.error = UserFacingError.message(error) }
    }
}
@ViewBuilder private func relationshipPickers(child: Bool, parentage: Binding<Parentage>, status: Binding<PartnerStatus>) -> some View {
    if child {
        DisclosureGroup {
            Picker("Parent relationship", selection: parentage) { ForEach(Parentage.allCases) { Text($0.rawValue.capitalized).tag($0) } }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Relationship details (optional)")
                Text(parentage.wrappedValue.rawValue.capitalized).font(.subheadline).foregroundStyle(KinTheme.secondary)
            }.accessibilityElement(children: .combine)
        }.accessibilityIdentifier("relationship-details")
    } else {
        Picker("Partner status", selection: status) { ForEach(PartnerStatus.allCases) { Text($0.rawValue.capitalized).tag($0) } }
    }
}
