# Localaze for Swift

Typed translations for iOS and macOS apps, generated from a [Localaze](https://localize.sharpy.dev) release and updated over the air.

[![CI](https://github.com/localaze/localaze-swift/actions/workflows/ci.yml/badge.svg)](https://github.com/localaze/localaze-swift/actions/workflows/ci.yml)
[![Version](https://img.shields.io/github/v/tag/localaze/localaze-swift?label=version&sort=semver)](https://github.com/localaze/localaze-swift/tags)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Swift 5.9+](https://img.shields.io/badge/swift-5.9%2B-F05138)
![iOS 16+ · macOS 13+](https://img.shields.io/badge/platforms-iOS%2016%2B%20%C2%B7%20macOS%2013%2B-lightgrey)

The `Localaze` library is the runtime; the `localaze-generate` executable writes your app's typed accessors from a release. No dependencies.

## Why

**A plural cannot be called without its count.** Every message becomes a typed accessor, so the compiler checks each call site:

<!-- snippet: examples/swiftui-app/Sources/LocalazeDemo/ReadmeSnippets.swift#use -->
```swift
let lines = [
    t.authSignOut,                          // "Выход"
    t.authWelcome(name: "Аян"),             // "Добро пожаловать, Аян"
    t.inboxUnread(count: 1),                // "У вас 1 сообщение"
    t.inboxUnread(count: 11),               // "У вас 11 сообщений"
    t.billingDue(when: Date(timeIntervalSince1970: 1_772_323_200)),
]
// Neither of these compiles:
// t.inboxUnread()                  a plural needs its count
// t.inboxUnread(count: "eleven")   the count is a number
```

A `NUMBER` parameter takes any standard integer or floating-point type, or `Decimal`, without converting.

**A missing translation fails the build, not the screen.** Generation refuses a release in which any language lacks a message, and names every gap at once.

**Wording fixes reach users without an app release.** The app ships with every catalog compiled in, and fetches newer wording when you ask it to. A new catalog is applied only if every accessor the app was built with still fits it.

## Install

In `Package.swift`, or in Xcode under *File → Add Package Dependencies…* with the same URL:

<!-- uncompiled -->
```swift
.package(url: "https://github.com/localaze/localaze-swift.git", from: "0.2.0")
```

and add the `Localaze` product to your app target.

## Generate

With an integration key from the project's settings in Localaze:

```sh
swift run --package-path path/to/localaze-swift localaze-generate \
    --key "$LOCALAZE_KEY" --version 1.4.0 \
    --out MyApp/Localaze.g.swift --assets MyApp/localaze
```

From a Swift package that depends on this one, `swift run localaze-generate …` is enough. Keep the key in an environment variable or your CI's secrets, never in the repository. The command writes:

| Output | Default | Check it in? |
|---|---|---|
| `--out` | `Localaze.g.swift` | **Yes.** Typed accessors, plural rules and a compiled-in copy of every catalog. Deterministic, so regenerating unchanged content gives no diff |
| `--assets` | `localaze/` | **Yes.** One `<language>.json` per language. Add the folder to the app target as a folder reference; `LocalazeFileStorage` reads it from there |

The generated file is checked in rather than produced by a build plugin: a build plugin cannot reach the network without a prompt on every build, and a build that fetches is not reproducible.

**Pin `--version`.** Without it the generator takes the environment's live release. Regenerate when keys change; wording changes need no regeneration.

Generation exits non-zero, listing every problem, when a translation is missing, a catalog is from a different release, or a key cannot become a Swift name. `--allow-gaps` turns missing translations into warnings for early development. `--manifest manifest.json --catalogs catalogs/` generates offline from saved responses.

## Use

<!-- snippet: examples/swiftui-app/Sources/LocalazeDemo/ReadmeSnippets.swift#setup -->
```swift
let t = Localaze.forLocale("ru", config: LocalazeConfig(
    apiKey: ProcessInfo.processInfo.environment["LOCALAZE_KEY"] ?? "",
    onDiagnostic: { message, error in print("localaze:", message, error ?? "") },
    transport: LocalazeUrlSessionTransport(),
    storage: LocalazeFileStorage()  // the app's `localaze` folder, and a cache
))
```

In SwiftUI, hold the translations in an observable object, so a locale switch or a newly applied catalog re-renders:

<!-- snippet: examples/swiftui-app/Sources/LocalazeDemo/ReadmeSnippets.swift#swiftui -->
```swift
@MainActor
final class Translations: ObservableObject {
    @Published private(set) var t: Localaze

    init(locale: String) { t = Self.make(locale) }

    func setLocale(_ locale: String) async {   // no restart
        t = Self.make(locale)
        await t.runtime.load()
    }

    func update() async {
        let status = await t.runtime.update()
        if status.isApplied { objectWillChange.send() }   // re-render with the new catalog
    }

    private static func make(_ locale: String) -> Localaze {
        Localaze.forLocale(locale, config: LocalazeConfig(
            apiKey: "…",
            transport: LocalazeUrlSessionTransport(),
            storage: LocalazeFileStorage()))
    }
}

struct InboxTitle: View {
    @EnvironmentObject var translations: Translations

    var body: some View {
        Text(translations.t.inboxUnread(count: 3))
            .task { await translations.update() }
    }
}
```

## Updates over the air

Fetching is explicit, so it never blocks a screen. Call it on launch, on returning to the foreground, or on a timer:

<!-- snippet: examples/swiftui-app/Sources/LocalazeDemo/ReadmeSnippets.swift#update -->
```swift
await t.runtime.load()                      // the cached catalog, if any
let status = await t.runtime.update()       // never throws
print(status.isApplied ? "now on \(t.runtime.version)" : "still on \(t.runtime.version)")
```

- **Offline**, the app renders the newest catalog it has: a cached update, else the bundled `localaze` folder, else the compiled-in copy. A first launch with no network still shows every message.
- **The update policy** decides which releases are taken: `.none`, `.patchOnly`, `.minorAndPatch` (the default) or `.range(from:to:)`. A **major** release is never applied, whatever the policy, because its messages no longer fit the accessors the app was built with.
- **The signature check** applies a catalog only if every key the app knows is present with the same parameter names and types. An incompatible catalog is refused whole.
- **Wording changes need no regeneration.** Adding, removing or retyping a key does, and that is a new version of the app.

## Errors

Nothing in this package throws or fails a `Task`. A network failure, a malformed payload, an unreadable cache or a refused update each leaves the app on the text it already had. A translation outage is a stale screen, not a crash.

The cost is that a wrong API key looks exactly like a quiet network. **Pass `onDiagnostic` while integrating**: it is called with a message naming what failed and why, for every failure that was swallowed.

```text
localaze: /api/v1/read/version returned 401
localaze: The published version could not be read
```

## Configuration

Every option has a default except the key:

<!-- snippet: examples/swiftui-app/Sources/LocalazeDemo/ReadmeSnippets.swift#config -->
```swift
LocalazeConfig(
    apiKey: key,                            // carries the project and the environment
    baseUrl: "https://localize.sharpy.dev",
    policy: .minorAndPatch,
    timeout: 10,
    applyImmediately: false,
    dateFormatter: localazeIsoUtc,
    onDiagnostic: nil,
    transport: nil,                         // no network: LocalazeUrlSessionTransport()
    storage: nil                            // updates last for the session: LocalazeFileStorage()
)
```

| Option | Default | What it does |
|---|---|---|
| `apiKey` | required | An integration key. It carries the project and the environment, so a staging build cannot read production |
| `baseUrl` | `https://localize.sharpy.dev` | Your Localaze server, if you run your own |
| `policy` | `.minorAndPatch` | Which releases an update may apply |
| `timeout` | 10 seconds | Per request |
| `applyImmediately` | `false` | Apply a fetched catalog at once rather than on `applyPending()` or the next launch |
| `dateFormatter` | ISO-8601 UTC | How `DATETIME` parameters render |
| `onDiagnostic` | none | Called for every swallowed failure |
| `transport` | none | How to fetch. `LocalazeUrlSessionTransport()`, or your own `LocalazeTransport` |
| `storage` | none | Where to read bundled catalogs and cache updates. `LocalazeFileStorage()` uses the main bundle's `localaze` folder and Application Support; without it, updates last for the session |

Plurals are generated Swift, never `.stringsdict`, and nothing goes through `NSLocalizedString`. Foundation's plural rules are its own, and routing through them would make iOS the one platform that renders differently.

## Compatibility

| | |
|---|---|
| Swift | 5.9 or later, in Swift 5 or Swift 6 language mode |
| Platforms | iOS 16, macOS 13 |
| Localaze server | Any that serves `/api/v1/read/manifest` and `format=resolved` catalogs, which every release of Localaze does |

**One version across Dart, Swift and Kotlin.** The three SDKs implement one [contract](https://github.com/localaze/localaze-contract) and are released together, so `0.2.0` behaves the same on every platform. Versions are semantic; a change to what the generator writes counts as API. See [`RELEASING.md`](https://github.com/localaze/localaze-contract/blob/main/RELEASING.md).

## Links

- **Other platforms:** [Dart and Flutter](https://github.com/localaze/localaze-dart) · [Kotlin and Android](https://github.com/localaze/localaze-kotlin)
- **The contract** all three implement: [localaze-contract](https://github.com/localaze/localaze-contract)
- **Changelog:** [`CHANGELOG.md`](CHANGELOG.md)
- **A working app:** [`examples/swiftui-app`](examples/swiftui-app/), against the [stub read API](https://github.com/localaze/localaze-contract/tree/main/stub-server)
- **Problems:** [open an issue](https://github.com/localaze/localaze-swift/issues). Security issues: see [`SECURITY.md`](SECURITY.md)
- **Contributing:** [`CONTRIBUTING.md`](CONTRIBUTING.md)

MIT licensed. See [`LICENSE`](LICENSE).
