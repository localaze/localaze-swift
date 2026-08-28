/// Turning a resolved message and its arguments into a string.
///
/// The whole algorithm is: pick a variant, walk its parts, concatenate. If an
/// implementation needs more than that, the payload is wrong.
///
/// See `../../contract/runtime-contract.md` section 3.

import Foundation

/// How a `DATETIME` parameter becomes text.
public typealias LocalazeDateFormatter = @Sendable (Date) -> String

/// ISO-8601, UTC, second precision: `2026-03-01T00:00:00Z`.
///
/// The default is deliberate and worth arguing with. Locale-aware formatting is
/// usually what an app wants, but Dart, Swift and Kotlin do not produce the
/// same string for a given locale — Foundation's rules are its own — so making
/// it the default would break the one guarantee these SDKs exist to make. This
/// is identical on all three and therefore testable. An app that wants a local
/// format supplies one, and accepts that it now owns the difference.
///
/// Built by hand rather than with `ISO8601DateFormatter`, whose output depends
/// on option flags a future Foundation could change under us.
public let localazeIsoUtc: LocalazeDateFormatter = { value in
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!

    let parts = calendar.dateComponents(
        [.year, .month, .day, .hour, .minute, .second], from: value)

    func pad(_ number: Int?, _ width: Int = 2) -> String {
        String(format: "%0\(width)d", number ?? 0)
    }

    return "\(pad(parts.year, 4))-\(pad(parts.month))-\(pad(parts.day))"
        + "T\(pad(parts.hour)):\(pad(parts.minute)):\(pad(parts.second))Z"
}

/// Renders `parts`, substituting from `args`.
///
/// A missing argument cannot happen through generated code, which requires
/// every parameter at the call site. It is handled anyway, as the empty string,
/// because the alternative is throwing and nothing in this package throws.
public func localazeRender(
    _ parts: [LocalazePart],
    _ args: [String: Any],
    dateFormatter: LocalazeDateFormatter = localazeIsoUtc
) -> String {
    var out = ""

    for part in parts {
        switch part {
        case let .text(text):
            out += text
        case let .variable(name, _):
            out += substitute(args[name], dateFormatter)
        }
    }
    return out
}

private func substitute(_ value: Any?, _ dateFormatter: LocalazeDateFormatter) -> String {
    guard let value else { return "" }

    if let date = value as? Date { return dateFormatter(date) }
    if let int = value as? Int { return String(int) }

    // An integral double renders without a decimal point, so a count passed as
    // 3.0 reads as "3" here, in Dart and in Kotlin alike. Left to description
    // it would be "3.0" on all three: consistent, but not what a count should
    // look like on a screen.
    if let double = value as? Double {
        if double.isFinite, double == double.rounded() {
            return String(Int(double))
        }
        return String(double)
    }

    if let string = value as? String { return string }
    return String(describing: value)
}
