@preconcurrency import BigInt
import Foundation
import SwiftCardanoCore

/// Argument "sizes" as the Plutus cost model measures them.
///
/// Mirrors `PlutusCore.Evaluation.Machine.ExMemoryUsage`. The reference
/// implementation builds a lazy tree of sizes (`CostRose`) so a builtin can be
/// costed without forcing its whole argument; every costing function sums that
/// tree before using it, so computing the total directly is equivalent.
enum ExMemory {

    /// Integers are measured in 64-bit words, with zero costing one word.
    static func size(integer value: BigInt) -> Int64 {
        if value.isZero { return 1 }
        // `integerLog2` is the index of the highest set bit.
        return Int64(value.magnitude.bitWidth - 1) / 64 + 1
    }

    /// Byte strings are measured in 8-byte words, with the empty string
    /// costing one word — note `(0 - 1) / 8 == 0` with truncating division, so
    /// the formula already yields 1 and must not be replaced by a rounding
    /// division that yields 0.
    static func size(byteString count: Int) -> Int64 {
        Int64((count - 1) / 8) + 1
    }

    /// `Data` costs four per node, plus the size of each leaf.
    static func size(data: PlutusData) -> Int64 {
        var total: Int64 = 0
        var stack: [PlutusData] = [data]
        while let node = stack.popLast() {
            total &+= 4
            switch node {
            case .constructor(let constr):
                stack.append(contentsOf: constr.fields)
            case .map(let entries):
                for (key, value) in entries {
                    stack.append(key)
                    stack.append(value)
                }
            case .array(let items):
                stack.append(contentsOf: items)
            case .indefiniteArray(let items):
                stack.append(contentsOf: items.getAll())
            case .bigInt(let n):
                total &+= size(integer: bigInt(n))
            case .bytes(let b):
                total &+= size(byteString: b.data.count)
            }
        }
        return total
    }

    /// `PlutusData`'s integers are split across three representations.
    private static func bigInt(_ value: BigInteger) -> BigInt {
        switch value {
        case .int(let v):     return BigInt(v)
        case .bigUInt(let v): return BigInt(v)
        case .bigNInt(let v): return -v
        }
    }

    /// The size of a fully-evaluated constant.
    static func size(constant: UPLCConstant) -> Int64 {
        switch constant {
        case .integer(let n):        return size(integer: n)
        case .byteString(let b):     return size(byteString: b.count)
        case .string(let s):         return Int64(s.count)
        case .unit:                  return 1
        case .bool:                  return 1
        case .list(_, let items):    return Int64(items.count)
        // A pair's size is never consumed by any costing function; the
        // reference implementation uses `maxBound` so that a model which did
        // read it would be impossible to miss.
        case .pair:                  return Int64.max
        case .data(let d):           return size(data: d)
        // BLS elements are fixed width: 48, 96 and 576 bytes over 8.
        case .bls12_381G1Element:    return 18
        case .bls12_381G2Element:    return 36
        case .bls12_381MlResult:     return 72
        }
    }

    /// The size of a machine value.
    static func size(value: Value) -> Int64 {
        if case .con(let constant) = value { return size(constant: constant) }
        // Only constants ever reach a builtin's costing function.
        return 1
    }

    // MARK: - Non-default size measures

    /// Some builtins measure an argument differently from its type's default.
    /// Wrapping the argument is how the reference implementation does it, and
    /// the wrapper must match the one used in the costing benchmark.
    enum Measure: Sendable {
        /// The type's usual measure.
        case standard
        /// An integer counted as the number of 8-byte words it describes,
        /// used where the integer is a *length* (`integerToByteString`,
        /// `replicateByte`).
        case numBytesAsNumWords
        /// An integer counted by its absolute value, used where the cost
        /// depends on the value itself (`shiftByteString`, `rotateByteString`).
        case integerLiterally
    }

    static func size(value: Value, measure: Measure) -> Int64 {
        guard measure != .standard, case .con(let constant) = value else {
            return size(value: value)
        }
        switch (measure, constant) {
        case (.numBytesAsNumWords, .integer(let n)):
            // `((|n| - 1) div 8) + 1`, with *flooring* division. Zero gives
            // zero here, unlike the byte-string measure's truncating division
            // which gives one.
            return clamp(floorDiv(BigInt(n.magnitude) - 1, 8) + 1)
        case (.integerLiterally, .integer(let n)):
            return clamp(BigInt(n.magnitude))
        default:
            return size(constant: constant)
        }
    }

    /// Flooring division, matching Haskell's `div` (Swift's `/` truncates).
    private static func floorDiv(_ lhs: BigInt, _ rhs: BigInt) -> BigInt {
        var quotient = lhs / rhs
        if lhs % rhs != 0 && ((lhs < 0) != (rhs < 0)) { quotient -= 1 }
        return quotient
    }

    /// Saturate to `Int64`, as the reference implementation does — a size
    /// beyond this range cannot arise from a real script, and trapping on the
    /// conversion would take down the evaluator.
    private static func clamp(_ value: BigInt) -> Int64 {
        if value > BigInt(Int64.max) { return Int64.max }
        if value < BigInt(Int64.min) { return Int64.min }
        return Int64(value)
    }

    /// The per-argument size measures for builtins that do not use the default.
    static func measures(for function: DefaultFunction) -> [Measure]? {
        switch function {
        case .integerToByteString:
            // (useBigEndian, requestedWidth, value)
            return [.standard, .numBytesAsNumWords, .standard]
        case .replicateByte:
            return [.numBytesAsNumWords, .standard]
        case .shiftByteString, .rotateByteString:
            return [.standard, .integerLiterally]
        // `appendString`, `equalsString` and `encodeUtf8` measure their text
        // by character count. A later Plutus release re-measures them by
        // UTF-8 byte length over four (`TextCostedByByteLength`); the
        // conformance budgets bundled here predate that, and switching makes
        // all four of their cases disagree.
        default:
            return nil
        }
    }

    /// The sizes of a builtin's arguments, applying any non-default measures.
    static func sizes(for function: DefaultFunction, arguments: [Value]) -> [Int64] {
        guard let measures = measures(for: function) else {
            return arguments.map { size(value: $0) }
        }
        return arguments.enumerated().map { index, argument in
            size(value: argument, measure: index < measures.count ? measures[index] : .standard)
        }
    }
}
