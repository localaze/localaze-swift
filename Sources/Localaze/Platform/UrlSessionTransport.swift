/// The default transport. The only network code in the package.
///
/// This file and `FileStorage.swift` are the only ones permitted to touch
/// `URLSession` and `FileManager`.

import Foundation

public struct LocalazeUrlSessionTransport: LocalazeTransport {
    private let session: URLSession
    private let timeout: TimeInterval

    public init(timeout: TimeInterval = 10) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData

        self.session = URLSession(configuration: configuration)
        self.timeout = timeout
    }

    /// Returns a failed response rather than throwing, whatever goes wrong.
    ///
    /// A caller that has to wrap every call in a `do`/`catch` has an interface
    /// that lied to it, and this one promises not to throw.
    public func get(_ url: String, headers: [String: String]) async -> LocalazeResponse {
        guard let target = URL(string: url) else {
            return .failed("not a URL: \(url)")
        }

        var request = URLRequest(url: target, timeoutInterval: timeout)
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failed("not an HTTP response")
            }

            // URLSession normalises header names, so the ETag comes back
            // however the server spelled it.
            let etag = http.value(forHTTPHeaderField: "ETag")

            // 304 carries no body, and decoding an empty one as a missing body
            // would turn the cheap path into a reported failure.
            if http.statusCode == 304 {
                return LocalazeResponse(status: 304, etag: etag)
            }

            // utf8 explicitly: catalogs carry Cyrillic and Azerbaijani, and a
            // lossy conversion would corrupt both.
            return LocalazeResponse(
                status: http.statusCode,
                body: String(data: data, encoding: .utf8),
                etag: etag)
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
