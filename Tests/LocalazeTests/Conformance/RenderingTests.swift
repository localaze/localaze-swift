/// Conformance group: rendering. Contract section 3.

import Foundation
import XCTest

@testable import Localaze

final class RenderingTests: XCTestCase {

    /// Drives every row of the shared `expected-renders.json`, so Dart, Swift
    /// and Kotlin assert against the identical set and a new case lands in all
    /// three at once.
    func testRenderAll() throws {
        let raw = fixture("expected-renders.json").data(using: .utf8)!
        let decoded = try JSONSerialization.jsonObject(with: raw) as! [String: Any]
        let rows = decoded["renders"] as! [[String: Any]]

        XCTAssertGreaterThanOrEqual(rows.count, 20, "a dropped row would hollow out this test")

        for row in rows {
            let locale = row["locale"] as! String
            let key = row["key"] as! String
            let want = row["expect"] as! String
            let args = coerce(row["args"] as! [String: Any])

            let runtime = runtimeFor(locale)
            let selector = (args["count"] as? Int).map(Double.init)

            XCTAssertEqual(
                runtime.render(key, args: args, selector: selector),
                want,
                "\(locale) \(key)")
        }
    }

    func testRenderMissingCategoryFallsBack() {
        // A ru catalog whose inbox.unread has only `one` and `*`. Count 5
        // resolves to `many`, which is absent, so `*` must answer. LZ-07
        // guarantees `*` is always there.
        let runtime = runtimeFor("ru", compiledIn: fixture("bundled/partial-ru.json"))

        XCTAssertEqual(
            runtime.render("inbox.unread", args: ["count": 5], selector: 5),
            "У вас 5 сообщения")
    }

    func testRenderMalformedPartSkipped() throws {
        let body = """
            {"version":"1.0.0","messages":{"a.b":{"selectors":[],"params":[],
             "variants":{"*":[{"text":"before "},{"note":"neither"},{"text":"after"}]}}}}
            """
        let catalog = try XCTUnwrap(LocalazeCatalog.parse(body))
        let parts = try XCTUnwrap(catalog.messages["a.b"]?.parts(for: nil))

        XCTAssertEqual(localazeRender(parts, [:]), "before after")
    }

    func testIsoUtcIsSecondPrecision() {
        // Not ISO8601DateFormatter, whose output depends on option flags a
        // future Foundation could change under us.
        XCTAssertEqual(localazeIsoUtc(date(2026, 3, 1)), "2026-03-01T00:00:00Z")
        XCTAssertEqual(
            localazeIsoUtc(date(2026, 12, 31, 23, 59, 59)), "2026-12-31T23:59:59Z")
    }

    func testAppSuppliedFormatterWins() {
        let runtime = runtimeFor(
            "az",
            config: LocalazeConfig(
                apiKey: "k",
                dateFormatter: { value in
                    var calendar = Calendar(identifier: .gregorian)
                    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
                    let parts = calendar.dateComponents([.day, .month], from: value)
                    return "\(parts.day!)/\(parts.month!)"
                }))

        XCTAssertEqual(
            runtime.render("billing.due", args: ["when": date(2026, 3, 1)]),
            "Odenis 1/3 tarixindedir")
    }

    func testIntegralDoubleHasNoDecimalPoint() {
        // 3.0 must read as "3" here, in Dart and in Kotlin alike.
        let runtime = runtimeFor("az")
        XCTAssertEqual(
            runtime.render("inbox.unread", args: ["count": 3.0], selector: 3.0), "3 mesaj")
    }

    func testFractionalValueKeepsItsPoint() {
        let runtime = runtimeFor("az")
        XCTAssertEqual(
            runtime.render("inbox.unread", args: ["count": 2.5], selector: 2.5), "2.5 mesaj")
    }

    func testUnknownKeyRendersTheKeyAndReports() {
        let reported = Reported()
        let runtime = runtimeFor(
            "az", config: LocalazeConfig(apiKey: "k", onDiagnostic: reported.callback))

        XCTAssertEqual(runtime.render("nope.missing"), "nope.missing")
        XCTAssertTrue(reported.mentions("nope.missing"))
    }
}

/// Fixture args are JSON, so a datetime arrives as a string.
private func coerce(_ args: [String: Any]) -> [String: Any] {
    var out: [String: Any] = [:]
    for (key, value) in args {
        if key == "when", let raw = value as? String {
            out[key] = ISO8601DateFormatter().date(from: raw)
        } else {
            out[key] = value
        }
    }
    return out
}

private func date(
    _ year: Int, _ month: Int, _ day: Int,
    _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0
) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar.date(
        from: DateComponents(
            year: year, month: month, day: day,
            hour: hour, minute: minute, second: second))!
}
