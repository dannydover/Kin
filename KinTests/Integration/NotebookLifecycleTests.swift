#if os(iOS)
import Foundation
import UIKit
import Testing
@testable import Kin

@Suite("Notebook UIKit lifecycle") @MainActor struct NotebookLifecycleTests {
    @Test("Delegate warning detaches synchronously and availability reopens the same store")
    func callbacks() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try KinStore(storeURL: directory.appendingPathComponent("test.sqlite"))
        defer { try? store.close() }
        var friend = Person(firstName: "Rowan", lastName: "Vale", birthday: .exact(CivilDate(year: 1980, month: 1, day: 1)))
        try store.savePerson(friend)
        friend = try store.person(friend.id)
        let lifecycle = NotebookLifecycle()
        lifecycle.store = store
        lifecycle.applicationProtectedDataWillBecomeUnavailable(.shared)
        #expect(!lifecycle.isAvailable)
        #expect(store.isClosed && !store.isReady)
        #expect(store.people == [friend])
        // This test drives callback wiring; it does not actually lock the device.
        if UIApplication.shared.isProtectedDataAvailable {
            lifecycle.applicationProtectedDataDidBecomeAvailable(.shared)
            #expect(lifecycle.store === store)
            #expect(store.isReady && lifecycle.isAvailable)
            #expect(store.people == [friend])
            lifecycle.refresh()
            #expect(store.people == [friend])
        }
    }
}
#endif
