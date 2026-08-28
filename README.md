# localaze-swift

The Localaze runtime for Swift and iOS. `LZ-56`.

Generated code gives an app typed accessors. This package gives it everything else: fetching a newer catalog, caching it, deciding whether it is safe to apply, and rendering a message from it.

> **Not yet implemented.** The contract and fixtures are in place; the runtime is blocked on the baselines below. See `../README.md` for repository-wide status.

## Blocked on

`Package.swift` is not written until these are confirmed with the iOS team:

- Swift tools version
- **Minimum iOS.** `LZ-56` requires confirming this before choosing between an SPM build plugin and a checked-in generated file, and it also decides whether `async`/`await` is available unconditionally — which shapes the updater API
- Whether macOS or watchOS are in scope

They are recorded as `_to be confirmed_` in `CLAUDE.md`.

## Intended use

```swift
let localaze = Localaze(locale: "ru", config: LocalazeConfig(apiKey: "..."))

localaze.authSignOut                    // "Выход"
localaze.authWelcome(name: "Аян")       // "Добро пожаловать, Аян"
localaze.inboxUnread(count: 11)         // "У вас 11 сообщений"
localaze.inboxUnread()                  // compile error — a plural needs its count
localaze.inboxUnread(count: "eleven")   // compile error — count is numeric
```

The last two lines are the point of the whole SDK. A missing or wrongly typed translation argument is caught by the compiler, not by a user reading a broken screen.

Updating is explicit and never blocks a screen:

```swift
await localaze.update()   // fetches, checks, applies per policy. Never throws.
```

## Configuration

Every option has a default except the key.

```swift
LocalazeConfig(
    apiKey: "...",                       // required; carries project and environment
    baseUrl: "https://localize.sharpy.dev",
    assetPath: "localaze",               // a bundle resource
    cacheDirectory: nil,                 // defaults to Application Support
    policy: .minorAndPatch,
    timeout: 10,
    applyImmediately: false,
    onDiagnostic: { message, error in print(message) }
)
```

Unlike the Dart package, persistence is on by default — Swift can find a writable directory without an extra dependency. Behaviour given the same configuration is identical across platforms; only the default differs.

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
