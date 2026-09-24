import Foundation

// Generated from Plutus's `builtinCostModel{A,C}.json`, which declare the
// *shape* of every builtin's cost function. The shapes are fixed per language
// version; the coefficients come from the chain's protocol parameters, so this
// table only says which named parameter feeds which slot.
//
// Variant A backs PlutusV1/V2 and variant C backs PlutusV3. They are not
// interchangeable: `modInteger`, `multiplyInteger`, `remainderInteger` and
// `verifyEd25519Signature` are priced by different formulas, which is why the
// V3 parameter list carries `modInteger-cpu-arguments-model-arguments-c00`
// while V1/V2 carry `...-intercept` and `...-slope`.

extension CostModel {

    /// Builtin costing functions for PlutusV1 and PlutusV2 (semantics variant A).
    static func builtinCostsVariantA(_ p: (String) -> Int64) -> [DefaultFunction: BuiltinCostingFunction] {
        [
        .addInteger: BuiltinCostingFunction(
            cpu: .maxSize(intercept: p("addInteger-cpu-arguments-intercept"), slope: p("addInteger-cpu-arguments-slope")),
            memory: .maxSize(intercept: p("addInteger-memory-arguments-intercept"), slope: p("addInteger-memory-arguments-slope"))
        ),
        .andByteString: BuiltinCostingFunction(
            cpu: .linearInYAndZ(intercept: p("andByteString-cpu-arguments-intercept"), slopeY: p("andByteString-cpu-arguments-slope1"), slopeZ: p("andByteString-cpu-arguments-slope2")),
            memory: .linearInMaxYZ(intercept: p("andByteString-memory-arguments-intercept"), slope: p("andByteString-memory-arguments-slope"))
        ),
        .appendByteString: BuiltinCostingFunction(
            cpu: .addedSizes(intercept: p("appendByteString-cpu-arguments-intercept"), slope: p("appendByteString-cpu-arguments-slope")),
            memory: .addedSizes(intercept: p("appendByteString-memory-arguments-intercept"), slope: p("appendByteString-memory-arguments-slope"))
        ),
        .appendString: BuiltinCostingFunction(
            cpu: .addedSizes(intercept: p("appendString-cpu-arguments-intercept"), slope: p("appendString-cpu-arguments-slope")),
            memory: .addedSizes(intercept: p("appendString-memory-arguments-intercept"), slope: p("appendString-memory-arguments-slope"))
        ),
        .bData: BuiltinCostingFunction(
            cpu: .constant(p("bData-cpu-arguments")),
            memory: .constant(p("bData-memory-arguments"))
        ),
        .blake2b_224: BuiltinCostingFunction(
            cpu: .linearInX(intercept: p("blake2b_224-cpu-arguments-intercept"), slope: p("blake2b_224-cpu-arguments-slope")),
            memory: .constant(p("blake2b_224-memory-arguments"))
        ),
        .blake2b_256: BuiltinCostingFunction(
            cpu: .linearInX(intercept: p("blake2b_256-cpu-arguments-intercept"), slope: p("blake2b_256-cpu-arguments-slope")),
            memory: .constant(p("blake2b_256-memory-arguments"))
        ),
        .bls12_381_G1_add: BuiltinCostingFunction(
            cpu: .constant(p("bls12_381_G1_add-cpu-arguments")),
            memory: .constant(p("bls12_381_G1_add-memory-arguments"))
        ),
        .bls12_381_G1_compress: BuiltinCostingFunction(
            cpu: .constant(p("bls12_381_G1_compress-cpu-arguments")),
            memory: .constant(p("bls12_381_G1_compress-memory-arguments"))
        ),
        .bls12_381_G1_equal: BuiltinCostingFunction(
            cpu: .constant(p("bls12_381_G1_equal-cpu-arguments")),
            memory: .constant(p("bls12_381_G1_equal-memory-arguments"))
        ),
        .bls12_381_G1_hashToGroup: BuiltinCostingFunction(
            cpu: .linearInX(intercept: p("bls12_381_G1_hashToGroup-cpu-arguments-intercept"), slope: p("bls12_381_G1_hashToGroup-cpu-arguments-slope")),
            memory: .constant(p("bls12_381_G1_hashToGroup-memory-arguments"))
        ),
        .bls12_381_G1_neg: BuiltinCostingFunction(
            cpu: .constant(p("bls12_381_G1_neg-cpu-arguments")),
            memory: .constant(p("bls12_381_G1_neg-memory-arguments"))
        ),
        .bls12_381_G1_scalarMul: BuiltinCostingFunction(
            cpu: .linearInX(intercept: p("bls12_381_G1_scalarMul-cpu-arguments-intercept"), slope: p("bls12_381_G1_scalarMul-cpu-arguments-slope")),
            memory: .constant(p("bls12_381_G1_scalarMul-memory-arguments"))
        ),
        .bls12_381_G1_uncompress: BuiltinCostingFunction(
            cpu: .constant(p("bls12_381_G1_uncompress-cpu-arguments")),
            memory: .constant(p("bls12_381_G1_uncompress-memory-arguments"))
        ),
        .bls12_381_G2_add: BuiltinCostingFunction(
            cpu: .constant(p("bls12_381_G2_add-cpu-arguments")),
            memory: .constant(p("bls12_381_G2_add-memory-arguments"))
        ),
        .bls12_381_G2_compress: BuiltinCostingFunction(
            cpu: .constant(p("bls12_381_G2_compress-cpu-arguments")),
            memory: .constant(p("bls12_381_G2_compress-memory-arguments"))
        ),
        .bls12_381_G2_equal: BuiltinCostingFunction(
            cpu: .constant(p("bls12_381_G2_equal-cpu-arguments")),
            memory: .constant(p("bls12_381_G2_equal-memory-arguments"))
        ),
        .bls12_381_G2_hashToGroup: BuiltinCostingFunction(
            cpu: .linearInX(intercept: p("bls12_381_G2_hashToGroup-cpu-arguments-intercept"), slope: p("bls12_381_G2_hashToGroup-cpu-arguments-slope")),
            memory: .constant(p("bls12_381_G2_hashToGroup-memory-arguments"))
        ),
        .bls12_381_G2_neg: BuiltinCostingFunction(
            cpu: .constant(p("bls12_381_G2_neg-cpu-arguments")),
            memory: .constant(p("bls12_381_G2_neg-memory-arguments"))
        ),
        .bls12_381_G2_scalarMul: BuiltinCostingFunction(
            cpu: .linearInX(intercept: p("bls12_381_G2_scalarMul-cpu-arguments-intercept"), slope: p("bls12_381_G2_scalarMul-cpu-arguments-slope")),
            memory: .constant(p("bls12_381_G2_scalarMul-memory-arguments"))
        ),
        .bls12_381_G2_uncompress: BuiltinCostingFunction(
            cpu: .constant(p("bls12_381_G2_uncompress-cpu-arguments")),
            memory: .constant(p("bls12_381_G2_uncompress-memory-arguments"))
        ),
        .bls12_381_finalVerify: BuiltinCostingFunction(
            cpu: .constant(p("bls12_381_finalVerify-cpu-arguments")),
            memory: .constant(p("bls12_381_finalVerify-memory-arguments"))
        ),
        .bls12_381_millerLoop: BuiltinCostingFunction(
            cpu: .constant(p("bls12_381_millerLoop-cpu-arguments")),
            memory: .constant(p("bls12_381_millerLoop-memory-arguments"))
        ),
        .bls12_381_mulMlResult: BuiltinCostingFunction(
            cpu: .constant(p("bls12_381_mulMlResult-cpu-arguments")),
            memory: .constant(p("bls12_381_mulMlResult-memory-arguments"))
        ),
        .byteStringToInteger: BuiltinCostingFunction(
            cpu: .quadraticInY(c0: p("byteStringToInteger-cpu-arguments-c0"), c1: p("byteStringToInteger-cpu-arguments-c1"), c2: p("byteStringToInteger-cpu-arguments-c2")),
            memory: .linearInY(intercept: p("byteStringToInteger-memory-arguments-intercept"), slope: p("byteStringToInteger-memory-arguments-slope"))
        ),
        .chooseData: BuiltinCostingFunction(
            cpu: .constant(p("chooseData-cpu-arguments")),
            memory: .constant(p("chooseData-memory-arguments"))
        ),
        .chooseList: BuiltinCostingFunction(
            cpu: .constant(p("chooseList-cpu-arguments")),
            memory: .constant(p("chooseList-memory-arguments"))
        ),
        .chooseUnit: BuiltinCostingFunction(
            cpu: .constant(p("chooseUnit-cpu-arguments")),
            memory: .constant(p("chooseUnit-memory-arguments"))
        ),
        .complementByteString: BuiltinCostingFunction(
            cpu: .linearInX(intercept: p("complementByteString-cpu-arguments-intercept"), slope: p("complementByteString-cpu-arguments-slope")),
            memory: .linearInX(intercept: p("complementByteString-memory-arguments-intercept"), slope: p("complementByteString-memory-arguments-slope"))
        ),
        .consByteString: BuiltinCostingFunction(
            cpu: .linearInY(intercept: p("consByteString-cpu-arguments-intercept"), slope: p("consByteString-cpu-arguments-slope")),
            memory: .addedSizes(intercept: p("consByteString-memory-arguments-intercept"), slope: p("consByteString-memory-arguments-slope"))
        ),
        .constrData: BuiltinCostingFunction(
            cpu: .constant(p("constrData-cpu-arguments")),
            memory: .constant(p("constrData-memory-arguments"))
        ),
        .countSetBits: BuiltinCostingFunction(
            cpu: .linearInX(intercept: p("countSetBits-cpu-arguments-intercept"), slope: p("countSetBits-cpu-arguments-slope")),
            memory: .constant(p("countSetBits-memory-arguments"))
        ),
        .decodeUtf8: BuiltinCostingFunction(
            cpu: .linearInX(intercept: p("decodeUtf8-cpu-arguments-intercept"), slope: p("decodeUtf8-cpu-arguments-slope")),
            memory: .linearInX(intercept: p("decodeUtf8-memory-arguments-intercept"), slope: p("decodeUtf8-memory-arguments-slope"))
        ),
        .divideInteger: BuiltinCostingFunction(
            cpu: .constAboveDiagonal(constant: p("divideInteger-cpu-arguments-constant"), model: .multipliedSizes(intercept: p("divideInteger-cpu-arguments-model-arguments-intercept"), slope: p("divideInteger-cpu-arguments-model-arguments-slope"))),
            memory: .subtractedSizes(intercept: p("divideInteger-memory-arguments-intercept"), slope: p("divideInteger-memory-arguments-slope"), minimum: p("divideInteger-memory-arguments-minimum"))
        ),
        .encodeUtf8: BuiltinCostingFunction(
            cpu: .linearInX(intercept: p("encodeUtf8-cpu-arguments-intercept"), slope: p("encodeUtf8-cpu-arguments-slope")),
            memory: .linearInX(intercept: p("encodeUtf8-memory-arguments-intercept"), slope: p("encodeUtf8-memory-arguments-slope"))
        ),
        .equalsByteString: BuiltinCostingFunction(
            cpu: .linearOnDiagonal(constant: p("equalsByteString-cpu-arguments-constant"), intercept: p("equalsByteString-cpu-arguments-intercept"), slope: p("equalsByteString-cpu-arguments-slope")),
            memory: .constant(p("equalsByteString-memory-arguments"))
        ),
        .equalsData: BuiltinCostingFunction(
            cpu: .minSize(intercept: p("equalsData-cpu-arguments-intercept"), slope: p("equalsData-cpu-arguments-slope")),
            memory: .constant(p("equalsData-memory-arguments"))
        ),
        .equalsInteger: BuiltinCostingFunction(
            cpu: .minSize(intercept: p("equalsInteger-cpu-arguments-intercept"), slope: p("equalsInteger-cpu-arguments-slope")),
            memory: .constant(p("equalsInteger-memory-arguments"))
        ),
        .equalsString: BuiltinCostingFunction(
            cpu: .linearOnDiagonal(constant: p("equalsString-cpu-arguments-constant"), intercept: p("equalsString-cpu-arguments-intercept"), slope: p("equalsString-cpu-arguments-slope")),
            memory: .constant(p("equalsString-memory-arguments"))
        ),
        .findFirstSetBit: BuiltinCostingFunction(
            cpu: .linearInX(intercept: p("findFirstSetBit-cpu-arguments-intercept"), slope: p("findFirstSetBit-cpu-arguments-slope")),
            memory: .constant(p("findFirstSetBit-memory-arguments"))
        ),
        .fstPair: BuiltinCostingFunction(
            cpu: .constant(p("fstPair-cpu-arguments")),
            memory: .constant(p("fstPair-memory-arguments"))
        ),
        .headList: BuiltinCostingFunction(
            cpu: .constant(p("headList-cpu-arguments")),
            memory: .constant(p("headList-memory-arguments"))
        ),
        .iData: BuiltinCostingFunction(
            cpu: .constant(p("iData-cpu-arguments")),
            memory: .constant(p("iData-memory-arguments"))
        ),
        .ifThenElse: BuiltinCostingFunction(
            cpu: .constant(p("ifThenElse-cpu-arguments")),
            memory: .constant(p("ifThenElse-memory-arguments"))
        ),
        .indexByteString: BuiltinCostingFunction(
            cpu: .constant(p("indexByteString-cpu-arguments")),
            memory: .constant(p("indexByteString-memory-arguments"))
        ),
        .integerToByteString: BuiltinCostingFunction(
            cpu: .quadraticInZ(c0: p("integerToByteString-cpu-arguments-c0"), c1: p("integerToByteString-cpu-arguments-c1"), c2: p("integerToByteString-cpu-arguments-c2")),
            memory: .literalInYOrLinearInZ(intercept: p("integerToByteString-memory-arguments-intercept"), slope: p("integerToByteString-memory-arguments-slope"))
        ),
        .keccak_256: BuiltinCostingFunction(
            cpu: .linearInX(intercept: p("keccak_256-cpu-arguments-intercept"), slope: p("keccak_256-cpu-arguments-slope")),
            memory: .constant(p("keccak_256-memory-arguments"))
        ),
        .lengthOfByteString: BuiltinCostingFunction(
            cpu: .constant(p("lengthOfByteString-cpu-arguments")),
            memory: .constant(p("lengthOfByteString-memory-arguments"))
        ),
        .lessThanByteString: BuiltinCostingFunction(
            cpu: .minSize(intercept: p("lessThanByteString-cpu-arguments-intercept"), slope: p("lessThanByteString-cpu-arguments-slope")),
            memory: .constant(p("lessThanByteString-memory-arguments"))
        ),
        .lessThanEqualsByteString: BuiltinCostingFunction(
            cpu: .minSize(intercept: p("lessThanEqualsByteString-cpu-arguments-intercept"), slope: p("lessThanEqualsByteString-cpu-arguments-slope")),
            memory: .constant(p("lessThanEqualsByteString-memory-arguments"))
        ),
        .lessThanEqualsInteger: BuiltinCostingFunction(
            cpu: .minSize(intercept: p("lessThanEqualsInteger-cpu-arguments-intercept"), slope: p("lessThanEqualsInteger-cpu-arguments-slope")),
            memory: .constant(p("lessThanEqualsInteger-memory-arguments"))
        ),
        .lessThanInteger: BuiltinCostingFunction(
            cpu: .minSize(intercept: p("lessThanInteger-cpu-arguments-intercept"), slope: p("lessThanInteger-cpu-arguments-slope")),
            memory: .constant(p("lessThanInteger-memory-arguments"))
        ),
        .listData: BuiltinCostingFunction(
            cpu: .constant(p("listData-cpu-arguments")),
            memory: .constant(p("listData-memory-arguments"))
        ),
        .mapData: BuiltinCostingFunction(
            cpu: .constant(p("mapData-cpu-arguments")),
            memory: .constant(p("mapData-memory-arguments"))
        ),
        .mkCons: BuiltinCostingFunction(
            cpu: .constant(p("mkCons-cpu-arguments")),
            memory: .constant(p("mkCons-memory-arguments"))
        ),
        .mkNilData: BuiltinCostingFunction(
            cpu: .constant(p("mkNilData-cpu-arguments")),
            memory: .constant(p("mkNilData-memory-arguments"))
        ),
        .mkNilPairData: BuiltinCostingFunction(
            cpu: .constant(p("mkNilPairData-cpu-arguments")),
            memory: .constant(p("mkNilPairData-memory-arguments"))
        ),
        .mkPairData: BuiltinCostingFunction(
            cpu: .constant(p("mkPairData-cpu-arguments")),
            memory: .constant(p("mkPairData-memory-arguments"))
        ),
        .modInteger: BuiltinCostingFunction(
            cpu: .constAboveDiagonal(constant: p("modInteger-cpu-arguments-constant"), model: .multipliedSizes(intercept: p("modInteger-cpu-arguments-model-arguments-intercept"), slope: p("modInteger-cpu-arguments-model-arguments-slope"))),
            memory: .subtractedSizes(intercept: p("modInteger-memory-arguments-intercept"), slope: p("modInteger-memory-arguments-slope"), minimum: p("modInteger-memory-arguments-minimum"))
        ),
        .multiplyInteger: BuiltinCostingFunction(
            cpu: .addedSizes(intercept: p("multiplyInteger-cpu-arguments-intercept"), slope: p("multiplyInteger-cpu-arguments-slope")),
            memory: .addedSizes(intercept: p("multiplyInteger-memory-arguments-intercept"), slope: p("multiplyInteger-memory-arguments-slope"))
        ),
        .nullList: BuiltinCostingFunction(
            cpu: .constant(p("nullList-cpu-arguments")),
            memory: .constant(p("nullList-memory-arguments"))
        ),
        .orByteString: BuiltinCostingFunction(
            cpu: .linearInYAndZ(intercept: p("orByteString-cpu-arguments-intercept"), slopeY: p("orByteString-cpu-arguments-slope1"), slopeZ: p("orByteString-cpu-arguments-slope2")),
            memory: .linearInMaxYZ(intercept: p("orByteString-memory-arguments-intercept"), slope: p("orByteString-memory-arguments-slope"))
        ),
        .quotientInteger: BuiltinCostingFunction(
            cpu: .constAboveDiagonal(constant: p("quotientInteger-cpu-arguments-constant"), model: .multipliedSizes(intercept: p("quotientInteger-cpu-arguments-model-arguments-intercept"), slope: p("quotientInteger-cpu-arguments-model-arguments-slope"))),
            memory: .subtractedSizes(intercept: p("quotientInteger-memory-arguments-intercept"), slope: p("quotientInteger-memory-arguments-slope"), minimum: p("quotientInteger-memory-arguments-minimum"))
        ),
        .readBit: BuiltinCostingFunction(
            cpu: .constant(p("readBit-cpu-arguments")),
            memory: .constant(p("readBit-memory-arguments"))
        ),
        .remainderInteger: BuiltinCostingFunction(
            cpu: .constAboveDiagonal(constant: p("remainderInteger-cpu-arguments-constant"), model: .multipliedSizes(intercept: p("remainderInteger-cpu-arguments-model-arguments-intercept"), slope: p("remainderInteger-cpu-arguments-model-arguments-slope"))),
            memory: .subtractedSizes(intercept: p("remainderInteger-memory-arguments-intercept"), slope: p("remainderInteger-memory-arguments-slope"), minimum: p("remainderInteger-memory-arguments-minimum"))
        ),
        .replicateByte: BuiltinCostingFunction(
            cpu: .linearInX(intercept: p("replicateByte-cpu-arguments-intercept"), slope: p("replicateByte-cpu-arguments-slope")),
            memory: .linearInX(intercept: p("replicateByte-memory-arguments-intercept"), slope: p("replicateByte-memory-arguments-slope"))
        ),
        .ripemd_160: BuiltinCostingFunction(
            cpu: .linearInX(intercept: p("ripemd_160-cpu-arguments-intercept"), slope: p("ripemd_160-cpu-arguments-slope")),
            memory: .constant(p("ripemd_160-memory-arguments"))
        ),
        .rotateByteString: BuiltinCostingFunction(
            cpu: .linearInX(intercept: p("rotateByteString-cpu-arguments-intercept"), slope: p("rotateByteString-cpu-arguments-slope")),
            memory: .linearInX(intercept: p("rotateByteString-memory-arguments-intercept"), slope: p("rotateByteString-memory-arguments-slope"))
        ),
        .serialiseData: BuiltinCostingFunction(
            cpu: .linearInX(intercept: p("serialiseData-cpu-arguments-intercept"), slope: p("serialiseData-cpu-arguments-slope")),
            memory: .linearInX(intercept: p("serialiseData-memory-arguments-intercept"), slope: p("serialiseData-memory-arguments-slope"))
        ),
        .sha2_256: BuiltinCostingFunction(
            cpu: .linearInX(intercept: p("sha2_256-cpu-arguments-intercept"), slope: p("sha2_256-cpu-arguments-slope")),
            memory: .constant(p("sha2_256-memory-arguments"))
        ),
        .sha3_256: BuiltinCostingFunction(
            cpu: .linearInX(intercept: p("sha3_256-cpu-arguments-intercept"), slope: p("sha3_256-cpu-arguments-slope")),
            memory: .constant(p("sha3_256-memory-arguments"))
        ),
        .shiftByteString: BuiltinCostingFunction(
            cpu: .linearInX(intercept: p("shiftByteString-cpu-arguments-intercept"), slope: p("shiftByteString-cpu-arguments-slope")),
            memory: .linearInX(intercept: p("shiftByteString-memory-arguments-intercept"), slope: p("shiftByteString-memory-arguments-slope"))
        ),
        .sliceByteString: BuiltinCostingFunction(
            cpu: .linearInZ(intercept: p("sliceByteString-cpu-arguments-intercept"), slope: p("sliceByteString-cpu-arguments-slope")),
            memory: .linearInZ(intercept: p("sliceByteString-memory-arguments-intercept"), slope: p("sliceByteString-memory-arguments-slope"))
        ),
        .sndPair: BuiltinCostingFunction(
            cpu: .constant(p("sndPair-cpu-arguments")),
            memory: .constant(p("sndPair-memory-arguments"))
        ),
        .subtractInteger: BuiltinCostingFunction(
            cpu: .maxSize(intercept: p("subtractInteger-cpu-arguments-intercept"), slope: p("subtractInteger-cpu-arguments-slope")),
            memory: .maxSize(intercept: p("subtractInteger-memory-arguments-intercept"), slope: p("subtractInteger-memory-arguments-slope"))
        ),
        .tailList: BuiltinCostingFunction(
            cpu: .constant(p("tailList-cpu-arguments")),
            memory: .constant(p("tailList-memory-arguments"))
        ),
        .trace: BuiltinCostingFunction(
            cpu: .constant(p("trace-cpu-arguments")),
            memory: .constant(p("trace-memory-arguments"))
        ),
        .unBData: BuiltinCostingFunction(
            cpu: .constant(p("unBData-cpu-arguments")),
            memory: .constant(p("unBData-memory-arguments"))
        ),
        .unConstrData: BuiltinCostingFunction(
            cpu: .constant(p("unConstrData-cpu-arguments")),
            memory: .constant(p("unConstrData-memory-arguments"))
        ),
        .unIData: BuiltinCostingFunction(
            cpu: .constant(p("unIData-cpu-arguments")),
            memory: .constant(p("unIData-memory-arguments"))
        ),
        .unListData: BuiltinCostingFunction(
            cpu: .constant(p("unListData-cpu-arguments")),
            memory: .constant(p("unListData-memory-arguments"))
        ),
        .unMapData: BuiltinCostingFunction(
            cpu: .constant(p("unMapData-cpu-arguments")),
            memory: .constant(p("unMapData-memory-arguments"))
        ),
        .verifyEcdsaSecp256k1Signature: BuiltinCostingFunction(
            cpu: .constant(p("verifyEcdsaSecp256k1Signature-cpu-arguments")),
            memory: .constant(p("verifyEcdsaSecp256k1Signature-memory-arguments"))
        ),
        .verifyEd25519Signature: BuiltinCostingFunction(
            cpu: .linearInZ(intercept: p("verifyEd25519Signature-cpu-arguments-intercept"), slope: p("verifyEd25519Signature-cpu-arguments-slope")),
            memory: .constant(p("verifyEd25519Signature-memory-arguments"))
        ),
        .verifySchnorrSecp256k1Signature: BuiltinCostingFunction(
            cpu: .linearInY(intercept: p("verifySchnorrSecp256k1Signature-cpu-arguments-intercept"), slope: p("verifySchnorrSecp256k1Signature-cpu-arguments-slope")),
            memory: .constant(p("verifySchnorrSecp256k1Signature-memory-arguments"))
        ),
        .writeBits: BuiltinCostingFunction(
            cpu: .linearInY(intercept: p("writeBits-cpu-arguments-intercept"), slope: p("writeBits-cpu-arguments-slope")),
            memory: .linearInX(intercept: p("writeBits-memory-arguments-intercept"), slope: p("writeBits-memory-arguments-slope"))
        ),
        .xorByteString: BuiltinCostingFunction(
            cpu: .linearInYAndZ(intercept: p("xorByteString-cpu-arguments-intercept"), slopeY: p("xorByteString-cpu-arguments-slope1"), slopeZ: p("xorByteString-cpu-arguments-slope2")),
            memory: .linearInMaxYZ(intercept: p("xorByteString-memory-arguments-intercept"), slope: p("xorByteString-memory-arguments-slope"))
        ),
        ]
    }

    /// Builtin costing functions for PlutusV3 (semantics variant C).
    /// Variant B: what PlutusV1 and V2 are priced by from the Chang hard fork
    /// (major protocol version 9) onwards.
    ///
    /// It is variant A with two cpu formulas changed. `multiplyInteger` moves from
    /// the sum of its argument sizes to their product, and
    /// `verifyEd25519Signature` from the size of the signature to the size of the
    /// message. Pricing a V1 or V2 script with variant A on a Chang-or-later chain
    /// overcharges every `multiplyInteger` by one slope — the difference that
    /// showed up as a flat 4,152 steps on a mainnet withdrawal script.
    static func builtinCostsVariantB(_ p: (String) -> Int64) -> [DefaultFunction: BuiltinCostingFunction] {
        var table = builtinCostsVariantA(p)
        table[.multiplyInteger] = BuiltinCostingFunction(
            cpu: .multipliedSizes(
                intercept: p("multiplyInteger-cpu-arguments-intercept"),
                slope: p("multiplyInteger-cpu-arguments-slope")
            ),
            memory: .addedSizes(
                intercept: p("multiplyInteger-memory-arguments-intercept"),
                slope: p("multiplyInteger-memory-arguments-slope")
            )
        )
        table[.verifyEd25519Signature] = BuiltinCostingFunction(
            cpu: .linearInY(
                intercept: p("verifyEd25519Signature-cpu-arguments-intercept"),
                slope: p("verifyEd25519Signature-cpu-arguments-slope")
            ),
            memory: .constant(p("verifyEd25519Signature-memory-arguments"))
        )
        return table
    }

    /// The costing functions for a language at a protocol version.
    ///
    /// Plutus calls these builtin *semantics variants*, and which one applies
    /// depends on both the language and the protocol version. V1 and V2 used
    /// variant A up to the Chang hard fork and variant B since; V3, which only
    /// exists from Chang, uses variant C.
    ///
    /// Plutus also defines variants D and E for a later hard fork, changing how
    /// `divideInteger` and `modInteger` are priced. Those are deliberately not
    /// used here: mainnet at major version 11 still prices V3 by variant C, which
    /// a transaction calling `divideInteger` nine times and `modInteger` nineteen
    /// times confirms to the step. Adding D and E before a chain uses them would
    /// make every such budget wrong.
    static func builtinCosts(
        version: PlutusVersion,
        protocolMajorVersion: Int,
        _ p: (String) -> Int64
    ) -> [DefaultFunction: BuiltinCostingFunction] {
        switch version {
            case .v3:
                return builtinCostsVariantC(p)
            case .v1, .v2:
                return protocolMajorVersion < 9
                    ? builtinCostsVariantA(p)
                    : builtinCostsVariantB(p)
        }
    }

    static func builtinCostsVariantC(_ p: (String) -> Int64) -> [DefaultFunction: BuiltinCostingFunction] {
        [
        .addInteger: BuiltinCostingFunction(
            cpu: .maxSize(intercept: p("addInteger-cpu-arguments-intercept"), slope: p("addInteger-cpu-arguments-slope")),
            memory: .maxSize(intercept: p("addInteger-memory-arguments-intercept"), slope: p("addInteger-memory-arguments-slope"))
        ),
        .andByteString: BuiltinCostingFunction(
            cpu: .linearInYAndZ(intercept: p("andByteString-cpu-arguments-intercept"), slopeY: p("andByteString-cpu-arguments-slope1"), slopeZ: p("andByteString-cpu-arguments-slope2")),
            memory: .linearInMaxYZ(intercept: p("andByteString-memory-arguments-intercept"), slope: p("andByteString-memory-arguments-slope"))
        ),
        .appendByteString: BuiltinCostingFunction(
            cpu: .addedSizes(intercept: p("appendByteString-cpu-arguments-intercept"), slope: p("appendByteString-cpu-arguments-slope")),
            memory: .addedSizes(intercept: p("appendByteString-memory-arguments-intercept"), slope: p("appendByteString-memory-arguments-slope"))
        ),
        .appendString: BuiltinCostingFunction(
            cpu: .addedSizes(intercept: p("appendString-cpu-arguments-intercept"), slope: p("appendString-cpu-arguments-slope")),
            memory: .addedSizes(intercept: p("appendString-memory-arguments-intercept"), slope: p("appendString-memory-arguments-slope"))
        ),
        .bData: BuiltinCostingFunction(
            cpu: .constant(p("bData-cpu-arguments")),
            memory: .constant(p("bData-memory-arguments"))
        ),
        .blake2b_224: BuiltinCostingFunction(
            cpu: .linearInX(intercept: p("blake2b_224-cpu-arguments-intercept"), slope: p("blake2b_224-cpu-arguments-slope")),
            memory: .constant(p("blake2b_224-memory-arguments"))
        ),
        .blake2b_256: BuiltinCostingFunction(
            cpu: .linearInX(intercept: p("blake2b_256-cpu-arguments-intercept"), slope: p("blake2b_256-cpu-arguments-slope")),
            memory: .constant(p("blake2b_256-memory-arguments"))
        ),
        .bls12_381_G1_add: BuiltinCostingFunction(
            cpu: .constant(p("bls12_381_G1_add-cpu-arguments")),
            memory: .constant(p("bls12_381_G1_add-memory-arguments"))
        ),
        .bls12_381_G1_compress: BuiltinCostingFunction(
            cpu: .constant(p("bls12_381_G1_compress-cpu-arguments")),
            memory: .constant(p("bls12_381_G1_compress-memory-arguments"))
        ),
        .bls12_381_G1_equal: BuiltinCostingFunction(
            cpu: .constant(p("bls12_381_G1_equal-cpu-arguments")),
            memory: .constant(p("bls12_381_G1_equal-memory-arguments"))
        ),
        .bls12_381_G1_hashToGroup: BuiltinCostingFunction(
            cpu: .linearInX(intercept: p("bls12_381_G1_hashToGroup-cpu-arguments-intercept"), slope: p("bls12_381_G1_hashToGroup-cpu-arguments-slope")),
            memory: .constant(p("bls12_381_G1_hashToGroup-memory-arguments"))
        ),
        .bls12_381_G1_neg: BuiltinCostingFunction(
            cpu: .constant(p("bls12_381_G1_neg-cpu-arguments")),
            memory: .constant(p("bls12_381_G1_neg-memory-arguments"))
        ),
        .bls12_381_G1_scalarMul: BuiltinCostingFunction(
            cpu: .linearInX(intercept: p("bls12_381_G1_scalarMul-cpu-arguments-intercept"), slope: p("bls12_381_G1_scalarMul-cpu-arguments-slope")),
            memory: .constant(p("bls12_381_G1_scalarMul-memory-arguments"))
        ),
        .bls12_381_G1_uncompress: BuiltinCostingFunction(
            cpu: .constant(p("bls12_381_G1_uncompress-cpu-arguments")),
            memory: .constant(p("bls12_381_G1_uncompress-memory-arguments"))
        ),
        .bls12_381_G2_add: BuiltinCostingFunction(
            cpu: .constant(p("bls12_381_G2_add-cpu-arguments")),
            memory: .constant(p("bls12_381_G2_add-memory-arguments"))
        ),
        .bls12_381_G2_compress: BuiltinCostingFunction(
            cpu: .constant(p("bls12_381_G2_compress-cpu-arguments")),
            memory: .constant(p("bls12_381_G2_compress-memory-arguments"))
        ),
        .bls12_381_G2_equal: BuiltinCostingFunction(
            cpu: .constant(p("bls12_381_G2_equal-cpu-arguments")),
            memory: .constant(p("bls12_381_G2_equal-memory-arguments"))
        ),
        .bls12_381_G2_hashToGroup: BuiltinCostingFunction(
            cpu: .linearInX(intercept: p("bls12_381_G2_hashToGroup-cpu-arguments-intercept"), slope: p("bls12_381_G2_hashToGroup-cpu-arguments-slope")),
            memory: .constant(p("bls12_381_G2_hashToGroup-memory-arguments"))
        ),
        .bls12_381_G2_neg: BuiltinCostingFunction(
            cpu: .constant(p("bls12_381_G2_neg-cpu-arguments")),
            memory: .constant(p("bls12_381_G2_neg-memory-arguments"))
        ),
        .bls12_381_G2_scalarMul: BuiltinCostingFunction(
            cpu: .linearInX(intercept: p("bls12_381_G2_scalarMul-cpu-arguments-intercept"), slope: p("bls12_381_G2_scalarMul-cpu-arguments-slope")),
            memory: .constant(p("bls12_381_G2_scalarMul-memory-arguments"))
        ),
        .bls12_381_G2_uncompress: BuiltinCostingFunction(
            cpu: .constant(p("bls12_381_G2_uncompress-cpu-arguments")),
            memory: .constant(p("bls12_381_G2_uncompress-memory-arguments"))
        ),
        .bls12_381_finalVerify: BuiltinCostingFunction(
            cpu: .constant(p("bls12_381_finalVerify-cpu-arguments")),
            memory: .constant(p("bls12_381_finalVerify-memory-arguments"))
        ),
        .bls12_381_millerLoop: BuiltinCostingFunction(
            cpu: .constant(p("bls12_381_millerLoop-cpu-arguments")),
            memory: .constant(p("bls12_381_millerLoop-memory-arguments"))
        ),
        .bls12_381_mulMlResult: BuiltinCostingFunction(
            cpu: .constant(p("bls12_381_mulMlResult-cpu-arguments")),
            memory: .constant(p("bls12_381_mulMlResult-memory-arguments"))
        ),
        .byteStringToInteger: BuiltinCostingFunction(
            cpu: .quadraticInY(c0: p("byteStringToInteger-cpu-arguments-c0"), c1: p("byteStringToInteger-cpu-arguments-c1"), c2: p("byteStringToInteger-cpu-arguments-c2")),
            memory: .linearInY(intercept: p("byteStringToInteger-memory-arguments-intercept"), slope: p("byteStringToInteger-memory-arguments-slope"))
        ),
        .chooseData: BuiltinCostingFunction(
            cpu: .constant(p("chooseData-cpu-arguments")),
            memory: .constant(p("chooseData-memory-arguments"))
        ),
        .chooseList: BuiltinCostingFunction(
            cpu: .constant(p("chooseList-cpu-arguments")),
            memory: .constant(p("chooseList-memory-arguments"))
        ),
        .chooseUnit: BuiltinCostingFunction(
            cpu: .constant(p("chooseUnit-cpu-arguments")),
            memory: .constant(p("chooseUnit-memory-arguments"))
        ),
        .complementByteString: BuiltinCostingFunction(
            cpu: .linearInX(intercept: p("complementByteString-cpu-arguments-intercept"), slope: p("complementByteString-cpu-arguments-slope")),
            memory: .linearInX(intercept: p("complementByteString-memory-arguments-intercept"), slope: p("complementByteString-memory-arguments-slope"))
        ),
        .consByteString: BuiltinCostingFunction(
            cpu: .linearInY(intercept: p("consByteString-cpu-arguments-intercept"), slope: p("consByteString-cpu-arguments-slope")),
            memory: .addedSizes(intercept: p("consByteString-memory-arguments-intercept"), slope: p("consByteString-memory-arguments-slope"))
        ),
        .constrData: BuiltinCostingFunction(
            cpu: .constant(p("constrData-cpu-arguments")),
            memory: .constant(p("constrData-memory-arguments"))
        ),
        .countSetBits: BuiltinCostingFunction(
            cpu: .linearInX(intercept: p("countSetBits-cpu-arguments-intercept"), slope: p("countSetBits-cpu-arguments-slope")),
            memory: .constant(p("countSetBits-memory-arguments"))
        ),
        .decodeUtf8: BuiltinCostingFunction(
            cpu: .linearInX(intercept: p("decodeUtf8-cpu-arguments-intercept"), slope: p("decodeUtf8-cpu-arguments-slope")),
            memory: .linearInX(intercept: p("decodeUtf8-memory-arguments-intercept"), slope: p("decodeUtf8-memory-arguments-slope"))
        ),
        .divideInteger: BuiltinCostingFunction(
            cpu: .constAboveDiagonal(constant: p("divideInteger-cpu-arguments-constant"), model: .quadraticInXAndY(.init(minimum: p("divideInteger-cpu-arguments-model-arguments-minimum"), c00: p("divideInteger-cpu-arguments-model-arguments-c00"), c10: p("divideInteger-cpu-arguments-model-arguments-c10"), c01: p("divideInteger-cpu-arguments-model-arguments-c01"), c20: p("divideInteger-cpu-arguments-model-arguments-c20"), c11: p("divideInteger-cpu-arguments-model-arguments-c11"), c02: p("divideInteger-cpu-arguments-model-arguments-c02")))),
            memory: .subtractedSizes(intercept: p("divideInteger-memory-arguments-intercept"), slope: p("divideInteger-memory-arguments-slope"), minimum: p("divideInteger-memory-arguments-minimum"))
        ),
        .encodeUtf8: BuiltinCostingFunction(
            cpu: .linearInX(intercept: p("encodeUtf8-cpu-arguments-intercept"), slope: p("encodeUtf8-cpu-arguments-slope")),
            memory: .linearInX(intercept: p("encodeUtf8-memory-arguments-intercept"), slope: p("encodeUtf8-memory-arguments-slope"))
        ),
        .equalsByteString: BuiltinCostingFunction(
            cpu: .linearOnDiagonal(constant: p("equalsByteString-cpu-arguments-constant"), intercept: p("equalsByteString-cpu-arguments-intercept"), slope: p("equalsByteString-cpu-arguments-slope")),
            memory: .constant(p("equalsByteString-memory-arguments"))
        ),
        .equalsData: BuiltinCostingFunction(
            cpu: .minSize(intercept: p("equalsData-cpu-arguments-intercept"), slope: p("equalsData-cpu-arguments-slope")),
            memory: .constant(p("equalsData-memory-arguments"))
        ),
        .equalsInteger: BuiltinCostingFunction(
            cpu: .minSize(intercept: p("equalsInteger-cpu-arguments-intercept"), slope: p("equalsInteger-cpu-arguments-slope")),
            memory: .constant(p("equalsInteger-memory-arguments"))
        ),
        .equalsString: BuiltinCostingFunction(
            cpu: .linearOnDiagonal(constant: p("equalsString-cpu-arguments-constant"), intercept: p("equalsString-cpu-arguments-intercept"), slope: p("equalsString-cpu-arguments-slope")),
            memory: .constant(p("equalsString-memory-arguments"))
        ),
        .findFirstSetBit: BuiltinCostingFunction(
            cpu: .linearInX(intercept: p("findFirstSetBit-cpu-arguments-intercept"), slope: p("findFirstSetBit-cpu-arguments-slope")),
            memory: .constant(p("findFirstSetBit-memory-arguments"))
        ),
        .fstPair: BuiltinCostingFunction(
            cpu: .constant(p("fstPair-cpu-arguments")),
            memory: .constant(p("fstPair-memory-arguments"))
        ),
        .headList: BuiltinCostingFunction(
            cpu: .constant(p("headList-cpu-arguments")),
            memory: .constant(p("headList-memory-arguments"))
        ),
        .iData: BuiltinCostingFunction(
            cpu: .constant(p("iData-cpu-arguments")),
            memory: .constant(p("iData-memory-arguments"))
        ),
        .ifThenElse: BuiltinCostingFunction(
            cpu: .constant(p("ifThenElse-cpu-arguments")),
            memory: .constant(p("ifThenElse-memory-arguments"))
        ),
        .indexByteString: BuiltinCostingFunction(
            cpu: .constant(p("indexByteString-cpu-arguments")),
            memory: .constant(p("indexByteString-memory-arguments"))
        ),
        .integerToByteString: BuiltinCostingFunction(
            cpu: .quadraticInZ(c0: p("integerToByteString-cpu-arguments-c0"), c1: p("integerToByteString-cpu-arguments-c1"), c2: p("integerToByteString-cpu-arguments-c2")),
            memory: .literalInYOrLinearInZ(intercept: p("integerToByteString-memory-arguments-intercept"), slope: p("integerToByteString-memory-arguments-slope"))
        ),
        .keccak_256: BuiltinCostingFunction(
            cpu: .linearInX(intercept: p("keccak_256-cpu-arguments-intercept"), slope: p("keccak_256-cpu-arguments-slope")),
            memory: .constant(p("keccak_256-memory-arguments"))
        ),
        .lengthOfByteString: BuiltinCostingFunction(
            cpu: .constant(p("lengthOfByteString-cpu-arguments")),
            memory: .constant(p("lengthOfByteString-memory-arguments"))
        ),
        .lessThanByteString: BuiltinCostingFunction(
            cpu: .minSize(intercept: p("lessThanByteString-cpu-arguments-intercept"), slope: p("lessThanByteString-cpu-arguments-slope")),
            memory: .constant(p("lessThanByteString-memory-arguments"))
        ),
        .lessThanEqualsByteString: BuiltinCostingFunction(
            cpu: .minSize(intercept: p("lessThanEqualsByteString-cpu-arguments-intercept"), slope: p("lessThanEqualsByteString-cpu-arguments-slope")),
            memory: .constant(p("lessThanEqualsByteString-memory-arguments"))
        ),
        .lessThanEqualsInteger: BuiltinCostingFunction(
            cpu: .minSize(intercept: p("lessThanEqualsInteger-cpu-arguments-intercept"), slope: p("lessThanEqualsInteger-cpu-arguments-slope")),
            memory: .constant(p("lessThanEqualsInteger-memory-arguments"))
        ),
        .lessThanInteger: BuiltinCostingFunction(
            cpu: .minSize(intercept: p("lessThanInteger-cpu-arguments-intercept"), slope: p("lessThanInteger-cpu-arguments-slope")),
            memory: .constant(p("lessThanInteger-memory-arguments"))
        ),
        .listData: BuiltinCostingFunction(
            cpu: .constant(p("listData-cpu-arguments")),
            memory: .constant(p("listData-memory-arguments"))
        ),
        .mapData: BuiltinCostingFunction(
            cpu: .constant(p("mapData-cpu-arguments")),
            memory: .constant(p("mapData-memory-arguments"))
        ),
        .mkCons: BuiltinCostingFunction(
            cpu: .constant(p("mkCons-cpu-arguments")),
            memory: .constant(p("mkCons-memory-arguments"))
        ),
        .mkNilData: BuiltinCostingFunction(
            cpu: .constant(p("mkNilData-cpu-arguments")),
            memory: .constant(p("mkNilData-memory-arguments"))
        ),
        .mkNilPairData: BuiltinCostingFunction(
            cpu: .constant(p("mkNilPairData-cpu-arguments")),
            memory: .constant(p("mkNilPairData-memory-arguments"))
        ),
        .mkPairData: BuiltinCostingFunction(
            cpu: .constant(p("mkPairData-cpu-arguments")),
            memory: .constant(p("mkPairData-memory-arguments"))
        ),
        .modInteger: BuiltinCostingFunction(
            cpu: .constAboveDiagonal(constant: p("modInteger-cpu-arguments-constant"), model: .quadraticInXAndY(.init(minimum: p("modInteger-cpu-arguments-model-arguments-minimum"), c00: p("modInteger-cpu-arguments-model-arguments-c00"), c10: p("modInteger-cpu-arguments-model-arguments-c10"), c01: p("modInteger-cpu-arguments-model-arguments-c01"), c20: p("modInteger-cpu-arguments-model-arguments-c20"), c11: p("modInteger-cpu-arguments-model-arguments-c11"), c02: p("modInteger-cpu-arguments-model-arguments-c02")))),
            memory: .linearInY(intercept: p("modInteger-memory-arguments-intercept"), slope: p("modInteger-memory-arguments-slope"))
        ),
        .multiplyInteger: BuiltinCostingFunction(
            cpu: .multipliedSizes(intercept: p("multiplyInteger-cpu-arguments-intercept"), slope: p("multiplyInteger-cpu-arguments-slope")),
            memory: .addedSizes(intercept: p("multiplyInteger-memory-arguments-intercept"), slope: p("multiplyInteger-memory-arguments-slope"))
        ),
        .nullList: BuiltinCostingFunction(
            cpu: .constant(p("nullList-cpu-arguments")),
            memory: .constant(p("nullList-memory-arguments"))
        ),
        .orByteString: BuiltinCostingFunction(
            cpu: .linearInYAndZ(intercept: p("orByteString-cpu-arguments-intercept"), slopeY: p("orByteString-cpu-arguments-slope1"), slopeZ: p("orByteString-cpu-arguments-slope2")),
            memory: .linearInMaxYZ(intercept: p("orByteString-memory-arguments-intercept"), slope: p("orByteString-memory-arguments-slope"))
        ),
        .quotientInteger: BuiltinCostingFunction(
            cpu: .constAboveDiagonal(constant: p("quotientInteger-cpu-arguments-constant"), model: .quadraticInXAndY(.init(minimum: p("quotientInteger-cpu-arguments-model-arguments-minimum"), c00: p("quotientInteger-cpu-arguments-model-arguments-c00"), c10: p("quotientInteger-cpu-arguments-model-arguments-c10"), c01: p("quotientInteger-cpu-arguments-model-arguments-c01"), c20: p("quotientInteger-cpu-arguments-model-arguments-c20"), c11: p("quotientInteger-cpu-arguments-model-arguments-c11"), c02: p("quotientInteger-cpu-arguments-model-arguments-c02")))),
            memory: .subtractedSizes(intercept: p("quotientInteger-memory-arguments-intercept"), slope: p("quotientInteger-memory-arguments-slope"), minimum: p("quotientInteger-memory-arguments-minimum"))
        ),
        .readBit: BuiltinCostingFunction(
            cpu: .constant(p("readBit-cpu-arguments")),
            memory: .constant(p("readBit-memory-arguments"))
        ),
        .remainderInteger: BuiltinCostingFunction(
            cpu: .constAboveDiagonal(constant: p("remainderInteger-cpu-arguments-constant"), model: .quadraticInXAndY(.init(minimum: p("remainderInteger-cpu-arguments-model-arguments-minimum"), c00: p("remainderInteger-cpu-arguments-model-arguments-c00"), c10: p("remainderInteger-cpu-arguments-model-arguments-c10"), c01: p("remainderInteger-cpu-arguments-model-arguments-c01"), c20: p("remainderInteger-cpu-arguments-model-arguments-c20"), c11: p("remainderInteger-cpu-arguments-model-arguments-c11"), c02: p("remainderInteger-cpu-arguments-model-arguments-c02")))),
            memory: .linearInY(intercept: p("remainderInteger-memory-arguments-intercept"), slope: p("remainderInteger-memory-arguments-slope"))
        ),
        .replicateByte: BuiltinCostingFunction(
            cpu: .linearInX(intercept: p("replicateByte-cpu-arguments-intercept"), slope: p("replicateByte-cpu-arguments-slope")),
            memory: .linearInX(intercept: p("replicateByte-memory-arguments-intercept"), slope: p("replicateByte-memory-arguments-slope"))
        ),
        .ripemd_160: BuiltinCostingFunction(
            cpu: .linearInX(intercept: p("ripemd_160-cpu-arguments-intercept"), slope: p("ripemd_160-cpu-arguments-slope")),
            memory: .constant(p("ripemd_160-memory-arguments"))
        ),
        .rotateByteString: BuiltinCostingFunction(
            cpu: .linearInX(intercept: p("rotateByteString-cpu-arguments-intercept"), slope: p("rotateByteString-cpu-arguments-slope")),
            memory: .linearInX(intercept: p("rotateByteString-memory-arguments-intercept"), slope: p("rotateByteString-memory-arguments-slope"))
        ),
        .serialiseData: BuiltinCostingFunction(
            cpu: .linearInX(intercept: p("serialiseData-cpu-arguments-intercept"), slope: p("serialiseData-cpu-arguments-slope")),
            memory: .linearInX(intercept: p("serialiseData-memory-arguments-intercept"), slope: p("serialiseData-memory-arguments-slope"))
        ),
        .sha2_256: BuiltinCostingFunction(
            cpu: .linearInX(intercept: p("sha2_256-cpu-arguments-intercept"), slope: p("sha2_256-cpu-arguments-slope")),
            memory: .constant(p("sha2_256-memory-arguments"))
        ),
        .sha3_256: BuiltinCostingFunction(
            cpu: .linearInX(intercept: p("sha3_256-cpu-arguments-intercept"), slope: p("sha3_256-cpu-arguments-slope")),
            memory: .constant(p("sha3_256-memory-arguments"))
        ),
        .shiftByteString: BuiltinCostingFunction(
            cpu: .linearInX(intercept: p("shiftByteString-cpu-arguments-intercept"), slope: p("shiftByteString-cpu-arguments-slope")),
            memory: .linearInX(intercept: p("shiftByteString-memory-arguments-intercept"), slope: p("shiftByteString-memory-arguments-slope"))
        ),
        .sliceByteString: BuiltinCostingFunction(
            cpu: .linearInZ(intercept: p("sliceByteString-cpu-arguments-intercept"), slope: p("sliceByteString-cpu-arguments-slope")),
            memory: .linearInZ(intercept: p("sliceByteString-memory-arguments-intercept"), slope: p("sliceByteString-memory-arguments-slope"))
        ),
        .sndPair: BuiltinCostingFunction(
            cpu: .constant(p("sndPair-cpu-arguments")),
            memory: .constant(p("sndPair-memory-arguments"))
        ),
        .subtractInteger: BuiltinCostingFunction(
            cpu: .maxSize(intercept: p("subtractInteger-cpu-arguments-intercept"), slope: p("subtractInteger-cpu-arguments-slope")),
            memory: .maxSize(intercept: p("subtractInteger-memory-arguments-intercept"), slope: p("subtractInteger-memory-arguments-slope"))
        ),
        .tailList: BuiltinCostingFunction(
            cpu: .constant(p("tailList-cpu-arguments")),
            memory: .constant(p("tailList-memory-arguments"))
        ),
        .trace: BuiltinCostingFunction(
            cpu: .constant(p("trace-cpu-arguments")),
            memory: .constant(p("trace-memory-arguments"))
        ),
        .unBData: BuiltinCostingFunction(
            cpu: .constant(p("unBData-cpu-arguments")),
            memory: .constant(p("unBData-memory-arguments"))
        ),
        .unConstrData: BuiltinCostingFunction(
            cpu: .constant(p("unConstrData-cpu-arguments")),
            memory: .constant(p("unConstrData-memory-arguments"))
        ),
        .unIData: BuiltinCostingFunction(
            cpu: .constant(p("unIData-cpu-arguments")),
            memory: .constant(p("unIData-memory-arguments"))
        ),
        .unListData: BuiltinCostingFunction(
            cpu: .constant(p("unListData-cpu-arguments")),
            memory: .constant(p("unListData-memory-arguments"))
        ),
        .unMapData: BuiltinCostingFunction(
            cpu: .constant(p("unMapData-cpu-arguments")),
            memory: .constant(p("unMapData-memory-arguments"))
        ),
        .verifyEcdsaSecp256k1Signature: BuiltinCostingFunction(
            cpu: .constant(p("verifyEcdsaSecp256k1Signature-cpu-arguments")),
            memory: .constant(p("verifyEcdsaSecp256k1Signature-memory-arguments"))
        ),
        .verifyEd25519Signature: BuiltinCostingFunction(
            cpu: .linearInY(intercept: p("verifyEd25519Signature-cpu-arguments-intercept"), slope: p("verifyEd25519Signature-cpu-arguments-slope")),
            memory: .constant(p("verifyEd25519Signature-memory-arguments"))
        ),
        .verifySchnorrSecp256k1Signature: BuiltinCostingFunction(
            cpu: .linearInY(intercept: p("verifySchnorrSecp256k1Signature-cpu-arguments-intercept"), slope: p("verifySchnorrSecp256k1Signature-cpu-arguments-slope")),
            memory: .constant(p("verifySchnorrSecp256k1Signature-memory-arguments"))
        ),
        .writeBits: BuiltinCostingFunction(
            cpu: .linearInY(intercept: p("writeBits-cpu-arguments-intercept"), slope: p("writeBits-cpu-arguments-slope")),
            memory: .linearInX(intercept: p("writeBits-memory-arguments-intercept"), slope: p("writeBits-memory-arguments-slope"))
        ),
        .xorByteString: BuiltinCostingFunction(
            cpu: .linearInYAndZ(intercept: p("xorByteString-cpu-arguments-intercept"), slopeY: p("xorByteString-cpu-arguments-slope1"), slopeZ: p("xorByteString-cpu-arguments-slope2")),
            memory: .linearInMaxYZ(intercept: p("xorByteString-memory-arguments-intercept"), slope: p("xorByteString-memory-arguments-slope"))
        ),
        ]
    }
}
