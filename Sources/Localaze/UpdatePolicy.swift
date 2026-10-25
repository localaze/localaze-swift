/// Semantic versions and the update policy.
///
/// See `contract/runtime-contract.md` section 5.

import Foundation

/// Which updates an app is willing to take.
///
/// A major release is refused under every policy, including `range`. `LZ-62`
/// defines major as signature-breaking by construction, so its messages no
/// longer take the parameters generated accessors pass. Taking one would not be
/// a stale screen, it would be a wrong one.
/// `Hashable` because an app puts this in a SwiftUI `Picker`, which requires
/// it. Free here — every associated value is a `String` — and the demo app
/// found it missing straight away.
public enum LocalazeUpdatePolicy: Sendable, Equatable, Hashable {
    /// Never fetch. The app ships with what it was built with.
    case none

    /// Wording fixes only.
    case patchOnly

    /// Wording fixes and added keys. The default, and exactly the set that
    /// leaves every existing call site valid.
    case minorAndPatch

    /// Same major, and within `from` and `to` inclusive.
    case range(from: String, to: String)

    /// Whether this policy would even make a request. Only `.none` would not.
    public var fetches: Bool { self != .none }

    public var name: String {
        switch self {
        case .none: return "none"
        case .patchOnly: return "patchOnly"
        case .minorAndPatch: return "minorAndPatch"
        case let .range(from, to): return "range(\(from)..\(to))"
        }
    }

    /// Whether `candidate` may replace `current`.
    ///
    /// `LocalazeVersion.accepts` has already established that the candidate is
    /// a greater version with the same major, so this decides only the narrower
    /// question each case's name describes.
    func permits(_ current: LocalazeVersion, _ candidate: LocalazeVersion) -> Bool {
        switch self {
        case .none:
            return false
        case .patchOnly:
            return current.minor == candidate.minor
        case .minorAndPatch:
            return true
        case let .range(from, to):
            guard let lower = LocalazeVersion.parse(from),
                  let upper = LocalazeVersion.parse(to)
            else { return false }
            return candidate >= lower && candidate <= upper
        }
    }
}

/// A semantic version, compared numerically field by field.
///
/// String comparison would put `1.10.0` below `1.9.0`, which is the kind of bug
/// that only shows up once a project has shipped ten minor releases.
public struct LocalazeVersion: Sendable, Comparable, Equatable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(_ major: Int, _ minor: Int, _ patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Returns nil for anything that is not `major.minor.patch`.
    ///
    /// A malformed version is refused rather than coerced, because guessing
    /// what `latest` or `2.0` meant is how a major update gets applied by
    /// accident.
    public static func parse(_ raw: String?) -> LocalazeVersion? {
        guard let raw else { return nil }
        let fields = raw.trimmingCharacters(in: .whitespaces).split(
            separator: ".", omittingEmptySubsequences: false)
        guard fields.count == 3 else { return nil }

        var numbers: [Int] = []
        for field in fields {
            // Int(_:) accepts a leading "-", so non-negative is checked too.
            guard let value = Int(field), value >= 0 else { return nil }
            numbers.append(value)
        }
        return LocalazeVersion(numbers[0], numbers[1], numbers[2])
    }

    public static func < (lhs: LocalazeVersion, rhs: LocalazeVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }

    /// Whether `candidate` may replace `current` under `policy`.
    ///
    /// Three gates, in order of how cheaply they settle the question: the
    /// policy fetches at all, the candidate is actually newer, and the major
    /// matches. The major gate sits outside the policy on purpose — no policy
    /// may override it, so putting it in each case would invite one to forget.
    public static func accepts(
        current: String?,
        candidate: String?,
        policy: LocalazeUpdatePolicy
    ) -> Bool {
        guard policy.fetches,
              let from = parse(current),
              let to = parse(candidate),
              to > from,
              to.major == from.major
        else { return false }

        return policy.permits(from, to)
    }
}
