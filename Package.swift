// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "OpenNotch",
    platforms: [.macOS(.v14)],
    products: [
        // The SDK module for plugin authors. The host statically links this target
        // and exports its symbols (-export_dynamic below); plugins compile against
        // this module but link with `-undefined dynamic_lookup` (no embedded copy),
        // so at dlopen they bind to the host's single OpenNotchKit — one shared
        // runtime, no duplicate classes. See spikes/2026-07-07-m3-risk2-*.
        .library(name: "OpenNotchKit", targets: ["OpenNotchKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.10.0"),
    ],
    targets: [
        .target(name: "OpenNotchKit"),
        .executableTarget(name: "OpenNotch", dependencies: ["OpenNotchKit"],
            // Export the statically-linked OpenNotchKit (and Swift runtime) symbols
            // so dlopened plugins resolve against this process instead of embedding
            // their own copy.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-export_dynamic"])]),
        .testTarget(name: "OpenNotchKitTests", dependencies: ["OpenNotchKit", .product(name: "Testing", package: "swift-testing")],
                    resources: [.copy("Fixtures")]),
    ]
)
