// swift-tools-version:6.0
// Compile-check only (tools/check-app.sh). The real app is built by XcodeGen from ios/project.yml;
// this manifest mirrors its Shiori target. The script copies the sources next to it, so the paths
// are relative to the staging folder, not to this file.
import PackageDescription

let package = Package(
    name: "ShioriCheck",
    platforms: [.iOS("26.0")],
    targets: [
        .target(
            name: "Shiori",
            path: "App"
        ),
    ],
    swiftLanguageModes: [.v5]
)
