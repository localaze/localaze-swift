// swift-tools-version: 5.9
//
// 5.9 rather than 6.0 deliberately. It keeps the package in Swift 5 language
// mode, so an app on either mode consumes it without strict-concurrency
// friction, and nothing here needs a 6.0-only feature.

import PackageDescription

let package = Package(
    name: "Localaze",
    // macOS is here so `swift test` runs on a build machine rather than only in
    // a simulator. iOS 16 is the baseline that matters: roughly four years old,
    // and it brings Duration for the timeout configuration.
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "Localaze", targets: ["Localaze"]),
        // The generator. An app runs it at build time; it never links it.
        .executable(name: "localaze-generate", targets: ["localaze-generate"]),
    ],
    // No dependencies. Every package here is one a consuming app must also
    // carry and keep in step.
    dependencies: [],
    targets: [
        .target(name: "Localaze"),
        // Pure planning and emitting. No network, no files, so tests reach
        // every check directly. Not a product: nothing outside links it.
        .target(name: "LocalazeGenerator"),
        // The command: HTTP and file writes around LocalazeGenerator.
        .executableTarget(name: "localaze-generate", dependencies: ["LocalazeGenerator"]),
        // The fixture project is shared with the Dart and Kotlin packages and
        // is reached through #filePath rather than copied in as a resource.
        // SPM resources must live inside the target directory, which would mean
        // a Swift-only copy — and it would drift from the others in a release.
        .testTarget(name: "LocalazeTests", dependencies: ["Localaze"]),
        .testTarget(
            name: "LocalazeGeneratorTests",
            dependencies: ["LocalazeGenerator", "localaze-generate"]),
        // The golden file, compiled against the runtime exactly as an app
        // compiles its generated source, and rendering every expected row.
        .testTarget(name: "LocalazeGoldenTests", dependencies: ["Localaze"]),
    ]
)
