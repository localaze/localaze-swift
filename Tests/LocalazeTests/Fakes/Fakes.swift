/// Fakes and the shared fixture project.
///
/// These exist because every failure row in contract section 8 is reachable
/// with a fake and unreachable without one. A runtime testable only against a
/// live server is a runtime that is not tested.

import Foundation
@testable import Localaze

/// Records what it was asked for and returns what it was told to.
final class FakeTransport: LocalazeTransport, @unchecked Sendable {
    /// Path fragment to response, matched by `contains`, so a caller writes
    /// `/version` rather than the whole URL.
    var responses: [String: LocalazeResponse]

    private(set) var urls: [String] = []
    private(set) var headers: [[String: String]] = []

    /// Set to make `get` behave as a transport that violates its own contract.
    var failEverything: String?

    init(_ responses: [String: LocalazeResponse] = [:]) {
        self.responses = responses
    }

    func headerValue(_ name: String) -> String? {
        headers.compactMap { $0[name] }.first
    }

    func get(_ url: String, headers: [String: String]) async -> LocalazeResponse {
        urls.append(url)
        self.headers.append(headers)

        if let failEverything { return .failed(failEverything) }

        for (fragment, response) in responses where url.contains(fragment) {
            return response
        }
        return LocalazeResponse(status: 404)
    }
}

/// In-memory storage, so a test never touches the disk.
final class FakeStorage: LocalazeStorage, @unchecked Sendable {
    var asset: String?
    var cache: String?
    var writable: Bool
    private(set) var writes = 0

    init(asset: String? = nil, cache: String? = nil, writable: Bool = true) {
        self.asset = asset
        self.cache = cache
        self.writable = writable
    }

    func readAsset(_ language: String) async -> String? { asset }
    func readCache(_ language: String) async -> String? { cache }

    func writeCache(_ language: String, _ body: String) async -> Bool {
        guard writable else { return false }
        writes += 1
        cache = body
        return true
    }
}

/// Collects diagnostics so a test can assert something was reported.
final class Reported: @unchecked Sendable {
    private(set) var messages: [String] = []

    var callback: LocalazeDiagnostic {
        { [weak self] message, _ in self?.messages.append(message) }
    }

    func mentions(_ fragment: String) -> Bool {
        messages.contains { $0.contains(fragment) }
    }

    var isEmpty: Bool { messages.isEmpty }
}

// MARK: - The shared fixture project

/// Loads a file from `contract/fixtures`, the contract submodule.
///
/// Reached through `#filePath` rather than copied in as an SPM resource: SPM
/// resources must live inside the target, which would mean a Swift-only copy of
/// the fixture, and it would drift from Dart's and Kotlin's within a release.
func fixture(_ path: String) -> String {
    let here = URL(fileURLWithPath: #filePath)
    let fixtures = here
        .deletingLastPathComponent()   // Fakes/
        .deletingLastPathComponent()   // LocalazeTests/
        .deletingLastPathComponent()   // Tests/
        .deletingLastPathComponent()   // the package root
        .appendingPathComponent("contract/fixtures")
        .appendingPathComponent(path)

    guard let body = try? String(contentsOf: fixtures, encoding: .utf8) else {
        fatalError("fixture not found: \(fixtures.path)")
    }
    return body
}

/// Compiled CLDR rules for Russian, as `PluralRuleCompiler` emits them.
///
/// The `i % 100 != 11` exclusion is the whole reason this is generated rather
/// than guessed: without it 11, 111 and 211 select `one` and read as
/// "У вас 11 сообщение".
func russianPlural(_ value: Double) -> String? {
    let i = Int(abs(value).rounded(.down))
    let v = value == Double(i) ? 0 : 1

    if v == 0, i % 10 == 1, !(i % 100 == 11) { return "one" }
    if v == 0, (i % 10) >= 2, (i % 10) <= 4, !((i % 100) >= 12 && (i % 100) <= 14) {
        return "few"
    }
    if v == 0,
       (i % 10) == 0 || ((i % 10) >= 5 && (i % 10) <= 9) || ((i % 100) >= 11 && (i % 100) <= 14)
    {
        return "many"
    }
    return nil  // `other`, which is the catch-all.
}

/// Azerbaijani has one rule and no exception.
func azerbaijaniPlural(_ value: Double) -> String? { value == 1 ? "one" : nil }

func plural(_ locale: String, _ value: Double) -> String? {
    locale == "ru" ? russianPlural(value) : azerbaijaniPlural(value)
}

/// The signature the generator emits for the fixture project.
let fixtureSignature = LocalazeSignature(of: [
    "auth.sign_out": [],
    "auth.welcome": [("name", "STRING")],
    "billing.due": [("when", "DATETIME")],
    "inbox.unread": [("count", "NUMBER")],
])

func catalogFor(_ locale: String) -> String { fixture("catalogs/\(locale).json") }

/// A runtime configured the way generated code configures one.
func runtimeFor(
    _ locale: String,
    config: LocalazeConfig? = nil,
    compiledIn: String? = nil
) -> LocalazeRuntime {
    LocalazeRuntime(
        locale: locale,
        config: config ?? LocalazeConfig(apiKey: "test-key"),
        signature: fixtureSignature,
        compiledIn: compiledIn ?? catalogFor(locale),
        pluralResolver: { plural(locale, $0) })
}

/// A response carrying a fixture file.
func ok(_ body: String, etag: String? = nil) -> LocalazeResponse {
    LocalazeResponse(status: 200, body: body, etag: etag)
}

/// The `/version` endpoint's body. Note it carries no `messages`, which is why
/// the updater reads the field directly rather than through the catalog parser.
func versionBody(_ version: String) -> String {
    """
    {"environment":"production","version":"\(version)","bump":"PATCH",
     "note":null,"publishedAt":"2026-08-01T00:00:00Z","keyCount":4,
     "available":["1.0.0","\(version)"]}
    """
}

/// A minimal ru catalog whose auth.sign_out reads `text`.
func catalogSaying(_ text: String, _ version: String) -> String {
    """
    {"version":"\(version)","language":"ru","messages":{
      "auth.sign_out":{"selectors":[],"params":[],"variants":{"*":[{"text":"\(text)"}]}},
      "auth.welcome":{"selectors":[],"params":[{"name":"name","type":"STRING"}],
        "variants":{"*":[{"text":"hi "},{"var":"name","type":"STRING"}]}},
      "billing.due":{"selectors":[],"params":[{"name":"when","type":"DATETIME"}],
        "variants":{"*":[{"var":"when","type":"DATETIME"}]}},
      "inbox.unread":{"selectors":["count"],"params":[{"name":"count","type":"NUMBER"}],
        "variants":{"*":[{"var":"count","type":"NUMBER"}]}}}}
    """
}
