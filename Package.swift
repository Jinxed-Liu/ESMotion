// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ESMotion",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "ESMotion", targets: ["ESMotion"]),
        .library(name: "ESMotionCore", targets: ["ESMotionCore"]),
        .library(name: "ESMotionRuntime", targets: ["ESMotionRuntime"]),
    ],
    targets: [
        .target(name: "ESMotionCore"),
        .target(
            name: "ESMotionRuntime",
            dependencies: ["ESMotionCore"]
        ),
        .target(
            name: "ESMotion",
            dependencies: [
                "ESMotionCore",
                "ESMotionRuntime",
            ],
            exclude: ["ESMotion.docc"]
        ),
        .testTarget(
            name: "ESMotionCoreTests",
            dependencies: ["ESMotionCore"]
        ),
        .testTarget(
            name: "ESMotionRuntimeTests",
            dependencies: [
                "ESMotionCore",
                "ESMotionRuntime",
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
