// The code the README shows, compiled by CI with the rest of this app, and run
// by ReadmeSnippetTests.
//
// `Localaze.g.swift` beside this file is what `localaze-generate` writes for
// the contract's fixture project; an app's own file has its own accessors.

import Foundation
import Localaze
import SwiftUI

enum ReadmeSnippets {
    static func setup() -> Localaze {
        // #region setup
        let t = Localaze.forLocale("ru", config: LocalazeConfig(
            apiKey: ProcessInfo.processInfo.environment["LOCALAZE_KEY"] ?? "",
            onDiagnostic: { message, error in print("localaze:", message, error ?? "") },
            transport: LocalazeUrlSessionTransport(),
            storage: LocalazeFileStorage()  // the app's `localaze` folder, and a cache
        ))
        // #endregion setup
        return t
    }

    static func use(_ t: Localaze) -> [String] {
        // #region use
        let lines = [
            t.authSignOut,                          // "Выход"
            t.authWelcome(name: "Аян"),             // "Добро пожаловать, Аян"
            t.inboxUnread(count: 1),                // "У вас 1 сообщение"
            t.inboxUnread(count: 11),               // "У вас 11 сообщений"
            t.billingDue(when: Date(timeIntervalSince1970: 1_772_323_200)),
        ]
        // Neither of these compiles:
        // t.inboxUnread()                  a plural needs its count
        // t.inboxUnread(count: "eleven")   the count is a number
        // #endregion use
        return lines
    }

    static func update(_ t: Localaze) async -> LocalazeFetchStatus {
        // #region update
        await t.runtime.load()                      // the cached catalog, if any
        let status = await t.runtime.update()       // never throws
        print(status.isApplied ? "now on \(t.runtime.version)" : "still on \(t.runtime.version)")
        // #endregion update
        return status
    }

    static func everyOption(_ key: String) -> LocalazeConfig {
        // #region config
        LocalazeConfig(
            apiKey: key,                            // carries the project and the environment
            baseUrl: "https://localize.sharpy.dev",
            policy: .minorAndPatch,
            timeout: 10,
            applyImmediately: false,
            dateFormatter: localazeIsoUtc,
            onDiagnostic: nil,
            transport: nil,                         // no network: LocalazeUrlSessionTransport()
            storage: nil                            // updates last for the session: LocalazeFileStorage()
        )
        // #endregion config
    }
}

// #region swiftui
@MainActor
final class Translations: ObservableObject {
    @Published private(set) var t: Localaze

    init(locale: String) { t = Self.make(locale) }

    func setLocale(_ locale: String) async {   // no restart
        t = Self.make(locale)
        await t.runtime.load()
    }

    func update() async {
        let status = await t.runtime.update()
        if status.isApplied { objectWillChange.send() }   // re-render with the new catalog
    }

    private static func make(_ locale: String) -> Localaze {
        Localaze.forLocale(locale, config: LocalazeConfig(
            apiKey: "…",
            transport: LocalazeUrlSessionTransport(),
            storage: LocalazeFileStorage()))
    }
}

struct InboxTitle: View {
    @EnvironmentObject var translations: Translations

    var body: some View {
        Text(translations.t.inboxUnread(count: 3))
            .task { await translations.update() }
    }
}
// #endregion swiftui
