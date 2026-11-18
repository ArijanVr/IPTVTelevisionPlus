// swift-tools-version: 6.0
import PackageDescription

// Kapselt Sparkle (nur macOS). Auf iOS und tvOS bleibt das Target leer und Sparkle wird nicht gelinkt.
let package = Package(
    name: "ARJOUpdate",
    platforms: [.iOS(.v18), .tvOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "ARJOUpdate", targets: ["ARJOUpdate"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.4")
    ],
    targets: [
        .target(
            name: "ARJOUpdate",
            dependencies: [.product(name: "Sparkle", package: "Sparkle", condition: .when(platforms: [.macOS]))]
        )
    ],
    swiftLanguageModes: [.v5]
)
