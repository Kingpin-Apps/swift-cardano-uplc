import Foundation
import Testing
@testable import SwiftCardanoUPLC

/// Traces and budget kept when a script fails, and the step observer.
@Suite("CEK observer and failure reporting")
struct CEKObserverTests {
    func program(_ source: String) throws -> NamedDeBruijnProgram {
        var parser = UPLCParser()
        let converter = DeBruijnConverter()
        return try converter.convertToNamed(try converter.convert(try parser.parse(source)))
    }

    /// Traces "boom", then fails.
    let traceThenFail = """
    (program 1.1.0 [(lam x (error)) [(force (builtin trace)) (con string "boom") (con unit ())]])
    """

    /// Adds two integers.
    let addition = "(program 1.1.0 [(builtin addInteger) (con integer 2) (con integer 3)])"

    @Test("A failing run keeps its traces and the budget it spent")
    func failureKeepsLogsAndBudget() throws {
        var machine = CEKMachine(budget: .restricted, costModel: .placeholder())
        #expect(throws: MachineError.evaluationFailure) {
            try machine.run(try program(traceThenFail))
        }
        #expect(machine.logs == ["boom"])
        #expect(machine.consumedBudget.cpu > 0)
        #expect(machine.consumedBudget.mem > 0)
        #expect(machine.remainingBudget.cpu == ExBudget.restricted.cpu - machine.consumedBudget.cpu)
    }

    @Test("evaluate reports a failure with its traces instead of throwing")
    func evaluateReportsFailure() throws {
        var machine = CEKMachine(budget: .restricted, costModel: .placeholder())
        let evaluation = machine.evaluate(try program(traceThenFail))
        #expect(!evaluation.succeeded)
        #expect(evaluation.logs == ["boom"])
        guard case .failure(let error) = evaluation.outcome else { return }
        #expect(error == .evaluationFailure)
    }

    @Test("A successful run's consumed budget is what it took from the budget")
    func consumedMatchesRemaining() throws {
        var machine = CEKMachine(budget: .restricted, costModel: .placeholder())
        let result = try machine.run(try program(addition))
        #expect(machine.consumedBudget.cpu == ExBudget.restricted.cpu - result.remainingBudget.cpu)
        #expect(machine.consumedBudget.mem == ExBudget.restricted.mem - result.remainingBudget.mem)
        #expect(machine.remainingBudget == result.remainingBudget)
    }

    @Test("Running out of budget reports how far over the run went")
    func outOfBudget() throws {
        let tight = ExBudget(cpu: 1_000, mem: 1_000)
        var machine = CEKMachine(budget: tight, costModel: .placeholder())
        let evaluation = machine.evaluate(try program(addition))
        guard case .failure(.outOfExBudget) = evaluation.outcome else {
            Issue.record("expected out of budget, got \(evaluation.outcome)")
            return
        }
        #expect(evaluation.consumedBudget.cpu > tight.cpu || evaluation.consumedBudget.mem > tight.mem)
        #expect(evaluation.remainingBudget.cpu < 0 || evaluation.remainingBudget.mem < 0)
    }

    @Test("The observer sees every step, builtin, trace and the failure")
    func observerSeesTheRun() throws {
        var machine = CEKMachine(budget: .restricted, costModel: .placeholder())
        var recorder = CEKStepRecorder()
        #expect(throws: MachineError.self) {
            try machine.run(try program(traceThenFail), observer: &recorder)
        }
        let steps = recorder.steps
        guard case .compute? = steps.first?.event else {
            Issue.record("first event is not a compute step")
            return
        }
        #expect(steps.contains { if case .builtin(.trace, _) = $0.event { true } else { false } })
        #expect(steps.contains { if case .log("boom") = $0.event { true } else { false } })
        guard case .failed(.evaluationFailure)? = steps.last?.event else {
            Issue.record("last event is not the failure")
            return
        }
        #expect(steps.last?.consumed == machine.consumedBudget)
        // Steps are reported in order, and the budget only grows.
        #expect(zip(steps, steps.dropFirst()).allSatisfy { $0.index <= $1.index })
        #expect(zip(steps, steps.dropFirst()).allSatisfy { $0.consumed.cpu <= $1.consumed.cpu })
    }

    @Test("Observing does not change the outcome or the budget")
    func observingChangesNothing() throws {
        var plain = CEKMachine(budget: .restricted, costModel: .placeholder())
        let expected = try plain.run(try program(addition))

        var observed = CEKMachine(budget: .restricted, costModel: .placeholder())
        var recorder = CEKStepRecorder()
        let result = try observed.run(try program(addition), observer: &recorder)
        #expect(result.term == expected.term)
        #expect(result.remainingBudget == expected.remainingBudget)
        guard case .finished? = recorder.steps.last?.event else {
            Issue.record("last event is not the end of the run")
            return
        }
        #expect(recorder.steps.last?.consumed == plain.consumedBudget)
    }

    @Test("A recorder with a limit keeps only the first steps")
    func recorderLimit() throws {
        var machine = CEKMachine(budget: .restricted, costModel: .placeholder())
        var recorder = CEKStepRecorder(limit: 3)
        _ = try machine.run(try program(addition), observer: &recorder)
        #expect(recorder.steps.count == 3)
    }
}
