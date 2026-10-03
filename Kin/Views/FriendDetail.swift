import SwiftUI

struct FriendDetail: View {
    let store: KinStore
    let friendID: UUID
    let today: Date
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var deleting = false
    @State private var error: String?
    var body: some View {
        Group {
            if let friend = store.friends.first(where: { $0.id == friendID }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        header(friend)
                        let layout = FamilyLayout(friend: friend)
                        (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout())) {
                            SectionLabel(text: "Children")
                            if !typeSize.isAccessibilitySize { Spacer() }
                            NavigationLink { ChildEditor(store: store, friend: friend, today: today) }
                            label: { Label("Add Child", systemImage: "plus").font(.subheadline.weight(.medium)).padding(.vertical, 10) }
                        }
                        if friend.children.isEmpty {
                            Text("No children added yet").font(.body).foregroundStyle(KinTheme.secondary)
                        }
                        if layout.grouped {
                            ForEach(layout.groups) { group in
                                KinCard {
                                    if let partner = group.partner { partnerHeader(partner, friend: friend) }
                                    else { SectionLabel(text: "With \(friend.firstName)") }
                                    ForEach(group.children) { child in childLink(child, friend: friend) }
                                }
                            }
                        } else {
                            ForEach(friend.children) { child in childLink(child, friend: friend) }
                        }
                        if !layout.compactFormerPartners.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                SectionLabel(text: "Former partners")
                                ForEach(layout.compactFormerPartners) { partner in
                                    NavigationLink { PartnerEditor(store: store, friend: friend, partner: partner) }
                                    label: {
                                        (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading)) : AnyLayout(HStackLayout())) {
                                            Text(partner.fullName).font(.subheadline)
                                            if !typeSize.isAccessibilitySize { Spacer() }
                                            Text("Former partner").font(.caption)
                                            Image(systemName: "chevron.right").font(.caption)
                                        }.foregroundStyle(KinTheme.secondary).padding(.vertical, 14)
                                    }
                                }
                            }
                        }
                        NavigationLink { PartnerEditor(store: store, friend: friend) }
                        label: { Label("Add Partner", systemImage: "person.badge.plus").padding(.vertical, 12) }
                        if !friend.notes.isEmpty {
                            KinCard {
                                SectionLabel(text: "A little to remember")
                                Text(friend.notes).font(.body).textSelection(.enabled)
                            }
                        }
                        Text("School grades are estimates using a September 1 US cutoff. Individual schools and children may differ.")
                            .font(.caption).foregroundStyle(KinTheme.secondary)
                    }.padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity)
                }.background(KinTheme.background)
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Menu {
                                NavigationLink("Edit Friend") { FriendEditor(store: store, friend: friend) }
                                Button("Delete Friend", role: .destructive) { deleting = true }
                            } label: { Image(systemName: "ellipsis") }.accessibilityLabel("Friend options")
                        }
                    }
                    .confirmationDialog("Delete \(friend.fullName) and their family?", isPresented: $deleting, titleVisibility: .visible) {
                        Button("Delete Friend and Family", role: .destructive) {
                            do { try store.deleteFriend(friend.id); dismiss() } catch { self.error = error.localizedDescription }
                        }
                    } message: { Text("This permanently removes their family and notes from Kin.") }
            } else { ContentUnavailableView("Friend unavailable", systemImage: "person.crop.circle.badge.questionmark") }
        }.foregroundStyle(KinTheme.text).navigationTitle("Family").navigationBarTitleDisplayMode(.inline).kinError($error)
            .task {
                #if DEBUG
                let arguments = ProcessInfo.processInfo.arguments
                if arguments.contains("--kin-preview") && arguments.contains("friend-confirm") { deleting = true }
                #endif
            }
    }
    private func header(_ friend: Friend) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            InitialAvatar(first: friend.firstName, last: friend.lastName, photo: friend.photo, size: 80)
            Text(friend.fullName).font(.largeTitle).fontDesign(.serif).accessibilityAddTraits(.isHeader)
            if !FamilyLayout(friend: friend).grouped, let partner = friend.currentPartner { partnerHeader(partner, friend: friend) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10)
    }
    private func partnerHeader(_ partner: Partner, friend: Friend) -> some View {
        NavigationLink { PartnerEditor(store: store, friend: friend, partner: partner) }
        label: {
            (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(alignment: .center, spacing: 12))) {
                InitialAvatar(first: partner.firstName, last: partner.lastName, photo: partner.photo, gender: partner.gender, size: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text(partner.fullName).font(.subheadline).foregroundStyle(partner.isCurrent ? KinTheme.text : KinTheme.secondary)
                    Text("with \(friend.firstName)").font(.caption).foregroundStyle(KinTheme.secondary)
                }
                if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                Text(partner.isCurrent ? "Partner" : "Former")
                    .font(.caption.weight(.medium)).foregroundStyle(partner.isCurrent ? KinTheme.sage : KinTheme.secondary)
                    .padding(.horizontal, 10).padding(.vertical, 6).background(KinTheme.field, in: Capsule())
            }.padding(.vertical, 4)
        }.buttonStyle(.plain).accessibilityHint("Edit partner")
    }
    private func childLink(_ child: Child, friend: Friend) -> some View {
        NavigationLink { ChildEditor(store: store, friend: friend, child: child, today: today) }
        label: { ChildRow(child: child, friendLastName: friend.lastName, today: today) }
            .buttonStyle(.plain).accessibilityHint("Edit child")
    }
}
struct ChildRow: View {
    let child: Child
    let friendLastName: String
    let today: Date
    private var rules: AgeRules { AgeRules(calendar: CivilDate.gregorian(in: .current)) }
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14)) : AnyLayout(HStackLayout(alignment: .top, spacing: 14))) {
            if let age = rules.age(for: child.birthday, on: today) {
                ChildAvatar(stage: .forAge(age), gender: child.gender)
            } else {
                Image(systemName: "calendar.badge.exclamationmark").font(.title).foregroundStyle(KinTheme.secondary).frame(width: 56, height: 56).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 7) {
                Text(child.displayName(friendLastName: friendLastName)).font(.body).fontDesign(.serif)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) { ageAndGrade }
                    VStack(alignment: .leading, spacing: 6) { ageAndGrade }
                }
                if !child.notes.isEmpty { Text(child.notes).font(.subheadline).foregroundStyle(KinTheme.secondary).lineLimit(3) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if !typeSize.isAccessibilitySize { Image(systemName: "chevron.right").font(.caption).foregroundStyle(KinTheme.secondary).padding(.top, 8) }
        }.padding(.vertical, 8)
    }
    @ViewBuilder private var ageAndGrade: some View {
        if let age = rules.age(for: child.birthday, on: today) {
            HStack(spacing: 0) {
                if child.birthday.isEstimated { Text("~").foregroundStyle(KinTheme.accent) }
                Text("\(age)").fontWeight(.medium)
            }.font(.title3).fontDesign(.serif).accessibilityElement(children: .ignore)
                .accessibilityLabel("\(child.birthday.isEstimated ? "Approximately " : "")\(age) years old")
            if let grade = rules.grade(for: child.birthday, on: today) {
                Text("\(grade) · estimated").font(.caption).foregroundStyle(KinTheme.secondary)
            }
        } else {
            Text("Date needs review").font(.subheadline).foregroundStyle(KinTheme.accent)
        }
    }
}
