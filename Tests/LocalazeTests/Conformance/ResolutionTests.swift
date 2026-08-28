/// Conformance group: resolution. Contract section 7.

import Foundation
import XCTest

@testable import Localaze

final class ResolutionTests: XCTestCase {

    func testAppliedOverCachedOverBundled() async {
        let storage = FakeStorage(
            asset: catalogSaying("from-bundled", "1.0.0"),
            cache: catalogSaying("from-cached", "1.0.0"))
        let transport = FakeTransport([
            "/version": ok(versionBody("1.0.1")),
            "/translations": ok(catalogSaying("from-applied", "1.0.1")),
        ])

        let runtime = runtimeFor(
            "ru",
            config: LocalazeConfig(
                apiKey: "k", applyImmediately: true,
                transport: transport, storage: storage),
            compiledIn: catalogSaying("from-compiled-in", "1.0.0"))

        XCTAssertEqual(runtime.render("auth.sign_out"), "from-compiled-in")

        await runtime.load()
        XCTAssertEqual(runtime.render("auth.sign_out"), "from-cached")

        await runtime.update()
        XCTAssertEqual(runtime.render("auth.sign_out"), "from-applied")
    }

    func testBundledBeatsCompiledInWhenThereIsNoCache() async {
        let storage = FakeStorage(asset: catalogSaying("from-bundled", "1.0.0"))
        let runtime = runtimeFor(
            "ru",
            config: LocalazeConfig(apiKey: "k", storage: storage),
            compiledIn: catalogSaying("from-compiled-in", "1.0.0"))

        await runtime.load()
        XCTAssertEqual(runtime.render("auth.sign_out"), "from-bundled")
    }

    func testPerKeyFallback() async {
        // partial-ru.json omits billing.due. The three keys it has come from
        // the asset; the missing one falls through to the compiled-in copy.
        // Per key, not per catalog.
        let storage = FakeStorage(asset: fixture("bundled/partial-ru.json"))
        let runtime = runtimeFor(
            "ru", config: LocalazeConfig(apiKey: "k", storage: storage))

        await runtime.load()

        XCTAssertEqual(runtime.render("auth.sign_out"), "Выход")
        XCTAssertEqual(
            runtime.render("billing.due", args: ["when": utc(2026, 3, 1)]),
            "Оплата до 2026-03-01T00:00:00Z")
    }

    func testCacheSurvivesLaunch() async {
        let storage = FakeStorage(asset: catalogSaying("from-bundled", "1.0.0"))
        let transport = FakeTransport([
            "/version": ok(versionBody("1.0.1")),
            "/translations": ok(catalogSaying("from-applied", "1.0.1")),
        ])

        let first = runtimeFor(
            "ru",
            config: LocalazeConfig(
                apiKey: "k", applyImmediately: true,
                transport: transport, storage: storage),
            compiledIn: catalogSaying("compiled", "1.0.0"))
        await first.load()
        await first.update()

        let relaunched = runtimeFor(
            "ru",
            config: LocalazeConfig(apiKey: "k", storage: storage),
            compiledIn: catalogSaying("compiled", "1.0.0"))
        await relaunched.load()

        XCTAssertEqual(relaunched.render("auth.sign_out"), "from-applied")
        XCTAssertEqual(relaunched.version, "1.0.1")
    }

    func testNoStorageIsSessionOnly() async {
        let transport = FakeTransport([
            "/version": ok(versionBody("1.0.1")),
            "/translations": ok(catalogSaying("from-applied", "1.0.1")),
        ])
        let config = LocalazeConfig(
            apiKey: "k", applyImmediately: true, transport: transport)

        let session = runtimeFor(
            "ru", config: config, compiledIn: catalogSaying("compiled", "1.0.0"))
        let status = await session.update()

        XCTAssertEqual(status.outcome, .applied)
        XCTAssertTrue(status.detail?.contains("this session only") ?? false)
        XCTAssertEqual(session.render("auth.sign_out"), "from-applied")

        let relaunched = runtimeFor(
            "ru", config: config, compiledIn: catalogSaying("compiled", "1.0.0"))
        await relaunched.load()
        XCTAssertEqual(relaunched.render("auth.sign_out"), "compiled")
    }

    func testOfflineFirstLaunch() {
        // Fresh install, no network, no cache. Every key still renders, and no
        // request is made at all.
        let transport = FakeTransport()
        let runtime = runtimeFor(
            "ru", config: LocalazeConfig(apiKey: "k", transport: transport))

        XCTAssertEqual(runtime.render("auth.sign_out"), "Выход")
        XCTAssertEqual(
            runtime.render("auth.welcome", args: ["name": "Аян"]),
            "Добро пожаловать, Аян")
        XCTAssertEqual(
            runtime.render("inbox.unread", args: ["count": 11], selector: 11),
            "У вас 11 сообщений")
        XCTAssertTrue(transport.urls.isEmpty)
    }

    func testApplyImmediatelyOffHoldsTheCatalog() async {
        let transport = FakeTransport([
            "/version": ok(versionBody("1.0.1")),
            "/translations": ok(catalogSaying("from-applied", "1.0.1")),
        ])
        let runtime = runtimeFor(
            "ru",
            config: LocalazeConfig(apiKey: "k", transport: transport),
            compiledIn: catalogSaying("compiled", "1.0.0"))

        await runtime.update()
        XCTAssertEqual(
            runtime.render("auth.sign_out"), "compiled",
            "text must not change under a user mid-session")

        XCTAssertTrue(runtime.applyPending())
        XCTAssertEqual(runtime.render("auth.sign_out"), "from-applied")
        XCTAssertFalse(runtime.applyPending())
    }
}

private func utc(_ year: Int, _ month: Int, _ day: Int) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar.date(from: DateComponents(year: year, month: month, day: day))!
}
