// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EmulationKit",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "EmulationKit", targets: ["EmulationKit"])],
    targets: [
        .target(name: "EmulationKit"),
        .testTarget(name: "EmulationKitTests", dependencies: ["EmulationKit"])
    ]
)
