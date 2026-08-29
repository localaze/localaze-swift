// swift-tools-version: 5.9
//
// Built as a package rather than an .xcodeproj so `swift build` and
// `swift test` work from a terminal and in CI. Open Package.swift in Xcode and
// it runs as an app on a simulator or a device just the same.
//
// macOS is listed alongside iOS so the whole thing compiles and runs on a build
// machine — which is what let this app be verified rather than only written.

import PackageDescription

let package = Package(
    name: "LocalazeDemo",
    platforms: [.iOS(.v16), .macOS(.v13)],
    dependencies: [
        .package(path: "../../localaze-swift")
    ],
    targets: [
        .executableTarget(
            name: "LocalazeDemo",
            dependencies: [.product(name: "Localaze", package: "localaze-swift")]
        ),
        .testTarget(
            name: "LocalazeDemoTests",
            dependencies: ["LocalazeDemo"]
        ),
    ]
)
