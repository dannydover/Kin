import Testing
@testable import Kin

@Suite("Installed app version") struct AppVersionTests {
    @Test("Version and build reflect supplied bundle metadata") func metadata() {
        let value = AppVersion(info: ["CFBundleShortVersionString": "2.7.1", "CFBundleVersion": "83"])
        #expect(value.displayText == "Kin 2.7.1 (83)")
        #expect(value.accessibilityLabel == "Kin, version 2.7.1, build 83")
    }
    @Test("Missing individual values never invent release numbers") func partial() {
        #expect(AppVersion(info: ["CFBundleShortVersionString": " 3.0 \n"]).displayText == "Kin 3.0")
        #expect(AppVersion(info: ["CFBundleVersion": "7"]).displayText == "Kin (build 7)")
        #expect(AppVersion(info: ["CFBundleVersion": "7"]).accessibilityLabel == "Kin, build 7")
    }
    @Test("Absent, blank or malformed metadata uses an honest fallback") func fallback() {
        for info: [String: Any] in [[:], ["CFBundleShortVersionString": " ", "CFBundleVersion": 8]] {
            let value = AppVersion(info: info)
            #expect(value.displayText == "Kin — Version unavailable")
            #expect(value.accessibilityLabel == "Kin, Version unavailable")
        }
    }
}
