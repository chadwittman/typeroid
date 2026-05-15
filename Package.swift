// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TypeRoid",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "TypeRoid", targets: ["TypeRoid"])
    ],
    targets: [
        .target(
            name: "TypeRoidCore",
            path: "Sources/TypeRoidCore"
        ),
        .executableTarget(
            name: "TypeRoid",
            dependencies: ["TypeRoidCore"],
            path: "Sources/TypeRoidApp"
        ),
        .testTarget(
            name: "TypeRoidCoreTests",
            dependencies: ["TypeRoidCore"],
            path: "Tests/TypeRoidCoreTests"
        )
    ]
)
