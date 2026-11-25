import SwiftUI
import CoreText

// Named assets preserve the warm palette across system materials and custom surfaces.
enum KinTheme {
    static let background = Color("KinBackground")
    static let surface = Color("KinSurface")
    static let field = Color("KinField")
    static let text = Color("KinText")
    static let secondary = Color("KinSecondary")
    // Opaque adaptive secondary ink chosen for the actual warm footer background.
    static let helperInk = UIColor { traits in
        // Kin's warm background is dark in both asset appearances. Adapt to
        // Increase Contrast while retaining readable ink on that actual surface.
        UIColor(white: traits.accessibilityContrast == .high ? 0.92 : 0.78, alpha: 1)
    }
    static let helperText = Color(uiColor: helperInk)
    static let accent = Color("KinAccent")
    static let sage = Color("KinSage")
    static let border = Color("KinBorder")
    static let editableFormRow = surface
    static let divider = Color(red: 0.36, green: 0.21, blue: 0.12)
    static let panel = LinearGradient(colors: [surface, field], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let backdrop = LinearGradient(
        stops: [.init(color: Color(red: 0.107, green: 0.037, blue: 0), location: 0),
                .init(color: background, location: 1)],
        startPoint: .top, endPoint: .bottom
    )
    static let clay = LinearGradient(colors: [Color(red: 0.949, green: 0.627, blue: 0.486),
                                               Color(red: 0.875, green: 0.514, blue: 0.361)],
                                     startPoint: .top, endPoint: .bottom)
    static let cream = LinearGradient(colors: [Color(red: 0.969, green: 0.953, blue: 0.918),
                                                Color(red: 0.894, green: 0.871, blue: 0.816)],
                                      startPoint: .top, endPoint: .bottom)
    private static let childPink = LinearGradient(
        colors: [Color(red: 255 / 255, green: 217 / 255, blue: 227 / 255),
                 Color(red: 231 / 255, green: 167 / 255, blue: 185 / 255)],
        startPoint: .top, endPoint: .bottom
    )
    private static let childBlue = LinearGradient(
        colors: [Color(red: 213 / 255, green: 232 / 255, blue: 255 / 255),
                 Color(red: 156 / 255, green: 191 / 255, blue: 218 / 255)],
        startPoint: .top, endPoint: .bottom
    )
    static func childDisc(for gender: Gender) -> LinearGradient {
        switch gender {
        case .female: childPink
        case .male: childBlue
        case .unknown, .other: cream
        }
    }
    static let discRim = LinearGradient(stops: [
        .init(color: .white.opacity(0.55), location: 0), .init(color: .clear, location: 0.35),
        .init(color: .clear, location: 0.7), .init(color: .white.opacity(0.25), location: 1)
    ], startPoint: .top, endPoint: .bottom)
    static let clayInk = Color(red: 0.19, green: 0.10, blue: 0.06)
    @MainActor private static let brandDescriptor: CTFontDescriptor? = {
        guard let url = Bundle.main.url(forResource: "LibreBaskerville", withExtension: "ttf"),
              let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] else { return nil }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        guard let descriptor = descriptors.first else { return nil }
        return CTFontDescriptorCreateCopyWithVariation(descriptor, NSNumber(value: 0x77676874), 700)
    }()
    @MainActor static func titleFont(_ size: CGFloat) -> Font {
        guard let brandDescriptor else { return .system(size: size, weight: .bold, design: .serif) }
        return Font(CTFontCreateWithFontDescriptor(brandDescriptor, size, nil))
    }
    static func ink(_ gender: Gender) -> Color { Color("Avatar_\((gender == .other ? "unknown" : gender.rawValue))") }
    static func wash(_ gender: Gender) -> Color { Color("AvatarWash_\((gender == .other ? "unknown" : gender.rawValue))") }
}
struct KinSectionHeading: View {
    let text: String
    var body: some View {
        KinTitle(text: text, size: 15)
            .foregroundStyle(KinTheme.text)
            .textCase(nil)
            .accessibilityAddTraits(.isHeader)
    }
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
            .kinPanel(radius: 22)
    }
}
struct KinTitle: View {
    let text: String
    @ScaledMetric(relativeTo: .headline) private var size: CGFloat = 19

    init(text: String, size: CGFloat = 19) {
        self.text = text
        _size = ScaledMetric(wrappedValue: size, relativeTo: .headline)
    }

    var body: some View {
        Text(text).font(KinTheme.titleFont(size)).fixedSize(horizontal: false, vertical: true)
    }
}

func spokenAgeOrGrade(_ value: String) -> String {
    value.hasPrefix("~") ? "Approximately " + String(value.dropFirst()) : value
}

struct SchoolGradeLabel: View {
    let grade: String

    var body: some View {
        Text(verbatim: grade)
            .accessibilityLabel(Text(verbatim: spokenAgeOrGrade(grade)))
    }
}

struct InitialAvatar: View {
    let first: String
    let last: String
    var photo: Data? = nil
    var gender: Gender = .unknown
    var size: CGFloat = 48
    var isChild = false
    var body: some View {
        Circle()
            .fill(isChild ? KinTheme.childDisc(for: gender) : KinTheme.clay)
            .overlay {
                if let photo, let image = UIImage(data: photo) {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: size, height: size).clipShape(Circle())
                } else {
                    Text(initials).font(KinTheme.titleFont(size * 0.32))
                        .foregroundStyle(KinTheme.clayInk)
                        .lineLimit(1).minimumScaleFactor(0.65)
                        .frame(width: size * 0.9, height: size, alignment: .center)
                }
            }
            .overlay(Circle().strokeBorder(KinTheme.discRim, lineWidth: size * (isChild ? 0.025 : 0.014)))
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.45), radius: size * 0.043, x: 0, y: size * 0.038)
            .accessibilityHidden(true)
    }
    private var initials: String {
        let value = (first.prefix(1) + last.prefix(1)).uppercased()
        return value.isEmpty ? "?" : value
    }
}
struct ErrorMessage: ViewModifier {
    @Binding var message: String?
    func body(content: Content) -> some View {
        content.alert("Couldn’t finish", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) { message = nil }
        } message: { Text(message ?? "Try again.") }
    }
}
extension View {
    func kinError(_ message: Binding<String?>) -> some View { modifier(ErrorMessage(message: message)) }
    func kinDestructiveText() -> some View {
        foregroundStyle(Color(uiColor: .systemRed)).tint(Color(uiColor: .systemRed))
    }
    func kinPanel(radius: CGFloat = 18) -> some View {
        background(KinTheme.panel, in: RoundedRectangle(cornerRadius: radius))
            .overlay { RoundedRectangle(cornerRadius: radius).strokeBorder(KinTheme.border, lineWidth: 1).allowsHitTesting(false) }
    }
    func kinForm() -> some View {
        scrollContentBackground(.hidden).background { KinBackdrop() }.foregroundStyle(KinTheme.text)
            .tint(KinTheme.accent)
    }
}

extension View {
    @ViewBuilder func kinSearch(enabled: Bool, query: Binding<String>) -> some View {
        if enabled { searchable(text: query, prompt: "Find a friend or family member") }
        else { self }
    }
}

struct KinBackdrop: View {
    var body: some View {
        ZStack(alignment: .top) {
            KinTheme.background
            KinTheme.backdrop.frame(height: 310)
        }.ignoresSafeArea()
    }
}

/// Opaque colors keep confirmation text readable over native toolbar materials.
struct ConfirmationLabel: View {
    let title: String
    var primary = true
    var fillsWidth = false
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(primary ? KinTheme.clayInk : KinTheme.text)
            .padding(.horizontal, 10).padding(.vertical, fillsWidth ? 8 : 0)
            .frame(minWidth: 44, maxWidth: fillsWidth ? .infinity : nil, minHeight: 44)
            .background {
                Capsule().fill(primary ? AnyShapeStyle(KinTheme.clay) : AnyShapeStyle(KinTheme.panel))
                    .overlay {
                        if fillsWidth || contrast == .increased {
                            Capsule().strokeBorder(primary ? KinTheme.accent : KinTheme.border, lineWidth: 1)
                        }
                    }
            }
            // Preserve the entire padded background's intrinsic toolbar width,
            // rather than letting only the text overflow a compressed frame.
            .fixedSize(horizontal: !fillsWidth, vertical: true)
    }
}

struct SheetEditActions: ToolbarContent {
    var cancel: (() -> Void)? = nil
    var confirmTitle = "Save"
    var confirm: (() -> Void)?
    var confirmDisabled = false
    var cancelIdentifier: String?
    var confirmIdentifier: String?

    var body: some ToolbarContent {
        if let cancel {
            ToolbarItem(placement: .cancellationAction) {
                Button(action: cancel) { ConfirmationLabel(title: "Cancel", primary: false) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(cancelIdentifier ?? "Cancel")
            }.sharedBackgroundVisibility(.hidden)
        }
        if let confirm {
            ToolbarItem(placement: .confirmationAction) {
                Button(action: confirm) { ConfirmationLabel(title: confirmTitle) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(confirmIdentifier ?? confirmTitle)
                    .disabled(confirmDisabled)
            }.sharedBackgroundVisibility(.hidden)
        }
    }
}
