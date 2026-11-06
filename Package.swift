// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Kin",
    platforms: [.macOS(.v14), .iOS("26.0")],
    products: [.library(name: "Kin", targets: ["Kin"])],
    targets: [
        .target(name: "Kin", path: "Kin/Core", resources: [.process("Resources")]),
        .target(name: "SyntheticContactsTestSupport", path: "KinTests/Shared"),
        .testTarget(name: "KinTests", dependencies: ["Kin", "SyntheticContactsTestSupport"], path: "KinTests/Core")
    ],
    swiftLanguageModes: [.v6]
)
