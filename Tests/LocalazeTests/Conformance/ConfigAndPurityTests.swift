/// Conformance groups: config (contract section 9) and purity (sections 2, 3
/// and 10).
///
/// The purity checks assert on the source itself, because the properties are
/// about what the package does not contain. A runtime test cannot prove the
/// absence of a plural-rule table or a stray URLSession call.

import Foundation
import XCTest

@testable import Localaze

final class ConfigTests: XCTestCase {

    func testKeyOnlyWorks() {
        // An app constructing the SDK with only a key must behave sensibly.
        let config = LocalazeConfig(apiKey: "k")

        XCTAssertEqual(config.baseUrl, "https://localize.sharpy.dev")
        XCTAssertEqual(config.policy, .minorAndPatch)
        XCTAssertEqual(config.timeout, 10)
        XCTAssertFalse(config.applyImmediately)
        XCTAssertNil(config.onDiagnostic)
        XCTAssertNil(config.transport)
        XCTAssertNil(config.storage)

        let runtime = runtimeFor("ru", config: config)
        XCTAssertEqual(runtime.render("auth.sign_out"), "Выход")
        XCTAssertEqual(runtime.version, "1.0.0")
    }

    func testApplyImmediatelyOffByDefault() async {
        let transport = FakeTransport([
            "/version": ok(versionBody("1.0.1")),
            "/translations": ok(fixture("updates/patch-1.0.1-ru.json")),
        ])
        let runtime = runtimeFor(
            "ru", config: LocalazeConfig(apiKey: "k", transport: transport))

        let status = await runtime.update()

        XCTAssertEqual(status.outcome, .applied)
        // Text changing under a user mid-session is worse than text being one
        // launch out of date.
        XCTAssertEqual(runtime.render("auth.sign_out"), "Выход")
    }

    func testVersionInUseIsReadable() async {
        let transport = FakeTransport([
            "/version": ok(versionBody("1.0.1")),
            "/translations": ok(fixture("updates/patch-1.0.1-ru.json")),
        ])
        let runtime = runtimeFor(
            "ru",
            config: LocalazeConfig(
                apiKey: "k", applyImmediately: true, transport: transport))

        XCTAssertEqual(runtime.version, "1.0.0")
        await runtime.update()
        XCTAssertEqual(runtime.version, "1.0.1")
    }

    func testCustomBaseUrlIsHonoured() async throws {
        let transport = FakeTransport(["/version": ok(versionBody("1.0.1"))])

        await runtimeFor(
            "ru",
            config: LocalazeConfig(
                apiKey: "k",
                baseUrl: "https://staging.localaze.internal",
                transport: transport)
        ).update()

        let url = try XCTUnwrap(transport.urls.first)
        XCTAssertTrue(url.hasPrefix("https://staging.localaze.internal"), url)
    }

    func testNoStorageIsTheDocumentedDefault() async {
        let storage = LocalazeNoStorage()

        let asset = await storage.readAsset("ru")
        let cache = await storage.readCache("ru")
        let written = await storage.writeCache("ru", "{}")

        XCTAssertNil(asset)
        XCTAssertNil(cache)
        XCTAssertFalse(written)
    }
}

final class PurityTests: XCTestCase {

    /// Every `.swift` file under `Sources/`, with its path relative to it.
    ///
    /// Comments are stripped: the properties are about what the package
    /// contains **as code**. A doc comment explaining why no plural table ships
    /// here is the documentation working rather than a violation, and a check
    /// that forbids explaining itself is a check nobody keeps.
    private lazy var code: [String: String] = {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Conformance/
            .deletingLastPathComponent()  // LocalazeTests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // the package root
            .appendingPathComponent("Sources/Localaze")

        var out: [String: String] = [:]
        let files = FileManager.default.enumerator(
            at: sources, includingPropertiesForKeys: nil)

        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "swift",
                  let body = try? String(contentsOf: url, encoding: .utf8)
            else { continue }

            let stripped = body.split(separator: "\n", omittingEmptySubsequences: false)
                .map { line -> String in
                    guard let comment = line.range(of: "//") else { return String(line) }
                    return String(line[line.startIndex..<comment.lowerBound])
                }
                .joined(separator: "\n")

            out[url.lastPathComponent] = stripped
        }
        return out
    }()

    func testThereIsSourceToCheck() {
        XCTAssertFalse(code.isEmpty)
        XCTAssertNotNil(code["Localaze.swift"])
        XCTAssertFalse(code["Signature.swift"]?.contains("///") ?? true,
                       "the comment stripper is doing something")
    }

    func testNoMf2Parser() {
        // A device never sees MF2 syntax. Catalogs arrive already parsed, which
        // is what makes this package possible without a Swift MF2 library.
        for (name, body) in code {
            XCTAssertFalse(body.contains(".match $"), name)
            XCTAssertFalse(body.contains(".input {"), name)
            XCTAssertFalse(body.contains("{{"), name)
        }
    }

    func testNoPluralRuleData() {
        // Plural categories resolve through rules the generator compiled in.
        for (name, body) in code {
            XCTAssertFalse(body.lowercased().contains("cldr"), name)
            XCTAssertFalse(body.contains("stringsdict"), name)
            // LZ-56 rejects Foundation's plural handling explicitly: its rules
            // are its own, and LZ-54 guarantees all three platforms agree.
            XCTAssertFalse(body.contains("NSLocalizedString"), name)
        }
    }

    func testNoTranslationsInPackage() {
        // The packages are generic: no key names, no translated text, no
        // project identifier.
        let leaks = [
            "inbox.unread", "auth.welcome", "auth.sign_out", "billing.due",
            "Postbox", "Выход", "mesaj",
        ]
        for (name, body) in code {
            for leak in leaks {
                XCTAssertFalse(body.contains(leak), "\(name) contains \"\(leak)\"")
            }
        }
    }

    func testCoreHasNoPlatformIo() {
        // URLSession and FileManager live in Platform/ and nowhere else.
        let platform = ["UrlSessionTransport.swift", "FileStorage.swift"]

        for (name, body) in code where !platform.contains(name) {
            XCTAssertFalse(body.contains("URLSession"), name)
            XCTAssertFalse(body.contains("FileManager"), name)
            XCTAssertFalse(body.contains("URLRequest"), name)
        }
    }

    func testCoreImportsNoUiFramework() {
        // A UIKit-only app must carry no SwiftUI, and the core must carry
        // neither, so a Dart-style headless consumer stays possible.
        for (name, body) in code {
            XCTAssertFalse(body.contains("import SwiftUI"), name)
            XCTAssertFalse(body.contains("import UIKit"), name)
        }
    }
}
