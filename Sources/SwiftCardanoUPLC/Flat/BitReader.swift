import Foundation

/// Errors thrown during flat decoding.
public enum FlatDecodingError: Error, Sendable {
    case unexpectedEnd
    case invalidTag(UInt64)
    case invalidConstantType(UInt64)
    case invalidBuiltinTag(UInt64)
    case integerOverflow
    case invalidUTF8
    case trailingBytes
    case missingEndMarker
}

/// Reads individual bits from a flat-encoded byte buffer.
/// Bits are packed MSB-first within each byte.
public struct BitReader: Sendable {
    private let data: [UInt8]
    /// Index of the next byte to read from.
    private var byteIndex: Int = 0
    /// Number of bits already consumed from the current byte (0–7).
    private var bitIndex: Int = 0

    public init(data: Data) {
        self.data = Array(data)
    }

    /// Total number of bits consumed so far.
    public var bitsRead: Int { byteIndex * 8 + bitIndex }

    /// True when all data bits have been consumed (ignoring the end-marker byte).
    public var isAtEnd: Bool { byteIndex >= data.count }

    /// Read a single bit.
    public mutating func readBit() throws -> Bool {
        guard byteIndex < data.count else { throw FlatDecodingError.unexpectedEnd }
        let byte = data[byteIndex]
        let shift = 7 - bitIndex
        let bit = (byte >> shift) & 1 == 1
        bitIndex += 1
        if bitIndex == 8 {
            bitIndex = 0
            byteIndex += 1
        }
        return bit
    }

    /// Read `count` bits and return them as a UInt64 (MSB first).
    public mutating func readBits(count: Int) throws -> UInt64 {
        assert(count >= 0 && count <= 64)
        var result: UInt64 = 0
        for _ in 0..<count {
            result = (result << 1) | (try readBit() ? 1 : 0)
        }
        return result
    }

    /// Read `count` raw bytes (each 8 bits).
    public mutating func readBytes(count: Int) throws -> [UInt8] {
        var result = [UInt8](repeating: 0, count: count)
        for i in 0..<count {
            result[i] = UInt8(try readBits(count: 8))
        }
        return result
    }

    /// Consume the flat filler that precedes byte-array data (bytestrings, strings, CBOR).
    /// Reads zero-padding bits until the first `1` bit is found (the filler terminator),
    /// leaving the reader byte-aligned.
    ///
    /// The filler is *always* present, including when the reader is already on
    /// a byte boundary — flat's `preAligned` emits a whole `0x01` byte in that
    /// case (seven zero bits and the terminating one). Returning early when
    /// already aligned desynchronises the bit stream by exactly one byte, and
    /// every term after it decodes as garbage. `consumeEndPadding` below
    /// handles the same case the same way.
    public mutating func consumeFiller() throws {
        while true {
            let bit = try readBit()
            if bit { return }  // found the `1` filler terminator; now byte-aligned
        }
    }

    /// Consume any trailing padding zeros and the flat end-marker `1` bit.
    /// Throws if the end marker is missing or unexpected bytes remain.
    public mutating func consumeEndPadding() throws {
        // Skip zero padding bits until byte boundary
        while bitIndex != 0 {
            let bit = try readBit()
            if bit {
                // The first `1` we see while padding IS the end marker
                return
            }
        }
        // If we hit an exact byte boundary, the next byte should be the 0x01 end-marker
        guard byteIndex < data.count, data[byteIndex] == 0x01 else {
            throw FlatDecodingError.missingEndMarker
        }
        byteIndex += 1
    }
}
