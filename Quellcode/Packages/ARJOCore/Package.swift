// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ARJOCore",
    platforms: [.iOS(.v18), .tvOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "ARJOCore", targets: ["ARJOCore"])
    ],
    targets: [
        .target(name: "ARJOCore"),
        .testTarget(name: "ARJOCoreTests", dependencies: ["ARJOCore"])
    ],
    swiftLanguageModes: [.v5]
)
