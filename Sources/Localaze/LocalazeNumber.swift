/// A value a `NUMBER` parameter accepts.
///
/// Generated accessors take `some LocalazeNumber` so a call site passes an
/// `Int`, a `Double` or any other standard number without converting it. Dart
/// takes `num` and Kotlin takes `Number`; Swift has no common numeric
/// supertype, so this is it. See `generator-contract.md` §6.

import Foundation

public protocol LocalazeNumber {
    /// The value as a `Double`, which is what plural selection runs on.
    var localazeValue: Double { get }
}

extension Int: LocalazeNumber { public var localazeValue: Double { Double(self) } }
extension Int8: LocalazeNumber { public var localazeValue: Double { Double(self) } }
extension Int16: LocalazeNumber { public var localazeValue: Double { Double(self) } }
extension Int32: LocalazeNumber { public var localazeValue: Double { Double(self) } }
extension Int64: LocalazeNumber { public var localazeValue: Double { Double(self) } }
extension UInt: LocalazeNumber { public var localazeValue: Double { Double(self) } }
extension UInt8: LocalazeNumber { public var localazeValue: Double { Double(self) } }
extension UInt16: LocalazeNumber { public var localazeValue: Double { Double(self) } }
extension UInt32: LocalazeNumber { public var localazeValue: Double { Double(self) } }
extension UInt64: LocalazeNumber { public var localazeValue: Double { Double(self) } }
extension Double: LocalazeNumber { public var localazeValue: Double { self } }
extension Float: LocalazeNumber { public var localazeValue: Double { Double(self) } }
extension Decimal: LocalazeNumber {
    public var localazeValue: Double { NSDecimalNumber(decimal: self).doubleValue }
}
