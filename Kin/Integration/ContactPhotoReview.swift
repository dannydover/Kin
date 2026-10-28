import Foundation

/// Review-owned bytes: changing eligibility or deselecting invalidates the preview.
/// This value never writes a notebook and never retains the source contact.
struct PreparedContactPhoto {
    let contactID: UUID
    let birthday: Birthday
    let data: Data?
}
@MainActor struct ContactPhotoReview {
    private(set) var prepared: PreparedContactPhoto?
    mutating func update(snapshot: ContactSnapshot, birthday: Birthday, included: Bool,
                         today: Date = Date(), calendar: Calendar = .current) {
        guard included, AgeRules(calendar: calendar).allowsPhoto(birthday, on: today) else {
            prepared = nil; return
        }
        guard prepared?.birthday != birthday || prepared?.contactID != snapshot.photoIdentity else { return }
        let data = snapshot.photo(for: birthday, today: today, calendar: calendar)
            .flatMap { PhotoProcessor.thumbnail($0) }
        prepared = PreparedContactPhoto(contactID: snapshot.photoIdentity, birthday: birthday, data: data)
    }
}
