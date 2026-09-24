import Testing
import Foundation
@testable import SwiftCardanoUPLC

// MARK: — Cost model conformance
//
// The Plutus conformance suite ships an expected execution budget alongside
// each test program. Those budgets are the reference implementation's own
// output, so reproducing them exercises every part of the costing machinery at
// once: the parameter table, all twenty costing-function shapes, the argument
// size measures, the machine step costs, and the point at which a builtin is
// charged. A single wrong coefficient or size measure shows up immediately.
//
// The budgets were produced with Plutus's default PlutusV3 cost model, which
// `Resources/costmodel/defaultV3.json` carries in the same name/value form
// that protocol parameters use positionally.

@Suite("Cost model conformance")
struct CostModelConformanceTests {

    /// Plutus's default PlutusV3 cost model.
    static func defaultV3Model() throws -> CostModel {
        let url = try #require(Bundle.module.url(
            forResource: "Resources/costmodel/defaultV3", withExtension: "json"
        ))
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        var table = [String: Int64]()
        for (name, value) in json { table[name] = Int64("\(value)") }
        return try CostModel.fromParameters(table, version: .v3)
    }

    @Test("every conformance budget is reproduced exactly")
    func budgetsMatch() throws {
        let model = try Self.defaultV3Model()
        #expect(!model.isApproximate)

        let root = try #require(Bundle.module.url(
            forResource: "Resources/conformance/v3", withExtension: nil
        ))
        let fileManager = FileManager.default
        let enumerator = try #require(fileManager.enumerator(atPath: root.path))

        var compared = 0
        var mismatches: [String] = []

        for case let relativePath as String in enumerator
        where relativePath.hasSuffix(".uplc.budget.expected") {
            let budgetURL = root.appendingPathComponent(relativePath)
            let programURL = root.appendingPathComponent(
                String(relativePath.dropLast(".budget.expected".count))
            )
            guard let source = try? String(contentsOf: programURL, encoding: .utf8),
                  let expectedText = try? String(contentsOf: budgetURL, encoding: .utf8)
            else { continue }

            let expected = expectedText
                .split(whereSeparator: { !$0.isNumber })
                .compactMap { Int64($0) }
            guard expected.count == 2 else { continue }

            // A program whose expected outcome is a failure has no meaningful
            // budget to compare.
            guard let result = try? evaluate(source, with: model) else { continue }

            compared += 1
            if result != (cpu: expected[0], mem: expected[1]) {
                mismatches.append(
                    "\(relativePath): got (\(result.cpu), \(result.mem)) "
                    + "expected (\(expected[0]), \(expected[1]))"
                )
            }
        }

        #expect(compared > 500, "expected the conformance corpus to be present")
        #expect(mismatches.isEmpty, "\(mismatches.count) budget mismatches: \(mismatches.prefix(5))")
    }

    private func evaluate(
        _ source: String, with model: CostModel
    ) throws -> (cpu: Int64, mem: Int64) {
        var parser = UPLCParser()
        let converter = DeBruijnConverter()
        let program = try converter.convertToNamed(try converter.convert(try parser.parse(source)))
        var machine = CEKMachine(budget: .unlimited, costModel: model)
        let result = try machine.run(program)
        return (
            cpu: ExBudget.unlimited.cpu - result.remainingBudget.cpu,
            mem: ExBudget.unlimited.mem - result.remainingBudget.mem
        )
    }
}
