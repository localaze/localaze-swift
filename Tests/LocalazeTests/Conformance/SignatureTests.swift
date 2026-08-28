/// Conformance group: signature. Contract section 4.
///
/// The group that matters most. The first implementation compared parameter
/// names only, which accepts a retype, and a retype is the likelier edit.

import XCTest

@testable import Localaze

private func parse(_ path: String) -> LocalazeCatalog {
    LocalazeCatalog.parse(fixture(path))!
}

final class SignatureTests: XCTestCase {

    func testAcceptsTheCatalogItWasGeneratedFrom() {
        XCTAssertTrue(fixtureSignature.incompatibilities(parse("catalogs/ru.json")).isEmpty)
    }

    func testRetypedParameterRefused() throws {
        // 1.0.2 is a patch, so policy accepts it. Every key is present, so a
        // key-set check accepts it. inbox.unread still declares a parameter
        // named "count", so a name-only check accepts it too.
        //
        // The type changed from NUMBER to STRING. Generated code has already
        // promised every call site inboxUnread(count: Int).
        let problems = fixtureSignature.incompatibilities(
            parse("updates/retyped-1.0.2-ru.json"))

        XCTAssertEqual(problems.count, 1)
        let problem = try XCTUnwrap(problems.first)
        XCTAssertTrue(problem.contains("inbox.unread.count"), problem)
        XCTAssertTrue(problem.contains("now string"), problem)
        XCTAssertTrue(problem.contains("generated as number"), problem)
    }

    func testNameOnlyCheckWouldHaveAcceptedIt() {
        // Reproduces the old logic against the same fixture. If this ever
        // fails, the fixture stopped exercising the bug and the test above is
        // hollow.
        let catalog = parse("updates/retyped-1.0.2-ru.json")
        var namesOnly: [String] = []

        for (key, expected) in fixtureSignature.keys {
            guard let message = catalog.messages[key] else {
                namesOnly.append("missing \(key)")
                continue
            }
            let declared = Set(message.params.map(\.name))
            for param in expected where !declared.contains(param.name) {
                namesOnly.append("\(key) lost \(param.name)")
            }
        }

        XCTAssertTrue(
            namesOnly.isEmpty,
            "the name-only check finds nothing wrong, which is the defect")
    }

    func testMissingKeyRefused() {
        let problems = fixtureSignature.incompatibilities(
            parse("updates/major-2.0.0-ru.json"))

        XCTAssertTrue(problems.contains("auth.sign_out is missing"), "\(problems)")
    }

    func testAddedKeyIgnored() {
        // minor-1.1.0 adds settings.title, which no accessor references.
        let catalog = parse("updates/minor-1.1.0-ru.json")

        XCTAssertTrue(fixtureSignature.incompatibilities(catalog).isEmpty)
        XCTAssertNotNil(catalog.messages["settings.title"])
        XCTAssertNil(fixtureSignature.keys["settings.title"])
    }

    func testExtraParameterIgnored() {
        // The signature is a floor, not an equality.
        let body = """
            {"version":"1.0.1","messages":{
              "auth.sign_out":{"selectors":[],"params":[],"variants":{"*":[{"text":"x"}]}},
              "auth.welcome":{"selectors":[],"params":[
                {"name":"name","type":"STRING"},{"name":"extra","type":"NUMBER"}],
                "variants":{"*":[{"text":"hi "},{"var":"name","type":"STRING"}]}},
              "billing.due":{"selectors":[],"params":[{"name":"when","type":"DATETIME"}],
                "variants":{"*":[{"var":"when","type":"DATETIME"}]}},
              "inbox.unread":{"selectors":["count"],"params":[{"name":"count","type":"NUMBER"}],
                "variants":{"*":[{"var":"count","type":"NUMBER"}]}}}}
            """

        XCTAssertTrue(
            fixtureSignature.incompatibilities(LocalazeCatalog.parse(body)!).isEmpty)
    }

    func testRenamedParameterRefused() throws {
        let body = """
            {"version":"1.0.1","messages":{
              "auth.sign_out":{"selectors":[],"params":[],"variants":{"*":[{"text":"x"}]}},
              "auth.welcome":{"selectors":[],"params":[{"name":"username","type":"STRING"}],
                "variants":{"*":[{"var":"username","type":"STRING"}]}},
              "billing.due":{"selectors":[],"params":[{"name":"when","type":"DATETIME"}],
                "variants":{"*":[{"var":"when","type":"DATETIME"}]}},
              "inbox.unread":{"selectors":["count"],"params":[{"name":"count","type":"NUMBER"}],
                "variants":{"*":[{"var":"count","type":"NUMBER"}]}}}}
            """
        let problems = fixtureSignature.incompatibilities(LocalazeCatalog.parse(body)!)

        XCTAssertEqual(problems.count, 1)
        XCTAssertTrue(try XCTUnwrap(problems.first).contains("no longer takes \"name\""))
    }

    func testRefusalIsWhole() async {
        // One key of four is incompatible. None of the four may be applied.
        let transport = FakeTransport([
            "/version": ok(versionBody("1.0.2")),
            "/translations": ok(fixture("updates/retyped-1.0.2-ru.json")),
        ])
        let runtime = runtimeFor(
            "ru",
            config: LocalazeConfig(
                apiKey: "k", applyImmediately: true, transport: transport))

        let status = await runtime.update()

        XCTAssertEqual(status.outcome, .refusedBySignature)
        // auth.sign_out is identical in the refused catalog, and still must not
        // be taken from it.
        XCTAssertEqual(runtime.render("auth.sign_out"), "Выход")
        XCTAssertEqual(runtime.version, "1.0.0")
    }

    func testRecheckedAfterUpgrade() async {
        // A cached catalog written before the app upgraded, next to code that
        // now promises something else.
        let reported = Reported()
        let storage = FakeStorage(cache: fixture("updates/retyped-1.0.2-ru.json"))
        let runtime = runtimeFor(
            "ru",
            config: LocalazeConfig(
                apiKey: "k", onDiagnostic: reported.callback, storage: storage))

        await runtime.load()

        XCTAssertEqual(
            runtime.render("inbox.unread", args: ["count": 5], selector: 5),
            "У вас 5 сообщений")
        XCTAssertTrue(reported.mentions("Dropping the cached ru catalog"))
    }
}
