import SwiftUI
import PhotosUI

struct PersonEditor: View {
    let store: KinStore
    let relationship: NewRelationship?
    let onSaved: (() -> Void)?
    let onPersonSaved: ((UUID) -> Void)?
    private let isNew: Bool
    private let original: Person?
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Person
    @State private var genderDefault: DraftGenderDefault
    @State private var birthKind: String
    @State private var exactDate: Date
    @State private var referenceDate: Date
    @State private var estimatedAge: Int?
    @State private var pickingContact = false
    @State private var savedImport = false
    @State private var didSave = false
    @State private var pendingContact: ContactSnapshot?
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var photoGeneration = UUID()
    @State private var photoLoading = false
    @State private var removalWarning = false
    @State private var error: String?
    init(store: KinStore, person: Person? = nil, relationship: NewRelationship? = nil, onSaved: (() -> Void)? = nil, onPersonSaved: ((UUID) -> Void)? = nil) {
        self.store = store; original = person; isNew = person == nil
        self.relationship = relationship; self.onSaved = onSaved; self.onPersonSaved = onPersonSaved
        let value = person ?? PersonDraftDefaults.newPerson(relationship: relationship, people: store.people)
        _draft = State(initialValue: value)
        _genderDefault = State(initialValue: DraftGenderDefault(value: value.gender, isNew: person == nil))
        let today = CivilDate(Date(), timeZone: .current).pickerDate
        var kind = "unknown", exact = today, reference = today
        var age: Int? = nil
        switch value.birthday {
        case .unknown: break
        case .exact(let date): kind = "exact"; exact = date.pickerDate
        case .estimated(let years, let date): kind = "estimated"; reference = date.pickerDate; age = years
        }
        _birthKind = State(initialValue: kind); _exactDate = State(initialValue: exact)
        _referenceDate = State(initialValue: reference); _estimatedAge = State(initialValue: age)
    }
    private var ageInputValid: Bool { birthKind != "estimated" || estimatedAge != nil }
    private var birthday: Birthday {
        switch birthKind {
        case "exact": .exact(CivilDate(exactDate, timeZone: CivilDate.pickerCalendar.timeZone))
        case "estimated": estimatedAge.map { .estimated(age: $0, referenceDate: CivilDate(referenceDate, timeZone: CivilDate.pickerCalendar.timeZone)) } ?? .unknown
        default: .unknown
        }
    }
    private var showsAllergyEditor: Bool {
        // Keep a previously available field accessible while the age is being corrected.
        let isChild = isChildEntry(relationship) || store.parentLinks.contains { $0.childID == draft.id }
        let today = Date()
        return draft.showsAllergyEditor(isChildInNotebook: isChild, birthday: birthday, on: today)
            || original.map { $0.showsAllergyEditor(isChildInNotebook: isChild, birthday: $0.birthday, on: today) } == true
    }
    private var photoAllowed: Bool { AgeRules(calendar: .current).allowsPhoto(birthday, on: Date()) }
    private var needsRemoval: Bool { ageInputValid && original?.photo != nil && original?.birthday != birthday && !photoAllowed }
    var body: some View {
        Form {
            Group {
                Section {
                    Button("Import from Contacts") { pendingContact = nil; pickingContact = true }
                } footer: { Text("Choose a contact to copy their name and birthday. Kin only imports their photo when we can be sure they’re at least 18.") }
                ChildParentsReview(relationship: relationship, people: store.people)
                nameSection
                ageSection
                photoSection
                connectionSection
                if showsAllergyEditor {
                    ChildAllergyField(allergies: $draft.allergies)
                }
                Section { TextField("The little things to remember", text: $draft.notes, axis: .vertical).lineLimit(4...10) } header: { KinSectionHeading(text: "Notes") }
            }.listRowBackground(KinTheme.editableFormRow)
        }
        .environment(\.calendar, CivilDate.pickerCalendar).environment(\.timeZone, CivilDate.pickerCalendar.timeZone)
        .kinForm().navigationTitle(isNew ? "Add person" : "Edit person").navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(KinTheme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            SheetEditActions(cancel: { dismiss() }, confirm: { save() },
                             confirmDisabled: photoLoading || didSave || !ageInputValid)
        }
        .alert("Remove the existing photo?", isPresented: $removalWarning) {
            Button("Remove photo and save", role: .destructive) { save(confirmed: true) }.kinDestructiveText()
            Button("Cancel", role: .cancel) { }
        } message: { Text("Kin can’t be sure this person is at least 18, so it can’t keep this photo. Remove it to save these changes. To keep the saved photo and age, cancel this edit.") }
        .sheet(isPresented: $pickingContact, onDismiss: {
            pendingContact = nil
            if savedImport { finishSave() }
        }) {
            Group {
                if let snapshot = pendingContact {
                    NavigationStack {
                        ContactBirthInformationView(snapshot: snapshot, currentDraft: draft, currentBirthday: birthday, isNew: isNew, genderDefault: genderDefault, store: store, relationship: relationship, onNewSaved: { savedImport = true; pickingContact = false }) { birth, includePhoto, photo in
                            finishContactImport(snapshot, birthday: birth, importPhoto: includePhoto, preparedPhoto: photo)
                        } onCancel: { pendingContact = nil; pickingContact = false }
                    }
                } else {
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--kin-ui-preservation-contacts") {
                        VStack {
                            ForEach(0..<4) { index in
                                Button("Use synthetic contact \(index)") {
                                    let birth: ContactBirthInformation = index == 1 ? .yearless : index == 3 ? .exact(CivilDate(year: 1995, month: 6, day: 23)) : .missing
                                    pendingContact = ContactSnapshot(firstName: "Kin Synthetic Keep \(index)", lastName: "", birthInformation: birth)
                                }.accessibilityIdentifier("synthetic-preservation-contact-\(index)")
                            }
                        }
                    } else if ProcessInfo.processInfo.arguments.contains("--kin-ui-synthetic-contact-with-photo") {
                        Button("Use synthetic contact with photo") {
                            pendingContact = ContactSnapshot.syntheticMissingBirthdayWithPhoto()
                        }.accessibilityIdentifier("synthetic-contact-with-photo-selection")
                    } else if ProcessInfo.processInfo.arguments.contains("--kin-ui-synthetic-contact") {
                        Button("Use synthetic contact") {
                            pendingContact = ContactSnapshot(firstName: "John", lastName: "Appleseed")
                        }.accessibilityIdentifier("synthetic-contact-selection")
                    } else {
                        ContactPicker { snapshot in
                            pendingContact = snapshot
                        } onCancel: { pickingContact = false }
                    }
                    #else
                    ContactPicker { snapshot in
                        pendingContact = snapshot
                    } onCancel: { pickingContact = false }
                    #endif
                }
            }.interactiveDismissDisabled()
        }
        .onChange(of: pickedPhoto) { _, item in loadPhoto(item) }
        .onChange(of: photoAllowed) { _, allowed in
            if !allowed { photoGeneration = UUID(); pickedPhoto = nil; photoLoading = false }
        }
        .onDisappear { photoGeneration = UUID(); photoLoading = false }
        .kinError($error).notebookAvailability(store)
    }
    private var nameSection: some View {
        Section {
            TextField("First name (optional)", text: Binding(get: { draft.firstName ?? "" }, set: { name in
                draft.firstName = name.isEmpty ? nil : name
                genderDefault.nameChanged(name, lookup: NameAssociations.bundled.gender)
                draft.gender = genderDefault.value
            }), prompt: Text("First name").foregroundStyle(KinTheme.secondary))
                .textContentType(.givenName).accessibilityLabel("First name (optional)")
            TextField("Last name (optional)", text: Binding(get: { draft.lastName ?? "" }, set: { draft.lastName = $0.isEmpty ? nil : $0 }),
                      prompt: Text("Last name").foregroundStyle(KinTheme.secondary))
                .textContentType(.familyName).accessibilityLabel("Last name (optional)")
            GenderChoice(value: draft.gender) { gender in genderDefault.choose(gender); draft.gender = gender }
        } header: { KinSectionHeading(text: "Name") } footer: {
            if isNew { Text("Names and gender are optional. A name-based gender suggestion can always be changed.") }
        }
    }
    private var connectionSection: some View {
        Section {
            if !isNew || relationship != nil {
                Toggle("Show on main list", isOn: $draft.isListed).accessibilityIdentifier("index-inclusion").accessibilityHint("Show this person on the People screen.")
            }
            ForEach(Connection.allCases) { connection in
                Toggle(connection.rawValue.capitalized, isOn: Binding(get: { draft.connections.contains(connection) }, set: { selected in
                    if selected { draft.connections.insert(connection) } else { draft.connections.remove(connection) }
                }))
            }
        } header: { KinSectionHeading(text: "Your connection") } footer: {
            if isNew && relationship == nil { FeatureHelp.directPerson }
            else if isNew { FeatureHelp.newLinkedPerson }
            else { FeatureHelp.listInclusion }
        }
    }
    private var ageSection: some View {
        Section {
            BirthInformationRows(birthKind: $birthKind, exactDate: $exactDate, referenceDate: $referenceDate, estimatedAge: $estimatedAge)
        } header: { KinSectionHeading(text: "Age") }
    }
    private func finishContactImport(_ snapshot: ContactSnapshot, birthday importedBirthday: Birthday? = nil, importPhoto: Bool = true, preparedPhoto: PreparedContactPhoto? = nil) {
        photoGeneration = UUID(); pickedPhoto = nil; photoLoading = false
        draft.birthday = birthday
        ContactImport.apply(snapshot, to: &draft, birthday: importedBirthday, importPhoto: importPhoto, preparedPhoto: preparedPhoto)
        // Clear inactive controls too, so switching modes after importing a
        // different card cannot resurrect the previous person's age or date.
        let today = CivilDate(Date(), timeZone: .current).pickerDate
        estimatedAge = nil; exactDate = today; referenceDate = today
        switch draft.birthday {
        case .unknown: birthKind = "unknown"
        case .exact(let date): birthKind = "exact"; exactDate = date.pickerDate
        case .estimated(let age, let date): birthKind = "estimated"; estimatedAge = age; referenceDate = date.pickerDate
        }
        pendingContact = nil; pickingContact = false
    }
    private var photoSection: some View {
        let title = draft.photo == nil ? "Add photo" : "Change photo"
        return Section {
            if photoAllowed {
                InitialAvatar(first: draft.firstName ?? "?", last: draft.lastName ?? "", photo: draft.photo, gender: draft.gender, size: 64)
                PhotosPicker(selection: $pickedPhoto, matching: .images) { Label(title, systemImage: "photo") }
                if photoLoading { ProgressView("Loading photo") }
                if draft.photo != nil { Button("Remove photo", role: .destructive) { photoGeneration = UUID(); pickedPhoto = nil; photoLoading = false; draft.photo = nil }.kinDestructiveText() }
            } else {
                Text(needsRemoval ? "You’ll need to remove the saved photo before saving this age." : "Photos are only available when we can be sure this person is at least 18. For an estimate, even the youngest possible age must be 18 or older.")
            }
        } header: { KinSectionHeading(text: "Photo") }
    }
    private func loadPhoto(_ item: PhotosPickerItem?) {
        let generation = UUID(); photoGeneration = generation
        guard let item, photoAllowed else { photoLoading = false; return }
        photoLoading = true
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { throw PhotoError.unreadable }
                guard photoGeneration == generation, photoAllowed else { return }
                guard let photo = PhotoProcessor.thumbnail(data) else { throw PhotoError.unreadable }
                guard photoGeneration == generation, photoAllowed else { return }
                draft.photo = photo
            } catch { if photoGeneration == generation { self.error = "The photo couldn’t be loaded. Try another image." } }
            if photoGeneration == generation { photoLoading = false }
        }
    }
    private func save(confirmed: Bool = false) {
        guard !didSave, ageInputValid else { return }
        guard !needsRemoval || confirmed else { removalWarning = true; return }
        var value = draft; value.birthday = birthday
        if confirmed && !photoAllowed { value.photo = nil }
        do {
            try store.savePerson(value, confirmPhotoRemoval: confirmed, relationship: relationship)
            didSave = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            // The linked-create flow owns dismissal of its entire sheet; use
            // one presentation owner instead of dismissing a push and sheet together.
            finishSave()
        } catch { self.error = UserFacingError.message(error) }
    }
    private func finishSave() {
        onPersonSaved?(draft.id)
        if let onSaved { onSaved() } else { dismiss() }
    }
}

/// Shared civil-date controls for the person draft and Contacts import draft.
private struct BirthInformationRows: View {
    @Binding var birthKind: String
    @Binding var exactDate: Date
    @Binding var referenceDate: Date
    @Binding var estimatedAge: Int?
    private enum Sheet: String, Identifiable {
        case estimated, exact
        var id: Self { self }
    }
    @State private var sheet: Sheet?
    @State private var proposedDate = Date()
    var accessibilityPrefix = ""
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        Group {
            birthKindControl
                .accessibilityIdentifier(accessibilityPrefix + "birth-information")
                .sheet(item: $sheet) { route in
                    switch route {
                    case .estimated:
                        EstimatedAgeWheel(age: estimatedAge) { selected in
                            estimatedAge = selected
                            birthKind = "estimated"
                        }
                        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.height(340)])
                        .presentationDragIndicator(.visible)
                    case .exact:
                        NavigationStack {
                            DatePicker("Birthday", selection: $proposedDate,
                                       in: ...CivilDate(Date(), timeZone: .current).pickerDate, displayedComponents: .date)
                                .datePickerStyle(.wheel)
                                .labelsHidden()
                                .accessibilityLabel("Birthday")
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.horizontal)
                                .navigationTitle("Birthday").navigationBarTitleDisplayMode(.inline)
                                .toolbar {
                                    SheetEditActions(cancel: { sheet = nil }, confirmTitle: "Done", confirm: {
                                        exactDate = proposedDate
                                        birthKind = "exact"
                                        sheet = nil
                                    })
                                }
                        }
                    }
                }
            if birthKind == "exact" {
                Button { openDate() } label: {
                    LabeledContent("Birthday", value: CivilDate(exactDate, timeZone: CivilDate.pickerCalendar.timeZone).formatted())
                }.accessibilityIdentifier(accessibilityPrefix + "exact-birthday")
            }
            if birthKind == "estimated" {
                Button { sheet = .estimated } label: {
                    LabeledContent("Age in years", value: estimatedAge.map(String.init) ?? "Choose age")
                }.accessibilityLabel("Age in years")
                    .accessibilityValue(estimatedAge.map(String.init) ?? "Not chosen")
                    .accessibilityHint("Opens a scrollable age picker")
                    .accessibilityIdentifier(accessibilityPrefix + "choose-estimated-age")
                DatePicker("As of", selection: $referenceDate, in: ...CivilDate(Date(), timeZone: .current).pickerDate, displayedComponents: .date)
                Text("Estimated ages are marked with ~. Starting from the age and date you choose, Kin adds a year on the same date each year without guessing a birthday. School grades are a rough guide and may differ from the child’s actual grade.").font(.footnote)
            }
        }
    }

    private func openDate() {
        proposedDate = exactDate
        sheet = .exact
    }

    private var birthKindControl: some View {
        Menu {
            Button("Unknown") { birthKind = "unknown" }
            Button("Exact birthday") { openDate() }
            Button("Estimated age") { sheet = .estimated }
        } label: {
            LabeledContent("Birth information") {
                HStack {
                    Text(birthKindTitle).fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "chevron.up.chevron.down").font(.caption)
                }
            }
        }
        .accessibilityLabel(Text("Birth information, \(Text(birthKindTitle))"))
    }

    private var birthKindTitle: LocalizedStringKey {
        switch birthKind {
        case "exact": "Exact birthday"
        case "estimated": "Estimated age"
        default: "Unknown"
        }
    }
}

private func isChildEntry(_ relationship: NewRelationship?) -> Bool {
    if case .child? = relationship { return true }
    return false
}

private struct ChildAllergyField: View {
    @Binding var allergies: String?
    var body: some View {
        Section {
            TextField("Allergies (optional)", text: Binding(get: { allergies ?? "" }, set: { allergies = $0 }), axis: .vertical)
                .lineLimit(2...5)
                .accessibilityIdentifier("person-allergies-input")
            if let allergies, !allergies.isEmpty {
                Button("Clear allergies") { self.allergies = nil }
                    .accessibilityIdentifier("clear-person-allergies")
            }
        } header: {
            KinSectionHeading(text: "Allergies")
        } footer: {
            Text("A blank field means no allergy information was entered.")
        }
    }
}

private struct EstimatedAgeWheel: View {
    @State private var selection: Int
    let onDone: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    init(age: Int?, onDone: @escaping (Int) -> Void) {
        _selection = State(initialValue: age.flatMap { AgeRules.estimatedAgeRange.contains($0) ? $0 : nil } ?? 0)
        self.onDone = onDone
    }
    var body: some View {
        NavigationStack {
            Picker("Age in years", selection: $selection) {
                ForEach(AgeRules.estimatedAgeRange, id: \.self) { age in Text(String(age)).tag(age) }
            }.pickerStyle(.wheel).accessibilityLabel("Age in years")
                .accessibilityIdentifier("estimated-age-wheel")
                .padding(.horizontal).frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(KinTheme.background)
                .navigationTitle("Age in years").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    SheetEditActions(cancel: { dismiss() }, confirmTitle: "Done", confirm: {
                        onDone(selection)
                        dismiss()
                    })
                }
        }.tint(KinTheme.accent).preferredColorScheme(.dark)
    }
}

private struct ContactBirthInformationView: View {
    let snapshot: ContactSnapshot
    let currentDraft: Person
    let currentBirthday: Birthday
    let isNew: Bool
    let store: KinStore
    let relationship: NewRelationship?
    let onNewSaved: () -> Void
    @State private var reviewedGender: DraftGenderDefault
    @State private var reviewedFirstName: String
    @State private var reviewedLastName: String
    @State private var reviewedConnections: Set<Connection>
    @State private var reviewedIndexInclusion: Bool
    @State private var reviewedAllergies: String?
    @State private var includePhoto = true
    @State private var photoReview = ContactPhotoReview()
    @State private var commit = NewContactImportCommit()
    @State private var importError: String?
    let onImport: (Birthday?, Bool, PreparedContactPhoto?) -> Void
    let onCancel: () -> Void
    @State private var birthKind = "unknown"
    @State private var exactDate = CivilDate(Date(), timeZone: .current).pickerDate
    @State private var referenceDate = CivilDate(Date(), timeZone: .current).pickerDate
    @State private var estimatedAge: Int?
    init(snapshot: ContactSnapshot, currentDraft: Person, currentBirthday: Birthday, isNew: Bool, genderDefault: DraftGenderDefault, store: KinStore, relationship: NewRelationship?, onNewSaved: @escaping () -> Void, onImport: @escaping (Birthday?, Bool, PreparedContactPhoto?) -> Void, onCancel: @escaping () -> Void) {
        self.snapshot = snapshot; self.currentDraft = currentDraft; self.currentBirthday = currentBirthday
        self.onImport = onImport; self.onCancel = onCancel
        self.isNew = isNew; self.store = store; self.relationship = relationship; self.onNewSaved = onNewSaved
        var proposedGender = genderDefault
        proposedGender.nameChanged(snapshot.firstName, lookup: NameAssociations.bundled.gender)
        _reviewedGender = State(initialValue: proposedGender)
        _reviewedFirstName = State(initialValue: snapshot.firstName)
        _reviewedLastName = State(initialValue: snapshot.lastName)
        _reviewedConnections = State(initialValue: currentDraft.connections)
        _reviewedIndexInclusion = State(initialValue: relationship == nil || currentDraft.isListed)
        _reviewedAllergies = State(initialValue: currentDraft.allergies)
        _includePhoto = State(initialValue: !ContactImport.needsPhotoConfirmation(for: snapshot.birthInformation, isNew: isNew))
        let initial = ContactImport.initialBirthday(for: snapshot.birthInformation, currentBirthday: currentBirthday, isNew: isNew)
        switch initial {
        case .unknown: break
        case .exact(let date):
            _birthKind = State(initialValue: "exact"); _exactDate = State(initialValue: date.pickerDate)
        case .estimated(let age, let reference):
            _birthKind = State(initialValue: "estimated"); _estimatedAge = State(initialValue: age)
            _referenceDate = State(initialValue: reference.pickerDate)
        }
    }
    private var needsPhotoConfirmation: Bool {
        ContactImport.needsPhotoConfirmation(for: snapshot.birthInformation, isNew: isNew)
    }
    private var selectedContactName: String {
        (snapshot.firstName + " " + snapshot.lastName).trimmingCharacters(in: .whitespaces)
    }
    private var currentBirthDescription: String {
        switch currentBirthday {
        case .unknown: "Unknown"
        case .exact(let date): date.formatted()
        case .estimated(let age, let reference): "About \(age) on \(reference.formatted())"
        }
    }
    private var valid: Bool {
        (birthKind != "estimated" || estimatedAge != nil) && commit.completedID == nil
    }
    private var birthday: Birthday {
        switch birthKind {
        case "exact": .exact(CivilDate(exactDate, timeZone: CivilDate.pickerCalendar.timeZone))
        case "estimated": estimatedAge.map { .estimated(age: $0, referenceDate: CivilDate(referenceDate, timeZone: CivilDate.pickerCalendar.timeZone)) } ?? .unknown
        default: .unknown
        }
    }
    var body: some View {
        Form {
            Group {
                Section {
                    if isNew {
                        ImportNameField(title: "First name", label: "Imported first name (optional)",
                                        contentType: .givenName, text: Binding(get: { reviewedFirstName }, set: { name in
                            reviewedFirstName = name
                            reviewedGender.nameChanged(name, lookup: NameAssociations.bundled.gender)
                        }))
                        ImportNameField(title: "Last name", label: "Imported last name (optional)",
                                        contentType: .familyName, text: $reviewedLastName)
                        GenderChoice(value: reviewedGender.value, accessibilityID: "contact-gender-choice",
                                     showsIndicator: true) { reviewedGender.choose($0) }
                    } else {
                        LabeledContent("Name from Contacts", value: selectedContactName)
                            .accessibilityIdentifier("contact-selected-contact")
                    }
                    BirthInformationRows(birthKind: $birthKind, exactDate: $exactDate, referenceDate: $referenceDate,
                                         estimatedAge: $estimatedAge, accessibilityPrefix: "contact-")
                } header: {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Contact birth information")
                            .font(.title2.bold()).foregroundStyle(KinTheme.text)
                            .fixedSize(horizontal: false, vertical: true)
                            .background(KinTheme.background)
                            .accessibilityAddTraits(.isHeader)
                        KinSectionHeading(text: isNew ? "Edit details to save" : "Details to apply")
                    }.textCase(nil)
                } footer: {
                    ImportHelper(title: Text("What changes"), text: isNew
                        ? Text("Tap \(FeatureReference.importAndSave) to save the details shown here. Your notes, categories, and chosen relationship stay with the new person.")
                        : Text("Tap \(FeatureReference.importAction) to copy the contact’s name and the reviewed birth information into \(FeatureReference.editPerson). Notes, categories, and relationships stay. Review the photo choice below."))
                }
                if !isNew {
                    Section {
                        if let name = ContactImport.reviewName(for: currentDraft) {
                            LabeledContent("Current name", value: name).accessibilityIdentifier("contact-current-draft")
                        }
                        LabeledContent("Current birth information", value: currentBirthDescription)
                        if currentDraft.photo != nil {
                            LabeledContent("Current photo", value: "Will be replaced or removed")
                        }
                    } header: { KinSectionHeading(text: "Current Kin details") }
                }
                Section {
                    if isNew {
                        LabeledContent("Selected contact", value: selectedContactName)
                            .accessibilityIdentifier("contact-selected-contact")
                    }
                    Text(snapshot.birthInformation.explanation)
                    if needsPhotoConfirmation {
                        Text("Your current birth information is kept unless you change it here.")
                            .accessibilityIdentifier("contact-birth-preservation")
                    }
                } header: { KinSectionHeading(text: "Contact source") } footer: {
                    ImportHelper(title: Text("Before importing a photo"), text: isNew
                        ? Text("Check the birth information before tapping \(FeatureReference.importAndSave). Kin saves without a photo when there isn’t an eligible one. Tap \(FeatureReference.cancel) to return to your earlier draft.")
                        : Text("Check the birth information shown. When the contact has no usable birthday, only turn on \(FeatureReference.includeContactsPhoto) after confirming this information belongs to them. Changes stay on the \(FeatureReference.editPerson) screen until you tap \(FeatureReference.save)."))
                }
                if isNew {
                    Section {
                        if relationship != nil {
                            Toggle("Show on main list", isOn: $reviewedIndexInclusion).accessibilityIdentifier("contact-index-inclusion").accessibilityHint("Show this person on the People screen.")
                        }
                        ForEach(Connection.allCases) { connection in
                            Toggle(connection.rawValue.capitalized, isOn: Binding(get: { reviewedConnections.contains(connection) }, set: { selected in
                                if selected { reviewedConnections.insert(connection) } else { reviewedConnections.remove(connection) }
                            })).accessibilityIdentifier("contact-connection-" + connection.rawValue)
                        }
                    } header: { KinSectionHeading(text: "Your connection") } footer: {
                        if relationship == nil { FeatureHelp.directPerson }
                        else { FeatureHelp.newLinkedPerson }
                    }
                }
                ChildParentsReview(relationship: relationship, people: store.people)
                if isNew && (currentDraft.showsAllergyEditor(isChildInNotebook: isChildEntry(relationship), birthday: birthday, on: Date())
                    || !(reviewedAllergies ?? "").isEmpty) {
                    ChildAllergyField(allergies: $reviewedAllergies)
                }
                if AgeRules(calendar: .current).allowsPhoto(birthday, on: Date()) && (isNew || needsPhotoConfirmation) {
                    Section {
                        Toggle("Include eligible Contacts photo", isOn: $includePhoto)
                            .accessibilityIdentifier("contact-include-photo")
                    } footer: {
                        if needsPhotoConfirmation {
                            Text("Only include a photo after confirming the birth information shown belongs to this contact.")
                        }
                    }
                }
                Section("Contacts photo preview") {
                    if let prepared = photoReview.prepared, prepared.birthday == birthday, includePhoto,
                       AgeRules(calendar: .current).allowsPhoto(birthday, on: Date()),
                       let data = prepared.data, let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 180)
                            .accessibilityLabel("Eligible Contacts photo to import")
                            .accessibilityIdentifier("contact-photo-preview")
                    } else {
                        Text(includePhoto && AgeRules(calendar: .current).allowsPhoto(birthday, on: Date())
                             ? "No eligible Contacts photo available." : "No Contacts photo will be imported.")
                            .accessibilityIdentifier("contact-photo-preview-empty")
                    }
                }
                Section {
                    Button(isNew ? "Import and Save without photo" : "Continue without importing photo") { confirmImport(withoutPhoto: true) }.disabled(!valid)
                } footer: { Text(isNew ? "Save the reviewed details without keeping a Contacts photo." : "Copy the name and use the reviewed birth information. A missing or incomplete birthday keeps your current information unless you change it here. Remove the photo already on this screen without keeping the Contacts photo.") }
            }.listRowBackground(KinTheme.editableFormRow)
        }
        .environment(\.calendar, CivilDate.pickerCalendar).environment(\.timeZone, CivilDate.pickerCalendar.timeZone)
        .onAppear { refreshPhoto() }
        .onChange(of: birthday) { _, _ in refreshPhoto() }
        .onChange(of: includePhoto) { _, _ in refreshPhoto() }
        .kinError($importError).notebookAvailability(store)
        .kinForm().navigationTitle("Contact birth information").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1).accessibilityHidden(true) }
            SheetEditActions(cancel: onCancel, confirmTitle: isNew ? "Import and Save" : "Import",
                             confirm: { confirmImport() }, confirmDisabled: !valid,
                             cancelIdentifier: "contact-cancel", confirmIdentifier: "contact-import")
        }
    }
    private func refreshPhoto() {
        photoReview.update(snapshot: snapshot, birthday: birthday, included: includePhoto)
    }
    private func confirmImport(withoutPhoto: Bool = false) {
        guard commit.completedID == nil else { return }
        guard valid else { return }
        if !withoutPhoto { refreshPhoto() }
        if !isNew { onImport(birthday, !withoutPhoto && includePhoto, photoReview.prepared); return }
        var value = currentDraft
        var reviewed = snapshot
        reviewed.firstName = reviewedFirstName; reviewed.lastName = reviewedLastName
        ContactImport.apply(reviewed, to: &value, birthday: birthday, importPhoto: !withoutPhoto && includePhoto, preparedPhoto: photoReview.prepared)
        value.gender = reviewedGender.value
        value.connections = reviewedConnections
        value.isListed = reviewedIndexInclusion
        value.allergies = reviewedAllergies
        do {
            try commit.save(value, store: store, relationship: relationship)
            onNewSaved()
        } catch { importError = UserFacingError.message(error) }
    }
}

private struct ImportNameField: View {
    let title: LocalizedStringKey
    let label: LocalizedStringKey
    let contentType: UITextContentType
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.subheadline.weight(.medium)).accessibilityHidden(true)
            TextField(label, text: $text, prompt: Text("Optional").foregroundStyle(KinTheme.secondary))
                .textContentType(contentType)
                .accessibilityLabel(Text(label))
                .padding(.horizontal, 10)
                .frame(minHeight: 44)
                .background(KinTheme.field, in: RoundedRectangle(cornerRadius: 10))
                .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(KinTheme.divider).allowsHitTesting(false) }
        }
        .padding(.vertical, 4)
    }
}

/// Supporting guidance stays visible, wraps semantically and keeps its section's reading order.
private struct ImportHelper: View {
    let title: Text
    let text: Text
    var body: some View {
        (title.fontWeight(.semibold) + Text("\n") + text)
            .font(.footnote).foregroundStyle(KinTheme.helperText).lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true).textCase(nil)
    }
}

/// Explicit actions also register reselecting the current value as a manual override.
private struct GenderChoice: View {
    let value: Gender
    let accessibilityID: String
    let showsIndicator: Bool
    let choose: (Gender) -> Void
    init(value: Gender, accessibilityID: String = "gender-choice", showsIndicator: Bool = false, choose: @escaping (Gender) -> Void) {
        self.value = value; self.accessibilityID = accessibilityID; self.showsIndicator = showsIndicator; self.choose = choose
    }
    var body: some View {
        Menu {
            ForEach(Gender.allCases) { gender in
                Button(gender.title, systemImage: gender == value ? "checkmark" : "person") { choose(gender) }
                    .accessibilityAddTraits(gender == value ? .isSelected : [])
            }
        } label: {
            LabeledContent("Gender") {
                HStack(spacing: 6) {
                    Text(value.title)
                    if showsIndicator { Image(systemName: "chevron.up.chevron.down").font(.caption).accessibilityHidden(true) }
                }
            }.frame(minHeight: 44)
        }
        .accessibilityLabel("Gender").accessibilityValue(value.title)
        .accessibilityHint("Optional. Choose any value to keep it while editing this name.")
        .accessibilityIdentifier(accessibilityID)
    }
}
