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
    private var photoAllowed: Bool { AgeRules(calendar: .current).allowsPhoto(birthday, on: Date()) }
    private var needsRemoval: Bool { ageInputValid && original?.photo != nil && original?.birthday != birthday && !photoAllowed }
    var body: some View {
        Form {
            Group {
                Section {
                    Button("Import from Contacts") { pendingContact = nil; pickingContact = true }
                } footer: { Text("Choose a contact to copy their name and birthday. Kin only imports their photo when we can be sure they’re at least 18.") }
                nameSection
                connectionSection
                ageSection
                photoSection
                Section("Notes") { TextField("The little things to remember", text: $draft.notes, axis: .vertical).lineLimit(4...10) }
            }.listRowBackground(KinTheme.editableFormRow)
        }
        .environment(\.calendar, CivilDate.pickerCalendar).environment(\.timeZone, CivilDate.pickerCalendar.timeZone)
        .kinForm().navigationTitle(isNew ? "Add person" : "Edit person").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(photoLoading || didSave || !ageInputValid) }
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
                        ContactBirthInformationView(snapshot: snapshot, currentDraft: draft, currentBirthday: birthday, isNew: isNew, store: store, relationship: relationship, onNewSaved: { savedImport = true; pickingContact = false }) { birth, includePhoto in
                            finishContactImport(snapshot, birthday: birth, importPhoto: includePhoto)
                        } onCancel: { pendingContact = nil; pickingContact = false }
                    }
                } else {
                    ContactPicker { snapshot in
                        pendingContact = snapshot
                    } onCancel: { pickingContact = false }
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
        Section("Name") {
            TextField("First name (optional)", text: Binding(get: { draft.firstName ?? "" }, set: { draft.firstName = $0.isEmpty ? nil : $0 })).textContentType(.givenName)
            TextField("Last name (optional)", text: Binding(get: { draft.lastName ?? "" }, set: { draft.lastName = $0.isEmpty ? nil : $0 })).textContentType(.familyName)
            Picker("Gender", selection: $draft.gender) { ForEach(Gender.allCases) { Text($0.rawValue.capitalized).tag($0) } }
        }
    }
    private var connectionSection: some View {
        Section {
            if !isNew || relationship != nil {
                Toggle("Show in Your people", isOn: $draft.isListed).accessibilityIdentifier("index-inclusion")
            }
            ForEach(Connection.allCases) { connection in
                Toggle(connection.rawValue.capitalized, isOn: Binding(get: { draft.connections.contains(connection) }, set: { selected in
                    if selected { draft.connections.insert(connection) } else { draft.connections.remove(connection) }
                }))
            }
        } header: { Text("Your connection") } footer: {
            Text(isNew && relationship == nil ? "Connection labels are optional. People added here stay in Your people, even without a label." : "Connection labels are optional and don’t change list inclusion. Turn on Show in Your people to include this person there. Everyone remains in All people and linked profiles.")
        }
    }
    private var ageSection: some View {
        BirthInformationFields(birthKind: $birthKind, exactDate: $exactDate, referenceDate: $referenceDate, estimatedAge: $estimatedAge)
    }
    private func finishContactImport(_ snapshot: ContactSnapshot, birthday importedBirthday: Birthday? = nil, importPhoto: Bool = true) {
        photoGeneration = UUID(); pickedPhoto = nil; photoLoading = false
        draft.birthday = birthday
        ContactImport.apply(snapshot, to: &draft, birthday: importedBirthday, importPhoto: importPhoto)
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
        return Section("Photo") {
            if photoAllowed {
                InitialAvatar(first: draft.firstName ?? "?", last: draft.lastName ?? "", photo: draft.photo, gender: draft.gender, size: 64)
                PhotosPicker(selection: $pickedPhoto, matching: .images) { Label(title, systemImage: "photo") }
                if photoLoading { ProgressView("Loading photo") }
                if draft.photo != nil { Button("Remove photo", role: .destructive) { photoGeneration = UUID(); pickedPhoto = nil; photoLoading = false; draft.photo = nil }.kinDestructiveText() }
            } else {
                Text(needsRemoval ? "You’ll need to remove the saved photo before saving this age." : "Photos are only available when we can be sure this person is at least 18. For an estimate, even the youngest possible age must be 18 or older.")
            }
        }
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
private struct BirthInformationFields: View {
    @Binding var birthKind: String
    @Binding var exactDate: Date
    @Binding var referenceDate: Date
    @Binding var estimatedAge: Int?
    @State private var choosingAge = false
    var accessibilityPrefix = ""
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        Section("Age") {
            Picker("Birth information", selection: $birthKind) {
                Text("Unknown").tag("unknown"); Text("Exact birthday").tag("exact"); Text("Estimated age").tag("estimated")
            }.accessibilityIdentifier(accessibilityPrefix + "birth-information")
            if birthKind == "exact" {
                DatePicker("Birthday", selection: $exactDate, in: ...CivilDate(Date(), timeZone: .current).pickerDate, displayedComponents: .date)
            }
            if birthKind == "estimated" {
                Button { choosingAge = true } label: {
                    LabeledContent("Age in years", value: estimatedAge.map(String.init) ?? "Choose age")
                }.accessibilityLabel("Age in years")
                    .accessibilityValue(estimatedAge.map(String.init) ?? "Not chosen")
                    .accessibilityHint("Opens a scrollable age picker")
                    .accessibilityIdentifier(accessibilityPrefix + "choose-estimated-age")
                    .sheet(isPresented: $choosingAge) {
                        EstimatedAgeWheel(age: estimatedAge) { selected in estimatedAge = selected }
                            .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.height(340)])
                            .presentationDragIndicator(.visible)
                    }
                DatePicker("As of", selection: $referenceDate, in: ...CivilDate(Date(), timeZone: .current).pickerDate, displayedComponents: .date)
                Text("Estimated ages are marked with ~. Starting from the age and date you choose, Kin adds a year on the same date each year without guessing a birthday. School grades are a rough guide and may differ from the child’s actual grade.").font(.footnote)
            }
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
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { onDone(selection); dismiss() } }
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
    @State private var reviewedFirstName: String
    @State private var reviewedLastName: String
    @State private var reviewedConnections: Set<Connection>
    @State private var reviewedIndexInclusion: Bool
    @State private var includePhoto = true
    @State private var commit = NewContactImportCommit()
    @State private var importError: String?
    let onImport: (Birthday?, Bool) -> Void
    let onCancel: () -> Void
    @State private var birthKind = "unknown"
    @State private var exactDate = CivilDate(Date(), timeZone: .current).pickerDate
    @State private var referenceDate = CivilDate(Date(), timeZone: .current).pickerDate
    @State private var estimatedAge: Int?
    init(snapshot: ContactSnapshot, currentDraft: Person, currentBirthday: Birthday, isNew: Bool, store: KinStore, relationship: NewRelationship?, onNewSaved: @escaping () -> Void, onImport: @escaping (Birthday?, Bool) -> Void, onCancel: @escaping () -> Void) {
        self.snapshot = snapshot; self.currentDraft = currentDraft; self.currentBirthday = currentBirthday
        self.onImport = onImport; self.onCancel = onCancel
        self.isNew = isNew; self.store = store; self.relationship = relationship; self.onNewSaved = onNewSaved
        _reviewedFirstName = State(initialValue: snapshot.firstName)
        _reviewedLastName = State(initialValue: snapshot.lastName)
        _reviewedConnections = State(initialValue: currentDraft.connections)
        _reviewedIndexInclusion = State(initialValue: relationship == nil || currentDraft.isListed)
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
                    if let name = ContactImport.reviewName(for: currentDraft) {
                        LabeledContent("Current draft", value: name).accessibilityIdentifier("contact-current-draft")
                    }
                    LabeledContent("Current birth information", value: currentBirthDescription)
                    if currentDraft.photo != nil {
                        LabeledContent("Current photo", value: "Will be replaced or removed")
                    }
                    LabeledContent("Selected contact", value: (snapshot.firstName + " " + snapshot.lastName).trimmingCharacters(in: .whitespaces)).accessibilityIdentifier("contact-selected-contact")
                    if isNew {
                        TextField("Imported first name (optional)", text: $reviewedFirstName).textContentType(.givenName)
                        TextField("Imported last name (optional)", text: $reviewedLastName).textContentType(.familyName)
                    }
                } header: { Text("Review import") } footer: {
                    ImportHelper(title: "What changes", text: isNew
                        ? "Import and Save replaces the draft’s name, age, and photo with your reviewed contact details, then saves the new person. It saves without a photo if none is selected or eligible. Notes, connections, and chosen relationship details stay."
                        : "Import copies the name and uses the birth information you review below. A missing or incomplete contact birthday keeps your current birth information unless you change it. The photo is replaced or removed according to your choice. Notes, connections, and relationships stay.")
                }
                Section {
                    Text(snapshot.birthInformation.explanation)
                    if needsPhotoConfirmation {
                        Text("Your current birth information is kept unless you change it here.")
                            .accessibilityIdentifier("contact-birth-preservation")
                    }
                } footer: {
                    ImportHelper(title: "Before importing a photo", text: isNew
                        ? "Check the contact’s birthday or estimated age. You can leave their age unknown. Import and Save saves the new person and any chosen relationship together. Cancel keeps your earlier draft without saving."
                        : "Check the birth information shown. When the contact has no usable birthday, confirm this information belongs to the selected contact before choosing to include their photo. Changes are saved only when you save the person.")
                }
                if isNew {
                    Section {
                        if relationship != nil {
                            Toggle("Show in Your people", isOn: $reviewedIndexInclusion).accessibilityIdentifier("contact-index-inclusion")
                        }
                        ForEach(Connection.allCases) { connection in
                            Toggle(connection.rawValue.capitalized, isOn: Binding(get: { reviewedConnections.contains(connection) }, set: { selected in
                                if selected { reviewedConnections.insert(connection) } else { reviewedConnections.remove(connection) }
                            })).accessibilityIdentifier("contact-connection-" + connection.rawValue)
                        }
                    } header: { Text("Your connection") } footer: {
                        Text(relationship == nil ? "Connection labels are optional. This person will stay in Your people, even without a label." : "Connection labels are optional. Show in Your people controls list inclusion; everyone remains in All people and linked profiles.")
                    }
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
                BirthInformationFields(birthKind: $birthKind, exactDate: $exactDate, referenceDate: $referenceDate, estimatedAge: $estimatedAge, accessibilityPrefix: "contact-")
                Section {
                    Button(isNew ? "Import and Save without photo" : "Continue without importing photo") { confirmImport(withoutPhoto: true) }.disabled(!valid)
                } footer: { Text(isNew ? "Save the reviewed name and age without reading a photo from Contacts." : "Copy the name and use the reviewed birth information. A missing or incomplete birthday keeps your current information unless you change it here. Remove the photo already on this screen without reading a Contacts photo.") }
            }.listRowBackground(KinTheme.editableFormRow)
        }
        .environment(\.calendar, CivilDate.pickerCalendar).environment(\.timeZone, CivilDate.pickerCalendar.timeZone)
        .kinError($importError).notebookAvailability(store)
        .kinForm().navigationTitle("Contact birth information").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
            ToolbarItem(placement: .confirmationAction) { Button(isNew ? "Import and Save" : "Import") { confirmImport() }.disabled(!valid) }
        }
    }
    private func confirmImport(withoutPhoto: Bool = false) {
        guard commit.completedID == nil else { return }
        guard valid else { return }
        if !isNew { onImport(birthday, !withoutPhoto && includePhoto); return }
        var value = currentDraft
        var reviewed = snapshot
        reviewed.firstName = reviewedFirstName; reviewed.lastName = reviewedLastName
        ContactImport.apply(reviewed, to: &value, birthday: birthday, importPhoto: !withoutPhoto && includePhoto)
        value.connections = reviewedConnections
        value.isListed = reviewedIndexInclusion
        do {
            try commit.save(value, store: store, relationship: relationship)
            onNewSaved()
        } catch { importError = UserFacingError.message(error) }
    }
}

/// Supporting guidance stays visible, wraps semantically and keeps its section's reading order.
private struct ImportHelper: View {
    let title: String
    let text: String
    var body: some View {
        (Text(title).fontWeight(.semibold) + Text("\n" + text))
            .font(.footnote).foregroundStyle(KinTheme.helperText).lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true).textCase(nil)
    }
}
