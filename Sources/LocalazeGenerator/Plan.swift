/// Everything the generator decides before it writes a line of Swift.
///
/// The checks of `contract/generator-contract.md` §4 all live here, so the
/// emitter receives a plan that is already known to compile. Nothing in this
/// file touches the network or the filesystem: the `localaze-generate`
/// executable reads the inputs and writes the outputs, and the tests drive
/// this directly.

import Foundation

/// One parameter of a key, as the manifest declares it.
public struct PlannedParam: Equatable {
    /// The name the catalog uses. Passed to the runtime unchanged.
    public let name: String
    /// The lower-camel identifier the accessor declares, before escaping.
    public let identifier: String
    /// `STRING`, `NUMBER` or `DATETIME`.
    public let type: String
}

/// One key, ready to become an accessor.
public struct PlannedKey: Equatable {
    public let key: String
    /// The lower-camel accessor name, before escaping.
    public let accessor: String
    public let params: [PlannedParam]
    /// The parameter the message selects on, or nil for a simple message.
    public let selector: String?
    /// The source-language text, for the accessor's documentation comment.
    public let preview: String
}

/// One language's plural resolver.
public struct PlannedPlural: Equatable {
    public let language: String
    /// Category to condition, sorted by category name.
    public let categories: [(String, String)]

    public static func == (lhs: PlannedPlural, rhs: PlannedPlural) -> Bool {
        lhs.language == rhs.language
            && lhs.categories.map { $0.0 + "\u{0}" + $0.1 }
            == rhs.categories.map { $0.0 + "\u{0}" + $0.1 }
    }

    /// Whether any condition mentions `operand`.
    public func uses(_ operand: String) -> Bool {
        categories.contains { tokens(in: $0.1).contains(operand) }
    }
}

/// A plan the emitter can turn into source without any further checks.
public struct GenerationPlan {
    public let environment: String
    public let version: String
    public let contentHash: String
    public let sourceLanguage: String
    /// The manifest's languages, in its order.
    public let languages: [String]
    public let keys: [PlannedKey]
    public let plurals: [PlannedPlural]
    /// Language to the catalog exactly as it was read.
    public let catalogs: [String: String]
}

/// What planning produced: a plan, or every reason there is none.
public struct PlanResult {
    public let plan: GenerationPlan?
    /// Each one fails generation.
    public let problems: [String]
    /// Reported, not fatal. Only `--allow-gaps` produces these.
    public let warnings: [String]
}

/// Members of the generated type, plus members a base type already has on at
/// least one platform. Reserved on every platform alike, so a key set that
/// generates for Swift also generates for Dart and Kotlin.
public let reservedAccessors: Set<String> = [
    "runtime", "forLocale", "supportedLocales", "sourceLocale", "generatedFrom",
    "contentHash", "hashCode", "toString", "equals", "runtimeType", "noSuchMethod",
]

private let types: Set<String> = ["STRING", "NUMBER", "DATETIME"]
private let operands: Set<String> = ["n", "i", "v"]
private let previewLength = 80

/// `auth.sign_out` becomes `authSignOut`. The same rule names parameters.
public func lowerCamel(_ raw: String) -> String {
    let segments = raw.split(whereSeparator: { $0 == "." || $0 == "_" || $0 == "-" })
    var out = ""
    for segment in segments {
        let head = String(segment.prefix(1))
        out += out.isEmpty ? head.lowercased() : head.uppercased()
        out += segment.dropFirst()
    }
    return out
}

private func isIdentifier(_ value: String) -> Bool {
    guard let first = value.unicodeScalars.first, first.isASCII,
          CharacterSet.letters.contains(first) else { return false }
    return value.unicodeScalars.allSatisfy {
        $0.isASCII && CharacterSet.alphanumerics.contains($0)
    }
}

/// The alphabetic tokens in a condition: operands, or anything that should
/// not be there.
private func tokens(in condition: String) -> Set<String> {
    var found = Set<String>()
    var current = ""
    for scalar in condition.unicodeScalars {
        if scalar == "_" || (scalar.isASCII && CharacterSet.letters.contains(scalar)) {
            current.unicodeScalars.append(scalar)
        } else if !current.isEmpty {
            found.insert(current)
            current = ""
        }
    }
    if !current.isEmpty { found.insert(current) }
    return found
}

private let ruleCharacters = CharacterSet(charactersIn: "niv0123456789 \t\n()%=!<>&|")

/// Plans generation from a manifest and one catalog per language, each the raw
/// text the server returned or the file a build saved.
public func plan(manifest: String, catalogs: [String: String], allowGaps: Bool = false) -> PlanResult {
    var problems: [String] = []
    var warnings: [String] = []

    guard let parsed = decode(manifest, "The manifest", &problems) else {
        return PlanResult(plan: nil, problems: problems, warnings: warnings)
    }

    let version = string(parsed, "version", &problems)
    let sourceLanguage = string(parsed, "sourceLanguage", &problems)
    let languages = strings(parsed["languages"], "languages", &problems)
    let keys = manifestKeys(parsed["keys"], &problems)
    let rules = pluralRules(parsed["pluralRules"], &problems)
    guard problems.isEmpty else {
        return PlanResult(plan: nil, problems: problems, warnings: warnings)
    }

    var messages: [String: [String: Any]] = [:]
    for language in languages {
        guard let raw = catalogs[language] else {
            problems.append("No catalog for language \"\(language)\".")
            continue
        }
        guard let catalog = decode(raw, "The \"\(language)\" catalog", &problems) else { continue }
        let catalogVersion = catalog["version"] as? String
        if catalogVersion != version {
            problems.append("The \"\(language)\" catalog is version "
                + "\(catalogVersion ?? "null"), but the manifest is \(version).")
        }
        guard let body = catalog["messages"] as? [String: Any] else {
            problems.append("The \"\(language)\" catalog has no \"messages\".")
            continue
        }
        messages[language] = body
    }

    for key in keys {
        for language in languages where messages[language] != nil {
            if messages[language]?[key.key] == nil {
                let gap = "\(key.key) is missing in \(language)."
                if allowGaps { warnings.append(gap) } else { problems.append(gap) }
            }
        }
    }

    let planned = planKeys(keys, sourceLanguage, languages, messages, &problems)
    let plurals = planPlurals(languages, rules, &problems)

    guard problems.isEmpty else {
        return PlanResult(plan: nil, problems: problems, warnings: warnings)
    }

    var carried: [String: String] = [:]
    for language in languages { carried[language] = catalogs[language] }

    return PlanResult(
        plan: GenerationPlan(
            environment: parsed["environment"] as? String ?? "unknown",
            version: version,
            contentHash: parsed["contentHash"] as? String ?? "",
            sourceLanguage: sourceLanguage,
            languages: languages,
            keys: planned,
            plurals: plurals,
            catalogs: carried),
        problems: problems,
        warnings: warnings)
}

private struct ManifestKey {
    let key: String
    let params: [(String, String)]
    let selects: Bool
}

private func planKeys(
    _ keys: [ManifestKey],
    _ sourceLanguage: String,
    _ languages: [String],
    _ messages: [String: [String: Any]],
    _ problems: inout [String]
) -> [PlannedKey] {
    var planned: [PlannedKey] = []
    var owners: [String: String] = [:]

    for key in keys {
        let accessor = lowerCamel(key.key)
        if !isIdentifier(accessor) {
            problems.append("Key \"\(key.key)\" gives no valid accessor name "
                + "(\"\(accessor)\"). Use ASCII letters and digits, starting with a letter.")
        } else if reservedAccessors.contains(accessor) {
            problems.append("Key \"\(key.key)\" would generate \"\(accessor)\", which is reserved.")
        } else if let owner = owners[accessor] {
            problems.append("Keys \"\(owner)\" and \"\(key.key)\" both generate the accessor \"\(accessor)\".")
        } else {
            owners[accessor] = key.key
        }

        var params: [PlannedParam] = []
        var seen: [String: String] = [:]
        for (name, type) in key.params {
            let identifier = lowerCamel(name)
            if !isIdentifier(identifier) {
                problems.append("Parameter \"\(name)\" of \"\(key.key)\" gives no valid identifier (\"\(identifier)\").")
            } else if let other = seen[identifier] {
                problems.append("Parameters \"\(other)\" and \"\(name)\" of \"\(key.key)\" both generate \"\(identifier)\".")
            } else {
                seen[identifier] = name
            }
            params.append(PlannedParam(name: name, identifier: identifier, type: type))
        }

        let reference = referenceMessage(key.key, sourceLanguage, languages, messages)
        let selector = key.selects ? selectorOf(key, reference, &problems) : nil

        planned.append(PlannedKey(
            key: key.key, accessor: accessor, params: params,
            selector: selector, preview: preview(reference)))
    }
    return planned
}

/// The source language's message, or the first language that has the key.
private func referenceMessage(
    _ key: String, _ sourceLanguage: String, _ languages: [String],
    _ messages: [String: [String: Any]]
) -> [String: Any]? {
    for language in [sourceLanguage] + languages {
        if let message = messages[language]?[key] as? [String: Any] { return message }
    }
    return nil
}

private func selectorOf(
    _ key: ManifestKey, _ reference: [String: Any]?, _ problems: inout [String]
) -> String? {
    guard let selectors = reference?["selectors"] as? [Any],
          let name = selectors.first as? String else {
        problems.append("\"\(key.key)\" selects, but no catalog names its selector.")
        return nil
    }
    guard let declared = key.params.first(where: { $0.0 == name }) else {
        problems.append("\"\(key.key)\" selects on $\(name), which the manifest does not declare.")
        return nil
    }
    guard declared.1 == "NUMBER" else {
        problems.append("\"\(key.key)\" selects on $\(name), a \(declared.1). "
            + "Only NUMBER selection runs on device.")
        return nil
    }
    return name
}

/// The `*` variant as text, variables as `{$name}`, on one line.
private func preview(_ message: [String: Any]?) -> String {
    guard let variants = message?["variants"] as? [String: Any],
          let parts = variants["*"] as? [Any] else { return "" }

    var out = ""
    for case let part as [String: Any] in parts {
        if let text = part["text"] as? String {
            out += text
        } else if let name = part["var"] as? String {
            out += "{$\(name)}"
        }
    }

    var line = ""
    var pendingSpace = false
    for scalar in out.unicodeScalars {
        if scalar == "\r" || scalar == "\n" || scalar == "\t" {
            pendingSpace = true
            continue
        }
        if pendingSpace { line += " "; pendingSpace = false }
        line.unicodeScalars.append(scalar)
    }
    if pendingSpace { line += " " }

    // Cut by UTF-16 unit, as Dart and Kotlin do, never inside a surrogate pair.
    let units = Array(line.utf16)
    guard units.count > previewLength else { return line }
    var end = previewLength
    if UTF16.isLeadSurrogate(units[end - 1]) { end -= 1 }
    return String(decoding: units[0..<end], as: UTF16.self) + "…"
}

private func planPlurals(
    _ languages: [String], _ rules: [String: [(String, String)]], _ problems: inout [String]
) -> [PlannedPlural] {
    var plurals: [PlannedPlural] = []
    for language in languages {
        let categories = rules[language] ?? []
        for (category, condition) in categories {
            let isCategory = !category.isEmpty && category.unicodeScalars.allSatisfy {
                $0.isASCII && CharacterSet.lowercaseLetters.contains($0)
            }
            if !isCategory {
                problems.append("The \"\(language)\" plural rules name an unrecognised category \"\(category)\".")
            }
            let unknown = tokens(in: condition).subtracting(operands).sorted()
            if !unknown.isEmpty {
                problems.append("The \"\(language)\" rule for \"\(category)\" uses "
                    + "\(unknown.joined(separator: ", ")). Only n, i and v are supported.")
            } else if !condition.unicodeScalars.allSatisfy({ ruleCharacters.contains($0) }) {
                problems.append("The \"\(language)\" rule for \"\(category)\" is not a recognised condition: \(condition)")
            }
        }
        plurals.append(PlannedPlural(language: language, categories: categories))
    }
    return plurals
}

// MARK: - Parsing

private func decode(_ raw: String, _ what: String, _ problems: inout [String]) -> [String: Any]? {
    guard let data = raw.data(using: .utf8),
          let decoded = try? JSONSerialization.jsonObject(with: data) else {
        problems.append("\(what) is not valid JSON.")
        return nil
    }
    guard let object = decoded as? [String: Any] else {
        problems.append("\(what) is not a JSON object.")
        return nil
    }
    return object
}

private func string(_ json: [String: Any], _ field: String, _ problems: inout [String]) -> String {
    if let value = json[field] as? String, !value.isEmpty { return value }
    problems.append("The manifest has no \"\(field)\".")
    return ""
}

private func strings(_ value: Any?, _ field: String, _ problems: inout [String]) -> [String] {
    if let list = value as? [String], !list.isEmpty { return list }
    problems.append("The manifest has no \"\(field)\".")
    return []
}

private func manifestKeys(_ value: Any?, _ problems: inout [String]) -> [ManifestKey] {
    guard let list = value as? [Any] else {
        problems.append("The manifest has no \"keys\".")
        return []
    }
    var keys: [ManifestKey] = []
    for entry in list {
        guard let object = entry as? [String: Any],
              let key = object["key"] as? String,
              let rawParams = object["params"] as? [Any] else {
            problems.append("The manifest has a key entry it cannot read: \(entry)")
            continue
        }
        var params: [(String, String)] = []
        for param in rawParams {
            if let param = param as? [String: Any],
               let name = param["name"] as? String,
               let type = param["type"] as? String, types.contains(type) {
                params.append((name, type))
            } else {
                problems.append("\"\(key)\" declares a parameter it cannot read: \(param)")
            }
        }
        // JSONSerialization reads a JSON true as an NSNumber; compare as Bool.
        keys.append(ManifestKey(key: key, params: params, selects: (object["selects"] as? Bool) == true))
    }
    return keys
}

private func pluralRules(_ value: Any?, _ problems: inout [String]) -> [String: [(String, String)]] {
    guard let value else { return [:] }
    guard let object = value as? [String: Any] else {
        problems.append("The manifest's \"pluralRules\" is not an object.")
        return [:]
    }
    var rules: [String: [(String, String)]] = [:]
    for (language, categories) in object {
        guard let categories = categories as? [String: Any] else {
            problems.append("The manifest has plural rules it cannot read for \"\(language)\".")
            continue
        }
        // Name order, per generator-contract.md §7: JSONSerialization does not
        // keep an object's order, so this is what makes every platform agree.
        rules[language] = categories
            .compactMap { entry in (entry.value as? String).map { (entry.key, $0) } }
            .sorted { $0.0 < $1.0 }
    }
    return rules
}
