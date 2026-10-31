// swift-tools-version:6.0
// Compile-check only (tools/check-app.sh). The real app is built by XcodeGen from ios/project.yml;
// this manifest mirrors its Shiori target. The script copies the sources next to it, so the paths
// are relative to the staging folder, not to this file. GRDB, ZIPFoundation and SwiftSoup come in
// through ShioriLibrary's own manifest, at the versions it pins.
import PackageDescription

let package = Package(
    name: "ShioriCheck",
    platforms: [.iOS("26.0")],
    dependencies: [
        .package(path: "ShioriCore"),
        .package(path: "ShioriLibrary"),
    ],
    targets: [
        .target(
            name: "Shiori",
            dependencies: [
                .product(name: "ShioriCore", package: "ShioriCore"),
                .product(name: "ShioriLibrary", package: "ShioriLibrary"),
            ],
            path: "App"
        ),
    ],
    swiftLanguageModes: [.v5]
)
