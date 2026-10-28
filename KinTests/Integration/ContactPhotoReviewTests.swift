import Foundation
import CoreData
import UIKit
import Testing
@testable import Kin

@Suite("Eligible Contacts photo review") @MainActor struct ContactPhotoReviewTests {
    private let today = CivilDate(year: 2026, month: 10, day: 23).pickerDate
    private let adult = Birthday.exact(CivilDate(year: 1980, month: 1, day: 1))
    private func image() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 8,height: 8)).pngData { context in
            UIColor.systemBlue.setFill(); context.fill(CGRect(x: 0,y: 0,width: 8,height: 8))
        }
    }
    @Test("No access before eligibility or opt-in; corrections invalidate and repeated review reuses bytes")
    func eligibility() {
        var reads = 0; let data = image()
        let snapshot = ContactSnapshot(firstName: "Synthetic",lastName: "Preview",loadPhoto: { reads += 1; return data })
        var review = ContactPhotoReview()
        for birth in [Birthday.unknown,.exact(CivilDate(year: 2020,month: 1,day: 1)),.estimated(age: 17,referenceDate: CivilDate(year: 2026,month: 10,day: 23))] {
            review.update(snapshot: snapshot,birthday: birth,included: true,today: today)
            #expect(review.prepared == nil && reads == 0)
        }
        review.update(snapshot: snapshot,birthday: adult,included: false,today: today)
        #expect(review.prepared == nil && reads == 0)
        review.update(snapshot: snapshot,birthday: adult,included: true,today: today)
        let preview = review.prepared?.data
        #expect(preview != nil && reads == 1)
        review.update(snapshot: snapshot,birthday: adult,included: true,today: today)
        #expect(review.prepared?.data == preview && reads == 1)
        review.update(snapshot: snapshot,birthday: .unknown,included: true,today: today)
        #expect(review.prepared == nil && reads == 1)
        review.update(snapshot: snapshot,birthday: adult,included: true,today: today)
        #expect(reads == 2)
    }
    @Test("No-photo and corrupt-photo reviews stay empty and do not repeatedly reread")
    func noPhoto() {
        for data: Data? in [nil,Data("invalid image".utf8)] {
            var reads = 0
            let snapshot = ContactSnapshot(firstName: "Synthetic",lastName: "Empty",loadPhoto: { reads += 1; return data })
            var review = ContactPhotoReview()
            for _ in 0..<3 { review.update(snapshot: snapshot,birthday: adult,included: true,today: today) }
            #expect(review.prepared?.data == nil && reads == 1)
        }
    }
    @Test("Prepared import uses exactly reviewed bytes without rereading and still enforces the age gate")
    func exactBytes() {
        var reads = 0; let data = image()
        let snapshot = ContactSnapshot(firstName: "Synthetic",lastName: "Photo",loadPhoto: { reads += 1; return data })
        var review = ContactPhotoReview()
        review.update(snapshot: snapshot,birthday: adult,included: true,today: today)
        var person = Person()
        ContactImport.apply(snapshot,to: &person,birthday: adult,preparedPhoto: review.prepared,today: today)
        #expect(person.photo == review.prepared?.data && person.photo != nil && reads == 1)
        ContactImport.apply(snapshot,to: &person,birthday: .unknown,preparedPhoto: review.prepared,today: today)
        #expect(person.photo == nil && reads == 1)
    }
    @Test("Changing contacts at the same age cannot reuse another contact's photo")
    func differentContact() {
        var firstReads = 0, nextReads = 0
        let data = image()
        let first = ContactSnapshot(firstName: "Synthetic First",lastName: "",loadPhoto: { firstReads += 1; return data })
        let next = ContactSnapshot(firstName: "Synthetic Next",lastName: "",loadPhoto: { nextReads += 1; return nil })
        var review = ContactPhotoReview()
        review.update(snapshot: first,birthday: adult,included: true,today: today)
        let previous = review.prepared
        review.update(snapshot: next,birthday: adult,included: true,today: today)
        #expect(review.prepared?.data == nil && firstReads == 1 && nextReads == 1)
        var person = Person()
        ContactImport.apply(next,to: &person,birthday: adult,preparedPhoto: previous,today: today)
        #expect(person.photo == nil && nextReads == 1)
    }
    @Test("Review cancellation and failed save retain prepared bytes without a partial saved person", arguments: [false,true])
    func failure(afterCommit: Bool) throws {
        var failing = true, reads = 0
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try KinStore(storeURL: directory.appendingPathComponent("synthetic.sqlite"), saveContext: { context in
            if failing && !afterCommit { throw CocoaError(.fileWriteNoPermission) }
            try context.save()
            if failing && afterCommit { throw CocoaError(.fileWriteNoPermission) }
        })
        defer { try? store.close() }
        let data = image()
        let snapshot = ContactSnapshot(firstName: "Synthetic Retry",lastName: "",loadPhoto: { reads += 1; return data })
        var review = ContactPhotoReview()
        review.update(snapshot: snapshot,birthday: adult,included: true,today: today)
        #expect(store.people.isEmpty, "Preview or cancellation cannot save anything")
        var person = Person()
        ContactImport.apply(snapshot,to: &person,birthday: adult,preparedPhoto: review.prepared,today: today)
        let commit = NewContactImportCommit()
        #expect(throws: (any Error).self) { try commit.save(person,store: store,relationship: nil) }
        #expect(commit.completedID == nil && store.people.isEmpty)
        #expect(person.photo == review.prepared?.data && reads == 1)
        failing = false
        try store.resume()
        try commit.save(person,store: store,relationship: nil)
        try commit.save(person,store: store,relationship: nil)
        #expect(store.people.count == 1 && store.people.first?.id == person.id)
        #expect(store.people.first?.photo == review.prepared?.data && reads == 1)
    }

}
