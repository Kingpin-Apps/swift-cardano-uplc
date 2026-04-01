import BigInt
import Foundation
import OrderedCollections
import SwiftCardanoCore

/// Errors thrown during UPLC text parsing.
public enum UPLCParseError: Error, Sendable {
    case unexpectedEnd
    case unexpectedToken(String)
    case unknownBuiltin(String)
    case invalidVersion(String)
    case invalidConstant(String)
    case invalidInteger(String)
}

/// Parses textual UPLC format into a `NamedProgram`.
///
/// Supports all term forms:
/// ```
/// (program 1.0.0 <term>)
/// ```
public struct UPLCParser: Sendable {
    private var uniqueCounter: Int = 0

    public init() {}

    /// Parse textual UPLC source into a named program.
    public mutating func parse(_ source: String) throws -> NamedProgram {
        var tokens = tokenize(source)
        return try parseProgram(&tokens)
    }

    // MARK: — Tokenizer

    private func tokenize(_ source: String) -> [String] {
        var tokens = [String]()
        var current = ""
        var inLineComment = false
        var inString = false
        for ch in source {
            // Handle line comments (-- to end of line)
            if inLineComment {
                if ch == "\n" { inLineComment = false }
                continue
            }
            // Handle quoted strings
            if inString {
                current.append(ch)
                if ch == "\"" {
                    inString = false
                    tokens.append(current)
                    current = ""
                }
                continue
            }
            if ch == "\"" {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                inString = true
                current.append(ch)
                continue
            }
            if ch == "-" && current == "-" {
                // Start of line comment; remove the first "-" we already accumulated
                current = ""
                inLineComment = true
                continue
            }
            if ch == "," {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                tokens.append(",")
            } else if ch == "(" || ch == ")" || ch == "[" || ch == "]" {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                if ch == "[" {
                    tokens.append("[")
                } else if ch == "]" {
                    tokens.append("]")
                } else {
                    tokens.append(String(ch))
                }
            } else if ch.isWhitespace || ch.isNewline {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    // MARK: — Top-level parser

    private mutating func parseProgram(_ tokens: inout [String]) throws -> NamedProgram {
        try consume("(", in: &tokens)
        try consumeKeyword("program", in: &tokens)
        let versionStr = try next(&tokens)
        let version = try parseVersion(versionStr)
        let term = try parseTerm(&tokens)
        try consume(")", in: &tokens)
        return NamedProgram(version: version, term: term)
    }

    private func parseVersion(_ s: String) throws -> (UInt, UInt, UInt) {
        let parts = s.split(separator: ".")
        guard parts.count == 3,
              let major = UInt(parts[0]),
              let minor = UInt(parts[1]),
              let patch = UInt(parts[2]) else {
            throw UPLCParseError.invalidVersion(s)
        }
        return (major, minor, patch)
    }

    // MARK: — Term parser

    private mutating func parseTerm(_ tokens: inout [String]) throws -> Term<Name> {
        guard let tok = tokens.first else { throw UPLCParseError.unexpectedEnd }

        if tok == "error" {
            tokens.removeFirst()
            return .error
        }

        // Application syntax: [f x ...] — left-associative currying
        if tok == "[" {
            tokens.removeFirst() // consume "["
            var result = try parseTerm(&tokens)
            while tokens.first != "]" {
                let arg = try parseTerm(&tokens)
                result = .apply(function: result, argument: arg)
            }
            try consume("]", in: &tokens)
            return result
        }

        if tok != "(" {
            // Bare identifier — treat as a variable reference
            tokens.removeFirst()
            return .var(makeName(tok))
        }

        tokens.removeFirst() // consume "("
        guard let keyword = tokens.first else { throw UPLCParseError.unexpectedEnd }

        switch keyword {
        case "lam":
            tokens.removeFirst()
            let paramStr = try next(&tokens)
            let param = makeName(paramStr)
            let body = try parseTerm(&tokens)
            try consume(")", in: &tokens)
            return .lambda(parameterName: param, body: body)

        case "delay":
            tokens.removeFirst()
            let body = try parseTerm(&tokens)
            try consume(")", in: &tokens)
            return .delay(body)

        case "force":
            tokens.removeFirst()
            let body = try parseTerm(&tokens)
            try consume(")", in: &tokens)
            return .force(body)

        case "error":
            tokens.removeFirst()
            try consume(")", in: &tokens)
            return .error

        case "con":
            tokens.removeFirst()
            let (type_, val) = try parseConstant(&tokens)
            _ = type_
            try consume(")", in: &tokens)
            return .constant(val)

        case "builtin":
            tokens.removeFirst()
            let name = try next(&tokens)
            guard let fn = builtinByName(name) else {
                throw UPLCParseError.unknownBuiltin(name)
            }
            try consume(")", in: &tokens)
            return .builtin(fn)

        case "constr":
            tokens.removeFirst()
            let tagStr = try next(&tokens)
            guard let tag = UInt64(tagStr) else { throw UPLCParseError.unexpectedToken(tagStr) }
            var fields = [Term<Name>]()
            while tokens.first != ")" {
                fields.append(try parseTerm(&tokens))
            }
            try consume(")", in: &tokens)
            return .constr(tag: tag, fields: fields)

        case "case":
            tokens.removeFirst()
            let arg = try parseTerm(&tokens)
            var branches = [Term<Name>]()
            while tokens.first != ")" {
                branches.append(try parseTerm(&tokens))
            }
            try consume(")", in: &tokens)
            return .case(argument: arg, branches: branches)

        default:
            // Application: (function argument)
            let f = try parseTerm(&tokens)
            let arg = try parseTerm(&tokens)
            try consume(")", in: &tokens)
            return .apply(function: f, argument: arg)
        }
    }

    // MARK: — Constant parser

    private mutating func parseConstant(_ tokens: inout [String]) throws -> (UPLCType, UPLCConstant) {
        // Type can be a simple keyword or a parenthesized compound type
        let type = try parseType(&tokens)
        let val = try parseConstantValue(type: type, tokens: &tokens)
        return (type, val)
    }

    // MARK: — Type parser

    private func parseType(_ tokens: inout [String]) throws -> UPLCType {
        guard let tok = tokens.first else { throw UPLCParseError.unexpectedEnd }

        if tok == "(" {
            // Compound type: (list T) or (pair T1 T2)
            tokens.removeFirst()
            let keyword = try next(&tokens)
            switch keyword {
            case "list":
                let elemType = try parseType(&tokens)
                try consume(")", in: &tokens)
                return .list(elemType)
            case "pair":
                let t1 = try parseType(&tokens)
                let t2 = try parseType(&tokens)
                try consume(")", in: &tokens)
                return .pair(t1, t2)
            default:
                throw UPLCParseError.invalidConstant(keyword)
            }
        }

        tokens.removeFirst()
        switch tok {
        case "integer":               return .integer
        case "bytestring":            return .byteString
        case "string":                return .string
        case "bool":                  return .bool
        case "unit":                  return .unit
        case "data":                  return .data
        case "bls12_381_G1_element":  return .bls12_381G1Element
        case "bls12_381_G2_element":  return .bls12_381G2Element
        case "bls12_381_mlresult":    return .bls12_381MlResult
        default:
            throw UPLCParseError.invalidConstant(tok)
        }
    }

    // MARK: — Constant value parser (given a known type)

    private mutating func parseConstantValue(type: UPLCType, tokens: inout [String]) throws -> UPLCConstant {
        switch type {
        case .integer:
            let valStr = try next(&tokens)
            guard let n = BigInt(valStr) else { throw UPLCParseError.invalidInteger(valStr) }
            return .integer(n)

        case .byteString:
            let hex = try next(&tokens)
            let cleaned = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
            return .byteString(Data(try hexToBytes(cleaned)))

        case .string:
            var s = try next(&tokens)
            // Strings must be quoted — reject bare tokens
            guard s.hasPrefix("\"") && s.hasSuffix("\"") && s.count >= 2 else {
                throw UPLCParseError.invalidConstant("string: expected quoted string, got \(s)")
            }
            s = String(s.dropFirst().dropLast())
            return .string(s)

        case .bool:
            let b = try next(&tokens)
            guard b == "True" || b == "False" || b == "true" || b == "false" else {
                throw UPLCParseError.invalidConstant("bool: expected True/False, got \(b)")
            }
            return .bool(b == "True" || b == "true")

        case .unit:
            // Consume optional "()" tokens: the tokenizer splits "()" into "(" ")" 
            if tokens.first == "(" {
                tokens.removeFirst()
                try consume(")", in: &tokens)
            }
            return .unit

        case .list(let elemType):
            // [v1, v2, ...] — commas are stripped by tokenizer since they're not delimiters;
            // the tokenizer keeps commas attached to tokens, so we filter them.
            try consume("[", in: &tokens)
            var items = [UPLCConstant]()
            while tokens.first != "]" {
                // Skip commas (may appear as standalone "," token or attached to a value)
                if tokens.first == "," { tokens.removeFirst(); continue }
                // Remove trailing comma from token if attached
                if var tok = tokens.first, tok.hasSuffix(",") {
                    tok.removeLast()
                    tokens[0] = tok
                }
                items.append(try parseConstantValue(type: elemType, tokens: &tokens))
            }
            try consume("]", in: &tokens)
            return .list(elemType, items)

        case .pair(let t1, let t2):
            // (v1, v2)
            try consume("(", in: &tokens)
            let v1 = try parseConstantValue(type: t1, tokens: &tokens)
            // Skip comma
            if tokens.first == "," { tokens.removeFirst() }
            if var tok = tokens.first, tok.hasSuffix(",") {
                tok.removeLast()
                tokens[0] = tok
            }
            let v2 = try parseConstantValue(type: t2, tokens: &tokens)
            try consume(")", in: &tokens)
            return .pair(t1, t2, v1, v2)

        case .data:
            return .data(try parsePlutusDataLiteral(&tokens))

        case .bls12_381G1Element:
            let hex = try next(&tokens)
            let cleaned = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) :
                          hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
            return .bls12_381G1Element(Data(try hexToBytes(cleaned)))

        case .bls12_381G2Element:
            let hex = try next(&tokens)
            let cleaned = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) :
                          hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
            return .bls12_381G2Element(Data(try hexToBytes(cleaned)))

        case .bls12_381MlResult:
            let hex = try next(&tokens)
            let cleaned = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) :
                          hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
            return .bls12_381MlResult(Data(try hexToBytes(cleaned)))
        }
    }

    // MARK: — PlutusData literal parser
    //
    // Formats: I n | B #hex | Constr tag [fields] | List [items] | Map [(k, v), ...]

    private mutating func parsePlutusDataLiteral(_ tokens: inout [String]) throws -> PlutusData {
        guard let tok = tokens.first else { throw UPLCParseError.unexpectedEnd }

        // Handle optional parenthesized form: (I 42), (B #hex), etc.
        if tok == "(" {
            tokens.removeFirst()
            let result = try parsePlutusDataLiteral(&tokens)
            try consume(")", in: &tokens)
            return result
        }

        switch tok {
        case "I":
            tokens.removeFirst()
            let valStr = try next(&tokens)
            guard let n = BigInt(valStr) else { throw UPLCParseError.invalidInteger(valStr) }
            return .bigInt(BigInteger(bigInt: n))

        case "B":
            tokens.removeFirst()
            let hex = try next(&tokens)
            // B requires a # prefix for hex data
            guard hex.hasPrefix("#") else {
                throw UPLCParseError.invalidConstant("data B: expected #hex, got \(hex)")
            }
            let cleaned = String(hex.dropFirst())
            return .bytes(try Bytes(from: Data(try hexToBytes(cleaned))))

        case "Constr":
            tokens.removeFirst()
            let tagStr = try next(&tokens)
            guard let rawTag = UInt64(tagStr) else { throw UPLCParseError.invalidInteger(tagStr) }
            // Convert from Plutus display tag to CBOR tag
            let cborTag: UInt64
            if rawTag <= 6 {
                cborTag = 121 + rawTag
            } else if rawTag >= 7 && rawTag <= 127 {
                cborTag = 1280 + (rawTag - 7)
            } else {
                cborTag = rawTag
            }
            // Parse fields: [field1, field2, ...]
            try consume("[", in: &tokens)
            var fields = [PlutusData]()
            while tokens.first != "]" {
                if tokens.first == "," { tokens.removeFirst(); continue }
                fields.append(try parsePlutusDataLiteral(&tokens))
            }
            try consume("]", in: &tokens)
            return .constructor(Constr(tag: cborTag, fields: fields))

        case "List":
            tokens.removeFirst()
            try consume("[", in: &tokens)
            var items = [PlutusData]()
            while tokens.first != "]" {
                if tokens.first == "," { tokens.removeFirst(); continue }
                items.append(try parsePlutusDataLiteral(&tokens))
            }
            try consume("]", in: &tokens)
            return .array(items)

        case "Map":
            tokens.removeFirst()
            try consume("[", in: &tokens)
            var dict = OrderedDictionary<PlutusData, PlutusData>()
            while tokens.first != "]" {
                if tokens.first == "," { tokens.removeFirst(); continue }
                // Each entry: (key, value)
                try consume("(", in: &tokens)
                let key = try parsePlutusDataLiteral(&tokens)
                if tokens.first == "," { tokens.removeFirst() }
                let value = try parsePlutusDataLiteral(&tokens)
                try consume(")", in: &tokens)
                dict[key] = value
            }
            try consume("]", in: &tokens)
            return .map(dict)

        default:
            throw UPLCParseError.invalidConstant("data literal: \(tok)")
        }
    }

    // MARK: — Helpers

    private mutating func makeName(_ text: String) -> Name {
        defer { uniqueCounter += 1 }
        return Name(text: text, unique: Unique(uniqueCounter))
    }

    private func next(_ tokens: inout [String]) throws -> String {
        guard !tokens.isEmpty else { throw UPLCParseError.unexpectedEnd }
        return tokens.removeFirst()
    }

    private func consume(_ expected: String, in tokens: inout [String]) throws {
        guard tokens.first == expected else {
            throw UPLCParseError.unexpectedToken(tokens.first ?? "<end>")
        }
        tokens.removeFirst()
    }

    private func consumeKeyword(_ kw: String, in tokens: inout [String]) throws {
        guard tokens.first == kw else {
            throw UPLCParseError.unexpectedToken(tokens.first ?? "<end>")
        }
        tokens.removeFirst()
    }

    private func hexToBytes(_ hex: String) throws -> [UInt8] {
        guard hex.count % 2 == 0 else { throw UPLCParseError.invalidConstant(hex) }
        var bytes = [UInt8]()
        var idx = hex.startIndex
        while idx < hex.endIndex {
            let next = hex.index(idx, offsetBy: 2)
            guard let byte = UInt8(hex[idx..<next], radix: 16) else {
                throw UPLCParseError.invalidConstant(hex)
            }
            bytes.append(byte)
            idx = next
        }
        return bytes
    }
}

// MARK: — Builtin name → DefaultFunction

private func builtinByName(_ name: String) -> DefaultFunction? {
    switch name {
    case "addInteger":                    return .addInteger
    case "subtractInteger":               return .subtractInteger
    case "multiplyInteger":               return .multiplyInteger
    case "divideInteger":                 return .divideInteger
    case "quotientInteger":               return .quotientInteger
    case "remainderInteger":              return .remainderInteger
    case "modInteger":                    return .modInteger
    case "equalsInteger":                 return .equalsInteger
    case "lessThanInteger":               return .lessThanInteger
    case "lessThanEqualsInteger":         return .lessThanEqualsInteger
    case "appendByteString":              return .appendByteString
    case "consByteString":                return .consByteString
    case "sliceByteString":               return .sliceByteString
    case "lengthOfByteString":            return .lengthOfByteString
    case "indexByteString":               return .indexByteString
    case "equalsByteString":              return .equalsByteString
    case "lessThanByteString":            return .lessThanByteString
    case "lessThanEqualsByteString":      return .lessThanEqualsByteString
    case "sha2_256":                      return .sha2_256
    case "sha3_256":                      return .sha3_256
    case "blake2b_256":                   return .blake2b_256
    case "blake2b_224":                   return .blake2b_224
    case "keccak_256":                    return .keccak_256
    case "verifyEd25519Signature":        return .verifyEd25519Signature
    case "verifyEcdsaSecp256k1Signature": return .verifyEcdsaSecp256k1Signature
    case "verifySchnorrSecp256k1Signature": return .verifySchnorrSecp256k1Signature
    case "appendString":                  return .appendString
    case "equalsString":                  return .equalsString
    case "encodeUtf8":                    return .encodeUtf8
    case "decodeUtf8":                    return .decodeUtf8
    case "ifThenElse":                    return .ifThenElse
    case "chooseUnit":                    return .chooseUnit
    case "trace":                         return .trace
    case "fstPair":                       return .fstPair
    case "sndPair":                       return .sndPair
    case "chooseList":                    return .chooseList
    case "mkCons":                        return .mkCons
    case "headList":                      return .headList
    case "tailList":                      return .tailList
    case "nullList":                      return .nullList
    case "chooseData":                    return .chooseData
    case "constrData":                    return .constrData
    case "mapData":                       return .mapData
    case "listData":                      return .listData
    case "iData":                         return .iData
    case "bData":                         return .bData
    case "unConstrData":                  return .unConstrData
    case "unMapData":                     return .unMapData
    case "unListData":                    return .unListData
    case "unIData":                       return .unIData
    case "unBData":                       return .unBData
    case "equalsData":                    return .equalsData
    case "serialiseData":                 return .serialiseData
    case "mkPairData":                    return .mkPairData
    case "mkNilData":                     return .mkNilData
    case "mkNilPairData":                 return .mkNilPairData
    case "integerToByteString":           return .integerToByteString
    case "byteStringToInteger":           return .byteStringToInteger
    case "andByteString":                 return .andByteString
    case "orByteString":                  return .orByteString
    case "xorByteString":                 return .xorByteString
    case "complementByteString":          return .complementByteString
    case "readBit":                       return .readBit
    case "writeBits":                     return .writeBits
    case "replicateByte":                 return .replicateByte
    case "shiftByteString":               return .shiftByteString
    case "rotateByteString":              return .rotateByteString
    case "countSetBits":                  return .countSetBits
    case "findFirstSetBit":               return .findFirstSetBit
    case "ripemd_160":                    return .ripemd_160
    default: return nil
    }
}
