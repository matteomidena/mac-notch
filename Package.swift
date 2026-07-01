// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "OpenNotch",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.10.0"),
    ],
    targets: [
        .target(name: "OpenNotchKit"),
        .executableTarget(name: "OpenNotch", dependencies: ["OpenNotchKit"]),
        .testTarget(name: "OpenNotchKitTests", dependencies: ["OpenNotchKit", .product(name: "Testing", package: "swift-testing")],
                    resources: [.copy("Fixtures")]),
    ]
)
