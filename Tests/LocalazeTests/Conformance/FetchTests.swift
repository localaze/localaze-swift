/// Conformance group: fetch. Contract section 6.

import XCTest

@testable import Localaze

private func runtimeWith(
    _ transport: FakeTransport,
    storage: FakeStorage? = nil,
    reported: Reported? = nil,
    policy: LocalazeUpdatePolicy = .minorAndPatch,
    applyImmediately: Bool = true
) -> LocalazeRuntime {
    runtimeFor(
        "ru",
        config: LocalazeConfig(
            apiKey: "test-key",
            policy: policy,
            applyImmediately: applyImmediately,
            onDiagnostic: reported?.callback,
            transport: transport,
            storage: storage))
}

final class FetchTests: XCTestCase {

    func testSendsApiKey() async {
        let transport = FakeTransport([
            "/version": ok(versionBody("1.0.1")),
            "/translations": ok(fixture("updates/patch-1.0.1-ru.json")),
        ])

        await runtimeWith(transport).update()

        XCTAssertFalse(transport.headers.isEmpty)
        for headers in transport.headers {
            XCTAssertEqual(headers["X-Localaze-Key"], "test-key")
        }
        // The key carries the project and the environment, so neither appears
        // in any URL. A staging build cannot read production by editing one.
        for url in transport.urls {
            XCTAssertFalse(url.contains("project"), url)
            XCTAssertFalse(url.contains("environment"), url)
        }
    }

    func testSendsIfNoneMatch() async {
        // Not done by the implementation this replaces, though the server has
        // served version-scoped ETags all along.
        let transport = FakeTransport([
            "/version": ok(versionBody("1.0.1")),
            "/translations": ok(fixture("updates/patch-1.0.1-ru.json"), etag: "\"1.0.1-ab\""),
        ])
        let runtime = runtimeWith(transport)

        await runtime.update()
        XCTAssertNil(
            transport.headerValue("If-None-Match"),
            "nothing is held before the first fetch")

        transport.responses["/version"] = ok(versionBody("1.0.2"))
        await runtime.update()

        XCTAssertEqual(transport.headerValue("If-None-Match"), "\"1.0.1-ab\"")
    }

    func testNotModifiedKeepsContent() async {
        let reported = Reported()
        let transport = FakeTransport([
            "/version": ok(versionBody("1.0.1")),
            "/translations": LocalazeResponse(status: 304, etag: "\"1.0.1-ab\""),
        ])
        let runtime = runtimeWith(transport, reported: reported)

        let status = await runtime.update()

        // A success, not a failure. This is the cheap path the ETag exists for.
        XCTAssertEqual(status.outcome, .upToDate)
        XCTAssertEqual(runtime.render("auth.sign_out"), "Выход")
        XCTAssertTrue(reported.isEmpty, "\(reported.messages)")
    }

    func testPinnedVersion() async throws {
        let transport = FakeTransport([
            "/translations": ok(fixture("updates/patch-1.0.1-ru.json"))
        ])

        let status = await runtimeWith(transport).update(pinnedVersion: "1.0.1")

        XCTAssertEqual(status.outcome, .applied)
        let url = try XCTUnwrap(transport.urls.first)
        XCTAssertTrue(url.contains("version=1.0.1"), url)
        XCTAssertTrue(url.contains("format=resolved"), url)
        // A pin answers the version question, so that endpoint is not hit.
        XCTAssertFalse(transport.urls.contains { $0.contains("/read/version") })
    }

    func testNothingWrittenBeforeSignaturePasses() async {
        let storage = FakeStorage()
        let transport = FakeTransport([
            "/version": ok(versionBody("1.0.2")),
            "/translations": ok(fixture("updates/retyped-1.0.2-ru.json")),
        ])

        let status = await runtimeWith(transport, storage: storage).update()

        XCTAssertEqual(status.outcome, .refusedBySignature)
        XCTAssertEqual(storage.writes, 0, "a refused catalog must leave no trace")
        XCTAssertNil(storage.cache)
    }

    func testOrderIsPolicyVersionDownloadSignaturePersist() async {
        // policy none short-circuits before the transport is touched.
        let first = FakeTransport(["/version": ok(versionBody("1.0.1"))])
        await runtimeWith(first, policy: .none).update()
        XCTAssertTrue(first.urls.isEmpty)

        // A version the policy refuses stops before the catalog is downloaded.
        let second = FakeTransport([
            "/version": ok(versionBody("1.1.0")),
            "/translations": ok(fixture("updates/minor-1.1.0-ru.json")),
        ])
        await runtimeWith(second, policy: .patchOnly).update()

        XCTAssertEqual(second.urls.count, 1)
        XCTAssertTrue(second.urls[0].contains("/read/version"))
    }

    func testAppliedCatalogIsPersisted() async {
        let storage = FakeStorage()
        let transport = FakeTransport([
            "/version": ok(versionBody("1.0.1")),
            "/translations": ok(fixture("updates/patch-1.0.1-ru.json")),
        ])

        await runtimeWith(transport, storage: storage).update()

        XCTAssertEqual(storage.writes, 1)
        XCTAssertTrue(storage.cache?.contains("Выйти") ?? false)
    }

    func testPatchChangesWordingWithoutRegenerating() async {
        // The outcome the whole design exists for: a typo fix reaching a
        // running app with no rebuild and no new generated source.
        let transport = FakeTransport([
            "/version": ok(versionBody("1.0.1")),
            "/translations": ok(fixture("updates/patch-1.0.1-ru.json")),
        ])
        let runtime = runtimeWith(transport)

        XCTAssertEqual(runtime.render("auth.sign_out"), "Выход")
        await runtime.update()
        XCTAssertEqual(runtime.render("auth.sign_out"), "Выйти")
        XCTAssertEqual(runtime.version, "1.0.1")
    }
}
