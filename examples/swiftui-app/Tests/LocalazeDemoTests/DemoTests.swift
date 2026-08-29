/// Drives the demo's model against a fake transport.
///
/// `swift build` says the app compiles; these say it works. Every scenario the
/// Server section offers is exercised here through the real generated
/// accessors and the real runtime, so the app is covered rather than assumed.
///
/// No network: the fake transport means these run in CI and on a plane.

import Localaze
import XCTest

@testable import LocalazeDemo

/// Serves whatever it is told to, recording what was asked.
final class FakeTransport: LocalazeTransport, @unchecked Sendable {
    var responses: [String: LocalazeResponse]
    private(set) var urls: [String] = []

    init(_ responses: [String: LocalazeResponse] = [:]) {
        self.responses = responses
    }

    func get(_ url: String, headers: [String: String]) async -> LocalazeResponse {
        urls.append(url)
        for (fragment, response) in responses where url.contains(fragment) {
            return response
        }
        return LocalazeResponse(status: 404)
    }
}

private func ok(_ body: String) -> LocalazeResponse {
    LocalazeResponse(status: 200, body: body)
}

private func versionBody(_ version: String) -> String {
    #"{"environment":"demo","version":"\#(version)","bump":"PATCH","keyCount":4}"#
}

/// A ru catalog at `version` whose sign-out reads `signOut`.
///
/// `countType` is what makes the retype case reachable: `STRING` here is a
/// catalog that kept the key and the parameter name but changed its type.
private func catalog(
    _ version: String,
    signOut: String = "Выход",
    countType: String = "NUMBER"
) -> String {
    """
    {"version":"\(version)","language":"ru","messages":{
    "auth.sign_out":{"selectors":[],"params":[],"variants":{"*":[{"text":"\(signOut)"}]}},
    "auth.welcome":{"selectors":[],"params":[{"name":"name","type":"STRING"}],
      "variants":{"*":[{"text":"Добро пожаловать, "},{"var":"name","type":"STRING"}]}},
    "billing.due":{"selectors":[],"params":[{"name":"when","type":"DATETIME"}],
      "variants":{"*":[{"text":"Оплата до "},{"var":"when","type":"DATETIME"}]}},
    "inbox.unread":{"selectors":["count"],"params":[{"name":"count","type":"\(countType)"}],
      "variants":{
        "one":[{"text":"У вас "},{"var":"count","type":"\(countType)"},{"text":" сообщение"}],
        "few":[{"text":"У вас "},{"var":"count","type":"\(countType)"},{"text":" сообщения"}],
        "many":[{"text":"У вас "},{"var":"count","type":"\(countType)"},{"text":" сообщений"}],
        "*":[{"text":"У вас "},{"var":"count","type":"\(countType)"},{"text":" сообщения"}]}}}}
    """
}

@MainActor
final class GeneratedAccessorTests: XCTestCase {

    func testRenderFromCompiledInWithNoNetwork() {
        // The offline-first-launch case: a fresh install with nothing.
        let az = Localaze.forLocale("az", config: LocalazeConfig(apiKey: "k"))

        XCTAssertEqual(az.authSignOut, "Cixis")
        XCTAssertEqual(az.authWelcome(name: "Ayan"), "Xos geldiniz, Ayan")
        XCTAssertEqual(az.inboxUnread(count: 3), "3 mesaj")
    }

    func testRussianPluralIncludingTheElevenException() {
        let ru = Localaze.forLocale("ru", config: LocalazeConfig(apiKey: "k"))

        // The values the demo's buttons offer, and the reason the rule is
        // generated rather than guessed.
        XCTAssertEqual(ru.inboxUnread(count: 1), "У вас 1 сообщение")
        XCTAssertEqual(ru.inboxUnread(count: 2), "У вас 2 сообщения")
        XCTAssertEqual(ru.inboxUnread(count: 5), "У вас 5 сообщений")
        XCTAssertEqual(ru.inboxUnread(count: 11), "У вас 11 сообщений")
        XCTAssertEqual(ru.inboxUnread(count: 21), "У вас 21 сообщение")
        XCTAssertEqual(ru.inboxUnread(count: 101), "У вас 101 сообщение")
        XCTAssertEqual(ru.inboxUnread(count: 111), "У вас 111 сообщений")
    }

    func testRendersMatchTheDartAndKotlinDemos() {
        // Identical output across platforms is the LZ-54 guarantee, and the
        // demos have to honour it as much as the packages do.
        let az = Localaze.forLocale("az", config: LocalazeConfig(apiKey: "k"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!

        XCTAssertEqual(az.billingDue(when: date), "Odenis 2026-03-01T00:00:00Z tarixindedir")
    }
}

@MainActor
final class DemoModelTests: XCTestCase {

    func testSwitchesLocaleWithoutRestart() {
        let model = DemoModel(transport: FakeTransport())

        XCTAssertEqual(model.translations.authSignOut, "Cixis")
        model.setLocale("ru")
        XCTAssertEqual(model.translations.authSignOut, "Выход")
    }

    func testIgnoresAnUnsupportedLocale() {
        let model = DemoModel(transport: FakeTransport())
        model.setLocale("fr")
        XCTAssertEqual(model.locale, "az")
    }

    func testAppliesAPatch() async {
        let model = DemoModel(transport: FakeTransport([
            "/version": ok(versionBody("1.0.1")),
            "/translations": ok(catalog("1.0.1", signOut: "Выйти")),
        ]))
        model.setLocale("ru")

        XCTAssertEqual(model.translations.authSignOut, "Выход")

        await model.update()

        XCTAssertEqual(model.lastStatus?.outcome, .applied)
        XCTAssertEqual(model.translations.authSignOut, "Выйти")
        XCTAssertEqual(model.version, "1.0.1")
    }

    func testRefusesAMajor() async {
        let model = DemoModel(transport: FakeTransport([
            "/version": ok(versionBody("2.0.0"))
        ]))
        model.setLocale("ru")

        await model.update()

        XCTAssertEqual(model.lastStatus?.outcome, .refusedByPolicy)
        XCTAssertEqual(model.translations.authSignOut, "Выход")
    }

    func testRefusesARetypedPatch() async {
        // The case the demo's "retyped" option sets up. Policy accepts it,
        // every key is present, and the parameter is still called count.
        let model = DemoModel(transport: FakeTransport([
            "/version": ok(versionBody("1.0.2")),
            "/translations": ok(catalog("1.0.2", signOut: "Выйти", countType: "STRING")),
        ]))
        model.setLocale("ru")

        await model.update()

        XCTAssertEqual(model.lastStatus?.outcome, .refusedBySignature)
        XCTAssertTrue(
            model.lastStatus?.detail?.contains("inbox.unread.count") ?? false,
            model.lastStatus?.detail ?? "no detail")
        // Refused whole: sign-out is fine in that catalog and still not taken.
        XCTAssertEqual(model.translations.authSignOut, "Выход")
    }

    func testReportsRatherThanThrowsWhenTheServerIsDown() async {
        let model = DemoModel(transport: FakeTransport([
            "/version": LocalazeResponse.failed("connection refused")
        ]))
        model.setLocale("ru")

        await model.update()

        XCTAssertEqual(model.lastStatus?.outcome, .failed)
        XCTAssertFalse(model.diagnostics.isEmpty)
        XCTAssertEqual(model.translations.authSignOut, "Выход")
    }

    func testAWrongKeyIsDistinguishableFromAQuietNetwork() async {
        // The defect the live run found: without the status in the diagnostic,
        // a 401 and a dead network read identically.
        let model = DemoModel(transport: FakeTransport([
            "/version": LocalazeResponse(status: 401)
        ]))

        await model.update()

        XCTAssertTrue(
            model.diagnostics.contains { $0.contains("401") },
            "\(model.diagnostics)")
    }

    func testNothingNewIsUpToDateNotARefusal() async {
        let model = DemoModel(transport: FakeTransport([
            "/version": ok(versionBody("1.0.0"))
        ]))

        await model.update()

        XCTAssertEqual(model.lastStatus?.outcome, .upToDate)
    }

    func testPolicyNoneMakesNoRequest() async {
        let transport = FakeTransport(["/version": ok(versionBody("1.0.1"))])
        let model = DemoModel(transport: transport)
        model.policy = .none

        await model.update()

        XCTAssertTrue(transport.urls.isEmpty)
    }
}
