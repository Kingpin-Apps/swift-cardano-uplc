/// All UPLC built-in functions.
/// Raw values match the Plutus specification exactly — these are encoded
/// as 7-bit integers in the flat binary format (BUILTIN_TAG_WIDTH = 7).
public enum DefaultFunction: UInt8, CaseIterable, Sendable, Codable, Hashable {
    // MARK: — Integer arithmetic
    case addInteger                     = 0
    case subtractInteger                = 1
    case multiplyInteger                = 2
    case divideInteger                  = 3
    case quotientInteger                = 4
    case remainderInteger               = 5
    case modInteger                     = 6
    case equalsInteger                  = 7
    case lessThanInteger                = 8
    case lessThanEqualsInteger          = 9

    // MARK: — ByteString
    case appendByteString               = 10
    case consByteString                 = 11
    case sliceByteString                = 12
    case lengthOfByteString             = 13
    case indexByteString                = 14
    case equalsByteString               = 15
    case lessThanByteString             = 16
    case lessThanEqualsByteString       = 17

    // MARK: — Cryptographic / hash
    case sha2_256                       = 18
    case sha3_256                       = 19
    case blake2b_256                    = 20
    case verifyEd25519Signature         = 21

    // MARK: — String
    case appendString                   = 22
    case equalsString                   = 23
    case encodeUtf8                     = 24
    case decodeUtf8                     = 25

    // MARK: — Control
    case ifThenElse                     = 26
    case chooseUnit                     = 27
    case trace                          = 28

    // MARK: — Pairs
    case fstPair                        = 29
    case sndPair                        = 30

    // MARK: — Lists
    case chooseList                     = 31
    case mkCons                         = 32
    case headList                       = 33
    case tailList                       = 34
    case nullList                       = 35

    // MARK: — Data
    case chooseData                     = 36
    case constrData                     = 37
    case mapData                        = 38
    case listData                       = 39
    case iData                          = 40
    case bData                          = 41
    case unConstrData                   = 42
    case unMapData                      = 43
    case unListData                     = 44
    case unIData                        = 45
    case unBData                        = 46
    case equalsData                     = 47
    case mkPairData                     = 48
    case mkNilData                      = 49
    case mkNilPairData                  = 50
    case serialiseData                  = 51

    // MARK: — SECP256k1
    case verifyEcdsaSecp256k1Signature  = 52
    case verifySchnorrSecp256k1Signature = 53

    // MARK: — BLS12-381 G1
    case bls12_381_G1_add               = 54
    case bls12_381_G1_neg               = 55
    case bls12_381_G1_scalarMul         = 56
    case bls12_381_G1_equal             = 57
    case bls12_381_G1_compress          = 58
    case bls12_381_G1_uncompress        = 59
    case bls12_381_G1_hashToGroup       = 60

    // MARK: — BLS12-381 G2
    case bls12_381_G2_add               = 61
    case bls12_381_G2_neg               = 62
    case bls12_381_G2_scalarMul         = 63
    case bls12_381_G2_equal             = 64
    case bls12_381_G2_compress          = 65
    case bls12_381_G2_uncompress        = 66
    case bls12_381_G2_hashToGroup       = 67

    // MARK: — BLS12-381 pairing
    case bls12_381_millerLoop           = 68
    case bls12_381_mulMlResult          = 69
    case bls12_381_finalVerify          = 70

    // MARK: — Additional crypto (inserted after BLS block in spec)
    case keccak_256                     = 71
    case blake2b_224                    = 72

    // MARK: — Integer ↔ ByteString conversion
    case integerToByteString            = 73
    case byteStringToInteger            = 74

    // MARK: — Bitwise (Conway era)
    case andByteString                  = 75
    case orByteString                   = 76
    case xorByteString                  = 77
    case complementByteString           = 78
    case readBit                        = 79
    case writeBits                      = 80
    case replicateByte                  = 81
    case shiftByteString                = 82
    case rotateByteString               = 83
    case countSetBits                   = 84
    case findFirstSetBit                = 85
    case ripemd_160                     = 86
}

extension DefaultFunction {
    /// Number of value arguments the builtin requires before it executes.
    public var arity: Int {
        switch self {
        case .addInteger, .subtractInteger, .multiplyInteger,
             .divideInteger, .quotientInteger, .remainderInteger, .modInteger,
             .equalsInteger, .lessThanInteger, .lessThanEqualsInteger:
            return 2
        case .appendByteString, .equalsByteString, .lessThanByteString, .lessThanEqualsByteString,
             .consByteString, .indexByteString:
            return 2
        case .sliceByteString:
            return 3
        case .lengthOfByteString:
            return 1
        case .sha2_256, .sha3_256, .blake2b_256, .blake2b_224, .keccak_256, .ripemd_160:
            return 1
        case .verifyEd25519Signature, .verifyEcdsaSecp256k1Signature, .verifySchnorrSecp256k1Signature:
            return 3
        case .appendString, .equalsString:
            return 2
        case .encodeUtf8, .decodeUtf8:
            return 1
        case .ifThenElse:
            return 3
        case .chooseUnit:
            return 2
        case .trace:
            return 2
        case .fstPair, .sndPair:
            return 1
        case .chooseList:
            return 3
        case .mkCons:
            return 2
        case .headList, .tailList, .nullList:
            return 1
        case .chooseData:
            return 6
        case .constrData:
            return 2
        case .iData, .bData:
            return 1
        case .mapData, .listData, .unConstrData, .unMapData, .unListData, .unIData, .unBData:
            return 1
        case .equalsData, .mkPairData:
            return 2
        case .mkNilData, .mkNilPairData:
            return 1
        case .serialiseData:
            return 1
        case .bls12_381_G1_add, .bls12_381_G1_equal:
            return 2
        case .bls12_381_G1_neg, .bls12_381_G1_compress, .bls12_381_G1_uncompress:
            return 1
        case .bls12_381_G1_scalarMul:
            return 2
        case .bls12_381_G1_hashToGroup:
            return 2
        case .bls12_381_G2_add, .bls12_381_G2_equal:
            return 2
        case .bls12_381_G2_neg, .bls12_381_G2_compress, .bls12_381_G2_uncompress:
            return 1
        case .bls12_381_G2_scalarMul:
            return 2
        case .bls12_381_G2_hashToGroup:
            return 2
        case .bls12_381_millerLoop:
            return 2
        case .bls12_381_mulMlResult:
            return 2
        case .bls12_381_finalVerify:
            return 2
        case .integerToByteString:
            return 3
        case .byteStringToInteger:
            return 2
        case .andByteString, .orByteString, .xorByteString:
            return 3
        case .complementByteString:
            return 1
        case .readBit:
            return 2
        case .writeBits:
            return 3
        case .replicateByte:
            return 2
        case .shiftByteString, .rotateByteString:
            return 2
        case .countSetBits, .findFirstSetBit:
            return 1
        }
    }

    /// Number of `force` applications required before arguments can be supplied.
    public var forceCount: Int {
        switch self {
        case .ifThenElse, .chooseUnit, .trace, .mkCons, .headList, .tailList, .nullList, .chooseData:
            return 1
        case .fstPair, .sndPair, .chooseList:
            return 2
        default:
            return 0
        }
    }
}
