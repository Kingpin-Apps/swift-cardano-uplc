import BigInt
import Foundation
import SwiftCardanoCore

/// Runtime values produced during CEK evaluation.
public indirect enum Value: Sendable {
    /// A fully-evaluated constant.
    case con(UPLCConstant)
    /// A delayed (unevaluated) term together with its closure environment.
    case delay(Term<NamedDeBruijn>, Environment)
    /// A lambda closure.
    case lambda(parameterName: NamedDeBruijn, body: Term<NamedDeBruijn>, env: Environment)
    /// A partially-applied builtin accumulating arguments.
    case partiallyApplied(DefaultFunction, [Value], forces: Int)
    /// A fully-constructed data constructor value.
    case constr(tag: UInt64, fields: [Value])
}

extension Value {
    /// Compute the memory cost of a value (in ExMem units).
    /// Matches the Rust `to_ex_mem` implementation.
    public func exMem() -> Int64 {
        switch self {
        case .con(let c): return c.exMem()
        case .delay:      return 1
        case .lambda:     return 1
        case .partiallyApplied: return 1
        case .constr(_, let fields): return fields.reduce(0) { $0 + $1.exMem() } + 1
        }
    }
}

extension UPLCConstant {
    /// Memory cost in ExMem units.
    func exMem() -> Int64 {
        switch self {
        case .integer(let n):
            if n == 0 { return 1 }
            let bits = n.magnitude.bitWidth
            return Int64((bits - 1) / 64 + 1)
        case .byteString(let d):
            if d.isEmpty { return 1 }
            return Int64((d.count - 1) / 8 + 1)
        case .string(let s):
            return Int64(s.unicodeScalars.count)
        case .unit:       return 1
        case .bool:       return 1
        case .list(_, let items):
            return items.reduce(0) { $0 + $1.exMem() }
        case .pair(_, _, let a, let b):
            return a.exMem() + b.exMem()
        case .data(let pd):
            return pd.exMem()
        case .bls12_381G1Element:  return 48 / 8
        case .bls12_381G2Element:  return 96 / 8
        case .bls12_381MlResult:   return 576 / 8
        }
    }
}

extension PlutusData {
    /// Memory cost for PlutusData — 4 per node, size of leaves.
    func exMem() -> Int64 {
        switch self {
        case .constructor(let c):
            return 4 + c.fields.reduce(0) { $0 + $1.exMem() }
        case .map(let m):
            return 4 + m.reduce(0) { $0 + $1.key.exMem() + $1.value.exMem() }
        case .array(let a):
            return 4 + a.reduce(0) { $0 + $1.exMem() }
        case .indefiniteArray(let a):
            return 4 + a.reduce(0) { $0 + $1.exMem() }
        case .bigInt(let n):
            return n.exMem()
        case .bytes(let b):
            if b.count == 0 { return 1 }
            return Int64((b.count - 1) / 8 + 1)
        }
    }
}

extension SwiftCardanoCore.BigInteger {
    func exMem() -> Int64 {
        switch self {
        case .int(let n):
            if n == 0 { return 1 }
            return Int64((abs(n).bitWidth - 1) / 64 + 1)
        case .bigUInt(let n):
            if n == 0 { return 1 }
            return Int64((n.bitWidth - 1) / 64 + 1)
        case .bigNInt(let n):
            if n == 0 { return 1 }
            return Int64((n.magnitude.bitWidth - 1) / 64 + 1)
        }
    }
}
