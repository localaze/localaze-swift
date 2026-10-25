# ``Localaze``

Typed translations generated from a Localaze release, updated over the air.

## Overview

`localaze-generate` writes a `Localaze` struct for your app from a published release: one typed accessor per message, the compiled plural rules, and a compiled-in copy of every catalog. This library is what those accessors run on. It fetches newer catalogs, caches them, decides whether each is safe to apply, and renders messages.

```swift
let t = Localaze.forLocale("ru", config: LocalazeConfig(
    apiKey: key,
    transport: LocalazeUrlSessionTransport(),
    storage: LocalazeFileStorage()))

t.inboxUnread(count: 11)   // "У вас 11 сообщений"
await t.runtime.update()   // fetches, checks, applies per policy. Never throws.
```

Nothing here throws. Every failure leaves the app on the text it already had, and calls ``LocalazeConfig/onDiagnostic`` saying what failed and why.

The [README](https://github.com/localaze/localaze-swift#readme) covers installing, generating, updates over the air and every configuration option.

## Topics

### Configuring

- ``LocalazeConfig``
- ``LocalazeUpdatePolicy``

### Running

- ``LocalazeRuntime``
- ``LocalazeFetchStatus``
- ``LocalazeFetchOutcome``

### Supplying a transport and storage

- ``LocalazeTransport``
- ``LocalazeUrlSessionTransport``
- ``LocalazeStorage``
- ``LocalazeFileStorage``
- ``LocalazeNoStorage``

### Parameters

- ``LocalazeNumber``
