import Foundation

/// Writes individual bits and groups into a growable byte buffer.
/// The flat format packs bits MSB-first within each byte.
public struct BitWriter: Sendable {
    private var buffer: [UInt8] = []
    /// Current byte being assembled (bits written MSB-first).
    private var currentByte: UInt8 = 0
    /// How many bits have been written into `currentByte` (0–7).
    private var usedBits: Int = 0

    public init() {}

    /// Write a single bit (false = 0, true = 1).
    public mutating func writeBit(_ bit: Bool) {
        let shift = 7 - usedBits
        if bit { currentByte |= (1 << shift) }
        usedBits += 1
        if usedBits == 8 {
            buffer.append(currentByte)
            currentByte = 0
            usedBits = 0
        }
    }

    /// Write the lowest `count` bits of `value`, MSB first.
    public mutating func writeBits(_ value: UInt64, count: Int) {
        assert(count >= 0 && count <= 64)
        for i in stride(from: count - 1, through: 0, by: -1) {
            writeBit((value >> i) & 1 == 1)
        }
    }

    /// Write raw bytes (8 bits each).
    public mutating func writeBytes(_ bytes: [UInt8]) {
        for byte in bytes {
            writeBits(UInt64(byte), count: 8)
        }
    }

    /// Byte-align the stream by writing a flat "filler": pad the current partial
    /// byte with `0` bits and write a `1` at the final (LSB) position, then
    /// commit the byte so `usedBits` returns to 0.
    ///
    /// The filler is written *unconditionally*. When the stream is already on
    /// a byte boundary flat still emits a whole `0x01` byte (seven zero bits
    /// and the terminating one) — skipping it there produces a stream the
    /// reference decoder cannot read, and a script whose hash will not match
    /// what the node computes.
    ///
    /// This must be called before writing byte-array data (bytestrings, strings,
    /// CBOR-encoded data constants) to match the reference flat encoder, which
    /// requires byte-aligned chunk writes.
    public mutating func writeFiller() {
        while usedBits < 7 {
            writeBit(false)
        }
        writeBit(true)
        // usedBits is now 0 — the byte was committed by writeBit above.
    }

    /// Write the flat end-of-stream marker and return the final buffer.
    ///
    /// The flat format embeds the end marker as a `1` bit written into the
    /// last (possibly partial) byte, preceded by zero-padding bits:
    ///   - If mid-byte: pad zeros up to bit 0 of the current byte, then
    ///     write `1` at bit 0 — the decoder finds the first `1` while
    ///     consuming padding and treats it as the end marker.
    ///   - If exactly on a byte boundary: append `0x01` as a standalone
    ///     end-marker byte (decoder handles this case separately).
    ///
    /// After calling this the writer is in an undefined state.
    public mutating func finalize() -> Data {
        if usedBits != 0 {
            // Pad zeros up to but not including the last bit of the current byte,
            // then write 1 (the end marker) at the final bit position.
            while usedBits < 7 {
                writeBit(false)
            }
            writeBit(true)
        } else {
            // Exactly on a byte boundary: write end-marker as a standalone 0x01 byte.
            buffer.append(0x01)
        }
        return Data(buffer)
    }
}
