/// The resolved message shape, and parsing it.
///
/// Catalogs arrive already parsed by the server, as variants and typed
/// parameter references. Nothing here parses MessageFormat 2, which is what
/// makes this package possible without a Swift MF2 library — there is no
/// maintained one, and decision D7 turns on that.
///
/// See `contract/runtime-contract.md` section 2.

import Foundation

/// The three types a parameter can have. Deliberately small; the generators map
/// these onto native types and the set is not widened per platform.
public enum LocalazeParamType: String, Sendable, Hashable {
    case string = "STRING"
    case number = "NUMBER"
    case datetime = "DATETIME"

    /// An unknown type reads as a string rather than failing, so a newer server
    /// cannot break an older SDK.
    public static func parse(_ wire: Any?) -> LocalazeParamType {
        guard let raw = wire as? String, let type = LocalazeParamType(rawValue: raw) else {
            return .string
        }
        return type
    }
}

/// A parameter, with the type its MF2 function annotation implied.
public struct LocalazeParam: Sendable, Hashable {
    public let name: String
    public let type: LocalazeParamType

    public init(_ name: String, _ type: LocalazeParamType) {
        self.name = name
        self.type = type
    }
}

/// One piece of a message: literal text, or a reference to a parameter.
///
/// A part is one or the other. The server omits null fields, so a part with
/// neither is malformed and is dropped at parse time.
public enum LocalazePart: Sendable, Hashable {
    case text(String)
    case variable(name: String, type: LocalazeParamType)
}

/// A message resolved into parts and variants.
public struct LocalazeMessage: Sendable {
    /// Parameters the message selects on. Empty for a simple message.
    public let selectors: [String]

    /// Every parameter, with its type.
    public let params: [LocalazeParam]

    /// Variant category to its ordered parts. A simple message has only `*`.
    public let variants: [String: [LocalazePart]]

    public var selects: Bool { !selectors.isEmpty }

    /// The parts for `category`, falling back to the catch-all.
    ///
    /// `LZ-07` guarantees `*` is present on every message, which is what makes
    /// this fallback safe rather than optimistic.
    public func parts(for category: String?) -> [LocalazePart]? {
        if let category, let exact = variants[category] { return exact }
        return variants["*"]
    }

    static func parse(_ raw: Any?) -> LocalazeMessage? {
        guard let object = raw as? [String: Any],
              let rawVariants = object["variants"] as? [String: Any]
        else { return nil }

        var variants: [String: [LocalazePart]] = [:]
        for (category, rawParts) in rawVariants {
            guard let list = rawParts as? [Any] else { continue }
            var parts: [LocalazePart] = []
            for rawPart in list {
                guard let part = rawPart as? [String: Any] else { continue }
                if let text = part["text"] as? String {
                    parts.append(.text(text))
                } else if let name = part["var"] as? String {
                    parts.append(.variable(name: name, type: .parse(part["type"])))
                }
                // A part with neither is dropped here rather than carried and
                // skipped later; what a caller sees is the same either way.
            }
            variants[category] = parts
        }
        guard !variants.isEmpty else { return nil }

        return LocalazeMessage(
            selectors: (object["selectors"] as? [Any])?.compactMap { $0 as? String } ?? [],
            params: parseParams(object["params"]),
            variants: variants
        )
    }

    private static func parseParams(_ raw: Any?) -> [LocalazeParam] {
        guard let list = raw as? [Any] else { return [] }
        return list.compactMap { entry in
            guard let object = entry as? [String: Any],
                  let name = object["name"] as? String
            else { return nil }
            return LocalazeParam(name, .parse(object["type"]))
        }
    }
}

/// One language's messages, and the release they came from.
///
/// A catalog file and a read-API response body have the same shape, so a
/// bundled asset and a fetched payload go through this one parser. Inventing a
/// second envelope for bundled files would mean two code paths where one is
/// tested and the other is not.
public struct LocalazeCatalog: Sendable {
    public let version: String
    public let messages: [String: LocalazeMessage]

    public init(version: String, messages: [String: LocalazeMessage]) {
        self.version = version
        self.messages = messages
    }

    public static let empty = LocalazeCatalog(version: "0.0.0", messages: [:])

    public var isEmpty: Bool { messages.isEmpty }

    /// Parses a catalog, returning nil rather than throwing.
    ///
    /// Malformed JSON, a missing `messages` object, and a body that is not an
    /// object at all all return nil. The caller keeps whatever it already had.
    public static func parse(_ body: String, fallbackVersion: String? = nil) -> LocalazeCatalog? {
        guard let data = body.data(using: .utf8),
              let decoded = try? JSONSerialization.jsonObject(with: data),
              let object = decoded as? [String: Any],
              let rawMessages = object["messages"] as? [String: Any]
        else { return nil }

        var messages: [String: LocalazeMessage] = [:]
        for (key, raw) in rawMessages {
            if let message = LocalazeMessage.parse(raw) { messages[key] = message }
        }

        return LocalazeCatalog(
            version: object["version"] as? String ?? fallbackVersion ?? "0.0.0",
            messages: messages
        )
    }

    /// One top-level string field, or nil for anything unreadable.
    ///
    /// The version endpoint returns no `messages`, so `parse` correctly rejects
    /// it and this reads the one field that matters instead.
    static func stringField(_ body: String, _ field: String) -> String? {
        guard let data = body.data(using: .utf8),
              let decoded = try? JSONSerialization.jsonObject(with: data),
              let object = decoded as? [String: Any]
        else { return nil }
        return object[field] as? String
    }
}
