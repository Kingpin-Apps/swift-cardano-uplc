import Testing
import Foundation
import SwiftCardanoCore
@testable import SwiftCardanoUPLC

/// Terms nested far deeper than any call stack could recurse through. Each test
/// runs on a Swift-concurrency cooperative thread (a small stack, around 512 KB),
/// where a recursive printer overflowed on a real mainnet validator.
@Suite("Deep terms")
struct DeepTermTests {
    static let depth = 100_000

    @Test func compactPrintsDeepTerm() async throws {
        let matches = await Task.detached {
            let chain = DeepChain(depth: Self.depth)
            var term = chain.namedDeBruijnTerm()
            let printed = PrettyPrinter().printCompact(term)
            dismantle(&term)
            return printed == chain.expectedCompact
        }.value
        #expect(matches)
    }

    @Test func indentedPrintsDeepTerm() async throws {
        // Indented output grows with the square of the depth, so go less deep.
        let depth = 2_000
        let lines = await Task.detached {
            var term = Term<NamedDeBruijn>.var(NamedDeBruijn(text: "i", index: DeBruijn(1)))
            for _ in 0..<depth {
                term = .lambda(parameterName: NamedDeBruijn(text: "i", index: DeBruijn(0)), body: term)
            }
            let printed = PrettyPrinter().printNamedDeBruijn(term)
            dismantle(&term)
            return printed.split(separator: "\n", omittingEmptySubsequences: false)
        }.value
        #expect(lines.count == 2 * depth + 1)
        #expect(lines.first == "(lam i_0")
        #expect(lines[depth] == String(repeating: " ", count: 2 * depth) + "i_1")
        #expect(lines.last == ")")
    }

    @Test func flatAndDeBruijnRoundTripDeepTerm() async throws {
        let outcome = try await Task.detached {
            let chain = DeepChain(depth: Self.depth)
            let converter = DeBruijnConverter()
            let version: (UInt, UInt, UInt) = (1, 1, 0)

            var named = chain.namedTerm()
            var deBruijn = try converter.convert(NamedProgram(version: version, term: named)).term
            dismantle(&named)

            let bytes = try FlatEncoder().encode(DeBruijnProgram(version: version, term: deBruijn))
            dismantle(&deBruijn)

            var decoded = try FlatDecoder().decode(bytes).term
            var stripped = try converter.convertFromNamed(
                NamedDeBruijnProgram(version: version, term: decoded)
            ).term
            let decodedPrint = PrettyPrinter().printCompact(decoded)
            dismantle(&decoded)

            let reencoded = try FlatEncoder().encode(DeBruijnProgram(version: version, term: stripped))
            var renamed = try converter.convertToNamed(DeBruijnProgram(version: version, term: stripped)).term
            dismantle(&stripped)
            let renamedPrint = PrettyPrinter().printCompact(renamed)
            dismantle(&renamed)

            return (
                decoded: decodedPrint == chain.expectedCompact,
                reencoded: reencoded == bytes,
                renamed: renamedPrint == chain.expectedCompact
            )
        }.value
        #expect(outcome.decoded)
        #expect(outcome.reencoded)
        #expect(outcome.renamed)
    }

    @Test func parsesDeepProgram() async throws {
        let matches = try await Task.detached {
            let chain = DeepChain(depth: Self.depth)
            let converter = DeBruijnConverter()
            let version: (UInt, UInt, UInt) = (1, 1, 0)
            var parser = UPLCParser()

            var named = try parser.parse(chain.source).term
            var deBruijn = try converter.convert(NamedProgram(version: version, term: named)).term
            dismantle(&named)
            var renamed = try converter.convertToNamed(DeBruijnProgram(version: version, term: deBruijn)).term
            dismantle(&deBruijn)
            let printed = PrettyPrinter().printCompact(renamed)
            dismantle(&renamed)
            return printed == chain.expectedCompact
        }.value
        #expect(matches)
    }

    @Test func parsesDeepDataLiteral() async throws {
        let matches = try await Task.detached {
            var prefix = [String](), suffix = [String]()
            for level in 0..<Self.depth {
                prefix.append(level.isMultiple(of: 2) ? "List [" : "Constr 1 [")
                suffix.append(level.isMultiple(of: 2) ? ", B #ab]" : "]")
            }
            let literal = prefix.reversed().joined() + "I 7" + suffix.joined()

            var parser = UPLCParser()
            var term = try parser.parse("(program 1.1.0 (con data (\(literal))))").term
            guard case .constant(.data(var data)) = term else { return false }
            term = .error
            let printed = PrettyPrinter().printPlutusData(data)
            dismantle(&data)
            return printed == literal
        }.value
        #expect(matches)
    }

    @Test func printsDeepPlutusData() async throws {
        let matches = await Task.detached {
            var data = PlutusData.bigInt(.int(7))
            var prefix = "", suffix = ""
            for level in 0..<Self.depth {
                if level.isMultiple(of: 2) {
                    data = .array([data, .bytes(.byteString(ByteString(bytes: Data([0xab]))))])
                    prefix = "List [" + prefix
                    suffix += ", B #ab]"
                } else {
                    data = .constructor(Constr(tag: 122, fields: [data]))
                    prefix = "Constr 1 [" + prefix
                    suffix += "]"
                }
            }
            let printed = PrettyPrinter().printPlutusData(data)
            dismantle(&data)
            return printed == prefix + "I 7" + suffix
        }.value
        #expect(matches)
    }
}

// MARK: — Building deep terms

/// A term nested `depth` levels deep, cycling through every compound term form
/// so each one is exercised in every child position the walks handle.
private struct DeepChain {
    let depth: Int

    /// The compact rendering, built independently of the printer: each level
    /// wraps the one inside it in a fixed prefix and suffix.
    var expectedCompact: String {
        wrap("i_1", in: Self.compactShapes)
    }

    /// The same term as UPLC source, with `x` for every variable. It writes
    /// one application in the `(f x)` form and the other in the `[f x]` form.
    var source: String {
        "(program 1.1.0 \(wrap("x", in: Self.sourceShapes)))"
    }

    private func wrap(_ leaf: String, in shapes: [(String, String)]) -> String {
        var prefix = [String](), suffix = [String]()
        for level in 0..<depth {
            let (open, close) = shapes[level % shapes.count]
            prefix.append(open)
            suffix.append(close)
        }
        return prefix.reversed().joined() + leaf + suffix.joined()
    }

    private static let compactShapes: [(String, String)] = [
        ("(lam i_0 ", ")"),
        ("(delay ", ")"),
        ("[ ", " (error) ]"),
        ("(force ", ")"),
        ("[ (builtin addInteger) ", " ]"),
        ("(constr 3 ", " (error))"),
        ("(case ", " (error) (con integer 1))"),
    ]

    private static let sourceShapes: [(String, String)] = [
        ("(lam x ", ")"),
        ("(delay ", ")"),
        ("(", " (error))"),
        ("(force ", ")"),
        ("[(builtin addInteger) ", "]"),
        ("(constr 3 ", " (error))"),
        ("(case ", " (error) (con integer 1))"),
    ]

    func namedTerm() -> Term<Name> {
        let x = Name(text: "x", unique: Unique(0))
        return build(leaf: .var(x), binder: x)
    }

    func namedDeBruijnTerm() -> Term<NamedDeBruijn> {
        build(
            leaf: .var(NamedDeBruijn(text: "i", index: DeBruijn(1))),
            binder: NamedDeBruijn(text: "i", index: DeBruijn(0))
        )
    }

    /// Level 0 is a lambda, so the leaf variable is always bound by it.
    private func build<T>(leaf: Term<T>, binder: T) -> Term<T> {
        var term = leaf
        for level in 0..<depth {
            switch level % Self.compactShapes.count {
            case 0: term = .lambda(parameterName: binder, body: term)
            case 1: term = .delay(term)
            case 2: term = .apply(function: term, argument: .error)
            case 3: term = .force(term)
            case 4: term = .apply(function: .builtin(.addInteger), argument: term)
            case 5: term = .constr(tag: 3, fields: [term, .error])
            default: term = .case(argument: term, branches: [.error, .constant(.integer(1))])
            }
        }
        return term
    }
}

// MARK: — Tearing deep values down

/// Release a deep term one node at a time, leaving `.error` in its place.
/// Dropping the last reference to it would free the nodes recursively and
/// overflow the stack on its own.
private func dismantle<T>(_ term: inout Term<T>) {
    var pending = [term]
    term = .error
    while let node = pending.popLast() {
        switch node {
        case .delay(let body), .force(let body), .lambda(_, let body):
            pending.append(body)
        case .apply(let f, let arg):
            pending.append(f)
            pending.append(arg)
        case .constr(_, let fields):
            pending.append(contentsOf: fields)
        case .case(let arg, let branches):
            pending.append(arg)
            pending.append(contentsOf: branches)
        case .var, .constant, .error, .builtin:
            break
        }
    }
}

/// Release deep PlutusData one node at a time (see `dismantle(_:)` for terms).
private func dismantle(_ data: inout PlutusData) {
    var pending = [data]
    data = .bigInt(.int(0))
    while let node = pending.popLast() {
        switch node {
        case .constructor(let c):
            pending.append(contentsOf: c.fields)
        case .array(let items):
            pending.append(contentsOf: items)
        case .indefiniteArray(let items):
            pending.append(contentsOf: items.map { $0 })
        case .map(let entries), .indefiniteMap(let entries):
            for (key, value) in entries {
                pending.append(key)
                pending.append(value)
            }
        case .bigInt, .bytes:
            break
        }
    }
}
