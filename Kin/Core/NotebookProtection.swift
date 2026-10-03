import Foundation

enum NotebookAccessError: LocalizedError {
    case locked, reopenRequired
    var errorDescription: String? {
        switch self {
        case .locked: "Unlock your iPhone to use your notebook. Your draft is still here; try saving again after unlocking."
        case .reopenRequired: "Reopen your notebook, check what was saved, then try again. Your draft is still here."
        }
    }
}

/// The notebook has its own directory. Protect existing SQLite companions and
/// external payloads before opening, plus directories from which new files inherit.
/// Never move, replace or delete a notebook as part of this upgrade.
enum NotebookProtection {
    static func prepare(directory: URL) throws {
        let manager = FileManager.default
        #if os(iOS)
        let attributes: [FileAttributeKey: Any] = [.protectionKey: FileProtectionType.complete]
        try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: attributes)
        func protect(_ url: URL) throws {
            try manager.setAttributes(attributes, ofItemAtPath: url.path)
            // Simulator does not implement iOS Data Protection attribute readback.
            // Require verified protection on device; never claim simulator proof.
            #if !targetEnvironment(simulator)
            guard try manager.attributesOfItem(atPath: url.path)[.protectionKey] as? FileProtectionType == .complete else {
                throw CocoaError(.fileWriteNoPermission)
            }
            #endif
        }
        try protect(directory)
        // contentsOfDirectory throws on access failure; do not silently skip any files.
        func walk(_ parent: URL) throws {
            for url in try manager.contentsOfDirectory(at: parent, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) {
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values.isSymbolicLink != true else { throw CocoaError(.fileWriteNoPermission) }
                try protect(url)
                if values.isDirectory == true { try walk(url) }
            }
        }
        try walk(directory)
        #else
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        #endif
    }
}
