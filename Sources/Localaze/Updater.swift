/// Fetching, checking and applying catalogs.
///
/// Nothing here throws. Every failure path leaves the app on the catalog it
/// already had, because a translation outage must never become a crash.
///
/// See `../../contract/runtime-contract.md` sections 5, 6 and 8.

import Foundation

final class Updater {
    let config: LocalazeConfig
    let signature: LocalazeSignature

    private let diagnostics: Diagnostics
    private let transport: LocalazeTransport?
    private let storage: LocalazeStorage

    /// Held per language, so an unchanged catalog costs a round trip and
    /// nothing else. The server's ETag is version-scoped, so a pinned version's
    /// tag never changes and a rollback returns the earlier tag.
    private var etags: [String: String] = [:]

    init(
        config: LocalazeConfig,
        signature: LocalazeSignature,
        diagnostics: Diagnostics,
        transport: LocalazeTransport?,
        storage: LocalazeStorage
    ) {
        self.config = config
        self.signature = signature
        self.diagnostics = diagnostics
        self.transport = transport
        self.storage = storage
    }

    /// What the key currently serves, or nil if it cannot be read.
    ///
    /// Cheap enough for every launch: it does not download the translations.
    func currentVersion() async -> String? {
        let path = "/api/v1/read/version"
        guard let response = await get(path) else { return nil }

        guard response.isOk, let body = response.body else {
            // The status has to reach the diagnostic here, not only on the
            // translations path. A 401 is a wrong key, and without this it is
            // indistinguishable from a quiet network to whoever reads the log —
            // which is the exact failure the no-throw rule trades away.
            diagnostics.report("\(path) returned \(response.status)")
            return nil
        }

        guard let version = LocalazeCatalog.stringField(body, "version") else {
            diagnostics.report("\(path) carried no version")
            return nil
        }
        return version
    }

    /// Downloads `language` if the server has something this build accepts.
    ///
    /// The order is policy, version, download, signature, persist. Policy comes
    /// first because it is the cheapest way to answer the question, and the
    /// signature is checked before anything is written, because a refused
    /// catalog must leave no trace.
    func fetchIfAccepted(
        _ language: String,
        held: String,
        pinnedVersion: String? = nil
    ) async -> (LocalazeCatalog?, LocalazeFetchStatus) {
        guard config.policy.fetches else {
            return (nil, LocalazeFetchStatus(
                .refusedByPolicy, detail: "policy none makes no request"))
        }

        // Spelled out rather than `pinnedVersion ?? (await …)`: `??` takes an
        // autoclosure, which cannot be async. A pin also answers the version
        // question outright, so the endpoint is not called at all.
        let offered: String?
        if let pinnedVersion {
            offered = pinnedVersion
        } else {
            offered = await currentVersion()
        }

        guard let available = offered else {
            return (nil, failed("The published version could not be read"))
        }

        // Nothing new is not a refusal. Reporting it as one reads, in a log and
        // in a UI, as though the policy blocked something — when in fact the
        // server and the app already agree.
        if available == held {
            return (nil, LocalazeFetchStatus(
                .upToDate, detail: "already on \(held)", version: held))
        }

        guard LocalazeVersion.accepts(
            current: held, candidate: available, policy: config.policy)
        else {
            let detail = "Version \(available) refused by policy "
                + "\(config.policy.name), staying on \(held)"
            diagnostics.report(detail)
            return (nil, LocalazeFetchStatus(
                .refusedByPolicy, detail: detail, version: available))
        }

        var path = "/api/v1/read/translations/\(language)?format=resolved"
        if let pinnedVersion { path += "&version=\(pinnedVersion)" }

        guard let response = await get(path, etag: etags[language]) else {
            return (nil, failed("The \(language) catalog could not be fetched"))
        }

        if response.isNotModified {
            return (nil, LocalazeFetchStatus(
                .upToDate, detail: "not modified", version: held))
        }

        guard response.isOk, let body = response.body else {
            // The status goes in the message on purpose: a 401 is a wrong key
            // and must be distinguishable from a quiet network by whoever
            // reads the log.
            return (nil, failed("\(path) returned \(response.status)"))
        }

        guard let catalog = LocalazeCatalog.parse(body, fallbackVersion: available),
              !catalog.isEmpty
        else {
            return (nil, failed("The \(language) catalog had no readable messages"))
        }

        // Belt and braces. LZ-62 guarantees a minor or patch release is
        // signature-compatible, so a failure here is a platform bug rather than
        // an expected refusal — which is why it is its own outcome.
        let problems = signature.incompatibilities(catalog)
        guard problems.isEmpty else {
            let detail = "Catalog \(catalog.version) is not compatible: "
                + problems.joined(separator: ", ")
            diagnostics.report(detail)
            return (nil, LocalazeFetchStatus(
                .refusedBySignature, detail: detail, version: catalog.version))
        }

        if let etag = response.etag { etags[language] = etag }

        let persisted = await persist(language, body)

        return (catalog, LocalazeFetchStatus(
            .applied,
            detail: persisted ? nil : "applied for this session only, not cached",
            version: catalog.version))
    }

    private func failed(_ detail: String) -> LocalazeFetchStatus {
        diagnostics.report(detail)
        return LocalazeFetchStatus(.failed, detail: detail)
    }

    private func persist(_ language: String, _ body: String) async -> Bool {
        let written = await storage.writeCache(language, body)
        if !written {
            diagnostics.report(
                "Could not cache the \(language) catalog; "
                    + "it applies for this session only")
        }
        return written
    }

    private func get(_ path: String, etag: String? = nil) async -> LocalazeResponse? {
        guard let transport else {
            diagnostics.report(
                "No transport configured; use LocalazeUrlSessionTransport or supply one")
            return nil
        }

        var headers = [
            "X-Localaze-Key": config.apiKey,
            "Accept": "application/json",
        ]
        if let etag { headers["If-None-Match"] = etag }

        let response = await transport.get(config.baseUrl + path, headers: headers)

        if let error = response.error {
            diagnostics.report("\(path) failed", error)
            return nil
        }
        if response.isOk, response.body == nil {
            diagnostics.report("\(path) returned 200 with no body")
            return nil
        }
        return response
    }
}
