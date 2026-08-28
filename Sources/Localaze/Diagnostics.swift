/// Reporting swallowed failures.
///
/// Nothing in this package throws, which is a deliberate choice and a dangerous
/// one: a wrong API key and a quiet network look identical from the outside, so
/// an integration that never worked can go unnoticed for a month. The callback
/// is not optional polish, it is how anyone finds out.
///
/// See `../../contract/runtime-contract.md` section 8.

import Foundation

/// Called for every failure the package declines to throw.
public typealias LocalazeDiagnostic = @Sendable (String, String?) -> Void

/// Wraps the app's callback.
///
/// Unlike Dart, a Swift callback cannot throw unless it is declared `throws`,
/// so there is nothing to catch here. The type carries the intent and keeps the
/// three implementations shaped the same.
struct Diagnostics: Sendable {
    let callback: LocalazeDiagnostic?

    init(_ callback: LocalazeDiagnostic?) {
        self.callback = callback
    }

    func report(_ message: String, _ error: String? = nil) {
        callback?(message, error)
    }
}

/// What happened on the last fetch, so an app can report it rather than guess.
public enum LocalazeFetchOutcome: String, Sendable, Equatable {
    /// No fetch has been attempted.
    case none

    /// A newer catalog was downloaded, checked and applied.
    case applied

    /// The server had nothing newer, or returned 304.
    case upToDate

    /// The update policy declined it.
    case refusedByPolicy

    /// The signature check declined it. On a minor or patch release this is a
    /// platform bug — `LZ-62` guarantees those are signature-compatible.
    case refusedBySignature

    /// The network, the server, or the payload failed.
    case failed
}

/// The outcome of the last fetch, and why.
public struct LocalazeFetchStatus: Sendable, Equatable {
    public let outcome: LocalazeFetchOutcome

    /// Human-readable, and the same text passed to the diagnostic callback.
    public let detail: String?

    /// The version involved, when there was one.
    public let version: String?

    public init(_ outcome: LocalazeFetchOutcome, detail: String? = nil, version: String? = nil) {
        self.outcome = outcome
        self.detail = detail
        self.version = version
    }

    public static let idle = LocalazeFetchStatus(.none)

    public var isApplied: Bool { outcome == .applied }
}
