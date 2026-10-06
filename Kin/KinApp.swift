import SwiftUI
import UIKit
import Combine

@main
struct KinApp: App {
    @UIApplicationDelegateAdaptor(NotebookLifecycle.self) private var lifecycle
    @Environment(\.scenePhase) private var scenePhase
    @State private var store: KinStore?
    @State private var loadError: String?
    var body: some Scene {
        WindowGroup {
            Group {
                if let store {
                    #if DEBUG
                    if let previewScreen { DevelopmentPreview(store: store, screen: previewScreen, today: previewDate) }
                    else { ContentView(store: store) }
                    #else
                    ContentView(store: store)
                    #endif
                }
                else if !lifecycle.isAvailable {
                    ContentUnavailableView("Notebook locked", systemImage: "lock", description: Text("Unlock your iPhone to open Kin."))
                }
                else if let loadError {
                    ContentUnavailableView {
                        Label("Your notebook couldn’t open", systemImage: "book.closed")
                    } description: {
                        Text("Your saved data has not been reset. \(loadError)")
                    } actions: { Button("Try Again") { load() } }
                } else { ProgressView("Opening Kin…") }
            }
            .preferredColorScheme(.dark).tint(KinTheme.accent)
            .background(KinTheme.background)
            .task { if store == nil { load() } }
            .onChange(of: lifecycle.isAvailable) { _, available in
                if available && store == nil { load() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    lifecycle.refresh()
                    if store == nil { load() }
                }
            }
        }
    }
    #if DEBUG
    private var previewScreen: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--kin-preview"), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
    private var previewDate: Date { Date(timeIntervalSince1970: 1790899200) }
    #endif
    private func load() {
        #if DEBUG
        if let previewScreen {
            do {
                let preview = try KinStore(inMemory: true)
                if previewScreen != "empty" {
                    for var friend in DemoFamilies.make(on: previewDate, calendar: .current) {
                        if previewScreen == "long-names" {
                            friend.firstName = "Alexandria-Clementine"
                            friend.lastName = "Willowbrook-Montgomery"
                            for index in friend.children.indices { friend.children[index].firstName = "Christopher-Alexander" }
                        }
                        try preview.saveFriend(friend)
                    }
                }
                store = preview; loadError = nil
            } catch { loadError = error.localizedDescription }
            return
        }
        #endif
        guard lifecycle.isAvailable else { loadError = nil; return }
        do {
            let notebook = try KinStore(protectedDataAvailable: { UIApplication.shared.isProtectedDataAvailable })
            store = notebook
            lifecycle.store = notebook
            loadError = nil
        }
        catch {
            if !UIApplication.shared.isProtectedDataAvailable {
                lifecycle.refresh()
                loadError = nil
            } else { loadError = error.localizedDescription }
        }
    }
}

/// UIKit delegate callbacks run on the main actor, alongside every context save.
/// Close synchronously during the warning, rather than queueing work after lock.
@MainActor final class NotebookLifecycle: NSObject, UIApplicationDelegate, ObservableObject {
    @Published private(set) var isAvailable = UIApplication.shared.isProtectedDataAvailable
    weak var store: KinStore?

    func applicationProtectedDataWillBecomeUnavailable(_ application: UIApplication) {
        isAvailable = false
        store?.suspend()
    }
    func applicationProtectedDataDidBecomeAvailable(_ application: UIApplication) { refresh() }

    func refresh() {
        isAvailable = UIApplication.shared.isProtectedDataAvailable
        if isAvailable {
            // The store exposes a retry message on failure; never reset the notebook.
            do { try store?.resume() } catch { }
        } else { store?.suspend() }
    }
}

private struct NotebookAvailability: ViewModifier {
    let store: KinStore
    func body(content: Content) -> some View {
        content
            .accessibilityHidden(!store.isReady)
            .overlay {
                if !store.isReady {
                    ContentUnavailableView {
                        Label(store.recoveryError == nil ? "Notebook locked" : "Notebook unavailable", systemImage: "lock")
                    } description: {
                        Text(store.recoveryError ?? "Unlock your iPhone to continue. Unsaved edits stay here while Kin remains open.")
                    } actions: {
                        if store.recoveryError != nil {
                            Button("Try Again") { do { try store.resume() } catch { } }
                        }
                    }
                    .background(KinTheme.background)
                }
            }
    }
}
extension View {
    func notebookAvailability(_ store: KinStore) -> some View { modifier(NotebookAvailability(store: store)) }
}
