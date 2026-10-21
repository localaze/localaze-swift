# localaze-swift

The Localaze runtime for Swift and iOS. `LZ-56`.

Generated code gives an app typed accessors. This package gives it everything else: fetching a newer catalog, caching it, deciding whether it is safe to apply, and rendering a message from it.

It also ships the generator that writes those accessors from a published release.

> **Implemented.** 92 tests pass against the shared fixture project. Run them with `swift test`.

## Baselines

Chosen rather than confirmed — the app teams delegated the call. Reasoning is in `CLAUDE.md`, and each is a one-line change.

- `swift-tools-version: 5.9`, so the package stays in Swift 5 language mode and either kind of app consumes it cleanly. Generated code also compiles cleanly in Swift 6 language mode
- **Minimum iOS 16** — about four years old in 2026, and it brings `Duration`
- macOS 13 as well, so `swift test` runs on a build machine rather than a simulator
- **Zero dependencies**

## Generating

Run from a checkout of this package, or from any package that depends on it, with an integration key from the project's settings:

```
swift run localaze-generate --key $LOCALAZE_KEY --version 1.4.0 \
    --out MyApp/Localaze.g.swift --assets MyApp/localaze
```

That writes two things:

| Output | Default | Contents |
|---|---|---|
| `--out` | `Localaze.g.swift` | The `Localaze` struct: typed accessors, the signature, plural rules, and a compiled-in copy of every catalog |
| `--assets` | `localaze/` | One `<language>.json` per language. Add the folder to the app target as a folder reference, which is where `LocalazeFileStorage` looks |

**The generated file is checked in, not produced by a build plugin.** A build plugin cannot reach the network without asking for permission on every build, and a build that silently fetches is a build that is not reproducible. Generation is deterministic, so regenerating unchanged content produces no diff. This settles the choice `LZ-56` left open.

**Pin `--version` in a build.** Without it the generator takes the environment's live release.

Generation fails, naming every problem at once, when a translation is missing, a catalog is from a different release, or a key cannot become a Swift name. `--allow-gaps` turns missing translations into warnings for early development. `--manifest` and `--catalogs` replay saved server responses for a build with no network.

The full specification is `../contract/generator-contract.md`.

## Using it

```swift
let t = Localaze.forLocale("ru", config: LocalazeConfig(
    apiKey: "...",
    storage: LocalazeFileStorage()))

t.authSignOut                    // "Выход"
t.authWelcome(name: "Аян")       // "Добро пожаловать, Аян"
t.inboxUnread(count: 11)         // "У вас 11 сообщений"
t.inboxUnread()                  // compile error — a plural needs its count
t.inboxUnread(count: "eleven")   // compile error — count is numeric
```

The last two lines are the point of the whole SDK. A missing or wrongly typed translation argument is caught by the compiler, not by a user reading a broken screen.

A `NUMBER` parameter takes `some LocalazeNumber`, which every standard integer and floating-point type adopts, along with `Decimal`. Pass an `Int` or a `Double` without converting it.

Updating is explicit and never blocks a screen:

```swift
await t.runtime.update()   // fetches, checks, applies per policy. Never throws.
```

## Configuration

Every option has a default except the key.

```swift
LocalazeConfig(
    apiKey: "...",                       // required; carries project and environment
    baseUrl: "https://localize.sharpy.dev",
    policy: .minorAndPatch,
    timeout: 10,
    applyImmediately: false,
    dateFormatter: localazeIsoUtc,
    onDiagnostic: { message, error in print(message) },
    transport: nil,                      // LocalazeUrlSessionTransport
    storage: nil                         // LocalazeNoStorage: updates last for the session
)
```

`LocalazeFileStorage()` reads bundled catalogs from the `localaze` folder of the main bundle and caches updates in Application Support, so updates survive a restart.

**Pass `onDiagnostic` during integration.** Nothing here throws, which means a wrong API key and a quiet network look identical from the outside.

## What it will not do

- **It never throws.** No `throws`, no failed `Task`. Every failure leaves your app on the text it already had.
- **It never parses MF2**, and never uses `.stringsdict`. Catalogs arrive already parsed, and plural rules are generated Swift. Foundation's plural rules are its own, and routing through them would make iOS the one platform that renders differently.
- **It never applies a major update**, whatever the policy says.
- **It never applies half a catalog.**

## Reading order

1. `../contract/runtime-contract.md` — the behaviour, specified once for all three platforms
2. `CLAUDE.md` — what is specific to Swift
3. `../contract/conformance.json` — every case this package must pass
