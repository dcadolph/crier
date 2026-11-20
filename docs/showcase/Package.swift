// swift-tools-version: 6.0

import PackageDescription

// Showcase draws docs/crierkit.png, the README's picture of CrierKit's news band inside two made-up apps. It
// sits outside the main package so the library and app builds never include it.
let package = Package(
    name: "Showcase",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../..")],
    targets: [
        .executableTarget(name: "Showcase", dependencies: [.product(name: "CrierKit", package: "crier")])
    ]
)
