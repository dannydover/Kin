import Foundation

struct AppVersion {
    let version: String?
    let build: String?
    init(info: [String: Any] = Bundle.main.infoDictionary ?? [:]) {
        func value(_ key: String) -> String? {
            guard let raw = info[key] as? String else { return nil }
            let result = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return result.isEmpty ? nil : result
        }
        version = value("CFBundleShortVersionString")
        build = value("CFBundleVersion")
    }
    var displayText: String {
        switch (version, build) {
        case let (version?, build?): "Kin \(version) (\(build))"
        case let (version?, nil): "Kin \(version)"
        case let (nil, build?): "Kin (build \(build))"
        case (nil, nil): "Kin — Version unavailable"
        }
    }
    var accessibilityLabel: String {
        (["Kin"] + [version.map { "version \($0)" }, build.map { "build \($0)" }].compactMap { $0 }
         + (version == nil && build == nil ? ["Version unavailable"] : [])).joined(separator: ", ")
    }
}
