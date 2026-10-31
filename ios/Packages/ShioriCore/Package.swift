// swift-tools-version:6.2
// Pure Swift with no dependencies, so `swift test` runs on Windows as well as on CI.
import PackageDescription

let package = Package(
    name: "ShioriCore",
    platforms: [.iOS(.v26), .macOS(.v14)],
    products: [
        .library(name: "ShioriCore", targets: ["ShioriCore"]),
    ],
    targets: [
        .target(name: "ShioriCore"),
        .testTarget(name: "ShioriCoreTests", dependencies: ["ShioriCore"]),
    ],
    swiftLanguageModes: [.v5]
)
