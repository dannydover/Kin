import Foundation

/// A local convenience default, never an assertion about a person's identity.
struct NameAssociations: Sendable {
    let sourceAssociationCount: Int
    private let values: [String: Gender]
    private struct Payload: Decodable { let male: [String]; let female: [String] }
    init(data: Data) throws {
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        var result: [String: Gender] = [:]
        for (names, gender) in [(payload.male, Gender.male), (payload.female, Gender.female)] {
            for name in names {
                let key = name.lowercased()
                if let previous = result[key], previous != gender { result[key] = .unknown }
                else { result[key] = gender }
            }
        }
        values = result
        sourceAssociationCount = payload.male.count + payload.female.count
    }
    private init() { values = [:]; sourceAssociationCount = 0 }
    func gender(for name: String) -> Gender {
        values[name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] ?? .unknown
    }
    static let bundled: NameAssociations = {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: "NameAssociations", withExtension: "json"),
              let data = try? Data(contentsOf: url), let lookup = try? NameAssociations(data: data) else {
            return NameAssociations()
        }
        return lookup
    }()
}
