import Foundation
import OSLog

/// Only errors written for people reach the UI. System diagnostics can include
/// storage paths and notebook values, so keep those private in the system log.
enum UserFacingError {
    static func message(_ error: any Error, opening: Bool = false) -> String {
        Logger(subsystem: "com.intriguingideas.Kin", category: "Recovery")
            .error("Kin operation failed: \(String(reflecting: error), privacy: .private)")
        if let error = error as? KinError { return error.errorDescription! }
        if let error = error as? NotebookAccessError { return error.errorDescription! }
        return opening
            ? "Kin couldn’t open your notebook. Your saved data hasn’t been reset. Try again, or close and reopen Kin."
            : "Kin couldn’t finish that change. Try again. If it still fails, reopen Kin and check what was saved."
    }
}
