@preconcurrency import BigInt
import Foundation
import SwiftCardanoCore

/// Plutus `Data` equality.
///
/// `PlutusData` carries representation detail that has no meaning on chain:
/// a byte string can be held as `.boundedBytes` or `.byteString`, an integer
/// as `.int`, `.bigUInt` or `.bigNInt`, a list as `.array` or
/// `.indefiniteArray`, and a constructor remembers whether its fields were
/// written with an indefinite-length encoding. Swift's synthesised `==`
/// compares all of that, so two values that encode to *byte-identical* CBOR
/// can compare unequal.
///
/// That difference is not hypothetical: a datum decoded from the chain and the
/// same value rebuilt by a script take different representations, and
/// `equalsData` on them returned `false` — which made correct validators
/// reject perfectly good transactions.
enum PlutusDataSemantics {

    /// Compare two `Data` values the way the ledger does: by structure and
    /// content, ignoring how each part happens to be represented.
    static func equal(_ lhs: PlutusData, _ rhs: PlutusData) -> Bool {
        switch (lhs, rhs) {
        case (.constructor(let a), .constructor(let b)):
            return a.tag == b.tag && equal(a.fields, b.fields)

        case (.map(let a), .map(let b)):
            // A `Data` map is a list of pairs, so order is part of the value.
            guard a.count == b.count else { return false }
            for (left, right) in zip(a, b) {
                guard equal(left.key, right.key), equal(left.value, right.value) else {
                    return false
                }
            }
            return true

        case (.bigInt(let a), .bigInt(let b)):
            return integer(a) == integer(b)

        case (.bytes(let a), .bytes(let b)):
            return a.data == b.data

        default:
            // Lists, in either representation.
            guard let a = items(lhs), let b = items(rhs) else { return false }
            return equal(a, b)
        }
    }

    private static func equal(_ lhs: [PlutusData], _ rhs: [PlutusData]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy { equal($0, $1) }
    }

    /// The elements of a `Data` list, whichever way it is held.
    private static func items(_ value: PlutusData) -> [PlutusData]? {
        switch value {
        case .array(let items):          return items
        case .indefiniteArray(let items): return items.getAll()
        default:                          return nil
        }
    }

    private static func integer(_ value: BigInteger) -> BigInt {
        switch value {
        case .int(let v):     return BigInt(v)
        case .bigUInt(let v): return BigInt(v)
        case .bigNInt(let v): return -v
        }
    }
}
