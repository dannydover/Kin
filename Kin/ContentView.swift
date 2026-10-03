import SwiftUI

struct ContentView: View {
    let store: KinStore
    @State private var query = ""
    private enum AddRoute: String, Identifiable { case manual, contacts; var id: String { rawValue } }
    @State private var adding: AddRoute?
    @State private var showingAbout = false
    @State private var deletion: Friend?
    @State private var error: String?
    @State private var today = Date()
    @Environment(\.scenePhase) private var scenePhase
    private var hits: [SearchHit] { FamilySearch.results(in: store.friends, query: query) }

    var body: some View {
        NavigationStack {
            Group {
                if store.friends.isEmpty && query.isEmpty { emptyState }
                else if hits.isEmpty {
                    ContentUnavailableView { Label("No matches", systemImage: "magnifyingglass") }
                    description: { Text("No matches for “\(query)”. Try a friend, partner, or child’s name.") }
                } else {
                    List {
                        if query.isEmpty {
                            Text("A little context. A closer connection.")
                                .font(.subheadline).foregroundStyle(KinTheme.secondary)
                                .listRowBackground(KinTheme.background).listRowSeparator(.hidden)
                        }
                        ForEach(hits) { hit in
                            if let friend = store.friends.first(where: { $0.id == hit.friendID }) {
                                NavigationLink(value: friend.id) {
                                    if let subtitle = hit.subtitle {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(hit.title).font(.headline).fontDesign(.serif)
                                            Text(subtitle).font(.caption).foregroundStyle(KinTheme.secondary)
                                        }.padding(.vertical, 12)
                                    } else { FriendRow(friend: friend, today: today) }
                                }
                                .listRowBackground(KinTheme.background)
                                .listRowSeparatorTint(KinTheme.border)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    if hit.allowsFamilyDeletion {
                                        Button("Delete Friend", role: .destructive) { deletion = friend }
                                    }
                                }
                            }
                        }
                    }.listStyle(.plain).scrollContentBackground(.hidden)
                }
            }
            .background(KinTheme.background).foregroundStyle(KinTheme.text)
            .navigationTitle("Kin").navigationBarTitleDisplayMode(.inline)
            .kinSearch(enabled: !store.friends.isEmpty, query: $query)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingAbout = true } label: { Image(systemName: "info.circle") }
                        .accessibilityLabel("About Kin")
                        .accessibilityHint("Includes the Privacy Policy link")
                }
                ToolbarItem(placement: .principal) { Text("Kin").font(.title).fontDesign(.serif).foregroundStyle(KinTheme.text).accessibilityAddTraits(.isHeader) }
                ToolbarItem(placement: .primaryAction) {
                    Button { adding = .manual } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add friend")
                }
            }
            .navigationDestination(for: UUID.self) { id in FriendDetail(store: store, friendID: id, today: today) }
            .sheet(item: $adding) { route in NavigationStack { FriendEditor(store: store, importFirst: route == .contacts) } }
            .sheet(isPresented: $showingAbout) { AboutKinView() }
            .confirmationDialog("Delete \(deletion?.fullName ?? "friend") and their family?", isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } }), titleVisibility: .visible) {
                Button("Delete Friend and Family", role: .destructive) {
                    if let deletion { do { try store.deleteFriend(deletion.id) } catch { self.error = error.localizedDescription } }
                    deletion = nil
                }
            } message: { Text("Their partners, children, photos, and notes will be removed from Kin. This cannot be undone.") }
            .kinError($error)
            .task {
                #if DEBUG
                let arguments = ProcessInfo.processInfo.arguments
                if arguments.contains("--kin-preview") && arguments.contains("list-confirm") { deletion = store.friends.first }
                if arguments.contains("--kin-preview") && arguments.contains("about") { showingAbout = true }
                #endif
            }
            .onChange(of: scenePhase) { _, phase in if phase == .active { today = Date() } }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in today = Date() }
        }
    }
    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image("notebook").renderingMode(.template).resizable().scaledToFit()
                    .foregroundStyle(KinTheme.accent).frame(width: 124, height: 124).accessibilityHidden(true)
                VStack(spacing: 12) {
                    Text("Keep your people close.").font(.largeTitle).fontDesign(.serif).multilineTextAlignment(.center)
                    Text("A small notebook for your friends’ families. Names, ages, and the little things you want to remember.")
                        .font(.body).foregroundStyle(KinTheme.secondary).multilineTextAlignment(.center)
                }
                Text("Add your first friend").font(.title3).fontDesign(.serif).padding(.top, 12)
                VStack(spacing: 12) {
                    Button { adding = .contacts } label: { Label("Import from Contacts", systemImage: "person.crop.circle.badge.plus").frame(maxWidth: .infinity, minHeight: 44) }
                    Button { adding = .manual } label: { Label("Add Manually", systemImage: "square.and.pencil").frame(maxWidth: .infinity, minHeight: 44) }
                }.buttonStyle(.bordered).controlSize(.large)
                Label("Private, on your iPhone", systemImage: "lock").font(.caption).foregroundStyle(KinTheme.secondary)
            }.padding(28).padding(.top, 32).frame(maxWidth: 520).frame(maxWidth: .infinity)
        }
    }
}
private struct AboutKinView: View {
    @Environment(\.dismiss) private var dismiss
    private let appVersion = AppVersion()
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 24) {
                            VStack(spacing: 12) {
                                Image("KinLogo").resizable().scaledToFit()
                                    .frame(width: 64, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                    .accessibilityHidden(true)
                                Text(appVersion.displayText)
                                    .font(.footnote)
                                    .foregroundStyle(KinTheme.secondary)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityLabel(appVersion.accessibilityLabel)
                            }
                            .frame(maxWidth: .infinity)
                            Link(destination: URL(string: "https://www.intriguingideas.com/kin-privacy-policy")!) {
                                Label("Privacy Policy", systemImage: "arrow.up.right.square")
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .padding(16)
                                    .background(KinTheme.field, in: RoundedRectangle(cornerRadius: 22))
                            }
                            .accessibilityHint("Opens the Kin Privacy Policy in your browser")
                            Spacer(minLength: 24)
                            VStack(spacing: 8) {
                                Image(systemName: "heart.fill")
                                    .font(.subheadline)
                                    .foregroundStyle(KinTheme.ink(.female))
                                    .accessibilityHidden(true)
                                Text("Made by an indie developer")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(KinTheme.secondary)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity)
                            .id("indie-message")
                        }
                        .frame(minHeight: max(0, geometry.size.height - 48))
                        .padding(24)
                    }
                    .task {
                        #if DEBUG
                        let arguments = ProcessInfo.processInfo.arguments
                        if arguments.contains("--kin-preview") && arguments.contains("--about-bottom") {
                            proxy.scrollTo("indie-message", anchor: .bottom)
                        }
                        #endif
                    }
                }
            }
            .kinForm()
            .navigationTitle("About Kin").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        #if DEBUG
        .presentationDetents(ProcessInfo.processInfo.arguments.contains("--kin-preview") && ProcessInfo.processInfo.arguments.contains("--about-compact") ? [.height(420)] : [.large])
        #endif
    }
}
struct FriendRow: View {
    let friend: Friend
    let today: Date
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var previewAvatarSize = 40.0
    private var rules: AgeRules { AgeRules(calendar: CivilDate.gregorian(in: .current)) }
    var body: some View {
        (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout(alignment: .top, spacing: 16))) {
            InitialAvatar(first: friend.firstName, last: friend.lastName, photo: friend.photo)
            VStack(alignment: .leading, spacing: 10) {
                Text(friend.fullName).font(.headline).fontDesign(.serif).fixedSize(horizontal: false, vertical: true)
                if friend.children.isEmpty {
                    Text(friend.currentPartner.map { "With \($0.fullName)" } ?? "No children added yet")
                        .font(.subheadline).foregroundStyle(KinTheme.secondary)
                } else {
                    LazyVGrid(columns: typeSize.isAccessibilitySize ? [GridItem(.flexible(), alignment: .leading)] : [GridItem(.adaptive(minimum: 125), alignment: .leading)], alignment: .leading, spacing: 12) {
                        previews
                    }
                }
            }
        }.padding(.vertical, 16)
    }
    @ViewBuilder private var previews: some View {
        ForEach(friend.children.prefix(3)) { child in
            (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(spacing: 8))) {
                if let age = rules.age(for: child.birthday, on: today) {
                    ChildAvatar(stage: .forAge(age), gender: child.gender, size: previewAvatarSize)
                } else {
                    Image(systemName: "calendar.badge.exclamationmark").frame(width: previewAvatarSize, height: previewAvatarSize).foregroundStyle(KinTheme.secondary).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(child.firstName).font(.subheadline).foregroundStyle(KinTheme.secondary).fixedSize(horizontal: false, vertical: true)
                    Text(rules.displayAge(for: child.birthday, on: today)).font(.title3).fontDesign(.serif).foregroundStyle(KinTheme.text)
                }
            }.accessibilityElement(children: .ignore)
                .accessibilityLabel(ageLabel(for: child))
        }
        if friend.children.count > 3 { Text("+\(friend.children.count - 3) more").font(.caption).foregroundStyle(KinTheme.secondary) }
    }
    private func ageLabel(for child: Child) -> String {
        guard let age = rules.age(for: child.birthday, on: today) else { return "\(child.firstName), date needs review" }
        return "\(child.firstName), \(child.birthday.isEstimated ? "approximately " : "")\(age) years old"
    }
}
