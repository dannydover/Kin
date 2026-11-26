import Foundation

enum PetLifeStage: String, CaseIterable, Codable, Identifiable, Sendable {
    case puppy, kitten, middleAged, elderly

    var id: Self { self }
    var title: String {
        switch self {
        case .puppy: "Puppy"
        case .kitten: "Kitten"
        case .middleAged: "Middle-aged"
        case .elderly: "Elderly"
        }
    }
}

enum PetSpecies: Codable, Equatable, Sendable {
    case dog
    case cat
    case other(String)

    var title: String {
        switch self {
        case .dog: "Dog"
        case .cat: "Cat"
        case .other(let name): name
        }
    }
    var estimatedStages: [PetLifeStage] {
        switch self {
        case .dog: [.puppy, .middleAged, .elderly]
        case .cat: [.kitten, .middleAged, .elderly]
        case .other: []
        }
    }
}

enum PetAge: Codable, Equatable, Sendable {
    case unknown
    case exact(CivilDate)
    case estimated(PetLifeStage)
}

struct Pet: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var species: PetSpecies
    var age: PetAge

    init(id: UUID = UUID(), name: String, species: PetSpecies, age: PetAge = .unknown) {
        self.id = id
        self.name = name
        self.species = species
        self.age = age
    }

    private var cleaned: Self {
        var result = self
        result.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if case .other(let name) = species {
            result.species = .other(name.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return result
    }

    var isStructurallyValid: Bool {
        (try? validated()) == self
    }

    /// A future-day check belongs to new edits, not reading an existing notebook:
    /// travel or a corrected device clock must not make saved records unreadable.
    func validated(today: CivilDate? = nil) throws -> Self {
        let result = cleaned
        guard (1...200).contains(result.name.count) else { throw PetError.invalidName }
        if case .other(let name) = result.species {
            guard (1...200).contains(name.count) else { throw PetError.invalidSpecies }
        }
        switch result.age {
        case .unknown: break
        case .exact(let date):
            guard date.isValid, today.map({ date <= $0 }) ?? true else { throw PetError.invalidBirthday }
        case .estimated(let stage):
            guard result.species.estimatedStages.contains(stage) else { throw PetError.invalidEstimate }
        }
        return result
    }
}

enum PetError: LocalizedError, Equatable {
    case invalidName, invalidSpecies, invalidBirthday, invalidEstimate, staleEdit

    var errorDescription: String? {
        switch self {
        case .invalidName: "Enter a pet name of 200 characters or fewer."
        case .invalidSpecies: "Enter a species of 200 characters or fewer."
        case .invalidBirthday: "Choose a valid birthday that isn’t in the future."
        case .invalidEstimate: "Choose an age estimate for this species, or leave the age unknown."
        case .staleEdit: "This pet’s details changed while you were editing. Cancel and reopen the pet to see what’s saved."
        }
    }
}
