/// The state behind the demo's views.
///
/// Everything SwiftUI-independent lives here so the tests can drive it without
/// rendering anything — which is also how a real app should hold the SDK.

import Foundation
import Localaze

/// Where the stub server is listening.
///
/// A simulator reaches the host as localhost. A device on the same network
/// wants the machine's address; pass it in the environment.
let baseUrl = ProcessInfo.processInfo.environment["LOCALAZE_BASE_URL"]
    ?? "http://localhost:8787"

/// The stub server's key. A real one carries the project and the environment.
let apiKey = "demo-key"

/// Mirrors the scenarios in `../../stub-server/serve.dart`.
enum Scenario: String, CaseIterable, Identifiable {
    case base, patch, minor, retyped, major, malformed, down

    var id: String { rawValue }

    var explanation: String {
        switch self {
        case .base:
            return "1.0.0 — what the app was built against. Nothing to take."
        case .patch:
            return "1.0.1 — a wording fix. Accepted under patchOnly and above."
        case .minor:
            return "1.1.0 — adds a key. Refused under patchOnly."
        case .retyped:
            return """
                1.0.2 — a patch that retypes count from NUMBER to STRING. \
                Policy accepts it, every key is present, and the parameter is \
                still called "count". Only the type check refuses it.
                """
        case .major:
            return "2.0.0 — drops a key. Refused under every policy."
        case .malformed:
            return "1.0.4 — a body with no messages."
        case .down:
            return "Every request fails, for the offline path."
        }
    }
}

@MainActor
final class DemoModel: ObservableObject {
    @Published private(set) var translations: Localaze
    @Published private(set) var locale = "az"
    @Published private(set) var lastStatus: LocalazeFetchStatus?
    @Published private(set) var busy = false

    /// Every diagnostic the SDK reports.
    ///
    /// Nothing in the SDK throws, which means a wrong API key and a quiet
    /// network look identical from the outside. Showing these is the whole
    /// reason the callback exists.
    @Published private(set) var diagnostics: [String] = []

    @Published var scenario: Scenario = .base
    @Published var count = 1

    @Published var policy: LocalazeUpdatePolicy = .minorAndPatch {
        didSet { rebuild() }
    }

    @Published var applyImmediately = true {
        didSet { rebuild() }
    }

    private let transport: LocalazeTransport

    init(transport: LocalazeTransport? = nil) {
        self.transport = transport ?? LocalazeUrlSessionTransport()
        // Built before self is fully available, so the config is assembled
        // inline here and by `rebuild()` afterwards.
        self.translations = Localaze.forLocale(
            "az",
            config: LocalazeConfig(
                apiKey: apiKey,
                baseUrl: baseUrl,
                transport: transport ?? LocalazeUrlSessionTransport()))
        rebuild()
    }

    var version: String { translations.runtime.version }

    /// Config is immutable, so changing an option means a fresh runtime.
    private func rebuild() {
        translations = Localaze.forLocale(
            locale,
            config: LocalazeConfig(
                apiKey: apiKey,
                baseUrl: baseUrl,
                policy: policy,
                applyImmediately: applyImmediately,
                onDiagnostic: { [weak self] message, error in
                    Task { @MainActor in
                        self?.diagnostics.insert(
                            error == nil ? message : "\(message) — \(error!)", at: 0)
                    }
                },
                transport: transport,
                // No storage: this demo keeps updates for the session only,
                // which is the documented default when none is configured.
                storage: nil))
    }

    /// Switches locale without a restart, as `LZ-56` requires.
    func setLocale(_ next: String) {
        guard next != locale, Localaze.supportedLocales.contains(next) else { return }
        locale = next
        rebuild()
    }

    func update() async {
        busy = true
        lastStatus = await translations.runtime.update()
        // The runtime mutated in place; tell SwiftUI the rendered text changed.
        objectWillChange.send()
        busy = false
    }

    func applyPending() -> Bool {
        let applied = translations.runtime.applyPending()
        if applied { objectWillChange.send() }
        return applied
    }

    func clearDiagnostics() { diagnostics.removeAll() }

    /// Switches what the stub server offers, through its control endpoint.
    ///
    /// The real read API has no such thing — this is the demo harness, not the
    /// SDK, which is why it goes straight to the transport.
    func serve(_ scenario: Scenario) async {
        _ = await transport.get("\(baseUrl)/control/serve/\(scenario.rawValue)", headers: [:])
        self.scenario = scenario
    }
}
