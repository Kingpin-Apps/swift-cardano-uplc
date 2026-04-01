/// Continuation frames in the CEK machine evaluation context.
/// The context forms a stack of "what to do next" after the current computation finishes.
public indirect enum Context: Sendable {
    /// Waiting for an argument value; have the function value already.
    case frameAwaitArg(Value, Context)
    /// Evaluating the function; have the unevaluated argument term.
    case frameAwaitFunTerm(Environment, Term<NamedDeBruijn>, Context)
    /// Have the argument value; waiting for the function value.
    case frameAwaitFunValue(Value, Context)
    /// Forcing a delayed term.
    case frameForce(Context)
    /// Building a `constr` value: env, tag, remaining field terms, already-evaluated fields.
    case frameConstr(Environment, UInt64, [Term<NamedDeBruijn>], [Value], Context)
    /// Waiting to pattern match after evaluating the scrutinee.
    case frameCases(Environment, [Term<NamedDeBruijn>], Context)
    /// Applying constr fields to a case branch one by one.
    /// Contains remaining field values to apply and the outer context.
    case frameCaseApplyFields([Value], Context)
    /// The empty context — evaluation is complete.
    case noFrame
}
