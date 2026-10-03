import Foundation

/// Both editors use the same one-time snapshot and bounded photo conversion.
/// Only names/photo change; identity, notes, gender and family links stay intact.
enum ContactImport {
    static func apply(_ snapshot: ContactSnapshot, to friend: inout Friend) {
        friend.firstName = snapshot.firstName
        friend.lastName = snapshot.lastName
        friend.photo = snapshot.photo.flatMap { PhotoProcessor.thumbnail($0) }
    }
    static func apply(_ snapshot: ContactSnapshot, to partner: inout Partner) {
        partner.firstName = snapshot.firstName
        partner.lastName = snapshot.lastName
        partner.photo = snapshot.photo.flatMap { PhotoProcessor.thumbnail($0) }
    }
}
