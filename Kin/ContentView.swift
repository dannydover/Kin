import SwiftUI

struct ContentView: View {
    let store: KinStore
    private enum PeopleScope { case yours, all }
    @State private var scope = PeopleScope.yours
    @State private var query = ""
    @State private var adding = false
    @State private var path: [UUID] = []
    @State private var savedPersonID: UUID?
    @State private var showingAbout = false
    @State private var deletingAll = false
    @State private var today = Date()
    @Environment(\.scenePhase) private var scenePhase
    private var hits: [Person] { PeopleIndex.results(store.people, query: query, includeUnlisted: scope == .all) }
    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if hits.isEmpty {
                    if isSearching { noMatches }
                    else { emptyState }
                } else {
                    List(hits) { person in
                        NavigationLink(value: person.id) {
                            if scope == .yours { FamilyIndexRow(person: person, store: store, today: today) }
                            else { PersonRow(person: person, today: today, showsAge: false) }
                        }
                        .listRowBackground(KinTheme.background)
                        .listRowSeparatorTint(KinTheme.border)
                    }.listStyle(.plain)
                }
            }
            .kinForm().navigationTitle(scope == .yours ? "Kin" : "All people").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: scope == .yours ? "Find your people" : "Find all people")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("Your people", systemImage: scope == .yours ? "checkmark" : "person.2") { switchScope(.yours) }
                        Button("All people", systemImage: scope == .all ? "checkmark" : "person.3") { switchScope(.all) }
                        Button("About", systemImage: "info.circle") { showingAbout = true }
                        Button("Delete all people", systemImage: "trash", role: .destructive) { deletingAll = true }
                    } label: { Image(systemName: "line.3.horizontal") }
                    .accessibilityLabel("Navigation menu")
                    .accessibilityHint(scope == .yours ? "Showing Your people" : "Showing All people")
                    .accessibilityIdentifier("people-menu")
                }
                ToolbarItem(placement: .primaryAction) { Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add person") }
            }
            .navigationDestination(for: UUID.self) { id in PersonDetail(store: store, personID: id, today: today).id(id) }
            .sheet(isPresented: $adding, onDismiss: {
                if let id = savedPersonID {
                    savedPersonID = nil
                    path.append(id)
                }
            }) { NavigationStack { PersonEditor(store: store,onPersonSaved: { savedPersonID = $0 }) } }
            .sheet(isPresented: $showingAbout) { AboutKinView() }
            .sheet(isPresented: $deletingAll) {
                NavigationStack {
                    DeleteAllPeopleView(store: store) {
                        path = []; query = ""; scope = .yours; deletingAll = false
                    }
                }
            }
            .onChange(of: scenePhase) { _, phase in if phase == .active { today = Date() } }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in today = Date() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in today = Date() }
        }.notebookAvailability(store)
    }
    private func switchScope(_ selection: PeopleScope) { scope = selection; query = "" }
    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image("notebook").renderingMode(.template).resizable().scaledToFit()
                    .foregroundStyle(KinTheme.accent).frame(width: 124, height: 124).accessibilityHidden(true)
                VStack(spacing: 12) {
                    Text(store.people.isEmpty ? "Keep your people close." : "Your people is empty")
                        .font(.largeTitle).fontDesign(.serif).multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    Text(store.people.isEmpty
                         ? "Names, ages, and the little things you want to remember. A small, private notebook for the people in your life."
                         : "Turn on Show in Your people on a profile to include them here. Everyone you’ve saved is in All people in the menu.")
                        .font(.body).foregroundStyle(KinTheme.secondary).multilineTextAlignment(.center)
                }.fixedSize(horizontal: false, vertical: true)
                if store.people.isEmpty {
                    Button { adding = true } label: {
                        Label("Add your first person", systemImage: "plus").foregroundStyle(KinTheme.background).frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.borderedProminent).controlSize(.large)
                } else {
                    Button { switchScope(.all) } label: {
                        Label("Browse all people", systemImage: "person.3").frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.bordered).controlSize(.large)
                }
                Label("Private, on your iPhone", systemImage: "lock")
                    .font(.caption).foregroundStyle(KinTheme.secondary)
            }.padding(28).padding(.top, 32).frame(maxWidth: 520).frame(maxWidth: .infinity)
        }
    }
    private var noMatches: some View {
        ContentUnavailableView {
            Label("No matches", systemImage: "magnifyingglass")
        } description: {
            Text(scope == .yours ? "Try another name or a label like Child 2. Search All people for anyone outside Your people." : "Try another name or a label like Child 2.")
        } actions: {
            if scope == .yours { Button("Search all people") { scope = .all } }
        }
    }
}
/// Index previews follow explicit parent links only; partner links imply no children.
struct FamilyIndexRow: View {
    let person: Person
    let store: KinStore
    let today: Date
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var previewAvatarSize = 40.0
    @ScaledMetric(relativeTo: .subheadline) private var childCellMinimum = 150.0
    private var rules: AgeRules { AgeRules(calendar: .current) }
    private var children: [Person] {
        let ids = Set(store.parentLinks.filter { $0.parentID == person.id }.map(\.childID))
        return store.people.filter { ids.contains($0.id) }.sorted { $0.reference < $1.reference }
    }
    private var partners: [Person] {
        let ids = Set(store.partnerLinks.filter { ($0.firstID == person.id || $0.secondID == person.id) && $0.status == .current }.map { $0.other(than: person.id) })
        return store.people.filter { ids.contains($0.id) }.sorted { $0.reference < $1.reference }
    }
    var body: some View {
        (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout(alignment: .top, spacing: 16))) {
            PersonAvatar(person: person, today: today)
            VStack(alignment: .leading, spacing: 10) {
                Text(person.displayName).font(.headline).fontDesign(.serif).fixedSize(horizontal: false, vertical: true)
                if children.isEmpty {
                    Text(partners.isEmpty ? "No children added yet" : "With " + partners.map(\.displayName).joined(separator: ", "))
                        .font(.subheadline).foregroundStyle(KinTheme.secondary).fixedSize(horizontal: false, vertical: true)
                } else {
                    LazyVGrid(columns: typeSize.isAccessibilitySize ? [GridItem(.flexible(), alignment: .leading)] : [GridItem(.adaptive(minimum: childCellMinimum), alignment: .leading)], alignment: .leading, spacing: 12) {
                        ForEach(children.prefix(3)) { child in
                            let unknownAge = rules.age(for: child.birthday, on: today) == nil
                            (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(spacing: 8))) {
                                PersonAvatar(person: child, today: today, size: previewAvatarSize)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(child.displayName).font(.subheadline).foregroundStyle(KinTheme.secondary)
                                    Text(rules.displayAge(for: child.birthday, on: today)).font(.subheadline).foregroundStyle(KinTheme.secondary)
                                        .lineLimit(unknownAge && !typeSize.isAccessibilitySize ? 1 : nil)
                                        .fixedSize(horizontal: unknownAge && !typeSize.isAccessibilitySize, vertical: true)
                                        .layoutPriority(1)
                                    if let grade = rules.grade(for: child.birthday, on: today) {
                                        Text("Approx. " + grade).font(.caption).foregroundStyle(KinTheme.secondary)
                                    }
                                }.fixedSize(horizontal: false, vertical: true)
                            }.accessibilityElement(children: .combine)
                                .accessibilityIdentifier("child-preview-" + child.id.uuidString)
                        }
                        if children.count > 3 { Text("+\(children.count - 3) more").font(.caption).foregroundStyle(KinTheme.secondary) }
                    }
                }
            }
        }.padding(.vertical, 16)
    }
}
struct PersonAvatar: View {
    let person: Person
    let today: Date
    var size: CGFloat = 48
    var body: some View {
        if let age = AgeRules(calendar: .current).age(for: person.birthday, on: today), age < 18 {
            ChildAvatar(stage: .forAge(age), gender: person.gender, size: size)
        } else {
            InitialAvatar(first: person.firstName ?? "?", last: person.lastName ?? "", photo: person.visiblePhoto(on: today), gender: person.gender, size: size)
        }
    }
}
struct PersonRow: View {
    let person: Person
    let today: Date
    var showsAge = true
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 16))) {
            PersonAvatar(person: person, today: today)
            VStack(alignment: .leading, spacing: 5) {
                Text(person.displayName).font(.headline).fontDesign(.serif)
                if showsAge { Text(AgeRules(calendar: .current).displayAge(for: person.birthday, on: today)).font(.subheadline).foregroundStyle(KinTheme.secondary) }
            }
        }.padding(.vertical, 8)
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
                            Link(destination: URL(string: "https://www.intriguingideas.com/kin-privacy-policy")!) {
                                Label("Privacy Policy", systemImage: "arrow.up.right.square")
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                    .padding(16)
                                    .background(KinTheme.field, in: RoundedRectangle(cornerRadius: 22))
                            }
                            .accessibilityHint("Opens the Kin Privacy Policy in your browser")
                            .accessibilityIdentifier("about-privacy-policy")
                            .id("privacy-policy")
                        }
                        .frame(minHeight: max(0, geometry.size.height - 48))
                        .padding(24)
                    }
                    .task {
                        #if DEBUG
                        let arguments = ProcessInfo.processInfo.arguments
                        if arguments.contains("--kin-preview") && arguments.contains("--about-bottom") {
                            proxy.scrollTo("privacy-policy", anchor: .bottom)
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
