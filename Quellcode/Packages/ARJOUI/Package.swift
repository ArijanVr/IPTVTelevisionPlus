// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ARJOUI",
    platforms: [.iOS(.v18), .tvOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "ARJOUI", targets: ["ARJOUI"])
    ],
    dependencies: [
        .package(path: "../ARJOCore"),
        .package(path: "../ARJONetwork"),
        .package(path: "../ARJOPlayer")
    ],
    targets: [
        .target(name: "ARJOUI", dependencies: ["ARJOCore", "ARJONetwork", "ARJOPlayer"]),
        .testTarget(name: "ARJOUITests", dependencies: ["ARJOUI", "ARJOPlayer"])
    ],
    swiftLanguageModes: [.v5]
)
