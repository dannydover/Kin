import Foundation
import Testing
@testable import Kin

@Suite("Friendly error boundaries") struct UserFacingErrorTests {
    @Test("Unexpected system details never appear in user messages") func privateDiagnostics() {
        let diagnostic = "Synthetic internal storage failure with private notebook values"
        let error = NSError(domain: "SyntheticInternalDomain",code: 42,userInfo: [NSLocalizedDescriptionKey: diagnostic])
        for opening in [false,true] {
            let message = UserFacingError.message(error,opening: opening)
            #expect(!message.contains(diagnostic) && !message.contains("SyntheticInternalDomain"))
            #expect(message.contains("Try again"))
        }
        #expect(UserFacingError.message(KinError.incompatibleStore).contains("data hasn’t been changed"))
        #expect(UserFacingError.message(NotebookAccessError.locked).contains("Unlock your iPhone"))
    }
}
