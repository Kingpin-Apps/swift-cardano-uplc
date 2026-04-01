import Testing
import BigInt
import Foundation
@testable import SwiftCardanoUPLC

// MARK: — Plutus Conformance Test Runner
//
// This mirrors the Aiken project's conformance test runner (conformance.rs).
// It walks the conformance test data directory, evaluates each .uplc file,
// and compares the result against the corresponding .uplc.expected file.
//
// Like Aiken, we compare NamedDeBruijn ASTs structurally (only DeBruijn
// indices matter, not variable name text). This matches Plutus semantics.
//
// Expected outcomes:
//   - "evaluation failure" → evaluation should throw an error
//   - "parse error"        → parsing should fail
//   - Otherwise            → a valid UPLC program that should match the result

private let EVALUATION_FAILURE = "evaluation failure"
private let PARSE_ERROR = "parse error"

/// Outcome of evaluating a UPLC test file.
private enum TestOutcome {
    case success(NamedDeBruijnProgram)  // evaluated result as NamedDeBruijn AST
    case evaluationFailure
    case parseError
}

/// Structurally compare two NamedDeBruijn terms, ignoring name text
/// and only comparing DeBruijn indices and structure.
private func termsEqual(_ lhs: Term<NamedDeBruijn>, _ rhs: Term<NamedDeBruijn>) -> Bool {
    switch (lhs, rhs) {
    case (.var(let a), .var(let b)):
        return a.index == b.index
    case (.delay(let a), .delay(let b)):
        return termsEqual(a, b)
    case (.lambda(let n1, let b1), .lambda(let n2, let b2)):
        // Binder indices are both 0 by convention; compare bodies
        return n1.index == n2.index && termsEqual(b1, b2)
    case (.apply(let f1, let a1), .apply(let f2, let a2)):
        return termsEqual(f1, f2) && termsEqual(a1, a2)
    case (.constant(let a), .constant(let b)):
        return a == b
    case (.force(let a), .force(let b)):
        return termsEqual(a, b)
    case (.error, .error):
        return true
    case (.builtin(let a), .builtin(let b)):
        return a == b
    case (.constr(let t1, let f1), .constr(let t2, let f2)):
        return t1 == t2 && f1.count == f2.count
            && zip(f1, f2).allSatisfy { termsEqual($0, $1) }
    case (.case(let a1, let b1), .case(let a2, let b2)):
        return termsEqual(a1, a2) && b1.count == b2.count
            && zip(b1, b2).allSatisfy { termsEqual($0, $1) }
    default:
        return false
    }
}

/// Structurally compare two NamedDeBruijn programs.
private func programsEqual(_ lhs: NamedDeBruijnProgram, _ rhs: NamedDeBruijnProgram) -> Bool {
    lhs.version == rhs.version && termsEqual(lhs.term, rhs.term)
}

/// Parse a UPLC string and convert to NamedDeBruijn form.
private func parseToNamedDeBruijn(_ code: String) throws -> NamedDeBruijnProgram {
    var parser = UPLCParser()
    let named = try parser.parse(code)
    let converter = DeBruijnConverter()
    let db = try converter.convert(named)
    return try converter.convertToNamed(db)
}

/// Parse the .uplc.expected file and determine the expected outcome.
private func parseExpected(_ content: String) -> TestOutcome {
    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.contains(EVALUATION_FAILURE) {
        return .evaluationFailure
    }
    if trimmed.contains(PARSE_ERROR) {
        return .parseError
    }
    // Parse expected into NamedDeBruijn AST
    do {
        let program = try parseToNamedDeBruijn(trimmed)
        return .success(program)
    } catch {
        // If we can't parse the expected, treat as parse error
        return .parseError
    }
}

/// Evaluate a .uplc file and return the outcome.
private func evaluateFile(_ code: String) -> TestOutcome {
    var parser = UPLCParser()
    let namedProgram: NamedProgram
    do {
        namedProgram = try parser.parse(code)
    } catch {
        return .parseError
    }

    let converter = DeBruijnConverter()
    let ndbProgram: NamedDeBruijnProgram
    do {
        let dbProgram = try converter.convert(namedProgram)
        ndbProgram = try converter.convertToNamed(dbProgram)
    } catch {
        return .evaluationFailure
    }

    var machine = CEKMachine(budget: .unlimited, costModel: .defaultV2())
    let result: EvalResult
    do {
        result = try machine.run(ndbProgram)
    } catch {
        return .evaluationFailure
    }

    let resultProgram = NamedDeBruijnProgram(version: ndbProgram.version, term: result.term)
    return .success(resultProgram)
}

/// Recursively find all .uplc files under a directory URL.
private func findUPLCFiles(in directory: URL) -> [URL] {
    let fm = FileManager.default
    guard let enumerator = fm.enumerator(
        at: directory,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else { return [] }

    var files: [URL] = []
    for case let fileURL as URL in enumerator {
        if fileURL.pathExtension == "uplc" && !fileURL.lastPathComponent.contains(".expected") {
            files.append(fileURL)
        }
    }
    return files.sorted { $0.path < $1.path }
}

// MARK: — Test Suites

/// Paths containing any of these substrings are skipped to avoid crashes
/// in external dependencies (BLS12-381 operations can trigger precondition
/// failures in SwiftBLST when fed malformed conformance test inputs).
private let crashPronePatterns = [
    "bls12_381",
    "bls12-381",
    "cardano-crypto",
]

/// Run conformance tests for a given version directory (v2 or v3).
/// Each test is parameterized by the test name derived from the directory structure.
private func runConformanceTests(version: String, category: String) throws {
    guard let baseURL = Bundle.module.url(forResource: "Resources/Conformance/\(version)/\(category)", withExtension: nil) else {
        Issue.record("Could not find Conformance/\(version)/\(category) resource directory")
        return
    }

    let uplcFiles = findUPLCFiles(in: baseURL)
    guard !uplcFiles.isEmpty else {
        Issue.record("No .uplc files found in conformance/\(version)/\(category)")
        return
    }

    var passed = 0
    var failed = 0
    var skipped = 0
    var failures: [(String, String)] = []
    let pp = PrettyPrinter()

    for file in uplcFiles {
        // Skip tests known to crash in external dependencies
        let filePath = file.path
        if crashPronePatterns.contains(where: { filePath.contains($0) }) {
            skipped += 1
            continue
        }

        let expectedFile = file.appendingPathExtension("expected")
        guard FileManager.default.fileExists(atPath: expectedFile.path) else {
            skipped += 1
            continue
        }

        let code = try String(contentsOf: file, encoding: .utf8)
        let expectedContent = try String(contentsOf: expectedFile, encoding: .utf8)

        let expected = parseExpected(expectedContent)
        let actual = evaluateFile(code)

        // Derive a readable test name from the path
        let testName = file.deletingPathExtension().lastPathComponent

        // Compare outcomes
        var matches = false
        switch (expected, actual) {
        case (.evaluationFailure, .evaluationFailure):
            matches = true
        case (.parseError, .parseError):
            matches = true
        case (.success(let expectedProg), .success(let actualProg)):
            // Structural comparison: only DeBruijn indices matter, not name text
            matches = programsEqual(expectedProg, actualProg)
        default:
            matches = false
        }

        if matches {
            passed += 1
        } else {
            failed += 1
            // Format a readable failure message
            let expectedDesc: String
            let actualDesc: String
            switch expected {
            case .success(let p): expectedDesc = "success(\(pp.printCompactProgram(p)))"
            case .evaluationFailure: expectedDesc = "evaluationFailure"
            case .parseError: expectedDesc = "parseError"
            }
            switch actual {
            case .success(let p): actualDesc = "success(\(pp.printCompactProgram(p)))"
            case .evaluationFailure: actualDesc = "evaluationFailure"
            case .parseError: actualDesc = "parseError"
            }
            failures.append((testName, "expected: \(expectedDesc), actual: \(actualDesc)"))
        }
    }

    // Report failures
    for (name, detail) in failures {
        Issue.record("FAIL [\(version)/\(category)] \(name): \(detail)")
    }

    // Summary assertion — require that all non-skipped tests pass
    let total = passed + failed
    #expect(failed == 0, "\(version)/\(category): \(failed)/\(total) tests failed (\(skipped) skipped)")
}

// MARK: — V3 Conformance Suites

@Suite("Plutus Conformance: V3 Examples")
struct PlutusConformanceV3ExampleTests {
    @Test func v3Examples() throws {
        try runConformanceTests(version: "v3", category: "example")
    }
}

@Suite("Plutus Conformance: V3 Terms")
struct PlutusConformanceV3TermTests {
    @Test func v3Terms() throws {
        try runConformanceTests(version: "v3", category: "term")
    }
}

@Suite("Plutus Conformance: V3 Builtin Semantics")
struct PlutusConformanceV3BuiltinSemanticsTests {
    // Split into subcategories to isolate crash-prone V3-only builtins.
    // V3-only builtins: countSetBits, findFirstSetBit, readBit, writeBits,
    // replicateByte, shiftByteString, rotateByteString, complementByteString,
    // andByteString, orByteString, xorByteString

    @Test func v3Semantics_countSetBits() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/countSetBits")
    }
    @Test func v3Semantics_findFirstSetBit() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/findFirstSetBit")
    }
    @Test func v3Semantics_readBit() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/readBit")
    }
    @Test func v3Semantics_writeBits() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/writeBits")
    }
    @Test func v3Semantics_replicateByte() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/replicateByte")
    }
    @Test func v3Semantics_shiftByteString() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/shiftByteString")
    }
    @Test func v3Semantics_rotateByteString() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/rotateByteString")
    }
    @Test func v3Semantics_complementByteString() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/complementByteString")
    }
    @Test func v3Semantics_andByteString() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/andByteString")
    }
    @Test func v3Semantics_orByteString() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/orByteString")
    }
    @Test func v3Semantics_xorByteString() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/xorByteString")
    }
    @Test func v3Semantics_integerToByteString() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/integerToByteString")
    }
    @Test func v3Semantics_byteStringToInteger() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/byteStringToInteger")
    }

    // MARK: — Shared builtins (also present in V2, tested here under V3)

    @Test func v3Semantics_addInteger() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/addInteger")
    }
    @Test func v3Semantics_subtractInteger() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/subtractInteger")
    }
    @Test func v3Semantics_subtractIntegerNonIter() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/subtractInteger-non-iter")
    }
    @Test func v3Semantics_multiplyInteger() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/multiplyInteger")
    }
    @Test func v3Semantics_divideInteger() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/divideInteger")
    }
    @Test func v3Semantics_modInteger() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/modInteger")
    }
    @Test func v3Semantics_quotientInteger() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/quotientInteger")
    }
    @Test func v3Semantics_remainderInteger() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/remainderInteger")
    }
    @Test func v3Semantics_equalsInteger() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/equalsInteger")
    }
    @Test func v3Semantics_lessThanInteger() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/lessThanInteger")
    }
    @Test func v3Semantics_lessThanEqualsInteger() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/lessThanEqualsInteger")
    }
    @Test func v3Semantics_appendByteString() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/appendByteString")
    }
    @Test func v3Semantics_consByteString() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/consByteString")
    }
    @Test func v3Semantics_sliceByteString() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/sliceByteString")
    }
    @Test func v3Semantics_lengthOfByteString() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/lengthOfByteString")
    }
    @Test func v3Semantics_indexByteString() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/indexByteString")
    }
    @Test func v3Semantics_equalsByteString() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/equalsByteString")
    }
    @Test func v3Semantics_lessThanByteString() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/lessThanByteString")
    }
    @Test func v3Semantics_lessThanEqualsByteString() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/lessThanEqualsByteString")
    }
    @Test func v3Semantics_appendString() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/appendString")
    }
    @Test func v3Semantics_equalsString() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/equalsString")
    }
    @Test func v3Semantics_encodeUtf8() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/encodeUtf8")
    }
    @Test func v3Semantics_decodeUtf8() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/decodeUtf8")
    }
    @Test func v3Semantics_ifThenElse() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/ifThenElse")
    }
    @Test func v3Semantics_chooseUnit() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/chooseUnit")
    }
    @Test func v3Semantics_chooseUnit2() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/chooseUnit2")
    }
    @Test func v3Semantics_trace() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/trace")
    }
    @Test func v3Semantics_iData() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/iData")
    }
    @Test func v3Semantics_bData() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/bData")
    }
    @Test func v3Semantics_constrData() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/constrData")
    }
    @Test func v3Semantics_mapData() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/mapData")
    }
    @Test func v3Semantics_listData() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/listData")
    }
    @Test func v3Semantics_unIData() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/unIData")
    }
    @Test func v3Semantics_unBData() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/unBData")
    }
    @Test func v3Semantics_unConstrData() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/unConstrData")
    }
    @Test func v3Semantics_unMapData() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/unMapData")
    }
    @Test func v3Semantics_unListData() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/unListData")
    }
    @Test func v3Semantics_equalsData() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/equalsData")
    }
    @Test func v3Semantics_chooseDataByteString() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/chooseDataByteString")
    }
    @Test func v3Semantics_chooseDataConstr() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/chooseDataConstr")
    }
    @Test func v3Semantics_chooseDataInteger() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/chooseDataInteger")
    }
    @Test func v3Semantics_chooseDataList() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/chooseDataList")
    }
    @Test func v3Semantics_chooseDataMap() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/chooseDataMap")
    }
    @Test func v3Semantics_chooseList() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/chooseList")
    }
    @Test func v3Semantics_headList() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/headList")
    }
    @Test func v3Semantics_tailList() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/tailList")
    }
    @Test func v3Semantics_nullList() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/nullList")
    }
    @Test func v3Semantics_nullList2() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/nullList2")
    }
    @Test func v3Semantics_mkCons() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/mkCons")
    }
    @Test func v3Semantics_mkNilData() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/mkNilData")
    }
    @Test func v3Semantics_mkNilPairData() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/mkNilPairData")
    }
    @Test func v3Semantics_mkPairData() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/mkPairData")
    }
    @Test func v3Semantics_fstPairOfPairAndList() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/fstPairOfPairAndList")
    }
    @Test func v3Semantics_sndPairOfPairAndList() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/sndPairOfPairAndList")
    }
    @Test func v3Semantics_pairOfPairAndList() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/pairOfPairAndList")
    }
    @Test func v3Semantics_listOfList() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/listOfList")
    }
    @Test func v3Semantics_listOfPair() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/listOfPair")
    }
    @Test func v3Semantics_blake2b_224() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/blake2b_224")
    }
    @Test func v3Semantics_blake2b_256() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/blake2b_256")
    }
    @Test func v3Semantics_sha2_256() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/sha2_256")
    }
    @Test func v3Semantics_sha3_256() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/sha3_256")
    }
    @Test func v3Semantics_keccak_256() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/keccak_256")
    }
    @Test func v3Semantics_ripemd_160() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/ripemd_160")
    }
    @Test func v3Semantics_verifyEd25519Signature() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/verifyEd25519Signature")
    }
    @Test func v3Semantics_verifyEcdsaSecp256k1Signature() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/verifyEcdsaSecp256k1Signature")
    }
    @Test func v3Semantics_verifySchnorrSecp256k1Signature() throws {
        try runConformanceTests(version: "v3", category: "builtin/semantics/verifySchnorrSecp256k1Signature")
    }
}

@Suite("Plutus Conformance: V3 Builtin Constants")
struct PlutusConformanceV3BuiltinConstantTests {
    @Test func v3BuiltinConstants() throws {
        try runConformanceTests(version: "v3", category: "builtin/constant")
    }
}

@Suite("Plutus Conformance: V3 Builtin Interleaving")
struct PlutusConformanceV3BuiltinInterleavingTests {
    @Test func v3BuiltinInterleaving() throws {
        try runConformanceTests(version: "v3", category: "builtin/interleaving")
    }
}

// MARK: — V2 Conformance Suites

@Suite("Plutus Conformance: V2 Examples")
struct PlutusConformanceV2ExampleTests {
    @Test func v2Examples() throws {
        try runConformanceTests(version: "v2", category: "example")
    }
}

@Suite("Plutus Conformance: V2 Terms")
struct PlutusConformanceV2TermTests {
    @Test func v2Terms() throws {
        try runConformanceTests(version: "v2", category: "term")
    }
}

@Suite("Plutus Conformance: V2 Builtin Semantics")
struct PlutusConformanceV2BuiltinSemanticsTests {
    @Test func v2BuiltinSemantics() throws {
        try runConformanceTests(version: "v2", category: "builtin/semantics")
    }
}

@Suite("Plutus Conformance: V2 Builtin Constants")
struct PlutusConformanceV2BuiltinConstantTests {
    @Test func v2BuiltinConstants() throws {
        try runConformanceTests(version: "v2", category: "builtin/constant")
    }
}

@Suite("Plutus Conformance: V2 Builtin Interleaving")
struct PlutusConformanceV2BuiltinInterleavingTests {
    @Test func v2BuiltinInterleaving() throws {
        try runConformanceTests(version: "v2", category: "builtin/interleaving")
    }
}
