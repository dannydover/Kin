import Foundation
import Testing
@testable import Kin

@Suite("Partner photo persistence") @MainActor struct PartnerPhotoTests {
    private func withPhoto(_ partner: Partner, bytes: Data) throws -> Partner {
        var payload = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(partner)) as? [String: Any])
        payload["photo"] = bytes.base64EncodedString()
        return try JSONDecoder().decode(Partner.self, from: JSONSerialization.data(withJSONObject: payload))
    }
    private func photoBytes(_ partner: Partner) throws -> String? {
        let payload = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(partner)) as? [String: Any])
        return payload["photo"] as? String
    }
    @Test("Partner payload retains an imported photo") func photoSurvivesCoding() throws {
        let bytes = Data("synthetic thumbnail bytes".utf8)
        let partner = try withPhoto(Partner(firstName: "Mira", lastName: "Vale"), bytes: bytes)
        #expect(try photoBytes(partner) == bytes.base64EncodedString())
    }
    @Test("Partners saved before photo support decode unchanged") func oldPayloadRemainsReadable() throws {
        let original = Partner(firstName: "Mira", lastName: "Vale", gender: .female, isCurrent: false)
        var payload = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        payload.removeValue(forKey: "photo")
        let decoded = try JSONDecoder().decode(Partner.self, from: JSONSerialization.data(withJSONObject: payload))
        #expect(decoded == original)
        #expect(decoded.photo == nil)
    }
    @Test("Imported partner photo survives SQLite close and reopen") func photoSurvivesSQLiteReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("partner-photo.sqlite")
        let bytes = Data("synthetic thumbnail bytes".utf8)
        let partner = try withPhoto(Partner(firstName: "Mira", lastName: "Vale"), bytes: bytes)
        let store = try KinStore(storeURL: url)
        defer { try? store.close() }
        let friend = Friend(firstName: "Rowan", lastName: "Vale")
        try store.saveFriend(friend); try store.savePartner(partner, friendID: friend.id); try store.close()
        let reopened = try KinStore(storeURL: url)
        defer { try? reopened.close() }
        let saved = try #require(reopened.friends.first?.partners.first)
        #expect(try photoBytes(saved) == bytes.base64EncodedString())
        #expect(saved.id == partner.id)
    }
}
