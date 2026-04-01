import Testing
import BigInt
import Foundation
@testable import SwiftCardanoUPLC

// MARK: — Integer Arithmetic

@Suite("Conformance: Integer Arithmetic")
struct IntegerArithmeticConformanceTests {
    @Test func addInteger1() throws {
        #expect(try evalInt("(program 1.0.0 [(builtin addInteger) (con integer 1) (con integer 1)])") == 2)
    }

    @Test func addInteger2() throws {
        #expect(try evalInt("(program 1.0.0 [(builtin addInteger) (con integer 0) (con integer 0)])") == 0)
    }

    @Test func addInteger3() throws {
        #expect(try evalInt("(program 1.0.0 [(builtin addInteger) (con integer -1) (con integer 1)])") == 0)
    }

    @Test func subtractInteger() throws {
        #expect(try evalInt("(program 1.0.0 [(builtin subtractInteger) (con integer 10) (con integer 3)])") == 7)
    }

    @Test func multiplyInteger() throws {
        #expect(try evalInt("(program 1.0.0 [(builtin multiplyInteger) (con integer 7) (con integer 6)])") == 42)
    }

    @Test func divideIntegerNegPos() throws {
        #expect(try evalInt("(program 1.0.0 [(builtin divideInteger) (con integer -503) (con integer 1777777777)])") == -1)
    }

    @Test func divideIntegerPosPos() throws {
        #expect(try evalInt("(program 1.0.0 [(builtin divideInteger) (con integer 7) (con integer 3)])") == 2)
    }

    @Test func divideIntegerNegNeg() throws {
        #expect(try evalInt("(program 1.0.0 [(builtin divideInteger) (con integer -7) (con integer -3)])") == 2)
    }

    @Test func divideIntegerPosNeg() throws {
        #expect(try evalInt("(program 1.0.0 [(builtin divideInteger) (con integer 7) (con integer -3)])") == -3)
    }

    @Test func divideIntegerByZero() {
        #expect(throws: (any Error).self) {
            try evalInt("(program 1.0.0 [(builtin divideInteger) (con integer 7) (con integer 0)])")
        }
    }

    @Test func modIntegerNegPos() throws {
        #expect(try evalInt("(program 1.0.0 [(builtin modInteger) (con integer -7) (con integer 3)])") == 2)
    }

    @Test func quotientInteger() throws {
        #expect(try evalInt("(program 1.0.0 [(builtin quotientInteger) (con integer -7) (con integer 3)])") == -2)
    }

    @Test func remainderInteger() throws {
        #expect(try evalInt("(program 1.0.0 [(builtin remainderInteger) (con integer -7) (con integer 3)])") == -1)
    }

    @Test func equalsInteger() throws {
        #expect(try evalBool("(program 1.0.0 [(builtin equalsInteger) (con integer 42) (con integer 42)])") == true)
    }

    @Test func equalsIntegerFalse() throws {
        #expect(try evalBool("(program 1.0.0 [(builtin equalsInteger) (con integer 42) (con integer 43)])") == false)
    }

    @Test func lessThanInteger() throws {
        #expect(try evalBool("(program 1.0.0 [(builtin lessThanInteger) (con integer 3) (con integer 7)])") == true)
    }

    @Test func lessThanEqualsInteger() throws {
        #expect(try evalBool("(program 1.0.0 [(builtin lessThanEqualsInteger) (con integer 3) (con integer 3)])") == true)
    }
}

// MARK: — ByteString Operations

@Suite("Conformance: ByteString")
struct ByteStringConformanceTests {
    @Test func appendByteString() throws {
        #expect(try evalBytesHex("(program 1.0.0 [(builtin appendByteString) (con bytestring #dead) (con bytestring #beef)])") == "deadbeef")
    }

    @Test func lengthOfByteString() throws {
        #expect(try evalInt("(program 1.0.0 [(builtin lengthOfByteString) (con bytestring #deadbeef)])") == 4)
    }

    @Test func indexByteString() throws {
        #expect(try evalInt("(program 1.0.0 [(builtin indexByteString) (con bytestring #deadbeef) (con integer 0)])") == 0xDE)
    }

    @Test func equalsByteString() throws {
        #expect(try evalBool("(program 1.0.0 [(builtin equalsByteString) (con bytestring #dead) (con bytestring #dead)])") == true)
    }

    @Test func equalsByteStringFalse() throws {
        #expect(try evalBool("(program 1.0.0 [(builtin equalsByteString) (con bytestring #dead) (con bytestring #beef)])") == false)
    }

    @Test func sliceByteString() throws {
        #expect(try evalBytesHex("(program 1.0.0 [(builtin sliceByteString) (con integer 1) (con integer 2) (con bytestring #deadbeef)])") == "adbe")
    }

    @Test func consByteString() throws {
        #expect(try evalBytesHex("(program 1.0.0 [(builtin consByteString) (con integer 255) (con bytestring #dead)])") == "ffdead")
    }

    @Test func lessThanByteString() throws {
        #expect(try evalBool("(program 1.0.0 [(builtin lessThanByteString) (con bytestring #00) (con bytestring #01)])") == true)
    }

    @Test func lessThanEqualsByteString() throws {
        #expect(try evalBool("(program 1.0.0 [(builtin lessThanEqualsByteString) (con bytestring #dead) (con bytestring #dead)])") == true)
    }
}

// MARK: — String Operations

@Suite("Conformance: String")
struct StringConformanceTests {
    @Test func appendString() throws {
        let term = try evalUPLC("(program 1.0.0 [(builtin appendString) (con string \"hello\") (con string \"world\")])")
        if case .constant(.string(let s)) = term {
            #expect(s == "helloworld")
        } else {
            Issue.record("Expected string")
        }
    }

    @Test func equalsString() throws {
        #expect(try evalBool("(program 1.0.0 [(builtin equalsString) (con string \"abc\") (con string \"abc\")])") == true)
    }

    @Test func equalsStringFalse() throws {
        #expect(try evalBool("(program 1.0.0 [(builtin equalsString) (con string \"abc\") (con string \"def\")])") == false)
    }

    @Test func encodeUtf8() throws {
        #expect(try evalBytesHex("(program 1.0.0 [(builtin encodeUtf8) (con string \"AB\")])") == "4142")
    }

    @Test func decodeUtf8() throws {
        let term = try evalUPLC("(program 1.0.0 [(builtin decodeUtf8) (con bytestring #4142)])")
        if case .constant(.string(let s)) = term {
            #expect(s == "AB")
        } else {
            Issue.record("Expected string")
        }
    }
}

// MARK: — Crypto Hash Functions

@Suite("Conformance: Crypto")
struct CryptoConformanceTests {
    @Test func sha2_256_empty() throws {
        #expect(try evalBytesHex("(program 1.0.0 [(builtin sha2_256) (con bytestring #)])") ==
                "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    @Test func blake2b_256_empty() throws {
        #expect(try evalBool("""
        (program 1.0.0
         [[(builtin equalsByteString)
           [(builtin blake2b_256) (con bytestring #)]]
          (con bytestring #0e5751c026e543b2e8ab2eb06099daa1d1e5df47778f7787faab45cdf12fe3a8)])
        """) == true)
    }

    @Test func blake2b_224_empty() throws {
        #expect(try evalBytesHex("(program 1.0.0 [(builtin blake2b_224) (con bytestring #)])") ==
                "836cc68931c2e4e3e838602eca1902591d216837bafddfe6f0c8cb07")
    }

    @Test func sha3_256_empty() throws {
        #expect(try evalBytesHex("(program 1.0.0 [(builtin sha3_256) (con bytestring #)])") ==
                "a7ffc6f8bf1ed76651c14756a061d662f580ff4de43b49fa82d80a4b80f8434a")
    }

    @Test func keccak_256_empty() throws {
        #expect(try evalBytesHex("(program 1.0.0 [(builtin keccak_256) (con bytestring #)])") ==
                "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470")
    }
}

// MARK: — Control Flow

@Suite("Conformance: Control Flow")
struct ControlFlowConformanceTests {
    @Test func ifThenElseTrue() throws {
        #expect(try evalInt("(program 1.0.0 [(force (builtin ifThenElse)) (con bool True) (con integer 1) (con integer 2)])") == 1)
    }

    @Test func ifThenElseFalse() throws {
        #expect(try evalInt("(program 1.0.0 [(force (builtin ifThenElse)) (con bool False) (con integer 1) (con integer 2)])") == 2)
    }

    @Test func traceTest() throws {
        let result = try evalUPLCFull("(program 1.0.0 [(force (builtin trace)) (con string \"hello\") (con integer 42)])")
        #expect(result.logs == ["hello"])
        if case .constant(.integer(let n)) = result.term {
            #expect(n == 42)
        } else {
            Issue.record("Expected integer 42")
        }
    }
}

// MARK: — Data Operations

@Suite("Conformance: Data Operations")
struct DataConformanceTests {
    @Test func iDataRoundTrip() throws {
        #expect(try evalInt("(program 1.0.0 [(builtin unIData) [(builtin iData) (con integer 42)]])") == 42)
    }

    @Test func equalsDataTrue() throws {
        #expect(try evalBool("(program 1.0.0 [(builtin equalsData) [(builtin iData) (con integer 5)] [(builtin iData) (con integer 5)]])") == true)
    }

    @Test func equalsDataFalse() throws {
        #expect(try evalBool("(program 1.0.0 [(builtin equalsData) [(builtin iData) (con integer 5)] [(builtin iData) (con integer 6)]])") == false)
    }

    @Test func bDataRoundTrip() throws {
        #expect(try evalBytesHex("(program 1.0.0 [(builtin unBData) [(builtin bData) (con bytestring #deadbeef)]])") == "deadbeef")
    }
}

// MARK: — Integer-ByteString Conversion

@Suite("Conformance: Integer-ByteString Conversion")
struct IntByteStringConformanceTests {
    @Test func integerToByteStringBigEndian() throws {
        #expect(try evalBytesHex("(program 1.0.0 [(builtin integerToByteString) (con bool True) (con integer 4) (con integer 256)])") == "00000100")
    }

    @Test func byteStringToIntegerBigEndian() throws {
        #expect(try evalInt("(program 1.0.0 [(builtin byteStringToInteger) (con bool True) (con bytestring #00000100)])") == 256)
    }

    @Test func byteStringToIntegerEmpty() throws {
        #expect(try evalInt("(program 1.0.0 [(builtin byteStringToInteger) (con bool True) (con bytestring #)])") == 0)
    }
}
