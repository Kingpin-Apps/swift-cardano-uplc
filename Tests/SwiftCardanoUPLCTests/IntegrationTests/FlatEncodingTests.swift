import Testing
import BigInt
import Foundation
@testable import SwiftCardanoUPLC

@Suite("Flat Encoding")
struct FlatEncodingTests {
    @Test func roundTripInteger() throws {
        let term = Term<DeBruijn>.constant(.integer(BigInt(42)))
        let program = DeBruijnProgram(version: (1, 0, 0), term: term)
        let encoded = try FlatEncoder().encode(program)
        let decoded = try FlatDecoder().decode(encoded)
        if case .constant(.integer(let n)) = decoded.term {
            #expect(n == 42)
        } else {
            Issue.record("Round-trip failed for integer constant")
        }
    }

    @Test func roundTripBool() throws {
        let program = DeBruijnProgram(version: (1, 0, 0), term: .constant(.bool(true)))
        let encoded = try FlatEncoder().encode(program)
        let decoded = try FlatDecoder().decode(encoded)
        if case .constant(.bool(let b)) = decoded.term {
            #expect(b == true)
        } else {
            Issue.record("Round-trip failed for bool constant")
        }
    }

    @Test func roundTripByteString() throws {
        let bs = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let program = DeBruijnProgram(version: (1, 0, 0), term: .constant(.byteString(bs)))
        let encoded = try FlatEncoder().encode(program)
        let decoded = try FlatDecoder().decode(encoded)
        if case .constant(.byteString(let d)) = decoded.term {
            #expect(d == bs)
        } else {
            Issue.record("Round-trip failed for bytestring constant")
        }
    }

    @Test func roundTripString() throws {
        let program = DeBruijnProgram(version: (1, 0, 0), term: .constant(.string("hello")))
        let encoded = try FlatEncoder().encode(program)
        let decoded = try FlatDecoder().decode(encoded)
        if case .constant(.string(let s)) = decoded.term {
            #expect(s == "hello")
        } else {
            Issue.record("Round-trip failed for string constant")
        }
    }

    @Test func roundTripUnit() throws {
        let program = DeBruijnProgram(version: (1, 0, 0), term: .constant(.unit))
        let encoded = try FlatEncoder().encode(program)
        let decoded = try FlatDecoder().decode(encoded)
        if case .constant(.unit) = decoded.term {
            // pass
        } else {
            Issue.record("Round-trip failed for unit constant")
        }
    }

    @Test func roundTripBuiltin() throws {
        let program = DeBruijnProgram(version: (1, 0, 0), term: .builtin(.addInteger))
        let encoded = try FlatEncoder().encode(program)
        let decoded = try FlatDecoder().decode(encoded)
        if case .builtin(let fn) = decoded.term {
            #expect(fn == .addInteger)
        } else {
            Issue.record("Round-trip failed for builtin")
        }
    }

    @Test func roundTripError() throws {
        let program = DeBruijnProgram(version: (1, 0, 0), term: .error)
        let encoded = try FlatEncoder().encode(program)
        let decoded = try FlatDecoder().decode(encoded)
        if case .error = decoded.term {
            // pass
        } else {
            Issue.record("Round-trip failed for error term")
        }
    }

    @Test func roundTripLambdaApply() throws {
        let body = Term<DeBruijn>.var(DeBruijn(1))
        let lambda = Term<DeBruijn>.lambda(parameterName: DeBruijn(0), body: body)
        let arg = Term<DeBruijn>.constant(.integer(BigInt(99)))
        let term = Term<DeBruijn>.apply(function: lambda, argument: arg)
        let program = DeBruijnProgram(version: (1, 0, 0), term: term)
        let encoded = try FlatEncoder().encode(program)
        let decoded = try FlatDecoder().decode(encoded)
        let converter = DeBruijnConverter()
        let ndb = try converter.convertToNamed(
            DeBruijnProgram(version: decoded.version,
                            term: converter.convertFromNamed(decoded).term)
        )
        var machine = CEKMachine(budget: .unlimited, costModel: .defaultV2())
        let result = try machine.run(ndb)
        if case .constant(.integer(let n)) = result.term {
            #expect(n == 99)
        } else {
            Issue.record("Round-trip lambda-apply failed")
        }
    }

    @Test func roundTripNegativeInteger() throws {
        let program = DeBruijnProgram(version: (1, 0, 0), term: .constant(.integer(BigInt(-12345))))
        let encoded = try FlatEncoder().encode(program)
        let decoded = try FlatDecoder().decode(encoded)
        if case .constant(.integer(let n)) = decoded.term {
            #expect(n == -12345)
        } else {
            Issue.record("Round-trip failed for negative integer")
        }
    }

    @Test func roundTripList() throws {
        let list = UPLCConstant.list(.integer, [.integer(BigInt(1)), .integer(BigInt(2)), .integer(BigInt(3))])
        let program = DeBruijnProgram(version: (1, 0, 0), term: .constant(list))
        let encoded = try FlatEncoder().encode(program)
        let decoded = try FlatDecoder().decode(encoded)
        if case .constant(.list(.integer, let items)) = decoded.term {
            #expect(items.count == 3)
        } else {
            Issue.record("Round-trip failed for list constant")
        }
    }

    @Test func roundTripAllBuiltinTags() throws {
        for fn in DefaultFunction.allCases {
            let program = DeBruijnProgram(version: (1, 0, 0), term: .builtin(fn))
            let encoded = try FlatEncoder().encode(program)
            let decoded = try FlatDecoder().decode(encoded)
            if case .builtin(let decodedFn) = decoded.term {
                #expect(decodedFn == fn, "Builtin round-trip failed for \(fn)")
            } else {
                Issue.record("Builtin round-trip failed for \(fn)")
            }
        }
    }

    // MARK: — Fixture-Based Tests (Aiken test_data)

    @Test func decodeIntegerFixture() throws {
        guard let url = Bundle.module.url(forResource: "Resources/basic/integer/integer", withExtension: "flat") else {
            Issue.record("integer.flat fixture not found"); return
        }
        let data = try Data(contentsOf: url)
        let decoded = try FlatDecoder().decode(data)
        #expect(decoded.version == (11, 22, 33))
        if case .constant(.integer(let n)) = decoded.term {
            #expect(n == 11)
        } else {
            Issue.record("Expected integer 11 from fixture")
        }
    }

    @Test func decodeCaseConstrFixture() throws {
        guard let url = Bundle.module.url(forResource: "Resources/case_constr/case_constr", withExtension: "flat") else {
            Issue.record("case_constr.flat fixture not found"); return
        }
        let data = try Data(contentsOf: url)
        let decoded = try FlatDecoder().decode(data)
        // Just verify it decodes without error
        #expect(decoded.version.0 >= 0)
    }

    // MARK: — Encode round-trip fixtures (Aiken integ_tests equivalent)

    /// Parse jpg.uplc → encode to flat → compare byte-for-byte with jpg.flat.
    /// jpg.uplc is ~9700 lines; the recursive encoder can overflow the default stack,
    /// so the work runs on a thread with 64 MB of stack space.
    @Test func encodeJpgMatchesFixture() throws {
        guard
            let uplcURL = Bundle.module.url(forResource: "Resources/jpg/jpg", withExtension: "uplc"),
            let flatURL = Bundle.module.url(forResource: "Resources/jpg/jpg", withExtension: "flat")
        else {
            Issue.record("jpg fixture files not found"); return
        }
        let uplcText = try String(contentsOf: uplcURL, encoding: .utf8)
        let expectedBytes = try Data(contentsOf: flatURL)

        // Run the recursive parse + encode on a thread with a larger stack.
        enum Result { case success(Data); case failure(Error) }
        nonisolated(unsafe) var threadResult: Result?
        let sema = DispatchSemaphore(value: 0)

        let t = Thread {
            do {
                var parser = UPLCParser()
                let named = try parser.parse(uplcText)
                let db = try DeBruijnConverter().convert(named)
                let encoded = try FlatEncoder().encode(db)
                threadResult = .success(encoded)
            } catch {
                threadResult = .failure(error)
            }
            sema.signal()
        }
        t.stackSize = 64 * 1024 * 1024  // 64 MB — enough for deeply-nested programs
        t.qualityOfService = .userInitiated
        t.start()
        sema.wait()

        switch threadResult! {
        case .success(let encoded):
            #expect(encoded == expectedBytes, "Encoded jpg bytes do not match jpg.flat fixture")
        case .failure(let error):
            Issue.record("jpg encode failed: \(error)")
        }
    }

    /// Parse fibonacci.uplc → encode to flat → compare byte-for-byte with fibonacci.flat
    @Test func encodeFibonacciMatchesFixture() throws {
        guard
            let uplcURL = Bundle.module.url(forResource: "Resources/fibonacci/fibonacci", withExtension: "uplc"),
            let flatURL = Bundle.module.url(forResource: "Resources/fibonacci/fibonacci", withExtension: "flat")
        else {
            Issue.record("fibonacci fixture files not found"); return
        }
        let uplcText = try String(contentsOf: uplcURL, encoding: .utf8)
        let expectedBytes = try Data(contentsOf: flatURL)

        var parser = UPLCParser()
        let named = try parser.parse(uplcText)
        let db = try DeBruijnConverter().convert(named)
        let encoded = try FlatEncoder().encode(db)

        #expect(encoded == expectedBytes, "Encoded fibonacci bytes do not match fibonacci.flat fixture")
    }

    /// Parse unsanitary_fibonacci.uplc — verifies the parser accepts non-canonical formatting
    /// and the program converts and evaluates without error.
    @Test func decodeUnsanitaryFibonacci() throws {
        guard let url = Bundle.module.url(forResource: "Resources/fibonacci/unsanitary_fibonacci", withExtension: "uplc") else {
            Issue.record("unsanitary_fibonacci.uplc fixture not found"); return
        }
        let uplcText = try String(contentsOf: url, encoding: .utf8)

        var parser = UPLCParser()
        let named = try parser.parse(uplcText)
        let db = try DeBruijnConverter().convert(named)
        let ndb = try DeBruijnConverter().convertToNamed(db)

        // Verify it evaluates without error (the program is a lambda, so result is a value)
        var machine = CEKMachine(budget: .unlimited, costModel: .defaultV2())
        _ = try machine.run(ndb)
    }
}
