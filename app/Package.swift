// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Porto",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Signed, delta-capable updates. Inert until a feed and key are configured (UPDATES.md).
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "Porto",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            resources: [.process("Resources")],
            // The packaged app keeps Sparkle in Contents/Frameworks; `swift run`
            // keeps it beside the executable.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
                                           "-Xlinker", "-rpath", "-Xlinker", "@executable_path"])]
        ),
        .testTarget(name: "PortoTests", dependencies: ["Porto"]),
    ]
)
