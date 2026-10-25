/// The generated code, compiled against the runtime, rendering the fixture.
///
/// This is the `LZ-54` guarantee for generation: the three generators agree
/// because their output renders the same strings, not because their source
/// looks alike. See `contract/generator-contract.md` §9.

import Foundation
import Localaze
import XCTest

/// Loads a file from `contract/fixtures`, reached through `#filePath`.
private func fixture(_ path: String) -> String {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // LocalazeGoldenTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // the package root
    return try! String(contentsOf: root.appendingPathComponent("contract/fixtures/\(path)"), encoding: .utf8)
}

private func translations(_ locale: String) -> Localaze {
    Localaze.forLocale(locale, config: LocalazeConfig(apiKey: "test-key"))
}

/// Calls the typed accessor for `key`, the way an app would.
private func render(_ t: Localaze, _ key: String, _ args: [String: Any]) -> String {
    switch key {
    case "auth.sign_out": return t.authSignOut
    case "auth.welcome": return t.authWelcome(name: args["name"] as! String)
    case "billing.due":
        return t.billingDue(when: ISO8601DateFormatter().date(from: args["when"] as! String)!)
    case "inbox.unread": return t.inboxUnread(count: (args["count"] as! NSNumber).intValue)
    default: fatalError("No accessor for \(key)")
    }
}

final class GoldenRenderTests: XCTestCase {
    func testRendersAll() throws {
        let data = Data(fixture("expected-renders.json").utf8)
        let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let renders = root["renders"] as! [[String: Any]]
        XCTAssertFalse(renders.isEmpty)

        for row in renders {
            let locale = row["locale"] as! String
            let key = row["key"] as! String
            XCTAssertEqual(
                render(translations(locale), key, row["args"] as! [String: Any]),
                row["expect"] as? String,
                "\(locale) \(key) \(row["args"]!)")
        }
    }

    func testTypedAccessorsAndConstants() {
        XCTAssertEqual(Localaze.supportedLocales, ["az", "ru"])
        XCTAssertEqual(Localaze.sourceLocale, "az")
        XCTAssertEqual(Localaze.generatedFrom, "1.0.0")

        // Any standard number is accepted, integral or not.
        let ru = translations("ru")
        XCTAssertEqual(ru.inboxUnread(count: 11), "У вас 11 сообщений")
        XCTAssertEqual(ru.inboxUnread(count: Int64(21)), "У вас 21 сообщение")
        XCTAssertEqual(ru.inboxUnread(count: 1.5), "У вас 1.5 сообщения")
    }

    func testPluralGuardRendersTheCatchAll() {
        let ru = translations("ru")
        for value in [Double.infinity, Double.nan, 1e15, -1e16] {
            XCTAssertTrue(ru.inboxUnread(count: value).hasSuffix("сообщения"), "\(value)")
        }
    }

    func testUncarriedLocaleStartsFromTheSourceLanguage() {
        XCTAssertEqual(translations("en").authSignOut, "Cixis")
    }
}
