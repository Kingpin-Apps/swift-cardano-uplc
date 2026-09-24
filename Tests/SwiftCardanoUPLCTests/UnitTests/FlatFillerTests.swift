import Testing
import Foundation
@testable import SwiftCardanoUPLC

/// Flat's `preAligned` filler is written before every byte-array payload
/// (bytestrings, strings, CBOR `data` constants) and is *always* present —
/// including when the stream already sits on a byte boundary, where it is a
/// whole `0x01` byte.
///
/// Skipping it when aligned desynchronises the stream by exactly one byte.
/// The reader and writer both did that, so they agreed with each other and
/// round-trip tests passed, while real scripts compiled by the reference
/// implementation decoded into garbage.
@Suite("Flat filler alignment")
struct FlatFillerTests {

    // MARK: - Writer

    @Test("writeFiller emits a whole 0x01 byte when already byte-aligned")
    func writerEmitsFillerWhenAligned() {
        var w = BitWriter()
        w.writeBits(0xAB, count: 8)   // exactly one byte — now aligned
        w.writeFiller()
        w.writeBits(0xCD, count: 8)
        let out = Array(w.finalize())

        #expect(out.count >= 3)
        #expect(out[0] == 0xAB)
        #expect(out[1] == 0x01, "expected a full filler byte when already aligned")
        #expect(out[2] == 0xCD)
    }

    @Test("writeFiller pads the partial byte when mid-byte")
    func writerPadsWhenMidByte() {
        var w = BitWriter()
        w.writeBits(0b101, count: 3)
        w.writeFiller()
        w.writeBits(0xCD, count: 8)
        let out = Array(w.finalize())

        // 101 then four 0 pad bits then the terminating 1 -> 0b1010_0001
        #expect(out[0] == 0b1010_0001)
        #expect(out[1] == 0xCD)
    }

    // MARK: - Reader

    @Test("consumeFiller consumes the filler byte when already byte-aligned")
    func readerConsumesFillerWhenAligned() throws {
        var r = BitReader(data: Data([0xAB, 0x01, 0xCD]))
        #expect(try r.readBits(count: 8) == 0xAB)
        try r.consumeFiller()
        #expect(r.bitsRead == 16, "the 0x01 filler byte should have been consumed")
        #expect(try r.readBits(count: 8) == 0xCD)
    }

    @Test("consumeFiller consumes the padding when mid-byte")
    func readerConsumesPaddingWhenMidByte() throws {
        var r = BitReader(data: Data([0b1010_0001, 0xCD]))
        _ = try r.readBits(count: 3)
        try r.consumeFiller()
        #expect(r.bitsRead == 8)
        #expect(try r.readBits(count: 8) == 0xCD)
    }

    // MARK: - Round trip

    @Test("reader and writer agree on both alignments")
    func roundTrip() throws {
        for leadingBits in 0...8 {
            var w = BitWriter()
            if leadingBits > 0 { w.writeBits(0b1, count: leadingBits) }
            w.writeFiller()
            w.writeBytes([0xDE, 0xAD, 0xBE, 0xEF])
            let data = w.finalize()

            var r = BitReader(data: data)
            if leadingBits > 0 { _ = try r.readBits(count: leadingBits) }
            try r.consumeFiller()
            #expect(try r.readBytes(count: 4) == [0xDE, 0xAD, 0xBE, 0xEF],
                    "round trip failed with \(leadingBits) leading bits")
        }
    }
}
