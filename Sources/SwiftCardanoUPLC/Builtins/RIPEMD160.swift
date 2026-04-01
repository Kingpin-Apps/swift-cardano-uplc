import Foundation

/// Pure Swift implementation of the RIPEMD-160 hash function.
/// Produces a 20-byte (160-bit) digest.
///
/// Reference: https://homes.esat.kuleuven.be/~bosMDselaers/ripemd160.html
enum RIPEMD160 {

    static func hash(_ data: Data) -> Data {
        var message = Array(data)

        // Step 1: Pad the message
        let originalBitLength = UInt64(message.count) &* 8
        message.append(0x80)
        while message.count % 64 != 56 {
            message.append(0x00)
        }
        // Append length in bits as 64-bit little-endian
        for i in 0..<8 {
            message.append(UInt8(truncatingIfNeeded: originalBitLength >> (i * 8)))
        }

        // Step 2: Initialize hash values
        var h0: UInt32 = 0x67452301
        var h1: UInt32 = 0xEFCDAB89
        var h2: UInt32 = 0x98BADCFE
        var h3: UInt32 = 0x10325476
        var h4: UInt32 = 0xC3D2E1F0

        // Step 3: Process each 512-bit block
        let blockCount = message.count / 64
        for block in 0..<blockCount {
            var x = [UInt32](repeating: 0, count: 16)
            for i in 0..<16 {
                let offset = block * 64 + i * 4
                x[i] = UInt32(message[offset])
                     | (UInt32(message[offset + 1]) << 8)
                     | (UInt32(message[offset + 2]) << 16)
                     | (UInt32(message[offset + 3]) << 24)
            }

            // Left round
            var al = h0, bl = h1, cl = h2, dl = h3, el = h4
            // Right round
            var ar = h0, br = h1, cr = h2, dr = h3, er = h4

            for j in 0..<80 {
                var tl: UInt32
                var tr: UInt32

                // Left
                let fl: UInt32
                let kl: UInt32
                switch j {
                case 0..<16:
                    fl = bl ^ cl ^ dl
                    kl = 0x00000000
                case 16..<32:
                    fl = (bl & cl) | (~bl & dl)
                    kl = 0x5A827999
                case 32..<48:
                    fl = (bl | ~cl) ^ dl
                    kl = 0x6ED9EBA1
                case 48..<64:
                    fl = (bl & dl) | (cl & ~dl)
                    kl = 0x8F1BBCDC
                default:
                    fl = bl ^ (cl | ~dl)
                    kl = 0xA953FD4E
                }
                tl = al &+ fl &+ x[Int(rl[j])] &+ kl
                tl = rotl(tl, Int(sl[j])) &+ el
                al = el; el = dl; dl = rotl(cl, 10); cl = bl; bl = tl

                // Right
                let fr: UInt32
                let kr: UInt32
                switch j {
                case 0..<16:
                    fr = br ^ (cr | ~dr)
                    kr = 0x50A28BE6
                case 16..<32:
                    fr = (br & dr) | (cr & ~dr)
                    kr = 0x5C4DD124
                case 32..<48:
                    fr = (br | ~cr) ^ dr
                    kr = 0x6D703EF3
                case 48..<64:
                    fr = (br & cr) | (~br & dr)
                    kr = 0x7A6D76E9
                default:
                    fr = br ^ cr ^ dr
                    kr = 0x00000000
                }
                tr = ar &+ fr &+ x[Int(rr[j])] &+ kr
                tr = rotl(tr, Int(sr[j])) &+ er
                ar = er; er = dr; dr = rotl(cr, 10); cr = br; br = tr
            }

            let t = h1 &+ cl &+ dr
            h1 = h2 &+ dl &+ er
            h2 = h3 &+ el &+ ar
            h3 = h4 &+ al &+ br
            h4 = h0 &+ bl &+ cr
            h0 = t
        }

        // Step 4: Produce the final hash value (little-endian)
        var result = Data(count: 20)
        for (i, h) in [h0, h1, h2, h3, h4].enumerated() {
            result[i * 4]     = UInt8(truncatingIfNeeded: h)
            result[i * 4 + 1] = UInt8(truncatingIfNeeded: h >> 8)
            result[i * 4 + 2] = UInt8(truncatingIfNeeded: h >> 16)
            result[i * 4 + 3] = UInt8(truncatingIfNeeded: h >> 24)
        }
        return result
    }

    // MARK: - Internal helpers

    private static func rotl(_ x: UInt32, _ n: Int) -> UInt32 {
        (x << n) | (x >> (32 - n))
    }

    // Left message schedule
    private static let rl: [UInt8] = [
        // Round 1
        0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
        // Round 2
        7, 4, 13, 1, 10, 6, 15, 3, 12, 0, 9, 5, 2, 14, 11, 8,
        // Round 3
        3, 10, 14, 4, 9, 15, 8, 1, 2, 7, 0, 6, 13, 11, 5, 12,
        // Round 4
        1, 9, 11, 10, 0, 8, 12, 4, 13, 3, 7, 15, 14, 5, 6, 2,
        // Round 5
        4, 0, 5, 9, 7, 12, 2, 10, 14, 1, 3, 8, 11, 6, 15, 13,
    ]

    // Right message schedule
    private static let rr: [UInt8] = [
        // Round 1
        5, 14, 7, 0, 9, 2, 11, 4, 13, 6, 15, 8, 1, 10, 3, 12,
        // Round 2
        6, 11, 3, 7, 0, 13, 5, 10, 14, 15, 8, 12, 4, 9, 1, 2,
        // Round 3
        15, 5, 1, 3, 7, 14, 6, 9, 11, 8, 12, 2, 10, 0, 4, 13,
        // Round 4
        8, 6, 4, 1, 3, 11, 15, 0, 5, 12, 2, 13, 9, 7, 10, 14,
        // Round 5
        12, 15, 10, 4, 1, 5, 8, 7, 6, 2, 13, 14, 0, 3, 9, 11,
    ]

    // Left rotation amounts
    private static let sl: [UInt8] = [
        // Round 1
        11, 14, 15, 12, 5, 8, 7, 9, 11, 13, 14, 15, 6, 7, 9, 8,
        // Round 2
        7, 6, 8, 13, 11, 9, 7, 15, 7, 12, 15, 9, 11, 7, 13, 12,
        // Round 3
        11, 13, 6, 7, 14, 9, 13, 15, 14, 8, 13, 6, 5, 12, 7, 5,
        // Round 4
        11, 12, 14, 15, 14, 15, 9, 8, 9, 14, 5, 6, 8, 6, 5, 12,
        // Round 5
        9, 15, 5, 11, 6, 8, 13, 12, 5, 12, 13, 14, 11, 8, 5, 6,
    ]

    // Right rotation amounts
    private static let sr: [UInt8] = [
        // Round 1
        8, 9, 9, 11, 13, 15, 15, 5, 7, 7, 8, 11, 14, 14, 12, 6,
        // Round 2
        9, 13, 15, 7, 12, 8, 9, 11, 7, 7, 12, 7, 6, 15, 13, 11,
        // Round 3
        9, 7, 15, 11, 8, 6, 6, 14, 12, 13, 5, 14, 13, 13, 7, 5,
        // Round 4
        15, 5, 8, 11, 14, 14, 6, 14, 6, 9, 12, 9, 12, 5, 15, 8,
        // Round 5
        8, 5, 12, 9, 12, 5, 14, 6, 8, 13, 6, 5, 15, 13, 11, 11,
    ]
}
