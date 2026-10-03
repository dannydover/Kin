#if DEBUG
import SwiftUI

/// Explicit, in-memory previews support manual visual checks without touching saved data.
struct DevelopmentPreview: View {
    let store: KinStore
    let screen: String
    let today: Date
    var body: some View {
        if screen == "new-friend-sheet" { FriendAddSheetPreview(store: store) }
        else if screen == "about" || screen == "list-confirm" || screen == "list" || screen == "empty" || screen == "long-names" { ContentView(store: store) }
        else if let friend = store.friends.first(where: { $0.firstName == "Rowan" }) {
            NavigationStack {
                switch screen {
                case "friend": FriendEditor(store: store, friend: friend)
                case "new-friend": FriendEditor(store: store)
                case "partner", "partner-delete", "partner-confirm": PartnerEditor(store: store, friend: friend, partner: friend.currentPartner)
                case "new-partner": PartnerEditor(store: store, friend: friend)
                case "legacy": ChildEditor(store: store, friend: friend, child: legacyChild(in: friend), today: today)
                case "child", "child-delete", "child-confirm": ChildEditor(store: store, friend: friend, child: friend.children.first(where: { $0.birthday.isEstimated }), today: today)
                case "new-child": ChildEditor(store: store, friend: friend, today: today)
                default: FriendDetail(store: store, friendID: friend.id, today: today)
                }
            }
        }
    }
    private func legacyChild(in friend: Friend) -> Child {
        var child = friend.children[0]
        child.birthday = .legacyExact(Date(timeIntervalSince1970: 1_567_378_800))
        return child
    }
}
private struct FriendAddSheetPreview: View {
    let store: KinStore
    @State private var presented = false
    var body: some View {
        ContentView(store: store)
            .sheet(isPresented: $presented) { NavigationStack { FriendEditor(store: store) } }
            .onAppear { presented = true }
    }
}
#endif
