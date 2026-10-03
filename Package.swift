// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Kin",
    platforms: [.macOS(.v14), .iOS("26.0")],
    products: [.library(name: "Kin", targets: ["Kin"])],
    targets: [
        .target(name: "Kin", path: "Kin/Core"),
        .testTarget(name: "KinTests", dependencies: ["Kin"], path: "KinTests/Core")
    ],
    swiftLanguageModes: [.v6]
)
