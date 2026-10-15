import SwiftUI
import PhotosUI

struct PersonEditor: View {
    let store: KinStore
    let relationship: NewRelationship?
    let onSaved: (() -> Void)?
    private let isNew: Bool
    private let original: Person?
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Person
    @State private var birthKind: String
    @State private var exactDate: Date
    @State private var referenceDate: Date
    @State private var estimatedAge: Int?
    @State private var pickingContact = false
    @State private var pendingContact: ContactSnapshot?
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var photoGeneration = UUID()
    @State private var photoLoading = false
    @State private var removalWarning = false
    @State private var error: String?
    init(store: KinStore, person: Person? = nil, relationship: NewRelationship? = nil, onSaved: (() -> Void)? = nil) {
        self.store = store; original = person; isNew = person == nil
        self.relationship = relationship; self.onSaved = onSaved
        let value = person ?? Person()
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
    private var connectionChosen: Bool { relationship != nil || !isNew || !draft.connections.isEmpty }
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
            ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(photoLoading || !connectionChosen || !ageInputValid) }
        }
        .alert("Remove the existing photo?", isPresented: $removalWarning) {
            Button("Remove photo and save", role: .destructive) { save(confirmed: true) }.kinDestructiveText()
            Button("Cancel", role: .cancel) { }
        } message: { Text("Kin can’t be sure this person is at least 18, so it can’t keep this photo. Remove it to save these changes. To keep the saved photo and age, cancel this edit.") }
        .sheet(isPresented: $pickingContact, onDismiss: { pendingContact = nil }) {
            Group {
                if let snapshot = pendingContact {
                    NavigationStack {
                        ContactBirthInformationView(snapshot: snapshot, currentDraft: draft, currentBirthday: birthday) { birth, includePhoto in
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
            ForEach(Connection.allCases) { connection in
                Toggle(connection.rawValue.capitalized, isOn: Binding(get: { draft.connections.contains(connection) }, set: { selected in
                    if selected { draft.connections.insert(connection) } else { draft.connections.remove(connection) }
                }))
            }
        } header: { Text("Your connection") } footer: {
            Text(isNew && relationship == nil ? "Choose at least one way you know this person. You can change it later." : "Choose any that fit. Leave all off to keep this person out of Your people. You can still find them in All people and linked profiles.")
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
        guard ageInputValid else { return }
        guard !needsRemoval || confirmed else { removalWarning = true; return }
        var value = draft; value.birthday = birthday
        if confirmed && !photoAllowed { value.photo = nil }
        do {
            try store.savePerson(value, confirmPhotoRemoval: confirmed, relationship: relationship)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            // The linked-create flow owns dismissal of its entire sheet; use
            // one presentation owner instead of dismissing a push and sheet together.
            if let onSaved { onSaved() } else { dismiss() }
        } catch { self.error = UserFacingError.message(error) }
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
            }
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
                Text("~ means the age is an estimate. Starting from the age and date you choose, Kin adds a year on the same date each year without guessing a birthday. School grades are a rough guide and may differ from the child’s actual grade.").font(.footnote)
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
    let onImport: (Birthday?, Bool) -> Void
    let onCancel: () -> Void
    @State private var birthKind = "unknown"
    @State private var exactDate = CivilDate(Date(), timeZone: .current).pickerDate
    @State private var referenceDate = CivilDate(Date(), timeZone: .current).pickerDate
    @State private var estimatedAge: Int?
    init(snapshot: ContactSnapshot, currentDraft: Person, currentBirthday: Birthday, onImport: @escaping (Birthday?, Bool) -> Void, onCancel: @escaping () -> Void) {
        self.snapshot = snapshot; self.currentDraft = currentDraft; self.currentBirthday = currentBirthday
        self.onImport = onImport; self.onCancel = onCancel
        // Only this selected card supplies initial age information. Never use a
        // different person's prefilled adulthood to authorize a photo read.
        if case .exact(let date) = snapshot.birthInformation {
            _birthKind = State(initialValue: "exact"); _exactDate = State(initialValue: date.pickerDate)
        }
    }
    private var currentBirthDescription: String {
        switch currentBirthday {
        case .unknown: "Unknown"
        case .exact(let date): date.formatted()
        case .estimated(let age, let reference): "About \(age) on \(reference.formatted())"
        }
    }
    private var valid: Bool { birthKind != "estimated" || estimatedAge != nil }
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
                Section("Review import") {
                    LabeledContent("Current draft", value: currentDraft.displayName)
                    LabeledContent("Current birth information", value: currentBirthDescription)
                    if currentDraft.photo != nil {
                        LabeledContent("Current photo", value: "Will be replaced or removed")
                    }
                    LabeledContent("Selected contact", value: (snapshot.firstName + " " + snapshot.lastName).trimmingCharacters(in: .whitespaces))
                    Text("Import will replace the name and age information on this screen. It will also replace the photo, or remove it if this contact has no photo Kin can use. Notes, connections, and relationships will stay.")
                }
                Section {
                    Text(snapshot.birthInformation.explanation)
                    Text("Check this contact’s birthday or estimated age before importing a photo. You can leave their age unknown. These changes won’t be saved until you save the person.")
                }
                BirthInformationFields(birthKind: $birthKind, exactDate: $exactDate, referenceDate: $referenceDate, estimatedAge: $estimatedAge, accessibilityPrefix: "contact-")
                Section {
                    Button("Continue without importing photo") { onImport(nil, false) }
                } footer: { Text("Copy the name and birthday from this contact. If the birthday is missing or incomplete, use Unknown. Remove the photo already on this screen without reading a photo from Contacts.") }
            }.listRowBackground(KinTheme.editableFormRow)
        }
        .environment(\.calendar, CivilDate.pickerCalendar).environment(\.timeZone, CivilDate.pickerCalendar.timeZone)
        .kinForm().navigationTitle("Contact birth information").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
            ToolbarItem(placement: .confirmationAction) { Button("Import") { onImport(birthday, true) }.disabled(!valid) }
        }
    }
}
