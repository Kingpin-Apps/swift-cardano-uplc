@preconcurrency import BigInt
import Foundation
import SwiftCardanoCore
import OrderedCollections
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
@preconcurrency import SwiftNaCl
@preconcurrency import CryptoSwift
import SwiftBLST
import P256K
import libsecp256k1

/// Executes UPLC built-in functions.
public struct BuiltinRuntime: Sendable {
    /// Execute a built-in with fully-evaluated arguments.
    public static func apply(
        _ function: DefaultFunction,
        to args: [Value],
        costModel: CostModel,
        logs: inout [String]
    ) throws -> Value {
        switch function {

        // MARK: — Integer arithmetic
        case .addInteger:
            let (a, b) = try twoIntegers(args)
            return .con(.integer(a + b))
        case .subtractInteger:
            let (a, b) = try twoIntegers(args)
            return .con(.integer(a - b))
        case .multiplyInteger:
            let (a, b) = try twoIntegers(args)
            return .con(.integer(a * b))
        case .divideInteger:
            let (a, b) = try twoIntegers(args)
            guard b != 0 else { throw MachineError.evaluationFailure }
            return .con(.integer(euclideanDiv(a, b)))
        case .quotientInteger:
            let (a, b) = try twoIntegers(args)
            guard b != 0 else { throw MachineError.evaluationFailure }
            return .con(.integer(a / b))
        case .remainderInteger:
            let (a, b) = try twoIntegers(args)
            guard b != 0 else { throw MachineError.evaluationFailure }
            return .con(.integer(a % b))
        case .modInteger:
            let (a, b) = try twoIntegers(args)
            guard b != 0 else { throw MachineError.evaluationFailure }
            return .con(.integer(euclideanMod(a, b)))
        case .equalsInteger:
            let (a, b) = try twoIntegers(args)
            return .con(.bool(a == b))
        case .lessThanInteger:
            let (a, b) = try twoIntegers(args)
            return .con(.bool(a < b))
        case .lessThanEqualsInteger:
            let (a, b) = try twoIntegers(args)
            return .con(.bool(a <= b))

        // MARK: — ByteString
        case .appendByteString:
            let (a, b) = try twoByteStrings(args)
            return .con(.byteString(a + b))
        case .consByteString:
            let n = try integer(args[0])
            let bs = try byteString(args[1])
            guard n >= 0 && n <= 255 else { throw MachineError.evaluationFailure }
            return .con(.byteString(Data([UInt8(n)]) + bs))
        case .sliceByteString:
            let from  = try safeInt(try integer(args[0]))
            let count = try safeInt(try integer(args[1]))
            let bs    = try byteString(args[2])
            let start = max(0, min(from, bs.count))
            let end   = max(start, min(start + count, bs.count))
            return .con(.byteString(bs[start..<end]))
        case .lengthOfByteString:
            let bs = try byteString(args[0])
            return .con(.integer(BigInt(bs.count)))
        case .indexByteString:
            let bs  = try byteString(args[0])
            let idx = try safeInt(try integer(args[1]))
            guard idx >= 0 && idx < bs.count else { throw MachineError.evaluationFailure }
            return .con(.integer(BigInt(bs[bs.startIndex + idx])))
        case .equalsByteString:
            let (a, b) = try twoByteStrings(args)
            return .con(.bool(a == b))
        case .lessThanByteString:
            let (a, b) = try twoByteStrings(args)
            return .con(.bool(a.lexicographicallyPrecedes(b)))
        case .lessThanEqualsByteString:
            let (a, b) = try twoByteStrings(args)
            return .con(.bool(a == b || a.lexicographicallyPrecedes(b)))

        // MARK: — Crypto / hash
        case .sha2_256:
            let bs = try byteString(args[0])
            let digest = SHA256.hash(data: bs)
            return .con(.byteString(Data(digest)))
        case .sha3_256:
            let bs = try byteString(args[0])
            return .con(.byteString(try sha3_256(bs)))
        case .blake2b_256:
            let bs = try byteString(args[0])
            return .con(.byteString(try blake2b(bs, digestSize: 32)))
        case .blake2b_224:
            let bs = try byteString(args[0])
            return .con(.byteString(try blake2b(bs, digestSize: 28)))
        case .keccak_256:
            let bs = try byteString(args[0])
            return .con(.byteString(try keccak256(bs)))
        case .ripemd_160:
            let bs = try byteString(args[0])
            return .con(.byteString(try ripemd160(bs)))
        case .verifyEd25519Signature:
            let pubKey = try byteString(args[0])
            let msg    = try byteString(args[1])
            let sig    = try byteString(args[2])
            return .con(.bool(try verifyEd25519(pubKey: pubKey, msg: msg, sig: sig)))
        case .verifyEcdsaSecp256k1Signature:
            let pubKey  = try byteString(args[0])   // 33-byte compressed
            let msgHash = try byteString(args[1])   // 32-byte pre-hashed message
            let sig     = try byteString(args[2])   // 64-byte compact r||s
            return .con(.bool(try verifyEcdsaSecp256k1(pubKey: pubKey, msgHash: msgHash, sig: sig)))
        case .verifySchnorrSecp256k1Signature:
            let pubKey = try byteString(args[0])    // 32-byte x-only
            let msg    = try byteString(args[1])    // arbitrary-length message
            let sig    = try byteString(args[2])    // 64-byte BIP-340 signature
            return .con(.bool(try verifySchnorrSecp256k1(pubKey: pubKey, msg: msg, sig: sig)))

        // MARK: — String
        case .appendString:
            let (a, b) = try twoStrings(args)
            return .con(.string(a + b))
        case .equalsString:
            let (a, b) = try twoStrings(args)
            return .con(.bool(a == b))
        case .encodeUtf8:
            let s = try string(args[0])
            return .con(.byteString(Data(s.utf8)))
        case .decodeUtf8:
            let bs = try byteString(args[0])
            guard let s = String(data: bs, encoding: .utf8) else {
                throw MachineError.typeError("decodeUtf8: invalid UTF-8")
            }
            return .con(.string(s))

        // MARK: — Control
        case .ifThenElse:
            let cond  = try bool(args[0])
            return cond ? args[1] : args[2]
        case .chooseUnit:
            _ = try unit(args[0])
            return args[1]
        case .trace:
            let msg = try string(args[0])
            logs.append(msg)
            return args[1]

        // MARK: — Pairs
        case .fstPair:
            if case .con(.pair(_, _, let a, _)) = args[0] { return .con(a) }
            throw MachineError.typeError("fstPair: not a pair")
        case .sndPair:
            if case .con(.pair(_, _, _, let b)) = args[0] { return .con(b) }
            throw MachineError.typeError("sndPair: not a pair")

        // MARK: — Lists
        case .chooseList:
            if case .con(.list(_, let items)) = args[0] {
                return items.isEmpty ? args[1] : args[2]
            }
            throw MachineError.typeError("chooseList: not a list")
        case .mkCons:
            let head = try constant(args[0])
            if case .con(.list(let t, var items)) = args[1] {
                // Validate that the element type matches the list type
                let headMatchesType: Bool
                switch (t, head) {
                case (.integer, .integer): headMatchesType = true
                case (.byteString, .byteString): headMatchesType = true
                case (.string, .string): headMatchesType = true
                case (.bool, .bool): headMatchesType = true
                case (.unit, .unit): headMatchesType = true
                case (.data, .data): headMatchesType = true
                case (.list, .list): headMatchesType = true
                case (.pair, .pair): headMatchesType = true
                default: headMatchesType = false
                }
                guard headMatchesType else {
                    throw MachineError.typeError("mkCons: element type mismatch")
                }
                items.insert(head, at: 0)
                return .con(.list(t, items))
            }
            throw MachineError.typeError("mkCons: second arg not a list")
        case .headList:
            if case .con(.list(_, let items)) = args[0] {
                guard !items.isEmpty else { throw MachineError.evaluationFailure }
                return .con(items[0])
            }
            throw MachineError.typeError("headList: not a list")
        case .tailList:
            if case .con(.list(let t, let items)) = args[0] {
                guard !items.isEmpty else { throw MachineError.evaluationFailure }
                return .con(.list(t, Array(items.dropFirst())))
            }
            throw MachineError.typeError("tailList: not a list")
        case .nullList:
            if case .con(.list(_, let items)) = args[0] {
                return .con(.bool(items.isEmpty))
            }
            throw MachineError.typeError("nullList: not a list")

        // MARK: — Data
        case .chooseData:
            let pd = try plutusData(args[0])
            switch pd {
            case .constructor: return args[1]
            case .map:         return args[2]
            case .array, .indefiniteArray: return args[3]
            case .bigInt:      return args[4]
            case .bytes:       return args[5]
            }
        case .constrData:
            let tag    = try safeUInt64(try integer(args[0]))
            let fields = try listOfData(args[1])
            return .con(.data(.constructor(Constr(tag: tag, fields: fields))))
        case .mapData:
            let pairs = try listOfPairs(args[0])
            var dict = OrderedDictionary<PlutusData, PlutusData>()
            for (k, v) in pairs { dict[k] = v }
            return .con(.data(.map(dict)))
        case .listData:
            let items = try listOfData(args[0])
            return .con(.data(.array(items)))
        case .iData:
            let n = try integer(args[0])
            return .con(.data(.bigInt(BigInteger(bigInt: n))))
        case .bData:
            let bs = try byteString(args[0])
            return .con(.data(.bytes(try Bytes(from: bs))))
        case .unConstrData:
            let pd = try plutusData(args[0])
            guard case .constructor(let c) = pd else { throw MachineError.typeError("unConstrData") }
            let tag = UPLCConstant.integer(BigInt(c.tag ?? 0))
            let fields = UPLCConstant.list(.data, c.fields.map { .data($0) })
            return .con(.pair(.integer, .list(.data), tag, fields))
        case .unMapData:
            let pd = try plutusData(args[0])
            guard case .map(let m) = pd else { throw MachineError.typeError("unMapData") }
            let pairs: [UPLCConstant] = m.map { .pair(.data, .data, .data($0.key), .data($0.value)) }
            return .con(.list(.pair(.data, .data), pairs))
        case .unListData:
            let pd = try plutusData(args[0])
            switch pd {
            case .array(let a):
                return .con(.list(.data, a.map { .data($0) }))
            case .indefiniteArray(let a):
                return .con(.list(.data, Array(a).map { .data($0) }))
            default:
                throw MachineError.typeError("unListData")
            }
        case .unIData:
            let pd = try plutusData(args[0])
            guard case .bigInt(let n) = pd else { throw MachineError.typeError("unIData") }
            return .con(.integer(n.toBigInt()))
        case .unBData:
            let pd = try plutusData(args[0])
            guard case .bytes(let b) = pd else { throw MachineError.typeError("unBData") }
            return .con(.byteString(b.data))
        case .equalsData:
            let a = try plutusData(args[0])
            let b = try plutusData(args[1])
            return .con(.bool(PlutusDataSemantics.equal(a, b)))
        case .serialiseData:
            let pd = try plutusData(args[0])
            let cborBytes = try pd.toCBORData()
            return .con(.byteString(Data(cborBytes)))
        case .mkPairData:
            let a = try plutusData(args[0])
            let b = try plutusData(args[1])
            return .con(.pair(.data, .data, .data(a), .data(b)))
        case .mkNilData:
            _ = try unit(args[0])
            return .con(.list(.data, []))
        case .mkNilPairData:
            _ = try unit(args[0])
            return .con(.list(.pair(.data, .data), []))

        // MARK: — Integer ↔ ByteString
        case .integerToByteString:
            let bigEndian = try bool(args[0])
            let width     = try safeInt(try integer(args[1]))
            guard width >= 0 else { throw MachineError.evaluationFailure }
            let n         = try integer(args[2])
            return .con(.byteString(try integerToByteString(n, width: width, bigEndian: bigEndian)))
        case .byteStringToInteger:
            let bigEndian = try bool(args[0])
            let bs        = try byteString(args[1])
            return .con(.integer(byteStringToInteger(bs, bigEndian: bigEndian)))

        // MARK: — Bitwise
        case .andByteString:
            let ext  = try bool(args[0])
            let (a, b) = try twoByteStrings([args[1], args[2]])
            return .con(.byteString(bitwiseAnd(a, b, extending: ext)))
        case .orByteString:
            let ext  = try bool(args[0])
            let (a, b) = try twoByteStrings([args[1], args[2]])
            return .con(.byteString(bitwiseOr(a, b, extending: ext)))
        case .xorByteString:
            let ext  = try bool(args[0])
            let (a, b) = try twoByteStrings([args[1], args[2]])
            return .con(.byteString(bitwiseXor(a, b, extending: ext)))
        case .complementByteString:
            let bs = try byteString(args[0])
            return .con(.byteString(Data(bs.map { ~$0 })))
        case .readBit:
            let bs  = try byteString(args[0])
            let idx = try safeInt(try integer(args[1]))
            guard idx >= 0 && idx < bs.count * 8 else { throw MachineError.evaluationFailure }
            // Plutus uses LSB-first bit ordering with little-endian byte order:
            // bit 0 = LSB of the LAST byte (byte at index N-1)
            let byteIdx = bs.count - 1 - (idx / 8)
            let byte = bs[bs.startIndex + byteIdx]
            let bit  = (byte >> (idx % 8)) & 1
            return .con(.bool(bit == 1))
        case .writeBits:
            var bs     = try byteString(args[0])
            let pairs  = try listOfIntPairs(args[1])
            let value  = try bool(args[2])
            for idx in pairs {
                guard idx >= 0 && idx < bs.count * 8 else { throw MachineError.evaluationFailure }
                // LSB-first bit ordering, little-endian byte order
                let byteIdx = bs.count - 1 - (idx / 8)
                let bitIdx  = idx % 8
                if value {
                    bs[bs.startIndex + byteIdx] |= (1 << bitIdx)
                } else {
                    bs[bs.startIndex + byteIdx] &= ~(1 << bitIdx)
                }
            }
            return .con(.byteString(bs))
        case .replicateByte:
            let count = try safeInt(try integer(args[0]))
            let byte  = try safeUInt8(try integer(args[1]))
            guard count >= 0 && count <= 8192 else { throw MachineError.evaluationFailure }
            return .con(.byteString(Data(repeating: byte, count: count)))
        case .shiftByteString:
            let bs       = try byteString(args[0])
            let shiftBig = try integer(args[1])
            // If shift magnitude exceeds bit length, result is all zeros
            let bitLen = BigInt(bs.count * 8)
            if bs.isEmpty {
                return .con(.byteString(bs))
            } else if shiftBig.magnitude >= bitLen.magnitude {
                return .con(.byteString(Data(count: bs.count)))
            }
            return .con(.byteString(shiftBytes(bs, by: Int(shiftBig))))
        case .rotateByteString:
            let bs     = try byteString(args[0])
            let rotBig = try integer(args[1])
            if bs.isEmpty {
                return .con(.byteString(bs))
            }
            // Reduce rotation modulo bit length using BigInt arithmetic
            let bitLen = BigInt(bs.count * 8)
            let reduced = ((rotBig % bitLen) + bitLen) % bitLen
            return .con(.byteString(rotateBytes(bs, by: Int(reduced))))
        case .countSetBits:
            let bs = try byteString(args[0])
            return .con(.integer(BigInt(bs.reduce(0) { $0 + Int($1.nonzeroBitCount) })))
        case .findFirstSetBit:
            // Plutus: LSB-first, little-endian byte order
            // Scan from the LAST byte (byte 0 in Plutus = lowest significance)
            let bs = try byteString(args[0])
            for revIdx in 0..<bs.count {
                let byteIdx = bs.count - 1 - revIdx
                let byte = bs[bs.startIndex + byteIdx]
                if byte != 0 {
                    for bit in 0...7 {
                        if (byte >> bit) & 1 == 1 {
                            return .con(.integer(BigInt(revIdx * 8 + bit)))
                        }
                    }
                }
            }
            return .con(.integer(-1))

        // MARK: — BLS12-381 G1
        case .bls12_381_G1_add:
            let a = try g1Element(args[0])
            let b = try g1Element(args[1])
            return .con(.bls12_381G1Element((a + b).compress()))
        case .bls12_381_G1_neg:
            let p = try g1Element(args[0])
            return .con(.bls12_381G1Element(p.negated().compress()))
        case .bls12_381_G1_scalarMul:
            let scalar = try integer(args[0])
            let p      = try g1Element(args[1])
            return .con(.bls12_381G1Element(p.multiplied(by: scalar).compress()))
        case .bls12_381_G1_equal:
            let a = try g1Element(args[0])
            let b = try g1Element(args[1])
            return .con(.bool(a == b))
        case .bls12_381_G1_compress:
            let p = try g1Element(args[0])
            return .con(.byteString(p.compress()))
        case .bls12_381_G1_uncompress:
            let bs = try byteString(args[0])
            let p  = try G1Point(compressed: bs)
            return .con(.bls12_381G1Element(p.compress()))
        case .bls12_381_G1_hashToGroup:
            let msg = try byteString(args[0])
            let dst = try byteString(args[1])
            let p = G1Point.hash(to: msg, dst: dst)
            return .con(.bls12_381G1Element(p.compress()))

        // MARK: — BLS12-381 G2
        case .bls12_381_G2_add:
            let a = try g2Element(args[0])
            let b = try g2Element(args[1])
            return .con(.bls12_381G2Element((a + b).compress()))
        case .bls12_381_G2_neg:
            let p = try g2Element(args[0])
            return .con(.bls12_381G2Element(p.negated().compress()))
        case .bls12_381_G2_scalarMul:
            let scalar = try integer(args[0])
            let p      = try g2Element(args[1])
            return .con(.bls12_381G2Element(p.multiplied(by: scalar).compress()))
        case .bls12_381_G2_equal:
            let a = try g2Element(args[0])
            let b = try g2Element(args[1])
            return .con(.bool(a == b))
        case .bls12_381_G2_compress:
            let p = try g2Element(args[0])
            return .con(.byteString(p.compress()))
        case .bls12_381_G2_uncompress:
            let bs = try byteString(args[0])
            let p  = try G2Point(compressed: bs)
            return .con(.bls12_381G2Element(p.compress()))
        case .bls12_381_G2_hashToGroup:
            let msg = try byteString(args[0])
            let dst = try byteString(args[1])
            let p = G2Point.hash(to: msg, dst: dst)
            return .con(.bls12_381G2Element(p.compress()))

        // MARK: — BLS12-381 Pairing
        case .bls12_381_millerLoop:
            let g1 = try g1Element(args[0])
            let g2 = try g2Element(args[1])
            let result = Pairing.millerLoop(g1: g1, g2: g2)
            return .con(.bls12_381MlResult(fp12ToData(result)))
        case .bls12_381_mulMlResult:
            let a = try mlResult(args[0])
            let b = try mlResult(args[1])
            let product = a * b
            return .con(.bls12_381MlResult(fp12ToData(product)))
        case .bls12_381_finalVerify:
            let a = try mlResult(args[0])
            let b = try mlResult(args[1])
            return .con(.bool(Pairing.finalVerify(a, b)))
        }
    }
}

// MARK: — Argument extraction helpers

private func integer(_ v: Value) throws -> BigInt {
    guard case .con(.integer(let n)) = v else { throw MachineError.typeError("expected integer") }
    return n
}

private func byteString(_ v: Value) throws -> Data {
    guard case .con(.byteString(let d)) = v else { throw MachineError.typeError("expected bytestring") }
    return d
}

private func string(_ v: Value) throws -> String {
    guard case .con(.string(let s)) = v else { throw MachineError.typeError("expected string") }
    return s
}

private func bool(_ v: Value) throws -> Bool {
    guard case .con(.bool(let b)) = v else { throw MachineError.typeError("expected bool") }
    return b
}

private func unit(_ v: Value) throws -> Void {
    guard case .con(.unit) = v else { throw MachineError.typeError("expected unit") }
}

private func constant(_ v: Value) throws -> UPLCConstant {
    guard case .con(let c) = v else { throw MachineError.typeError("expected constant") }
    return c
}

private func plutusData(_ v: Value) throws -> PlutusData {
    guard case .con(.data(let pd)) = v else { throw MachineError.typeError("expected data") }
    return pd
}

private func twoIntegers(_ args: [Value]) throws -> (BigInt, BigInt) {
    (try integer(args[0]), try integer(args[1]))
}

private func twoByteStrings(_ args: [Value]) throws -> (Data, Data) {
    (try byteString(args[0]), try byteString(args[1]))
}

private func twoStrings(_ args: [Value]) throws -> (String, String) {
    (try string(args[0]), try string(args[1]))
}

private func listOfData(_ v: Value) throws -> [PlutusData] {
    guard case .con(.list(_, let items)) = v else { throw MachineError.typeError("expected list") }
    return try items.map { guard case .data(let pd) = $0 else { throw MachineError.typeError("expected data in list") }; return pd }
}

private func listOfPairs(_ v: Value) throws -> [(PlutusData, PlutusData)] {
    guard case .con(.list(_, let items)) = v else { throw MachineError.typeError("expected list of pairs") }
    return try items.map { item in
        guard case .pair(_, _, .data(let k), .data(let vv)) = item else { throw MachineError.typeError("expected data pair") }
        return (k, vv)
    }
}

private func listOfIntPairs(_ v: Value) throws -> [Int] {
    guard case .con(.list(_, let items)) = v else { throw MachineError.typeError("expected list") }
    return try items.map { Int(try integer(.con($0))) }
}

// MARK: — BLS12-381 argument extraction helpers

private func g1Element(_ v: Value) throws -> G1Point {
    guard case .con(.bls12_381G1Element(let d)) = v else {
        throw MachineError.typeError("expected BLS12-381 G1 element")
    }
    return try G1Point(compressed: d)
}

private func g2Element(_ v: Value) throws -> G2Point {
    guard case .con(.bls12_381G2Element(let d)) = v else {
        throw MachineError.typeError("expected BLS12-381 G2 element")
    }
    return try G2Point(compressed: d)
}

private func mlResult(_ v: Value) throws -> Fp12 {
    guard case .con(.bls12_381MlResult(let d)) = v else {
        throw MachineError.typeError("expected BLS12-381 Miller loop result")
    }
    return dataToFp12(d)
}

/// Serialize an Fp12 value to raw bytes.
/// Fp12 is a thin wrapper around blst_fp12 — we serialize by copying the struct's memory.
private func fp12ToData(_ fp12: Fp12) -> Data {
    var value = fp12
    return withUnsafeBytes(of: &value) { Data($0) }
}

/// Deserialize raw bytes back to an Fp12 value.
private func dataToFp12(_ data: Data) -> Fp12 {
    precondition(data.count == MemoryLayout<Fp12>.size,
                 "BLS12-381 ML result data has wrong size: \(data.count) vs \(MemoryLayout<Fp12>.size)")
    return data.withUnsafeBytes { ptr in
        ptr.load(as: Fp12.self)
    }
}

// MARK: — Safe Int conversion from BigInt

/// Safely convert a BigInt to Int, throwing on overflow instead of crashing.
private func safeInt(_ n: BigInt) throws -> Int {
    guard n >= BigInt(Int.min) && n <= BigInt(Int.max) else {
        throw MachineError.evaluationFailure
    }
    return Int(n)
}

/// Safely convert a BigInt to UInt8, throwing on overflow.
private func safeUInt8(_ n: BigInt) throws -> UInt8 {
    guard n >= 0 && n <= 255 else {
        throw MachineError.evaluationFailure
    }
    return UInt8(n)
}

/// Safely convert a BigInt to UInt64, throwing on overflow.
private func safeUInt64(_ n: BigInt) throws -> UInt64 {
    guard n >= 0 && n <= BigInt(UInt64.max) else {
        throw MachineError.evaluationFailure
    }
    return UInt64(n)
}

// MARK: — Integer arithmetic helpers

/// Floor division (Haskell's `div`): rounds toward negative infinity.
/// Matches Cardano UPLC `divideInteger` semantics.
private func euclideanDiv(_ a: BigInt, _ b: BigInt) -> BigInt {
    let q = a / b       // Swift truncating division (rounds toward zero)
    let r = a % b       // Swift truncating remainder
    // Adjust when remainder is nonzero and has different sign than divisor
    if r != 0 && ((r < 0) != (b < 0)) {
        return q - 1
    }
    return q
}

/// Floor mod (Haskell's `mod`): result has same sign as divisor.
/// Matches Cardano UPLC `modInteger` semantics.
private func euclideanMod(_ a: BigInt, _ b: BigInt) -> BigInt {
    let r = a % b
    if r != 0 && ((r < 0) != (b < 0)) {
        return r + b
    }
    return r
}

// MARK: — Crypto helpers

private func blake2b(_ data: Data, digestSize: Int) throws -> Data {
    // Use the one-shot API which correctly sizes the output buffer,
    // avoiding a bug in SwiftNaCl's streaming blake2bFinal that
    // allocates a bytesMax-sized buffer and returns it un-truncated.
    let sodium = Sodium()
    return try sodium.cryptoGenericHash.blake2bSaltPersonal(
        data: data,
        digestSize: digestSize
    )
}

private func sha3_256(_ data: Data) throws -> Data {
    Data(CryptoSwift.SHA3(variant: .sha256).calculate(for: Array(data)))
}

private func keccak256(_ data: Data) throws -> Data {
    Data(CryptoSwift.SHA3(variant: .keccak256).calculate(for: Array(data)))
}

private func ripemd160(_ data: Data) throws -> Data {
    RIPEMD160.hash(data)
}

private func verifyEd25519(pubKey: Data, msg: Data, sig: Data) throws -> Bool {
    guard pubKey.count == 32 else { throw MachineError.evaluationFailure }
    guard sig.count == 64 else { throw MachineError.evaluationFailure }
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: pubKey)
    return key.isValidSignature(sig, for: msg)
}

// MARK: — SECP256k1 helpers

/// Verify an ECDSA signature over the SECP256k1 curve (CIP-0049).
/// Uses the libsecp256k1 C API directly to avoid Digest protocol ambiguity
/// and to pass the pre-hashed 32-byte message without double-hashing.
/// - Parameters:
///   - pubKey: 33-byte compressed public key (SEC1 format)
///   - msgHash: 32-byte pre-hashed message
///   - sig: 64-byte compact signature (r || s)
/// - Returns: true if the signature is valid
private func verifyEcdsaSecp256k1(pubKey: Data, msgHash: Data, sig: Data) throws -> Bool {
    guard pubKey.count == 33 else {
        throw MachineError.typeError("verifyEcdsaSecp256k1Signature: pubkey must be 33 bytes")
    }
    guard msgHash.count == 32 else {
        throw MachineError.typeError("verifyEcdsaSecp256k1Signature: message hash must be 32 bytes")
    }
    guard sig.count == 64 else {
        throw MachineError.typeError("verifyEcdsaSecp256k1Signature: signature must be 64 bytes")
    }

    guard let ctx = secp256k1_context_create(UInt32(SECP256K1_CONTEXT_VERIFY)) else {
        throw MachineError.typeError("verifyEcdsaSecp256k1Signature: failed to create secp256k1 context")
    }
    defer { secp256k1_context_destroy(ctx) }

    // Parse the 33-byte compressed public key
    var parsedPubKey = secp256k1_pubkey()
    guard secp256k1_ec_pubkey_parse(ctx, &parsedPubKey, Array(pubKey), pubKey.count) == 1 else {
        throw MachineError.typeError("verifyEcdsaSecp256k1Signature: invalid public key")
    }

    // Parse the 64-byte compact (r||s) signature
    var parsedSig = secp256k1_ecdsa_signature()
    guard secp256k1_ecdsa_signature_parse_compact(ctx, &parsedSig, Array(sig)) == 1 else {
        throw MachineError.typeError("verifyEcdsaSecp256k1Signature: invalid signature")
    }

    // Cardano (CIP-0049) requires signatures to use low-S form.
    // secp256k1_ecdsa_signature_normalize returns 1 if the signature had a
    // high-S component (and was normalised), 0 if it was already low-S.
    // Reject high-S signatures outright rather than accepting them after normalisation.
    var normalizedSig = secp256k1_ecdsa_signature()
    let wasHighS = secp256k1_ecdsa_signature_normalize(ctx, &normalizedSig, &parsedSig)
    guard wasHighS == 0 else {
        return false
    }

    // Verify: passes the raw 32-byte hash directly to secp256k1_ecdsa_verify
    return secp256k1_ecdsa_verify(ctx, &parsedSig, Array(msgHash), &parsedPubKey) == 1
}

/// Verify a Schnorr signature over the SECP256k1 curve (CIP-0049 / BIP-340).
/// - Parameters:
///   - pubKey: 32-byte x-only public key
///   - msg: arbitrary-length message
///   - sig: 64-byte BIP-340 signature
/// - Returns: true if the signature is valid
private func verifySchnorrSecp256k1(pubKey: Data, msg: Data, sig: Data) throws -> Bool {
    guard pubKey.count == 32 else {
        throw MachineError.typeError("verifySchnorrSecp256k1Signature: pubkey must be 32 bytes")
    }
    guard sig.count == 64 else {
        throw MachineError.typeError("verifySchnorrSecp256k1Signature: signature must be 64 bytes")
    }
    let xonlyKey = P256K.Schnorr.XonlyKey(dataRepresentation: pubKey)
    let signature = try P256K.Schnorr.SchnorrSignature(dataRepresentation: sig)
    var msgBytes = Array(msg)
    return xonlyKey.isValid(signature, for: &msgBytes)
}

// MARK: — IntegerToByteString

private let maxIntegerToByteStringLength = 8192

private func integerToByteString(_ n: BigInt, width: Int, bigEndian: Bool) throws -> Data {
    guard n >= 0 else { throw MachineError.typeError("integerToByteString: negative integer") }
    var bytes = n.magnitude.serialize()   // big-endian bytes from BigUInt
    // Remove leading zero byte that BigUInt.serialize() may add
    if bytes.first == 0 && bytes.count > 1 { bytes.removeFirst() }
    if width > 0 {
        guard bytes.count <= width else { throw MachineError.integerToByteStringTooLong }
        guard width <= maxIntegerToByteStringLength else { throw MachineError.integerToByteStringTooLong }
        while bytes.count < width { bytes.insert(0, at: 0) }
    } else {
        guard bytes.count <= maxIntegerToByteStringLength else { throw MachineError.integerToByteStringTooLong }
    }
    if !bigEndian { bytes.reverse() }
    return Data(bytes)
}

private func byteStringToInteger(_ data: Data, bigEndian: Bool) -> BigInt {
    var bytes = Array(data)
    if !bigEndian { bytes.reverse() }
    return BigInt(BigUInt(Data(bytes)))
}

// MARK: — Bitwise helpers

private func bitwiseOp(_ a: Data, _ b: Data, extending: Bool, identity: UInt8, op: (UInt8, UInt8) -> UInt8) -> Data {
    let len = extending ? max(a.count, b.count) : min(a.count, b.count)
    var result = Data(count: len)
    for i in 0..<len {
        let ai: UInt8 = i < a.count ? a[a.startIndex + i] : identity
        let bi: UInt8 = i < b.count ? b[b.startIndex + i] : identity
        result[i] = op(ai, bi)
    }
    return result
}

private func bitwiseAnd(_ a: Data, _ b: Data, extending: Bool) -> Data {
    // AND identity = 0xFF (AND with 0xFF preserves the other operand)
    bitwiseOp(a, b, extending: extending, identity: 0xFF) { $0 & $1 }
}

private func bitwiseOr(_ a: Data, _ b: Data, extending: Bool) -> Data {
    // OR identity = 0x00 (OR with 0x00 preserves the other operand)
    bitwiseOp(a, b, extending: extending, identity: 0x00) { $0 | $1 }
}

private func bitwiseXor(_ a: Data, _ b: Data, extending: Bool) -> Data {
    // XOR identity = 0x00 (XOR with 0x00 preserves the other operand)
    bitwiseOp(a, b, extending: extending, identity: 0x00) { $0 ^ $1 }
}

private func shiftBytes(_ data: Data, by shift: Int) -> Data {
    // Plutus: positive shift = left shift (towards MSB / higher significance)
    // In big-endian bit indexing: output[i] = input[i + shift]
    guard !data.isEmpty else { return data }
    let bitLen = data.count * 8
    var result = Data(count: data.count)
    for i in 0..<bitLen {
        let src = i + shift
        guard src >= 0 && src < bitLen else { continue }
        let srcByte = src / 8; let srcBit = 7 - (src % 8)
        let dstByte = i / 8;   let dstBit = 7 - (i % 8)
        let bit = (data[data.startIndex + srcByte] >> srcBit) & 1
        result[dstByte] |= bit << dstBit
    }
    return result
}

private func rotateBytes(_ data: Data, by rotation: Int) -> Data {
    // Plutus: positive rotation = left rotation (towards MSB)
    guard !data.isEmpty else { return data }
    let bitLen = data.count * 8
    let rot    = ((rotation % bitLen) + bitLen) % bitLen
    var result = Data(count: data.count)
    for i in 0..<bitLen {
        let src = (i + rot) % bitLen
        let srcByte = src / 8; let srcBit = 7 - (src % 8)
        let dstByte = i / 8;   let dstBit = 7 - (i % 8)
        let bit = (data[data.startIndex + srcByte] >> srcBit) & 1
        result[dstByte] |= bit << dstBit
    }
    return result
}

// MARK: — BigInteger → BigInt bridge

extension SwiftCardanoCore.BigInteger {
    func toBigInt() -> BigInt {
        switch self {
        case .int(let n):    return BigInt(n)
        case .bigUInt(let n): return BigInt(n)
        case .bigNInt(let n): return n
        }
    }
}

extension SwiftCardanoCore.BigInteger {
    init(bigInt: BigInt) {
        if bigInt >= 0 {
            self = .bigUInt(bigInt.magnitude)
        } else {
            self = .bigNInt(bigInt)
        }
    }
}
