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
    private var photoAllowed: Bool { AgeRules(calendar: .current).allowsPhoto(birthday, on: Date()) }
    private var needsRemoval: Bool { ageInputValid && original?.photo != nil && original?.birthday != birthday && !photoAllowed }
    var body: some View {
        Form {
            Group {
                Section {
                    Button("Import from Contacts") { pendingContact = nil; pickingContact = true }
                } footer: { Text("Choose a contact to copy their name and birthday. Kin only imports their photo when we can be sure they’re at least 18.") }
                nameSection
                ageSection
                photoSection
                connectionSection
                Section("Notes") { TextField("The little things to remember", text: $draft.notes, axis: .vertical).lineLimit(4...10) }
            }.listRowBackground(KinTheme.editableFormRow)
        }
        .environment(\.calendar, CivilDate.pickerCalendar).environment(\.timeZone, CivilDate.pickerCalendar.timeZone)
        .kinForm().navigationTitle(isNew ? "Add person" : "Edit person").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { ConfirmationLabel(title: "Cancel", primary: false) }.buttonStyle(.plain) }.sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .confirmationAction) { Button { save() } label: { ConfirmationLabel(title: "Save") }.buttonStyle(.plain).disabled(photoLoading || didSave || !ageInputValid) }.sharedBackgroundVisibility(.hidden)
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
        Section {
            TextField("First name (optional)", text: Binding(get: { draft.firstName ?? "" }, set: { name in
                draft.firstName = name.isEmpty ? nil : name
                genderDefault.nameChanged(name, lookup: NameAssociations.bundled.gender)
                draft.gender = genderDefault.value
            }), prompt: Text("First name")).textContentType(.givenName).accessibilityLabel("First name (optional)")
            TextField("Last name (optional)", text: Binding(get: { draft.lastName ?? "" }, set: { draft.lastName = $0.isEmpty ? nil : $0 }), prompt: Text("Last name")).textContentType(.familyName).accessibilityLabel("Last name (optional)")
            GenderChoice(value: draft.gender) { gender in genderDefault.choose(gender); draft.gender = gender }
        } header: { Text("Name") } footer: {
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
        } header: { Text("Your connection") } footer: {
            if isNew && relationship == nil { FeatureHelp.directPerson }
            else if isNew { FeatureHelp.newLinkedPerson }
            else { FeatureHelp.listInclusion }
        }
    }
    private var ageSection: some View {
        BirthInformationFields(birthKind: $birthKind, exactDate: $exactDate, referenceDate: $referenceDate, estimatedAge: $estimatedAge)
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
                    .accessibilityIdentifier(accessibilityPrefix + "exact-birthday")
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
    @State private var reviewedGender: DraftGenderDefault
    @State private var reviewedFirstName: String
    @State private var reviewedLastName: String
    @State private var reviewedConnections: Set<Connection>
    @State private var reviewedIndexInclusion: Bool
    @State private var includePhoto = true
    @State private var photoReview = ContactPhotoReview()
    @State private var commit = NewContactImportCommit()
    @State private var importError: String?
    let onImport: (Birthday?, Bool, PreparedContactPhoto?) -> Void
    let onCancel: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
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
                        TextField("Imported first name (optional)", text: Binding(get: { reviewedFirstName }, set: { name in
                            reviewedFirstName = name
                            reviewedGender.nameChanged(name, lookup: NameAssociations.bundled.gender)
                        }), prompt: Text("First name")).textContentType(.givenName).accessibilityLabel("Imported first name (optional)")
                        TextField("Imported last name (optional)", text: $reviewedLastName, prompt: Text("Last name")).textContentType(.familyName).accessibilityLabel("Imported last name (optional)")
                        GenderChoice(value: reviewedGender.value, accessibilityID: "contact-gender-choice") { reviewedGender.choose($0) }
                    }
                } header: { Text("Review import") } footer: {
                    ImportHelper(title: Text("What changes"), text: isNew
                        ? Text("Tap \(FeatureReference.importAndSave) to replace the draft’s name, gender, age, and photo with your reviewed contact details and save the new person. It saves without a photo if none is selected or eligible. Notes, categories, and chosen relationship details stay.")
                        : Text("Tap \(FeatureReference.importAction) to copy the name and use the birth information you review below. A missing or incomplete contact birthday keeps your current birth information unless you change it. The photo is replaced or removed according to your choice. Notes, categories, and relationships stay."))
                }
                Section {
                    Text(snapshot.birthInformation.explanation)
                    if needsPhotoConfirmation {
                        Text("Your current birth information is kept unless you change it here.")
                            .accessibilityIdentifier("contact-birth-preservation")
                    }
                } footer: {
                    ImportHelper(title: Text("Before importing a photo"), text: isNew
                        ? Text("Check the contact’s birthday or estimated age. You can leave their age unknown. Tap \(FeatureReference.importAndSave) to save this person and any chosen relationship together. Tap \(FeatureReference.cancel) to keep your earlier draft without saving.")
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
                    } header: { Text("Your connection") } footer: {
                        if relationship == nil { FeatureHelp.directPerson }
                        else { FeatureHelp.newLinkedPerson }
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
                BirthInformationFields(birthKind: $birthKind, exactDate: $exactDate, referenceDate: $referenceDate, estimatedAge: $estimatedAge, accessibilityPrefix: "contact-")
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))) {
                Button(action: onCancel) { ConfirmationLabel(title: "Cancel", primary: false, fillsWidth: true) }
                    .accessibilityIdentifier("contact-cancel")
                Button { confirmImport() } label: { ConfirmationLabel(title: isNew ? "Import and Save" : "Import", fillsWidth: true) }
                    .accessibilityIdentifier("contact-import").disabled(!valid)
            }
            .buttonStyle(.plain).padding(16).background(KinTheme.background)
            .overlay(alignment: .top) { Rectangle().fill(KinTheme.border).frame(height: 1).accessibilityHidden(true) }
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
        do {
            try commit.save(value, store: store, relationship: relationship)
            onNewSaved()
        } catch { importError = UserFacingError.message(error) }
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
    let choose: (Gender) -> Void
    init(value: Gender, accessibilityID: String = "gender-choice", choose: @escaping (Gender) -> Void) {
        self.value = value; self.accessibilityID = accessibilityID; self.choose = choose
    }
    var body: some View {
        Menu {
            ForEach(Gender.allCases) { gender in
                Button(gender.title, systemImage: gender == value ? "checkmark" : "person") { choose(gender) }
                    .accessibilityAddTraits(gender == value ? .isSelected : [])
            }
        } label: {
            LabeledContent("Gender", value: value.title).frame(minHeight: 44)
        }
        .accessibilityLabel("Gender").accessibilityValue(value.title)
        .accessibilityHint("Optional. Choose any value to keep it while editing this name.")
        .accessibilityIdentifier(accessibilityID)
    }
}

/// Opaque colors keep confirmation text readable over native toolbar materials.
private struct ConfirmationLabel: View {
    let title: String
    var primary = true
    var fillsWidth = false
    var body: some View {
        Text(title).foregroundStyle(primary ? KinTheme.background : KinTheme.text)
            .padding(.horizontal, 10).padding(.vertical, fillsWidth ? 8 : 0)
            .frame(minWidth: 44, maxWidth: fillsWidth ? .infinity : nil, minHeight: 44)
            .background(primary ? KinTheme.text : KinTheme.background, in: RoundedRectangle(cornerRadius: 12))
            // Preserve the entire padded background's intrinsic toolbar width,
            // rather than letting only the text overflow a compressed frame.
            .fixedSize(horizontal: !fillsWidth, vertical: true)
    }
}
