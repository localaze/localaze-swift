/// Catalogs on disk. The only filesystem code in the package.

import Foundation

/// Reads bundled catalogs from a bundle or directory, and caches applied ones.
///
/// Unlike the Dart package, persistence is on by default here: Foundation can
/// find a writable directory without an extra dependency. Behaviour given the
/// same configuration is identical across platforms; only the default differs.
public struct LocalazeFileStorage: LocalazeStorage {
    private let assetDirectory: URL?
    private let cacheDirectory: URL?

    /// - Parameters:
    ///   - bundle: where the generated catalogs were copied as resources.
    ///   - assetSubdirectory: the folder inside that bundle.
    ///   - cacheDirectory: nil uses Application Support, which is what an app
    ///     almost always wants. Pass a directory to override, or use
    ///     `LocalazeNoStorage` for session-only updates.
    public init(
        bundle: Bundle = .main,
        assetSubdirectory: String = "localaze",
        cacheDirectory: URL? = nil
    ) {
        self.assetDirectory = bundle.resourceURL?.appendingPathComponent(assetSubdirectory)
        self.cacheDirectory = cacheDirectory ?? Self.defaultCacheDirectory()
    }

    /// Explicit directories, for tests and for apps that manage their own paths.
    public init(assetDirectory: URL?, cacheDirectory: URL?) {
        self.assetDirectory = assetDirectory
        self.cacheDirectory = cacheDirectory
    }

    private static func defaultCacheDirectory() -> URL? {
        guard let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }

        // Namespaced by bundle identifier so two apps sharing a container
        // cannot read each other's catalogs.
        let identifier = Bundle.main.bundleIdentifier ?? "localaze"
        return support.appendingPathComponent(identifier).appendingPathComponent("localaze")
    }

    public func readAsset(_ language: String) async -> String? {
        guard let directory = assetDirectory else { return nil }
        return read(directory.appendingPathComponent("\(language).json"))
    }

    public func readCache(_ language: String) async -> String? {
        guard let directory = cacheDirectory else { return nil }
        return read(directory.appendingPathComponent("\(language).json"))
    }

    public func writeCache(_ language: String, _ body: String) async -> Bool {
        guard let directory = cacheDirectory else { return false }
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            try body.write(
                to: directory.appendingPathComponent("\(language).json"),
                atomically: true,
                encoding: .utf8)
            return true
        } catch {
            // Reported by the updater, which knows whether it mattered.
            return false
        }
    }

    /// Nil for anything unreadable, including a corrupt or truncated file.
    ///
    /// A missing asset is expected rather than exceptional — the compiled-in
    /// copy sits behind it — so there is nothing to distinguish here.
    private func read(_ url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }
}
