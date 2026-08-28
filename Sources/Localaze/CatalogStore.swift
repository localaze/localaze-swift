/// Where content comes from, and in what order.
///
/// See `../../contract/runtime-contract.md` section 7.

import Foundation

/// Holds the four levels of content for one language and answers lookups from
/// the highest that has the key.
///
/// **Per key, not per catalog.** A partial or stale catalog degrades key by key
/// rather than wholly, so one missing key does not cost an app every string it
/// has. That is the only reason the levels are kept separate rather than merged
/// once at load.
final class CatalogStore {
    let language: String
    let signature: LocalazeSignature

    private let diagnostics: Diagnostics

    /// Level 4, the floor. Shipped inside the generated source.
    ///
    /// It is duplication and it earns its place: without it the first launch of
    /// a fresh install with no network has no text at all, and a mistyped asset
    /// path fails as a blank screen rather than a stale one.
    private let compiledIn: LocalazeCatalog

    private var bundled: LocalazeCatalog?
    private var cached: LocalazeCatalog?
    private var applied: LocalazeCatalog?

    init(
        language: String,
        compiledIn: LocalazeCatalog,
        signature: LocalazeSignature,
        diagnostics: Diagnostics
    ) {
        self.language = language
        self.compiledIn = compiledIn
        self.signature = signature
        self.diagnostics = diagnostics
    }

    /// The version currently rendering, so an app can report it.
    var version: String {
        (applied ?? cached ?? bundled ?? compiledIn).version
    }

    /// Reads the bundled asset and any cached catalog.
    ///
    /// Both are optional and neither failing is an error. The cached catalog is
    /// checked against the signature again here, because an app upgrade can
    /// leave yesterday's catalog next to code that now promises something else.
    func load(_ storage: LocalazeStorage) async {
        if let asset = await storage.readAsset(language) {
            if let parsed = LocalazeCatalog.parse(asset) {
                bundled = parsed
            } else {
                diagnostics.report("The bundled \(language) catalog could not be read")
            }
        }

        guard let raw = await storage.readCache(language) else { return }

        guard let parsed = LocalazeCatalog.parse(raw) else {
            diagnostics.report("Ignoring an unreadable cached \(language) catalog")
            return
        }

        let problems = signature.incompatibilities(parsed)
        guard problems.isEmpty else {
            diagnostics.report(
                "Dropping the cached \(language) catalog \(parsed.version): "
                    + problems.joined(separator: ", "))
            return
        }
        cached = parsed
    }

    /// Takes a catalog that has already passed policy and signature.
    func apply(_ catalog: LocalazeCatalog) { applied = catalog }

    /// The message for `key`, from the highest level that has it.
    func lookup(_ key: String) -> LocalazeMessage? {
        applied?.messages[key]
            ?? cached?.messages[key]
            ?? bundled?.messages[key]
            ?? compiledIn.messages[key]
    }
}
