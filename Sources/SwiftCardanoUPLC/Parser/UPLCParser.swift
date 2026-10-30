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
        var tokens = Tokens(tokenize(source))
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

    private mutating func parseProgram(_ tokens: inout Tokens) throws -> NamedProgram {
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

    /// Parses one term with an explicit frame stack rather than recursion, so
    /// deeply nested programs cannot overflow the call stack. Tokens are
    /// consumed, names created, and errors thrown in exactly the order a
    /// recursive descent would.
    private mutating func parseTerm(_ tokens: inout Tokens) throws -> Term<Name> {
        var frames: [ParseFrame] = []
        while true {
            var term: Term<Name>
            parse: do {
                guard let tok = tokens.first else { throw UPLCParseError.unexpectedEnd }

                if tok == "error" {
                    tokens.removeFirst()
                    term = .error
                    break parse
                }

                // Application syntax: [f x ...] — left-associative currying
                if tok == "[" {
                    tokens.removeFirst() // consume "["
                    frames.append(.bracket(applied: nil))
                    continue
                }

                if tok != "(" {
                    // Bare identifier — treat as a variable reference
                    tokens.removeFirst()
                    term = .var(makeName(tok))
                    break parse
                }

                tokens.removeFirst() // consume "("
                guard let keyword = tokens.first else { throw UPLCParseError.unexpectedEnd }

                switch keyword {
                case "lam":
                    tokens.removeFirst()
                    let paramStr = try next(&tokens)
                    frames.append(.lambda(parameterName: makeName(paramStr)))
                    continue

                case "delay":
                    tokens.removeFirst()
                    frames.append(.delay)
                    continue

                case "force":
                    tokens.removeFirst()
                    frames.append(.force)
                    continue

                case "error":
                    tokens.removeFirst()
                    try consume(")", in: &tokens)
                    term = .error

                case "con":
                    tokens.removeFirst()
                    let (type_, val) = try parseConstant(&tokens)
                    _ = type_
                    try consume(")", in: &tokens)
                    term = .constant(val)

                case "builtin":
                    tokens.removeFirst()
                    let name = try next(&tokens)
                    guard let fn = builtinByName(name) else {
                        throw UPLCParseError.unknownBuiltin(name)
                    }
                    try consume(")", in: &tokens)
                    term = .builtin(fn)

                case "constr":
                    tokens.removeFirst()
                    let tagStr = try next(&tokens)
                    guard let tag = UInt64(tagStr) else { throw UPLCParseError.unexpectedToken(tagStr) }
                    if tokens.first != ")" {
                        frames.append(.constr(tag: tag, fields: []))
                        continue
                    }
                    try consume(")", in: &tokens)
                    term = .constr(tag: tag, fields: [])

                case "case":
                    tokens.removeFirst()
                    frames.append(.caseArgument)
                    continue

                default:
                    // Application: (function argument)
                    frames.append(.applyFunction)
                    continue
                }
            }

            // `term` is complete: fold it into its parents until one needs another child.
            reduce: while true {
                guard let frame = frames.popLast() else { return term }
                switch frame {
                case .bracket(let applied):
                    let result = applied.map { .apply(function: $0, argument: term) } ?? term
                    if tokens.first != "]" {
                        frames.append(.bracket(applied: result))
                        break reduce
                    }
                    try consume("]", in: &tokens)
                    term = result
                case .lambda(let param):
                    try consume(")", in: &tokens)
                    term = .lambda(parameterName: param, body: term)
                case .delay:
                    try consume(")", in: &tokens)
                    term = .delay(term)
                case .force:
                    try consume(")", in: &tokens)
                    term = .force(term)
                case .constr(let tag, var fields):
                    fields.append(term)
                    if tokens.first != ")" {
                        frames.append(.constr(tag: tag, fields: fields))
                        break reduce
                    }
                    try consume(")", in: &tokens)
                    term = .constr(tag: tag, fields: fields)
                case .caseArgument:
                    if tokens.first != ")" {
                        frames.append(.caseBranches(argument: term, branches: []))
                        break reduce
                    }
                    try consume(")", in: &tokens)
                    term = .case(argument: term, branches: [])
                case .caseBranches(let argument, var branches):
                    branches.append(term)
                    if tokens.first != ")" {
                        frames.append(.caseBranches(argument: argument, branches: branches))
                        break reduce
                    }
                    try consume(")", in: &tokens)
                    term = .case(argument: argument, branches: branches)
                case .applyFunction:
                    frames.append(.applyArgument(function: term))
                    break reduce
                case .applyArgument(let function):
                    try consume(")", in: &tokens)
                    term = .apply(function: function, argument: term)
                }
            }
        }
    }

    // MARK: — Constant parser

    private mutating func parseConstant(_ tokens: inout Tokens) throws -> (UPLCType, UPLCConstant) {
        // Type can be a simple keyword or a parenthesized compound type
        let type = try parseType(&tokens)
        let val = try parseConstantValue(type: type, tokens: &tokens)
        return (type, val)
    }

    // MARK: — Type parser

    private func parseType(_ tokens: inout Tokens) throws -> UPLCType {
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

    private mutating func parseConstantValue(type: UPLCType, tokens: inout Tokens) throws -> UPLCConstant {
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
                    tokens.replaceFirst(with: tok)
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
                tokens.replaceFirst(with: tok)
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

    /// Parses one PlutusData literal with an explicit frame stack rather than
    /// recursion, consuming tokens and throwing errors in the same order a
    /// recursive descent would.
    private mutating func parsePlutusDataLiteral(_ tokens: inout Tokens) throws -> PlutusData {
        var frames: [DataFrame] = []
        while true {
            var data: PlutusData
            parse: do {
                guard let tok = tokens.first else { throw UPLCParseError.unexpectedEnd }

                // Handle optional parenthesized form: (I 42), (B #hex), etc.
                if tok == "(" {
                    tokens.removeFirst()
                    frames.append(.parenthesized)
                    continue
                }

                switch tok {
                case "I":
                    tokens.removeFirst()
                    let valStr = try next(&tokens)
                    guard let n = BigInt(valStr) else { throw UPLCParseError.invalidInteger(valStr) }
                    data = .bigInt(BigInteger(bigInt: n))

                case "B":
                    tokens.removeFirst()
                    let hex = try next(&tokens)
                    // B requires a # prefix for hex data
                    guard hex.hasPrefix("#") else {
                        throw UPLCParseError.invalidConstant("data B: expected #hex, got \(hex)")
                    }
                    let cleaned = String(hex.dropFirst())
                    data = .bytes(try Bytes(from: Data(try hexToBytes(cleaned))))

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
                    if try beginItem(&tokens) {
                        frames.append(.constr(tag: cborTag, fields: []))
                        continue
                    }
                    data = .constructor(Constr(tag: cborTag, fields: []))

                case "List":
                    tokens.removeFirst()
                    try consume("[", in: &tokens)
                    if try beginItem(&tokens) {
                        frames.append(.list(items: []))
                        continue
                    }
                    data = .array([])

                case "Map":
                    tokens.removeFirst()
                    try consume("[", in: &tokens)
                    if try beginMapEntry(&tokens) {
                        frames.append(.mapKey(entries: [:]))
                        continue
                    }
                    data = .map([:])

                default:
                    throw UPLCParseError.invalidConstant("data literal: \(tok)")
                }
            }

            // `data` is complete: fold it into its parents until one needs another child.
            reduce: while true {
                guard let frame = frames.popLast() else { return data }
                switch frame {
                case .parenthesized:
                    try consume(")", in: &tokens)
                case .constr(let tag, var fields):
                    fields.append(data)
                    if try beginItem(&tokens) {
                        frames.append(.constr(tag: tag, fields: fields))
                        break reduce
                    }
                    data = .constructor(Constr(tag: tag, fields: fields))
                case .list(var items):
                    items.append(data)
                    if try beginItem(&tokens) {
                        frames.append(.list(items: items))
                        break reduce
                    }
                    data = .array(items)
                case .mapKey(let entries):
                    if tokens.first == "," { tokens.removeFirst() }
                    frames.append(.mapValue(entries: entries, key: data))
                    break reduce
                case .mapValue(var entries, let key):
                    try consume(")", in: &tokens)
                    // Every pair, in order: a Plutus map may repeat a key.
                    entries.append(key: key, value: data)
                    if try beginMapEntry(&tokens) {
                        frames.append(.mapKey(entries: entries))
                        break reduce
                    }
                    data = .map(entries)
                }
            }
        }
    }

    /// Skip separating commas in a `[...]` data list. Returns true when another
    /// item follows; otherwise consumes the closing `]` and returns false.
    private func beginItem(_ tokens: inout Tokens) throws -> Bool {
        while tokens.first == "," { tokens.removeFirst() }
        if tokens.first != "]" { return true }
        try consume("]", in: &tokens)
        return false
    }

    /// Like ``beginItem(_:)`` for a `Map [...]`, also consuming the `(` that
    /// opens the next `(key, value)` entry.
    private func beginMapEntry(_ tokens: inout Tokens) throws -> Bool {
        guard try beginItem(&tokens) else { return false }
        try consume("(", in: &tokens)
        return true
    }

    // MARK: — Helpers

    private mutating func makeName(_ text: String) -> Name {
        defer { uniqueCounter += 1 }
        return Name(text: text, unique: Unique(uniqueCounter))
    }

    private func next(_ tokens: inout Tokens) throws -> String {
        guard !tokens.isEmpty else { throw UPLCParseError.unexpectedEnd }
        return tokens.removeFirst()
    }

    private func consume(_ expected: String, in tokens: inout Tokens) throws {
        guard tokens.first == expected else {
            throw UPLCParseError.unexpectedToken(tokens.first ?? "<end>")
        }
        tokens.removeFirst()
    }

    private func consumeKeyword(_ kw: String, in tokens: inout Tokens) throws {
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

// MARK: — Token stream

/// The token list with a read position, so consuming a token is O(1) instead
/// of shifting the whole array as `Array.removeFirst()` does.
private struct Tokens {
    private var storage: [String]
    private var position = 0

    init(_ tokens: [String]) { storage = tokens }

    var first: String? { position < storage.count ? storage[position] : nil }
    var isEmpty: Bool { position >= storage.count }

    @discardableResult
    mutating func removeFirst() -> String {
        precondition(position < storage.count, "no tokens left")
        defer { position += 1 }
        return storage[position]
    }

    /// Replace the next token in place.
    mutating func replaceFirst(with token: String) {
        storage[position] = token
    }
}

// MARK: — Parse frames

/// A term whose remaining children are still being parsed.
private enum ParseFrame {
    /// `[f x ...]`; `applied` is nil until the first term is parsed.
    case bracket(applied: Term<Name>?)
    case lambda(parameterName: Name)
    case delay
    case force
    case constr(tag: UInt64, fields: [Term<Name>])
    case caseArgument
    case caseBranches(argument: Term<Name>, branches: [Term<Name>])
    /// `(f x)`
    case applyFunction
    case applyArgument(function: Term<Name>)
}

/// A PlutusData literal whose remaining children are still being parsed.
private enum DataFrame {
    case parenthesized
    case constr(tag: UInt64, fields: [PlutusData])
    case list(items: [PlutusData])
    case mapKey(entries: MapPairs<PlutusData, PlutusData>)
    case mapValue(entries: MapPairs<PlutusData, PlutusData>, key: PlutusData)
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
