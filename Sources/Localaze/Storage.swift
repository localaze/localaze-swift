/// The persistence seam.
///
/// Two separate concerns behind one protocol: reading the bundled asset that
/// shipped with the app, and reading or writing the cache that survives a
/// launch. They fail differently and are configured differently, so they are
/// separate methods rather than one keyed store.
///
/// See `contract/runtime-contract.md` sections 7 and 10.

import Foundation

/// Implementations must not throw. Anything unreadable is nil.
public protocol LocalazeStorage: Sendable {
    /// The catalog that shipped with the app, for `language`.
    ///
    /// Nil when there is no asset, or it cannot be read. A missing asset is not
    /// an error: the compiled-in copy is behind it, which is what lets the
    /// asset path be configurable without a typo becoming a blank screen.
    func readAsset(_ language: String) async -> String?

    /// A catalog written by an earlier run.
    func readCache(_ language: String) async -> String?

    /// Persists `body`. Returns false when it could not be written.
    ///
    /// False is not a failure worth stopping for — the update still applies for
    /// this session. It is reported so an app can tell "working, not persisted"
    /// from "working".
    func writeCache(_ language: String, _ body: String) async -> Bool
}

/// Storage that has nothing and keeps nothing.
public struct LocalazeNoStorage: LocalazeStorage {
    public init() {}

    public func readAsset(_ language: String) async -> String? { nil }
    public func readCache(_ language: String) async -> String? { nil }
    public func writeCache(_ language: String, _ body: String) async -> Bool { false }
}
