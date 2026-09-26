/// Errors thrown during De Bruijn conversion.
public enum DeBruijnError: Error, Sendable {
    case freeVariable(String)
    case indexOutOfRange(UInt)
}

/// Converts between named programs, De Bruijn programs, and NamedDeBruijn programs.
public struct DeBruijnConverter: Sendable {
    public init() {}

    // MARK: — Named → DeBruijn

    /// Convert a named program to De Bruijn indices for flat encoding.
    public func convert(_ program: NamedProgram) throws -> DeBruijnProgram {
        let term = try convertTerm(program.term, scope: [])
        return DeBruijnProgram(version: program.version, term: term)
    }

    private func convertTerm(_ term: Term<Name>, scope: [String]) throws -> Term<DeBruijn> {
        var scope = scope
        return try mapTerm(
            term,
            binder: DeBruijn(0),
            variable: { name in
                guard let idx = scope.lastIndex(of: name.text) else {
                    throw DeBruijnError.freeVariable(name.text)
                }
                // De Bruijn index 1 = nearest enclosing lambda
                let distance = UInt(scope.count - idx)
                return DeBruijn(distance)
            },
            enterLambda: { scope.append($0.text) },
            exitLambda: { scope.removeLast() }
        )
    }

    // MARK: — NamedDeBruijn → DeBruijn

    /// Strip names from a NamedDeBruijn program to get plain DeBruijn.
    public func convertFromNamed(_ program: NamedDeBruijnProgram) throws -> DeBruijnProgram {
        return DeBruijnProgram(version: program.version,
                               term: stripNames(program.term))
    }

    private func stripNames(_ term: Term<NamedDeBruijn>) -> Term<DeBruijn> {
        mapTerm(term, binder: DeBruijn(0), variable: { $0.index })
    }

    // MARK: — DeBruijn → NamedDeBruijn

    /// Restore synthetic names to a De Bruijn program for evaluation.
    public func convertToNamed(_ program: DeBruijnProgram) throws -> NamedDeBruijnProgram {
        let term = addNames(program.term)
        return NamedDeBruijnProgram(version: program.version, term: term)
    }

    private func addNames(_ term: Term<DeBruijn>) -> Term<NamedDeBruijn> {
        // Plutus convention: lambda binders always get index 0
        mapTerm(
            term,
            binder: NamedDeBruijn(text: "i", index: DeBruijn(0)),
            variable: { NamedDeBruijn(text: "i", index: $0) }
        )
    }
}

// MARK: — Iterative term rebuilding

/// A term whose remaining children are still being converted.
private enum MapFrame<A: Sendable & Hashable, B: Sendable & Hashable> {
    case delay
    case force
    case lambda
    case applyFunction(argument: Term<A>)
    case applyArgument(function: Term<B>)
    case constr(tag: UInt64, done: [Term<B>], rest: ArraySlice<Term<A>>)
    case caseArgument(branches: [Term<A>])
    case caseBranches(argument: Term<B>, done: [Term<B>], rest: ArraySlice<Term<A>>)
}

/// Rebuild `term` with every variable mapped by `variable` and every lambda
/// binder replaced by `binder`. Children are visited left to right in pre-order
/// (the same order as a recursive walk), with `enterLambda`/`exitLambda`
/// bracketing each lambda body. Uses an explicit frame stack so deeply nested
/// programs cannot overflow the call stack.
private func mapTerm<A, B>(
    _ term: Term<A>,
    binder: B,
    variable: (A) throws -> B,
    enterLambda: (A) -> Void = { _ in },
    exitLambda: () -> Void = {}
) rethrows -> Term<B> {
    var frames: [MapFrame<A, B>] = []
    var current = term
    while true {
        var mapped: Term<B>
        switch current {
        case .var(let v):
            mapped = .var(try variable(v))
        case .delay(let body):
            frames.append(.delay)
            current = body
            continue
        case .lambda(let param, let body):
            enterLambda(param)
            frames.append(.lambda)
            current = body
            continue
        case .apply(let f, let arg):
            frames.append(.applyFunction(argument: arg))
            current = f
            continue
        case .constant(let c):
            mapped = .constant(c)
        case .force(let body):
            frames.append(.force)
            current = body
            continue
        case .error:
            mapped = .error
        case .builtin(let fn):
            mapped = .builtin(fn)
        case .constr(let tag, let fields):
            guard let first = fields.first else {
                mapped = .constr(tag: tag, fields: [])
                break
            }
            frames.append(.constr(tag: tag, done: [], rest: fields.dropFirst()))
            current = first
            continue
        case .case(let arg, let branches):
            frames.append(.caseArgument(branches: branches))
            current = arg
            continue
        }

        // `mapped` is complete: fold it into its parents until one needs another child.
        reduce: while true {
            guard let frame = frames.popLast() else { return mapped }
            switch frame {
            case .delay:
                mapped = .delay(mapped)
            case .force:
                mapped = .force(mapped)
            case .lambda:
                exitLambda()
                mapped = .lambda(parameterName: binder, body: mapped)
            case .applyFunction(let argument):
                frames.append(.applyArgument(function: mapped))
                current = argument
                break reduce
            case .applyArgument(let function):
                mapped = .apply(function: function, argument: mapped)
            case .constr(let tag, var done, let rest):
                done.append(mapped)
                if let next = rest.first {
                    frames.append(.constr(tag: tag, done: done, rest: rest.dropFirst()))
                    current = next
                    break reduce
                }
                mapped = .constr(tag: tag, fields: done)
            case .caseArgument(let branches):
                if let first = branches.first {
                    frames.append(.caseBranches(argument: mapped, done: [], rest: branches.dropFirst()))
                    current = first
                    break reduce
                }
                mapped = .case(argument: mapped, branches: [])
            case .caseBranches(let argument, var done, let rest):
                done.append(mapped)
                if let next = rest.first {
                    frames.append(.caseBranches(argument: argument, done: done, rest: rest.dropFirst()))
                    current = next
                    break reduce
                }
                mapped = .case(argument: argument, branches: done)
            }
        }
    }
}
