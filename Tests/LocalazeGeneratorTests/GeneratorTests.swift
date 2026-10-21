/// The generator against the shared fixture project.
///
/// See `contract/generator-contract.md` §9 and the `generator` group of
/// `contract/conformance.json`.

import Foundation
@testable import LocalazeGenerator
import XCTest

let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // LocalazeGeneratorTests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()  // localaze-swift

let fixtures = packageRoot.deletingLastPathComponent().appendingPathComponent("contract/fixtures")
let goldenPath = packageRoot.appendingPathComponent("Tests/LocalazeGoldenTests/Localaze.g.swift")

func fixture(_ path: String) -> String {
    try! String(contentsOf: fixtures.appendingPathComponent(path), encoding: .utf8)
}

func json(_ text: String) -> [String: Any] {
    try! JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
}

func text(_ object: Any) -> String {
    String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
}

func catalogs() -> [String: String] {
    ["az": fixture("catalogs/az.json"), "ru": fixture("catalogs/ru.json")]
}

func planFixture(manifest: [String: Any]? = nil, catalogs given: [String: String]? = nil,
         allowGaps: Bool = false) -> PlanResult {
    plan(manifest: text(manifest ?? json(fixture("manifest.json"))),
         catalogs: given ?? catalogs(), allowGaps: allowGaps)
}

/// The fixture manifest with one more key.
func withKey(_ entry: [String: Any]) -> [String: Any] {
    var manifest = json(fixture("manifest.json"))
    manifest["keys"] = (manifest["keys"] as! [Any]) + [entry]
    return manifest
}

/// A catalog with `key` added to its messages.
func catalog(_ language: String, adding key: String, _ message: [String: Any]) -> String {
    var catalog = json(fixture("catalogs/\(language).json"))
    var messages = catalog["messages"] as! [String: Any]
    messages[key] = message
    catalog["messages"] = messages
    return text(catalog)
}

let simple: [String: Any] = [
    "selectors": [String](), "params": [Any](), "variants": ["*": [["text": "x"]]],
]

final class GeneratorTests: XCTestCase {
    func testGolden() throws {
        let result = planFixture()
        XCTAssertEqual(result.problems, [])
        let source = emitSwift(try XCTUnwrap(result.plan))

        // UPDATE_GOLDEN=1 rewrites the file. The diff is then reviewed like
        // any other change, which is the point of a golden.
        if ProcessInfo.processInfo.environment["UPDATE_GOLDEN"] == "1" {
            try source.write(to: goldenPath, atomically: true, encoding: .utf8)
        }
        XCTAssertEqual(source, try String(contentsOf: goldenPath, encoding: .utf8))
    }

    func testSameInputSameOutput() {
        XCTAssertEqual(emitSwift(planFixture().plan!), emitSwift(planFixture().plan!))
    }

    func testCatalogsAreCarriedByteForByte() {
        let planned = planFixture().plan!
        XCTAssertEqual(planned.catalogs, catalogs())
        XCTAssertEqual(planned.languages, ["az", "ru"])
    }

    func testMissingCatalog() {
        let result = planFixture(catalogs: ["az": fixture("catalogs/az.json")])
        XCTAssertNil(result.plan)
        XCTAssertTrue(result.problems.contains("No catalog for language \"ru\"."))
    }

    func testMissingKeyFails() {
        var ru = json(fixture("catalogs/ru.json"))
        var messages = ru["messages"] as! [String: Any]
        messages["auth.sign_out"] = nil
        ru["messages"] = messages
        let result = planFixture(catalogs: ["az": fixture("catalogs/az.json"), "ru": text(ru)])

        XCTAssertNil(result.plan)
        XCTAssertTrue(result.problems.contains("auth.sign_out is missing in ru."))
    }

    func testAllowGapsWarns() {
        var ru = json(fixture("catalogs/ru.json"))
        var messages = ru["messages"] as! [String: Any]
        messages["auth.sign_out"] = nil
        ru["messages"] = messages
        let result = planFixture(catalogs: ["az": fixture("catalogs/az.json"), "ru": text(ru)], allowGaps: true)

        XCTAssertNotNil(result.plan)
        XCTAssertEqual(result.warnings, ["auth.sign_out is missing in ru."])
    }

    func testVersionMismatch() {
        var ru = json(fixture("catalogs/ru.json"))
        ru["version"] = "1.0.1"
        let result = planFixture(catalogs: ["az": fixture("catalogs/az.json"), "ru": text(ru)])

        XCTAssertNil(result.plan)
        XCTAssertTrue(result.problems.contains(
            "The \"ru\" catalog is version 1.0.1, but the manifest is 1.0.0."))
    }

    func testUnsupportedOperand() {
        var manifest = json(fixture("manifest.json"))
        var rules = manifest["pluralRules"] as! [String: Any]
        rules["ru"] = ["one": "f == 1"]
        manifest["pluralRules"] = rules
        let result = planFixture(manifest: manifest)

        XCTAssertNil(result.plan)
        XCTAssertEqual(result.problems.count, 1)
        XCTAssertTrue(result.problems[0].contains("uses f"))
    }

    func testUnrecognisedRule() {
        var manifest = json(fixture("manifest.json"))
        var rules = manifest["pluralRules"] as! [String: Any]
        rules["ru"] = ["one": "n == 1; exit(0)"]
        manifest["pluralRules"] = rules
        let result = planFixture(manifest: manifest)

        XCTAssertNil(result.plan)
        XCTAssertTrue(result.problems[0].contains("exit"))
    }

    func testAccessorCollision() {
        var manifest = json(fixture("manifest.json"))
        manifest["keys"] = [
            ["key": "a.b_c", "params": [Any](), "selects": false],
            ["key": "a_b.c", "params": [Any](), "selects": false],
        ]
        let result = planFixture(manifest: manifest, catalogs: [
            "az": catalog("az", adding: "a_b.c", simple),
            "ru": catalog("ru", adding: "a_b.c", simple),
        ], allowGaps: true)

        XCTAssertNil(result.plan)
        XCTAssertTrue(result.problems.contains(
            "Keys \"a.b_c\" and \"a_b.c\" both generate the accessor \"aBC\"."))
    }

    func testReservedMember() {
        let result = planFixture(
            manifest: withKey(["key": "runtime", "params": [Any](), "selects": false]),
            catalogs: [
                "az": catalog("az", adding: "runtime", simple),
                "ru": catalog("ru", adding: "runtime", simple),
            ])

        XCTAssertNil(result.plan)
        XCTAssertTrue(result.problems[0].contains("\"runtime\", which is reserved"))
    }

    func testNonNumberSelector() {
        let message: [String: Any] = [
            "selectors": ["who"], "params": [["name": "who", "type": "STRING"]],
            "variants": ["*": [["var": "who", "type": "STRING"]]],
        ]
        let result = planFixture(
            manifest: withKey(["key": "greeting", "params": [["name": "who", "type": "STRING"]], "selects": true]),
            catalogs: [
                "az": catalog("az", adding: "greeting", message),
                "ru": catalog("ru", adding: "greeting", message),
            ])

        XCTAssertNil(result.plan)
        XCTAssertTrue(result.problems[0].contains("selects on $who, a STRING"))
    }

    func testAllProblemsReported() {
        var manifest = json(fixture("manifest.json"))
        var rules = manifest["pluralRules"] as! [String: Any]
        rules["ru"] = ["one": "t == 1"]
        manifest["pluralRules"] = rules
        let result = planFixture(manifest: manifest, catalogs: ["az": fixture("catalogs/az.json")])

        XCTAssertEqual(result.problems.count, 2)
    }

    func testReservedSwiftWordIsBackticked() {
        let message: [String: Any] = [
            "selectors": [String](), "params": [["name": "in", "type": "STRING"]],
            "variants": ["*": [["var": "in", "type": "STRING"]]],
        ]
        let result = planFixture(
            manifest: withKey(["key": "default", "params": [["name": "in", "type": "STRING"]], "selects": false]),
            catalogs: [
                "az": catalog("az", adding: "default", message),
                "ru": catalog("ru", adding: "default", message),
            ])

        let source = emitSwift(result.plan!)
        XCTAssertTrue(source.contains("public func `default`(`in`: String) -> String {"))
        XCTAssertTrue(source.contains("args: [\"in\": `in`]"))
    }

    func testFloatingPointModuloIsRewritten() {
        XCTAssertEqual(swiftCondition("(n % 10) == 1 && (n % 100) != 11"),
                       "n.truncatingRemainder(dividingBy: 10) == 1 && n.truncatingRemainder(dividingBy: 100) != 11")
        XCTAssertEqual(swiftCondition("(i % 10) == 1"), "(i % 10) == 1")
    }
}
