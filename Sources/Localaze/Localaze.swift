/// What generated code sits on.
///
/// A generated `Localaze` class holds one of these and calls `render` from each
/// typed accessor. The type safety lives in the generated signatures; this
/// supplies the content and the update machinery behind them.
///
/// Nothing in this package throws. Every failure leaves the app on the content
/// it already had and is reported through `LocalazeConfig.onDiagnostic`.

import Foundation

/// Resolves a numeric value to a CLDR plural category for one locale.
///
/// Generated at build time from the project's locales, so the device resolves
/// categories without shipping plural data and without an MF2 parser. Returning
/// nil means "no category", and the catch-all is used.
public typealias LocalazePluralResolver = @Sendable (Double) -> String?

public final class LocalazeRuntime: @unchecked Sendable {
    public let locale: String
    public let config: LocalazeConfig
    public let signature: LocalazeSignature

    private let diagnostics: Diagnostics
    private let pluralResolver: LocalazePluralResolver?
    private let storage: LocalazeStorage
    private let store: CatalogStore
    private let updater: Updater

    private var status: LocalazeFetchStatus = .idle

    /// Held back until next launch when `applyImmediately` is off.
    private var pending: LocalazeCatalog?

    public init(
        locale: String,
        config: LocalazeConfig,
        signature: LocalazeSignature,
        compiledIn: String,
        pluralResolver: LocalazePluralResolver? = nil
    ) {
        self.locale = locale
        self.config = config
        self.signature = signature
        self.pluralResolver = pluralResolver

        let diagnostics = Diagnostics(config.onDiagnostic)
        self.diagnostics = diagnostics
        self.storage = config.storage ?? LocalazeNoStorage()

        let parsed = LocalazeCatalog.parse(compiledIn)
        if parsed == nil {
            // A compiled-in copy that will not parse is a generator bug, not a
            // runtime condition. Failing soft here keeps the no-throw rule
            // intact and leaves the app rendering key names, which is loud
            // enough to notice.
            diagnostics.report("The compiled-in \(locale) catalog could not be read")
        }

        self.store = CatalogStore(
            language: locale,
            compiledIn: parsed ?? .empty,
            signature: signature,
            diagnostics: diagnostics)

        self.updater = Updater(
            config: config,
            signature: signature,
            diagnostics: diagnostics,
            transport: config.transport,
            storage: storage)
    }

    /// What happened on the last fetch. Readable so an app can report it rather
    /// than guess, which matters when nothing throws.
    public var lastFetch: LocalazeFetchStatus { status }

    /// The version currently rendering.
    public var version: String { store.version }

    /// Reads the bundled asset and any cached catalog.
    ///
    /// Optional — everything renders from the compiled-in copy without it — but
    /// an app that skips it gets no cached updates.
    public func load() async {
        await store.load(storage)
    }

    /// Fetches, checks and applies a newer catalog if the policy allows one.
    ///
    /// Never throws, and never blocks a screen: the app renders from what it
    /// has throughout.
    @discardableResult
    public func update(pinnedVersion: String? = nil) async -> LocalazeFetchStatus {
        let (catalog, result) = await updater.fetchIfAccepted(
            locale, held: store.version, pinnedVersion: pinnedVersion)
        status = result

        guard let catalog else { return result }

        if config.applyImmediately {
            store.apply(catalog)
        } else {
            // Text changing under a user mid-session is worse than text being
            // one launch out of date. It is cached either way.
            pending = catalog
        }
        return result
    }

    /// Applies a catalog held back by `applyImmediately`.
    ///
    /// An app with a natural seam — a navigation event, a background return —
    /// can call this rather than waiting for a relaunch.
    @discardableResult
    public func applyPending() -> Bool {
        guard let catalog = pending else { return false }
        store.apply(catalog)
        pending = nil
        return true
    }

    /// Renders `key`. Called by generated accessors, which supply typed
    /// arguments; the loose dictionary here is an internal boundary.
    ///
    /// Returns the key itself when it is not found anywhere. That is a
    /// generator bug rather than a runtime condition — generation fails on a
    /// missing translation — so it is reported rather than rendered blank.
    public func render(
        _ key: String,
        args: [String: Any] = [:],
        selector: Double? = nil
    ) -> String {
        guard let message = store.lookup(key) else {
            diagnostics.report("No message for \"\(key)\" in \(locale)")
            return key
        }

        var category: String?
        if message.selects, let selector {
            category = pluralResolver?(selector)
        }

        guard let parts = message.parts(for: category) else {
            diagnostics.report("\"\(key)\" has no variants in \(locale)")
            return key
        }

        return localazeRender(parts, args, dateFormatter: config.dateFormatter)
    }
}
