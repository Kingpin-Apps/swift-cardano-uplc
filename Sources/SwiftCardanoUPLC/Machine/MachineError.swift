/// Errors that can occur during CEK machine evaluation.
public enum MachineError: Error, Sendable, Equatable {
    /// Explicit `error` term was evaluated.
    case evaluationFailure
    /// Execution budget exceeded.
    case outOfExBudget(ExBudget)
    /// Variable not bound in environment (open term evaluated).
    case openTermEvaluated(DeBruijn)
    /// Applied a value that is not a function.
    case nonFunctionalApplication(String)
    /// Constr tag has no matching case branch.
    case missingCaseBranch(UInt64)
    /// A builtin expected a term argument but received a value.
    case builtinTermArgumentExpected
    /// Too many arguments supplied to a builtin.
    case unexpectedBuiltinTermArgument
    /// Type mismatch in a builtin.
    case typeError(String)
    /// Arithmetic overflow (e.g., byte-string integer conversion).
    case integerOverflow
    /// Integer-to-bytestring output length exceeds maximum.
    case integerToByteStringTooLong
    /// Builtin received wrong number of force applications.
    case forcingNonDelay
}
