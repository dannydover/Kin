import SwiftUI

struct ChildEditor: View {
    let store: KinStore
    let friendID: UUID
    let isNew: Bool
    let today: Date
    private let entryTimeZone: TimeZone
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var draft: Child
    @State private var estimated: Bool
    @State private var exactDate: Date
    @State private var estimatedAge: Int
    @State private var referenceDate: Date
    @State private var explaining = false
    @State private var deleting = false
    @State private var error: String?
    private var partners: [Partner] { store.friends.first(where: { $0.id == friendID })?.partners ?? [] }
    init(store: KinStore, friend: Friend, child: Child? = nil, today: Date) {
        self.store = store; friendID = friend.id; isNew = child == nil; self.today = today; self.entryTimeZone = .current
        let birthday = child?.birthday ?? .estimated(age: 0, referenceDate: CivilDate(today, timeZone: .current))
        let suggestion = birthday.editingSuggestion
        _draft = State(initialValue: child ?? Child(firstName: "", lastName: friend.lastName, birthday: birthday))
        _estimated = State(initialValue: birthday.isEstimated)
        _exactDate = State(initialValue: AgeRules(calendar: CivilDate.gregorian(in: .current)).birthDate(for: suggestion)?.pickerDate ?? CivilDate(today, timeZone: .current).pickerDate)
        if case .estimated(let age, let reference) = suggestion {
            _estimatedAge = State(initialValue: age); _referenceDate = State(initialValue: reference.pickerDate)
        } else {
            _estimatedAge = State(initialValue: AgeRules(calendar: CivilDate.gregorian(in: .current)).age(for: suggestion, on: today) ?? 0)
            _referenceDate = State(initialValue: CivilDate(today, timeZone: .current).pickerDate)
        }
    }
    var body: some View {
        ScrollViewReader { proxy in
            Form {
                Group {
                    if draft.birthday.requiresDateReview {
                        Section("Review the saved date") {
                            Text("An earlier version saved this date as a time without its original timezone. The date below is a UTC suggestion. Check it against the birthday or reference date you originally entered, then Save to confirm. Kin has preserved the original entry.")
                                .font(.subheadline)
                        }
                    }
                    Section("Name") {
                        TextField("First name", text: $draft.firstName).textContentType(.givenName)
                        TextField("Last name", text: $draft.lastName).textContentType(.familyName)
                        GenderPicker(selection: $draft.gender)
                    }
                    Section {
                        if typeSize.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Birthday type").accessibilityAddTraits(.isHeader)
                                birthdayChoice("Exact Birthday", value: false)
                                birthdayChoice("Estimated Age", value: true)
                            }
                        } else {
                            Picker("Birthday type", selection: $estimated) {
                                Text("Exact Birthday").tag(false)
                                Text("Estimated Age").tag(true)
                            }
                        }
                        if estimated {
                            Stepper("Age: \(estimatedAge) \(estimatedAge == 1 ? "year" : "years")", value: $estimatedAge, in: 0...120)
                            DatePicker("As of", selection: $referenceDate, in: ...CivilDate(today, timeZone: entryTimeZone).pickerDate, displayedComponents: .date)
                            Button { explaining.toggle() } label: {
                                Label(explaining ? "Hide explanation" : "How estimated ages work", systemImage: "questionmark.circle")
                            }.accessibilityValue(explaining ? "Expanded" : "Collapsed")
                            if explaining {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Heard an age in conversation but don’t know the birthday? That’s enough to start.")
                                    Text("A ~ means the age is approximate. You can replace it with an exact birthday whenever you learn it.")
                                    Text("Kin chooses a July 1 birthday that matches the age you entered on your reference date, then increases the estimate each July 1. It may differ from the child’s actual age.").font(.caption).foregroundStyle(KinTheme.secondary)
                                }.font(.subheadline).padding(.vertical, 8)
                            }
                        } else { DatePicker("Birthday", selection: $exactDate, in: ...CivilDate(today, timeZone: entryTimeZone).pickerDate, displayedComponents: .date) }
                    } header: { Text("Age") }
                    if !partners.isEmpty {
                        Section("Other Parent") {
                            // An adaptive grid keeps pills readable at accessibility text sizes.
                            LazyVGrid(columns: typeSize.isAccessibilitySize ? [GridItem(.flexible(), alignment: .leading)] : [GridItem(.adaptive(minimum: 140), alignment: .leading)], alignment: .leading, spacing: 10) {
                                parentButton("None", id: nil)
                                ForEach(partners) { partner in parentButton("\(partner.fullName)\(partner.isCurrent ? "" : " (ex)")", id: partner.id) }
                            }.padding(.vertical, 6)
                        }
                    }
                    Section("Notes") { TextField("The little things to remember", text: $draft.notes, axis: .vertical).lineLimit(4...10) }
                    if !isNew { Section { Button("Delete Child", role: .destructive) { deleting = true }.kinDestructiveText().id("delete-action") } }
                }.listRowBackground(KinTheme.editableFormRow)
            }.environment(\.calendar, CivilDate.pickerCalendar).environment(\.timeZone, CivilDate.pickerCalendar.timeZone)
                .kinForm().navigationTitle(isNew ? "Add Child" : "Edit Child").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.fontWeight(.semibold) }
                }
                .confirmationDialog("Delete \(draft.firstName.isEmpty ? "this child" : draft.firstName)?", isPresented: $deleting, titleVisibility: .visible) {
                    Button("Delete Child", role: .destructive) {
                        do { try store.deleteChild(draft.id, friendID: friendID); dismiss() } catch { self.error = error.localizedDescription }
                    }
                } message: { Text("This removes their entry and notes from Kin.") }
                .kinError($error)
                .task {
                    #if DEBUG
                    let arguments = ProcessInfo.processInfo.arguments
                    if arguments.contains("--kin-preview") && arguments.contains("child-delete") {
                        proxy.scrollTo("delete-action", anchor: .bottom)
                    }
                    if arguments.contains("--kin-preview") && arguments.contains("child-confirm") {
                        deleting = true
                    }
                    #endif
                }
        }
    }
    private func birthdayChoice(_ title: String, value: Bool) -> some View {
        Button { estimated = value } label: {
            HStack(alignment: .top) {
                Image(systemName: estimated == value ? "checkmark.circle.fill" : "circle").accessibilityHidden(true)
                Text(title).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }.buttonStyle(.plain)
            .accessibilityLabel("Birthday type, \(title)")
            .accessibilityValue(estimated == value ? "Selected" : "Not selected")
            .accessibilityAddTraits(estimated == value ? [.isSelected] : [])
    }
    private func parentButton(_ title: String, id: UUID?) -> some View {
        Button { draft.partnerID = id } label: {
            Text(title).font(.subheadline).frame(maxWidth: .infinity, minHeight: 44).padding(.horizontal, 8)
                .foregroundStyle(draft.partnerID == id ? KinTheme.background : KinTheme.text)
                .background(draft.partnerID == id ? KinTheme.accent : KinTheme.field, in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain).accessibilityAddTraits(draft.partnerID == id ? [.isSelected] : [])
    }
    private func save() {
        draft.birthday = estimated ? .estimated(age: estimatedAge, referenceDate: CivilDate(referenceDate, timeZone: CivilDate.pickerCalendar.timeZone)) : .exact(CivilDate(exactDate, timeZone: CivilDate.pickerCalendar.timeZone))
        do { try store.saveChild(draft, friendID: friendID, today: today, calendar: CivilDate.gregorian(in: entryTimeZone)); UIImpactFeedbackGenerator(style: .light).impactOccurred(); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}
