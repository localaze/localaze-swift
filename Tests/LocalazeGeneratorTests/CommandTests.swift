/// `localaze-generate` as a build runs it: a real process, real files.

import Foundation
import XCTest

/// The directory SwiftPM builds products into, found from the test bundle.
private var productsDirectory: URL {
    #if os(macOS)
    for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
        return bundle.bundleURL.deletingLastPathComponent()
    }
    fatalError("Could not find the products directory")
    #else
    return Bundle.main.bundleURL
    #endif
}

private func generate(_ arguments: [String]) throws -> (status: Int32, stdout: String, stderr: String) {
    let process = Process()
    process.executableURL = productsDirectory.appendingPathComponent("localaze-generate")
    process.arguments = arguments
    let out = Pipe()
    let err = Pipe()
    process.standardOutput = out
    process.standardError = err
    try process.run()
    process.waitUntilExit()
    return (process.terminationStatus,
            String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
}

final class CommandTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("localaze-gen-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testWritesTheGoldenSourceAndEveryCatalog() throws {
        let result = try generate([
            "--manifest", fixtures.appendingPathComponent("manifest.json").path,
            "--catalogs", fixtures.appendingPathComponent("catalogs").path,
            "--out", directory.appendingPathComponent("Sources/Localaze.g.swift").path,
            "--assets", directory.appendingPathComponent("Localaze").path,
        ])

        XCTAssertEqual(result.status, 0, result.stderr)
        XCTAssertEqual(
            try String(contentsOf: directory.appendingPathComponent("Sources/Localaze.g.swift"), encoding: .utf8),
            try String(contentsOf: goldenPath, encoding: .utf8))
        for language in ["az", "ru"] {
            XCTAssertEqual(
                try Data(contentsOf: directory.appendingPathComponent("Localaze/\(language).json")),
                try Data(contentsOf: fixtures.appendingPathComponent("catalogs/\(language).json")))
        }
    }

    func testAFailureExitsOneNamesTheProblemAndWritesNothing() throws {
        let onlyAz = directory.appendingPathComponent("only-az")
        try FileManager.default.createDirectory(at: onlyAz, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: fixtures.appendingPathComponent("catalogs/az.json"),
            to: onlyAz.appendingPathComponent("az.json"))

        let result = try generate([
            "--manifest", fixtures.appendingPathComponent("manifest.json").path,
            "--catalogs", onlyAz.path,
            "--out", directory.appendingPathComponent("Sources/Localaze.g.swift").path,
            "--assets", directory.appendingPathComponent("Localaze").path,
        ])

        XCTAssertEqual(result.status, 1)
        XCTAssertTrue(result.stderr.contains("No catalog for language \"ru\"."))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("Sources").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("Localaze").path))
    }

    func testAUsageErrorExits64() throws {
        let result = try generate(["--nonsense"])
        XCTAssertEqual(result.status, 64)
        XCTAssertTrue(result.stderr.contains("Unknown option \"--nonsense\""))
    }

    func testAnUnreachableServerIsAFailureNotACrash() throws {
        let result = try generate([
            "--key", "k", "--base-url", "http://127.0.0.1:9",
            "--out", directory.appendingPathComponent("Localaze.g.swift").path,
            "--assets", directory.appendingPathComponent("Localaze").path,
        ])
        XCTAssertEqual(result.status, 1)
        XCTAssertTrue(result.stderr.contains("Could not reach http://127.0.0.1:9"), result.stderr)
    }
}
