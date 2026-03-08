// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "HapiCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "HapiCore", targets: ["HapiCore"]),
    ],
    targets: [
        .target(
            name: "HapiCore",
            path: "Sources/HapiCore"
        ),
        .testTarget(
            name: "HapiCoreTests",
            dependencies: ["HapiCore"],
            path: "Tests/HapiCoreTests"
        ),
    ]
)
