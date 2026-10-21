# localaze-swift

The Swift/iOS runtime package, and its generator. `LZ-56`.

Read `../CLAUDE.md` for the rules that govern every SDK package, and `../contract/runtime-contract.md` for the behaviour this one implements. This file records only what is specific to Swift.

## Baselines

**Chosen, not confirmed.** The app teams were asked and delegated the decision, so these are recorded with their reasoning to make an override cheap.

| | | Why |
|---|---|---|
| Swift tools | **5.9** | Keeps the package in Swift 5 language mode, so an app on either mode consumes it without strict-concurrency friction. Nothing here needs a 6.0-only feature. Verified compiling on Swift 6.3.3 |
| Minimum iOS | **16** | Roughly four years old in 2026, and it brings `Duration`. `async`/`await` needs only 13, so the updater API is safe well below this |
| macOS | 13 | So `swift test` runs on a build machine rather than a simulator. Not a shipping target |
| watchOS / tvOS | Out of scope | |
| Dependencies | **None** | |
| Distribution | Local path dependency. SPM from the internal source is a later ticket | |

`LZ-56` asked for a choice between an SPM build plugin and a checked-in generated file. **It is a checked-in file**, written by the `localaze-generate` command. A build plugin cannot reach the network without a permission prompt on every build, and a build that fetches is not reproducible. iOS 16 did not bear on the choice.

### Foundation is kept at arm's length

Three places where the obvious Foundation answer is the wrong one, all for the same reason — `LZ-54` guarantees the three platforms render identically, and Foundation's rules are its own:

- **Dates** use a hand-built formatter, not `ISO8601DateFormatter`, whose output depends on option flags a future Foundation could change.
- **Plurals** compile into generated Swift. No `.stringsdict`, which `LZ-56` rejects explicitly.
- **No `NSLocalizedString`** anywhere.

A purity test enforces all three.

## Layout

```
localaze-swift/
├── CLAUDE.md
├── README.md
├── Package.swift
├── Sources/
│   ├── LocalazeGenerator/               Plan.swift decides and checks, SwiftEmitter.swift spells
│   ├── localaze-generate/               the command: network and files, nothing else
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
│       ├── LocalazeNumber.swift         what a NUMBER parameter accepts
│       └── Platform/                    default implementations, the only place URLSession appears in the runtime
└── Tests/
    ├── LocalazeTests/
    │   ├── Conformance/                 one file per group in ../contract/conformance.json
    │   └── Fakes/                       FakeTransport, FakeStorage
    ├── LocalazeGeneratorTests/          the generator group, and the command as a process
    └── LocalazeGoldenTests/             Localaze.g.swift, the golden, compiled and rendered
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

## The generator

`swift run localaze-generate`, specified in `../contract/generator-contract.md`.

- `LocalazeGenerator` is a target, not a product: nothing outside links it. It takes the manifest and catalogs as strings and returns a plan or every problem.
- `localaze-generate` is the only generator code that touches `URLSession` or `FileManager`. It is an executable product, so an app's build machine can run it from the dependency.
- File-private helpers in generated code start with an underscore. No accessor can, so a key named `plural` cannot shadow them.
- The golden file is `Tests/LocalazeGoldenTests/Localaze.g.swift`, compiled as part of a test target so a change that stops it compiling fails the suite. When output changes on purpose, run `UPDATE_GOLDEN=1 swift test --filter GeneratorTests/testGolden` and review the diff.

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
