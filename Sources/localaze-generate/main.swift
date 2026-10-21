/// `swift run localaze-generate` — the typed source and catalogs for one
/// published release.
///
/// See `contract/generator-contract.md`. This file is the only part of the
/// generator that touches the network or the filesystem; the decisions are in
/// `LocalazeGenerator`, where the tests reach them without either.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import LocalazeGenerator

let usage = """
Generates typed Localaze translations for one published release.

Usage:
  swift run localaze-generate --key <integration key> --version <x.y.z> --out <file> --assets <dir>
  swift run localaze-generate --manifest <file> --catalogs <dir> --out <file> --assets <dir>

Options:
  --key          Integration key. Carries the project and the environment.
  --version      Release to generate from. A build should pin it.
                 Omitted means the environment's live release.
  --base-url     Default https://localize.sharpy.dev
  --out          Generated file. Default Localaze.g.swift
  --assets       Catalog directory. Default localaze, the folder LocalazeFileStorage reads
  --allow-gaps   Generate even when a translation is missing.
  --manifest     Read the manifest from a file instead of the server.
  --catalogs     Read <language>.json catalogs from a directory.
  --help         Show this text.

"""

func printError(_ text: String) {
    FileHandle.standardError.write(Data((text + "\n").utf8))
}

func fail(_ problems: [String]) -> Int32 {
    printError("Generation failed:")
    for problem in problems { printError("  - \(problem)") }
    return 1
}

let flags: Set<String> = ["allow-gaps", "help"]
let valued: Set<String> = ["key", "version", "base-url", "out", "assets", "manifest", "catalogs"]

enum UsageError: Error { case message(String) }

func parse(_ arguments: [String]) throws -> [String: String?] {
    var options: [String: String?] = [:]
    var index = 0
    while index < arguments.count {
        let argument = arguments[index]
        guard argument.hasPrefix("--") else { throw UsageError.message("Unexpected argument \"\(argument)\".") }
        let body = argument.dropFirst(2)
        let name: String
        var inline: String?
        if let equals = body.firstIndex(of: "=") {
            name = String(body[..<equals])
            inline = String(body[body.index(after: equals)...])
        } else {
            name = String(body)
        }
        if flags.contains(name) {
            options[name] = .some(nil)
        } else if valued.contains(name) {
            if let inline {
                options[name] = inline
            } else if index + 1 < arguments.count {
                index += 1
                options[name] = arguments[index]
            } else {
                throw UsageError.message("--\(name) needs a value.")
            }
        } else {
            throw UsageError.message("Unknown option \"--\(name)\".")
        }
        index += 1
    }
    return options
}

struct Inputs {
    var manifest: String?
    var catalogs: [String: String] = [:]
    var problems: [String] = []
}

func readOffline(_ manifestPath: String, _ catalogsPath: String) -> Inputs {
    guard let manifest = try? String(contentsOfFile: manifestPath, encoding: .utf8) else {
        return Inputs(problems: ["No manifest at \(manifestPath)."])
    }
    var inputs = Inputs(manifest: manifest)
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: catalogsPath) else {
        inputs.problems.append("No catalog directory at \(catalogsPath).")
        return inputs
    }
    // Every catalog present. A missing language is the plan's to report,
    // alongside every other problem.
    for name in names where name.hasSuffix(".json") {
        let path = (catalogsPath as NSString).appendingPathComponent(name)
        if let body = try? String(contentsOfFile: path, encoding: .utf8) {
            inputs.catalogs[String(name.dropLast(5))] = body
        }
    }
    return inputs
}

func get(_ url: URL, key: String) async -> (String?, [String]) {
    var request = URLRequest(url: url, timeoutInterval: 30)
    request.setValue(key, forHTTPHeaderField: "X-Localaze-Key")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    do {
        let (data, response) = try await URLSession.shared.data(for: request)
        let body = String(decoding: data, as: UTF8.self)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 200 { return (body, []) }
        return (nil, problemsOf(url, status, body))
    } catch {
        return (nil, ["Could not reach \(url.scheme ?? "")://\(url.host ?? "")\(url.port.map { ":\($0)" } ?? ""): \(error.localizedDescription)"])
    }
}

/// The server's RFC 9457 problem, read for its detail and any gaps.
func problemsOf(_ url: URL, _ status: Int, _ body: String) -> [String] {
    var gaps: [String] = []
    var detail = ""
    if let data = body.data(using: .utf8),
       let problem = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        if let text = problem["detail"] as? String { detail = ": \(text)" }
        if let list = problem["gaps"] as? [Any] { gaps = list.map { "\($0)" } }
    }
    let hint = status == 401 || status == 403 ? " Check the integration key." : ""
    return ["\(url.path) returned \(status)\(detail.isEmpty ? "." : detail)\(hint)"] + gaps
}

func endpoint(_ base: String, _ path: String, _ query: [(String, String)]) -> URL? {
    guard var components = URLComponents(string: base + path) else { return nil }
    components.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
    return components.url
}

func fetch(key: String, version: String?, baseUrl: String, allowGaps: Bool) async -> Inputs {
    let base = baseUrl.hasSuffix("/") ? String(baseUrl.dropLast()) : baseUrl
    var query: [(String, String)] = []
    if let version, !version.isEmpty { query.append(("version", version)) }
    query.append(("strict", allowGaps ? "false" : "true"))
    guard let manifestUrl = endpoint(base, "/api/v1/read/manifest", query) else {
        return Inputs(problems: ["\(baseUrl) is not a valid base URL."])
    }

    let (manifest, problems) = await get(manifestUrl, key: key)
    guard let manifest else { return Inputs(problems: problems) }

    guard let data = manifest.data(using: .utf8),
          let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let pinned = parsed["version"] as? String,
          let languages = parsed["languages"] as? [String] else {
        return Inputs(manifest: manifest)
    }

    // Pinned to the version the manifest returned, even when the caller did
    // not pin: a release published between the two requests would otherwise
    // pair one version's manifest with another's catalogs.
    var inputs = Inputs(manifest: manifest)
    for language in languages {
        let encoded = language.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? language
        guard let url = endpoint(base, "/api/v1/read/translations/\(encoded)",
                                 [("format", "resolved"), ("version", pinned)]) else { continue }
        let (body, failures) = await get(url, key: key)
        inputs.problems += failures
        if let body { inputs.catalogs[language] = body }
    }
    return inputs
}

func write(_ content: String, to path: String) throws {
    let url = URL(fileURLWithPath: path)
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(content.utf8).write(to: url)
}

func run(_ arguments: [String]) async -> Int32 {
    let options: [String: String?]
    do {
        options = try parse(arguments)
    } catch UsageError.message(let message) {
        printError("error: \(message)\n")
        printError(usage)
        return 64
    } catch {
        return 64
    }

    if options["help"] != nil {
        print(usage, terminator: "")
        return 0
    }

    func value(_ name: String) -> String? { options[name] ?? nil }

    let offline = value("manifest") != nil || value("catalogs") != nil
    if offline && (value("manifest") == nil || value("catalogs") == nil) {
        printError("error: --manifest and --catalogs go together.")
        return 64
    }
    if !offline && (value("key") ?? "").isEmpty {
        printError("error: --key is required, or --manifest with --catalogs.")
        return 64
    }

    let allowGaps = options["allow-gaps"] != nil
    let inputs = offline
        ? readOffline(value("manifest")!, value("catalogs")!)
        : await fetch(key: value("key")!, version: value("version"),
                      baseUrl: value("base-url") ?? "https://localize.sharpy.dev",
                      allowGaps: allowGaps)
    guard inputs.problems.isEmpty, let manifest = inputs.manifest else {
        return fail(inputs.problems.isEmpty ? ["No manifest was read."] : inputs.problems)
    }

    let result = plan(manifest: manifest, catalogs: inputs.catalogs, allowGaps: allowGaps)
    for warning in result.warnings { printError("warning: \(warning)") }
    guard let planned = result.plan else { return fail(result.problems) }

    let out = value("out") ?? "Localaze.g.swift"
    let assets = value("assets") ?? "localaze"
    do {
        try write(emitSwift(planned), to: out)
        for language in planned.languages {
            try write(planned.catalogs[language]!, to: (assets as NSString).appendingPathComponent("\(language).json"))
        }
    } catch {
        return fail(["Could not write: \(error.localizedDescription)"])
    }

    print("Generated \(out) from \(planned.version) (\(planned.environment)): "
        + "\(planned.keys.count) keys, \(planned.languages.count) languages. Catalogs in \(assets)/.")
    return 0
}

exit(await run(Array(CommandLine.arguments.dropFirst())))
