import Foundation
import Testing

@testable import SwiftCardanoUPLC

/// A stepped session must be the machine's own run, step for step: the same
/// result, budget, traces and events, at the same step numbers.
@Suite("CEK session")
struct CEKSessionTests {
    static func program(_ code: String) throws -> NamedDeBruijnProgram {
        var parser = UPLCParser()
        let converter = DeBruijnConverter()
        return try converter.convertToNamed(try converter.convert(try parser.parse(code)))
    }

    /// The reportable events of a run, with their step numbers, as text.
    static func describe(_ index: Int, _ event: CEKEvent) -> String? {
        switch event {
        case .builtin(let function, let cost): "\(index) builtin \(function) \(cost.cpu)/\(cost.mem)"
        case .log(let message): "\(index) log \(message)"
        case .finished(let term): "\(index) finished \(PrettyPrinter().printCompact(term))"
        case .failed(let error): "\(index) failed \(error)"
        case .compute, .returning: nil
        }
    }

    struct Outcome: Equatable {
        var events: [String]
        var logs: [String]
        var consumed: String
        var steps: Int
    }

    static func viaRun(_ program: NamedDeBruijnProgram, budget: ExBudget) -> Outcome {
        var machine = CEKMachine(budget: budget, costModel: .placeholder())
        var recorder = CEKStepRecorder()
        _ = try? machine.run(program, observer: &recorder)
        let reported = recorder.steps.compactMap { describe($0.index, $0.event) }
        let lastStep = recorder.steps.last.map(\.index) ?? 0
        return Outcome(
            events: reported, logs: machine.logs,
            consumed: "\(machine.consumedBudget.cpu)/\(machine.consumedBudget.mem)", steps: lastStep
        )
    }

    static func viaSession(_ program: NamedDeBruijnProgram, budget: ExBudget, checkpointInterval: Int = 1024) -> Outcome {
        var session = CEKSession(program, budget: budget, costModel: .placeholder(), checkpointInterval: checkpointInterval)
        var reported: [String] = []
        var lastStep = 0
        // A failure before the first step (the startup charge) is reported at step 0.
        if case .failed(let error) = session.phase, session.stepIndex == 0 {
            reported.append("0 failed \(error)")
        }
        while !session.isOver {
            let index = session.stepIndex
            session.step()
            lastStep = index
            reported += session.lastEvents.compactMap { describe(index, $0) }
        }
        return Outcome(
            events: reported, logs: session.logs,
            consumed: "\(session.consumedBudget.cpu)/\(session.consumedBudget.mem)", steps: lastStep
        )
    }

    static func conformancePrograms() -> [(String, NamedDeBruijnProgram)] {
        guard let base = Bundle.module.url(forResource: "Resources/conformance", withExtension: nil),
            let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil)
        else { return [] }
        var found: [(String, NamedDeBruijnProgram)] = []
        for case let url as URL in walker where url.pathExtension == "uplc" && !url.lastPathComponent.contains(".expected") {
            guard let code = try? String(contentsOf: url, encoding: .utf8), let parsed = try? program(code) else { continue }
            found.append((url.path.replacingOccurrences(of: base.path, with: ""), parsed))
        }
        return found
    }

    @Test("Every conformance program steps exactly as it runs")
    func conformance() {
        let programs = Self.conformancePrograms()
        // The suite's programs that parse; the rest are parse-error cases.
        #expect(programs.count > 950)
        var mismatches: [String] = []
        for (name, program) in programs {
            if Self.viaRun(program, budget: .unlimited) != Self.viaSession(program, budget: .unlimited) { mismatches.append(name) }
        }
        #expect(mismatches.isEmpty, "\(mismatches.count) differ, e.g. \(mismatches.prefix(5))")
    }

    @Test("Running out of budget part way stops at the same step, with the same spend")
    func budget() {
        var mismatches: [String] = []
        for (name, program) in Self.conformancePrograms() {
            for budget in [ExBudget(cpu: 40_000, mem: 400), ExBudget(cpu: 1_000_000, mem: 2_000)] {
                if Self.viaRun(program, budget: budget) != Self.viaSession(program, budget: budget, checkpointInterval: 3) {
                    mismatches.append(name)
                }
            }
        }
        #expect(mismatches.isEmpty, "\(mismatches.count) differ, e.g. \(mismatches.prefix(5))")
    }

    /// A program that loops a while and traces: (fix-free) repeated addition.
    static let busy = """
    (program 1.0.0
      [(lam f [f [f [f [f (con integer 1)]]]])
       (lam x [(force (builtin trace)) (con string "step") [(builtin addInteger) x x]])])
    """

    @Test("Stepping back lands on the same state the run passed through")
    func back() throws {
        let program = try Self.program(Self.busy)
        var session = CEKSession(program, budget: .unlimited, costModel: .placeholder(), checkpointInterval: 5)
        var seen: [(Int, String, Int, [String])] = []
        while !session.isOver {
            seen.append((session.stepIndex, "\(session.consumedBudget.cpu)", session.depth, session.logs))
            session.step()
        }
        let end = session.stepIndex
        #expect(session.logs == ["step", "step", "step", "step"])
        for (index, consumed, depth, logs) in seen.reversed() {
            session.seek(to: index)
            #expect(session.stepIndex == index)
            #expect("\(session.consumedBudget.cpu)" == consumed, "budget at step \(index)")
            #expect(session.depth == depth, "depth at step \(index)")
            #expect(session.logs == logs, "logs at step \(index)")
        }
        session.seek(to: end)
        #expect(session.isOver)
        session.stepBack()
        #expect(session.stepIndex == end - 1 && !session.isOver)
    }

    @Test("Step over returns at the same depth; step out leaves the frame")
    func overAndOut() throws {
        let program = try Self.program(Self.busy)
        var session = CEKSession(program, budget: .unlimited, costModel: .placeholder())
        // Into the body: computing [f [f ...]] somewhere below the top.
        session.run { $0.depth >= 2 && { if case .computing = $0.phase { true } else { false } }($0) }
        let depth = session.depth
        session.stepOver()
        guard case .returning = session.phase else {
            Issue.record("Step over did not end on a returned value: \(session.phase)")
            return
        }
        #expect(session.depth <= depth)

        session.run { $0.depth >= 3 }
        let deeper = session.depth
        session.stepOut()
        #expect(session.depth < deeper)
    }

    @Test("Breakpoints stop on a builtin, a trace, a step and a failure")
    func breakpoints() throws {
        var session = CEKSession(try Self.program(Self.busy), budget: .unlimited, costModel: .placeholder())
        #expect(session.run(to: [.builtin(.addInteger)]) == .builtin(.addInteger))
        #expect(session.lastEvents.contains { if case .builtin(.addInteger, _) = $0 { true } else { false } })
        #expect(session.run(to: [.trace("step")]) == .trace("step"))
        let at = session.stepIndex + 7
        #expect(session.run(to: [.step(at)]) == .step(at))
        #expect(session.stepIndex == at)
        #expect(session.run(to: [.failure]) == nil)
        #expect(session.isOver)

        var failing = CEKSession(
            try Self.program("(program 1.0.0 [(lam x (error)) (con integer 1)])"), budget: .unlimited, costModel: .placeholder()
        )
        #expect(failing.run(to: [.failure]) == .failure)
        guard case .failed = failing.phase else {
            Issue.record("\(failing.phase)")
            return
        }
    }

    @Test("The environment and the stack can be read at any step")
    func state() throws {
        var session = CEKSession(try Self.program(Self.busy), budget: .unlimited, costModel: .placeholder())
        session.run { session in
            if case .computing(_, let env) = session.phase { return !env.values.isEmpty }
            return false
        }
        guard case .computing(_, let env) = session.phase else {
            Issue.record("\(session.phase)")
            return
        }
        #expect(!env.values.isEmpty)
        #expect(session.context.frames.count == session.depth)
        // The closure bound to f reads back as a lambda with no open variables.
        let closure = try #require(env.values.first { if case .lambda = $0 { true } else { false } })
        let term = try #require(session.term(of: closure))
        #expect(PrettyPrinter().printCompact(term).contains("addInteger"))
    }
}
