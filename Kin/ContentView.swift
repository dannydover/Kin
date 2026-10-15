import SwiftUI

struct ContentView: View {
    let store: KinStore
    @State private var query = ""
    @State private var adding = false
    @State private var showingAbout = false
    @State private var today = Date()
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink("All people (including unlisted)") { AllPeopleView(store: store, today: today) }
                } footer: { Text("People with a connection appear below. All people also includes entries saved through linked profiles.") }
                Section("Your people") {
                    let hits = PeopleIndex.results(store.people, query: query)
                    if hits.isEmpty { Text(query.isEmpty ? "Add a person and choose your connection." : "No matches. Search All people for unlisted entries.").foregroundStyle(KinTheme.secondary) }
                    ForEach(hits) { person in
                        NavigationLink(value: person.id) { PersonRow(person: person, today: today) }
                    }
                }
            }
            .kinForm().navigationTitle("Kin").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Find your people")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button { showingAbout = true } label: { Image(systemName: "info.circle") }.accessibilityLabel("About Kin") }
                ToolbarItem(placement: .primaryAction) { Button { adding = true } label: { Image(systemName: "plus") }.accessibilityLabel("Add person") }
            }
            .navigationDestination(for: UUID.self) { id in PersonDetail(store: store, personID: id, today: today).id(id) }
            .sheet(isPresented: $adding) { NavigationStack { PersonEditor(store: store) } }
            .sheet(isPresented: $showingAbout) { AboutKinView() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { today = Date() } }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in today = Date() }
        }.notebookAvailability(store)
    }
}
struct AllPeopleView: View {
    let store: KinStore
    let today: Date
    @State private var query = ""
    var body: some View {
        List(PeopleIndex.results(store.people, query: query, includeUnlisted: true)) { person in
            NavigationLink(value: person.id) { PersonRow(person: person, today: today) }
        }.kinForm().navigationTitle("All people").searchable(text: $query, prompt: "Name or stable entry label")
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
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 16))) {
            PersonAvatar(person: person, today: today)
            VStack(alignment: .leading, spacing: 5) {
                Text(person.displayName).font(.headline).fontDesign(.serif)
                if person.nameUnknown { Text("Name unknown").font(.caption) }
                Text(AgeRules(calendar: .current).displayAge(for: person.birthday, on: today)).font(.subheadline).foregroundStyle(KinTheme.secondary)
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
