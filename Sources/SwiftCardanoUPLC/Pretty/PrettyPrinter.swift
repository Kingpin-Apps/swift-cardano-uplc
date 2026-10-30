import BigInt
import Foundation
import SwiftCardanoCore

/// Renders UPLC ASTs back to readable textual UPLC format.
public struct PrettyPrinter: Sendable {
    private let indentWidth: Int

    public init(indentWidth: Int = 2) {
        self.indentWidth = indentWidth
    }

    // MARK: — Programs

    public func print(_ program: NamedProgram) -> String {
        let v = program.version
        return "(program \(v.0).\(v.1).\(v.2)\n\(printTerm(program.term, indent: 1)))"
    }

    public func print(_ program: NamedDeBruijnProgram) -> String {
        let v = program.version
        return "(program \(v.0).\(v.1).\(v.2)\n\(printNamedDeBruijn(program.term, indent: 1)))"
    }

    // MARK: — Compact single-line printer (for conformance test comparison)

    /// Print a NamedDeBruijn program on a single line (Plutus reference format).
    public func printCompactProgram(_ program: NamedDeBruijnProgram) -> String {
        let v = program.version
        return "(program \(v.0).\(v.1).\(v.2) \(printCompact(program.term)))"
    }

    /// Print a NamedDeBruijn term on a single line.
    public func printCompact(_ term: Term<NamedDeBruijn>) -> String {
        var out = ""
        var work: [PrintItem<NamedDeBruijn>] = [.term(term, indent: 0)]
        while let item = work.popLast() {
            switch item {
            case .text(let text):
                out += text
            case .term(let term, _):
                switch term {
                case .var(let ndb):
                    out += "\(ndb.text)_\(ndb.index.index)"
                case .delay(let body):
                    out += "(delay "
                    work.append(.text(")"))
                    work.append(.term(body, indent: 0))
                case .lambda(let param, let body):
                    out += "(lam \(param.text)_\(param.index.index) "
                    work.append(.text(")"))
                    work.append(.term(body, indent: 0))
                case .apply(let f, let arg):
                    out += "[ "
                    work.append(.text(" ]"))
                    work.append(.term(arg, indent: 0))
                    work.append(.text(" "))
                    work.append(.term(f, indent: 0))
                case .constant(let c):
                    out += "(con \(printConstant(c)))"
                case .force(let body):
                    out += "(force "
                    work.append(.text(")"))
                    work.append(.term(body, indent: 0))
                case .error:
                    out += "(error)"
                case .builtin(let fn):
                    out += "(builtin \(builtinName(fn)))"
                case .constr(let tag, let fields):
                    if fields.isEmpty {
                        out += "(constr \(tag))"
                    } else {
                        out += "(constr \(tag) "
                        work.append(.text(")"))
                        work.appendSeparated(fields, separator: " ", indent: 0)
                    }
                case .case(let arg, let branches):
                    out += "(case "
                    work.append(.text(")"))
                    work.appendSeparated(branches, separator: " ", indent: 0)
                    work.append(.text(" "))
                    work.append(.term(arg, indent: 0))
                }
            }
        }
        return out
    }

    // MARK: — Named terms

    public func printTerm(_ term: Term<Name>, indent: Int = 0) -> String {
        printIndented(term, indent: indent) { $0.text }
    }

    // MARK: — NamedDeBruijn terms

    public func printNamedDeBruijn(_ term: Term<NamedDeBruijn>, indent: Int = 0) -> String {
        printIndented(term, indent: indent) { "\($0.text)_\($0.index.index)" }
    }

    /// Multi-line printer shared by both binder types. Walks the term with an
    /// explicit work stack so deeply nested programs cannot overflow the call
    /// stack (Swift-concurrency threads have small stacks).
    private func printIndented<T>(
        _ term: Term<T>,
        indent: Int,
        name: (T) -> String
    ) -> String {
        var out = ""
        var work: [PrintItem<T>] = [.term(term, indent: indent)]
        while let item = work.popLast() {
            switch item {
            case .text(let text):
                out += text
            case .term(let term, let indent):
                let pad = String(repeating: " ", count: indent * indentWidth)
                switch term {
                case .var(let v):
                    out += "\(pad)\(name(v))"
                case .delay(let body):
                    out += "\(pad)(delay\n"
                    work.append(.text("\n\(pad))"))
                    work.append(.term(body, indent: indent + 1))
                case .lambda(let param, let body):
                    out += "\(pad)(lam \(name(param))\n"
                    work.append(.text("\n\(pad))"))
                    work.append(.term(body, indent: indent + 1))
                case .apply(let f, let arg):
                    out += "\(pad)[\n"
                    work.append(.text("\n\(pad)]"))
                    work.append(.term(arg, indent: indent + 1))
                    work.append(.text("\n"))
                    work.append(.term(f, indent: indent + 1))
                case .constant(let c):
                    out += "\(pad)(con \(printConstant(c)))"
                case .force(let body):
                    out += "\(pad)(force\n"
                    work.append(.text("\n\(pad))"))
                    work.append(.term(body, indent: indent + 1))
                case .error:
                    out += "\(pad)error"
                case .builtin(let fn):
                    out += "\(pad)(builtin \(builtinName(fn)))"
                case .constr(let tag, let fields):
                    out += "\(pad)(constr \(tag)\n"
                    work.append(.text("\n\(pad))"))
                    work.appendSeparated(fields, separator: "\n", indent: indent + 1)
                case .case(let arg, let branches):
                    out += "\(pad)(case\n"
                    work.append(.text("\n\(pad))"))
                    work.appendSeparated(branches, separator: "\n", indent: indent + 1)
                    work.append(.text("\n"))
                    work.append(.term(arg, indent: indent + 1))
                }
            }
        }
        return out
    }

    // MARK: — Constants

    public func printConstant(_ c: UPLCConstant) -> String {
        switch c {
        case .integer(let n):    return "integer \(n)"
        case .byteString(let d): return "bytestring #\(d.map { String(format: "%02x", $0) }.joined())"
        case .string(let s):     return "string \"\(s)\""
        case .unit:              return "unit ()"
        case .bool(let b):       return "bool \(b ? "True" : "False")"
        case .list(let t, let items):
            return "(list \(printType(t))) [\(items.map { printConstant($0) }.joined(separator: ", "))]"
        case .pair(let t1, let t2, let a, let b):
            return "(pair \(printType(t1)) \(printType(t2))) (\(printConstant(a)), \(printConstant(b)))"
        case .data(let pd):
            return "data (\(printPlutusData(pd)))"
        case .bls12_381G1Element(let d):
            return "bls12_381_G1_element 0x\(d.map { String(format: "%02x", $0) }.joined())"
        case .bls12_381G2Element(let d):
            return "bls12_381_G2_element 0x\(d.map { String(format: "%02x", $0) }.joined())"
        case .bls12_381MlResult(let d):
            return "bls12_381_mlresult 0x\(d.map { String(format: "%02x", $0) }.joined())"
        }
    }

    // MARK: — PlutusData pretty-printing

    public func printPlutusData(_ pd: PlutusData) -> String {
        var out = ""
        var work: [DataItem] = [.data(pd)]
        while let item = work.popLast() {
            switch item {
            case .text(let text):
                out += text
            case .data(let pd):
                switch pd {
                case .constructor(let c):
                    let tag = c.tag ?? 0
                    // Convert CBOR tag back to Plutus display tag
                    let displayTag: UInt64
                    if tag >= 121 && tag <= 127 {
                        displayTag = tag - 121
                    } else if tag >= 1280 && tag <= 1400 {
                        displayTag = (tag - 1280) + 7
                    } else {
                        displayTag = tag
                    }
                    out += "Constr \(displayTag) ["
                    work.append(.text("]"))
                    work.appendSeparated(c.fields)
                case .map(let m), .indefiniteMap(let m):
                    out += "Map ["
                    work.append(.text("]"))
                    // Push entries in reverse so they pop in dictionary order.
                    for (i, entry) in m.reversed().enumerated() {
                        if i > 0 { work.append(.text(", ")) }
                        work.append(.text(")"))
                        work.append(.data(entry.value))
                        work.append(.text(", "))
                        work.append(.data(entry.key))
                        work.append(.text("("))
                    }
                case .array(let a):
                    out += "List ["
                    work.append(.text("]"))
                    work.appendSeparated(a.array)
                case .indefiniteArray(let a):
                    out += "List ["
                    work.append(.text("]"))
                    work.appendSeparated(a.map { $0 })
                case .bigInt(let n):
                    out += "I \(n.toBigInt())"
                case .bytes(let b):
                    out += "B #\(b.data.map { String(format: "%02x", $0) }.joined())"
                }
            }
        }
        return out
    }

    /// Print just the value portion of a constant (no type prefix) — used inside lists/pairs.
    public func printConstantValue(_ c: UPLCConstant) -> String {
        switch c {
        case .integer(let n):    return "\(n)"
        case .byteString(let d): return "#\(d.map { String(format: "%02x", $0) }.joined())"
        case .string(let s):     return "\"\(s)\""
        case .unit:              return "()"
        case .bool(let b):       return b ? "True" : "False"
        case .list( _, let items):
            return "[\(items.map { printConstantValue($0) }.joined(separator: ","))]"
        case .pair(_, _, let a, let b):
            return "(\(printConstantValue(a)), \(printConstantValue(b)))"
        case .data(let pd):
            return "(\(printPlutusData(pd)))"
        case .bls12_381G1Element(let d):
            return "0x\(d.map { String(format: "%02x", $0) }.joined())"
        case .bls12_381G2Element(let d):
            return "0x\(d.map { String(format: "%02x", $0) }.joined())"
        case .bls12_381MlResult(let d):
            return "0x\(d.map { String(format: "%02x", $0) }.joined())"
        }
    }

    public func printType(_ t: UPLCType) -> String {
        switch t {
        case .integer:            return "integer"
        case .byteString:         return "bytestring"
        case .string:             return "string"
        case .unit:               return "unit"
        case .bool:               return "bool"
        case .list(let inner):    return "(list \(printType(inner)))"
        case .pair(let a, let b): return "(pair \(printType(a)) \(printType(b)))"
        case .data:               return "data"
        case .bls12_381G1Element: return "bls12_381_G1_element"
        case .bls12_381G2Element: return "bls12_381_G2_element"
        case .bls12_381MlResult:  return "bls12_381_mlresult"
        }
    }
}

// MARK: — Work stacks

/// A pending unit of printer output: either literal text or a term still to print.
private enum PrintItem<T: Sendable & Hashable> {
    case text(String)
    case term(Term<T>, indent: Int)
}

private extension Array {
    /// Push `terms` so they pop (and print) in order, with `separator` between them.
    mutating func appendSeparated<T>(_ terms: [Term<T>], separator: String, indent: Int)
    where Element == PrintItem<T> {
        for (i, term) in terms.reversed().enumerated() {
            if i > 0 { append(.text(separator)) }
            append(.term(term, indent: indent))
        }
    }
}

/// A pending unit of PlutusData output.
private enum DataItem {
    case text(String)
    case data(PlutusData)
}

private extension Array where Element == DataItem {
    /// Push `items` so they pop (and print) in order, separated by `", "`.
    mutating func appendSeparated(_ items: [PlutusData]) {
        for (i, item) in items.reversed().enumerated() {
            if i > 0 { append(.text(", ")) }
            append(.data(item))
        }
    }
}

// MARK: — Builtin name table

private func builtinName(_ fn: DefaultFunction) -> String {
    switch fn {
    case .addInteger:                     return "addInteger"
    case .subtractInteger:                return "subtractInteger"
    case .multiplyInteger:                return "multiplyInteger"
    case .divideInteger:                  return "divideInteger"
    case .quotientInteger:                return "quotientInteger"
    case .remainderInteger:               return "remainderInteger"
    case .modInteger:                     return "modInteger"
    case .equalsInteger:                  return "equalsInteger"
    case .lessThanInteger:                return "lessThanInteger"
    case .lessThanEqualsInteger:          return "lessThanEqualsInteger"
    case .appendByteString:               return "appendByteString"
    case .consByteString:                 return "consByteString"
    case .sliceByteString:                return "sliceByteString"
    case .lengthOfByteString:             return "lengthOfByteString"
    case .indexByteString:                return "indexByteString"
    case .equalsByteString:               return "equalsByteString"
    case .lessThanByteString:             return "lessThanByteString"
    case .lessThanEqualsByteString:       return "lessThanEqualsByteString"
    case .sha2_256:                       return "sha2_256"
    case .sha3_256:                       return "sha3_256"
    case .blake2b_256:                    return "blake2b_256"
    case .blake2b_224:                    return "blake2b_224"
    case .keccak_256:                     return "keccak_256"
    case .verifyEd25519Signature:         return "verifyEd25519Signature"
    case .verifyEcdsaSecp256k1Signature:  return "verifyEcdsaSecp256k1Signature"
    case .verifySchnorrSecp256k1Signature: return "verifySchnorrSecp256k1Signature"
    case .appendString:                   return "appendString"
    case .equalsString:                   return "equalsString"
    case .encodeUtf8:                     return "encodeUtf8"
    case .decodeUtf8:                     return "decodeUtf8"
    case .ifThenElse:                     return "ifThenElse"
    case .chooseUnit:                     return "chooseUnit"
    case .trace:                          return "trace"
    case .fstPair:                        return "fstPair"
    case .sndPair:                        return "sndPair"
    case .chooseList:                     return "chooseList"
    case .mkCons:                         return "mkCons"
    case .headList:                       return "headList"
    case .tailList:                       return "tailList"
    case .nullList:                       return "nullList"
    case .chooseData:                     return "chooseData"
    case .constrData:                     return "constrData"
    case .mapData:                        return "mapData"
    case .listData:                       return "listData"
    case .iData:                          return "iData"
    case .bData:                          return "bData"
    case .unConstrData:                   return "unConstrData"
    case .unMapData:                      return "unMapData"
    case .unListData:                     return "unListData"
    case .unIData:                        return "unIData"
    case .unBData:                        return "unBData"
    case .equalsData:                     return "equalsData"
    case .serialiseData:                  return "serialiseData"
    case .mkPairData:                     return "mkPairData"
    case .mkNilData:                      return "mkNilData"
    case .mkNilPairData:                  return "mkNilPairData"
    case .integerToByteString:            return "integerToByteString"
    case .byteStringToInteger:            return "byteStringToInteger"
    case .andByteString:                  return "andByteString"
    case .orByteString:                   return "orByteString"
    case .xorByteString:                  return "xorByteString"
    case .complementByteString:           return "complementByteString"
    case .readBit:                        return "readBit"
    case .writeBits:                      return "writeBits"
    case .replicateByte:                  return "replicateByte"
    case .shiftByteString:                return "shiftByteString"
    case .rotateByteString:               return "rotateByteString"
    case .countSetBits:                   return "countSetBits"
    case .findFirstSetBit:                return "findFirstSetBit"
    case .ripemd_160:                     return "ripemd_160"
    case .bls12_381_G1_add:               return "bls12_381_G1_add"
    case .bls12_381_G1_neg:               return "bls12_381_G1_neg"
    case .bls12_381_G1_scalarMul:         return "bls12_381_G1_scalarMul"
    case .bls12_381_G1_equal:             return "bls12_381_G1_equal"
    case .bls12_381_G1_compress:          return "bls12_381_G1_compress"
    case .bls12_381_G1_uncompress:        return "bls12_381_G1_uncompress"
    case .bls12_381_G1_hashToGroup:       return "bls12_381_G1_hashToGroup"
    case .bls12_381_G2_add:               return "bls12_381_G2_add"
    case .bls12_381_G2_neg:               return "bls12_381_G2_neg"
    case .bls12_381_G2_scalarMul:         return "bls12_381_G2_scalarMul"
    case .bls12_381_G2_equal:             return "bls12_381_G2_equal"
    case .bls12_381_G2_compress:          return "bls12_381_G2_compress"
    case .bls12_381_G2_uncompress:        return "bls12_381_G2_uncompress"
    case .bls12_381_G2_hashToGroup:       return "bls12_381_G2_hashToGroup"
    case .bls12_381_millerLoop:           return "bls12_381_millerLoop"
    case .bls12_381_mulMlResult:          return "bls12_381_mulMlResult"
    case .bls12_381_finalVerify:          return "bls12_381_finalVerify"
    }
}
