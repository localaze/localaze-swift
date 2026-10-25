/// The network seam.
///
/// A protocol rather than a direct `URLSession` call, because every failure row
/// in the contract is reachable with a fake and unreachable without one. A
/// runtime testable only against a live server is a runtime that is not tested.
///
/// See `contract/runtime-contract.md` section 10.

import Foundation

/// What came back. Never an error thrown — an implementation that cannot reach
/// the network returns `.failed` instead.
public struct LocalazeResponse: Sendable {
    public let status: Int
    public let body: String?
    public let etag: String?
    public let error: String?

    public init(status: Int, body: String? = nil, etag: String? = nil, error: String? = nil) {
        self.status = status
        self.body = body
        self.etag = etag
        self.error = error
    }

    /// A request that never completed. Status 0 is not a real HTTP status,
    /// which is the point: it cannot collide with one the server might send.
    public static func failed(_ error: String) -> LocalazeResponse {
        LocalazeResponse(status: 0, error: error)
    }

    public var isOk: Bool { status == 200 }

    /// The server had nothing newer. A success, not a failure — this is the
    /// cheap path the version-scoped ETag exists to serve.
    public var isNotModified: Bool { status == 304 }
}

/// One GET, with headers. Implementations must not throw.
public protocol LocalazeTransport: Sendable {
    func get(_ url: String, headers: [String: String]) async -> LocalazeResponse
}
