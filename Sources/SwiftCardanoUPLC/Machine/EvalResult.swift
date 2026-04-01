/// The result of evaluating a UPLC program.
public struct EvalResult: Sendable {
    /// The final term produced (should be a value, not a reducible expression).
    public let term: Term<NamedDeBruijn>
    /// Remaining budget after evaluation.
    public let remainingBudget: ExBudget
    /// Trace log entries emitted by `trace` builtins.
    public let logs: [String]

    public init(term: Term<NamedDeBruijn>, remainingBudget: ExBudget, logs: [String]) {
        self.term = term
        self.remainingBudget = remainingBudget
        self.logs = logs
    }
}
