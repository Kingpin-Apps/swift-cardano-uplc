import Testing
import BigInt
import Foundation
@testable import SwiftCardanoUPLC

@Suite("CEK Machine Edge Cases")
struct CEKMachineEdgeCaseTests {
    @Test func errorTermThrows() {
        #expect(throws: MachineError.evaluationFailure) {
            try evalUPLC("(program 1.0.0 error)")
        }
    }

    @Test func nestedLambda() throws {
        let n = try evalInt("""
        (program 1.0.0
          [[(lam x (lam y x)) (con integer 1)] (con integer 2)]
        )
        """)
        #expect(n == 1)
    }

    @Test func delayForce() throws {
        let n = try evalInt("(program 1.0.0 (force (delay (con integer 99))))")
        #expect(n == 99)
    }

    @Test func forcingNonDelayFails() {
        #expect(throws: (any Error).self) {
            try evalUPLC("(program 1.0.0 (force (con integer 1)))")
        }
    }

    @Test func applyNonFunctionFails() {
        #expect(throws: (any Error).self) {
            try evalUPLC("(program 1.0.0 [(con integer 1) (con integer 2)])")
        }
    }

    @Test func largeIntegerArithmetic() throws {
        let n = try evalInt("(program 1.0.0 [(builtin multiplyInteger) (con integer 999999999999999999) (con integer 999999999999999999)])")
        #expect(n == BigInt("999999999999999998000000000000000001"))
    }
}
