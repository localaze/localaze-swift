# Changelog

Versions follow `../RELEASING.md`: the Dart, Swift and Kotlin packages release together, at the same version.

## 0.1.0 — unreleased

First release.

- `Localaze`: the runtime. Fetches, caches and applies catalogs under an update policy and a names-and-types signature check, renders messages, and never throws. `LocalazeNumber` is what a generated `NUMBER` parameter accepts.
- `localaze-generate`: typed accessors and catalogs from a published release, per `../contract/generator-contract.md`. The generated file is checked in.
