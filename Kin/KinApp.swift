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
                    ContentView(store: store)
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
    private func load() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--kin-preview") {
            do { store = try KinStore(inMemory: true); loadError = nil } catch { loadError = error.localizedDescription }
            return
        }
        if let index = arguments.firstIndex(of: "--kin-test-notebook") {
            guard arguments.indices.contains(index + 1), let token = UUID(uuidString: arguments[index + 1]) else {
                loadError = "The isolated test notebook identifier is invalid. The saved notebook has not been opened."
                return
            }
            do {
                let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
                let url = root.appendingPathComponent("KinTestNotebooks").appendingPathComponent(token.uuidString).appendingPathComponent("Kin.sqlite")
                let notebook = try KinStore(storeURL: url, protectedDataAvailable: { UIApplication.shared.isProtectedDataAvailable })
                store = notebook; lifecycle.store = notebook; loadError = nil
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
