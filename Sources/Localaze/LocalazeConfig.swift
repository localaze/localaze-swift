/// Everything an app can change, all of it optional but the key.
///
/// See `../../contract/runtime-contract.md` section 9.

import Foundation

public struct LocalazeConfig: Sendable {
    /// Issued in project settings. Carries the project and the environment, so
    /// neither is a parameter here and a staging build cannot read production.
    public let apiKey: String

    public let baseUrl: String

    public let policy: LocalazeUpdatePolicy

    public let timeout: TimeInterval

    /// Whether an applied catalog takes effect now or on next launch.
    ///
    /// Off by default: text changing under a user mid-session is worse than
    /// text being one launch out of date.
    public let applyImmediately: Bool

    public let dateFormatter: LocalazeDateFormatter

    /// The only way to hear about failures.
    public let onDiagnostic: LocalazeDiagnostic?

    /// Defaults to no network. `LocalazeUrlSessionTransport` is the one to
    /// reach for unless a test is substituting a fake.
    public let transport: LocalazeTransport?

    /// Defaults to `LocalazeNoStorage`, so updates last for the session only.
    /// `LocalazeFileStorage` persists them.
    public let storage: LocalazeStorage?

    public init(
        apiKey: String,
        baseUrl: String = "https://localize.sharpy.dev",
        policy: LocalazeUpdatePolicy = .minorAndPatch,
        timeout: TimeInterval = 10,
        applyImmediately: Bool = false,
        dateFormatter: @escaping LocalazeDateFormatter = localazeIsoUtc,
        onDiagnostic: LocalazeDiagnostic? = nil,
        transport: LocalazeTransport? = nil,
        storage: LocalazeStorage? = nil
    ) {
        self.apiKey = apiKey
        self.baseUrl = baseUrl
        self.policy = policy
        self.timeout = timeout
        self.applyImmediately = applyImmediately
        self.dateFormatter = dateFormatter
        self.onDiagnostic = onDiagnostic
        self.transport = transport
        self.storage = storage
    }
}
