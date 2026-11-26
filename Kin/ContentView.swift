import SwiftUI

struct ContentView: View {
    let store: KinStore
    @State private var filter = PeopleFilterState()
    @State private var adding = false
    @State private var path: [UUID] = []
    @State private var savedPersonID: UUID?
    @State private var showingAbout = false
    @State private var exportingContacts = false
    @State private var deletingAll = false
    @State private var today = Date()
    @Environment(\.scenePhase) private var scenePhase
    private var hits: [Person] { filter.results(store.people) }
    private var showsCategoryFilter: Bool { filter.hasCategories(store.people) }
    private var isSearching: Bool { filter.isSearching }
    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if hits.isEmpty {
                    if isSearching { noMatches }
                    else if filter.category != nil { emptyCategory }
                    else { emptyState }
                } else {
                    List(hits) { person in
                        let sideInset: CGFloat = filter.scope == .all ? 20 : 16
                        let family = FamilyIndexRow(person: person, store: store, today: today)
                        NavigationLink(value: person.id) {
                            if filter.scope == .yours {
                                HStack(spacing: 10) {
                                    family
                                    disclosureChevron
                                }
                            } else { allPeopleCard(person) }
                        }
                        .accessibilityLabel(Text(verbatim: filter.scope == .yours ? family.spokenSummary : person.displayName))
                        .navigationLinkIndicatorVisibility(.hidden)
                        .listRowInsets(EdgeInsets(top: 5, leading: sideInset, bottom: 5, trailing: sideInset))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }.listStyle(.plain)
                }
            }
            .kinForm().navigationTitle(filter.scope == .yours ? "People" : "All people").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $filter.query, isPresented: $filter.searching, placement: .navigationBarDrawer(displayMode: .always), prompt: filter.scope == .yours ? "Find people" : "Find all people")
            .safeAreaInset(edge: .top, spacing: 0) {
                if showsCategoryFilter { categoryFilter }
            }
            .onChange(of: showsCategoryFilter) { _, shown in
                if !shown { filter.category = nil }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if filter.scope == .yours { KinTitle(text: "Kin", size: 28).accessibilityAddTraits(.isHeader) }
                    else { KinTitle(text: "All people", size: 19).accessibilityAddTraits(.isHeader) }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("People", systemImage: filter.scope == .yours ? "checkmark" : "person.2") { switchScope(.yours) }
                        Button("All people", systemImage: filter.scope == .all ? "checkmark" : "person.3") { switchScope(.all) }
                        Button("Export to Contacts", systemImage: "person.crop.rectangle") { exportingContacts = true }
                            .disabled(store.people.isEmpty)
                        Button("About", systemImage: "info.circle") { showingAbout = true }
                        Button("Delete all people", systemImage: "trash", role: .destructive) { deletingAll = true }
                    } label: { Image(systemName: "line.3.horizontal") }
                    .accessibilityLabel("Navigation menu")
                    .accessibilityHint(filter.scope == .yours ? "Showing People" : "Showing All people")
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
            .sheet(isPresented: $exportingContacts) { NavigationStack { ContactExportView(store: store) } }
            .sheet(isPresented: $showingAbout) { AboutKinView() }
            .sheet(isPresented: $deletingAll) {
                NavigationStack {
                    DeleteAllPeopleView(store: store) {
                        path = []; filter.switchScope(.yours); deletingAll = false
                    }
                }
            }
            .onChange(of: scenePhase) { _, phase in if phase == .active { today = Date() } }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in today = Date() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in today = Date() }
        }.notebookAvailability(store)
    }
    private func allPeopleCard(_ person: Person) -> some View {
        HStack(spacing: 12) {
            PersonRow(person: person, today: today, showsAge: false)
                .frame(maxWidth: .infinity, alignment: .leading)
            disclosureChevron
        }
        .padding(12)
        .kinPanel()
        .contentShape(Rectangle())
    }

    private var disclosureChevron: some View {
        Image(systemName: "chevron.right")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(KinTheme.secondary)
            .accessibilityHidden(true)
    }

    private func switchScope(_ selection: PeopleFilterState.Scope) { filter.switchScope(selection) }
    private var categoryFilter: some View {
        Menu {
            Button("All", systemImage: filter.category == nil ? "checkmark" : "person.2") { filter.category = nil }
                .accessibilityAddTraits(filter.category == nil ? .isSelected : [])
            ForEach(Connection.allCases) { connection in
                Button(connection.rawValue.capitalized, systemImage: filter.category == connection ? "checkmark" : "person") { filter.category = connection }
                    .accessibilityAddTraits(filter.category == connection ? .isSelected : [])
            }
        } label: {
            Label(filter.category?.rawValue.capitalized ?? "All", systemImage: "line.3.horizontal.decrease")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .kinPanel(radius: 22)
                .frame(maxWidth: .infinity)
        }
        .accessibilityLabel("Category filter")
        .accessibilityValue(filter.category?.rawValue.capitalized ?? "All")
        .accessibilityIdentifier("category-filter")
        .padding(.bottom, 6)
    }
    private var emptyCategory: some View {
        filteredEmptyState(title: Text("No people in this category"), image: "person.2",
            explanation: Text("No one matches the selected category. Tap \(FeatureReference.clearSearchAndFilters) to return to the \(FeatureReference.people) screen."))
    }
    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image("notebook").renderingMode(.template).resizable().scaledToFit()
                    .foregroundStyle(KinTheme.accent).frame(width: 124, height: 124).accessibilityHidden(true)
                VStack(spacing: 12) {
                    Text(store.people.isEmpty ? "Keep your people close." : "Your main list is empty")
                        .font(.largeTitle).fontDesign(.serif).multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    Group {
                        if store.people.isEmpty {
                            Text("Names, ages, and the little things you want to remember. A small, private notebook for the people in your life.")
                        } else {
                            Text("Open a profile, tap \(FeatureReference.edit), then turn on the \(FeatureReference.showOnMainList) setting. Everyone you’ve saved is on the \(FeatureReference.allPeople) screen in the navigation menu.")
                        }
                    }.font(.body).foregroundStyle(KinTheme.secondary).multilineTextAlignment(.center)
                }.fixedSize(horizontal: false, vertical: true)
                if store.people.isEmpty {
                    RelationshipProfileAction(title: "Add your first person", systemImage: "plus") { adding = true }
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
        filteredEmptyState(title: Text("No matches"), image: "magnifyingglass",
            explanation: Text("Try another name, such as Alex Morgan. Tap \(FeatureReference.clearSearchAndFilters) to return to the \(FeatureReference.people) screen."),
            offersAllPeople: filter.scope == .yours)
    }
    private func filteredEmptyState(title: Text, image: String, explanation: Text,
                                    offersAllPeople: Bool = false) -> some View {
        GeometryReader { geometry in
            ScrollView {
                // Keep the complete explanation in scrollable content, including
                // when the keyboard and accessibility text leave a short viewport.
                VStack(spacing: 16) {
                    Image(systemName: image).font(.system(size: 48)).foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    title.font(.title2.bold()).accessibilityAddTraits(.isHeader)
                    explanation.foregroundStyle(.secondary)
                        .accessibilityIdentifier("filtered-empty-explanation")
                    if offersAllPeople { Button("Search all people") { filter.scope = .all } }
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(24)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }.accessibilityIdentifier("filtered-empty-content")
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            clearSearchAndFiltersButton.padding(16).background(KinTheme.background)
        }
    }
    private var clearSearchAndFiltersButton: some View {
        Button {
            filter.clearSearchAndFilters()
        } label: {
            ConfirmationLabel(title: "Clear search and filters", fillsWidth: true)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("clear-search-and-filters")
        .accessibilityHint("Clears the search and category filter and returns to the People screen.")
    }
}
/// Index previews follow explicit parent links only; partner links imply no children.
struct FamilyIndexRow: View {
    let person: Person
    let store: KinStore
    let today: Date
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var adultSize = 40.0
    @ScaledMetric(relativeTo: .body) private var childSize = 34.0
    private let avatarTextSpacing: CGFloat = 12
    private var rules: AgeRules { AgeRules(calendar: .current) }
    private let childPreviewLimit = 4
    private var children: [Person] {
        let ids = Set(store.parentLinks.filter { $0.parentID == person.id }.map(\.childID))
        return store.people.filter { ids.contains($0.id) }.sorted { $0.reference < $1.reference }
    }
    private var partners: [Person] {
        let ids = Set(store.partnerLinks.filter { ($0.firstID == person.id || $0.secondID == person.id) && $0.status == .current }.map { $0.other(than: person.id) })
        return store.people.filter { ids.contains($0.id) }.sorted { $0.reference < $1.reference }
    }
    private var partnerSummary: String? {
        guard !partners.isEmpty else { return nil }
        return (partners.count == 1 ? "Partner: " : "Partners: ") + partners.map(\.displayName).joined(separator: ", ")
    }

    var spokenSummary: String {
        var details = [person.displayName]
        if let partnerSummary { details.append(partnerSummary) }
        let children = children
        if children.isEmpty, partnerSummary == nil { details.append("No children added yet") }
        for child in children.prefix(childPreviewLimit) {
            var preview = [child.displayName, spokenAgeOrGrade(rules.displayAge(for: child.birthday, on: today))]
            if let grade = rules.grade(for: child.birthday, on: today) {
                preview.append(spokenAgeOrGrade(grade))
            }
            details.append(preview.joined(separator: ", "))
        }
        if children.count > childPreviewLimit {
            let remaining = children.count - childPreviewLimit
            details.append(remaining == 1 ? "1 more child" : "\(remaining) more children")
        }
        return details.joined(separator: ". ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: avatarTextSpacing))) {
                PersonAvatar(person: person, today: today, size: adultSize)
                VStack(alignment: .leading, spacing: 1) {
                    KinTitle(text: person.displayName)
                        .foregroundStyle(KinTheme.text)
                        .background(KinTheme.surface)
                    if !partners.isEmpty {
                        Text((partners.count == 1 ? "Partner · " : "Partners · ") + partners.map(\.displayName).joined(separator: ", "))
                            .font(.subheadline).foregroundStyle(KinTheme.secondary)
                    } else if children.isEmpty {
                        Text("No children added yet").font(.subheadline).foregroundStyle(KinTheme.secondary)
                    }
                }.fixedSize(horizontal: false, vertical: true)
            }
            if !children.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .topLeading),
                                         count: typeSize.isAccessibilitySize ? 1 : 2), alignment: .leading, spacing: 12) {
                    ForEach(children.prefix(childPreviewLimit)) { child in
                        (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) :
                            AnyLayout(HStackLayout(alignment: .top, spacing: avatarTextSpacing))) {
                            PersonAvatar(person: child, today: today, size: childSize, childCircle: true)
                                .frame(width: adultSize)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(child.displayName).font(.subheadline).foregroundStyle(KinTheme.secondary)
                                KinTitle(text: rules.displayAge(for: child.birthday, on: today), size: 14)
                                if let grade = rules.grade(for: child.birthday, on: today) {
                                    SchoolGradeLabel(grade: grade).font(.caption).foregroundStyle(KinTheme.secondary)
                                }
                            }.fixedSize(horizontal: false, vertical: true)
                        }.accessibilityElement(children: .combine)
                            .accessibilityIdentifier("child-preview-" + child.id.uuidString)
                    }
                    if children.count > childPreviewLimit { Text("+\(children.count - childPreviewLimit) more").font(.caption).foregroundStyle(KinTheme.secondary) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .kinPanel()
    }
}
struct PersonAvatar: View {
    let person: Person
    let today: Date
    var size: CGFloat = 48
    var childCircle = false
    var body: some View {
        let age = AgeRules(calendar: .current).age(for: person.birthday, on: today)
        InitialAvatar(first: person.firstName ?? "", last: person.lastName ?? "",
                      photo: person.visiblePhoto(on: today), gender: person.gender, size: size,
                      isChild: childCircle || (age.map { $0 < 18 } ?? false))
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
                KinTitle(text: person.displayName, size: 17)
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
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(spacing: 14) {
                            Image("KinLogo").resizable().scaledToFit()
                                .frame(width: 74, height: 74)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .accessibilityHidden(true)
                            Text(appVersion.displayText)
                                .font(.subheadline)
                                .foregroundStyle(KinTheme.secondary)
                                .accessibilityLabel(appVersion.accessibilityLabel)
                            HStack(spacing: 8) {
                                Image(systemName: "heart.fill")
                                    .foregroundStyle(KinTheme.ink(.female))
                                    .accessibilityHidden(true)
                                Text("Made by an indie developer")
                                    .foregroundStyle(KinTheme.secondary)
                            }
                            .font(.subheadline.weight(.semibold))
                            .padding(.top, 6)
                        }
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                        Divider()
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Privacy & data")
                                .font(.headline)
                                .accessibilityAddTraits(.isHeader)
                            Link(destination: URL(string: "https://www.intriguingideas.com/kin-privacy-policy")!) {
                                HStack {
                                    Text("Privacy Policy")
                                    Spacer()
                                    Image(systemName: "arrow.up.right")
                                        .accessibilityHidden(true)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .frame(minHeight: 44)
                                .background(KinTheme.field, in: RoundedRectangle(cornerRadius: 16))
                            }
                            .accessibilityHint("Opens the Kin Privacy Policy in your browser")
                            .accessibilityIdentifier("about-privacy-policy")
                            .id("privacy-policy")
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Name-based gender suggestions")
                                .font(.headline)
                                .accessibilityAddTraits(.isHeader)
                            Text("Optional name-based gender suggestions use an offline lookup derived from U.S. Social Security Administration data (CC0). Recorded application sex associations do not establish anyone’s identity. SSA does not endorse Kin.")
                                .font(.footnote)
                                .foregroundStyle(KinTheme.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 28)
                    .padding(.bottom, 24)
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
            .kinForm()
            .navigationTitle("About Kin").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                SheetEditActions(confirmTitle: "Done", confirm: { dismiss() })
            }
        }
        #if DEBUG
        .presentationDetents(ProcessInfo.processInfo.arguments.contains("--kin-preview") && ProcessInfo.processInfo.arguments.contains("--about-compact") ? [.height(420)] : [.large])
        #endif
    }
}
