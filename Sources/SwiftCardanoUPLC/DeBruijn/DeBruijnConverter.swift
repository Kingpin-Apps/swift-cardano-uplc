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
        switch term {
        case .var(let name):
            guard let idx = scope.lastIndex(of: name.text) else {
                throw DeBruijnError.freeVariable(name.text)
            }
            // De Bruijn index 1 = nearest enclosing lambda
            let distance = UInt(scope.count - idx)
            return .var(DeBruijn(distance))
        case .delay(let body):
            return .delay(try convertTerm(body, scope: scope))
        case .lambda(let param, let body):
            let newScope = scope + [param.text]
            return .lambda(parameterName: DeBruijn(0), body: try convertTerm(body, scope: newScope))
        case .apply(let f, let arg):
            return .apply(function: try convertTerm(f, scope: scope),
                          argument: try convertTerm(arg, scope: scope))
        case .constant(let c):
            return .constant(c)
        case .force(let body):
            return .force(try convertTerm(body, scope: scope))
        case .error:
            return .error
        case .builtin(let fn):
            return .builtin(fn)
        case .constr(let tag, let fields):
            return .constr(tag: tag, fields: try fields.map { try convertTerm($0, scope: scope) })
        case .case(let arg, let branches):
            return .case(argument: try convertTerm(arg, scope: scope),
                         branches: try branches.map { try convertTerm($0, scope: scope) })
        }
    }

    // MARK: — NamedDeBruijn → DeBruijn

    /// Strip names from a NamedDeBruijn program to get plain DeBruijn.
    public func convertFromNamed(_ program: NamedDeBruijnProgram) throws -> DeBruijnProgram {
        return DeBruijnProgram(version: program.version,
                               term: stripNames(program.term))
    }

    private func stripNames(_ term: Term<NamedDeBruijn>) -> Term<DeBruijn> {
        switch term {
        case .var(let ndb):      return .var(ndb.index)
        case .delay(let body):   return .delay(stripNames(body))
        case .lambda(_, let body): return .lambda(parameterName: DeBruijn(0), body: stripNames(body))
        case .apply(let f, let a): return .apply(function: stripNames(f), argument: stripNames(a))
        case .constant(let c):   return .constant(c)
        case .force(let body):   return .force(stripNames(body))
        case .error:             return .error
        case .builtin(let fn):   return .builtin(fn)
        case .constr(let t, let fs): return .constr(tag: t, fields: fs.map(stripNames))
        case .case(let a, let bs):   return .case(argument: stripNames(a), branches: bs.map(stripNames))
        }
    }

    // MARK: — DeBruijn → NamedDeBruijn

    /// Restore synthetic names to a De Bruijn program for evaluation.
    public func convertToNamed(_ program: DeBruijnProgram) throws -> NamedDeBruijnProgram {
        let term = addNames(program.term, depth: 0)
        return NamedDeBruijnProgram(version: program.version, term: term)
    }

    private func addNames(_ term: Term<DeBruijn>, depth: UInt) -> Term<NamedDeBruijn> {
        switch term {
        case .var(let idx):
            return .var(NamedDeBruijn(text: "i", index: idx))
        case .delay(let body):
            return .delay(addNames(body, depth: depth))
        case .lambda(_, let body):
            // Plutus convention: lambda binders always get index 0
            let binder = NamedDeBruijn(text: "i", index: DeBruijn(0))
            return .lambda(parameterName: binder, body: addNames(body, depth: depth + 1))
        case .apply(let f, let a):
            return .apply(function: addNames(f, depth: depth), argument: addNames(a, depth: depth))
        case .constant(let c):
            return .constant(c)
        case .force(let body):
            return .force(addNames(body, depth: depth))
        case .error:
            return .error
        case .builtin(let fn):
            return .builtin(fn)
        case .constr(let t, let fs):
            return .constr(tag: t, fields: fs.map { addNames($0, depth: depth) })
        case .case(let a, let bs):
            return .case(argument: addNames(a, depth: depth), branches: bs.map { addNames($0, depth: depth) })
        }
    }
}
