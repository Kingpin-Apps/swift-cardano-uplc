/// Watches a ``CEKMachine`` run, step by step.
///
/// Pass one to ``CEKMachine/run(_:observer:)`` to trace a script: to build a
/// timeline of its steps, see where its budget goes, or step through it in a
/// debugger. The observer is told about each step as it happens and cannot
/// change the run.
public protocol CEKObserver {
    /// Whether to report steps at all. A run with an observer that is not
    /// observing costs no more than one without.
    var isObserving: Bool { get }

    mutating func observe(_ step: CEKStep)
}

extension CEKObserver {
    public var isObserving: Bool { true }
}

/// An observer that observes nothing.
public struct NoCEKObserver: CEKObserver {
    public init() {}
    public var isObserving: Bool { false }
    public func observe(_ step: CEKStep) {}
}

/// An observer that keeps every step it is told about.
public struct CEKStepRecorder: CEKObserver {
    public private(set) var steps: [CEKStep] = []
    /// The most steps to keep; later steps are dropped. `nil` keeps all.
    public var limit: Int?

    public init(limit: Int? = nil) {
        self.limit = limit
    }

    public mutating func observe(_ step: CEKStep) {
        if let limit, steps.count >= limit { return }
        steps.append(step)
    }
}

/// One thing that happened while a ``CEKMachine`` ran.
public struct CEKStep: Sendable {
    /// The machine step it happened at, counting from zero. A builtin, a
    /// trace message or the end of the run shares the index of the step
    /// that caused it.
    public let index: Int
    public let event: CEKEvent
    /// The budget spent up to and including this event.
    public let consumed: ExBudget
}

/// What happened at a ``CEKStep``.
public enum CEKEvent: Sendable {
    /// The machine began computing a term.
    case compute(Term<NamedDeBruijn>)
    /// The machine returned a value to its continuation.
    case returning(Value)
    /// A builtin was saturated and charged `cost`.
    case builtin(DefaultFunction, cost: ExBudget)
    /// A `trace` builtin emitted a message.
    case log(String)
    /// The run finished with this term.
    case finished(Term<NamedDeBruijn>)
    /// The run failed.
    case failed(MachineError)
}

/// The outcome of ``CEKMachine/evaluate(_:)``: whether the script succeeded,
/// with its traces and budget either way.
public struct CEKEvaluation: Sendable {
    public let outcome: Result<Term<NamedDeBruijn>, MachineError>
    /// Every trace message emitted, up to the failure if there was one.
    public let logs: [String]
    /// The budget spent. On a failure, what was spent before it.
    public let consumedBudget: ExBudget
    /// The budget left; negative in a dimension the script ran out of.
    public let remainingBudget: ExBudget

    public var succeeded: Bool {
        if case .success = outcome { return true }
        return false
    }
}
