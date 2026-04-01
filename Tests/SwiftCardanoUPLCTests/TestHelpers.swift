import Testing
import BigInt
import Foundation
@testable import SwiftCardanoUPLC

// MARK: — Shared test helpers

/// Parse a UPLC source string, convert to NamedDeBruijn, evaluate with the CEK machine,
/// and return the result term.
func evalUPLC(_ source: String) throws -> Term<NamedDeBruijn> {
    var parser = UPLCParser()
    let namedProgram = try parser.parse(source)
    let converter = DeBruijnConverter()
    let dbProgram = try converter.convert(namedProgram)
    let ndbProgram = try converter.convertToNamed(dbProgram)
    var machine = CEKMachine(budget: .unlimited, costModel: .defaultV2())
    let result = try machine.run(ndbProgram)
    return result.term
}

/// Evaluate UPLC and return the full machine result (term + logs).
func evalUPLCFull(_ source: String) throws -> EvalResult {
    var parser = UPLCParser()
    let namedProgram = try parser.parse(source)
    let converter = DeBruijnConverter()
    let dbProgram = try converter.convert(namedProgram)
    let ndbProgram = try converter.convertToNamed(dbProgram)
    var machine = CEKMachine(budget: .unlimited, costModel: .defaultV2())
    return try machine.run(ndbProgram)
}

/// Evaluate UPLC and extract the integer result.
func evalInt(_ source: String) throws -> BigInt {
    let term = try evalUPLC(source)
    guard case .constant(.integer(let n)) = term else {
        throw MachineError.typeError("Expected integer result, got \(term)")
    }
    return n
}

/// Evaluate UPLC and extract the bool result.
func evalBool(_ source: String) throws -> Bool {
    let term = try evalUPLC(source)
    guard case .constant(.bool(let b)) = term else {
        throw MachineError.typeError("Expected bool result, got \(term)")
    }
    return b
}

/// Evaluate UPLC and extract the bytestring result as hex.
func evalBytesHex(_ source: String) throws -> String {
    let term = try evalUPLC(source)
    guard case .constant(.byteString(let d)) = term else {
        throw MachineError.typeError("Expected bytestring result, got \(term)")
    }
    return d.map { String(format: "%02x", $0) }.joined()
}

/// Pretty-print a result term back to UPLC program text for comparison with .expected files.
func prettyPrintResult(_ term: Term<NamedDeBruijn>, version: (Int, Int, Int) = (1, 0, 0)) -> String {
    let pp = PrettyPrinter()
    let body = pp.printNamedDeBruijn(term)
    return "(program \(version.0).\(version.1).\(version.2) \(body))"
}

// MARK: — Resource helpers

/// Find a resource directory within the test bundle.
func testResourceURL(_ path: String) -> URL? {
    Bundle.module.url(forResource: "Resources/\(path)", withExtension: nil)
}
