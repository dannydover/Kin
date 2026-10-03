import SwiftUI
import PhotosUI

struct FriendEditor: View {
    let store: KinStore
    private let isNew: Bool
    private let importFirst: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var draft: Friend
    @State private var pickingContact = false
    @State private var didOfferImport = false
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var photoLoading = false
    @State private var photoGeneration = UUID()
    @State private var error: String?
    init(store: KinStore, friend: Friend? = nil, importFirst: Bool = false) {
        self.store = store; self.isNew = friend == nil; self.importFirst = importFirst
        _draft = State(initialValue: friend ?? Friend(firstName: "", lastName: ""))
    }
    var body: some View {
        let photoTitle = draft.photo == nil ? "Add Photo" : "Change Photo"
        Form {
            Group {
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
                        InitialAvatar(first: draft.firstName, last: draft.lastName, photo: draft.photo, size: 64)
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
                Section("Notes") { TextField("The little things to remember", text: $draft.notes, axis: .vertical).lineLimit(4...10) }
                if isNew { Section { Text("After saving, open their family to add partners and children.").foregroundStyle(KinTheme.secondary) } }
            }.listRowBackground(KinTheme.editableFormRow)
        }.kinForm().navigationTitle(isNew ? "Add Friend" : "Edit Friend").navigationBarTitleDisplayMode(.inline)
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
            .onAppear { if importFirst && !didOfferImport { didOfferImport = true; pickingContact = true } }
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
            .kinError($error)
    }
    private func save() {
        do { try store.saveFriend(draft); UIImpactFeedbackGenerator(style: .light).impactOccurred(); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}
