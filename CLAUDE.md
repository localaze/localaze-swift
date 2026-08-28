# localaze-swift

The Swift/iOS runtime package. `LZ-56`.

Read `../CLAUDE.md` for the rules that govern every SDK package, and `../contract/runtime-contract.md` for the behaviour this one implements. This file records only what is specific to Swift.

## Baselines

**Not yet confirmed. Do not guess, and do not write `Package.swift` until these are filled in.**

| | |
|---|---|
| Swift tools version | `_to be confirmed_` |
| Minimum iOS | `_to be confirmed_` |
| Other platforms (macOS, watchOS) | `_to be confirmed_` |
| Distribution | Local path dependency for now. SPM from an internal source is a later ticket |

`LZ-56` names this explicitly: *"Confirm the minimum iOS version with the app teams before choosing between a build plugin and a checked-in generated file."* The answer changes more than a number — it decides whether generation runs as an SPM build plugin or is checked in.

Minimum iOS also decides whether `async`/`await` is available unconditionally, which shapes the whole updater API. Settle it before writing the transport.

## Layout

```
localaze-swift/
├── CLAUDE.md
├── README.md
├── Package.swift                  blocked on Baselines
├── Sources/
│   └── Localaze/
│       ├── Localaze.swift               the public entry point
│       ├── LocalazeConfig.swift
│       ├── LocalazeCatalog.swift        parsing, part walking
│       ├── Renderer.swift               variant selection and substitution
│       ├── Signature.swift              names and types, compatibility check
│       ├── UpdatePolicy.swift           policy, version comparison
│       ├── CatalogStore.swift           applied, cached, bundled, compiled-in
│       ├── Updater.swift                currentVersion, fetchIfAccepted, ETag
│       ├── Diagnostics.swift
│       ├── Transport.swift              the protocol
│       ├── Storage.swift                the protocol
│       └── Platform/                    default implementations, the only place URLSession appears
└── Tests/
    └── LocalazeTests/
        ├── Conformance/                 one file per group in ../contract/conformance.json
        └── Fakes/                       FakeTransport, FakeStorage
```

`public` is a deliberate act. Default to internal and widen only when something outside needs it.

## Transport and storage

`Transport` and `Storage` are protocols. **Core code never touches `URLSession` or `FileManager` directly.**

`Sources/Localaze/Platform/` holds the defaults and is the only directory permitted to. A runtime testable only against a live server is a runtime that is not tested, and every failure row in contract §8 is reachable with a fake and unreachable without one.

## Defaults

| Option | Swift default |
|---|---|
| `assetPath` | Bundle resource named `localaze` |
| `cacheDirectory` | Application Support, under the bundle identifier |

Unlike Dart, Swift can find a writable directory without pulling in a dependency, so persistence is on by default here. **That is a real divergence in defaults, not in behaviour** — the contract requires identical behaviour given the same configuration, and a platform default that differs is fine as long as it is documented. Say so in `README.md`.

## Generation: no `.stringsdict`

`LZ-56` names the tempting alternative and rejects it: generating into `.stringsdict` and leaning on Foundation's plural handling.

It is worse. Foundation's plural rules are its own, and the `LZ-54` guarantee is that all three platforms behave identically. Explicit generated Swift control flow is what makes that true. The same reasoning is why dates render ISO-8601 rather than through `DateFormatter` — see contract §3.

## UIKit and SwiftUI

`LZ-56` requires the output to work from both, and to read naturally at the call site. Locale switching at runtime is required.

Keep any SwiftUI-specific surface — an `EnvironmentKey`, an `ObservableObject` — in its own file, and keep the core free of SwiftUI so a UIKit-only app carries none of it.

## Never do

Everything in `../CLAUDE.md`, plus:

- Never touch `URLSession` or `FileManager` outside `Sources/Localaze/Platform/`
- Never generate `.stringsdict` or rely on Foundation's plural rules
- Never make the core import SwiftUI or UIKit
- Never mark something `public` without a caller outside the package
- Never write `Package.swift` before the minimum iOS version is confirmed
