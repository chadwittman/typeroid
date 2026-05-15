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
        .executableTarget(
            name: "TypeRoid",
            path: "Sources/TypeRoid"
        )
    ]
)
