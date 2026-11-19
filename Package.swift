// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Crier",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CrierKit", targets: ["CrierKit"])
    ],
    targets: [
        .target(name: "CrierKit"),
        .executableTarget(
            name: "Crier",
            dependencies: ["CrierKit"],
            exclude: ["Info.plist", "Crier.entitlements"]
        ),
        .testTarget(
            name: "CrierKitTests",
            dependencies: ["CrierKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
