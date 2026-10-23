import SwiftUI

/// The sheet explains scope; only the separate destructive confirmation can commit.
struct DeleteAllPeopleView: View {
    let store: KinStore
    let onDeleted: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirming = false
    @State private var completed = false
    @State private var error: String?
    var body: some View {
        Form {
            Section {
                Text(store.people.isEmpty ? "No people saved in this notebook." : "\(store.people.count) \(store.people.count == 1 ? "person" : "people") saved in this notebook.")
                    .accessibilityIdentifier("delete-all-count")
                Text("Delete every person saved in this Kin notebook, including people not shown in your list, and all their relationships, notes and photos.")
                Text("This affects only this notebook on this device. It keeps unrelated settings, source Contacts, external copies and backups. There is no undo in Kin.")
            } header: { Text("What will be deleted") }
            Section {
                Button("Delete all people", role: .destructive) { confirming = true }
                    .kinDestructiveText().accessibilityIdentifier("review-delete-all")
                    .disabled(store.people.isEmpty || !store.isReady || completed)
            }
        }
        .kinForm().navigationTitle("Delete all people").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        .alert("Delete all people?", isPresented: $confirming) {
            Button("Delete all people", role: .destructive) { delete() }
                .kinDestructiveText().accessibilityIdentifier("confirm-delete-all")
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Permanently delete every saved person in this Kin notebook, including hidden people, and their relationships, notes and photos? Contacts, external copies, backups and unrelated settings are kept. There is no undo in Kin.")
        }
        .kinError($error).notebookAvailability(store)
    }
    private func delete() {
        guard !completed else { return }
        do {
            try store.deleteAllPeople()
            completed = true
            onDeleted()
        } catch {
            self.error = "Kin couldn’t confirm the deletion. Reopen your notebook to check what remains before trying again."
        }
    }
}
