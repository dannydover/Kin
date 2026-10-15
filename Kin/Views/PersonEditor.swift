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
    @State private var estimatedAgeText: String
    @FocusState private var ageFocused: Bool
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var pickingContact = false
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
        var kind = "unknown", exact = today, reference = today, age = ""
        switch value.birthday {
        case .unknown: break
        case .exact(let date): kind = "exact"; exact = date.pickerDate
        case .estimated(let years, let date): kind = "estimated"; reference = date.pickerDate; age = String(years)
        }
        _birthKind = State(initialValue: kind); _exactDate = State(initialValue: exact)
        _referenceDate = State(initialValue: reference); _estimatedAgeText = State(initialValue: age)
    }
    private var estimatedAge: Int? { AgeRules.estimatedAge(from: estimatedAgeText) }
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
                    Button("Import from Contacts") { pickingContact = true }
                } footer: { Text("One-time name import. A photo is imported only when the entered age is safely 18 or older. Contacts never supplies an assumed age.") }
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
            ToolbarItemGroup(placement: .keyboard) {
                if ageFocused { Spacer(); Button("Done") { ageFocused = false } }
            }
        }
        .alert("Remove the existing photo?", isPresented: $removalWarning) {
            Button("Remove photo and save", role: .destructive) { save(confirmed: true) }.kinDestructiveText()
            Button("Cancel", role: .cancel) { }
        } message: { Text("This age correction makes the person ineligible for photos. Saving will remove their photo. Canceling the editor preserves the saved photo and age.") }
        .sheet(isPresented: $pickingContact) {
            ContactPicker(includePhoto: photoAllowed) { snapshot in
                photoGeneration = UUID(); pickedPhoto = nil; photoLoading = false
                draft.birthday = birthday
                ContactImport.apply(snapshot, to: &draft)
                pickingContact = false
            } onCancel: { pickingContact = false }
            .interactiveDismissDisabled()
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
            Text(isNew && relationship == nil ? "Choose at least one connection for this top-level addition. You can change it later." : "Select any that apply. With none selected, this person stays in All people and linked profiles, off the main index.")
        }
    }
    private var ageSection: some View {
        Section("Age") {
            Picker("Birth information", selection: $birthKind) {
                Text("Unknown").tag("unknown"); Text("Exact birthday").tag("exact"); Text("Estimated age").tag("estimated")
            }
            if birthKind == "exact" {
                DatePicker("Birthday", selection: $exactDate, in: ...CivilDate(Date(), timeZone: .current).pickerDate, displayedComponents: .date)
            }
            if birthKind == "estimated" {
                (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 16))) {
                    Text("Age in years")
                    TextField("0–120", text: $estimatedAgeText)
                        .keyboardType(.numberPad).focused($ageFocused)
                        .multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
                        .accessibilityLabel("Estimated age in years")
                        .accessibilityHint("Enter a whole number from 0 to 120")
                }
                if estimatedAge == nil {
                    Text("Enter a whole number from 0 to 120.").font(.footnote)
                        .foregroundStyle(estimatedAgeText.isEmpty ? KinTheme.secondary : Color(uiColor: .systemRed))
                }
                DatePicker("As of", selection: $referenceDate, in: ...CivilDate(Date(), timeZone: .current).pickerDate, displayedComponents: .date)
                Text("~ means estimated. Kin keeps this age and as-of date, and advances the estimate on each as-of anniversary. It never invents a birthday. School grade is approximate; actual school placement can differ.").font(.footnote)
            }
        }
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
                Text(needsRemoval ? "Saving this age correction requires confirmation to remove the existing photo." : "Photos are available only for known ages of at least 18. Estimates must exclude every possible age under 18.")
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
        } catch { self.error = error.localizedDescription }
    }
}
