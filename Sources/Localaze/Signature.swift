/// What the generated code promised its call sites, and checking a catalog
/// against it.
///
/// See `contract/runtime-contract.md` section 4.

import Foundation

/// Keys to the parameters each accessor takes.
///
/// Emitted into the generated source and never fetched, because it describes
/// the code that was compiled rather than the content that arrives.
public struct LocalazeSignature: Sendable {
    public let keys: [String: [LocalazeParam]]

    public init(_ keys: [String: [LocalazeParam]]) {
        self.keys = keys
    }

    /// Builds a signature from the compact form generated code emits:
    /// `["inbox.unread": [("count", "NUMBER")]]`.
    public init(of raw: [String: [(String, String)]]) {
        self.keys = raw.mapValues { params in
            params.map { LocalazeParam($0.0, .parse($0.1)) }
        }
    }

    /// Why `catalog` cannot be applied, empty when it can.
    ///
    /// Three rules, and each one is a decision rather than an oversight:
    ///
    /// - A **missing key** is incompatible. Generated code has an accessor for
    ///   it and nothing to render.
    /// - A parameter whose **name or type** differs is incompatible. Checking
    ///   names alone is the defect this replaces: `{$count}` gaining `:number`
    ///   leaves the key and the name intact while changing what every call site
    ///   passes, and it is the likelier edit in practice than a removal.
    /// - An **added key**, or an **extra parameter** on a key we do know, is
    ///   fine. The app has no accessor for either, and a newer platform release
    ///   is not a client failure. The signature is a floor, not an equality.
    public func incompatibilities(_ catalog: LocalazeCatalog) -> [String] {
        var problems: [String] = []

        // Sorted so the message is stable between runs, which matters when it
        // is the only thing in a log.
        for key in keys.keys.sorted() {
            let expected = keys[key] ?? []

            guard let message = catalog.messages[key] else {
                problems.append("\(key) is missing")
                continue
            }

            var declared: [String: LocalazeParamType] = [:]
            for param in message.params { declared[param.name] = param.type }

            for param in expected {
                guard let actual = declared[param.name] else {
                    problems.append("\(key) no longer takes \"\(param.name)\"")
                    continue
                }
                if actual != param.type {
                    problems.append(
                        "\(key).\(param.name) is now \(actual.name), "
                            + "generated as \(param.type.name)")
                }
            }
        }
        return problems
    }

    public func accepts(_ catalog: LocalazeCatalog) -> Bool {
        incompatibilities(catalog).isEmpty
    }
}

extension LocalazeParamType {
    /// Lower-case, matching the Dart and Kotlin diagnostics exactly. The wire
    /// form is upper-case; a diagnostic is prose.
    var name: String { rawValue.lowercased() }
}
