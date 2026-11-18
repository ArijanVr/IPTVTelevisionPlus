// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ARJONetwork",
    platforms: [.iOS(.v18), .tvOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "ARJONetwork", targets: ["ARJONetwork"])
    ],
    dependencies: [
        .package(path: "../ARJOCore")
    ],
    targets: [
        .target(name: "ARJONetwork", dependencies: ["ARJOCore"]),
        .testTarget(name: "ARJONetworkTests", dependencies: ["ARJONetwork"])
    ],
    swiftLanguageModes: [.v5]
)
