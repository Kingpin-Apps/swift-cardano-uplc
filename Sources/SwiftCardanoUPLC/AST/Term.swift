/// UPLC term — the core language grammar.
/// Flat term tags (4-bit): var=0, delay=1, lambda=2, apply=3,
/// constant=4, force=5, error=6, builtin=7, constr=8, case=9
public indirect enum Term<T: Sendable & Hashable>: Sendable {
    /// Variable reference.
    case `var`(T)
    /// Delays evaluation of its body (used with `force`).
    case delay(Term<T>)
    /// Lambda abstraction — binds one variable.
    case lambda(parameterName: T, body: Term<T>)
    /// Function application.
    case apply(function: Term<T>, argument: Term<T>)
    /// A literal constant value.
    case constant(UPLCConstant)
    /// Forces evaluation of a delayed term.
    case force(Term<T>)
    /// An explicit error / failure term.
    case error
    /// A reference to a built-in function.
    case builtin(DefaultFunction)
    /// A data constructor (Conway+). Tag is the constructor index.
    case constr(tag: UInt64, fields: [Term<T>])
    /// Pattern match on a constructor (Conway+).
    case `case`(argument: Term<T>, branches: [Term<T>])
}

extension Term: Equatable where T: Equatable {
    public static func == (lhs: Term<T>, rhs: Term<T>) -> Bool {
        switch (lhs, rhs) {
        case (.var(let a), .var(let b)): return a == b
        case (.delay(let a), .delay(let b)): return a == b
        case (.lambda(let n1, let b1), .lambda(let n2, let b2)): return n1 == n2 && b1 == b2
        case (.apply(let f1, let a1), .apply(let f2, let a2)): return f1 == f2 && a1 == a2
        case (.constant(let a), .constant(let b)): return a == b
        case (.force(let a), .force(let b)): return a == b
        case (.error, .error): return true
        case (.builtin(let a), .builtin(let b)): return a == b
        case (.constr(let t1, let f1), .constr(let t2, let f2)): return t1 == t2 && f1 == f2
        case (.case(let a1, let b1), .case(let a2, let b2)): return a1 == a2 && b1 == b2
        default: return false
        }
    }
}
