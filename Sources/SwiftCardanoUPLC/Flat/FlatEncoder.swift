import BigInt
import Foundation
import SwiftCardanoCore

/// Encodes a `DeBruijnProgram` to the flat binary format used on-chain.
public struct FlatEncoder: Sendable {
    public init() {}

    /// Encode a De Bruijn program to flat bytes.
    public func encode(_ program: DeBruijnProgram) throws -> Data {
        var w = BitWriter()
        // Version: three zigzag-encoded unsigned integers
        writeUInt(&w, program.version.0)
        writeUInt(&w, program.version.1)
        writeUInt(&w, program.version.2)
        try encodeTerm(&w, program.term)
        return w.finalize()
    }

    /// Encode and return a hex string.
    public func encodeHex(_ program: DeBruijnProgram) throws -> String {
        let data = try encode(program)
        return data.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: — Internal encoding helpers

private func encodeTerm(_ w: inout BitWriter, _ term: Term<DeBruijn>) throws {
    switch term {
    case .var(let idx):
        w.writeBits(0b0000, count: 4)
        writeUInt(&w, idx.index)
    case .delay(let body):
        w.writeBits(0b0001, count: 4)
        try encodeTerm(&w, body)
    case .lambda(_, let body):
        w.writeBits(0b0010, count: 4)
        // binder: nothing written (DeBruijn binder encodes as zero bytes in Rust)
        try encodeTerm(&w, body)
    case .apply(let f, let arg):
        w.writeBits(0b0011, count: 4)
        try encodeTerm(&w, f)
        try encodeTerm(&w, arg)
    case .constant(let c):
        w.writeBits(0b0100, count: 4)
        try encodeConstant(&w, c)
    case .force(let body):
        w.writeBits(0b0101, count: 4)
        try encodeTerm(&w, body)
    case .error:
        w.writeBits(0b0110, count: 4)
    case .builtin(let fn):
        w.writeBits(0b0111, count: 4)
        w.writeBits(UInt64(fn.rawValue), count: 7)
    case .constr(let tag, let fields):
        w.writeBits(0b1000, count: 4)
        writeUInt(&w, UInt(tag))
        try writeList(&w, fields) { f, item in
            try encodeTerm(&f, item)
        }
    case .case(let arg, let branches):
        w.writeBits(0b1001, count: 4)
        try encodeTerm(&w, arg)
        try writeList(&w, branches) { f, item in
            try encodeTerm(&f, item)
        }
    }
}

private func encodeConstant(_ w: inout BitWriter, _ constant: UPLCConstant) throws {
    // Write the type tag sequence, then the value
    try encodeConstantType(&w, constant)
    try encodeConstantValue(&w, constant)
}

/// Write flat constant type tags (4-bit each), terminated by a 0-bit stop flag.
/// The encoding is a list: each element preceded by a `1` continuation bit,
/// the list terminated by a `0` stop bit.
private func encodeConstantType(_ w: inout BitWriter, _ constant: UPLCConstant) throws {
    let tags = constantTypeTags(for: constant)
    for tag in tags {
        w.writeBit(true)   // continuation: more elements
        w.writeBits(UInt64(tag), count: 4)
    }
    w.writeBit(false)      // stop bit
}

/// Returns the sequence of 4-bit type tags for a constant's type annotation.
private func constantTypeTags(for constant: UPLCConstant) -> [UInt8] {
    switch constant {
    case .integer:            return [0]
    case .byteString:         return [1]
    case .string:             return [2]
    case .unit:               return [3]
    case .bool:               return [4]
    case .list(let t, _):     return [7, 5] + typeTags(t)
    case .pair(let t1, let t2, _, _): return [7, 7, 6] + typeTags(t1) + typeTags(t2)
    case .data:               return [8]
    case .bls12_381G1Element: return [9]
    case .bls12_381G2Element: return [10]
    case .bls12_381MlResult:  return [11]
    }
}

private func typeTags(_ t: UPLCType) -> [UInt8] {
    switch t {
    case .integer:             return [0]
    case .byteString:          return [1]
    case .string:              return [2]
    case .unit:                return [3]
    case .bool:                return [4]
    case .list(let inner):     return [7, 5] + typeTags(inner)
    case .pair(let a, let b):  return [7, 7, 6] + typeTags(a) + typeTags(b)
    case .data:                return [8]
    case .bls12_381G1Element:  return [9]
    case .bls12_381G2Element:  return [10]
    case .bls12_381MlResult:   return [11]
    }
}

private func encodeConstantValue(_ w: inout BitWriter, _ constant: UPLCConstant) throws {
    switch constant {
    case .integer(let n):
        writeBigInt(&w, n)
    case .byteString(let data):
        writeByteString(&w, Array(data))
    case .string(let s):
        let bytes = Array(s.utf8)
        writeByteString(&w, bytes)
    case .unit:
        break
    case .bool(let b):
        w.writeBit(b)
    case .list(_, let items):
        for item in items {
            w.writeBit(true)
            try encodeConstantValue(&w, item)
        }
        w.writeBit(false)
    case .pair(_, _, let a, let b):
        try encodeConstantValue(&w, a)
        try encodeConstantValue(&w, b)
    case .data(let pd):
        let cborBytes = try pd.toCBORData()
        writeByteString(&w, Array(cborBytes))
    case .bls12_381G1Element(let bytes):
        w.writeBytes(Array(bytes))
    case .bls12_381G2Element(let bytes):
        w.writeBytes(Array(bytes))
    case .bls12_381MlResult(let bytes):
        w.writeBytes(Array(bytes))
    }
}

// MARK: — Flat integer encoding (ZigZag + 7-bit chunks)

/// Encode an unsigned integer using flat's variable-length 7-bit chunk encoding.
/// Each 7-bit group is preceded by a continuation bit (`1` = more, `0` = last).
private func writeUInt(_ w: inout BitWriter, _ value: UInt) {
    writeUInt64(&w, UInt64(value))
}

private func writeUInt64(_ w: inout BitWriter, _ value: UInt64) {
    var v = value
    repeat {
        let chunk = v & 0x7F
        v >>= 7
        w.writeBit(v != 0)   // continuation bit
        w.writeBits(chunk, count: 7)
    } while v != 0
}

/// ZigZag-encode a BigInt, then write using 7-bit chunks.
private func writeBigInt(_ w: inout BitWriter, _ value: BigInt) {
    // ZigZag: (n << 1) ^ (n >> 63)
    let zigzag: BigUInt
    if value >= 0 {
        zigzag = BigUInt(value) * 2
    } else {
        zigzag = BigUInt(value.magnitude) * 2 - 1
    }
    var v = zigzag
    let zero = BigUInt(0)
    let mask = BigUInt(0x7F)
    repeat {
        let chunk = v & mask
        v >>= 7
        w.writeBit(v != zero)
        w.writeBits(UInt64(chunk), count: 7)
    } while v != zero
}

/// Write a byte string: length-prefixed in 8-byte groups.
/// Format: for each group of up to 255 bytes: [length byte][bytes], terminated by [0x00].
private func writeByteString(_ w: inout BitWriter, _ bytes: [UInt8]) {
    w.writeFiller()   // byte-align before chunk data (flat filler protocol)
    var offset = 0
    while offset < bytes.count {
        let chunkLen = min(255, bytes.count - offset)
        w.writeBits(UInt64(chunkLen), count: 8)
        for i in offset..<(offset + chunkLen) {
            w.writeBits(UInt64(bytes[i]), count: 8)
        }
        offset += chunkLen
    }
    w.writeBits(0, count: 8) // terminating zero-length chunk
}

/// Write a list of items using the flat list encoding (1-bit per element).
private func writeList<T>(_ w: inout BitWriter, _ items: [T], body: (inout BitWriter, T) throws -> Void) rethrows {
    for item in items {
        w.writeBit(true)
        try body(&w, item)
    }
    w.writeBit(false)
}
