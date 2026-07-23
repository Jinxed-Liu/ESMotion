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
        .library(name: "ESMotionMetal", targets: ["ESMotionMetal"]),
        .library(name: "ESMotionDocument", targets: ["ESMotionDocument"]),
        .executable(name: "esmotionc", targets: ["esmotionc"]),
        .executable(name: "ESMotionStudio", targets: ["ESMotionStudio"]),
        .executable(name: "ESMotionGallery", targets: ["ESMotionGallery"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/airbnb/lottie-spm.git",
            from: "4.6.0"
        ),
    ],
    targets: [
        .target(name: "ESMotionCore"),
        .target(
            name: "ESMotionDocument",
            dependencies: ["ESMotionCore"]
        ),
        .target(
            name: "ESMotionRuntime",
            dependencies: [
                "ESMotionCore",
                "ESMotionDocument",
                .product(name: "Lottie", package: "lottie-spm"),
            ]
        ),
        .target(
            name: "ESMotionMetal",
            dependencies: [
                "ESMotionCore",
                "ESMotionRuntime",
            ],
            resources: [.process("Shaders")]
        ),
        .target(
            name: "ESMotion",
            dependencies: [
                "ESMotionCore",
                "ESMotionDocument",
                "ESMotionRuntime",
                "ESMotionMetal",
            ]
        ),
        .executableTarget(
            name: "esmotionc",
            dependencies: [
                "ESMotionCore",
                "ESMotionDocument",
            ]
        ),
        .executableTarget(
            name: "ESMotionStudio",
            dependencies: ["ESMotion"]
        ),
        .executableTarget(
            name: "ESMotionGallery",
            dependencies: ["ESMotion"]
        ),
        .testTarget(
            name: "ESMotionCoreTests",
            dependencies: ["ESMotionCore"]
        ),
        .testTarget(
            name: "ESMotionDocumentTests",
            dependencies: [
                "ESMotionCore",
                "ESMotionDocument",
            ]
        ),
        .testTarget(
            name: "ESMotionRuntimeTests",
            dependencies: [
                "ESMotionCore",
                "ESMotionRuntime",
            ],
            linkerSettings: [
                .unsafeFlags(
                    [
                        "-Xlinker",
                        "-rpath",
                        "-Xlinker",
                        "@loader_path/../../..",
                    ],
                    .when(platforms: [.macOS])
                ),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
