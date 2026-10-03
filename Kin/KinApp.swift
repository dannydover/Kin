import SwiftUI

@main
struct KinApp: App {
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
        do { store = try KinStore(); loadError = nil }
        catch { loadError = error.localizedDescription }
    }
}
