# swiftui-app

A SwiftUI demo over `localaze-swift`, exercising every feature.

## Run it

Start the stub server first:

```
cd ../stub-server && dart run serve.dart
```

Then, on macOS:

```
swift run LocalazeDemo
```

For iOS, open `Package.swift` in Xcode and run on a simulator or a device.

A device on the same network cannot reach `localhost`. Pass the machine's address:

```
LOCALAZE_BASE_URL=http://192.168.1.20:8787 swift run LocalazeDemo
```

## Tests

```
swift test
```

12 tests drive `DemoModel` against a fake transport — no network, so they run in CI. They cover the generated accessors, locale switching, and every acceptance and refusal the Server section can set up.

## Why it is a package, not an .xcodeproj

So `swift build` and `swift test` work from a terminal and in CI. Xcode opens `Package.swift` and runs it as an app just the same, and macOS sits alongside iOS in the platforms list so the whole thing compiles on a build machine — which is what let this app be verified rather than only written.

## What to try

Set the Server section to **`retyped`** and press Check for update.

It offers `1.0.2`, a patch. The policy accepts it. Every key is present. `inbox.unread` still declares a parameter called `count`. Only the *type* changed, `NUMBER` to `STRING` — and `Localaze.g.swift` has already promised every call site `inboxUnread(count: Int)`.

The SDK refuses the whole catalog and the Diagnostics section says why. A name-only signature check, which is what the first implementation did, takes it.

## `Localaze.g.swift` is generated

It is the real output of the Swift generator for the fixture release. `localaze/` holds the catalogs it wrote alongside; a real app adds that folder to its target for `LocalazeFileStorage`, while this demo configures no storage and renders from the compiled-in copies.

Regenerate from the stub server, exactly as an app would from production:

```
swift run --package-path ../../localaze-swift localaze-generate \
    --key demo-key --version 1.0.0 --base-url http://localhost:8787 \
    --out Sources/LocalazeDemo/Localaze.g.swift --assets localaze
```

Or offline with `--manifest ../../contract/fixtures/manifest.json --catalogs ../../contract/fixtures/catalogs` in place of the key and URL. Both produce the same file, byte for byte.

Two things it demonstrates that are easy to miss:

- `inboxUnread(count:)` **requires** its count, because the message selects on it. Deleting the argument is a compile error.
- The Russian plural rule is Swift control flow, including the `i % 100 != 11` exclusion. No plural data ships, and Foundation's rules are not consulted — `LZ-56` rejects `.stringsdict` for exactly that reason.

## What this app changed in the SDK

`LocalazeUpdatePolicy` was `Equatable` but not `Hashable`, so it could not go in a SwiftUI `Picker`. Free to add, and the app found it on the first build.
