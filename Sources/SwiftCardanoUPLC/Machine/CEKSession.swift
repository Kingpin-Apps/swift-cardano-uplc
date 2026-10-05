/// A CEK machine run that can be stepped, stopped and stepped back: what a
/// debugger drives.
///
/// Each ``step()`` is one turn of the machine's loop, numbered as
/// ``CEKMachine/run(_:observer:)`` numbers the steps it reports, and charged
/// the same budget: a session stepped to its end finishes exactly as `run`
/// does. Stepping back restores the nearest earlier checkpoint and runs
/// forward from it, which the machine being deterministic makes exact.
public struct CEKSession: Sendable {
    /// What the machine is doing at the current step.
    public enum Phase: Sendable {
        /// Computing `term` in `environment`.
        case computing(Term<NamedDeBruijn>, Environment)
        /// Returning `value` to the stack.
        case returning(Value)
        /// The run ended with this term.
        case finished(Term<NamedDeBruijn>)
        /// The run failed.
        case failed(MachineError)
    }

    /// A place to stop a run.
    public enum Breakpoint: Sendable, Hashable {
        /// Before this step runs.
        case step(Int)
        /// When this builtin is charged.
        case builtin(DefaultFunction)
        /// When a trace message containing this text is emitted.
        case trace(String)
        /// When the run fails.
        case failure
    }

    public let program: NamedDeBruijnProgram
    /// The step about to run, counting from zero.
    public private(set) var stepIndex = 0
    /// The events of the most recent step: its builtin, its traces, and how
    /// the run ended when it did.
    public private(set) var lastEvents: [CEKEvent] = []

    private var machine: CEKMachine
    private var state: MachineState?
    private var failure: MachineError?
    private var finished = false
    private var reportedLogs = 0
    private var checkpoints: [Checkpoint] = []
    private let checkpointInterval: Int

    private struct Checkpoint: Sendable {
        let stepIndex: Int
        let machine: CEKMachine
        let state: MachineState?
        let failure: MachineError?
        let finished: Bool
        let reportedLogs: Int
    }

    /// A session at the start of `program`, before its first step.
    /// `checkpointInterval` trades memory for how far a step back replays.
    public init(_ program: NamedDeBruijnProgram, budget: ExBudget = .restricted, costModel: CostModel, checkpointInterval: Int = 1024) {
        self.program = program
        self.machine = CEKMachine(budget: budget, costModel: costModel)
        self.checkpointInterval = max(1, checkpointInterval)
        do {
            try machine.spendBudget(costModel.machineStepCosts.startup)
            state = .compute(.noFrame, Environment(), program.term)
        } catch let error as MachineError {
            failure = error
        } catch {
            failure = .typeError("\(error)")
        }
        checkpoint()
    }

    // MARK: - Where the machine is

    public var phase: Phase {
        if let failure { return .failed(failure) }
        switch state {
        case .compute(_, let env, let term)?: return .computing(term, env)
        case .returning(_, let value)?: return .returning(value)
        case .done(let term)?: return .finished(term)
        case nil: return .failed(.typeError("The session has no state."))
        }
    }

    /// The stack of work still to do, innermost first.
    public var context: Context {
        switch state {
        case .compute(let ctx, _, _)?, .returning(let ctx, _)?: return ctx
        default: return .noFrame
        }
    }

    /// How many frames are on the stack.
    public var depth: Int { context.depth }

    /// Whether the run has ended, finished or failed. A `done` state still
    /// has its final step (settling the batched budget) to run.
    public var isOver: Bool { failure != nil || finished }

    public var logs: [String] { machine.logs }
    public var consumedBudget: ExBudget { machine.consumedBudget }
    public var remainingBudget: ExBudget { machine.remainingBudget }

    /// `value` as a term, with the variables it closes over filled in: how a
    /// debugger shows a closure or a delayed term. `nil` if it does not read
    /// back (an open variable).
    public func term(of value: Value) -> Term<NamedDeBruijn>? {
        try? machine.dischargeTo(value)
    }

    // MARK: - Stepping

    /// Runs one step. Does nothing once the run is over.
    public mutating func step() {
        guard !isOver, let current = state else { return }
        var events: [CEKEvent] = []
        do {
            switch current {
            case .compute(let ctx, let env, let term):
                state = try machine.computeStep(ctx, env, term)
            case .returning(let ctx, let value):
                state = try machine.returnStep(ctx, value)
            case .done(let term):
                try machine.spendUnbudgetedSteps()
                finished = true
                events.append(.finished(term))
            }
            if let (function, cost) = machine.lastBuiltin {
                machine.lastBuiltin = nil
                events.insert(.builtin(function, cost: cost), at: 0)
            }
            appendLogs(to: &events)
        } catch {
            let machineError = error as? MachineError ?? .typeError("\(error)")
            appendLogs(to: &events)
            failure = machineError
            events.append(.failed(machineError))
        }
        lastEvents = events
        stepIndex += 1
        if stepIndex % checkpointInterval == 0, checkpoints.last?.stepIndex != stepIndex { checkpoint() }
    }

    /// Steps until `stop` holds after a step, the run is over, or `limit`
    /// steps have run. Returns whether `stop` held.
    @discardableResult
    public mutating func run(limit: Int = .max, until stop: (CEKSession) -> Bool) -> Bool {
        var count = 0
        while !isOver, count < limit {
            step()
            count += 1
            if stop(self) { return true }
        }
        return false
    }

    /// Runs to the next breakpoint, or to the end. Returns the breakpoint hit.
    @discardableResult
    public mutating func run(to breakpoints: Set<Breakpoint>, limit: Int = .max) -> Breakpoint? {
        var hit: Breakpoint?
        run(limit: limit) { session in
            hit = session.breakpointHit(breakpoints)
            return hit != nil
        }
        return hit
    }

    /// Runs until the term being computed now has returned its value: over
    /// the calls it makes.
    public mutating func stepOver() {
        let start = depth
        guard case .computing = phase else {
            step()
            return
        }
        run { session in
            if case .returning = session.phase { return session.depth <= start }
            return false
        }
    }

    /// Runs until the stack is shallower than now: out of the current frame.
    public mutating func stepOut() {
        let start = depth
        run { $0.depth < start }
    }

    /// Goes to step `target`, back or forward.
    public mutating func seek(to target: Int) {
        let target = max(0, target)
        if target < stepIndex, let checkpoint = checkpoints.last(where: { $0.stepIndex <= target }) {
            restore(checkpoint)
        }
        while stepIndex < target, !isOver { step() }
    }

    /// Goes back one step.
    public mutating func stepBack() {
        seek(to: stepIndex - 1)
    }

    // MARK: - Helpers

    private func breakpointHit(_ breakpoints: Set<Breakpoint>) -> Breakpoint? {
        if breakpoints.contains(.step(stepIndex)) { return .step(stepIndex) }
        for event in lastEvents {
            switch event {
            case .builtin(let function, _) where breakpoints.contains(.builtin(function)):
                return .builtin(function)
            case .log(let message):
                if let match = breakpoints.first(where: { if case .trace(let text) = $0 { return message.contains(text) } else { return false } }) {
                    return match
                }
            case .failed where breakpoints.contains(.failure):
                return .failure
            default:
                break
            }
        }
        return nil
    }

    private mutating func appendLogs(to events: inout [CEKEvent]) {
        while reportedLogs < machine.logs.count {
            events.append(.log(machine.logs[reportedLogs]))
            reportedLogs += 1
        }
    }

    private mutating func checkpoint() {
        checkpoints.append(Checkpoint(stepIndex: stepIndex, machine: machine, state: state, failure: failure, finished: finished, reportedLogs: reportedLogs))
    }

    private mutating func restore(_ checkpoint: Checkpoint) {
        stepIndex = checkpoint.stepIndex
        machine = checkpoint.machine
        state = checkpoint.state
        failure = checkpoint.failure
        finished = checkpoint.finished
        reportedLogs = checkpoint.reportedLogs
        lastEvents = []
    }
}

extension Context {
    /// The frame this one returns to; `nil` for the empty stack.
    public var parent: Context? {
        switch self {
        case .frameAwaitArg(_, let outer), .frameAwaitFunTerm(_, _, let outer), .frameAwaitFunValue(_, let outer),
            .frameForce(let outer), .frameConstr(_, _, _, _, let outer), .frameCases(_, _, let outer),
            .frameCaseApplyFields(_, let outer):
            return outer
        case .noFrame:
            return nil
        }
    }

    /// The frames from this one outwards, innermost first, without the empty stack.
    public var frames: [Context] {
        var found: [Context] = []
        var current: Context? = self
        while let frame = current, frame.parent != nil {
            found.append(frame)
            current = frame.parent
        }
        return found
    }

    /// How many frames there are, without the empty stack.
    public var depth: Int {
        var count = 0
        var current = parent
        while let frame = current {
            count += 1
            current = frame.parent
        }
        return count
    }
}
