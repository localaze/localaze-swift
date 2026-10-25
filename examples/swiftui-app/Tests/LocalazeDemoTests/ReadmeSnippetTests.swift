@testable import LocalazeDemo
import Localaze
import XCTest

/// The README's examples, run: what it says they render is what they render.
final class ReadmeSnippetTests: XCTestCase {
    func testTheReadmeRendersWhatItSays() {
        let t = Localaze.forLocale("ru", config: LocalazeConfig(apiKey: "test-key"))
        XCTAssertEqual(ReadmeSnippets.use(t), [
            "Выход",
            "Добро пожаловать, Аян",
            "У вас 1 сообщение",
            "У вас 11 сообщений",
            "Оплата до 2026-03-01T00:00:00Z",
        ])
    }

    func testEveryOptionIsTheDefault() {
        let config = ReadmeSnippets.everyOption("k")
        XCTAssertEqual(config.baseUrl, LocalazeConfig(apiKey: "k").baseUrl)
        XCTAssertEqual(config.timeout, LocalazeConfig(apiKey: "k").timeout)
    }
}
