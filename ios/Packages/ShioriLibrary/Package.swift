// swift-tools-version:6.2
// Apple-only: GRDB needs Apple's SQLite and the importer uses CryptoKit, so these tests run
// on the macOS CI runner, not on Windows.
import PackageDescription

let package = Package(
    name: "ShioriLibrary",
    platforms: [.iOS(.v26), .macOS(.v14)],
    products: [
        .library(name: "ShioriLibrary", targets: ["ShioriLibrary"]),
    ],
    dependencies: [
        .package(path: "../ShioriCore"),
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.11.1"),
        .package(url: "https://github.com/weichsel/ZIPFoundation", from: "0.9.20"),
        .package(url: "https://github.com/scinfu/SwiftSoup", from: "2.14.3"),
    ],
    targets: [
        .target(
            name: "ShioriLibrary",
            dependencies: [
                .product(name: "ShioriCore", package: "ShioriCore"),
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
                .product(name: "SwiftSoup", package: "SwiftSoup"),
            ]
        ),
        .testTarget(
            name: "ShioriLibraryTests",
            dependencies: ["ShioriLibrary", .product(name: "ZIPFoundation", package: "ZIPFoundation")]
        ),
    ],
    swiftLanguageModes: [.v5]
)
