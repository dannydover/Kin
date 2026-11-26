import SwiftUI

enum PetEditorRoute: Identifiable {
    case add
    case edit(Pet)

    var id: String {
        switch self {
        case .add: "new-pet"
        case .edit(let pet): pet.id.uuidString
        }
    }

    var pet: Pet? {
        if case .edit(let pet) = self { return pet }
        return nil
    }
}

struct PetProfileSection: View {
    let pets: [Pet]
    let edit: (PetEditorRoute) -> Void

    var body: some View {
        Section {
            ForEach(pets) { pet in
                Button { edit(.edit(pet)) } label: {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            KinTitle(text: pet.name, size: 14)
                            Text(pet.species.title).font(.subheadline).foregroundStyle(KinTheme.secondary)
                            switch pet.age {
                            case .unknown:
                                EmptyView()
                            case .exact(let birthday):
                                Text("Birthday: \(birthday.formatted())").font(.subheadline)
                            case .estimated(let lifeStage):
                                Text("Estimated age: \(lifeStage.title)").font(.subheadline)
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityElement(children: .combine)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        Image(systemName: "pencil")
                            .font(.body.weight(.medium))
                            .foregroundStyle(KinTheme.accent)
                            .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens this pet’s details for editing.")
                .accessibilityIdentifier("pet-profile-row-\(pet.id.uuidString)")
            }
            RelationshipProfileAction(title: "Add pet", systemImage: "plus") { edit(.add) }
                .accessibilityIdentifier("add-pet")
        } header: {
            KinSectionHeading(text: "Pets")
        }
    }
}

struct PetEditor: View {
    let store: KinStore
    let personID: UUID
    let original: Pet?
    @State private var draft: Pet
    @State private var speciesKind: SpeciesKind
    @State private var customSpecies: String
    @State private var showBirthday = false
    @State private var suggestedBirthday = Date()
    @State private var deleting = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    private enum SpeciesKind: String, CaseIterable, Identifiable {
        case choose = "Choose species", dog = "Dog", cat = "Cat", other = "Other"
        var id: Self { self }
    }

    init(store: KinStore, personID: UUID, original: Pet?) {
        self.store = store
        self.personID = personID
        self.original = original
        let value = original ?? Pet(name: "", species: .dog)
        _draft = State(initialValue: value)
        switch value.species {
        case .dog:
            _speciesKind = State(initialValue: original == nil ? .choose : .dog)
            _customSpecies = State(initialValue: "")
        case .cat:
            _speciesKind = State(initialValue: .cat)
            _customSpecies = State(initialValue: "")
        case .other(let text):
            _speciesKind = State(initialValue: .other)
            _customSpecies = State(initialValue: text)
        }
    }

    private var species: PetSpecies? {
        switch speciesKind {
        case .choose: nil
        case .dog: .dog
        case .cat: .cat
        case .other: .other(customSpecies)
        }
    }

    private var value: Pet? {
        guard let species else { return nil }
        var value = draft
        value.species = species
        return value
    }

    private var today: CivilDate { CivilDate(Date(), timeZone: .current) }

    var body: some View {
        Form {
            Group {
                Section {
                    TextField("Pet name", text: $draft.name).accessibilityIdentifier("pet-name")
                    Picker("Species", selection: $speciesKind) {
                        ForEach(SpeciesKind.allCases) { kind in Text(kind.rawValue).tag(kind) }
                    }
                    .accessibilityIdentifier("pet-species")
                    if speciesKind == .other {
                        TextField("Species name", text: $customSpecies).accessibilityIdentifier("pet-species-name")
                    }
                } header: {
                    KinSectionHeading(text: "Pet details")
                }
                Section {
                    Menu {
                        Button("Unknown") { draft.age = .unknown }
                        Button("Exact birthday", action: openBirthday)
                        if let stages = species?.estimatedStages, !stages.isEmpty {
                            Section("Estimated age") {
                                ForEach(stages) { stage in
                                    Button(stage.title) { draft.age = .estimated(stage) }
                                }
                            }
                        }
                    } label: {
                        LabeledContent("Age information", value: ageDescription)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityLabel("Age information")
                    .accessibilityValue(ageDescription)
                    .accessibilityIdentifier("pet-age-information")
                    .disabled(species == nil)

                    if case .exact(let birthday) = draft.age {
                        Button(action: openBirthday) {
                            LabeledContent("Birthday", value: birthday.formatted())
                                .fixedSize(horizontal: false, vertical: true)
                        }.accessibilityIdentifier("pet-birthday")
                    }
                } header: {
                    KinSectionHeading(text: "Age")
                }
                if original != nil {
                    Section {
                        Button("Remove pet", role: .destructive) { deleting = true }
                            .kinDestructiveText()
                            .accessibilityIdentifier("remove-pet")
                    }
                }
            }.listRowBackground(KinTheme.editableFormRow)
        }
        .kinForm()
        .navigationTitle(original == nil ? "Add pet" : "Edit pet")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            SheetEditActions(cancel: { dismiss() }, confirm: save,
                             confirmDisabled: (try? value?.validated(today: today)) == nil)
        }
        .onChange(of: speciesKind) {
            if case .estimated(let stage) = draft.age, species?.estimatedStages.contains(stage) != true {
                draft.age = .unknown
            }
        }
        .sheet(isPresented: $showBirthday) {
            NavigationStack {
                DatePicker("Birthday", selection: $suggestedBirthday, in: ...today.pickerDate, displayedComponents: .date)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .environment(\.calendar, CivilDate.pickerCalendar)
                    .environment(\.timeZone, CivilDate.pickerCalendar.timeZone)
                    .accessibilityLabel("Birthday")
                    .accessibilityIdentifier("pet-birthday-picker")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal)
                    .navigationTitle("Birthday").navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        SheetEditActions(cancel: { showBirthday = false }, confirmTitle: "Done", confirm: {
                            draft.age = .exact(CivilDate(suggestedBirthday, timeZone: CivilDate.pickerCalendar.timeZone))
                            showBirthday = false
                        })
                    }
            }.notebookAvailability(store)
        }
        .alert("Remove \(original?.name ?? "this pet")?", isPresented: $deleting) {
            Button("Remove pet", role: .destructive, action: remove).kinDestructiveText()
                .accessibilityIdentifier("confirm-remove-pet")
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes the pet’s details from this profile.")
        }
        .kinError($error)
        .notebookAvailability(store)
    }

    private var ageDescription: String {
        switch draft.age {
        case .unknown: "Unknown"
        case .exact: "Exact birthday"
        case .estimated(let stage): "Estimated: \(stage.title)"
        }
    }

    private func openBirthday() {
        if case .exact(let birthday) = draft.age { suggestedBirthday = min(birthday, today).pickerDate }
        else { suggestedBirthday = today.pickerDate }
        showBirthday = true
    }

    private func save() {
        guard let value else { return }
        do {
            try store.savePet(value, on: personID, replacing: original)
            dismiss()
        } catch {
            self.error = (error as? PetError)?.errorDescription ?? UserFacingError.message(error)
        }
    }

    private func remove() {
        guard let original else { return }
        do {
            try store.removePet(original, from: personID)
            dismiss()
        } catch {
            self.error = (error as? PetError)?.errorDescription ?? UserFacingError.message(error)
        }
    }
}
