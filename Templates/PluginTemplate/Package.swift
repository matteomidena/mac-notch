// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "WeatherPlugin",
    platforms: [.macOS(.v14)],
    products: [
        // Dynamic so the build emits a dlopen-able dylib the host can load.
        .library(name: "WeatherPlugin", type: .dynamic, targets: ["WeatherPlugin"]),
    ],
    dependencies: [
        // Local path during development; point at a tagged OpenNotchKit once published.
        .package(path: "../..")
    ],
    targets: [
        .target(name: "WeatherPlugin", dependencies: [
            .product(name: "OpenNotchKit", package: "mac-notch")
        ])
    ]
)
