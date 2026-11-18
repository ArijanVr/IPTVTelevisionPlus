// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ARJOData",
    platforms: [.iOS(.v18), .tvOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "ARJOData", targets: ["ARJOData"])
    ],
    dependencies: [
        .package(path: "../ARJOCore")
    ],
    targets: [
        .target(name: "ARJOData", dependencies: ["ARJOCore"]),
        .testTarget(name: "ARJODataTests", dependencies: ["ARJOData"])
    ],
    swiftLanguageModes: [.v5]
)
