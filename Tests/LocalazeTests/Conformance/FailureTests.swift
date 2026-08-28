/// Conformance group: failure. Contract section 8.
///
/// The rule this whole group serves: no public API throws. A translation
/// outage is a stale screen; an SDK that throws makes it a crash.
///
/// Swift enforces part of this at compile time — none of these methods are
/// declared `throws`, so `try` is not even spellable at a call site. What the
/// tests add is that a failure still leaves the app rendering.

import XCTest

@testable import Localaze

private func runtimeWith(
    transport: FakeTransport? = nil,
    storage: FakeStorage? = nil,
    reported: Reported? = nil,
    compiledIn: String? = nil
) -> LocalazeRuntime {
    runtimeFor(
        "ru",
        config: LocalazeConfig(
            apiKey: "k",
            applyImmediately: true,
            onDiagnostic: reported?.callback,
            transport: transport,
            storage: storage),
        compiledIn: compiledIn)
}

final class FailureTests: XCTestCase {

    func testNetworkUnreachable() async {
        let reported = Reported()
        let transport = FakeTransport(["/version": .failed("connection refused")])
        let runtime = runtimeWith(transport: transport, reported: reported)

        let status = await runtime.update()

        XCTAssertEqual(status.outcome, .failed)
        XCTAssertEqual(runtime.render("auth.sign_out"), "Выход")
        XCTAssertFalse(reported.isEmpty)
    }

    func testTimeout() async {
        let reported = Reported()
        let transport = FakeTransport([
            "/version": .failed("operation timed out after 10s")
        ])

        let status = await runtimeWith(transport: transport, reported: reported).update()

        XCTAssertEqual(status.outcome, .failed)
        XCTAssertFalse(reported.isEmpty)
    }

    func testNon200IsReportedWithItsStatus() async {
        for status in [401, 403, 404, 500, 503] {
            let reported = Reported()
            let transport = FakeTransport([
                "/version": ok(versionBody("1.0.1")),
                "/translations": LocalazeResponse(status: status),
            ])
            let runtime = runtimeWith(transport: transport, reported: reported)

            let result = await runtime.update()

            XCTAssertEqual(result.outcome, .failed, "\(status)")
            // A 401 is a wrong key and must be distinguishable from a quiet
            // network by whoever reads the log.
            XCTAssertTrue(reported.mentions("\(status)"), "\(reported.messages)")
            XCTAssertEqual(runtime.render("auth.sign_out"), "Выход")
        }
    }

    func testMalformedJson() async {
        let transport = FakeTransport([
            "/version": ok(versionBody("1.0.1")),
            "/translations": ok(fixture("updates/malformed-syntax-ru.txt")),
        ])
        let runtime = runtimeWith(transport: transport)

        let status = await runtime.update()

        XCTAssertEqual(status.outcome, .failed)
        XCTAssertEqual(runtime.render("auth.sign_out"), "Выход")
    }

    func testMissingMessages() async {
        let reported = Reported()
        let transport = FakeTransport([
            "/version": ok(versionBody("1.0.4")),
            "/translations": ok(fixture("updates/malformed-shape-ru.json")),
        ])
        let runtime = runtimeWith(transport: transport, reported: reported)

        let status = await runtime.update()

        XCTAssertEqual(status.outcome, .failed)
        XCTAssertTrue(reported.mentions("no readable messages"))
        XCTAssertEqual(runtime.render("auth.sign_out"), "Выход")
    }

    func testCorruptCacheIgnored() async {
        let reported = Reported()
        let storage = FakeStorage(cache: "{\"messages\": trunc")
        let runtime = runtimeWith(storage: storage, reported: reported)

        await runtime.load()

        XCTAssertTrue(reported.mentions("unreadable cached ru catalog"))
        XCTAssertEqual(runtime.render("auth.sign_out"), "Выход")
    }

    func testMissingAsset() async {
        // assetPath points nowhere. Every key still renders, from the
        // compiled-in copy. This is why a path typo is stale text and never a
        // blank screen.
        let runtime = runtimeWith(storage: FakeStorage())
        await runtime.load()

        XCTAssertEqual(runtime.render("auth.sign_out"), "Выход")
        XCTAssertEqual(
            runtime.render("inbox.unread", args: ["count": 2], selector: 2),
            "У вас 2 сообщения")
    }

    func testUnwritableCache() async {
        let reported = Reported()
        let storage = FakeStorage(writable: false)
        let transport = FakeTransport([
            "/version": ok(versionBody("1.0.1")),
            "/translations": ok(fixture("updates/patch-1.0.1-ru.json")),
        ])
        let runtime = runtimeWith(
            transport: transport, storage: storage, reported: reported)

        let status = await runtime.update()

        // Applied, and reported as not persisted. Not an error.
        XCTAssertEqual(status.outcome, .applied)
        XCTAssertTrue(status.detail?.contains("session only") ?? false)
        XCTAssertEqual(runtime.render("auth.sign_out"), "Выйти")
        XCTAssertTrue(reported.mentions("Could not cache"))
    }

    func testNoTransportConfiguredIsReported() async {
        let reported = Reported()
        let runtime = runtimeWith(reported: reported)

        let status = await runtime.update()

        XCTAssertEqual(status.outcome, .failed)
        XCTAssertTrue(reported.mentions("No transport configured"))
    }

    func testUnreadableCompiledInCatalogStillRuns() {
        let reported = Reported()
        let runtime = runtimeWith(reported: reported, compiledIn: "not json at all")

        // A generator bug, not a runtime condition. Failing soft keeps the
        // no-throw rule and renders key names, which is loud enough to notice.
        XCTAssertEqual(runtime.render("auth.sign_out"), "auth.sign_out")
        XCTAssertTrue(reported.mentions("compiled-in ru catalog"))
    }

    func testLastStatusReadable() async {
        let runtime = runtimeWith(
            transport: FakeTransport(["/version": .failed("down")]))

        XCTAssertEqual(runtime.lastFetch.outcome, LocalazeFetchOutcome.none)

        await runtime.update()

        XCTAssertEqual(runtime.lastFetch.outcome, .failed)
        XCTAssertNotNil(runtime.lastFetch.detail)
    }

    func testEveryFailureAtOnce() async {
        // Dead network, unreadable cache, no asset, unwritable storage.
        let transport = FakeTransport()
        transport.failEverything = "boom"
        let storage = FakeStorage(cache: "corrupt{", writable: false)

        let runtime = runtimeFor(
            "ru",
            config: LocalazeConfig(
                apiKey: "k", transport: transport, storage: storage))

        await runtime.load()
        await runtime.update()

        XCTAssertFalse(runtime.applyPending())
        XCTAssertEqual(runtime.render("auth.sign_out"), "Выход")
        XCTAssertEqual(runtime.version, "1.0.0")
        XCTAssertEqual(runtime.lastFetch.outcome, .failed)
    }
}
