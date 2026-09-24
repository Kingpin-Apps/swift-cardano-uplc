import Testing
import BigInt
import Foundation
@testable import SwiftCardanoUPLC

// MARK: — AST Node Tests

@Suite("AST")
struct ASTTests {
    @Test func nameEquality() {
        let a = Name(text: "x", unique: Unique(0))
        let b = Name(text: "x", unique: Unique(0))
        #expect(a == b)
    }

    @Test func deBruijnIndex() {
        let idx = DeBruijn(3)
        #expect(idx.index == 3)
    }

    @Test func constantEquality() {
        let a = UPLCConstant.integer(BigInt(42))
        let b = UPLCConstant.integer(BigInt(42))
        #expect(a == b)
        let c = UPLCConstant.bool(true)
        let d = UPLCConstant.bool(false)
        #expect(c != d)
    }

    @Test func programCreation() {
        let term = Term<Name>.constant(.integer(BigInt(42)))
        let program = NamedProgram(version: (1, 0, 0), term: term)
        #expect(program.version == (1, 0, 0))
    }
}

// MARK: — DefaultFunction Tests

@Suite("DefaultFunction")
struct DefaultFunctionTests {
    @Test func rawValues() {
        #expect(DefaultFunction.addInteger.rawValue == 0)
        #expect(DefaultFunction.subtractInteger.rawValue == 1)
        #expect(DefaultFunction.blake2b_256.rawValue == 20)
        #expect(DefaultFunction.serialiseData.rawValue == 51)
        #expect(DefaultFunction.keccak_256.rawValue == 71)
        #expect(DefaultFunction.ripemd_160.rawValue == 86)
    }

    @Test func arity() {
        #expect(DefaultFunction.addInteger.arity == 2)
        #expect(DefaultFunction.sha2_256.arity == 1)
        #expect(DefaultFunction.sliceByteString.arity == 3)
        #expect(DefaultFunction.ifThenElse.arity == 3)
        #expect(DefaultFunction.chooseData.arity == 6)
    }

    @Test func forceCount() {
        #expect(DefaultFunction.ifThenElse.forceCount == 1)
        #expect(DefaultFunction.fstPair.forceCount == 2)
        #expect(DefaultFunction.addInteger.forceCount == 0)
    }
}

// MARK: — Bit I/O Tests

@Suite("BitIO")
struct BitIOTests {
    @Test func bitWriterRoundtrip() {
        var w = BitWriter()
        w.writeBit(true)
        w.writeBit(false)
        w.writeBit(true)
        w.writeBit(true)
        let data = w.finalize()
        #expect(!data.isEmpty)
    }

    @Test func bitReaderRoundtrip() throws {
        var w = BitWriter()
        w.writeBits(0b1011, count: 4)
        let data = w.finalize()
        var r = BitReader(data: data)
        let v = try r.readBits(count: 4)
        #expect(v == 0b1011)
    }
}

// MARK: — DeBruijn Conversion Tests

@Suite("DeBruijn Conversion")
struct DeBruijnConversionTests {
    @Test func basicConversion() throws {
        let x = Name(text: "x", unique: Unique(0))
        let term = Term<Name>.lambda(parameterName: x, body: .var(x))
        let program = NamedProgram(version: (1, 0, 0), term: term)
        let converter = DeBruijnConverter()
        let dbProgram = try converter.convert(program)
        if case .lambda(_, let body) = dbProgram.term,
           case .var(let idx) = body {
            #expect(idx.index == 1)
        } else {
            Issue.record("Expected .lambda(_, .var(DeBruijn(1)))")
        }
    }

    @Test func namedToDeBruijnToNamedRoundTrip() throws {
        let source = "(program 1.0.0 (lam x (lam y [(builtin addInteger) x y])))"
        var parser = UPLCParser()
        let named = try parser.parse(source)
        let converter = DeBruijnConverter()
        let db = try converter.convert(named)
        let ndb = try converter.convertToNamed(db)
        let applied = NamedDeBruijnProgram(
            version: ndb.version,
            term: .apply(
                function: .apply(function: ndb.term, argument: .constant(.integer(BigInt(3)))),
                argument: .constant(.integer(BigInt(4)))
            )
        )
        var machine = CEKMachine(budget: .unlimited, costModel: .placeholder())
        let result = try machine.run(applied)
        if case .constant(.integer(let n)) = result.term {
            #expect(n == 7)
        } else {
            Issue.record("Expected 7")
        }
    }

    @Test func stripNamesRoundTrip() throws {
        let xName = NamedDeBruijn(text: "x", index: DeBruijn(1))
        let ndbTerm = Term<NamedDeBruijn>.lambda(
            parameterName: NamedDeBruijn(text: "x", index: DeBruijn(0)),
            body: .var(xName)
        )
        let ndbProgram = NamedDeBruijnProgram(version: (1, 0, 0), term: ndbTerm)
        let converter = DeBruijnConverter()
        let db = try converter.convertFromNamed(ndbProgram)
        let restored = try converter.convertToNamed(db)
        let applied = NamedDeBruijnProgram(
            version: restored.version,
            term: .apply(function: restored.term, argument: .constant(.integer(BigInt(77))))
        )
        var machine = CEKMachine(budget: .unlimited, costModel: .placeholder())
        let result = try machine.run(applied)
        if case .constant(.integer(let n)) = result.term {
            #expect(n == 77)
        } else {
            Issue.record("Expected 77")
        }
    }
}

// MARK: — CEK Machine Basic Tests

@Suite("CEK Machine Basics")
struct CEKMachineBasicTests {
    @Test func evalConstant() throws {
        let term = Term<NamedDeBruijn>.constant(.integer(BigInt(42)))
        let program = NamedDeBruijnProgram(version: (1, 0, 0), term: term)
        var machine = CEKMachine(budget: .unlimited, costModel: .placeholder())
        let result = try machine.run(program)
        if case .constant(.integer(let n)) = result.term {
            #expect(n == 42)
        } else {
            Issue.record("Expected integer constant 42")
        }
    }

    @Test func evalIdentityLambda() throws {
        let xName = NamedDeBruijn(text: "x", index: DeBruijn(1))
        let lambda = Term<NamedDeBruijn>.lambda(parameterName: xName, body: .var(xName))
        let arg = Term<NamedDeBruijn>.constant(.integer(BigInt(1)))
        let applied = Term<NamedDeBruijn>.apply(function: lambda, argument: arg)
        let program = NamedDeBruijnProgram(version: (1, 0, 0), term: applied)
        var machine = CEKMachine(budget: .unlimited, costModel: .placeholder())
        let result = try machine.run(program)
        if case .constant(.integer(let n)) = result.term {
            #expect(n == 1)
        } else {
            Issue.record("Expected integer 1")
        }
    }

    @Test func evalAddInteger() throws {
        let add = Term<NamedDeBruijn>.builtin(.addInteger)
        let two = Term<NamedDeBruijn>.constant(.integer(BigInt(2)))
        let three = Term<NamedDeBruijn>.constant(.integer(BigInt(3)))
        let applied = Term<NamedDeBruijn>.apply(
            function: .apply(function: add, argument: two),
            argument: three
        )
        let program = NamedDeBruijnProgram(version: (1, 0, 0), term: applied)
        var machine = CEKMachine(budget: .unlimited, costModel: .placeholder())
        let result = try machine.run(program)
        if case .constant(.integer(let n)) = result.term {
            #expect(n == 5)
        } else {
            Issue.record("Expected 5")
        }
    }

    @Test func evalErrorTerm() {
        let program = NamedDeBruijnProgram(version: (1, 0, 0), term: .error)
        var machine = CEKMachine(budget: .unlimited, costModel: .placeholder())
        #expect(throws: MachineError.evaluationFailure) {
            try machine.run(program)
        }
    }
}

// MARK: — Parser Tests

@Suite("Parser")
struct ParserTests {
    @Test func parseSimpleProgram() throws {
        let source = "(program 1.0.0 (con integer 42))"
        var parser = UPLCParser()
        let program = try parser.parse(source)
        #expect(program.version == (1, 0, 0))
        if case .constant(.integer(let n)) = program.term {
            #expect(n == 42)
        } else {
            Issue.record("Expected integer constant")
        }
    }

    @Test func parseLambda() throws {
        let source = "(program 1.0.0 (lam x x))"
        var parser = UPLCParser()
        let program = try parser.parse(source)
        if case .lambda(let param, let body) = program.term,
           case .var(let v) = body {
            #expect(param.text == "x")
            #expect(v.text == "x")
        } else {
            Issue.record("Expected lambda")
        }
    }

    @Test func parseBuiltinApplication() throws {
        let source = "(program 1.0.0 [ [ (builtin addInteger) (con integer 10)] (con integer 20) ])"
        var parser = UPLCParser()
        let program = try parser.parse(source)
        if case .apply(let f, _) = program.term,
           case .apply(let inner, _) = f,
           case .builtin(.addInteger) = inner {
            // Structure is correct
        } else {
            Issue.record("Expected nested apply with builtin addInteger")
        }
    }

    @Test func parseForce() throws {
        let source = "(program 1.0.0 (force (builtin ifThenElse)))"
        var parser = UPLCParser()
        let program = try parser.parse(source)
        if case .force(let inner) = program.term,
           case .builtin(.ifThenElse) = inner {
            // pass
        } else {
            Issue.record("Expected force(builtin ifThenElse)")
        }
    }

    @Test func parseDelay() throws {
        let source = "(program 1.0.0 (delay (con integer 1)))"
        var parser = UPLCParser()
        let program = try parser.parse(source)
        if case .delay(let inner) = program.term,
           case .constant(.integer(let n)) = inner {
            #expect(n == 1)
        } else {
            Issue.record("Expected delay(con integer 1)")
        }
    }

    @Test func parseError() throws {
        let source = "(program 1.0.0 (error))"
        var parser = UPLCParser()
        let program = try parser.parse(source)
        if case .error = program.term {
            // pass
        } else {
            Issue.record("Expected error term")
        }
    }

    @Test func parseBytestring() throws {
        let source = "(program 1.0.0 (con bytestring #deadbeef))"
        var parser = UPLCParser()
        let program = try parser.parse(source)
        if case .constant(.byteString(let d)) = program.term {
            #expect(d == Data([0xDE, 0xAD, 0xBE, 0xEF]))
        } else {
            Issue.record("Expected bytestring")
        }
    }
}

// MARK: — Pretty Printer Tests

@Suite("Pretty Printer")
struct PrettyPrinterTests {
    @Test func printConstant() {
        let pp = PrettyPrinter()
        let c = UPLCConstant.integer(BigInt(99))
        #expect(pp.printConstant(c) == "integer 99")
    }

    @Test func printBool() {
        let pp = PrettyPrinter()
        #expect(pp.printConstant(.bool(true)) == "bool True")
        #expect(pp.printConstant(.bool(false)) == "bool False")
    }

    @Test func printByteString() {
        let pp = PrettyPrinter()
        let c = UPLCConstant.byteString(Data([0xDE, 0xAD]))
        #expect(pp.printConstant(c) == "bytestring #dead")
    }

    @Test func printUnit() {
        let pp = PrettyPrinter()
        #expect(pp.printConstant(.unit) == "unit ()")
    }

    @Test func printString() {
        let pp = PrettyPrinter()
        #expect(pp.printConstant(.string("hello")) == "string \"hello\"")
    }

    @Test func printList() {
        let pp = PrettyPrinter()
        let c = UPLCConstant.list(.integer, [.integer(BigInt(1)), .integer(BigInt(2))])
        let result = pp.printConstant(c)
        #expect(result.contains("list"))
        #expect(result.contains("integer 1"))
        #expect(result.contains("integer 2"))
    }

    @Test func printPair() {
        let pp = PrettyPrinter()
        let c = UPLCConstant.pair(.bool, .integer, .bool(true), .integer(BigInt(42)))
        let result = pp.printConstant(c)
        #expect(result.contains("pair"))
        #expect(result.contains("bool True"))
        #expect(result.contains("integer 42"))
    }
}

// MARK: — Pretty-Printer Round-Trip Tests

/// Helpers shared across round-trip tests.
private func parseAndConvert(_ source: String) throws -> DeBruijnProgram {
    var parser = UPLCParser()
    let named = try parser.parse(source)
    return try DeBruijnConverter().convert(named)
}

private func roundTrip(_ source: String) throws -> DeBruijnProgram {
    var parser = UPLCParser()
    let named = try parser.parse(source)
    let printed = PrettyPrinter().print(named)
    return try parseAndConvert(printed)
}

@Suite("Pretty Printer Round Trips")
struct PrettyPrinterRoundTripTests {

    // MARK: — Scalar constants

    @Test func roundTripIntegerConstant() throws {
        let original = try parseAndConvert("(program 1.0.0 (con integer 42))")
        let reparsed = try roundTrip("(program 1.0.0 (con integer 42))")
        #expect(original.term == reparsed.term)
    }

    @Test func roundTripBoolConstant() throws {
        let original = try parseAndConvert("(program 1.0.0 (con bool True))")
        let reparsed = try roundTrip("(program 1.0.0 (con bool True))")
        #expect(original.term == reparsed.term)
    }

    @Test func roundTripByteStringConstant() throws {
        let original = try parseAndConvert("(program 1.0.0 (con bytestring #deadbeef))")
        let reparsed = try roundTrip("(program 1.0.0 (con bytestring #deadbeef))")
        #expect(original.term == reparsed.term)
    }

    @Test func roundTripUnitConstant() throws {
        let original = try parseAndConvert("(program 1.0.0 (con unit ()))")
        let reparsed = try roundTrip("(program 1.0.0 (con unit ()))")
        #expect(original.term == reparsed.term)
    }

    @Test func roundTripStringConstant() throws {
        let original = try parseAndConvert("(program 1.0.0 (con string \"hello world\"))")
        let reparsed = try roundTrip("(program 1.0.0 (con string \"hello world\"))")
        #expect(original.term == reparsed.term)
    }

    @Test func roundTripNegativeInteger() throws {
        let original = try parseAndConvert("(program 1.0.0 (con integer -9999))")
        let reparsed = try roundTrip("(program 1.0.0 (con integer -9999))")
        #expect(original.term == reparsed.term)
    }

    // MARK: — Data constants

    @Test func roundTripDataIData() throws {
        let original = try parseAndConvert("(program 1.0.0 (con data (I 42)))")
        let reparsed = try roundTrip("(program 1.0.0 (con data (I 42)))")
        #expect(original.term == reparsed.term)
    }

    @Test func roundTripDataBData() throws {
        let original = try parseAndConvert("(program 1.0.0 (con data (B #deadbeef)))")
        let reparsed = try roundTrip("(program 1.0.0 (con data (B #deadbeef)))")
        #expect(original.term == reparsed.term)
    }

    @Test func roundTripDataConstrData() throws {
        let original = try parseAndConvert("(program 1.0.0 (con data (Constr 1 [I 1])))")
        let reparsed = try roundTrip("(program 1.0.0 (con data (Constr 1 [I 1])))")
        #expect(original.term == reparsed.term)
    }

    @Test func roundTripDataListData() throws {
        let original = try parseAndConvert("(program 1.0.0 (con data (List [I 1, I 2, B #ff])))")
        let reparsed = try roundTrip("(program 1.0.0 (con data (List [I 1, I 2, B #ff])))")
        #expect(original.term == reparsed.term)
    }

    @Test func roundTripDataMapData() throws {
        let src = "(program 1.0.0 (con data (Map [(I 1, B #aa), (I 2, B #bb)])))"
        let original = try parseAndConvert(src)
        let reparsed = try roundTrip(src)
        #expect(original.term == reparsed.term)
    }

    @Test func roundTripDataConstrNoFields() throws {
        let original = try parseAndConvert("(program 1.0.0 (con data (Constr 0 [])))")
        let reparsed = try roundTrip("(program 1.0.0 (con data (Constr 0 [])))")
        #expect(original.term == reparsed.term)
    }

    // MARK: — Term structure

    @Test func roundTripLambdaApply() throws {
        let src = "(program 1.0.0 [ (lam x x) (con integer 5) ])"
        let original = try parseAndConvert(src)
        let reparsed = try roundTrip(src)
        #expect(original.term == reparsed.term)
    }

    @Test func roundTripForceDelay() throws {
        let src = "(program 1.0.0 (force (delay (con integer 1))))"
        let original = try parseAndConvert(src)
        let reparsed = try roundTrip(src)
        #expect(original.term == reparsed.term)
    }

    @Test func roundTripBuiltin() throws {
        let src = "(program 1.0.0 (builtin addInteger))"
        let original = try parseAndConvert(src)
        let reparsed = try roundTrip(src)
        #expect(original.term == reparsed.term)
    }

    @Test func roundTripConstrCase() throws {
        let src = "(program 1.0.0 (case (constr 0 (con integer 1)) (lam x x)))"
        let original = try parseAndConvert(src)
        let reparsed = try roundTrip(src)
        #expect(original.term == reparsed.term)
    }

    @Test func roundTripNestedLambda() throws {
        let src = "(program 1.0.0 (lam x (lam y [ (builtin addInteger) x y ])))"
        let original = try parseAndConvert(src)
        let reparsed = try roundTrip(src)
        #expect(original.term == reparsed.term)
    }

    // MARK: — Complex program (fibonacci fixture)

    @Test func roundTripFibonacci() throws {
        guard let url = Bundle.module.url(forResource: "Resources/fibonacci/fibonacci", withExtension: "uplc") else {
            Issue.record("fibonacci.uplc fixture not found"); return
        }
        let src = try String(contentsOf: url, encoding: .utf8)
        let original = try parseAndConvert(src)
        let reparsed = try roundTrip(src)
        #expect(original.term == reparsed.term)
    }
}
