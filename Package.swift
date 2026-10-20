// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Emebal",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Emebal",
            path: "Sources/Emebal"
        )
    ]
)
