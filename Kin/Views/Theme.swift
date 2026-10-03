import SwiftUI

// Named assets preserve the warm palette across system materials and custom surfaces.
enum KinTheme {
    static let background = Color("KinBackground")
    static let surface = Color("KinSurface")
    static let field = Color("KinField")
    static let text = Color("KinText")
    static let secondary = Color("KinSecondary")
    static let accent = Color("KinAccent")
    static let sage = Color("KinSage")
    static let border = Color("KinBorder")
    // All record editors match Add Friend's sheet rows, independent of route or presentation.
    // Preserve the system's light/dark and increased-contrast color variants.
    static let editableFormRow = Color(uiColor: UIColor { traits in
        UIColor.secondarySystemGroupedBackground.resolvedColor(with:
            traits.modifyingTraits { $0.userInterfaceLevel = .elevated })
    })
    static func ink(_ gender: Gender) -> Color { Color("Avatar_\(gender.rawValue)") }
    static func wash(_ gender: Gender) -> Color { Color("AvatarWash_\(gender.rawValue)") }
}
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.caption.weight(.medium)).tracking(1.5)
            .foregroundStyle(KinTheme.secondary).accessibilityAddTraits(.isHeader)
    }
}
struct KinCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 18) { content }
            .frame(maxWidth: .infinity, alignment: .leading).padding(20)
            .background(KinTheme.surface, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(KinTheme.border, lineWidth: 0.5))
    }
}
struct InitialAvatar: View {
    let first: String
    let last: String
    var photo: Data? = nil
    var gender: Gender = .unknown
    var size: CGFloat = 48
    var body: some View {
        ZStack {
            Circle().fill(KinTheme.wash(gender))
            if let photo, let image = UIImage(data: photo) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                HStack(spacing: 0) {
                    Text(String(first.prefix(1)).uppercased()).rotationEffect(.degrees(-7))
                    Text(String(last.prefix(1)).uppercased()).rotationEffect(.degrees(4)).offset(y: 1)
                }
                .font(.system(size: size * 0.37, weight: .medium, design: .serif).italic())
                .foregroundStyle(KinTheme.ink(gender))
            }
        }.frame(width: size, height: size).clipShape(Circle()).accessibilityHidden(true)
    }
}
struct ChildAvatar: View {
    let stage: LifeStage
    let gender: Gender
    var size: CGFloat = 56
    var body: some View {
        Image(stage.rawValue).renderingMode(.template).resizable().scaledToFit()
            .foregroundStyle(KinTheme.ink(gender)).padding(size * 0.08)
            .frame(width: size, height: size).background(KinTheme.wash(gender), in: Circle())
            .accessibilityHidden(true)
    }
}
struct ErrorMessage: ViewModifier {
    @Binding var message: String?
    func body(content: Content) -> some View {
        content.alert("Couldn’t save changes", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) { message = nil }
        } message: { Text(message ?? "Try again.") }
    }
}
extension View {
    func kinError(_ message: Binding<String?>) -> some View { modifier(ErrorMessage(message: message)) }
    func kinDestructiveText() -> some View {
        foregroundStyle(Color(uiColor: .systemRed)).tint(Color(uiColor: .systemRed))
    }
    func kinForm() -> some View {
        scrollContentBackground(.hidden).background(KinTheme.background).foregroundStyle(KinTheme.text)
            .tint(KinTheme.accent)
    }
}

extension View {
    @ViewBuilder func kinSearch(enabled: Bool, query: Binding<String>) -> some View {
        if enabled { searchable(text: query, prompt: "Find a friend or family member") }
        else { self }
    }
}
