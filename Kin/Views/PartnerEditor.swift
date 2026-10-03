import SwiftUI
import PhotosUI

struct PartnerEditor: View {
    let store: KinStore
    let friendID: UUID
    let isNew: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var draft: Partner
    @State private var children: PartnerChildSelection
    @State private var pickingContact = false
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var photoLoading = false
    @State private var photoGeneration = UUID()
    @State private var error: String?
    @State private var replacing: String?
    @State private var deleting = false
    init(store: KinStore, friend: Friend, partner: Partner? = nil) {
        self.store = store; friendID = friend.id; isNew = partner == nil
        _draft = State(initialValue: partner ?? Partner(firstName: "", lastName: friend.lastName))
        _children = State(initialValue: PartnerChildSelection(friend: friend, partnerID: partner?.id ?? UUID()))
    }
    var body: some View {
        let photoTitle = draft.photo == nil ? "Add Photo" : "Change Photo"
        ScrollViewReader { proxy in
            Form {
                Group {
                    if !isNew { PartnerChildrenChecklist(selection: $children) }
                    if isNew {
                        Section {
                            Button { pickingContact = true } label: { Label("Import from Contacts", systemImage: "person.crop.circle.badge.plus") }
                        } footer: { Text("One-time import of a name and photo only. Nothing stays linked to Contacts.") }
                    }
                    Section("Name") {
                        TextField("First name", text: $draft.firstName).textContentType(.givenName)
                        TextField("Last name", text: $draft.lastName).textContentType(.familyName)
                    }
                    Section("Photo") {
                        (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 20)) : AnyLayout(HStackLayout(spacing: 20))) {
                            InitialAvatar(first: draft.firstName, last: draft.lastName, photo: draft.photo, gender: draft.gender, size: 64)
                            PhotosPicker(selection: $pickedPhoto, matching: .images, photoLibrary: .shared()) {
                                Label(photoTitle, systemImage: "photo")
                            }
                            if photoLoading { ProgressView().accessibilityLabel("Loading photo") }
                        }
                        if draft.photo != nil {
                            Button("Remove Photo", role: .destructive) {
                                photoGeneration = UUID(); pickedPhoto = nil; draft.photo = nil; photoLoading = false
                            }.kinDestructiveText()
                        }
                    }
                    Section {
                        GenderPicker(selection: $draft.gender)
                        Toggle("Current partner", isOn: $draft.isCurrent)
                    } footer: { Text("Only one partner can be current. Changing this alone keeps children linked to their existing parent.") }
                    if !isNew {
                        Section { Button("Delete Partner", role: .destructive) { deleting = true }.kinDestructiveText().id("delete-action") }
                        footer: { Text("Children will stay in this family with no other parent linked.") }
                    }
                }.listRowBackground(KinTheme.editableFormRow)
            }.kinForm().navigationTitle(isNew ? "Add Partner" : "Edit Partner").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }.fontWeight(.semibold)
                            .disabled(draft.firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || photoLoading)
                    }
                }
                .sheet(isPresented: $pickingContact) {
                    ContactPicker { snapshot in
                        photoGeneration = UUID(); pickedPhoto = nil; photoLoading = false
                        ContactImport.apply(snapshot, to: &draft)
                        pickingContact = false
                    } onCancel: { pickingContact = false }
                    .interactiveDismissDisabled()
                }
                .onChange(of: pickedPhoto) { _, item in
                    let generation = UUID(); photoGeneration = generation
                    guard let item else { photoLoading = false; return }
                    photoLoading = true
                    Task {
                        do {
                            guard let data = try await item.loadTransferable(type: Data.self), let photo = PhotoProcessor.thumbnail(data) else { throw PhotoError.unreadable }
                            guard photoGeneration == generation else { return }
                            draft.photo = photo
                        } catch {
                            guard photoGeneration == generation else { return }
                            self.error = "The photo couldn’t be loaded. Choose another image or try again."
                        }
                        if photoGeneration == generation { photoLoading = false }
                    }
                }
                .onDisappear { photoGeneration = UUID(); photoLoading = false }
                .confirmationDialog("Replace \(replacing ?? "partner") as current partner?", isPresented: Binding(get: { replacing != nil }, set: { if !$0 { replacing = nil } }), titleVisibility: .visible) {
                    Button("Replace Current Partner") { save(replace: true) }
                } message: { Text("The previous partner will become a former partner. Children keep their links unless you changed their selection in this editor.") }
                .confirmationDialog("Delete this partner?", isPresented: $deleting, titleVisibility: .visible) {
                    Button("Delete Partner", role: .destructive) {
                        do { try store.deletePartner(draft.id, friendID: friendID); dismiss() } catch { self.error = error.localizedDescription }
                    }
                }
                .kinError($error)
                .task {
                    #if DEBUG
                    let arguments = ProcessInfo.processInfo.arguments
                    if arguments.contains("--kin-preview") && arguments.contains("partner-delete") {
                        proxy.scrollTo("delete-action", anchor: .bottom)
                    }
                    if arguments.contains("--kin-preview") && arguments.contains("partner-confirm") {
                        deleting = true
                    }
                    #endif
                }
        }
    }
    private func save(replace: Bool = false) {
        do { try store.savePartner(draft, friendID: friendID, replaceCurrent: replace, selectedChildIDs: isNew ? nil : children.selectedIDs); dismiss() }
        catch KinError.replacementRequired(let name) { replacing = name }
        catch { self.error = error.localizedDescription }
    }
}
struct PartnerChildrenChecklist: View {
    @Binding var selection: PartnerChildSelection
    var body: some View {
        Section {
            if selection.options.isEmpty { Text("No children in this family yet.").foregroundStyle(.secondary) }
            ForEach(selection.options) { option in
                let selected = selection.selectedIDs.contains(option.id)
                Button { selection.toggle(option.id) } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(option.name).foregroundStyle(.primary)
                            Text(option.association).font(.subheadline).foregroundStyle(.secondary)
                            if option.reassigns {
                                Text(selected ? "Will move to this partner when saved" : "Selecting moves this link to this partner")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        }.fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(option.name). \(option.association)")
                .accessibilityValue(selected ? "Selected" : "Not selected")
                .accessibilityAddTraits(selected ? [.isSelected] : [])
                .accessibilityHint(option.reassigns
                    ? "Double-tap to change selection. Selecting moves the existing link to this partner when you save."
                    : "Double-tap to change selection. Changes apply when you save.")
            }
        } header: { Text("Children") }
        footer: { Text("Select all children to link to this partner. Deselecting removes only this partner’s link. Children stay in the family. Changes apply when you tap Save.") }
    }
}
struct GenderPicker: View {
    @Binding var selection: Gender
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                Text("Avatar color").accessibilityAddTraits(.isHeader)
                choice("Neutral / unknown", value: .unknown)
                choice("Blue / male", value: .male)
                choice("Pink / female", value: .female)
            }
        } else {
            Picker("Avatar color", selection: $selection) {
                Text("Neutral / unknown").tag(Gender.unknown)
                Text("Blue / male").tag(Gender.male)
                Text("Pink / female").tag(Gender.female)
            }
        }
    }
    private func choice(_ title: String, value: Gender) -> some View {
        Button { selection = value } label: {
            HStack(alignment: .top) {
                Image(systemName: selection == value ? "checkmark.circle.fill" : "circle").accessibilityHidden(true)
                Text(title).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }.buttonStyle(.plain)
            .accessibilityLabel("Avatar color, \(title)")
            .accessibilityValue(selection == value ? "Selected" : "Not selected")
            .accessibilityAddTraits(selection == value ? [.isSelected] : [])
    }
}
