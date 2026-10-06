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
        let friend = Friend(firstName: "Rowan", lastName: "Vale")
        try store.saveFriend(friend)
        let lifecycle = NotebookLifecycle()
        lifecycle.store = store
        lifecycle.applicationProtectedDataWillBecomeUnavailable(.shared)
        #expect(!lifecycle.isAvailable)
        #expect(store.isClosed && !store.isReady)
        #expect(store.friends == [friend])
        // This test drives callback wiring; it does not actually lock the device.
        if UIApplication.shared.isProtectedDataAvailable {
            lifecycle.applicationProtectedDataDidBecomeAvailable(.shared)
            #expect(lifecycle.store === store)
            #expect(store.isReady && lifecycle.isAvailable)
            #expect(store.friends == [friend])
            lifecycle.refresh()
            #expect(store.friends == [friend])
        }
    }
}
#endif
