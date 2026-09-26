import BigInt
import Foundation
import SwiftCardanoCore

/// Decodes flat-encoded bytes into a `NamedDeBruijnProgram`.
public struct FlatDecoder: Sendable {
    public init() {}

    /// Decode flat bytes into a NamedDeBruijn program.
    public func decode(_ data: Data) throws -> NamedDeBruijnProgram {
        var r = BitReader(data: data)
        let major = try readUInt(&r)
        let minor = try readUInt(&r)
        let patch = try readUInt(&r)
        let term = try decodeTerm(&r)
        try r.consumeEndPadding()
        return NamedDeBruijnProgram(version: (major, minor, patch), term: term)
    }

    /// Decode from a hex string.
    public func decodeHex(_ hex: String) throws -> NamedDeBruijnProgram {
        let cleaned = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
        guard cleaned.count % 2 == 0 else { throw FlatDecodingError.unexpectedEnd }
        var bytes = [UInt8]()
        var idx = cleaned.startIndex
        while idx < cleaned.endIndex {
            let next = cleaned.index(idx, offsetBy: 2)
            guard let byte = UInt8(cleaned[idx..<next], radix: 16) else {
                throw FlatDecodingError.unexpectedEnd
            }
            bytes.append(byte)
            idx = next
        }
        return try decode(Data(bytes))
    }
}

// MARK: — Internal decoding helpers

/// A term whose remaining children are still being decoded.
private enum DecodeFrame {
    case delay
    case lambda
    case force
    case applyFunction
    case applyArgument(function: Term<NamedDeBruijn>)
    case constr(tag: UInt64, fields: [Term<NamedDeBruijn>])
    case caseArgument
    case caseBranches(argument: Term<NamedDeBruijn>, branches: [Term<NamedDeBruijn>])
}

/// Decodes one term with an explicit frame stack rather than recursion, so
/// deeply nested programs cannot overflow the call stack. Bits are read in
/// exactly the same order as a recursive pre-order decode.
private func decodeTerm(_ r: inout BitReader) throws -> Term<NamedDeBruijn> {
    var frames: [DecodeFrame] = []
    while true {
        var term: Term<NamedDeBruijn>
        let tag = try r.readBits(count: 4)
        switch tag {
        case 0: // Var
            let idx = try readUInt(&r)
            term = .var(NamedDeBruijn(text: "i", index: DeBruijn(UInt(idx))))
        case 1: // Delay
            frames.append(.delay)
            continue
        case 2: // Lambda
            frames.append(.lambda)
            continue
        case 3: // Apply
            frames.append(.applyFunction)
            continue
        case 4: // Constant
            term = .constant(try decodeConstant(&r))
        case 5: // Force
            frames.append(.force)
            continue
        case 6: // Error
            term = .error
        case 7: // Builtin
            let rawTag = try r.readBits(count: 7)
            guard let fn = DefaultFunction(rawValue: UInt8(rawTag)) else {
                throw FlatDecodingError.invalidBuiltinTag(rawTag)
            }
            term = .builtin(fn)
        case 8: // Constr
            let constrTag = UInt64(try readUInt(&r))
            guard try r.readBit() else {
                term = .constr(tag: constrTag, fields: [])
                break
            }
            frames.append(.constr(tag: constrTag, fields: []))
            continue
        case 9: // Case
            frames.append(.caseArgument)
            continue
        default:
            throw FlatDecodingError.invalidTag(tag)
        }

        // `term` is complete: fold it into its parents until one needs another child.
        reduce: while true {
            guard let frame = frames.popLast() else { return term }
            switch frame {
            case .delay:
                term = .delay(term)
            case .lambda:
                // Binder decodes as DeBruijn(0) — synthetic name
                term = .lambda(parameterName: NamedDeBruijn(text: "i", index: DeBruijn(0)), body: term)
            case .force:
                term = .force(term)
            case .applyFunction:
                frames.append(.applyArgument(function: term))
                break reduce
            case .applyArgument(let function):
                term = .apply(function: function, argument: term)
            case .constr(let tag, var fields):
                fields.append(term)
                if try r.readBit() {
                    frames.append(.constr(tag: tag, fields: fields))
                    break reduce
                }
                term = .constr(tag: tag, fields: fields)
            case .caseArgument:
                if try r.readBit() {
                    frames.append(.caseBranches(argument: term, branches: []))
                    break reduce
                }
                term = .case(argument: term, branches: [])
            case .caseBranches(let argument, var branches):
                branches.append(term)
                if try r.readBit() {
                    frames.append(.caseBranches(argument: argument, branches: branches))
                    break reduce
                }
                term = .case(argument: argument, branches: branches)
            }
        }
    }
}

private func decodeConstant(_ r: inout BitReader) throws -> UPLCConstant {
    let type_ = try decodeConstantType(&r)
    return try decodeConstantValue(&r, type_)
}

/// Read the flat type-tag list (each element preceded by a `1` bit, terminated by `0`).
private func decodeConstantType(_ r: inout BitReader) throws -> UPLCType {
    var tags = [UInt64]()
    while try r.readBit() {
        tags.append(try r.readBits(count: 4))
    }
    return try parseTypeTagSequence(tags[...])
}

private func parseTypeTagSequence(_ tags: ArraySlice<UInt64>) throws -> UPLCType {
    guard let first = tags.first else { throw FlatDecodingError.invalidConstantType(0) }
    switch first {
    case 0: return .integer
    case 1: return .byteString
    case 2: return .string
    case 3: return .unit
    case 4: return .bool
    case 7:
        guard tags.count >= 2 else { throw FlatDecodingError.invalidConstantType(7) }
        let second = tags[tags.index(after: tags.startIndex)]
        if second == 5 {
            let inner = try parseTypeTagSequence(tags.dropFirst(2))
            return .list(inner)
        } else if second == 7 {
            guard tags.count >= 3, tags[tags.index(tags.startIndex, offsetBy: 2)] == 6 else {
                throw FlatDecodingError.invalidConstantType(7)
            }
            // Split remaining tags into two type sequences (each terminated by their own structure)
            let rest = tags.dropFirst(3)
            let (t1, remainder) = try splitType(rest)
            let t2 = try parseTypeTagSequence(remainder)
            return .pair(t1, t2)
        } else {
            throw FlatDecodingError.invalidConstantType(second)
        }
    case 8:  return .data
    case 9:  return .bls12_381G1Element
    case 10: return .bls12_381G2Element
    case 11: return .bls12_381MlResult
    default: throw FlatDecodingError.invalidConstantType(first)
    }
}

/// Split a flat type tag sequence into the first complete type and the remainder.
private func splitType(_ tags: ArraySlice<UInt64>) throws -> (UPLCType, ArraySlice<UInt64>) {
    guard let first = tags.first else { throw FlatDecodingError.invalidConstantType(0) }
    switch first {
    case 0: return (.integer,            tags.dropFirst())
    case 1: return (.byteString,         tags.dropFirst())
    case 2: return (.string,             tags.dropFirst())
    case 3: return (.unit,               tags.dropFirst())
    case 4: return (.bool,               tags.dropFirst())
    case 7:
        guard tags.count >= 2 else { throw FlatDecodingError.invalidConstantType(7) }
        let second = tags[tags.index(after: tags.startIndex)]
        if second == 5 {
            let (inner, rest) = try splitType(tags.dropFirst(2))
            return (.list(inner), rest)
        } else if second == 7 {
            guard tags.count >= 3 else { throw FlatDecodingError.invalidConstantType(7) }
            let (t1, rest1) = try splitType(tags.dropFirst(3))
            let (t2, rest2) = try splitType(rest1)
            return (.pair(t1, t2), rest2)
        } else {
            throw FlatDecodingError.invalidConstantType(second)
        }
    case 8:  return (.data,                tags.dropFirst())
    case 9:  return (.bls12_381G1Element,  tags.dropFirst())
    case 10: return (.bls12_381G2Element,  tags.dropFirst())
    case 11: return (.bls12_381MlResult,   tags.dropFirst())
    default: throw FlatDecodingError.invalidConstantType(first)
    }
}

private func decodeConstantValue(_ r: inout BitReader, _ type_: UPLCType) throws -> UPLCConstant {
    switch type_ {
    case .integer:
        return .integer(try readBigInt(&r))
    case .byteString:
        return .byteString(Data(try readByteString(&r)))
    case .string:
        let bytes = try readByteString(&r)
        guard let s = String(bytes: bytes, encoding: .utf8) else {
            throw FlatDecodingError.invalidUTF8
        }
        return .string(s)
    case .unit:
        return .unit
    case .bool:
        return .bool(try r.readBit())
    case .list(let elemType):
        var items = [UPLCConstant]()
        while try r.readBit() {
            items.append(try decodeConstantValue(&r, elemType))
        }
        return .list(elemType, items)
    case .pair(let t1, let t2):
        let a = try decodeConstantValue(&r, t1)
        let b = try decodeConstantValue(&r, t2)
        return .pair(t1, t2, a, b)
    case .data:
        let bytes = try readByteString(&r)
        let pd = try PlutusData.fromCBOR(data: Data(bytes))
        return .data(pd)
    case .bls12_381G1Element:
        return .bls12_381G1Element(Data(try r.readBytes(count: 48)))
    case .bls12_381G2Element:
        return .bls12_381G2Element(Data(try r.readBytes(count: 96)))
    case .bls12_381MlResult:
        return .bls12_381MlResult(Data(try r.readBytes(count: 576)))
    }
}

// MARK: — Flat integer decoding

private func readUInt(_ r: inout BitReader) throws -> UInt {
    var result: UInt64 = 0
    var shift = 0
    repeat {
        let more = try r.readBit()
        let chunk = try r.readBits(count: 7)
        result |= chunk << shift
        shift += 7
        if !more { break }
    } while true
    return UInt(result)
}

private func readBigInt(_ r: inout BitReader) throws -> BigInt {
    var result = BigUInt(0)
    var shift = 0
    repeat {
        let more = try r.readBit()
        let chunk = try r.readBits(count: 7)
        result |= BigUInt(chunk) << shift
        shift += 7
        if !more { break }
    } while true
    // Undo ZigZag: if LSB == 1 → negative, else positive
    if result & 1 == 1 {
        return BigInt(-(BigInt(result >> 1) + 1))
    } else {
        return BigInt(result >> 1)
    }
}

private func readByteString(_ r: inout BitReader) throws -> [UInt8] {
    try r.consumeFiller()   // skip filler padding before chunk data
    var result = [UInt8]()
    while true {
        let len = Int(try r.readBits(count: 8))
        if len == 0 { break }
        result.append(contentsOf: try r.readBytes(count: len))
    }
    return result
}
