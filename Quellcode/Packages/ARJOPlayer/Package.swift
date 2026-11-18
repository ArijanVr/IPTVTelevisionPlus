// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ARJOPlayer",
    platforms: [.iOS(.v18), .tvOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "ARJOPlayer", targets: ["ARJOPlayer"])
    ],
    dependencies: [
        // Fallback-Engine für MKV/AVI/TS/AC3. Community-Paket mit dem VLCKit-3.6.0-Binary (LGPL-2.1).
        .package(url: "https://github.com/tylerjonesio/vlckit-spm", exact: "3.6.0")
    ],
    targets: [
        .target(
            name: "ARJOPlayer",
            dependencies: [
                .product(name: "VLCKitSPM", package: "vlckit-spm", condition: .when(platforms: [.iOS, .tvOS, .macOS]))
            ]
        ),
        .testTarget(name: "ARJOPlayerTests", dependencies: ["ARJOPlayer"])
    ],
    swiftLanguageModes: [.v5]
)
